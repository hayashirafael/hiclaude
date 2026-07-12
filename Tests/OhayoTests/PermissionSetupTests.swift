import UserNotifications
import XCTest
@testable import Ohayo

final class PermissionSetupTests: XCTestCase {
    func testNotificationAuthorizationMapping() {
        XCTAssertEqual(SystemNotificationPermissionClient.map(.notDetermined), .notConfigured)
        XCTAssertEqual(SystemNotificationPermissionClient.map(.denied), .denied)
        XCTAssertEqual(SystemNotificationPermissionClient.map(.authorized), .allowed)
        XCTAssertEqual(SystemNotificationPermissionClient.map(.provisional), .allowed)
#if !os(macOS)
        XCTAssertEqual(SystemNotificationPermissionClient.map(.ephemeral), .allowed)
#endif
    }

    func testNotificationDeliveryPolicyOnlyAllowsAuthorizedStates() {
        XCTAssertTrue(SystemNotifier.canDeliver(authorizationStatus: .authorized))
        XCTAssertTrue(SystemNotifier.canDeliver(authorizationStatus: .provisional))
        XCTAssertFalse(SystemNotifier.canDeliver(authorizationStatus: .notDetermined))
        XCTAssertFalse(SystemNotifier.canDeliver(authorizationStatus: .denied))
    }
}
