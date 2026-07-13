import AppKit
import Combine
import Foundation
import ServiceManagement
import UserNotifications

enum PermissionAccessStatus: Equatable {
    case notConfigured
    case allowed
    case denied
    case unavailable
    case failed(String)

    var allowsRequest: Bool {
        self != .allowed && self != .unavailable
    }
}

protocol NotificationPermissionClient {
    func status() async -> PermissionAccessStatus
    func request() async -> PermissionAccessStatus
}

struct SystemNotificationPermissionClient: NotificationPermissionClient {
    private let isBundled: Bool
    private let center: () -> UNUserNotificationCenter

    init(
        isBundled: Bool = Bundle.main.bundleIdentifier != nil,
        center: @escaping () -> UNUserNotificationCenter = { .current() }
    ) {
        self.isBundled = isBundled
        self.center = center
    }

    func status() async -> PermissionAccessStatus {
        guard isBundled else { return .unavailable }
        let settings = await center().notificationSettings()
        return Self.map(settings.authorizationStatus)
    }

    func request() async -> PermissionAccessStatus {
        guard isBundled else { return .unavailable }
        do {
            _ = try await center().requestAuthorization(options: [.alert])
            return await status()
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func map(_ status: UNAuthorizationStatus) -> PermissionAccessStatus {
        switch status {
        case .notDetermined: return .notConfigured
        case .denied: return .denied
        case .authorized, .provisional, .ephemeral: return .allowed
        @unknown default: return .failed("unknown notification authorization status")
        }
    }
}

enum TerminalAutomationError: Error, Equatable {
    case appleEventNotPermitted
    case executionFailed(String)
}

protocol TerminalAutomationClient {
    func test() async -> PermissionAccessStatus
}

struct SystemTerminalAutomationClient: TerminalAutomationClient {
    static let probeScript = "tell application \"Terminal\" to get name"
    var runner: (String) -> Result<Void, TerminalAutomationError> = Self.run

    func test() async -> PermissionAccessStatus {
        switch runner(Self.probeScript) {
        case .success: return .allowed
        case .failure(.appleEventNotPermitted): return .denied
        case .failure(.executionFailed(let message)): return .failed(message)
        }
    }

    private static func run(_ source: String) -> Result<Void, TerminalAutomationError> {
        var details: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            return .failure(.executionFailed("failed to create AppleScript"))
        }
        script.executeAndReturnError(&details)
        if let details {
            let number = details[NSAppleScript.errorNumber] as? Int
            if number == -1743 { return .failure(.appleEventNotPermitted) }
            let message = details[NSAppleScript.errorMessage] as? String ?? details.description
            return .failure(.executionFailed(message))
        }
        return .success(())
    }
}

@MainActor
final class PermissionSetupModel: ObservableObject {
    @Published private(set) var notificationStatus: PermissionAccessStatus = .notConfigured
    @Published private(set) var terminalStatus: PermissionAccessStatus = .notConfigured
    @Published private(set) var loginItemEnabled: Bool
    let loginItemSupported: Bool

    private let notifications: NotificationPermissionClient
    private let terminal: TerminalAutomationClient
    private let loginItem: LoginItemManaging

    init(notifications: NotificationPermissionClient = SystemNotificationPermissionClient(),
         terminal: TerminalAutomationClient = SystemTerminalAutomationClient(),
         loginItem: LoginItemManaging = SystemLoginItemManager()) {
        self.notifications = notifications
        self.terminal = terminal
        self.loginItem = loginItem
        self.loginItemSupported = loginItem.isSupported
        self.loginItemEnabled = loginItem.isEnabled
    }

    func refresh() async {
        notificationStatus = await notifications.status()
        loginItemEnabled = loginItem.isEnabled
    }

    func requestNotifications() async {
        notificationStatus = await notifications.request()
    }

    func testTerminal() async {
        terminalStatus = await terminal.test()
    }

    func setLoginItemEnabled(_ enabled: Bool) {
        loginItem.setEnabled(enabled)
        loginItemEnabled = loginItem.isEnabled
    }
}
