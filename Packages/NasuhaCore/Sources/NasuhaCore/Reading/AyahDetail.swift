import Foundation

/// Where an ayah sits relative to the one being read.
public enum ContextRole: String, Sendable {
    case before, today, after
}

/// One ayah in the "ayahs around it" list.
public struct ContextRow: Hashable, Sendable, Identifiable {
    public var id: AyahKey { key }
    public let key: AyahKey
    public let role: ContextRole
    public let arabic: String
    public let translations: [Translation]
}

/// A translation together with the source it came from.
public struct SourcedTranslation: Hashable, Sendable, Identifiable {
    public var id: String { source.key }
    public let source: TranslationSource
    public let translation: Translation
}

/// Everything the Ayah screen shows for one curated set. Every string is read
/// from the content database; nothing is written or shortened here.
public struct AyahDetail: Hashable, Sendable, Identifiable {
    public var id: String { ayahSet.id }
    public let ayahSet: AyahSet
    public let surah: Surah?
    public let arabic: String
    public let translations: [SourcedTranslation]
    /// Up to two ayahs before and two after, in reading order, with today's in the middle.
    public let near: [ContextRow]
    /// A wider range in the same surah. Equal to `near` when there is nothing more to show.
    public let more: [ContextRow]
    /// Story steps in one language. Empty when the set has no story.
    public let storySteps: [StoryStep]
    /// The one-line summary, only when the source gives one in a reading language.
    public let oneLine: String?
    public let tafsir: [TafsirExcerpt]
    public let contentVersion: String
    public let textCredit: String?

    public var reference: String {
        [surah?.nameTransliterated, ayahSet.ayah.description].compactMap { $0 }.joined(separator: " ")
    }

    public var place: RevelationPlace? { ayahSet.when?.place ?? surah?.place }

    public var hasMoreContext: Bool { more.count > near.count }
}

public struct AyahDetailLoader {
    /// How far "Show more" reaches on each side of today's ayah.
    public static let wideReach = 5

    private let store: ContentStore

    public init(store: ContentStore) {
        self.store = store
    }

    /// The translation sources to read with: the user's choices that exist in the
    /// database, in their order. Falls back to the first English source, then to any.
    public func resolveSources(preferred: [String]) throws -> [TranslationSource] {
        let all = try store.translationSources()
        let chosen = preferred.compactMap { key in all.first { $0.key == key } }
        if !chosen.isEmpty { return chosen }
        if let english = all.first(where: { $0.language == "en" }) { return [english] }
        return Array(all.prefix(1))
    }

    /// `extraTafsirLanguages` adds explanations in languages that have no chosen translation, such as Arabic.
    public func load(setID: String, preferredTranslations: [String], extraTafsirLanguages: [String] = []) throws -> AyahDetail? {
        guard let set = try store.ayahSet(id: setID), let ayah = try store.ayah(set.ayah) else { return nil }
        let sources = try resolveSources(preferred: preferredTranslations)
        let sourceKeys = sources.map(\.key)
        let languages = sources.map(\.language)
        let surah = try store.surah(set.ayah.surah)

        let nearKeys = Array(set.before.suffix(2)) + [set.ayah] + Array(set.after.prefix(2))
        var wideKeys = set.before + [set.ayah] + set.after
        if let surah {
            let known = wideKeys.filter { $0.surah == set.ayah.surah }.map(\.ayah)
            let low = max(1, min(known.min() ?? set.ayah.ayah, set.ayah.ayah - Self.wideReach))
            let high = min(surah.ayahCount, max(known.max() ?? set.ayah.ayah, set.ayah.ayah + Self.wideReach))
            let range = (low...high).map { AyahKey(surah: set.ayah.surah, ayah: $0) }
            wideKeys = wideKeys.filter { $0.surah != set.ayah.surah && $0 < set.ayah }
                + range
                + wideKeys.filter { $0.surah != set.ayah.surah && $0 > set.ayah }
        }

        let allKeys = Array(Set(nearKeys + wideKeys))
        let texts = try store.translations(for: allKeys, sources: sourceKeys)
        func rows(_ keys: [AyahKey]) throws -> [ContextRow] {
            try keys.compactMap { key in
                guard let a = try store.ayah(key) else { return nil }
                let role: ContextRole = key == set.ayah ? .today : (key < set.ayah ? .before : .after)
                return ContextRow(key: key, role: role, arabic: a.arabic, translations: texts[key] ?? [])
            }
        }

        let translations: [SourcedTranslation] = (texts[set.ayah] ?? []).compactMap { t in
            sources.first { $0.key == t.sourceKey }.map { SourcedTranslation(source: $0, translation: t) }
        }

        var steps: [StoryStep] = []
        var oneLine: String?
        if let story = set.story {
            let available = story.steps.map(\.language)
            let language = languages.first(where: available.contains) ?? available.first
            steps = story.steps.filter { $0.language == language }
            if let line = story.oneLine, let lineLanguage = story.oneLineLanguage, languages.contains(lineLanguage) {
                oneLine = line
            }
        }

        let meta = try store.meta()
        return AyahDetail(
            ayahSet: set, surah: surah, arabic: ayah.arabic, translations: translations,
            near: try rows(nearKeys), more: try rows(wideKeys),
            storySteps: steps, oneLine: oneLine,
            tafsir: try store.tafsir(for: set.ayah, languages: Array(Set(languages + extraTafsirLanguages))),
            contentVersion: meta.contentVersion, textCredit: meta.values["tanzil_credit"])
    }
}

public extension SourceRef {
    /// "Sahih al-Bukhari 4950 (sahih)" or "Tafsir Ibn Kathir, 93:1–3".
    var display: String {
        var out = book
        if let number, !number.isEmpty { out += " \(number)" }
        if let location, !location.isEmpty { out += ", \(location)" }
        if let ayah, !ayah.isEmpty { out += ", \(ayah)" }
        if let page, !page.isEmpty { out += ", p. \(page)" }
        if let grade, !grade.isEmpty { out += " (\(grade))" }
        return out
    }

    /// True for hadith references, which carry a collection number.
    var isNumbered: Bool { !(number ?? "").isEmpty }
}

public extension RevelationInfo {
    /// "40" or "40–41". Nil when the set gives no age.
    var ageText: String? {
        switch (ageMin, ageMax) {
        case let (min?, max?): min == max ? "\(min)" : "\(min)\u{2013}\(max)"
        case let (value?, nil), let (nil, value?): "\(value)"
        default: nil
        }
    }
}
