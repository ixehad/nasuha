import Foundation

// Read-only content, as stored in nasuha.sqlite by tools/build_content.py.
// None of this text is written in the app: every string comes from a source
// file under content-src/ (see CONTENT-POLICY.md).

public enum RevelationPlace: String, Codable, Sendable {
    case makkah, madinah
}

public struct Surah: Hashable, Sendable, Identifiable {
    public var id: Int { number }
    public let number: Int
    public let nameArabic: String
    public let nameTransliterated: String
    public let nameEnglish: String
    public let place: RevelationPlace?
    public let ayahCount: Int
    /// Position in the 1924 Cairo mushaf chronology. Nil when not loaded.
    public let revelationOrder: Int?
    /// The bismillah line as Tanzil gives it, when the surah has one before ayah 1.
    public let bismillah: String?
}

public struct Ayah: Hashable, Sendable, Identifiable {
    public var id: AyahKey { key }
    public let key: AyahKey
    /// Tanzil Uthmani text, unchanged.
    public let arabic: String
}

public struct TranslationSource: Hashable, Sendable, Identifiable {
    public var id: String { key }
    /// QuranEnc key, e.g. "english_saheeh".
    public let key: String
    /// ISO 639-1 code, e.g. "en", "bn".
    public let language: String
    public let title: String
    /// QuranEnc version, shown in the app next to the translation.
    public let version: String
    public let lastUpdate: String?
}

public struct Translation: Hashable, Sendable {
    public let sourceKey: String
    public let key: AyahKey
    public let text: String
    public let footnotes: String?
}

/// One reference to a source book. Hadith refs carry a number (sunnah.com
/// numbering) and a grade; tafsir refs carry a location.
public struct SourceRef: Hashable, Sendable {
    public let book: String
    public let number: String?
    public let numbering: String?
    public let grade: String?
    public let location: String?
    public let ayah: String?
    public let edition: String?
    public let page: String?
}

public struct StoryStep: Hashable, Sendable {
    public let text: String
    public let language: String
}

public struct Story: Hashable, Sendable {
    public let steps: [StoryStep]
    /// Only present when the source itself gives a one-line summary.
    public let oneLine: String?
    public let refs: [SourceRef]
}

public struct RevelationInfo: Hashable, Sendable {
    public let place: RevelationPlace?
    public let order: Int?
    public let periodText: String?
    public let ageMin: Int?
    public let ageMax: Int?
    /// Always true for ages and dates. The UI shows "approx." when set.
    public let approx: Bool
    public let scholarsDiffer: Bool
    public let refs: [SourceRef]
}

public struct TafsirExcerpt: Hashable, Sendable {
    public let book: String
    public let language: String
    public let text: String
    public let location: String?
}

/// A curated set: one ayah with its context, story and timing.
public struct AyahSet: Hashable, Sendable, Identifiable {
    public let id: String
    public let ayah: AyahKey
    public let topics: [String]
    public let before: [AyahKey]
    public let after: [AyahKey]
    public let story: Story?
    public let when: RevelationInfo?
    public let tafsirRefs: [SourceRef]
    /// True for sets loaded from content-src/sample/. These must be replaced from source before release.
    public let isSample: Bool
}

public struct ContentMeta: Hashable, Sendable {
    public let contentVersion: String
    public let builtAt: String
    public let values: [String: String]
}
