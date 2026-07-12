import XCTest
@testable import Ohayo

final class AppPathsTests: XCTestCase {
    func testSupportWorkspaceAndLockUseOhayoDirectory() {
        let home = URL(fileURLWithPath: "/tmp/ohayo-home")
        let support = home.appendingPathComponent("Library/Application Support/Ohayo")

        XCTAssertEqual(AppPaths.supportDirectory(home: home), support)
        XCTAssertEqual(AppPaths.workspaceDirectory(home: home), support.appendingPathComponent("workspace"))
        XCTAssertEqual(AppPaths.instanceLockPath(home: home), support.appendingPathComponent("instance.lock").path)
    }
}
