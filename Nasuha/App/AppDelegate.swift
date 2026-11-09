import NasuhaCore
import UIKit
import UserNotifications

/// Handles notification taps and actions, including when a tap launches the app.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // The delegate must be set before launch finishes, or a cold-start tap is lost.
        UNUserNotificationCenter.current().delegate = self
        MainActor.assumeIsolated { AppServices.shared.registerNotificationActions() }
        return true
    }

    /// Show the reminder as a banner when the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let setID = info[ReminderUserInfo.ayahSetID] as? String
        let topicID = info[ReminderUserInfo.topicID] as? String
        let ayahKey = info[ReminderUserInfo.ayahKey] as? String

        await MainActor.run {
            let services = AppServices.shared
            switch response.actionIdentifier {
            case ReminderAction.snooze:
                guard let setID, let topicID else { return }
                Task { try? await services.reminders?.snooze(setID: setID, topicID: topicID) }
            case ReminderAction.save:
                guard let ayahKey else { return }
                try? services.reminders?.save(ayahKey: ayahKey, setID: setID)
            case UNNotificationDefaultActionIdentifier:
                if let link = DeepLink(userInfo: info) { services.router.open(link) }
            default:
                break
            }
        }
    }
}
