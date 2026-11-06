import Foundation

/// Light and dark colour tokens. The app wraps
/// these in dynamic SwiftUI colours in Nasuha/Theme/Palette.swift.
public enum PaletteToken: String, CaseIterable, Sendable {
    case bg, surface, fill, line, ink, ink2, muted, accent, onAccent
    case tint, tintInk, dawn, dawnInk, dawnTint, before, beforeInk

    public var light: UInt32 { PaletteToken.table[self]!.light }
    public var dark: UInt32 { PaletteToken.table[self]!.dark }

    private static let table: [PaletteToken: (light: UInt32, dark: UInt32)] = [
        .bg: (0xFFFFFF, 0x000000),
        .surface: (0xFFFFFF, 0x141417),
        .fill: (0xF6F5FA, 0x1C1C21),
        .line: (0xECEAF3, 0x2A2A31),
        .ink: (0x16141F, 0xF5F4F8),
        .ink2: (0x3B3850, 0xD6D4DE),
        .muted: (0x605D70, 0xA4A2B0),
        .accent: (0x5B3FA8, 0xB7A1F4),
        .onAccent: (0xFFFFFF, 0x160F2B),
        .tint: (0xF3EFFD, 0x1E1833),
        .tintInk: (0x3E2A7A, 0xDCCFFC),
        .dawn: (0xE9963E, 0xF3B66E),
        .dawnInk: (0x8A4B10, 0xF6CF9C),
        .dawnTint: (0xFDF1E4, 0x2A1E10),
        .before: (0xEEF2FF, 0x151B33),
        .beforeInk: (0x2E3F8F, 0xA9B8F5),
    ]
}

public enum ColorMath {
    public static func components(_ hex: UInt32) -> (r: Double, g: Double, b: Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    /// WCAG 2.x relative luminance.
    public static func luminance(_ hex: UInt32) -> Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let (r, g, b) = components(hex)
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    public static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
