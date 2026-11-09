import SwiftData
import XCTest
@testable import NasuhaCore

// MARK: Helpers

/// A fixed clock and calendar, so tests never depend on today's date.
struct FakeClock {
    var calendar: Calendar
    var now: Date

    init(_ iso: String, timeZone: String = "Asia/Dhaka") {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timeZone)!
        calendar = cal
        now = FakeClock.date(iso, timeZone: timeZone)
    }

    static func date(_ iso: String, timeZone: String = "Asia/Dhaka") -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: timeZone)
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: iso)!
    }

    func parts(_ date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: date)
    }
}

final class FakeScheduler: NotificationScheduling {
    var authorized = true
    var pending: [ReminderRequest] = []
    var removed: [String] = []

    func isAuthorized() async -> Bool { authorized }
    func pendingIdentifiers() async -> [String] { pending.map(\.id) }
    func removePending(identifiers: [String]) {
        removed += identifiers
        pending.removeAll { identifiers.contains($0.id) }
    }
    func add(_ request: ReminderRequest) async throws { pending.append(request) }
}

/// Marks each lookup with its language, so tests can see which language was used.
struct TaggingLocalizer: Localizer {
    func string(_ key: String, language: String) -> String { "[\(language)] \(key)" }
}

func fixtureStore() throws -> ContentStore {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "content-fixture", withExtension: "sqlite", subdirectory: "Fixtures"))
    return try ContentStore(path: url.path)
}

// MARK: Queue

final class QueueBuildingTests: XCTestCase {
    func testTopicsTakeTurnsInCuratedOrder() {
        let q = ReminderEngine.buildQueue(
            topics: ["hope", "tawbah", "why"],
            setsByTopic: ["hope": ["h1", "h2", "h3"], "tawbah": ["t1"], "why": ["w1", "w2"]],
            ramadanFirst: false)
        XCTAssertEqual(q.map(\.setID), ["h1", "t1", "w1", "h2", "w2", "h3"])
        XCTAssertEqual(q.map(\.topicID), ["hope", "tawbah", "why", "hope", "why", "hope"])
    }

    func testSetInTwoTopicsAppearsOnce() {
        let q = ReminderEngine.buildQueue(topics: ["hope", "why"],
                                          setsByTopic: ["hope": ["a", "b"], "why": ["a", "c"]], ramadanFirst: false)
        XCTAssertEqual(q.map(\.setID), ["a", "b", "c"])
        XCTAssertEqual(q.first?.topicID, "hope", "first turn wins")
    }

    func testTopicWithoutSetsIsSkipped() {
        let q = ReminderEngine.buildQueue(topics: ["grief", "hope"], setsByTopic: ["hope": ["h1"]], ramadanFirst: false)
        XCTAssertEqual(q.map(\.setID), ["h1"])
    }

    func testRamadanFirstDuringRamadan() {
        let sets = ["hope": ["h1", "h2"], "ramadan": ["r1", "r2"]]
        let during = ReminderEngine.rebuild(ReminderState(), topics: ["hope", "ramadan"], setsByTopic: sets,
                                            isRamadan: true, readThisCycle: [])
        XCTAssertEqual(during.items.map(\.setID), ["r1", "r2", "h1", "h2"])
        XCTAssertTrue(during.ramadanFirst)

        let outside = ReminderEngine.rebuild(ReminderState(), topics: ["hope", "ramadan"], setsByTopic: sets,
                                             isRamadan: false, readThisCycle: [])
        XCTAssertEqual(outside.items.map(\.setID), ["h1", "r1", "h2", "r2"])

        let notPicked = ReminderEngine.rebuild(ReminderState(), topics: ["hope"], setsByTopic: sets,
                                               isRamadan: true, readThisCycle: [])
        XCTAssertFalse(notPicked.ramadanFirst)
    }

