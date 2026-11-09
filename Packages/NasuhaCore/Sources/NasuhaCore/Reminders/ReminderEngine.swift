import Foundation

/// Pure functions for the reminder queue. No clocks, no I/O: everything is passed in.
public enum ReminderEngine {
    /// iOS keeps at most 64 pending requests per app. 60 leaves room for "remind me in 1 hour".
    public static let windowSize = 60

    // MARK: Queue

    /// Builds the queue: topics take turns (round robin), each in its curated order.
    /// A set tagged with several picked topics appears once, at its first turn.
    /// When `ramadanFirst` is true, the Ramadan topic's sets come first.
    public static func buildQueue(topics: [String], setsByTopic: [String: [String]], ramadanFirst: Bool) -> [QueueItem] {
        var seen = Set<String>()
        var out: [QueueItem] = []
        func add(_ setID: String, _ topic: String) {
            if seen.insert(setID).inserted { out.append(QueueItem(setID: setID, topicID: topic)) }
        }

        var rotating = topics
        if ramadanFirst, rotating.contains(TopicCatalog.ramadanTopicID) {
            for id in setsByTopic[TopicCatalog.ramadanTopicID] ?? [] { add(id, TopicCatalog.ramadanTopicID) }
            rotating.removeAll { $0 == TopicCatalog.ramadanTopicID }
        }

        let lists = rotating.map { ($0, setsByTopic[$0] ?? []) }
        let longest = lists.map(\.1.count).max() ?? 0
        for i in 0..<longest {
            for (topic, ids) in lists where i < ids.count { add(ids[i], topic) }
        }
        return out
    }

    /// Rebuilds the queue for the current topics, keeping what was already read or sent this cycle.
    public static func rebuild(_ state: ReminderState, topics: [String], setsByTopic: [String: [String]],
                               isRamadan: Bool, readThisCycle: Set<String>) -> ReminderState {
        var s = state
        let ramadanFirst = isRamadan && topics.contains(TopicCatalog.ramadanTopicID)
        let done = Set(state.items.filter(\.done).map(\.setID)).union(readThisCycle)
        s.items = buildQueue(topics: topics, setsByTopic: setsByTopic, ramadanFirst: ramadanFirst).map {
            var item = $0
            item.done = done.contains(item.setID)
            return item
        }
        s.topics = topics
        s.ramadanFirst = ramadanFirst
        return s
    }

    // MARK: Time passing

    /// Applies every planned reminder whose time has come: its ayah becomes today's and is marked done.
    /// The "all read" reminder starts a new cycle and asks the app to show AllRead.
    public static func reconcile(_ state: ReminderState, now: Date) -> ReminderState {
        var s = state
        let due = s.planned.filter { $0.fireDate <= now }.sorted { $0.fireDate < $1.fireDate }
        for slot in due {
            switch slot.kind {
            case let .ayah(setID, topicID):
                if let i = s.items.firstIndex(where: { $0.setID == setID }) { s.items[i].done = true }
                s.currentSetID = setID
                s.currentTopicID = topicID
            case .allRead:
                s.allReadPendingSince = slot.fireDate
                s = startNewCycle(s, at: slot.fireDate)
            }
        }
        s.planned.removeAll { $0.fireDate <= now }
        return s
    }

    /// "Start again": every ayah becomes unread, from the first one.
    public static func startNewCycle(_ state: ReminderState, at date: Date) -> ReminderState {
        var s = state
        s.cycle += 1
        s.cycleStartedAt = date
        for i in s.items.indices { s.items[i].done = false }
        return s
    }

    /// The user read an ayah set in the app.
    public static func markRead(_ state: ReminderState, setID: String) -> ReminderState {
        var s = state
        if let i = s.items.firstIndex(where: { $0.setID == setID }) { s.items[i].done = true }
        return s
    }

    // MARK: Planning

    /// Assigns the next undone ayahs to `dates`, in queue order. After the last one comes
    /// the "all read" reminder, then the queue starts again from the first ayah, so reminders
    /// keep coming even if the app is never opened.
    public static func plan(_ state: ReminderState, dates: [Date]) -> [PlannedSlot] {
        guard !state.items.isEmpty else { return [] }
        var done = state.items.map(\.done)
        var cycle = state.cycle
        var slots: [PlannedSlot] = []

        for date in dates.prefix(windowSize) {
            if let i = done.firstIndex(of: false) {
                let item = state.items[i]
                done[i] = true
                slots.append(PlannedSlot(id: "nasuha.slot.\(cycle).\(item.setID)", fireDate: date,
                                         kind: .ayah(setID: item.setID, topicID: item.topicID)))
            } else {
                slots.append(PlannedSlot(id: "nasuha.slot.\(cycle).allread", fireDate: date,
                                         kind: .allRead(total: state.items.count)))
                cycle += 1
                done = Array(repeating: false, count: done.count)
            }
        }
        return slots
    }
}
