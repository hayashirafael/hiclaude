import Foundation

/// Encadeia janelas de 5h por conta conforme o modo de renovação de cada uma.
/// Automática: arma no fim da janela detectada e encadeia. Programada: arma no
/// próximo disparo do ciclo ancorado (ver ScheduleMath), com gap noturno.
/// Timers reais só no app; o catch-up é testado com relógio e detector fakes.
@MainActor
final class RenewalEngine {
    /// Retorna `true` quando o disparo executou e `false` quando foi descartado
    /// pelo guard `isRunning` do controller — nesse caso `rearm` tenta de novo.
    var onRenew: ((URL) async -> Bool)?
    /// Snapshot de `nextRenewal` a cada mudança — vira "renova às HH:mm" na UI.
    var onStatus: (([URL: Date]) -> Void)?

    private(set) var nextRenewal: [URL: Date] = [:] {
        didSet { onStatus?(nextRenewal) }
    }

    static let defaultAnchorMinutes = 9 * 60

    private let detector: SessionDetecting
    private let clock: Clock
    private let calendar: Calendar
    private let dedupeInterval: TimeInterval = 120
    private var configs: [URL: AccountRenewal] = [:]
    private var paused = false
    private var timers: [URL: Timer] = [:]
    private var lastRenewAt: [URL: Date] = [:]
    /// Contas cuja última tentativa colidiu com o guard isRunning — `rearm`
    /// tenta de novo na próxima chamada (statusTick, wake, outro fire).
    private var pendingRetry: Set<URL> = []

    init(detector: SessionDetecting, clock: Clock = SystemClock(),
         calendar: Calendar = .current) {
        self.detector = detector
        self.clock = clock
        self.calendar = calendar
    }

    private var accounts: [URL] { Array(configs.keys) }

    func configure(renewals: [URL: AccountRenewal], paused: Bool) async {
        var normalized: [URL: AccountRenewal] = [:]
        for (url, config) in renewals { normalized[url.standardizedFileURL] = config }
        self.configs = normalized
        self.paused = paused
        for account in Array(timers.keys) where paused || configs[account] == nil {
            timers[account]?.invalidate()
            timers[account] = nil
        }
        if paused {
            nextRenewal = [:]
            pendingRetry.removeAll()
        } else {
            for account in Array(nextRenewal.keys) where configs[account] == nil {
                nextRenewal[account] = nil
            }
            pendingRetry = pendingRetry.filter { configs[$0] != nil }
        }
        await rearmAll()
    }

    /// Chamar ao acordar do sleep — e após cada disparo (a janela pode ter mudado).
    func handleWake() async { await rearmAll() }

    func rearmAll() async {
        guard !paused else { return }
        for account in accounts { await rearm(account) }
    }

    private func rearm(_ account: URL) async {
        if pendingRetry.contains(account) {
            pendingRetry.remove(account)
            await renew(account)
            return
        }
        if let armed = nextRenewal[account], armed > clock.now, timers[account] != nil { return }
        switch configs[account]?.mode ?? .automatic {
        case .automatic: await rearmAutomatic(account)
        case .scheduled: await rearmScheduled(account)
        }
    }

    private func rearmAutomatic(_ account: URL) async {
        guard let end = await detector.activeWindowEnd(account: account) else {
            let missed = nextRenewal[account].map { $0 <= clock.now } ?? false
            timers[account]?.invalidate(); timers[account] = nil
            nextRenewal[account] = nil
            if missed { await renew(account) }
            return
        }
        armTimer(account, at: end)
    }

    private func rearmScheduled(_ account: URL) async {
        let anchor = configs[account]?.anchorMinutes ?? Self.defaultAnchorMinutes
        // Uma janela ativa detectada (sessão real em andamento) sempre prevalece
        // sobre qualquer catch-up de disparo agendado — checagem única, usada
        // pelos dois ramos abaixo (mesmo critério do modo Automático).
        let activeEnd = await detector.activeWindowEnd(account: account)
        // Disparo armado passou? Catch-up só se ainda dentro da janela pretendida
        // e não houver janela ativa cobrindo a conta agora.
        if let armed = nextRenewal[account], armed <= clock.now {
            timers[account]?.invalidate(); timers[account] = nil
            nextRenewal[account] = nil
            if activeEnd == nil, armed.addingTimeInterval(ScheduleMath.renewalWindow) > clock.now {
                await renew(account); return
            }
        }
        // Sem armado: catch-up de um disparo perdido cuja janela ainda cobre agora.
        if nextRenewal[account] == nil, activeEnd == nil,
           ScheduleMath.missedScheduledRenewal(
                anchorMinutes: anchor,
                between: (lastRenewAt[account] ?? clock.now.addingTimeInterval(-ScheduleMath.renewalWindow)),
                and: clock.now, calendar: calendar) != nil {
            await renew(account); return
        }
        guard let next = ScheduleMath.nextScheduledRenewal(
            anchorMinutes: anchor, after: clock.now, calendar: calendar) else { return }
        armTimer(account, at: next)
    }

    private func armTimer(_ account: URL, at date: Date) {
        nextRenewal[account] = date
        timers[account]?.invalidate()
        let t = Timer(fire: date.addingTimeInterval(1), interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.timers[account] = nil
                await self.renew(account)
            }
        }
        t.tolerance = 30
        RunLoop.main.add(t, forMode: .common)
        timers[account] = t
    }

    private func renew(_ account: URL) async {
        guard !paused, configs[account] != nil else {
            pendingRetry.remove(account)
            return
        }
        let now = clock.now
        if let last = lastRenewAt[account], now.timeIntervalSince(last) < dedupeInterval { return }
        nextRenewal[account] = nil
        let didRun = await onRenew?(account) ?? true
        guard didRun else {
            pendingRetry.insert(account)
            return
        }
        pendingRetry.remove(account)
        lastRenewAt[account] = now
        await rearm(account) // encadeia
    }
}
