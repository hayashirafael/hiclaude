import Foundation

/// Decide QUANDO disparar. Não conhece o Claude — apenas chama `onFire`.
/// O timer real só é exercitado no app (smoke test); a lógica de catch-up,
/// dedupe e pausa é testada com relógio injetado.
final class SchedulerEngine {
    var onFire: ((Int) -> Void)?   // minutos do horário que disparou
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

    var nextFire: (date: Date, minutes: Int)? {
        paused ? nil : ScheduleMath.nextFire(times: times, after: clock.now, calendar: calendar)
    }

    var nextFireDate: Date? { nextFire?.date }

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
        let missed = paused ? nil
            : ScheduleMath.lastMissedMinutes(times: times, between: lastCheck, and: now, calendar: calendar)
        lastCheck = now
        if let missed { fire(minutes: missed) }
    }

    private func fire(minutes: Int) {
        let now = clock.now
        if let last = lastFireAt, now.timeIntervalSince(last) < dedupeInterval { return }
        lastFireAt = now
        lastCheck = now
        onFire?(minutes)
    }

    private func rearm() {
        timer?.invalidate()
        timer = nil
        guard let next = nextFire else { return }
        let t = Timer(fire: next.date, interval: 0, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.lastCheck = self.clock.now
            self.fire(minutes: next.minutes)
            self.rearm()
        }
        t.tolerance = 60 // deixa o macOS agrupar wakeups (bateria)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
