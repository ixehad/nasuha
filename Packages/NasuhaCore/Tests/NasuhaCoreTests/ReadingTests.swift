import XCTest
@testable import NasuhaCore

/// Reads Fixtures/content-fixture.sqlite (placeholder strings only).
final class AyahDetailTests: XCTestCase {
    var store: ContentStore!
    var loader: AyahDetailLoader!

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "content-fixture", withExtension: "sqlite", subdirectory: "Fixtures"))
        store = try ContentStore(path: url.path)
        loader = AyahDetailLoader(store: store)
    }

    func testLoadsAyahWithChosenTranslationsInOrder() throws {
        let detail = try XCTUnwrap(loader.load(setID: "fixture-2-3", preferredTranslations: ["fixture_bn", "fixture_en"]))
        XCTAssertEqual(detail.ayahSet.ayah, AyahKey(surah: 2, ayah: 3))
        XCTAssertEqual(detail.translations.map(\.source.key), ["fixture_bn", "fixture_en"])
        XCTAssertEqual(detail.translations.map(\.translation.text), ["FIXTURE bn 2:3", "FIXTURE en 2:3"])
        XCTAssertEqual(detail.reference, "Fixture-Two 2:3")
        XCTAssertEqual(detail.place, .madinah)
        XCTAssertFalse(detail.contentVersion.isEmpty)
    }

    func testUnknownTranslationFallsBackToEnglish() throws {
        let detail = try XCTUnwrap(loader.load(setID: "fixture-2-3", preferredTranslations: ["english_saheeh"]))
        XCTAssertEqual(detail.translations.map(\.source.key), ["fixture_en"])
        XCTAssertEqual(try loader.resolveSources(preferred: []).map(\.key), ["fixture_en"])
    }

    func testContextKeepsTodayInTheMiddle() throws {
        let detail = try XCTUnwrap(loader.load(setID: "fixture-2-3", preferredTranslations: ["fixture_en"]))
        XCTAssertEqual(detail.near.map(\.key.description), ["2:1", "2:2", "2:3", "2:4", "2:5"])
        XCTAssertEqual(detail.near.map(\.role), [.before, .before, .today, .after, .after])
        XCTAssertEqual(detail.near[0].translations.map(\.text), ["FIXTURE en 2:1"])
        // The surah has five ayahs, so there is nothing more to show.
        XCTAssertFalse(detail.hasMoreContext)
    }

    func testShowMoreStaysInsideTheSurah() throws {
        let detail = try XCTUnwrap(loader.load(setID: "fixture-1-2", preferredTranslations: ["fixture_en"]))
        XCTAssertEqual(detail.near.map(\.key.description), ["1:1", "1:2", "1:3"])
        XCTAssertEqual(detail.more.map(\.key.description), ["1:1", "1:2", "1:3"])
        XCTAssertEqual(detail.more.filter { $0.role == .today }.count, 1)
    }

    func testStoryInAReadingLanguage() throws {
        let detail = try XCTUnwrap(loader.load(setID: "fixture-2-3", preferredTranslations: ["fixture_en"]))
        XCTAssertEqual(detail.storySteps.map(\.text), ["FIXTURE STEP 1", "FIXTURE STEP 2"])
        XCTAssertEqual(detail.oneLine, "FIXTURE ONE LINE")
        XCTAssertFalse(detail.tafsir.isEmpty)
    }

    func testOneLineHiddenWhenNotInAReadingLanguage() throws {
        let detail = try XCTUnwrap(loader.load(setID: "fixture-2-3", preferredTranslations: ["fixture_bn"]))
        XCTAssertNil(detail.oneLine, "an English summary is not shown as if it were Bangla")
        // The story itself is still shown, in the language the source has.
        XCTAssertEqual(detail.storySteps.map(\.language), ["en", "en"])
    }

    func testSetWithoutStoryShowsNothing() throws {
        let detail = try XCTUnwrap(loader.load(setID: "fixture-1-2", preferredTranslations: ["fixture_en"]))
        XCTAssertTrue(detail.storySteps.isEmpty)
        XCTAssertNil(detail.oneLine)
        XCTAssertNil(detail.ayahSet.when)
    }

    func testMissingSetIsNil() throws {
        XCTAssertNil(try loader.load(setID: "nope", preferredTranslations: []))
    }

    func testSourceRefDisplay() throws {
        let set = try XCTUnwrap(store.ayahSet(id: "fixture-2-3"))
        XCTAssertEqual(set.story?.refs.first?.display, "Sahih al-Bukhari 0000 (sahih)")
        XCTAssertEqual(set.story?.refs.first?.isNumbered, true)
        XCTAssertEqual(set.when?.refs.first?.display, "Tafsir Ibn Kathir, 2:3")
        XCTAssertEqual(set.when?.refs.first?.isNumbered, false)
    }

    func testAgeText() throws {
        let when = try XCTUnwrap(store.ayahSet(id: "fixture-2-3")?.when)
        XCTAssertEqual(when.ageText, "53\u{2013}54")
        let single = RevelationInfo(place: nil, order: nil, periodText: nil, ageMin: 40, ageMax: 40,
                                    approx: true, scholarsDiffer: false, refs: [])
        XCTAssertEqual(single.ageText, "40")
        let none = RevelationInfo(place: nil, order: nil, periodText: nil, ageMin: nil, ageMax: nil,
                                  approx: true, scholarsDiffer: false, refs: [])
        XCTAssertNil(none.ageText)
    }
}

