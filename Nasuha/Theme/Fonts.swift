import SwiftUI

/// Bundled fonts. All scale with Dynamic Type through `relativeTo:`.
enum Fonts {
    /// Amiri Quran (OFL) for Qur'an Arabic.
    static func arabic(_ size: CGFloat = 26, relativeTo style: Font.TextStyle = .title2) -> Font {
        .custom("AmiriQuran-Regular", size: size, relativeTo: style)
    }

    /// Hind Siliguri (OFL) for Bangla.
    static func bangla(_ size: CGFloat = 17, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        let name = switch weight {
        case .semibold, .bold, .heavy, .black: "HindSiliguri-SemiBold"
        case .medium: "HindSiliguri-Medium"
        default: "HindSiliguri-Regular"
        }
        return .custom(name, size: size, relativeTo: style)
    }

    /// Translation text: Hind Siliguri for Bangla, the system font otherwise.
    static func translation(language: String, size: CGFloat = 17, relativeTo style: Font.TextStyle = .body) -> Font {
        language == "bn" ? bangla(size, relativeTo: style) : .system(style)
    }
}
