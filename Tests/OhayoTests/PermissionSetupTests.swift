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

    func testTerminalAutomationSuccessIsAllowed() async {
        let client = SystemTerminalAutomationClient { _ in .success(()) }
        let status = await client.test()
        XCTAssertEqual(status, .allowed)
    }

    func testTerminalAutomationDenialIsDenied() async {
        let client = SystemTerminalAutomationClient { _ in
            .failure(.appleEventNotPermitted)
        }
        let status = await client.test()
        XCTAssertEqual(status, .denied)
    }

    func testTerminalAutomationOtherFailureIsReported() async {
        let client = SystemTerminalAutomationClient { _ in
            .failure(.executionFailed("Terminal unavailable"))
        }
        let status = await client.test()
        XCTAssertEqual(status, .failed("Terminal unavailable"))
    }

    func testTerminalProbeIsReadOnly() {
        XCTAssertEqual(
            SystemTerminalAutomationClient.probeScript,
            "tell application \"Terminal\" to get name"
        )
    }

    @MainActor
    func testLoginItemManagerForwardsInjectedOperations() {
        var enabled = false
        let manager = ClosureLoginItemManager(
            isSupported: true,
            getEnabled: { enabled },
            setEnabled: { enabled = $0 }
        )

        XCTAssertTrue(manager.isSupported)
        XCTAssertFalse(manager.isEnabled)
        manager.setEnabled(true)
        XCTAssertTrue(manager.isEnabled)
    }
}
