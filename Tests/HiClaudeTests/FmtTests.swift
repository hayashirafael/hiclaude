import XCTest
@testable import HiClaude

final class FmtTests: XCTestCase {
    func testRemainingFormataHorasEMinutos() {
        let now = Date(timeIntervalSince1970: 1_783_000_000)
        XCTAssertEqual(Fmt.remaining(until: now.addingTimeInterval(3 * 3600 + 12 * 60), from: now), "3h12")
        XCTAssertEqual(Fmt.remaining(until: now.addingTimeInterval(45 * 60), from: now), "0h45")
        XCTAssertEqual(Fmt.remaining(until: now.addingTimeInterval(-60), from: now), "0h00")
    }
}
