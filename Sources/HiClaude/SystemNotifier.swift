import Foundation
import UserNotifications

/// Notificação do sistema em falha de disparo agendado.
final class SystemNotifier: FailureNotifying {
    func notifyFailure(message: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "HiClaude: disparo falhou"
            content.body = message
            center.add(UNNotificationRequest(identifier: UUID().uuidString,
                                             content: content,
                                             trigger: nil))
        }
    }
}
