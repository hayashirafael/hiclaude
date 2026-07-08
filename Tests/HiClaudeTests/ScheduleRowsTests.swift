import XCTest
@testable import HiClaude

final class ScheduleRowsTests: XCTestCase {
    func testEditingARowAcrossNeighborKeepsEditingSameRowIdentity() {
        var model = ScheduleRows(times: [7 * 60, 12 * 60])
        let editedID = model.rows[1].id

        model.update(id: editedID, minutes: 6 * 60 + 30)

        XCTAssertEqual(model.publishedTimes, [6 * 60 + 30, 7 * 60])
        XCTAssertEqual(model.rows.first?.id, editedID)

        model.update(id: editedID, minutes: 6 * 60 + 45)

        XCTAssertEqual(model.publishedTimes, [6 * 60 + 45, 7 * 60])
        XCTAssertEqual(model.rows.first?.id, editedID)
    }
}
