import Foundation
import GRDB

public enum ContentStoreError: Error, Equatable {
    case missingBundledDatabase
    case unsupportedSchema(found: Int, expected: Int)
}

/// Read-only access to the bundled nasuha.sqlite.
public final class ContentStore: Sendable {
    public static let schemaVersion = 1

    private let db: DatabaseQueue

    public init(path: String) throws {
        var config = Configuration()
        config.readonly = true
        config.label = "nasuha.content"
        db = try DatabaseQueue(path: path, configuration: config)
        let found = try db.read { try Int.fetchOne($0, sql: "SELECT value FROM meta WHERE key = 'schema_version'") } ?? 0
        guard found == Self.schemaVersion else {
            throw ContentStoreError.unsupportedSchema(found: found, expected: Self.schemaVersion)
        }
    }

    /// Opens nasuha.sqlite from the given bundle (the app bundle by default).
    public static func bundled(in bundle: Bundle = .main) throws -> ContentStore {
        guard let url = bundle.url(forResource: "nasuha", withExtension: "sqlite") else {
            throw ContentStoreError.missingBundledDatabase
        }
        return try ContentStore(path: url.path)
    }

    // MARK: Meta

    public func meta() throws -> ContentMeta {
        try db.read { db in
            var values: [String: String] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT key, value FROM meta") {
                values[row["key"]] = row["value"]
            }
            return ContentMeta(
                contentVersion: values["content_version"] ?? "",
                builtAt: values["built_at"] ?? "",
                values: values
            )
        }
    }

    // MARK: Qur'an

    public func surahs() throws -> [Surah] {
        try db.read { try Row.fetchAll($0, sql: "SELECT * FROM surah ORDER BY number").map(Self.surah) }
    }

    public func surah(_ number: Int) throws -> Surah? {
        try db.read { try Row.fetchOne($0, sql: "SELECT * FROM surah WHERE number = ?", arguments: [number]).map(Self.surah) }
    }

    public func ayahs(inSurah surah: Int) throws -> [Ayah] {
        try db.read {
            try Row.fetchAll($0, sql: "SELECT * FROM ayah WHERE surah = ? ORDER BY ayah", arguments: [surah]).map(Self.ayah)
        }
    }

    public func ayah(_ key: AyahKey) throws -> Ayah? {
        try db.read {
            try Row.fetchOne($0, sql: "SELECT * FROM ayah WHERE surah = ? AND ayah = ?", arguments: [key.surah, key.ayah]).map(Self.ayah)
        }
    }

    public func ayahs(_ keys: [AyahKey]) throws -> [Ayah] {
        try keys.compactMap { try ayah($0) }
    }

    /// Ayah keys from `from` to `to`, inclusive, inside one surah.
    public func range(_ from: AyahKey, through to: AyahKey) throws -> [AyahKey] {
        guard from.surah == to.surah, from.ayah <= to.ayah else { return [] }
        return (from.ayah...to.ayah).map { AyahKey(surah: from.surah, ayah: $0) }
    }

    public func exists(_ key: AyahKey) throws -> Bool {
        try db.read {
            try Bool.fetchOne($0, sql: "SELECT EXISTS(SELECT 1 FROM ayah WHERE surah = ? AND ayah = ?)", arguments: [key.surah, key.ayah]) ?? false
        }
    }

    // MARK: Translations

    public func translationSources() throws -> [TranslationSource] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM translation_source ORDER BY language, key").map {
                TranslationSource(key: $0["key"], language: $0["language"], title: $0["title"],
                                  version: $0["version"], lastUpdate: $0["last_update"])
            }
        }
    }

    /// Translations of `keys` in each of `sources`, in the order of `sources`.
    public func translations(for keys: [AyahKey], sources: [String]) throws -> [AyahKey: [Translation]] {
        guard !keys.isEmpty, !sources.isEmpty else { return [:] }
        return try db.read { db in
            var out: [AyahKey: [Translation]] = [:]
            for key in keys {
                var list: [Translation] = []
                for source in sources {
                    if let row = try Row.fetchOne(db, sql: """
                        SELECT * FROM translation WHERE source = ? AND surah = ? AND ayah = ?
                        """, arguments: [source, key.surah, key.ayah]) {
                        list.append(Self.translation(row))
                    }
                }
                out[key] = list
            }
            return out
        }
    }

    public func translations(inSurah surah: Int, source: String) throws -> [Int: Translation] {
        try db.read { db in
            var out: [Int: Translation] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT * FROM translation WHERE source = ? AND surah = ?", arguments: [source, surah]) {
                let t = Self.translation(row)
                out[t.key.ayah] = t
            }
            return out
        }
    }

    /// One translation of `key` in `language`, from the first of `preferring` that has it,
    /// else from any source in that language.
    public func translation(for key: AyahKey, language: String, preferring: [String] = []) throws -> Translation? {
        let inLanguage = try translationSources().filter { $0.language == language }.map(\.key)
        let ordered = preferring.filter(inLanguage.contains) + inLanguage.filter { !preferring.contains($0) }
        return try translations(for: [key], sources: ordered)[key]?.first
    }

    // MARK: Tafsir

    public func tafsir(for key: AyahKey, languages: [String]) throws -> [TafsirExcerpt] {
        guard !languages.isEmpty else { return [] }
        return try db.read { db in
            let marks = Array(repeating: "?", count: languages.count).joined(separator: ",")
            var args: [DatabaseValueConvertible] = [key.surah, key.ayah]
            args.append(contentsOf: languages)
            return try Row.fetchAll(db, sql: """
                SELECT * FROM tafsir WHERE surah = ? AND ayah = ? AND lang IN (\(marks)) ORDER BY book, lang
                """, arguments: StatementArguments(args)).map {
                TafsirExcerpt(book: $0["book"], language: $0["lang"], text: $0["text"], location: $0["location"])
            }
        }
    }

    // MARK: Curated sets

    /// Set IDs for one topic, in curated order.
    public func setIDs(topic: String) throws -> [String] {
        try db.read {
            try String.fetchAll($0, sql: "SELECT set_id FROM ayah_set_topic WHERE topic = ? ORDER BY position", arguments: [topic])
        }
    }

    /// Number of sets per topic. Topics with no sets are absent, and the app hides them.
    public func topicSetCounts() throws -> [String: Int] {
        try db.read { db in
            var out: [String: Int] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT topic, COUNT(*) AS n FROM ayah_set_topic GROUP BY topic") {
                out[row["topic"]] = row["n"]
            }
            return out
        }
    }

    public func ayahSet(id: String) throws -> AyahSet? {
        try db.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM ayah_set WHERE id = ?", arguments: [id]) else { return nil }
            let topics = try String.fetchAll(db, sql: "SELECT topic FROM ayah_set_topic WHERE set_id = ? ORDER BY topic", arguments: [id])
            let context = try Row.fetchAll(db, sql: "SELECT * FROM ayah_set_context WHERE set_id = ? ORDER BY role, position", arguments: [id])
            func ctx(_ role: String) -> [AyahKey] {
                context.filter { $0["role"] == role }.map { AyahKey(surah: $0["surah"], ayah: $0["ayah"]) }
            }
            let refs = try Row.fetchAll(db, sql: "SELECT * FROM source_ref WHERE set_id = ? ORDER BY block, position", arguments: [id])
            func refsFor(_ block: String) -> [SourceRef] { refs.filter { $0["block"] == block }.map(Self.sourceRef) }

            var story: Story?
            if row["has_story"] == true {
                let steps = try Row.fetchAll(db, sql: "SELECT * FROM story_step WHERE set_id = ? ORDER BY position", arguments: [id])
                    .map { StoryStep(text: $0["text"], language: $0["lang"]) }
                story = Story(steps: steps, oneLine: row["story_one_line"], oneLineLanguage: row["story_one_line_lang"], refs: refsFor("story"))
            }
            var when: RevelationInfo?
            if row["has_when"] == true {
                when = RevelationInfo(
                    place: (row["when_place"] as String?).flatMap(RevelationPlace.init(rawValue:)),
                    order: row["when_order"], periodText: row["when_period_text"],
                    ageMin: row["when_age_min"], ageMax: row["when_age_max"],
                    approx: row["when_approx"], scholarsDiffer: row["when_scholars_differ"],
                    refs: refsFor("when"))
            }
            return AyahSet(
                id: id, ayah: AyahKey(surah: row["surah"], ayah: row["ayah"]), topics: topics,
                before: ctx("before"), after: ctx("after"), story: story, when: when,
                tafsirRefs: refsFor("tafsir"), isSample: row["is_sample"])
        }
    }

    // MARK: Row mapping

    private static func surah(_ r: Row) -> Surah {
        Surah(number: r["number"], nameArabic: r["name_ar"], nameTransliterated: r["name_translit"],
              nameEnglish: r["name_en"], place: (r["place"] as String?).flatMap(RevelationPlace.init(rawValue:)),
              ayahCount: r["ayah_count"], revelationOrder: r["revelation_order"], bismillah: r["bismillah"])
    }

    private static func ayah(_ r: Row) -> Ayah {
        Ayah(key: AyahKey(surah: r["surah"], ayah: r["ayah"]), arabic: r["arabic"])
    }

    private static func translation(_ r: Row) -> Translation {
        Translation(sourceKey: r["source"], key: AyahKey(surah: r["surah"], ayah: r["ayah"]),
                    text: r["text"], footnotes: r["footnotes"])
    }

    private static func sourceRef(_ r: Row) -> SourceRef {
        SourceRef(book: r["book"], number: r["number"], numbering: r["numbering"], grade: r["grade"],
                  location: r["location"], ayah: r["ayah"], edition: r["edition"], page: r["page"])
    }
}
