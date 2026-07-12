import XCTest
@testable import Ohayo

final class StartupCoordinatorTests: XCTestCase {
    func testBundledFirstRunOpensGuide() {
        XCTAssertTrue(StartupCoordinator.shouldOpenGuide(
            hasDismissed: false, isBundled: true))
    }

    func testDismissedGuideDoesNotOpenAutomatically() {
        XCTAssertFalse(StartupCoordinator.shouldOpenGuide(
            hasDismissed: true, isBundled: true))
    }

    func testUnbundledDevelopmentRunDoesNotOpenGuide() {
        XCTAssertFalse(StartupCoordinator.shouldOpenGuide(
            hasDismissed: false, isBundled: false))
    }
}
