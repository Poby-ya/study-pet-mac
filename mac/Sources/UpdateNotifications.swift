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
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .list]) }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { self.open?() }
        completionHandler()
    }
}
