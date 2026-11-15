import Foundation

public extension TextSizeStep {
    /// Moves a position in an ordered list of text sizes by this step, staying inside the list.
    /// The app uses it to shift the phone's own text size up or down.
    func shifted(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(count - 1, max(0, index + rawValue))
    }
}

/// How long "Pause reminders for a while" lasts.
public enum PauseLength: Int, CaseIterable, Sendable {
    case oneDay = 1, threeDays = 3, oneWeek = 7

    /// The moment reminders start again: the start of the day after the pause ends.
    public func resumeDate(from now: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: rawValue, to: day) ?? now.addingTimeInterval(Double(rawValue) * 86_400)
    }
}

/// Builds the "Report a mistake" link. There is no backend: the link opens the person's
/// own mail app, or the project's issue page when no contact address is set.
public enum MistakeReport {
    public struct Details: Equatable, Sendable {
        public var ayahKey: String?
        public var setID: String?
        public var contentVersion: String
        public var appVersion: String

        public init(ayahKey: String? = nil, setID: String? = nil, contentVersion: String, appVersion: String) {
            self.ayahKey = ayahKey
            self.setID = setID
            self.contentVersion = contentVersion
            self.appVersion = appVersion
        }
    }

    public static func subject(_ details: Details) -> String {
        details.ayahKey.map { "Mistake report: \($0)" } ?? "Mistake report"
    }

    /// The prefilled text. It names the ayah and versions, and nothing about the person.
    public static func body(_ details: Details) -> String {
        var lines = ["What is wrong:", "", "", "---"]
        if let key = details.ayahKey { lines.append("Ayah: \(key)") }
        if let id = details.setID { lines.append("Ayah ID: \(id)") }
        lines.append("Content version: \(details.contentVersion)")
        lines.append("App version: \(details.appVersion)")
        return lines.joined(separator: "\n")
    }

    /// A `mailto:` link when `email` is set, else a new-issue link on `issuesURL`.
    public static func url(_ details: Details, email: String, issuesURL: URL) -> URL? {
        if !email.isEmpty {
            var parts = URLComponents()
            parts.scheme = "mailto"
            parts.path = email
            parts.queryItems = [URLQueryItem(name: "subject", value: subject(details)),
                                URLQueryItem(name: "body", value: body(details))]
            return parts.url
        }
        var parts = URLComponents(url: issuesURL.appendingPathComponent("new"), resolvingAgainstBaseURL: false)
        parts?.queryItems = [URLQueryItem(name: "title", value: subject(details)),
                             URLQueryItem(name: "body", value: body(details))]
        return parts?.url
    }
}

/// Progress in one topic: how many of its ayah sets have been read.
public struct TopicProgress: Equatable, Sendable, Identifiable {
    public var id: String { topicID }
    public let topicID: String
    public let read: Int
    public let total: Int

    public var fraction: Double { total > 0 ? Double(read) / Double(total) : 0 }

    public static func all(topics: [String], setsByTopic: [String: [String]], read: Set<String>) -> [TopicProgress] {
        topics.compactMap { topic in
            let sets = setsByTopic[topic] ?? []
            guard !sets.isEmpty else { return nil }
            return TopicProgress(topicID: topic, read: sets.filter(read.contains).count, total: sets.count)
        }
    }
}
