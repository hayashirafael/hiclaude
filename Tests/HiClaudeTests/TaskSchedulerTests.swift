import XCTest
@testable import HiClaude

@MainActor
final class TaskSchedulerTests: XCTestCase {
    // FakeClock mutável, no padrão dos testes existentes (FireControllerTests).
    private final class MutableClock: Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return c
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private func task(times: [Int], weekdays: Set<Int> = Set(1...7),
                      enabled: Bool = true) -> ScheduledTask {
        ScheduledTask(uid: UUID(), name: nil, commandUID: nil,
                      times: times, weekdays: weekdays, enabled: enabled)
    }

    func testConfigureArmaProximaOcorrenciaSemDispararNoLaunch() async {
        let clock = MutableClock(date(2026, 7, 9, 7, 0))
        let scheduler = TaskScheduler(clock: clock, calendar: cal)
        var fired: [UUID] = []
        scheduler.onFire = { fired.append($0.uid); return true }
        let t = task(times: [480]) // 08:00
        await scheduler.configure(tasks: [t], paused: false)
        XCTAssertEqual(scheduler.nextFires[t.uid], date(2026, 7, 9, 8, 0))
        XCTAssertTrue(fired.isEmpty) // launch não dispara retroativo
    }

    func testWakeAposHorarioPerdidoDispara() async {
        let clock = MutableClock(date(2026, 7, 9, 7, 0))
        let scheduler = TaskScheduler(clock: clock, calendar: cal)
        var fired: [UUID] = []
        scheduler.onFire = { fired.append($0.uid); return true }
        let t = task(times: [480])
        await scheduler.configure(tasks: [t], paused: false)
        clock.now = date(2026, 7, 9, 9, 0) // dormiu através das 08:00
        await scheduler.handleWake()
        XCTAssertEqual(fired, [t.uid])
        // encadeia: próxima é amanhã 08:00
        XCTAssertEqual(scheduler.nextFires[t.uid], date(2026, 7, 10, 8, 0))
    }

    func testDedupeNaoDisparaDuasVezesEmSeguida() async {
        let clock = MutableClock(date(2026, 7, 9, 7, 0))
        let scheduler = TaskScheduler(clock: clock, calendar: cal)
        var count = 0
        scheduler.onFire = { _ in count += 1; return true }
        let t = task(times: [480])
        await scheduler.configure(tasks: [t], paused: false)
        clock.now = date(2026, 7, 9, 8, 1)
        await scheduler.handleWake()
        await scheduler.handleWake() // segundo wake 0s depois → dedupe
        XCTAssertEqual(count, 1)
    }

    func testPausaLimpaTimersEStatus() async {
        let clock = MutableClock(date(2026, 7, 9, 7, 0))
        let scheduler = TaskScheduler(clock: clock, calendar: cal)
        let t = task(times: [480])
        await scheduler.configure(tasks: [t], paused: false)
        await scheduler.configure(tasks: [t], paused: true)
        XCTAssertTrue(scheduler.nextFires.isEmpty)
    }

    func testTarefaDesabilitadaNaoArma() async {
        let clock = MutableClock(date(2026, 7, 9, 7, 0))
        let scheduler = TaskScheduler(clock: clock, calendar: cal)
        let t = task(times: [480], enabled: false)
        await scheduler.configure(tasks: [t], paused: false)
        XCTAssertNil(scheduler.nextFires[t.uid])
    }

    func testFireDescartadoPeloGuardEntraEmRetry() async {
        let clock = MutableClock(date(2026, 7, 9, 7, 0))
        let scheduler = TaskScheduler(clock: clock, calendar: cal)
        var results: [Bool] = [false, true] // 1ª tentativa descartada, 2ª executa
        var count = 0
        scheduler.onFire = { _ in count += 1; return results.removeFirst() }
        let t = task(times: [480])
        await scheduler.configure(tasks: [t], paused: false)
        clock.now = date(2026, 7, 9, 8, 1)
        await scheduler.handleWake()   // dispara, é descartado → pendingRetry
        clock.now = date(2026, 7, 9, 8, 2)
        await scheduler.rearmAll()     // retry executa
        XCTAssertEqual(count, 2)
    }
}