    func testChangingTopicsKeepsReadItems() {
        var s = ReminderEngine.rebuild(ReminderState(), topics: ["hope"], setsByTopic: ["hope": ["a", "b"]],
                                       isRamadan: false, readThisCycle: [])
        s = ReminderEngine.markRead(s, setID: "a")
        s = ReminderEngine.rebuild(s, topics: ["hope", "why"], setsByTopic: ["hope": ["a", "b"], "why": ["c"]],
                                   isRamadan: false, readThisCycle: ["c"])
        XCTAssertEqual(s.items.map(\.setID), ["a", "c", "b"])
        XCTAssertEqual(s.items.map(\.done), [true, true, false])
        XCTAssertEqual(s.progress.next, 3)
        XCTAssertEqual(s.progress.total, 3)
    }
}

// MARK: Schedule

final class ScheduleTests: XCTestCase {
    func testDailyStartsTodayIfTheTimeIsStillAhead() {
        let early = FakeClock("2026-11-06 07:00")
        let dates = ReminderSchedule.fireDates(after: early.now, settings: ReminderSettings(topics: [], hour: 7, minute: 30),
                                               count: 3, calendar: early.calendar)
        XCTAssertEqual(dates.map { early.parts($0).day }, [6, 7, 8])
        XCTAssertTrue(dates.allSatisfy { early.parts($0).hour == 7 && early.parts($0).minute == 30 })

        let late = FakeClock("2026-11-06 08:00")
        let next = ReminderSchedule.fireDates(after: late.now, settings: ReminderSettings(topics: [], hour: 7, minute: 30),
                                              count: 1, calendar: late.calendar)
        XCTAssertEqual(late.parts(next[0]).day, 7)
    }

    func testEveryTwoDaysFollowsTheAnchor() {
        let clock = FakeClock("2026-11-06 08:00")
        let anchor = FakeClock.date("2026-11-05 09:00")
        let settings = ReminderSettings(topics: [], hour: 7, minute: 30, frequency: .everyTwoDays, anchor: anchor)
        let dates = ReminderSchedule.fireDates(after: clock.now, settings: settings, count: 3, calendar: clock.calendar)
        XCTAssertEqual(dates.map { clock.parts($0).day }, [7, 9, 11])

        // A refill a day later keeps the same rhythm.
        let later = ReminderSchedule.fireDates(after: FakeClock.date("2026-11-07 08:00"), settings: settings,
                                               count: 2, calendar: clock.calendar)
        XCTAssertEqual(later.map { clock.parts($0).day }, [9, 11])
    }

    func testFridaysOnly() {
        let clock = FakeClock("2026-11-06 06:00") // a Friday
        let dates = ReminderSchedule.fireDates(after: clock.now, settings: ReminderSettings(topics: [], frequency: .fridays),
                                               count: 4, calendar: clock.calendar)
        XCTAssertEqual(dates.map { clock.parts($0).weekday }, [6, 6, 6, 6])
        XCTAssertEqual(dates.map { clock.parts($0).day }, [6, 13, 20, 27])
    }

    func testPauseSkipsDaysUntilItEnds() {
        let clock = FakeClock("2026-11-06 08:00")
        let settings = ReminderSettings(topics: [], pausedUntil: FakeClock.date("2026-11-10 00:00"))
        let dates = ReminderSchedule.fireDates(after: clock.now, settings: settings, count: 2, calendar: clock.calendar)
        XCTAssertEqual(dates.map { clock.parts($0).day }, [10, 11])
    }

    func testLocalTimeStaysTheSameAcrossDaylightSaving() {
        // Clocks go back in New York on 1 November 2026.
        let clock = FakeClock("2026-10-30 08:00", timeZone: "America/New_York")
        let dates = ReminderSchedule.fireDates(after: clock.now, settings: ReminderSettings(topics: []), count: 4,
                                               calendar: clock.calendar)
        XCTAssertEqual(dates.map { clock.parts($0).day }, [31, 1, 2, 3])
        XCTAssertTrue(dates.allSatisfy { clock.parts($0).hour == 7 && clock.parts($0).minute == 30 })
        XCTAssertEqual(dates[2].timeIntervalSince(dates[1]), 86_400)
        XCTAssertEqual(dates[1].timeIntervalSince(dates[0]), 90_000, "the day clocks change is 25 hours")
    }
}

// MARK: Plan and end of queue

final class PlanTests: XCTestCase {
    private func state(_ ids: [String]) -> ReminderState {
        ReminderEngine.rebuild(ReminderState(), topics: ["hope"], setsByTopic: ["hope": ids], isRamadan: false, readThisCycle: [])
    }

