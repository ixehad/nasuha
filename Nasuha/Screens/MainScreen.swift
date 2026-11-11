import NasuhaCore
import SwiftUI

/// First open: a sample ayah of hope and the two ways in.
struct MainScreen: View {
    @Environment(ContentLoader.self) private var content
    let onSetUp: () -> Void
    let onLookAround: () -> Void

    /// The ayah shown on first open.
    private static let sampleKey = AyahKey(surah: 39, ayah: 53)

    @State private var sample: Sample?

    private struct Sample {
        let arabic: String
        let translation: Translation?
        let language: String
        let surahName: String?
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    LogoMark(size: 44)
                    Text("Nasuha")
                        .font(.title2.bold())
                        .foregroundStyle(Palette.ink)
                }
                if let sample {
                    Label("An ayah of hope for you", systemImage: "sunrise")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 28)
                        .foregroundStyle(Palette.dawnInk)
                        .background(Palette.dawnTint, in: Capsule())
                    ArabicText(sample.arabic, size: 31, style: .title)
                    if let translation = sample.translation {
                        Text(translation.text)
                            .font(sample.language == "bn" ? Fonts.bangla(20, relativeTo: .title3) : .system(.title3, design: .serif))
                            .lineSpacing(4)
                            .foregroundStyle(Palette.ink)
                    }
                    Text(reference(sample))
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .background(Palette.bg)
        .safeAreaInset(edge: .bottom, spacing: 0) { actions }
        .task { loadSample() }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("One ayah a day, chosen by you")
                .font(.title3.bold())
                .foregroundStyle(Palette.ink)
            Text("Pick what your heart needs: hope, tawbah, or the story behind an ayah. We send it at a quiet time.")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
            Button("Set up in 30 seconds", action: onSetUp)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 4)
            Button("Just look around", action: onLookAround)
                .buttonStyle(TextLinkButtonStyle())
            Text("Free · No account · No ads")
                .font(.caption)
                .foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(Palette.surface)
                .shadow(color: Color(red: 40 / 255, green: 28 / 255, blue: 90 / 255).opacity(0.08), radius: 15, y: -10)
                .overlay(alignment: .top) {
                    UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                        .stroke(Palette.line, lineWidth: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func reference(_ sample: Sample) -> String {
        let key = Self.sampleKey.description
        guard let name = sample.surahName else { return key }
        return String(localized: "Surah \(name) · \(key)")
    }

    /// Reads the ayah and its translation from the content database. Shows nothing if it isn't there.
    private func loadSample() {
        guard sample == nil, let store = content.store,
              let ayah = try? store.ayah(Self.sampleKey) else { return }
        let appLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        var translation: Translation?
        var language = appLanguage
        if let own = try? store.translation(for: Self.sampleKey, language: appLanguage) {
            translation = own
        } else if let english = try? store.translation(for: Self.sampleKey, language: "en") {
            translation = english
            language = "en"
        }
        sample = Sample(arabic: ayah.arabic, translation: translation, language: language,
                        surahName: (try? store.surah(Self.sampleKey.surah))?.nameTransliterated)
    }
}
