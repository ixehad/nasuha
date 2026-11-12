import Foundation

/// One topic the user can pick. `label` is the English text and also the
/// String Catalog key, so the app localises it with `String(localized:)`.
public struct Topic: Hashable, Sendable, Identifiable {
    public let id: String
    public let label: String
    /// Notification title, e.g. "Ayah of hope".
    public let reminderTitle: String
}

public struct TopicGroup: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let note: String?
    public let topics: [Topic]
}

/// The 29 topics in 6 groups, in the order shown on the Setup screen.
/// IDs are stable: curated sets in content-src/sets/ refer to them.
public enum TopicCatalog {
    public static let ramadanTopicID = "ramadan"

    public static let groups: [TopicGroup] = [
        TopicGroup(id: "heart", title: "For your heart", note: nil, topics: [
            Topic(id: "hope", label: "Hope", reminderTitle: "Ayah of hope"),
            Topic(id: "mercy", label: "Mercy & forgiveness", reminderTitle: "Ayah of mercy"),
            Topic(id: "patience", label: "Patience in hardship", reminderTitle: "Ayah of patience"),
            Topic(id: "worry", label: "Worry & trust in Allah", reminderTitle: "Ayah of trust in Allah"),
            Topic(id: "grief", label: "Grief & loss", reminderTitle: "Ayah for grief"),
            Topic(id: "alone", label: "Feeling alone", reminderTitle: "Ayah for when you feel alone"),
            Topic(id: "gratitude", label: "Gratitude", reminderTitle: "Ayah of gratitude"),
        ]),
        TopicGroup(id: "grow", title: "Return & grow", note: nil, topics: [
            Topic(id: "tawbah", label: "Tawbah", reminderTitle: "Ayah of tawbah"),
            Topic(id: "soul", label: "Purify the soul", reminderTitle: "Ayah to purify the soul"),
            Topic(id: "character", label: "Good character", reminderTitle: "Ayah of good character"),
            Topic(id: "taqwa", label: "Taqwa", reminderTitle: "Ayah of taqwa"),
        ]),
        TopicGroup(id: "stories", title: "Stories", note: nil, topics: [
            Topic(id: "why", label: "Stories of revelation", reminderTitle: "A story of revelation"),
            Topic(id: "prophets", label: "Prophets' stories", reminderTitle: "From the prophets' stories"),
            Topic(id: "seerah", label: "Prophet Muhammad ﷺ", reminderTitle: "Ayah about the Prophet ﷺ"),
            Topic(id: "trials", label: "Hardships of the prophets", reminderTitle: "Hardships of the prophets"),
            Topic(id: "women", label: "Women of the Qur'an", reminderTitle: "Women of the Qur'an"),
            Topic(id: "nations", label: "Lessons from past nations", reminderTitle: "Lessons from past nations"),
        ]),
        TopicGroup(id: "life", title: "Daily life", note: nil, topics: [
            Topic(id: "family", label: "Family & parents", reminderTitle: "Ayah about family"),
            Topic(id: "marriage", label: "Marriage", reminderTitle: "Ayah about marriage"),
            Topic(id: "money", label: "Money & honesty", reminderTitle: "Ayah about honesty"),
            Topic(id: "salah", label: "Salah & worship", reminderTitle: "Ayah about salah"),
            Topic(id: "justice", label: "Justice & people", reminderTitle: "Ayah about justice"),
        ]),
        TopicGroup(id: "special", title: "Ramadan & special days",
                   note: "What Ramadan is, why we fast, and the night of Qadr. During Ramadan these come first.",
                   topics: [
            Topic(id: "ramadan", label: "Ramadan & fasting", reminderTitle: "Ayah of Ramadan"),
            Topic(id: "qadr", label: "Laylat al-Qadr", reminderTitle: "Ayah of Laylat al-Qadr"),
            Topic(id: "hajj", label: "Hajj & Eid al-Adha", reminderTitle: "Ayah of Hajj"),
            Topic(id: "jumuah", label: "Jumu'ah (Friday)", reminderTitle: "Ayah for Jumu'ah"),
        ]),
        TopicGroup(id: "akhirah", title: "Du'a & Akhirah", note: nil, topics: [
            Topic(id: "dua", label: "Du'as of the Qur'an", reminderTitle: "A du'a from the Qur'an"),
            Topic(id: "akhirah", label: "Akhirah & Jannah", reminderTitle: "Ayah about the Akhirah"),
            Topic(id: "signs", label: "Signs in creation", reminderTitle: "Signs in creation"),
        ]),
    ]

    public static let all: [Topic] = groups.flatMap(\.topics)

    public static func topic(_ id: String) -> Topic? { all.first { $0.id == id } }

    /// Groups with only the topics that have at least one curated set
    /// (features without content are hidden). Empty groups are dropped.
    public static func available(setCounts: [String: Int]) -> [TopicGroup] {
        groups.compactMap { g in
            let topics = g.topics.filter { (setCounts[$0.id] ?? 0) > 0 }
            return topics.isEmpty ? nil : TopicGroup(id: g.id, title: g.title, note: g.note, topics: topics)
        }
    }
}
