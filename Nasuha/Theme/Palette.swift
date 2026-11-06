import NasuhaCore
import SwiftUI
import UIKit

/// Dynamic colours from the design tokens. They follow the system appearance,
/// or the user's override in Settings (applied with `.preferredColorScheme`).
enum Palette {
    static let bg = color(.bg)
    static let surface = color(.surface)
    static let fill = color(.fill)
    static let line = color(.line)
    static let ink = color(.ink)
    static let ink2 = color(.ink2)
    static let muted = color(.muted)
    /// One accent button per screen.
    static let accent = color(.accent)
    static let onAccent = color(.onAccent)
    /// Today's ayah.
    static let tint = color(.tint)
    static let tintInk = color(.tintInk)
    /// Good moments only: done, saved, progress.
    static let dawn = color(.dawn)
    static let dawnInk = color(.dawnInk)
    /// Ayahs after today's.
    static let dawnTint = color(.dawnTint)
    /// Ayahs before today's.
    static let before = color(.before)
    static let beforeInk = color(.beforeInk)

    private static func color(_ token: PaletteToken) -> Color {
        Color(uiColor: UIColor { traits in
            uiColor(traits.userInterfaceStyle == .dark ? token.dark : token.light)
        })
    }

    private static func uiColor(_ hex: UInt32) -> UIColor {
        let c = ColorMath.components(hex)
        return UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
    }
}

extension AppearanceMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
