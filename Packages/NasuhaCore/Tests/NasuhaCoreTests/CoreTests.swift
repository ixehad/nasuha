import SwiftData
import XCTest
@testable import NasuhaCore

final class AyahKeyTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(AyahKey("93:3"), AyahKey(surah: 93, ayah: 3))
        XCTAssertEqual(AyahKey(" 2 : 255 ")?.description, "2:255")
        XCTAssertNil(AyahKey("115:1"))
        XCTAssertNil(AyahKey("93"))
        XCTAssertNil(AyahKey("93:0"))
        XCTAssertNil(AyahKey("a:b"))
    }

    func testEveryAyahStemAndOrder() {
        XCTAssertEqual(AyahKey(surah: 93, ayah: 3).everyAyahStem, "093003")
        XCTAssertLessThan(AyahKey(surah: 2, ayah: 286), AyahKey(surah: 3, ayah: 1))
    }
}

final class TopicCatalogTests: XCTestCase {
    func testTwentyNineTopicsInSixGroups() {
        XCTAssertEqual(TopicCatalog.groups.count, 6)
        XCTAssertEqual(TopicCatalog.all.count, 29)
        XCTAssertEqual(Set(TopicCatalog.all.map(\.id)).count, 29, "ids are unique")
        XCTAssertNotNil(TopicCatalog.topic(TopicCatalog.ramadanTopicID))
        XCTAssertEqual(TopicCatalog.groups.filter { $0.note != nil }.map(\.id), ["special"])
    }
}

final class PaletteTests: XCTestCase {
    /// WCAG AA: 4.5:1 for body text.
    func testTextPairsMeetAA() {
        let pairs: [(PaletteToken, PaletteToken)] = [
            (.ink, .bg), (.ink, .surface), (.ink, .fill), (.ink2, .bg), (.ink2, .surface),
            (.muted, .bg), (.muted, .surface), (.muted, .fill),
            (.accent, .bg), (.accent, .surface), (.onAccent, .accent),
            (.tintInk, .tint), (.ink, .tint),
            (.dawnInk, .dawnTint), (.ink, .dawnTint),
            (.beforeInk, .before), (.ink, .before),
        ]
        for (fg, bg) in pairs {
            let light = ColorMath.contrast(fg.light, bg.light)
            let dark = ColorMath.contrast(fg.dark, bg.dark)
            XCTAssertGreaterThanOrEqual(light, 4.5, "\(fg) on \(bg), light: \(light)")
            XCTAssertGreaterThanOrEqual(dark, 4.5, "\(fg) on \(bg), dark: \(dark)")
        }
    }

    func testMath() {
        XCTAssertEqual(ColorMath.contrast(0x000000, 0xFFFFFF), 21, accuracy: 0.01)
    }
}

@MainActor
final class UserModelTests: XCTestCase {
    func testDefaults() throws {
        let container = try NasuhaSchema.container(inMemory: true)
        let ctx = container.mainContext
        let s = try UserSettings.current(in: ctx)
        XCTAssertTrue(s.keepArabicOffLockScreen, "Arabic stays off the lock screen by default")
        XCTAssertEqual(s.frequency, .daily)
        XCTAssertEqual(s.appearance, .system)
        XCTAssertFalse(s.hasCompletedSetup)
        XCTAssertEqual(s.hijriOffset, 0)
        XCTAssertNil(s.reciterID)
        // Single record
        XCTAssertTrue(try UserSettings.current(in: ctx) === s)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<UserSettings>()), 1)
    }

    func testHijriOffsetIsClamped() throws {
        let s = UserSettings()
        s.setHijriOffset(5); XCTAssertEqual(s.hijriOffset, 2)
        s.setHijriOffset(-9); XCTAssertEqual(s.hijriOffset, -2)
        s.setHijriOffset(1); XCTAssertEqual(s.hijriOffset, 1)
    }

    func testReadRecordsAndSavesAreUnique() throws {
        let container = try NasuhaSchema.container(inMemory: true)
        let ctx = container.mainContext
        ctx.insert(ReadRecord(ayahSetID: "a"))
        ctx.insert(SavedAyah(ayahKey: "93:3"))
        try ctx.save()
        ctx.insert(ReadRecord(ayahSetID: "a"))
        try ctx.save()
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<ReadRecord>()), 1, "unique id upserts")
    }

    func testProgress() throws {
        let container = try NasuhaSchema.container(inMemory: true)
        let ctx = container.mainContext
        let p = try ReadingProgress.current(in: ctx)
        p.markOpened(surah: 93); p.markOpened(surah: 93); p.markOpened(surah: 1)
        XCTAssertEqual(p.surahsOpened, [93, 1])
        XCTAssertEqual(p.lastSurah, 1)
    }
}
