import Foundation

/// One topic the user can pick. `label` is the English text and also the
/// String Catalog key, so the app localises it with `String(localized:)`.
public struct Topic: Hashable, Sendable, Identifiable {
    public let id: String
    public let label: String
    /// Notification title, e.g. "Ayah of hope".
    public let reminderTitle: String
    /// Featured topics are listed on the Setup screen. The rest are found by search or under "More topics".
    public let isFeatured: Bool

    public init(id: String, label: String, reminderTitle: String? = nil, isFeatured: Bool = true) {
        self.id = id
        self.label = label
        self.reminderTitle = reminderTitle ?? label
        self.isFeatured = isFeatured
    }
}

public struct TopicGroup: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let note: String?
    public let topics: [Topic]

    public init(id: String, title: String, note: String?, topics: [Topic]) {
        self.id = id
        self.title = title
        self.note = note
        self.topics = topics
    }

    /// This group with only the topics that pass the test, or nil when none do.
    public func keeping(_ isIncluded: (Topic) -> Bool) -> TopicGroup? {
        let kept = topics.filter(isIncluded)
        return kept.isEmpty ? nil : TopicGroup(id: id, title: title, note: note, topics: kept)
    }
}

/// Finding topics by name, in the app's language or in English.
public enum TopicSearch {
    /// Lower-cased with accents and punctuation removed, so "Qur'an" and "quran" compare alike.
    public static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber || $0 == " " }
    }

    /// The words of a search, ready to compare. Empty when there is nothing to search for.
    public static func words(_ query: String) -> [String] {
        folded(query).split(separator: " ").map(String.init)
    }

    /// Topics whose shown name or English name contains every word of the search, in catalogue order.
    public static func matches(_ query: String, in groups: [TopicGroup], name: (Topic) -> String) -> [Topic] {
        let wanted = words(query)
        guard !wanted.isEmpty else { return [] }
        return groups.flatMap(\.topics).filter { topic in
            let haystack = folded(name(topic)) + " " + folded(topic.label)
            return wanted.allSatisfy(haystack.contains)
        }
    }
}

