import Foundation
import ServiceManagement
import UserNotifications

enum PermissionAccessStatus: Equatable {
    case notConfigured
    case allowed
    case denied
    case failed(String)
}

protocol NotificationPermissionClient {
    func status() async -> PermissionAccessStatus
    func request() async -> PermissionAccessStatus
}

struct SystemNotificationPermissionClient: NotificationPermissionClient {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func status() async -> PermissionAccessStatus {
        let settings = await center.notificationSettings()
        return Self.map(settings.authorizationStatus)
    }

    func request() async -> PermissionAccessStatus {
        do {
            _ = try await center.requestAuthorization(options: [.alert])
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
