import Foundation

/// Encadeia janelas de 5h por conta: ao fim da janela corrente de cada conta
/// marcada, dispara `onRenew` e re-arma para a próxima. Sem janela ativa fica
/// aguardando — `rearmAll` é chamado após cada disparo e no tick de status, e
/// arma assim que uma janela aparecer. Timers reais só no app; o catch-up é
/// testado com relógio e detector fakes (mesmo padrão do SchedulerEngine).
@MainActor
final class RenewalEngine {
    /// Retorna `true` quando o disparo de fato executou (ver
    /// `FireController.fire`) e `false` quando foi descartado pelo guard
    /// `isRunning` do controller — nesse caso a renovação não conta como
    /// feita e `rearm` tenta de novo (ver `pendingRetry`).
    var onRenew: ((URL) async -> Bool)?
    /// Snapshot de `nextRenewal` a cada mudança — vira "↻ Renova às HH:mm" na UI.
    var onStatus: (([URL: Date]) -> Void)?

    private(set) var nextRenewal: [URL: Date] = [:] {
        didSet { onStatus?(nextRenewal) }
    }

    private let detector: SessionDetecting
    private let clock: Clock
    private let dedupeInterval: TimeInterval = 120
    private var accounts: [URL] = []
    private var paused = false
    private var timers: [URL: Timer] = [:]
    private var lastRenewAt: [URL: Date] = [:]
    /// Contas cuja última tentativa de renovação foi descartada pelo guard
    /// `isRunning` do FireController — `rearm` tenta de novo na próxima
    /// chamada (statusTick a cada 60s, wake, ou o rearmAll de outro fire).
    private var pendingRetry: Set<URL> = []

    init(detector: SessionDetecting, clock: Clock = SystemClock()) {
        self.detector = detector
        self.clock = clock
    }

    func configure(accounts: [URL], paused: Bool) async {
        self.accounts = accounts.map(\.standardizedFileURL)
        self.paused = paused
        // Desarma contas desmarcadas (ou tudo, quando pausado).
        for account in Array(timers.keys) where paused || !self.accounts.contains(account) {
            timers[account]?.invalidate()
            timers[account] = nil
        }
        if paused {
            nextRenewal = [:]
            pendingRetry.removeAll()
        } else {
            for account in Array(nextRenewal.keys) where !self.accounts.contains(account) {
                nextRenewal[account] = nil
            }
            pendingRetry = pendingRetry.filter { self.accounts.contains($0) }
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
        // Tentativa anterior descartada pelo isRunning do controller → tenta
        // de novo agora, sem depender de detectar uma janela nova (não há:
        // a renovação que abriria a janela é justamente o que falhou).
        if pendingRetry.contains(account) {
            pendingRetry.remove(account)
            await renew(account)
            return
        }
        // Já armado para o futuro → nada a fazer (evita re-varrer transcripts
        // a cada tick de status).
        if let armed = nextRenewal[account], armed > clock.now, timers[account] != nil { return }
        let projects = account.appendingPathComponent("projects")
        guard let end = await detector.activeWindowEnd(projectsDir: projects) else {
            // Janela venceu desde o último arm (ex: durante o sleep) → catch-up.
            let missed = nextRenewal[account].map { $0 <= clock.now } ?? false
            timers[account]?.invalidate()
            timers[account] = nil
            nextRenewal[account] = nil
            if missed { await renew(account) }
            return
        }
        nextRenewal[account] = end
        timers[account]?.invalidate()
        let t = Timer(fire: end.addingTimeInterval(1), interval: 0, repeats: false) { [weak self] _ in
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
        guard !paused, accounts.contains(account) else {
            pendingRetry.remove(account)
            return
        }
        let now = clock.now
        // Dedupe: timer + wake podem coincidir logo após o fim da janela.
        if let last = lastRenewAt[account], now.timeIntervalSince(last) < dedupeInterval { return }
        nextRenewal[account] = nil
        let didRun = await onRenew?(account) ?? true
        guard didRun else {
            // O disparo foi descartado pelo guard isRunning do FireController
            // (outro fire, de qualquer origem, em andamento) — não marca como
            // renovado (lastRenewAt fica intacto) para não travar a conta
            // permanentemente. `rearm` tenta de novo na próxima chamada.
            pendingRetry.insert(account)
            return
        }
        pendingRetry.remove(account)
        lastRenewAt[account] = now
        await rearm(account) // encadeia a janela recém-aberta
    }
}
