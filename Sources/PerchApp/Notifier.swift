import AppKit
import PerchAppCore
import PerchCore
import UserNotifications

/// macOS notifications for due reminders. Needs the .app bundle: UNUserNotificationCenter raises when the
/// process has no bundle identifier (e.g. the bare binary from `swift run PerchApp`), so it stays off there.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter?

    override init() {
        center = Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
            ? UNUserNotificationCenter.current() : nil
        super.init()
        guard let center else {
            NSLog("Perch: not running from Perch.app, so due reminders only pulse the notch")
            return
        }
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if !granted { NSLog("Perch: notifications not allowed (\(error.map(String.init(describing:)) ?? "denied")); reminders only pulse the notch") }
        }
    }

    func due(_ item: Item) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = "Due now" + (item.source == "human" ? "" : " · \(item.source)")
        content.sound = .default
        content.userInfo = ["id": item.id, "link": item.link ?? ""]
        let id = "due-\(item.id)-\(Int(item.dueAt?.timeIntervalSince1970 ?? 0))"
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
            if let error { NSLog("Perch: could not post reminder: \(error)") }
        }
    }

    /// Show the banner even if Perch happens to be the active app.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// Clicking the banner opens the item's link, if it has one.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let link = response.notification.request.content.userInfo["link"] as? String
        if let url = RowFormat.linkURL(link) {
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
        }
        completionHandler()
    }
}
