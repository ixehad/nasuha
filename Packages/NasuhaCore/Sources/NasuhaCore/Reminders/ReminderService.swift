import Foundation

/// One request handed to the notification system.
public struct ReminderRequest: Equatable, Sendable {
    public enum Trigger: Equatable, Sendable {
        /// Fires at this local wall-clock time (year…minute, no time zone), so 7:30 stays
        /// 7:30 if the user travels.
        case calendar(DateComponents)
        case after(seconds: TimeInterval)
    }

    public var id: String
    public var text: ReminderText
    public var trigger: Trigger
}

/// The parts of the notification system the reminder service uses.
/// `UserNotificationScheduler` is the device version; tests use a fake.
public protocol NotificationScheduling: AnyObject {
    func isAuthorized() async -> Bool
    func pendingIdentifiers() async -> [String]
    func removePending(identifiers: [String])
    func add(_ request: ReminderRequest) async throws
}

/// Keeps the reminder queue, the plan and the pending notifications in step.
@MainActor
public final class ReminderService {
    public static let slotPrefix = "nasuha.slot."
    public static let snoozePrefix = "nasuha.snooze."

    private let source: ReminderContentSource
    private let notifications: NotificationScheduling
    private let builder: ReminderContentBuilder
    private let now: () -> Date
    private let calendar: () -> Calendar

    public init(source: ReminderContentSource, notifications: NotificationScheduling, localizer: Localizer,
                now: @escaping () -> Date = Date.init,
                calendar: @escaping () -> Calendar = { Calendar.current }) {
        self.source = source
        self.notifications = notifications
        self.builder = ReminderContentBuilder(source: source, localizer: localizer)
        self.now = now
        self.calendar = calendar
    }

    /// Catches up with reminders that have fired, rebuilds the queue for the current topics,
    /// plans up to 60 reminders and replaces the pending notifications with them.
    /// Call it on app open, after settings change, on time-zone change and from background refresh.
    public func refill(_ state: ReminderState, settings: ReminderSettings, readThisCycle: Set<String>) async throws -> ReminderState {
        let date = now()
        let cal = calendar()
        var s = ReminderEngine.reconcile(state, now: date)

        var setsByTopic: [String: [String]] = [:]
        for topic in settings.topics { setsByTopic[topic] = try source.setIDs(topic: topic) }
        let ramadan = HijriDate.isRamadan(date, offset: settings.hijriOffset, timeZone: cal.timeZone)
        s = ReminderEngine.rebuild(s, topics: settings.topics, setsByTopic: setsByTopic,
                                   isRamadan: ramadan, readThisCycle: readThisCycle)
        if s.cycleStartedAt == nil { s.cycleStartedAt = date }

        let dates = ReminderSchedule.fireDates(after: date, settings: settings, count: ReminderEngine.windowSize, calendar: cal)
        s.planned = ReminderEngine.plan(s, dates: dates)

        let stale = await notifications.pendingIdentifiers().filter { $0.hasPrefix(Self.slotPrefix) }
        notifications.removePending(identifiers: stale)
        guard await notifications.isAuthorized() else { return s }
        for slot in s.planned {
            guard let text = try builder.text(for: slot.kind, settings: settings) else { continue }
            let parts = cal.dateComponents([.year, .month, .day, .hour, .minute], from: slot.fireDate)
            try await notifications.add(ReminderRequest(id: slot.id, text: text, trigger: .calendar(parts)))
        }
        return s
    }

    /// "Remind me in 1 hour".
    public func snooze(setID: String, topicID: String, settings: ReminderSettings) async throws {
        guard let text = try builder.ayah(setID: setID, topicID: topicID, settings: settings) else { return }
        let id = Self.snoozePrefix + UUID().uuidString
        try await notifications.add(ReminderRequest(id: id, text: text, trigger: .after(seconds: 3_600)))
    }
}
