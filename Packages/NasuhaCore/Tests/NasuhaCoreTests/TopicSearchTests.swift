import XCTest
@testable import NasuhaCore

final class TopicSearchTests: XCTestCase {
    private let groups = [
        TopicGroup(id: "a", title: "A", note: nil, topics: [
            Topic(id: "hope", label: "Hope", reminderTitle: "Ayah of hope"),
            Topic(id: "dua", label: "Du'as of the Qur'an"),
            Topic(id: "tawheed", label: "Oneness of Allah (Tawheed)", isFeatured: false),
        ]),
    ]

    private func ids(_ query: String, name: (Topic) -> String = { $0.label }) -> [String] {
        TopicSearch.matches(query, in: groups, name: name).map(\.id)
    }

    func testEmptySearchFindsNothing() {
        XCTAssertEqual(ids(""), [])
        XCTAssertEqual(ids("   "), [])
    }

    func testIgnoresCaseAndPunctuation() {
        XCTAssertEqual(ids("HOPE"), ["hope"])
        XCTAssertEqual(ids("quran"), ["dua"])
        XCTAssertEqual(ids("duas"), ["dua"])
    }

    func testEveryWordMustMatch() {
        XCTAssertEqual(ids("oneness allah"), ["tawheed"])
        XCTAssertEqual(ids("oneness hope"), [])
    }

    func testMatchesTheShownNameOrTheEnglishName() {
        let bangla: (Topic) -> String = { $0.id == "hope" ? "আশা" : $0.label }
        XCTAssertEqual(ids("আশা", name: bangla), ["hope"])
        XCTAssertEqual(ids("hope", name: bangla), ["hope"])
    }

    func testFeaturedFlagAndDefaultReminderTitle() {
        let all = groups[0].topics
        XCTAssertTrue(all[0].isFeatured)
        XCTAssertFalse(all[2].isFeatured)
        XCTAssertEqual(all[1].reminderTitle, "Du'as of the Qur'an")
        XCTAssertEqual(groups[0].keeping(\.isFeatured)?.topics.map(\.id), ["hope", "dua"])
        XCTAssertNil(groups[0].keeping { _ in false })
    }
}
