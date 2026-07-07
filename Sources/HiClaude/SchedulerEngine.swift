import Foundation

/// Decide QUANDO disparar. Não conhece o Claude — apenas chama `onFire`.
/// O timer real só é exercitado no app (smoke test); a lógica de catch-up,
/// dedupe e pausa é testada com relógio injetado.
final class SchedulerEngine {
    var onFire: (() -> Void)?
    private(set) var lastCheck: Date
    private(set) var lastFireAt: Date?

    private let clock: Clock
    private let calendar: Calendar
    private let dedupeInterval: TimeInterval = 120
    private var times: [Int] = []
    private var paused = false
    private var timer: Timer?

    init(clock: Clock = SystemClock(), calendar: Calendar = .current, lastCheck: Date? = nil) {
        self.clock = clock
        self.calendar = calendar
        self.lastCheck = lastCheck ?? clock.now
    }

    var nextFireDate: Date? {
        paused ? nil : ScheduleMath.nextFireDate(times: times, after: clock.now, calendar: calendar)
    }

    func configure(times: [Int], paused: Bool) {
        self.times = times
        self.paused = paused
        rearm()
    }

    /// Chamar ao abrir o app, ao acordar do sleep e quando o relógio do sistema mudar.
    func handleWake() {
        catchUp()
        rearm()
    }

    private func catchUp() {
        let now = clock.now
        let hadMissed = !paused
            && ScheduleMath.hasMissedTime(times: times, between: lastCheck, and: now, calendar: calendar)
        lastCheck = now
        if hadMissed { fire() }
    }

    private func fire() {
        let now = clock.now
        if let last = lastFireAt, now.timeIntervalSince(last) < dedupeInterval { return }
        lastFireAt = now
        lastCheck = now
        onFire?()
    }

    private func rearm() {
        timer?.invalidate()
        timer = nil
        guard let next = nextFireDate else { return }
        let t = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.lastCheck = self.clock.now
            self.fire()
            self.rearm()
        }
        t.tolerance = 60 // deixa o macOS agrupar wakeups (bateria)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
