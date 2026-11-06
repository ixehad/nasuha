import Foundation
import SwiftData

// User state lives only on this phone, in SwiftData. No accounts, no sync.

/// The single settings record. Use `UserSettings.current(in:)`.
@Model
public final class UserSettings {
    public var name: String
    public var hasCompletedSetup: Bool

    // Your daily ayah
    public var reminderHour: Int          // 0...23
    public var reminderMinute: Int        // 0, 15, 30, 45
    public var frequencyRaw: String
    public var pausedUntil: Date?
    public var endOfQueueRaw: String

    // Language
    /// QuranEnc keys shown when reading, in order, e.g. ["english_saheeh"].
    public var readingTranslations: [String]
    /// Language code for reminder text: "en" or "bn".
    public var reminderLanguage: String

    // Reading
    public var appearanceRaw: String
    public var textSizeRaw: Int
    /// Days added to the Umm al-Qura date to match local moon sighting. −2...+2.
    public var hijriOffset: Int
    public var reciterID: String?
    public var showTransliteration: Bool
    /// On by default: no Arabic in notification text.
    public var keepArabicOffLockScreen: Bool

    public init() {
        name = ""
        hasCompletedSetup = false
        reminderHour = 7
        reminderMinute = 30
        frequencyRaw = ReminderFrequency.daily.rawValue
        pausedUntil = nil
        endOfQueueRaw = EndOfQueueBehaviour.askThenRestart.rawValue
        readingTranslations = ["english_saheeh"]
        reminderLanguage = "en"
        appearanceRaw = AppearanceMode.system.rawValue
        textSizeRaw = TextSizeStep.standard.rawValue
        hijriOffset = 0
        reciterID = nil
        showTransliteration = false
        keepArabicOffLockScreen = true
    }

    public var frequency: ReminderFrequency {
        get { ReminderFrequency(rawValue: frequencyRaw) ?? .daily }
        set { frequencyRaw = newValue.rawValue }
    }

    public var appearance: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue }
    }

    public var textSize: TextSizeStep {
        get { TextSizeStep(rawValue: textSizeRaw) ?? .standard }
        set { textSizeRaw = newValue.rawValue }
    }

    public var endOfQueue: EndOfQueueBehaviour {
        get { EndOfQueueBehaviour(rawValue: endOfQueueRaw) ?? .askThenRestart }
        set { endOfQueueRaw = newValue.rawValue }
    }

    /// Clamps the Hijri offset to −2...+2.
    public func setHijriOffset(_ value: Int) { hijriOffset = min(2, max(-2, value)) }

    /// Fetches the settings record, creating it the first time.
    @MainActor
    public static func current(in context: ModelContext) throws -> UserSettings {
        if let existing = try context.fetch(FetchDescriptor<UserSettings>()).first { return existing }
        let fresh = UserSettings()
        context.insert(fresh)
        try context.save()
        return fresh
    }
}

/// A topic the user picked. `order` is the order they picked it in.
@Model
public final class TopicChoice {
    @Attribute(.unique) public var topicID: String
    public var order: Int
    public var chosenAt: Date

    public init(topicID: String, order: Int, chosenAt: Date = .now) {
        self.topicID = topicID
        self.order = order
        self.chosenAt = chosenAt
    }
}

/// One slot in the reminder queue.
@Model
public final class QueueEntry {
    public var index: Int
    public var ayahSetID: String
    public var topicID: String
    public var scheduledFor: Date?
    public var sentAt: Date?

    public init(index: Int, ayahSetID: String, topicID: String) {
        self.index = index
        self.ayahSetID = ayahSetID
        self.topicID = topicID
    }
}

/// Where the user is in the queue. Single record.
@Model
public final class QueueState {
    /// Index of the next entry to send.
    public var position: Int
    /// The topic IDs (sorted, joined) the queue was built from.
    public var topicsKey: String
    public var builtAt: Date
    /// Set when the last ayah was sent; cleared when AllRead is answered or the queue restarts.
    public var finishedAt: Date?

    public init(position: Int = 0, topicsKey: String = "", builtAt: Date = .now) {
        self.position = position
        self.topicsKey = topicsKey
        self.builtAt = builtAt
    }
}

/// An ayah set the user has read. Kept across queue rebuilds.
@Model
public final class ReadRecord {
    @Attribute(.unique) public var ayahSetID: String
    public var readAt: Date
    public var hadStory: Bool

    public init(ayahSetID: String, readAt: Date = .now, hadStory: Bool = false) {
        self.ayahSetID = ayahSetID
        self.readAt = readAt
        self.hadStory = hadStory
    }
}

@Model
public final class SavedAyah {
    /// "93:3"
    @Attribute(.unique) public var ayahKey: String
    public var ayahSetID: String?
    public var savedAt: Date

    public init(ayahKey: String, ayahSetID: String? = nil, savedAt: Date = .now) {
        self.ayahKey = ayahKey
        self.ayahSetID = ayahSetID
        self.savedAt = savedAt
    }
}

/// Reading and listening progress. Single record.
@Model
public final class ReadingProgress {
    public var surahsOpened: [Int]
    public var listeningSeconds: Double
    public var lastSurah: Int
    public var lastAyah: Int

    public init() {
        surahsOpened = []
        listeningSeconds = 0
        lastSurah = 1
        lastAyah = 1
    }

    public func markOpened(surah: Int) {
        if !surahsOpened.contains(surah) { surahsOpened.append(surah) }
        lastSurah = surah
    }

    @MainActor
    public static func current(in context: ModelContext) throws -> ReadingProgress {
        if let existing = try context.fetch(FetchDescriptor<ReadingProgress>()).first { return existing }
        let fresh = ReadingProgress()
        context.insert(fresh)
        try context.save()
        return fresh
    }
}

public enum NasuhaSchema {
    public static var schema: Schema {
        Schema([
            UserSettings.self, TopicChoice.self, QueueEntry.self, QueueState.self,
            ReadRecord.self, SavedAyah.self, ReadingProgress.self,
        ])
    }

    public static func container(inMemory: Bool = false) throws -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
