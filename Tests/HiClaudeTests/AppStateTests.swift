import XCTest
@testable import HiClaude

@MainActor
final class AppStateTests: XCTestCase {
    func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "hiclaude-test-\(UUID().uuidString)")!
    }

    func testPrimeiraExecucaoTemDefault7h() {
        let state = AppState(defaults: freshDefaults())
        XCTAssertEqual(state.times, [7 * 60])
        XCTAssertFalse(state.paused)
        XCTAssertNil(state.lastEvent)
    }

    func testPersisteERestauraTimesPausedELastEvent() {
        let defaults = freshDefaults()
        let event = FireEvent(date: Date(timeIntervalSince1970: 1_783_000_000), result: .success)

        let a = AppState(defaults: defaults)
        a.times = [12 * 60 + 30, 7 * 60] // salva ordenado
        a.paused = true
        a.lastEvent = event

        let b = AppState(defaults: defaults)
        XCTAssertEqual(b.times, [7 * 60, 12 * 60 + 30])
        XCTAssertTrue(b.paused)
        XCTAssertEqual(b.lastEvent, event)
    }

    func testPersisteLastCheck() {
        let defaults = freshDefaults()
        let a = AppState(defaults: defaults)
        let mark = Date(timeIntervalSince1970: 1_783_000_000)
        a.lastCheck = mark
        let b = AppState(defaults: defaults)
        XCTAssertEqual(b.lastCheck, mark)
    }

    func testFireResultSkippedRoundtripCodable() throws {
        let event = FireEvent(date: Date(timeIntervalSince1970: 1_783_000_000),
                              result: .skipped(activeUntil: Date(timeIntervalSince1970: 1_783_010_000)))
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(FireEvent.self, from: data)
        XCTAssertEqual(decoded, event)
    }
}
