import Foundation
import SwiftData

/// The user's answer on the AllRead screen.
public enum AllReadChoice: Sendable {
    /// Pick new topics: the app opens Setup, then calls `refill()`.
    case pickNewTopics
    /// Change time or how often: the app opens SetupTime, then calls `refill()`.
    case changeTime
    /// Start again from the first ayah.
    case startAgain
}

/// Connects the reminder service to the on-device store (SwiftData).
@MainActor
public final class ReminderController {
    private let context: ModelContext
    private let service: ReminderService
    private let now: () -> Date

    public init(context: ModelContext, service: ReminderService, now: @escaping () -> Date = Date.init) {
        self.context = context
        self.service = service
        self.now = now
    }

    public var state: ReminderState {
        (try? ReminderRecord.current(in: context).state) ?? ReminderState()
    }

    /// True after the "all read" reminder has gone out and the user hasn't answered yet.
    public var shouldShowAllRead: Bool { state.allReadPendingSince != nil }

    public func settings() throws -> ReminderSettings {
        let user = try UserSettings.current(in: context)
        if user.scheduleAnchor == nil { user.scheduleAnchor = now() }
        let topics = try context.fetch(FetchDescriptor<TopicChoice>(sortBy: [SortDescriptor(\.order)])).map(\.topicID)
        return ReminderSettings(
            topics: topics, hour: user.reminderHour, minute: user.reminderMinute, frequency: user.frequency,
            pausedUntil: user.pausedUntil, anchor: user.scheduleAnchor, language: user.reminderLanguage,
            preferredTranslations: user.readingTranslations, keepArabicOffLockScreen: user.keepArabicOffLockScreen,
            hijriOffset: user.hijriOffset)
    }

    /// See `ReminderService.refill`.
    public func refill() async throws {
        let record = try ReminderRecord.current(in: context)
        let current = record.state
        let since = current.cycleStartedAt ?? .distantPast
        let read = try context.fetch(FetchDescriptor<ReadRecord>(predicate: #Predicate { $0.readAt >= since }))
        let next = try await service.refill(current, settings: try settings(), readThisCycle: Set(read.map(\.ayahSetID)))
        record.state = next
        try context.save()
    }

    /// The user finished reading an ayah set ("I've read it").
    public func markRead(setID: String, hadStory: Bool) async throws {
        let id = setID
        if let existing = try context.fetch(FetchDescriptor<ReadRecord>(predicate: #Predicate { $0.ayahSetID == id })).first {
            existing.readAt = now()
            existing.hadStory = existing.hadStory || hadStory
        } else {
            context.insert(ReadRecord(ayahSetID: setID, readAt: now(), hadStory: hadStory))
        }
        let record = try ReminderRecord.current(in: context)
        record.state = ReminderEngine.markRead(record.state, setID: setID)
        try context.save()
        try await refill()
    }

    public func answerAllRead(_ choice: AllReadChoice) async throws {
        let record = try ReminderRecord.current(in: context)
        var s = record.state
        s.allReadPendingSince = nil
        if choice == .startAgain { s = ReminderEngine.startNewCycle(s, at: now()) }
        record.state = s
        try context.save()
        try await refill()
    }

    /// "Save" from a notification.
    public func save(ayahKey: String, setID: String?) throws {
        let key = ayahKey
        if try context.fetch(FetchDescriptor<SavedAyah>(predicate: #Predicate { $0.ayahKey == key })).isEmpty {
            context.insert(SavedAyah(ayahKey: ayahKey, ayahSetID: setID, savedAt: now()))
            try context.save()
        }
    }

    /// "Remind me in 1 hour" from a notification.
    public func snooze(setID: String, topicID: String) async throws {
        try await service.snooze(setID: setID, topicID: topicID, settings: try settings())
    }
}
