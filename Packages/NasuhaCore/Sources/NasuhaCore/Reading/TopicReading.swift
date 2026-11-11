import Foundation

/// Which ayah set to show for a topic, given what has been read.
public enum TopicReading {
    /// The first set of the topic not yet read, or the first one when all are read.
    public static func current(in setIDs: [String], read: Set<String>) -> String? {
        setIDs.first { !read.contains($0) } ?? setIDs.first
    }

    /// The next unread set after `setID` in the topic's curated order.
    public static func next(after setID: String, in setIDs: [String], read: Set<String>) -> String? {
        guard let index = setIDs.firstIndex(of: setID) else { return nil }
        return setIDs[(index + 1)...].first { !read.contains($0) }
    }

    /// The set for Home's card. The topic that today's reminder came from shows
    /// today's ayah; any other topic shows its own current set.
    public static func homeSet(topic: String, state: ReminderState, setIDs: [String], read: Set<String>) -> String? {
        if topic == state.currentTopicID, let today = state.currentSetID, setIDs.contains(today) { return today }
        return current(in: setIDs, read: read)
    }
}

/// A reminder time on a 12-hour clock face.
public struct ClockTime: Equatable, Sendable {
    /// 1...12
    public var hour: Int
    public var minute: Int
    public var isPM: Bool

    public static let minuteChoices = [0, 15, 30, 45]
    public static let dialHours = [12, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]

    public init(hour: Int, minute: Int, isPM: Bool) {
        self.hour = min(12, max(1, hour))
        self.minute = min(59, max(0, minute))
        self.isPM = isPM
    }

    public init(hour24: Int, minute: Int) {
        let h = ((hour24 % 24) + 24) % 24
        self.init(hour: h % 12 == 0 ? 12 : h % 12, minute: minute, isPM: h >= 12)
    }

    /// 0...23. 12 AM is 0 and 12 PM is 12.
    public var hour24: Int { (hour % 12) + (isPM ? 12 : 0) }

    /// Angle of an hour on the dial, in degrees, measured clockwise from 3 o'clock.
    public static func angle(forHour hour: Int) -> Double {
        Double(hour % 12) * 30 - 90
    }
}