final class TopicReadingTests: XCTestCase {
    let ids = ["a", "b", "c"]

    func testCurrentIsFirstUnread() {
        XCTAssertEqual(TopicReading.current(in: ids, read: []), "a")
        XCTAssertEqual(TopicReading.current(in: ids, read: ["a"]), "b")
        XCTAssertEqual(TopicReading.current(in: ids, read: ["a", "b", "c"]), "a", "all read: back to the first")
        XCTAssertNil(TopicReading.current(in: [], read: []))
    }

    func testNextSkipsReadAndStopsAtTheEnd() {
        XCTAssertEqual(TopicReading.next(after: "a", in: ids, read: ["a"]), "b")
        XCTAssertEqual(TopicReading.next(after: "a", in: ids, read: ["a", "b"]), "c")
        XCTAssertNil(TopicReading.next(after: "c", in: ids, read: ["c"]))
        XCTAssertNil(TopicReading.next(after: "x", in: ids, read: []))
    }

    func testHomeShowsTodaysAyahForItsTopic() {
        var state = ReminderState()
        state.currentSetID = "b"
        state.currentTopicID = "hope"
        XCTAssertEqual(TopicReading.homeSet(topic: "hope", state: state, setIDs: ids, read: []), "b")
        XCTAssertEqual(TopicReading.homeSet(topic: "mercy", state: state, setIDs: ids, read: ["a"]), "b")
        XCTAssertEqual(TopicReading.homeSet(topic: "mercy", state: state, setIDs: ["x", "y"], read: []), "x")
        // Today's ayah is no longer in the topic: fall back to the topic's own order.
        XCTAssertEqual(TopicReading.homeSet(topic: "hope", state: state, setIDs: ["x", "y"], read: ["x"]), "y")
    }
}

final class ClockTimeTests: XCTestCase {
    func testTwentyFourHourRoundTrip() {
        for hour in 0..<24 {
            let time = ClockTime(hour24: hour, minute: 15)
            XCTAssertEqual(time.hour24, hour)
            XCTAssertTrue((1...12).contains(time.hour))
        }
    }

    func testMidnightAndNoon() {
        XCTAssertEqual(ClockTime(hour24: 0, minute: 0), ClockTime(hour: 12, minute: 0, isPM: false))
        XCTAssertEqual(ClockTime(hour24: 12, minute: 0), ClockTime(hour: 12, minute: 0, isPM: true))
        XCTAssertEqual(ClockTime(hour: 12, minute: 0, isPM: false).hour24, 0)
        XCTAssertEqual(ClockTime(hour: 12, minute: 0, isPM: true).hour24, 12)
        XCTAssertEqual(ClockTime(hour: 7, minute: 30, isPM: true).hour24, 19)
    }

    func testDialHasTwelveHoursAtThirtyDegreeSteps() {
        XCTAssertEqual(Set(ClockTime.dialHours), Set(1...12))
        XCTAssertEqual(ClockTime.angle(forHour: 12), -90, "12 is at the top")
        XCTAssertEqual(ClockTime.angle(forHour: 3), 0, "3 is on the right")
        XCTAssertEqual(ClockTime.angle(forHour: 6), 90)
        XCTAssertEqual(ClockTime.angle(forHour: 9), 180)
    }

    func testMinuteChoices() {
        XCTAssertEqual(ClockTime.minuteChoices, [0, 15, 30, 45])
    }
}