/// The topics in the order shown on the Setup screen. Featured topics are listed;
/// the rest are found under "More topics" and by search.
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
        TopicGroup(id: "character", title: "The heart and good character", note: nil, topics: [
            Topic(id: "excellence", label: "Excellence (Ihsan)", isFeatured: false),
            Topic(id: "brotherhood", label: "Brotherhood", isFeatured: false),
            Topic(id: "istiqamah", label: "Steadfastness (Istiqamah)", isFeatured: false),
            Topic(id: "reconciliation", label: "Making peace between people", isFeatured: false),
            Topic(id: "moderation", label: "Moderation", isFeatured: false),
            Topic(id: "vain-talk", label: "Turning away from idle talk", isFeatured: false),
            Topic(id: "altruism", label: "Putting others first (Ithar)", isFeatured: false),
            Topic(id: "gentleness", label: "Gentleness", isFeatured: false),
            Topic(id: "cooperation", label: "Helping one another in good", isFeatured: false),
            Topic(id: "humility", label: "Humility", isFeatured: false),
            Topic(id: "wisdom", label: "Wisdom", isFeatured: false),
            Topic(id: "repel-evil-good", label: "Repelling evil with good", isFeatured: false),
            Topic(id: "human-mercy", label: "Being merciful", isFeatured: false),
            Topic(id: "tranquility", label: "Tranquillity (Sakinah)", isFeatured: false),
            Topic(id: "truthfulness", label: "Truthfulness", isFeatured: false),
            Topic(id: "chastity", label: "Chastity", isFeatured: false),
            Topic(id: "forgiving-others", label: "Forgiving others", isFeatured: false),
            Topic(id: "doing-good", label: "Doing good", isFeatured: false),
            Topic(id: "walking-voice", label: "Walking humbly and lowering the voice", isFeatured: false),
            Topic(id: "good-speech", label: "Speaking well", isFeatured: false),
            Topic(id: "anger", label: "Controlling anger", isFeatured: false),
            Topic(id: "racing-good", label: "Racing to do good", isFeatured: false),
            Topic(id: "keeping-promises", label: "Keeping promises", isFeatured: false),
            Topic(id: "heart", label: "The heart", isFeatured: false),
            Topic(id: "inner-self", label: "The self and its desires", isFeatured: false),
            Topic(id: "happiness", label: "Happiness", isFeatured: false),
            Topic(id: "love", label: "Love", isFeatured: false),
            Topic(id: "security", label: "Safety and security", isFeatured: false),
            Topic(id: "consistency", label: "Matching words with deeds", isFeatured: false),
            Topic(id: "ease", label: "Allah wants ease for you", isFeatured: false),
            Topic(id: "success", label: "Deeds that lead to success", isFeatured: false),
            Topic(id: "urging-action", label: "Striving and good work", isFeatured: false),
            Topic(id: "arrogance", label: "Arrogance", isFeatured: false),
            Topic(id: "envy", label: "Envy", isFeatured: false),
            Topic(id: "backbiting", label: "Backbiting and gossip", isFeatured: false),
            Topic(id: "lying", label: "Lying", isFeatured: false),
            Topic(id: "mockery", label: "Mocking others", isFeatured: false),
            Topic(id: "suspicion", label: "Suspicion", isFeatured: false),
            Topic(id: "slander", label: "Slander", isFeatured: false),
            Topic(id: "rumours", label: "Spreading rumours", isFeatured: false),
            Topic(id: "stinginess", label: "Stinginess", isFeatured: false),
            Topic(id: "greed", label: "Greed", isFeatured: false),
            Topic(id: "extravagance", label: "Extravagance", isFeatured: false),
            Topic(id: "showing-off", label: "Showing off", isFeatured: false),
            Topic(id: "betrayal", label: "Betrayal", isFeatured: false),
            Topic(id: "heedlessness", label: "Heedlessness", isFeatured: false),
            Topic(id: "hard-heart", label: "Hardness of heart", isFeatured: false),
            Topic(id: "ingratitude", label: "Ingratitude", isFeatured: false),
            Topic(id: "speaking-without-knowledge", label: "Speaking without knowledge", isFeatured: false),
            Topic(id: "injustice", label: "Injustice (Zulm)", isFeatured: false),
            Topic(id: "corruption", label: "Spreading corruption", isFeatured: false),
            Topic(id: "fitnah", label: "Trials and tests (Fitnah)", isFeatured: false),
            Topic(id: "wealth-trial", label: "The trial of wealth and children", isFeatured: false),
            Topic(id: "hypocrisy", label: "Hypocrisy", isFeatured: false),
            Topic(id: "afflictions-of-tongue", label: "Sins of the tongue", isFeatured: false),
            Topic(id: "mutual-quarrel", label: "Arguing and disputes", isFeatured: false),
            Topic(id: "lahw", label: "Distraction and play", isFeatured: false),
        ]),
        TopicGroup(id: "belief", title: "Allah and belief", note: nil, topics: [
            Topic(id: "tawheed", label: "Oneness of Allah (Tawheed)", isFeatured: false),
            Topic(id: "names-attributes", label: "Allah's names and attributes", isFeatured: false),
            Topic(id: "will-of-allah", label: "The will of Allah", isFeatured: false),
            Topic(id: "authority-of-allah", label: "All authority belongs to Allah", isFeatured: false),
            Topic(id: "allah-just", label: "Allah is never unjust", isFeatured: false),
            Topic(id: "love-of-allah", label: "Love of Allah", isFeatured: false),
            Topic(id: "forbearance", label: "Allah's forbearance with His servants", isFeatured: false),
            Topic(id: "pleasure-of-allah", label: "The pleasure of Allah", isFeatured: false),
            Topic(id: "knowledge-of-allah", label: "Allah's all-encompassing knowledge", isFeatured: false),
            Topic(id: "anger-of-allah", label: "The anger of Allah", isFeatured: false),
            Topic(id: "need-of-allah", label: "People need Allah; He needs no one", isFeatured: false),
            Topic(id: "blessings", label: "Allah's blessings on His servants", isFeatured: false),
            Topic(id: "existence-of-allah", label: "The existence of Allah", isFeatured: false),
            Topic(id: "promise-threat", label: "Promise and warning", isFeatured: false),
            Topic(id: "no-partner", label: "Allah has no child or partner", isFeatured: false),
            Topic(id: "shirk", label: "Shirk (associating partners with Allah)", isFeatured: false),
            Topic(id: "sincerity", label: "Sincerity to Allah (Ikhlas)", isFeatured: false),
            Topic(id: "iman", label: "Faith in Allah (Iman)", isFeatured: false),
            Topic(id: "fruits-of-faith", label: "Fruits of faith", isFeatured: false),
            Topic(id: "certainty", label: "Certainty (Yaqeen)", isFeatured: false),
            Topic(id: "doubt", label: "Doubt", isFeatured: false),
            Topic(id: "guidance", label: "Guidance to faith", isFeatured: false),
            Topic(id: "submission", label: "Submission to Allah", isFeatured: false),
            Topic(id: "khushu", label: "Humility in worship (Khushu')", isFeatured: false),
            Topic(id: "responding", label: "Responding to Allah's call", isFeatured: false),
            Topic(id: "divine-decree", label: "Divine decree (Qadar)", isFeatured: false),
            Topic(id: "unseen", label: "The unseen (Al-Ghayb)", isFeatured: false),
            Topic(id: "angels", label: "Angels", isFeatured: false),
            Topic(id: "angels-roles", label: "Angels and their duties", isFeatured: false),
            Topic(id: "angels-forgiveness", label: "Angels pray for the believers", isFeatured: false),
            Topic(id: "jibril", label: "Jibril, the angel of revelation", isFeatured: false),
            Topic(id: "jinn", label: "Jinn", isFeatured: false),
            Topic(id: "shaytan", label: "Shaytan", isFeatured: false),
            Topic(id: "whispers", label: "Shaytan's whispers and how to resist", isFeatured: false),
            Topic(id: "protection-shaytan", label: "Protection from Shaytan", isFeatured: false),
            Topic(id: "scriptures", label: "The revealed books", isFeatured: false),
            Topic(id: "revelation", label: "Revelation (Wahy)", isFeatured: false),
            Topic(id: "islam-truth", label: "Islam, the religion of truth", isFeatured: false),
            Topic(id: "blessing-islam", label: "The blessing of Islam", isFeatured: false),
            Topic(id: "freedom-belief", label: "No compulsion in religion", isFeatured: false),
            Topic(id: "fitrah", label: "Natural disposition (Fitrah)", isFeatured: false),
            Topic(id: "intercession", label: "Intercession (Shafa'ah)", isFeatured: false),
        ]),
    ]

    public static let all: [Topic] = groups.flatMap(\.topics)

    public static func topic(_ id: String) -> Topic? { all.first { $0.id == id } }

    /// Groups with only the topics that have at least one curated set
    /// (features without content are hidden). Empty groups are dropped.
    public static func available(setCounts: [String: Int]) -> [TopicGroup] {
        groups.compactMap { $0.keeping { (setCounts[$0.id] ?? 0) > 0 } }
    }
}
