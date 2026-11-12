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
    /// First day of the "every 2 days" rhythm. Set once, so refills don't shift it.
    public var scheduleAnchor: Date?
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
    /// Also show the Arabic explanation (Al-Mukhtasar) on the Ayah screen.
    public var showArabicTafsir: Bool = false

    public init() {
        name = ""
        hasCompletedSetup = false
        reminderHour = 7
        reminderMinute = 30
        frequencyRaw = ReminderFrequency.daily.rawValue
        pausedUntil = nil
        scheduleAnchor = nil
        endOfQueueRaw = EndOfQueueBehaviour.askThenRestart.rawValue
        readingTranslations = ["english_saheeh"]
        reminderLanguage = "en"
        appearanceRaw = AppearanceMode.system.rawValue
        textSizeRaw = TextSizeStep.standard.rawValue
        hijriOffset = 0
        reciterID = nil
        showTransliteration = false
        keepArabicOffLockScreen = true
        showArabicTafsir = false
    }

    /// Languages of explanation to show besides those of the chosen translations.
    public var extraTafsirLanguages: [String] { showArabicTafsir ? ["ar"] : [] }

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

/// The reminder queue and schedule, stored as one encoded `ReminderState`. Single record.
@Model
public final class ReminderRecord {
    public var stateData: Data
    public var updatedAt: Date

    public init(state: ReminderState = ReminderState(), updatedAt: Date = .now) {
        stateData = (try? JSONEncoder().encode(state)) ?? Data()
        self.updatedAt = updatedAt
    }

    public var state: ReminderState {
        get { (try? JSONDecoder().decode(ReminderState.self, from: stateData)) ?? ReminderState() }
        set {
            stateData = (try? JSONEncoder().encode(newValue)) ?? stateData
            updatedAt = .now
        }
    }

    @MainActor
    public static func current(in context: ModelContext) throws -> ReminderRecord {
        if let existing = try context.fetch(FetchDescriptor<ReminderRecord>()).first { return existing }
        let fresh = ReminderRecord()
        context.insert(fresh)
        try context.save()
        return fresh
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
            UserSettings.self, TopicChoice.self, ReminderRecord.self,
            ReadRecord.self, SavedAyah.self, ReadingProgress.self,
        ])
    }

    public static func container(inMemory: Bool = false) throws -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
