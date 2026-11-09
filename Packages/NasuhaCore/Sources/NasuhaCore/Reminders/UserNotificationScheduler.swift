import Foundation
import UserNotifications

/// The device implementation of `NotificationScheduling` (local notifications only, no server).
public final class UserNotificationScheduler: NotificationScheduling, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func isAuthorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    /// Asks for permission. Call only from "Start my daily ayah", after explaining why.
    public func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    public func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    public func removePending(identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func add(_ request: ReminderRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.text.title
        content.body = request.text.body
        content.threadIdentifier = request.text.threadID
        content.categoryIdentifier = request.text.category
        content.userInfo = request.text.userInfo
        content.sound = .default
        let trigger: UNNotificationTrigger = switch request.trigger {
        case let .calendar(parts): UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        case let .after(seconds): UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        }
        try await center.add(UNNotificationRequest(identifier: request.id, content: content, trigger: trigger))
    }

    /// Registers the reminder actions. "Listen" is included only when recitation is available,
    /// so the notification never shows a button that does nothing.
    public func registerCategories(listenTitle: String, snoozeTitle: String, saveTitle: String, audioAvailable: Bool) {
        var actions: [UNNotificationAction] = []
        if audioAvailable {
            actions.append(UNNotificationAction(identifier: ReminderAction.listen, title: listenTitle, options: []))
        }
        actions.append(UNNotificationAction(identifier: ReminderAction.snooze, title: snoozeTitle, options: []))
        actions.append(UNNotificationAction(identifier: ReminderAction.save, title: saveTitle, options: []))
        let ayah = UNNotificationCategory(identifier: ReminderCategory.ayah, actions: actions, intentIdentifiers: [], options: [])
        let allRead = UNNotificationCategory(identifier: ReminderCategory.allRead, actions: [], intentIdentifiers: [], options: [])
        center.setNotificationCategories([ayah, allRead])
    }
}
