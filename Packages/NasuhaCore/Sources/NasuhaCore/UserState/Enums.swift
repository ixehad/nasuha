import Foundation

public enum ReminderFrequency: String, Codable, CaseIterable, Sendable {
    case daily, everyTwoDays, fridays
}

public enum AppearanceMode: String, Codable, CaseIterable, Sendable {
    case system, light, dark
}

/// What happens after the last ayah in the user's topics is sent.
public enum EndOfQueueBehaviour: String, Codable, CaseIterable, Sendable {
    /// Show AllRead on next open; if the user does nothing, start again from the first ayah.
    case askThenRestart
}

public enum TextSizeStep: Int, Codable, CaseIterable, Sendable {
    case small = -1, standard = 0, large = 1, larger = 2
}
