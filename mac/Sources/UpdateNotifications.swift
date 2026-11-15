import AppKit
import UserNotifications

final class UpdateNotifications: NSObject, UNUserNotificationCenterDelegate {
    var open: (() -> Void)?
    func show(_ tag: String) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert]) { allowed, _ in
            guard allowed else { return }
            let content = UNMutableNotificationContent()
            content.title = "공부 친구 업데이트"
            content.body = "\(tag)이 나왔어요. 눌러서 설치 화면을 여세요."
            center.add(UNNotificationRequest(identifier: "update-" + tag, content: content, trigger: nil))
        }
    }
    /// "민지가 공부를 시작했어요 !" while I'm not studying; clicking it does nothing more.
    func news(_ text: String) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert]) { allowed, _ in
            guard allowed else { return }
            let content = UNMutableNotificationContent()
            content.title = "공부 친구"
            content.body = text
            center.add(UNNotificationRequest(identifier: "news-" + UUID().uuidString, content: content, trigger: nil))
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .list]) }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier.hasPrefix("update-") { DispatchQueue.main.async { self.open?() } }
        completionHandler()
    }
}
