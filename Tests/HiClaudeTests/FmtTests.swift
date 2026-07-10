import XCTest
@testable import HiClaude

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

    func testResumoDosDiasRespeitaIdioma() {
        XCTAssertEqual(HorariosView.daysSummary(Set(1...7), language: .english), "every day")
        XCTAssertEqual(HorariosView.daysSummary(Set(1...7), language: .portuguese), "todos os dias")
        XCTAssertEqual(HorariosView.daysSummary([2, 3, 4, 5, 6], language: .english), "Mon to Fri")
        XCTAssertEqual(HorariosView.daysSummary([2, 3, 4, 5, 6], language: .portuguese), "seg a sex")
    }
}
