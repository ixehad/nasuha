import Foundation

/// Looks up UI strings in a given language (the reminder language, which can differ
/// from the phone's language). The app reads them from its String Catalog.
public protocol Localizer: Sendable {
    func string(_ key: String, language: String) -> String
}

/// The content a reminder needs. `ContentStore` provides it on device.
public protocol ReminderContentSource {
    func setIDs(topic: String) throws -> [String]
    func ayahSet(id: String) throws -> AyahSet?
    func ayah(_ key: AyahKey) throws -> Ayah?
    func surah(_ number: Int) throws -> Surah?
    func translation(for key: AyahKey, language: String, preferring: [String]) throws -> Translation?
}

extension ContentStore: ReminderContentSource {}

/// Text of one notification.
public struct ReminderText: Equatable, Sendable {
    public var title: String
    public var body: String
    public var threadID: String
    public var category: String
    public var userInfo: [String: String]
}

public enum ReminderCategory {
    public static let ayah = "nasuha.ayah"
    public static let allRead = "nasuha.allread"
}

public enum ReminderAction {
    public static let listen = "nasuha.listen"
    public static let snooze = "nasuha.snooze"
    public static let save = "nasuha.save"
}

public enum ReminderUserInfo {
    public static let ayahSetID = "ayahSetId"
    public static let ayahKey = "ayahKey"
    public static let topicID = "topicId"
    public static let kind = "kind"
}

/// String Catalog keys used in reminders.
public enum ReminderStrings {
    public static let storyOfRevelation = "The story of its revelation: %@"
    public static let allReadTitle = "You've read all %@ ayahs"
    public static let allReadBodyTomorrow = "Alhamdulillah. Pick new topics, or tomorrow we start again from the first ayah."
    public static let allReadBodyNext = "Alhamdulillah. Pick new topics, or at your next reminder we start again from the first ayah."
}

public struct ReminderContentBuilder {
    /// Above this length the optional "The story of its revelation" line is left out, so the
    /// notification shows in full. Source text is never shortened.
    public static let fullDisplayLimit = 240

    let source: ReminderContentSource
    let localizer: Localizer

    public init(source: ReminderContentSource, localizer: Localizer) {
        self.source = source
        self.localizer = localizer
    }

    public func text(for kind: SlotKind, settings: ReminderSettings) throws -> ReminderText? {
        switch kind {
        case let .ayah(setID, topicID): try ayah(setID: setID, topicID: topicID, settings: settings)
        case let .allRead(total): allRead(total: total, settings: settings)
        }
    }

    /// Title: the topic's reminder title. Body: the translation in quotes, a space, the
    /// reference, then "The story of its revelation: …" when the source gives a one-line summary
    /// in the reminder language. Arabic is added only when the lock-screen setting is off.
    public func ayah(setID: String, topicID: String, settings: ReminderSettings) throws -> ReminderText? {
        guard let set = try source.ayahSet(id: setID) else { return nil }
        let lang = settings.language
        let key = set.ayah

        let surahName = try source.surah(key.surah)?.nameTransliterated
        let reference = [surahName, key.description].compactMap { $0 }.joined(separator: " ")

        var lines: [String] = []
        if !settings.keepArabicOffLockScreen, let arabic = try source.ayah(key)?.arabic {
            lines.append(arabic)
        }
        if let t = try source.translation(for: key, language: lang, preferring: settings.preferredTranslations) {
            lines.append("\u{201C}\(t.text)\u{201D} \(reference)")
        } else {
            lines.append(reference)
        }
        if let story = set.story, let oneLine = story.oneLine, story.oneLineLanguage == lang {
            let line = String(format: localizer.string(ReminderStrings.storyOfRevelation, language: lang), oneLine)
            if (lines + [line]).joined(separator: "\n").count <= Self.fullDisplayLimit {
                lines.append(line)
            }
        }

        let title = TopicCatalog.topic(topicID).map { localizer.string($0.reminderTitle, language: lang) } ?? ""
        return ReminderText(
            title: title,
            body: lines.joined(separator: "\n"),
            threadID: topicID,
            category: ReminderCategory.ayah,
            userInfo: [
                ReminderUserInfo.kind: "ayah",
                ReminderUserInfo.ayahSetID: setID,
                ReminderUserInfo.ayahKey: key.description,
                ReminderUserInfo.topicID: topicID,
            ])
    }

    public func allRead(total: Int, settings: ReminderSettings) -> ReminderText {
        let lang = settings.language
        let number = NumberFormatter.localizedString(from: NSNumber(value: total), number: .none)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: lang)
        let localNumber = formatter.string(from: NSNumber(value: total)) ?? number
        let bodyKey = settings.frequency == .daily ? ReminderStrings.allReadBodyTomorrow : ReminderStrings.allReadBodyNext
        return ReminderText(
            title: String(format: localizer.string(ReminderStrings.allReadTitle, language: lang), localNumber),
            body: localizer.string(bodyKey, language: lang),
            threadID: "nasuha.allread",
            category: ReminderCategory.allRead,
            userInfo: [ReminderUserInfo.kind: "allRead"])
    }
}