    private func days(_ n: Int, from start: String = "2026-11-07 07:30") -> [Date] {
        let first = FakeClock.date(start)
        return (0..<n).map { first.addingTimeInterval(Double($0) * 86_400) }
    }

    func testWindowIsAtMostSixty() {
        let ids = (1...100).map { "s\($0)" }
        let plan = ReminderEngine.plan(state(ids), dates: days(100))
        XCTAssertEqual(plan.count, 60)
        XCTAssertEqual(Set(plan.map(\.id)).count, 60, "identifiers are unique")
    }

    func testAllReadComesAfterTheLastAyahThenTheQueueStartsAgain() {
        let plan = ReminderEngine.plan(state(["a", "b", "c"]), dates: days(6))
        XCTAssertEqual(plan.map(\.kind), [
            .ayah(setID: "a", topicID: "hope"), .ayah(setID: "b", topicID: "hope"), .ayah(setID: "c", topicID: "hope"),
            .allRead(total: 3),
            .ayah(setID: "a", topicID: "hope"), .ayah(setID: "b", topicID: "hope"),
        ])
        XCTAssertEqual(plan[4].id, "nasuha.slot.1.a")
    }

    func testPlanSkipsWhatWasAlreadyRead() {
        let s = ReminderEngine.markRead(state(["a", "b", "c"]), setID: "b")
        XCTAssertEqual(ReminderEngine.plan(s, dates: days(2)).map(\.kind),
                       [.ayah(setID: "a", topicID: "hope"), .ayah(setID: "c", topicID: "hope")])
    }

    func testEmptyQueuePlansNothing() {
        XCTAssertTrue(ReminderEngine.plan(ReminderState(), dates: days(5)).isEmpty)
    }

    func testReconcileMarksSentAyahsAndShowsAllReadAtTheEnd() {
        var s = state(["a", "b"])
        s.planned = ReminderEngine.plan(s, dates: days(4)) // a, b, allRead, a
        s = ReminderEngine.reconcile(s, now: FakeClock.date("2026-11-08 08:00"))
        XCTAssertEqual(s.items.map(\.done), [true, true])
        XCTAssertEqual(s.currentSetID, "b")
        XCTAssertEqual(s.progress.next, 2, "clamped to the total")
        XCTAssertNil(s.allReadPendingSince)
        XCTAssertEqual(s.planned.count, 2)

        s = ReminderEngine.reconcile(s, now: FakeClock.date("2026-11-09 08:00"))
        XCTAssertEqual(s.allReadPendingSince, FakeClock.date("2026-11-09 07:30"))
        XCTAssertEqual(s.cycle, 1)
        XCTAssertEqual(s.items.map(\.done), [false, false], "if the user does nothing, the queue starts again")

        s = ReminderEngine.reconcile(s, now: FakeClock.date("2026-11-10 08:00"))
        XCTAssertEqual(s.currentSetID, "a")
        XCTAssertEqual(s.items.map(\.done), [true, false])
    }

    func testProgressReadsLikeAyahEighteenOfFortyEight() {
        var s = state((1...48).map { "s\($0)" })
        for i in 1...17 { s = ReminderEngine.markRead(s, setID: "s\(i)") }
        XCTAssertEqual(s.progress.next, 18)
        XCTAssertEqual(s.progress.total, 48)
    }
}

// MARK: Hijri

final class HijriTests: XCTestCase {
    private let dhaka = TimeZone(identifier: "Asia/Dhaka")!

    func testRamadanFollowsTheUmmAlQuraCalendar() {
        var cal = Calendar(identifier: .islamicUmmAlQura)
        cal.timeZone = dhaka
        let firstOfRamadan = cal.date(from: DateComponents(year: 1447, month: 9, day: 1, hour: 12))!
        let dayBefore = firstOfRamadan.addingTimeInterval(-86_400)
        XCTAssertTrue(HijriDate.isRamadan(firstOfRamadan, offset: 0, timeZone: dhaka))
        XCTAssertFalse(HijriDate.isRamadan(dayBefore, offset: 0, timeZone: dhaka))
        XCTAssertEqual(HijriDate.value(for: firstOfRamadan, offset: 0, timeZone: dhaka),
                       HijriDate.Value(year: 1447, month: 9, day: 1))
    }

