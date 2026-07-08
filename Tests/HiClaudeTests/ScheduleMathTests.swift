import XCTest
@testable import HiClaude

final class ScheduleMathTests: XCTestCase {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return c
    }()

    func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    // nextFireDate

    func testNextFireHojeQuandoHorarioAindaNaoPassou() {
        let now = date(2026, 7, 7, 6, 0)
        let next = ScheduleMath.nextFireDate(times: [7 * 60], after: now, calendar: cal)
        XCTAssertEqual(next, date(2026, 7, 7, 7, 0))
    }

    func testNextFireAmanhaQuandoHorarioJaPassou() {
        let now = date(2026, 7, 7, 8, 0)
        let next = ScheduleMath.nextFireDate(times: [7 * 60], after: now, calendar: cal)
        XCTAssertEqual(next, date(2026, 7, 8, 7, 0))
    }

    func testNextFireEscolheOMaisProximoEntreVarios() {
        let now = date(2026, 7, 7, 8, 0)
        let next = ScheduleMath.nextFireDate(times: [7 * 60, 12 * 60 + 30], after: now, calendar: cal)
        XCTAssertEqual(next, date(2026, 7, 7, 12, 30))
    }

    func testNextFireNilParaListaVazia() {
        XCTAssertNil(ScheduleMath.nextFireDate(times: [], after: date(2026, 7, 7, 8, 0), calendar: cal))
    }

    // hasMissedTime

    func testDetectaHorarioPerdidoNoMesmoDia() {
        let lastCheck = date(2026, 7, 7, 6, 0)
        let now = date(2026, 7, 7, 14, 0)
        XCTAssertTrue(ScheduleMath.hasMissedTime(times: [7 * 60, 12 * 60], between: lastCheck, and: now, calendar: cal))
    }

    func testNaoDetectaQuandoNenhumHorarioNoIntervalo() {
        let lastCheck = date(2026, 7, 7, 8, 0)
        let now = date(2026, 7, 7, 11, 0)
        XCTAssertFalse(ScheduleMath.hasMissedTime(times: [7 * 60, 12 * 60], between: lastCheck, and: now, calendar: cal))
    }

    func testDetectaHorarioPerdidoAtravessandoDias() {
        let lastCheck = date(2026, 7, 5, 23, 0)
        let now = date(2026, 7, 7, 6, 0)
        XCTAssertTrue(ScheduleMath.hasMissedTime(times: [7 * 60], between: lastCheck, and: now, calendar: cal))
    }

    func testIntervaloVazioNaoDetecta() {
        let t = date(2026, 7, 7, 8, 0)
        XCTAssertFalse(ScheduleMath.hasMissedTime(times: [7 * 60], between: t, and: t, calendar: cal))
    }
}

final class ScheduleMathPorHorarioTests: XCTestCase {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return c
    }()

    func date(_ d: Int, _ h: Int, _ mi: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 7, day: d, hour: h, minute: mi))!
    }

    func testNextFireRetornaDataEMinutos() {
        let next = ScheduleMath.nextFire(times: [7 * 60, 12 * 60], after: date(7, 8, 0), calendar: cal)
        XCTAssertEqual(next?.date, date(7, 12, 0))
        XCTAssertEqual(next?.minutes, 12 * 60)
    }

    func testNextFireViraParaODiaSeguinte() {
        let next = ScheduleMath.nextFire(times: [7 * 60], after: date(7, 8, 0), calendar: cal)
        XCTAssertEqual(next?.date, date(8, 7, 0))
        XCTAssertEqual(next?.minutes, 7 * 60)
    }

    func testLastMissedPegaOMaisRecenteAtravesDeDias() {
        // Perdeu 07/07 07:00, 07/07 12:00 e 08/07 07:00 — o mais recente é 07:00.
        XCTAssertEqual(ScheduleMath.lastMissedMinutes(times: [7 * 60, 12 * 60],
                                                      between: date(7, 6, 0), and: date(8, 8, 0),
                                                      calendar: cal), 7 * 60)
        // Dentro do mesmo dia, o mais recente é 12:00.
        XCTAssertEqual(ScheduleMath.lastMissedMinutes(times: [7 * 60, 12 * 60],
                                                      between: date(7, 6, 0), and: date(7, 14, 0),
                                                      calendar: cal), 12 * 60)
    }

    func testLastMissedNilSemPerdidos() {
        XCTAssertNil(ScheduleMath.lastMissedMinutes(times: [7 * 60],
                                                    between: date(7, 8, 0), and: date(7, 9, 0),
                                                    calendar: cal))
        XCTAssertNil(ScheduleMath.lastMissedMinutes(times: [],
                                                    between: date(7, 6, 0), and: date(7, 9, 0),
                                                    calendar: cal))
    }
}
