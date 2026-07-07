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