    func testOffsetMovesTheDate() {
        var cal = Calendar(identifier: .islamicUmmAlQura)
        cal.timeZone = dhaka
        let firstOfRamadan = cal.date(from: DateComponents(year: 1447, month: 9, day: 1, hour: 12))!
        let dayBefore = firstOfRamadan.addingTimeInterval(-86_400)
        XCTAssertTrue(HijriDate.isRamadan(dayBefore, offset: 1, timeZone: dhaka), "+1 day matches an earlier sighting")
        XCTAssertFalse(HijriDate.isRamadan(firstOfRamadan, offset: -1, timeZone: dhaka))
        XCTAssertEqual(HijriDate.value(for: firstOfRamadan, offset: 2, timeZone: dhaka).day, 3)
        XCTAssertEqual(HijriDate.value(for: firstOfRamadan, offset: 9, timeZone: dhaka).day, 3, "clamped to +2")
    }

    func testSanityAgainstAKnownDate() {
        // 1 Ramadan 1447 in Umm al-Qura falls in February 2026.
        var cal = Calendar(identifier: .islamicUmmAlQura)
        cal.timeZone = dhaka
        let first = cal.date(from: DateComponents(year: 1447, month: 9, day: 1, hour: 12))!
        var greg = Calendar(identifier: .gregorian)
        greg.timeZone = dhaka
        XCTAssertEqual(greg.dateComponents([.year, .month], from: first), DateComponents(year: 2026, month: 2))
    }
}

// MARK: Notification text

final class ReminderContentTests: XCTestCase {
    private func builder() throws -> ReminderContentBuilder {
        ReminderContentBuilder(source: try fixtureStore(), localizer: TaggingLocalizer())
    }

    func testAyahReminderFormat() throws {
        let settings = ReminderSettings(topics: ["hope"], language: "en", preferredTranslations: ["fixture_en"])
        let text = try XCTUnwrap(builder().ayah(setID: "fixture-2-3", topicID: "hope", settings: settings))
        XCTAssertEqual(text.title, "[en] Ayah of hope")
        XCTAssertEqual(text.body, "\u{201C}FIXTURE en 2:3\u{201D} Fixture-Two 2:3\n[en] Why it was revealed: FIXTURE ONE LINE")
        XCTAssertEqual(text.threadID, "hope")
        XCTAssertEqual(text.category, ReminderCategory.ayah)
        XCTAssertEqual(text.userInfo[ReminderUserInfo.ayahSetID], "fixture-2-3")
        XCTAssertEqual(text.userInfo[ReminderUserInfo.ayahKey], "2:3")
    }

    func testNoArabicWhileTheLockScreenSettingIsOn() throws {
        var settings = ReminderSettings(topics: ["hope"])
        let off = try XCTUnwrap(builder().ayah(setID: "fixture-2-3", topicID: "hope", settings: settings))
        XCTAssertFalse(off.body.contains("FIXTURE 2:3\n"))
        settings.keepArabicOffLockScreen = false
        let on = try XCTUnwrap(builder().ayah(setID: "fixture-2-3", topicID: "hope", settings: settings))
        XCTAssertTrue(on.body.hasPrefix("FIXTURE 2:3\n"))
    }

    func testReminderLanguagePicksTheTranslationAndHidesOtherLanguageStory() throws {
        let settings = ReminderSettings(topics: ["hope"], language: "bn")
        let text = try XCTUnwrap(builder().ayah(setID: "fixture-2-3", topicID: "hope", settings: settings))
        XCTAssertEqual(text.title, "[bn] Ayah of hope")
        XCTAssertTrue(text.body.contains("FIXTURE bn 2:3"))
        XCTAssertFalse(text.body.contains("Why it was revealed"), "the one-line story is in English only")
    }

    func testNoStoryMeansNoStoryLine() throws {
        let text = try XCTUnwrap(builder().ayah(setID: "fixture-1-2", topicID: "hope", settings: ReminderSettings(topics: ["hope"])))
        XCTAssertFalse(text.body.contains("\n"))
    }

