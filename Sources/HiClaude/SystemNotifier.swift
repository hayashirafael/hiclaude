import Foundation
import UserNotifications

/// Notificações do sistema: falha de disparo agendado e resposta capturada.
final class SystemNotifier: Notifying {
    func notifyFailure(message: String) {
        deliver(title: "HiClaude: disparo falhou", body: message)
    }

    func notifyResponse(messageText: String, response: String) {
        deliver(title: "HiClaude: \(messageText)", body: String(response.prefix(300)))
    }

    private func deliver(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: UUID().uuidString,
                                             content: content, trigger: nil))
        }
    }
}
