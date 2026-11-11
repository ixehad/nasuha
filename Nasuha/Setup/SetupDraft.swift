import NasuhaCore
import SwiftData
import SwiftUI

/// Screens pushed from Home: the two setup steps and the Qur'an reader.
enum AppRoute: Hashable {
    case topics
    case time
    case reader(ReaderTarget)
}

/// Choices made on the setup screens, kept until "Start my daily ayah" saves them.
@Observable
final class SetupDraft {
    /// Topic IDs in the order they were picked.
    var topics: [String] = []
    var time = ClockTime(hour24: 7, minute: 30)
    var frequency: ReminderFrequency = .daily
    var readingTranslations: [String] = []
    var reminderLanguage = "en"
    /// True when changing an existing setup.
    var isEditing = false

    /// Translations in the content database, for the "Read in" choice.
    private(set) var sources: [TranslationSource] = []

    /// Languages reminders can be written in: those with a translation in the database.
    var reminderLanguages: [String] {
        var seen: [String] = []
        for source in sources where !seen.contains(source.language) { seen.append(source.language) }
        return seen
    }

    @MainActor
    func load(from context: ModelContext, store: ContentStore?) {
        let settings = try? UserSettings.current(in: context)
        let choices = (try? context.fetch(FetchDescriptor<TopicChoice>(sortBy: [SortDescriptor(\.order)]))) ?? []
        sources = (try? store?.translationSources()) ?? []
        let available = Set(TopicCatalog.available(setCounts: (try? store?.topicSetCounts()) ?? [:]).flatMap(\.topics).map(\.id))

        topics = choices.map(\.topicID).filter(available.contains)
        time = ClockTime(hour24: settings?.reminderHour ?? 7, minute: settings?.reminderMinute ?? 30)
        frequency = settings?.frequency ?? .daily
        isEditing = settings?.hasCompletedSetup ?? false

        let keys = Set(sources.map(\.key))
        readingTranslations = (settings?.readingTranslations ?? []).filter(keys.contains)
        if readingTranslations.isEmpty, let store,
           let fallback = try? AyahDetailLoader(store: store).resolveSources(preferred: []) {
            readingTranslations = fallback.map(\.key)
        }
        let language = settings?.reminderLanguage ?? "en"
        reminderLanguage = reminderLanguages.contains(language) ? language : (reminderLanguages.first ?? language)
    }

    func toggle(topic id: String) {
        if let index = topics.firstIndex(of: id) {
            topics.remove(at: index)
        } else {
            topics.append(id)
        }
    }

    func toggle(translation key: String) {
        if let index = readingTranslations.firstIndex(of: key) {
            // Keep at least one translation.
            if readingTranslations.count > 1 { readingTranslations.remove(at: index) }
        } else {
            readingTranslations.append(key)
        }
    }

    /// Saves the choices on this phone.
    @MainActor
    func commit(to context: ModelContext) throws {
        let settings = try UserSettings.current(in: context)
        settings.reminderHour = time.hour24
        settings.reminderMinute = time.minute
        settings.frequency = frequency
        if !readingTranslations.isEmpty { settings.readingTranslations = readingTranslations }
        settings.reminderLanguage = reminderLanguage
        settings.hasCompletedSetup = true

        let existing = try context.fetch(FetchDescriptor<TopicChoice>())
        for choice in existing where !topics.contains(choice.topicID) { context.delete(choice) }
        for (order, id) in topics.enumerated() {
            if let choice = existing.first(where: { $0.topicID == id }) {
                choice.order = order
            } else {
                context.insert(TopicChoice(topicID: id, order: order))
            }
        }
        try context.save()
    }
}

/// The name a language calls itself.
enum LanguageName {
    static func autonym(_ code: String) -> String {
        Locale(identifier: code).localizedString(forLanguageCode: code)?.capitalized(with: Locale(identifier: code)) ?? code
    }
}