    func testMissingSetGivesNoReminder() throws {
        XCTAssertNil(try builder().ayah(setID: "nope", topicID: "hope", settings: ReminderSettings(topics: [])))
    }

    func testAllReadText() throws {
        let daily = try builder().allRead(total: 48, settings: ReminderSettings(topics: []))
        XCTAssertEqual(daily.title, "[en] You've read all 48 ayahs")
        XCTAssertEqual(daily.body, "[en] " + ReminderStrings.allReadBodyTomorrow)
        XCTAssertEqual(daily.category, ReminderCategory.allRead)
        let fridays = try builder().allRead(total: 48, settings: ReminderSettings(topics: [], frequency: .fridays))
        XCTAssertEqual(fridays.body, "[en] " + ReminderStrings.allReadBodyNext, "no promise of 'tomorrow' on a weekly rhythm")
    }
}

// MARK: Service

@MainActor
final class ReminderServiceTests: XCTestCase {
    private func service(_ scheduler: FakeScheduler, clock: FakeClock) throws -> ReminderService {
        ReminderService(source: try fixtureStore(), notifications: scheduler, localizer: TaggingLocalizer(),
                        now: { clock.now }, calendar: { clock.calendar })
    }

    func testRefillSchedulesTheWindowAtLocalTimes() async throws {
        let scheduler = FakeScheduler()
        let clock = FakeClock("2026-11-06 08:00")
        let s = try await service(scheduler, clock: clock)
            .refill(ReminderState(), settings: ReminderSettings(topics: ["hope"]), readThisCycle: [])
        XCTAssertEqual(s.items.map(\.setID), ["fixture-2-3", "fixture-1-2"])
        XCTAssertEqual(s.planned.count, 60)
        XCTAssertEqual(scheduler.pending.count, 60)
        guard case let .calendar(first) = scheduler.pending[0].trigger else { return XCTFail("calendar trigger") }
        XCTAssertEqual([first.year, first.month, first.day, first.hour, first.minute], [2026, 11, 7, 7, 30])
        XCTAssertNil(first.timeZone, "floating local time, so it follows the user across time zones")
        XCTAssertEqual(scheduler.pending[2].text.category, ReminderCategory.allRead)
    }

    func testRefillReplacesOldSlotsButKeepsSnoozes() async throws {
        let scheduler = FakeScheduler()
        let clock = FakeClock("2026-11-06 08:00")
        let svc = try service(scheduler, clock: clock)
        let settings = ReminderSettings(topics: ["hope"])
        var s = try await svc.refill(ReminderState(), settings: settings, readThisCycle: [])
        try await svc.snooze(setID: "fixture-2-3", topicID: "hope", settings: settings)
        s = try await svc.refill(s, settings: settings, readThisCycle: [])
        XCTAssertEqual(scheduler.pending.filter { $0.id.hasPrefix(ReminderService.slotPrefix) }.count, 60)
        let snoozes = scheduler.pending.filter { $0.id.hasPrefix(ReminderService.snoozePrefix) }
        XCTAssertEqual(snoozes.count, 1)
        XCTAssertEqual(snoozes.first?.trigger, .after(seconds: 3_600))
        XCTAssertLessThanOrEqual(scheduler.pending.count, 64)
    }

    func testWithoutPermissionTheQueueStillMovesButNothingIsScheduled() async throws {
        let scheduler = FakeScheduler()
        scheduler.authorized = false
        let clock = FakeClock("2026-11-06 08:00")
        let s = try await service(scheduler, clock: clock)
            .refill(ReminderState(), settings: ReminderSettings(topics: ["hope"]), readThisCycle: [])
        XCTAssertEqual(s.planned.count, 60)
        XCTAssertTrue(scheduler.pending.isEmpty)
    }

    func testNoTopicsClearsReminders() async throws {
        let scheduler = FakeScheduler()
        let clock = FakeClock("2026-11-06 08:00")
        let svc = try service(scheduler, clock: clock)
        let s = try await svc.refill(ReminderState(), settings: ReminderSettings(topics: ["hope"]), readThisCycle: [])
        let cleared = try await svc.refill(s, settings: ReminderSettings(topics: []), readThisCycle: [])
        XCTAssertTrue(cleared.planned.isEmpty)
        XCTAssertTrue(scheduler.pending.isEmpty)
    }
}

