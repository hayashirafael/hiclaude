import XCTest
@testable import HiClaude

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
