import XCTest
@testable import NasuhaCore

/// Reads Fixtures/content-fixture.sqlite, built by tools/tests (placeholder strings only).
final class ContentStoreTests: XCTestCase {
    var store: ContentStore!

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "content-fixture", withExtension: "sqlite", subdirectory: "Fixtures"))
        store = try ContentStore(path: url.path)
    }

    func testMeta() throws {
        let meta = try store.meta()
        XCTAssertFalse(meta.contentVersion.isEmpty)
        XCTAssertEqual(meta.values["schema_version"], "1")
    }

    func testSurahsAndAyahs() throws {
        let surahs = try store.surahs()
        XCTAssertEqual(surahs.map(\.number), [1, 2])
        let two = try XCTUnwrap(store.surah(2))
        XCTAssertEqual(two.place, .madinah)
        XCTAssertEqual(two.ayahCount, 5)
        XCTAssertEqual(two.revelationOrder, 87)
        XCTAssertEqual(two.bismillah, "FIXTURE BISMILLAH")
        XCTAssertNil(try store.surah(1)?.bismillah)
        XCTAssertEqual(try store.ayahs(inSurah: 2).count, 5)
        XCTAssertEqual(try store.ayah(AyahKey(surah: 2, ayah: 3))?.arabic, "FIXTURE 2:3")
        XCTAssertTrue(try store.exists(AyahKey(surah: 1, ayah: 3)))
        XCTAssertFalse(try store.exists(AyahKey(surah: 1, ayah: 4)))
    }

    func testTranslationsKeepSourceOrderAndVersion() throws {
        let sources = try store.translationSources()
        XCTAssertEqual(Set(sources.map(\.key)), ["fixture_en", "fixture_bn"])
        XCTAssertEqual(sources.first { $0.key == "fixture_en" }?.version, "9.9.9")
        let key = AyahKey(surah: 2, ayah: 3)
        let t = try store.translations(for: [key], sources: ["fixture_bn", "fixture_en"])
        XCTAssertEqual(t[key]?.map(\.text), ["FIXTURE bn 2:3", "FIXTURE en 2:3"])
        XCTAssertNil(t[key]?.first?.footnotes, "empty footnotes are stored as nil")
        XCTAssertEqual(try store.translations(inSurah: 1, source: "fixture_en").count, 3)
    }

    func testAyahSetWithStoryAndWhen() throws {
        let set = try XCTUnwrap(store.ayahSet(id: "fixture-2-3"))
        XCTAssertEqual(set.ayah, AyahKey(surah: 2, ayah: 3))
        XCTAssertEqual(set.topics, ["hope", "why"])
        XCTAssertEqual(set.before.map(\.description), ["2:1", "2:2"])
        XCTAssertEqual(set.after.map(\.description), ["2:4", "2:5"])
        XCTAssertFalse(set.isSample)
        let story = try XCTUnwrap(set.story)
        XCTAssertEqual(story.steps.map(\.text), ["FIXTURE STEP 1", "FIXTURE STEP 2"])
        XCTAssertEqual(story.oneLine, "FIXTURE ONE LINE")
        XCTAssertEqual(story.refs.first?.book, "Sahih al-Bukhari")
        XCTAssertEqual(story.refs.first?.grade, "sahih")
        XCTAssertEqual(story.refs.first?.numbering, "sunnah.com")
        let when = try XCTUnwrap(set.when)
        XCTAssertEqual(when.place, .madinah)
        XCTAssertEqual(when.ageMin, 53)
        XCTAssertTrue(when.approx)
        XCTAssertTrue(when.scholarsDiffer)
        XCTAssertEqual(when.refs.first?.book, "Tafsir Ibn Kathir")
        XCTAssertEqual(set.tafsirRefs.first?.book, "Al-Mukhtasar fi Tafsir al-Qur'an", "aliases are stored canonical")
    }

    func testAyahSetWithoutStoryShowsNothing() throws {
        let set = try XCTUnwrap(store.ayahSet(id: "fixture-1-2"))
        XCTAssertNil(set.story)
        XCTAssertNil(set.when)
        XCTAssertTrue(set.tafsirRefs.isEmpty)
        XCTAssertNil(try store.ayahSet(id: "nope"))
    }

    func testTopicsInCuratedOrderAndHiddenWhenEmpty() throws {
        XCTAssertEqual(try store.setIDs(topic: "hope"), ["fixture-2-3", "fixture-1-2"])
        let counts = try store.topicSetCounts()
        XCTAssertEqual(counts["hope"], 2)
        XCTAssertNil(counts["grief"])
        let groups = TopicCatalog.available(setCounts: counts)
        XCTAssertEqual(groups.flatMap(\.topics).map(\.id).sorted(), ["hope", "mercy", "why"])
        XCTAssertFalse(groups.contains { $0.topics.isEmpty })
    }

    func testSampleFlag() throws {
        XCTAssertEqual(try store.ayahSet(id: "sample-2-4")?.isSample, true)
    }

    func testTafsir() throws {
        let t = try store.tafsir(for: AyahKey(surah: 2, ayah: 3), languages: ["en"])
        XCTAssertEqual(Set(t.map(\.book)), ["Al-Mukhtasar fi Tafsir al-Qur'an", "Tafsir as-Sa'di"])
        XCTAssertTrue(try store.tafsir(for: AyahKey(surah: 2, ayah: 3), languages: ["bn"]).isEmpty)
    }

    func testMissingBundledDatabase() {
        XCTAssertThrowsError(try ContentStore.bundled(in: Bundle(for: Self.self))) {
            XCTAssertEqual($0 as? ContentStoreError, .missingBundledDatabase)
        }
    }
}
