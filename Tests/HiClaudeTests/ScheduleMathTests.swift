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

final class ScheduleMathRenewalTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)

    private func at(_ h: Int, _ m: Int = 0, day: Int = 9) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = day; c.hour = h; c.minute = m
        return cal.date(from: c)!
    }

    func testProximoDisparoDentroDoCiclo() {
        // Âncora 07:00; ciclo 07,12,17,22. Às 09:00 → 12:00.
        XCTAssertEqual(
            ScheduleMath.nextScheduledRenewal(anchorMinutes: 7 * 60, after: at(9), calendar: cal),
            at(12))
    }

    func testProximoDisparoPulaOGapParaProximaAncora() {
        // Às 23:00 o último disparo do dia (22:00) já passou → próxima âncora 07:00 do dia seguinte.
        XCTAssertEqual(
            ScheduleMath.nextScheduledRenewal(anchorMinutes: 7 * 60, after: at(23), calendar: cal),
            at(7, day: 10))
    }

    func testProximoDisparoDoGapVaiParaAncora() {
        // 04:00 está no gap (última janela 22–03 terminou). Próximo = 07:00.
        XCTAssertEqual(
            ScheduleMath.nextScheduledRenewal(anchorMinutes: 7 * 60, after: at(4, day: 10), calendar: cal),
            at(7, day: 10))
    }

    func testCatchUpQuandoJanelaAgendadaAindaAtiva() {
        // Disparo das 07:00 perdido (dormindo), agora 08:00 (dentro de 07–12).
        XCTAssertEqual(
            ScheduleMath.missedScheduledRenewal(anchorMinutes: 7 * 60,
                                                between: at(6, 30), and: at(8), calendar: cal),
            at(7))
    }

    func testSemCatchUpNoGap() {
        // Entre 03:30 e 04:30: última janela terminou 03:00 → estamos no gap, nada a recuperar.
        XCTAssertNil(
            ScheduleMath.missedScheduledRenewal(anchorMinutes: 7 * 60,
                                                between: at(3, 30, day: 10), and: at(4, 30, day: 10),
                                                calendar: cal))
    }

    func testSemCatchUpSeNadaPassouDesdeLastCheck() {
        XCTAssertNil(
            ScheduleMath.missedScheduledRenewal(anchorMinutes: 7 * 60,
                                                between: at(9), and: at(10), calendar: cal))
    }
}