// MARK: Controller (SwiftData)

@MainActor
final class ReminderControllerTests: XCTestCase {
    func testReadingRestartingAndTopicChanges() async throws {
        let container = try NasuhaSchema.container(inMemory: true)
        let ctx = container.mainContext
        var clock = FakeClock("2026-11-06 08:00")
        let scheduler = FakeScheduler()
        var now = clock.now
        let service = ReminderService(source: try fixtureStore(), notifications: scheduler, localizer: TaggingLocalizer(),
                                      now: { now }, calendar: { clock.calendar })
        let controller = ReminderController(context: ctx, service: service, now: { now })
        ctx.insert(TopicChoice(topicID: "hope", order: 0))
        try ctx.save()

        try await controller.refill()
        XCTAssertNotNil(try UserSettings.current(in: ctx).scheduleAnchor, "anchor is set once")
        XCTAssertEqual(controller.state.planned.first?.kind, .ayah(setID: "fixture-2-3", topicID: "hope"))

        // Reading in the app moves the queue on.
        try await controller.markRead(setID: "fixture-2-3", hadStory: true)
        XCTAssertEqual(controller.state.planned.first?.kind, .ayah(setID: "fixture-1-2", topicID: "hope"))

        // Adding a topic keeps what was read.
        ctx.insert(TopicChoice(topicID: "mercy", order: 1))
        try ctx.save()
        try await controller.refill()
        XCTAssertEqual(controller.state.items.map(\.setID), ["fixture-2-3", "sample-2-4", "fixture-1-2"])
        XCTAssertEqual(controller.state.items.map(\.done), [true, false, false])

        // Time passes until the "all read" reminder has gone out.
        clock.now = FakeClock.date("2026-11-09 08:00")
        now = clock.now
        try await controller.refill()
        XCTAssertTrue(controller.shouldShowAllRead)

        // "Start again" clears AllRead and starts from the first ayah.
        try await controller.answerAllRead(.startAgain)
        XCTAssertFalse(controller.shouldShowAllRead)
        XCTAssertEqual(controller.state.items.map(\.done), [false, false, false])
        XCTAssertEqual(controller.state.planned.first?.kind, .ayah(setID: "fixture-2-3", topicID: "hope"))
    }

    func testSaveFromNotificationIsStoredOnce() throws {
        let container = try NasuhaSchema.container(inMemory: true)
        let service = ReminderService(source: try fixtureStore(), notifications: FakeScheduler(), localizer: TaggingLocalizer())
        let controller = ReminderController(context: container.mainContext, service: service)
        try controller.save(ayahKey: "2:3", setID: "fixture-2-3")
        try controller.save(ayahKey: "2:3", setID: "fixture-2-3")
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<SavedAyah>()), 1)
    }
}

// MARK: Deep links

final class DeepLinkTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(DeepLink(url: URL(string: "nasuha://ayah/duha-93-3")!), .ayah(setID: "duha-93-3"))
        XCTAssertEqual(DeepLink(url: URL(string: "nasuha://allread")!), .allRead)
        XCTAssertNil(DeepLink(url: URL(string: "nasuha://ayah/")!))
        XCTAssertNil(DeepLink(url: URL(string: "https://ayah/duha-93-3")!))
        XCTAssertNil(DeepLink(url: URL(string: "nasuha://ayah/..%2Fsecret")!))
        XCTAssertNil(DeepLink(url: URL(string: "nasuha://settings")!))
    }

    func testRoundTripAndUserInfo() {
        let link = DeepLink.ayah(setID: "duha-93-3")
        XCTAssertEqual(DeepLink(url: link.url), link)
        XCTAssertEqual(DeepLink(userInfo: ["kind": "ayah", "ayahSetId": "duha-93-3"]), link)
        XCTAssertEqual(DeepLink(userInfo: ["kind": "allRead"]), .allRead)
        XCTAssertNil(DeepLink(userInfo: ["kind": "ayah"]))
    }
}
