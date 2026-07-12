import XCTest
@testable import Ohayo

@MainActor
final class FmtTests: XCTestCase {
    func testRemainingFormataHorasEMinutos() {
        let now = Date(timeIntervalSince1970: 1_783_000_000)
        XCTAssertEqual(Fmt.remaining(until: now.addingTimeInterval(3 * 3600 + 12 * 60), from: now), "3h12")
        XCTAssertEqual(Fmt.remaining(until: now.addingTimeInterval(45 * 60), from: now), "0h45")
        XCTAssertEqual(Fmt.remaining(until: now.addingTimeInterval(-60), from: now), "0h00")
    }

    func testWeekdayTimeRespeitaIdioma() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 8, minute: 0))!
        XCTAssertTrue(Fmt.weekdayTime(date, language: .english).lowercased().contains("fri"))
        XCTAssertTrue(Fmt.weekdayTime(date, language: .portuguese).lowercased().contains("sex"))
    }

    func testHhmmUsa24hEmAmbosOsIdiomas() {
        // Consistência com os chips (Fmt.minutes) e weekdayTime, que são 24h:
        // em inglês o timeStyle .short (locale en_US) virava "8:05 PM",
        // misturando 12h e 24h na mesma tela.
        let date = Calendar.current.date(
            from: DateComponents(year: 2026, month: 7, day: 10, hour: 20, minute: 5))!
        XCTAssertEqual(Fmt.hhmm(date, language: .english), "20:05")
        XCTAssertEqual(Fmt.hhmm(date, language: .portuguese), "20:05")
    }

    func testResumoDosDiasRespeitaIdioma() {
        XCTAssertEqual(HorariosView.daysSummary(Set(1...7), language: .english), "every day")
        XCTAssertEqual(HorariosView.daysSummary(Set(1...7), language: .portuguese), "todos os dias")
        XCTAssertEqual(HorariosView.daysSummary([2, 3, 4, 5, 6], language: .english), "Mon to Fri")
        XCTAssertEqual(HorariosView.daysSummary([2, 3, 4, 5, 6], language: .portuguese), "seg a sex")
    }

    func testEventTimeHojeSoHoraOutroDiaComDiaDaSemana() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 9, minute: 0))!
        let hoje = cal.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 21, minute: 0))!
        let amanha = cal.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: 21, minute: 0))!
        XCTAssertEqual(Fmt.eventTime(hoje, now: now, calendar: cal, language: .portuguese), "21:00")
        // 2026-07-11 é sábado: precisa vir com o dia da semana, não só a hora.
        let label = Fmt.eventTime(amanha, now: now, calendar: cal, language: .portuguese)
        XCTAssertTrue(label.lowercased().contains("sáb"), label)
        XCTAssertTrue(label.contains("21:00"), label)
    }
}
