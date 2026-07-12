import Foundation
import UserNotifications

/// Notificações do sistema: falha de disparo agendado, resposta capturada e
/// sucesso de tarefa com notifyOnSuccess ligado.
final class SystemNotifier: Notifying {
    func notifyFailure(title: String, message: String) {
        deliver(title: title, body: message)
    }

    func notifyResponse(title: String, response: String) {
        deliver(title: title, body: String(response.prefix(300)))
    }

    func notifySuccess(title: String, body: String) {
        deliver(title: title, body: body) // corpo curto por construção
    }

    static func canDeliver(authorizationStatus: UNAuthorizationStatus) -> Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined, .denied: return false
        @unknown default: return false
        }
    }

    private func deliver(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard Self.canDeliver(authorizationStatus: settings.authorizationStatus) else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: UUID().uuidString,
                                             content: content, trigger: nil))
        }
    }
}
