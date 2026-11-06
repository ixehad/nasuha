import NasuhaCore
import SwiftUI

// Core types carry English copy; it doubles as the String Catalog key.
extension Topic {
    var localizedLabel: String { String(localized: String.LocalizationValue(label)) }
    var localizedReminderTitle: String { String(localized: String.LocalizationValue(reminderTitle)) }
}

extension TopicGroup {
    var localizedTitle: String { String(localized: String.LocalizationValue(title)) }
    var localizedNote: String? { note.map { String(localized: String.LocalizationValue($0)) } }
}
