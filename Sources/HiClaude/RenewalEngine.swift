import Foundation

/// Encadeia janelas de 5h por conta: arma no fim da janela detectada e re-arma
/// após cada disparo. Alimentado pelos agendamentos contínuos. Timers reais só
/// no app; o catch-up é testado com relógio e detector fakes.
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

    private let detector: SessionDetecting
    private let clock: Clock
    private let dedupeInterval: TimeInterval = 120
    private var accounts: Set<URL> = []
    private var paused = false
    private var timers: [URL: Timer] = [:]
    private var lastRenewAt: [URL: Date] = [:]
    /// Contas cuja última tentativa colidiu com o guard isRunning — `rearm`
    /// tenta de novo na próxima chamada (statusTick, wake, outro fire).
    private var pendingRetry: Set<URL> = []

    init(detector: SessionDetecting, clock: Clock = SystemClock()) {
        self.detector = detector
        self.clock = clock
    }

    func configure(accounts: Set<URL>, paused: Bool) async {
        let normalized = Set(accounts.map { $0.standardizedFileURL })
        self.accounts = normalized
        self.paused = paused
        for account in Array(timers.keys) where paused || !normalized.contains(account) {
            timers[account]?.invalidate()
            timers[account] = nil
        }
        if paused {
            nextRenewal = [:]
            pendingRetry.removeAll()
        } else {
            for account in Array(nextRenewal.keys) where !normalized.contains(account) {
                nextRenewal[account] = nil
            }
            pendingRetry = pendingRetry.filter { normalized.contains($0) }
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
        guard let end = await detector.activeWindowEnd(account: account) else {
            let missed = nextRenewal[account].map { $0 <= clock.now } ?? false
            timers[account]?.invalidate(); timers[account] = nil
            nextRenewal[account] = nil
            if missed { await renew(account) }
            return
        }
        armTimer(account, at: end)
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
        guard !paused, accounts.contains(account) else {
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
