import XCTest
@testable import HiClaude

final class AgendaMathTests: XCTestCase {
    // Calendar fixo para testes determinísticos.
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return c
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func testProximaOcorrenciaNoMesmoDia() {
        // Quinta 2026-07-09 07:00; tarefa às 08:00 e 13:00, todos os dias.
        let now = date(2026, 7, 9, 7, 0)
        let next = AgendaMath.nextOccurrence(times: [480, 780], weekdays: Set(1...7),
                                             after: now, calendar: cal)
        XCTAssertEqual(next, date(2026, 7, 9, 8, 0))
    }

    func testProximaOcorrenciaPulaParaProximoDiaHabilitado() {
        // Sexta 2026-07-10 14:00; tarefa às 08:00 só em dias úteis (2...6)
        // → próxima é segunda 2026-07-13 08:00.
        let now = date(2026, 7, 10, 14, 0)
        let next = AgendaMath.nextOccurrence(times: [480], weekdays: [2, 3, 4, 5, 6],
                                             after: now, calendar: cal)
        XCTAssertEqual(next, date(2026, 7, 13, 8, 0))
    }

    func testProximaOcorrenciaVaziaSemHorariosOuDias() {
        let now = date(2026, 7, 9, 7, 0)
        XCTAssertNil(AgendaMath.nextOccurrence(times: [], weekdays: [1], after: now, calendar: cal))
        XCTAssertNil(AgendaMath.nextOccurrence(times: [480], weekdays: [], after: now, calendar: cal))
    }

    func testOcorrenciaPerdidaMaisRecente() {
        // Dormiu de quarta 07:00 até quinta 14:30; horários 08:00 e 13:00
        // todos os dias → perdidas: qua 08:00, qua 13:00, qui 08:00, qui
        // 13:00; a mais recente é qui 13:00.
        let since = date(2026, 7, 8, 7, 0)
        let now = date(2026, 7, 9, 14, 30)
        let missed = AgendaMath.lastMissedOccurrence(times: [480, 780], weekdays: Set(1...7),
                                                     between: since, and: now, calendar: cal)
        XCTAssertEqual(missed, date(2026, 7, 9, 13, 0))
    }

    func testSemOcorrenciaPerdidaQuandoNadaPassou() {
        let since = date(2026, 7, 9, 13, 30)
        let now = date(2026, 7, 9, 14, 0)
        XCTAssertNil(AgendaMath.lastMissedOccurrence(times: [480, 780], weekdays: Set(1...7),
                                                     between: since, and: now, calendar: cal))
    }

    // MARK: - chainTimes / normalized

    func testChainTimesCruzaAMeiaNoite() {
        // Âncora 09:00 → 09:00, 14:00, 19:00 e 00:00 (24:00 vira meia-noite).
        XCTAssertEqual(AgendaMath.chainTimes(anchor: 9 * 60), [0, 540, 840, 1140])
    }

    func testChainTimesAncoraNoturna() {
        // Âncora 21:00 → 21:00, 02:00, 07:00, 12:00.
        XCTAssertEqual(AgendaMath.chainTimes(anchor: 21 * 60), [120, 420, 720, 1260])
    }

    func testNormalizedOrdenaESemDuplicatas() {
        XCTAssertEqual(AgendaMath.normalized([780, 540, 540]), [540, 780])
        XCTAssertEqual(AgendaMath.normalized([]), [])
    }
}
