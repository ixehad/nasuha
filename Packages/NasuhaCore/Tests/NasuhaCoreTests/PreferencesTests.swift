import XCTest
@testable import NasuhaCore

final class TextSizeTests: XCTestCase {
    func testShiftMovesWithinTheList() {
        XCTAssertEqual(TextSizeStep.standard.shifted(3, count: 12), 3)
        XCTAssertEqual(TextSizeStep.large.shifted(3, count: 12), 4)
        XCTAssertEqual(TextSizeStep.larger.shifted(3, count: 12), 5)
        XCTAssertEqual(TextSizeStep.small.shifted(3, count: 12), 2)
    }

    func testShiftStopsAtTheEnds() {
        XCTAssertEqual(TextSizeStep.small.shifted(0, count: 12), 0)
        XCTAssertEqual(TextSizeStep.larger.shifted(11, count: 12), 11)
        XCTAssertEqual(TextSizeStep.larger.shifted(0, count: 0), 0)
    }
}

final class PauseLengthTests: XCTestCase {
    func testResumesAtTheStartOfTheDayAfterThePause() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Dhaka"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 21, minute: 15)))
        let resume = PauseLength.threeDays.resumeDate(from: now, calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day, .hour, .minute], from: resume),
                       DateComponents(year: 2026, month: 11, day: 15, hour: 0, minute: 0))
        XCTAssertEqual(PauseLength.allCases.map(\.rawValue), [1, 3, 7])
    }

    func testPausedRemindersSkipThePause() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Dhaka"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 21)))
        let settings = ReminderSettings(topics: ["hope"], hour: 7, minute: 30,
                                        pausedUntil: PauseLength.oneWeek.resumeDate(from: now, calendar: calendar))
        let first = try XCTUnwrap(ReminderSchedule.fireDates(after: now, settings: settings, count: 1, calendar: calendar).first)
        XCTAssertEqual(calendar.dateComponents([.month, .day, .hour, .minute], from: first),
                       DateComponents(month: 11, day: 19, hour: 7, minute: 30))
    }
}

final class MistakeReportTests: XCTestCase {
    private let issues = URL(string: "https://example.org/project/issues")!
    private let details = MistakeReport.Details(ayahKey: "93:3", setID: "duha-93-3",
                                                contentVersion: "2026.11.11-abc", appVersion: "1.0")

    func testBodyNamesTheAyahAndVersionsOnly() {
        let body = MistakeReport.body(details)
        XCTAssertTrue(body.contains("Ayah: 93:3"))
        XCTAssertTrue(body.contains("Ayah ID: duha-93-3"))
        XCTAssertTrue(body.contains("Content version: 2026.11.11-abc"))
        XCTAssertTrue(body.contains("App version: 1.0"))
        XCTAssertEqual(MistakeReport.subject(details), "Mistake report: 93:3")
    }

    func testEmailLinkWhenAnAddressIsSet() throws {
        let url = try XCTUnwrap(MistakeReport.url(details, email: "help@example.org", issuesURL: issues))
        XCTAssertEqual(url.scheme, "mailto")
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.path, "help@example.org")
        XCTAssertEqual(parts.queryItems?.first { $0.name == "subject" }?.value, "Mistake report: 93:3")
        XCTAssertEqual(parts.queryItems?.first { $0.name == "body" }?.value, MistakeReport.body(details))
    }

    func testIssuePageWhenNoAddressIsSet() throws {
        let url = try XCTUnwrap(MistakeReport.url(details, email: "", issuesURL: issues))
        XCTAssertEqual(url.host, "example.org")
        XCTAssertEqual(url.path, "/project/issues/new")
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.queryItems?.first { $0.name == "title" }?.value, "Mistake report: 93:3")
    }

    func testGeneralReportHasNoAyah() {
        let general = MistakeReport.Details(contentVersion: "v", appVersion: "1.0")
        XCTAssertEqual(MistakeReport.subject(general), "Mistake report")
        XCTAssertFalse(MistakeReport.body(general).contains("Ayah"))
    }
}

final class TopicProgressTests: XCTestCase {
    func testCountsReadSetsPerTopic() {
        let progress = TopicProgress.all(topics: ["hope", "mercy", "empty"],
                                         setsByTopic: ["hope": ["a", "b", "c", "d"], "mercy": ["e"], "empty": []],
                                         read: ["a", "c", "zzz"])
        XCTAssertEqual(progress.map(\.topicID), ["hope", "mercy"], "topics with no ayahs are left out")
        XCTAssertEqual(progress[0].read, 2)
        XCTAssertEqual(progress[0].total, 4)
        XCTAssertEqual(progress[0].fraction, 0.5)
        XCTAssertEqual(progress[1].fraction, 0)
    }
}
