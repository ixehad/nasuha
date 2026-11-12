import Foundation

/// Which content languages are offered to a person.
///
/// English and Arabic are offered everywhere. A regional language is offered where it is
/// spoken: when the phone's region is one of its home regions, or when the person has
/// that language in the phone's language list. Both come from the phone's own settings;
/// the app never asks for or reads the person's location.
public enum LanguageOffer {
    /// Languages offered everywhere.
    public static let global: Set<String> = ["en", "ar"]

    /// Home regions of each regional language, as ISO 3166 codes.
    public static let homeRegions: [String: Set<String>] = [
        "bn": ["BD"],
    ]

    public static func isOffered(_ language: String, region: String?, preferredLanguages: [String]) -> Bool {
        if global.contains(language) { return true }
        if let region, homeRegions[language]?.contains(region.uppercased()) == true { return true }
        return preferredLanguages.contains { code in
            let base = code.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? code
            return base.lowercased() == language
        }
    }

    /// The same check with the phone's current region and language list.
    public static func isOffered(_ language: String) -> Bool {
        isOffered(language, region: Locale.current.region?.identifier, preferredLanguages: Locale.preferredLanguages)
    }

    /// Keeps the sources whose language is offered, plus any the person already chose.
    public static func offered(_ sources: [TranslationSource], keeping chosen: [String] = [],
                               region: String?, preferredLanguages: [String]) -> [TranslationSource] {
        sources.filter {
            chosen.contains($0.key) || isOffered($0.language, region: region, preferredLanguages: preferredLanguages)
        }
    }
}
