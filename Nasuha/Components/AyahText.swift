import NasuhaCore
import SwiftUI

/// Qur'an Arabic: Amiri Quran, right to left, in full.
struct ArabicText: View {
    let text: String
    let size: CGFloat
    let style: Font.TextStyle

    init(_ text: String, size: CGFloat = 27, style: Font.TextStyle = .title2) {
        self.text = text
        self.size = size
        self.style = style
    }

    var body: some View {
        Text(verbatim: text)
            .font(Fonts.arabic(size, relativeTo: style))
            .lineSpacing(size * 0.45)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale(identifier: "ar"))
            .foregroundStyle(Palette.ink)
            .accessibilityLanguage("ar")
    }
}

/// One translation, in the font of its language.
struct TranslationText: View {
    let item: SourcedTranslation
    let size: CGFloat
    let style: Font.TextStyle
    var color: Color = Palette.ink

    init(_ item: SourcedTranslation, size: CGFloat = 18, style: Font.TextStyle = .body, color: Color = Palette.ink) {
        self.item = item
        self.size = size
        self.style = style
        self.color = color
    }

    var body: some View {
        Text(verbatim: item.translation.text)
            .font(item.source.language == "bn" ? Fonts.bangla(size, relativeTo: style) : .system(style, design: .serif))
            .lineSpacing(4)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLanguage(item.source.language)
    }
}

private extension View {
    /// Tells VoiceOver which language to read the text in.
    func accessibilityLanguage(_ code: String) -> some View {
        environment(\.locale, Locale(identifier: code))
    }
}

/// Wording for where and when an ayah was revealed, built from the set's data.
enum RevelationText {
    static func place(_ place: RevelationPlace) -> String {
        switch place {
        case .makkah: String(localized: "Makkah")
        case .madinah: String(localized: "Madinah")
        }
    }

    /// "Makkah · the Prophet ﷺ was about 40–41 (approx.)". Nil when the set gives neither.
    static func summary(_ detail: AyahDetail) -> String? {
        guard let when = detail.ayahSet.when else { return nil }
        var parts: [String] = []
        if let place = when.place { parts.append(self.place(place)) }
        if let age = when.ageText { parts.append(String(localized: "the Prophet ﷺ was about \(age) (approx.)")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The text shared from the Ayah and Done screens: the ayah, its translation and where each came from.
    static func shareText(_ detail: AyahDetail) -> String {
        var lines = [detail.arabic]
        for item in detail.translations {
            lines.append(item.translation.text)
        }
        lines.append(detail.reference)
        let sources = detail.translations.map(\.source.title)
        if !sources.isEmpty { lines.append(sources.joined(separator: " · ")) }
        return lines.joined(separator: "\n\n")
    }
}
