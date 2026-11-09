import Foundation

/// One ayah set in the reminder queue.
public struct QueueItem: Codable, Equatable, Sendable {
    public var setID: String
    /// The topic this item came from (used for the notification title and thread).
    public var topicID: String
    /// Sent or read in the current cycle.
    public var done: Bool

    public init(setID: String, topicID: String, done: Bool = false) {
        self.setID = setID
        self.topicID = topicID
        self.done = done
    }
}

/// What a scheduled reminder is for.
public enum SlotKind: Codable, Equatable, Sendable {
    case ayah(setID: String, topicID: String)
    /// The special last reminder: every ayah in the user's topics has been sent.
    case allRead(total: Int)
}

/// A reminder that is planned for a given time.
public struct PlannedSlot: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var fireDate: Date
    public var kind: SlotKind

    public init(id: String, fireDate: Date, kind: SlotKind) {
        self.id = id
        self.fireDate = fireDate
        self.kind = kind
    }
}

/// Everything the reminder system remembers between launches.
///
/// The planned slots are the source of truth for which ayah is "today's",
/// whether or not notifications are allowed, so Home stays in step with them.
public struct ReminderState: Codable, Equatable, Sendable {
    public var items: [QueueItem] = []
    /// Topic IDs the queue was built from, in pick order.
    public var topics: [String] = []
    /// True when the queue was built with Ramadan items first.
    public var ramadanFirst = false
    /// Increases each time the queue starts again from the first ayah.
    public var cycle = 0
    public var cycleStartedAt: Date?
    /// The ayah most recently sent: today's ayah on Home.
    public var currentSetID: String?
    public var currentTopicID: String?
    /// Set when the "all read" reminder has gone out. Home shows AllRead until the user answers.
    public var allReadPendingSince: Date?
    /// Reminders scheduled from now on, in time order.
    public var planned: [PlannedSlot] = []

    public init() {}

    public var total: Int { items.count }
    public var doneCount: Int { items.filter(\.done).count }

    /// "Ayah 18 of 48": the number of the next ayah to be sent, and the total.
    public var progress: (next: Int, total: Int) {
        (min(doneCount + 1, max(total, 1)), total)
    }

    public var nextSlot: PlannedSlot? { planned.first }
}

/// The reminder-related settings, as plain values.
public struct ReminderSettings: Equatable, Sendable {
    public var topics: [String]
    public var hour: Int
    public var minute: Int
    public var frequency: ReminderFrequency
    public var pausedUntil: Date?
    public var anchor: Date?
    public var language: String
    public var preferredTranslations: [String]
    public var keepArabicOffLockScreen: Bool
    public var hijriOffset: Int

    public init(topics: [String], hour: Int = 7, minute: Int = 30, frequency: ReminderFrequency = .daily,
                pausedUntil: Date? = nil, anchor: Date? = nil, language: String = "en",
                preferredTranslations: [String] = [], keepArabicOffLockScreen: Bool = true, hijriOffset: Int = 0) {
        self.topics = topics
        self.hour = hour
        self.minute = minute
        self.frequency = frequency
        self.pausedUntil = pausedUntil
        self.anchor = anchor
        self.language = language
        self.preferredTranslations = preferredTranslations
        self.keepArabicOffLockScreen = keepArabicOffLockScreen
        self.hijriOffset = hijriOffset
    }
}
