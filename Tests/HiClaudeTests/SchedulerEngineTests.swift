import XCTest
@testable import HiClaude

final class FakeClock: Clock {
    var now: Date
    init(now: Date) { self.now = now }
}

final class SchedulerEngineTests: XCTestCase {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return c
    }()

    func date(_ h: Int, _ mi: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 7, day: 7, hour: h, minute: mi))!
    }

    func testCatchUpDisparaUmaVezMesmoComVariosHorariosPerdidos() {
        let clock = FakeClock(now: date(6, 0))
        let engine = SchedulerEngine(clock: clock, calendar: cal, lastCheck: date(6, 0))
        var fires = 0
        engine.onFire = { fires += 1 }
        engine.configure(times: [7 * 60, 12 * 60], paused: false)

        clock.now = date(14, 0) // dormiu das 6h às 14h; perdeu 07:00 e 12:00
        engine.handleWake()
        XCTAssertEqual(fires, 1)
    }

    func testSemHorarioPerdidoNaoDispara() {
        let clock = FakeClock(now: date(8, 0))
        let engine = SchedulerEngine(clock: clock, calendar: cal, lastCheck: date(8, 0))
        var fires = 0
        engine.onFire = { fires += 1 }
        engine.configure(times: [7 * 60], paused: false)

        clock.now = date(9, 0)
        engine.handleWake()
        XCTAssertEqual(fires, 0)
    }

    func testPausadoNaoDisparaMasAvancaLastCheck() {
        let clock = FakeClock(now: date(6, 0))
        let engine = SchedulerEngine(clock: clock, calendar: cal, lastCheck: date(6, 0))
        var fires = 0
        engine.onFire = { fires += 1 }
        engine.configure(times: [7 * 60], paused: true)

        clock.now = date(8, 0)
        engine.handleWake() // 07:00 passou durante a pausa
        XCTAssertEqual(fires, 0)

        // Retomou depois: o horário perdido durante a pausa NÃO dispara retroativamente
        engine.configure(times: [7 * 60], paused: false)
        clock.now = date(8, 30)
        engine.handleWake()
        XCTAssertEqual(fires, 0)
        XCTAssertEqual(engine.lastCheck, date(8, 30))
    }

    func testDedupeSuprimeSegundoDisparoLegitimoEmMenosDe120s() {
        let clock = FakeClock(now: date(6, 59))
        let engine = SchedulerEngine(clock: clock, calendar: cal, lastCheck: date(6, 59))
        var fires = 0
        engine.onFire = { fires += 1 }
        engine.configure(times: [7 * 60, 7 * 60 + 1], paused: false) // 07:00 e 07:01

        clock.now = cal.date(from: DateComponents(year: 2026, month: 7, day: 7,
                                                  hour: 7, minute: 0, second: 30))!
        engine.handleWake() // perdeu 07:00 → dispara
        XCTAssertEqual(fires, 1)

        clock.now = cal.date(from: DateComponents(year: 2026, month: 7, day: 7,
                                                  hour: 7, minute: 1, second: 30))!
        engine.handleWake() // perdeu 07:01 (legítimo), mas só 60s após o último disparo → dedupe suprime
        XCTAssertEqual(fires, 1)
    }

    func testNextFireDateNilQuandoPausado() {
        let clock = FakeClock(now: date(6, 0))
        let engine = SchedulerEngine(clock: clock, calendar: cal, lastCheck: date(6, 0))
        engine.configure(times: [7 * 60], paused: true)
        XCTAssertNil(engine.nextFireDate)
    }
}
