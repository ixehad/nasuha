import NasuhaCore
import SwiftUI

/// About us: why the app exists, how its content is made, and every source.
struct AboutScreen: View {
    @Environment(ContentLoader.self) private var content
    @Environment(RecitationPlayer.self) private var player
    @Environment(\.openURL) private var openURL

    let open: (AppRoute) -> Void
    let onBack: () -> Void

    @State private var sources: [SourceRow] = []

    private struct SourceRow: Identifiable {
        let id: String
        let what: String
        let name: String
        let licence: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    LogoMark(size: 52)
                    Text("Nasuha")
                        .font(.title.bold())
                        .foregroundStyle(Palette.ink)
                }
                section("Why we made this") {
                    paragraph("Many of us read an ayah on social media without knowing when it came or what came before it. Nasuha sends one ayah a day on what your heart needs, always with the ayahs around it and, where an authentic report exists, the story of its revelation. So it gives hope and is never read out of context.")
                }
                section("How the content is made") {
                    VStack(alignment: .leading, spacing: 12) {
                        rule(1, "No AI writes the content", "Every story, translation and explanation comes from a named, well-known book.")
                        rule(2, "Word for word", "Translations are shown exactly as published, with their version.")
                        rule(3, "Always in context", "Every ayah links to the ayahs around it and the full surah.")
                        rule(4, "Found a mistake?", "Tap Report a mistake. We fix it in the next update, in sha Allah.")
                        rule(5, "Only authentic sources", "Trusted, widely used translations and tafsir. Stories only from narrations graded sahih or hasan. Weak reports and Isra'iliyyat are left out.")
                    }
                }
                section("Sources we use") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(sources.enumerated()), id: \.element.id) { index, row in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: row.what)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Palette.muted)
                                Text(verbatim: row.name)
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.ink)
                                Text(verbatim: row.licence)
                                    .font(.caption)
                                    .foregroundStyle(Palette.muted)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .combine)
                            if index < sources.count - 1 { RowDivider() }
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.line, lineWidth: 1))
                }
                section("Who we are") {
                    paragraph("Nasuha is made in Dhaka, Bangladesh, for the sake of Allah. Every word comes from the named sources, unchanged. The app is free and its code is public: anyone can read it, report a mistake or help add a language.")
                }
                HStack(spacing: 10) {
                    Button("Code on GitHub") { openURL(AppLinks.repository) }
                        .buttonStyle(OutlineButtonStyle(minHeight: 48))
                    Button("Contact us") { openURL(AppLinks.contact) }
                        .buttonStyle(OutlineButtonStyle(minHeight: 48))
                }
                Text("Anything right in this app is from Allah. Any mistake is from us. May Allah forgive us, and Allah knows best.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Button {
                    open(.legal)
                } label: {
                    Text("Nasuha \(AppLinks.appVersion) · Privacy and terms")
                        .font(.caption)
                        .foregroundStyle(Palette.accent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { ScreenHeader(title: "About us", onBack: onBack) }
        .task { loadSources() }
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func paragraph(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.callout)
            .lineSpacing(3)
            .foregroundStyle(Palette.ink2)
    }

    private func rule(_ number: Int, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: number.formatted())
                .font(.footnote.weight(.bold))
                .foregroundStyle(Palette.tintInk)
                .frame(width: 28, height: 28)
                .background(Palette.tint, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The table is built from what the content file holds, so names and versions are always the real ones.
    private func loadSources() {
        var rows: [SourceRow] = []
        let store = content.store
        let meta = try? store?.meta()
        rows.append(SourceRow(id: "arabic", what: String(localized: "Arabic text"),
                              name: meta?.values["tanzil_credit"] ?? "Tanzil Quran Text (Uthmani), tanzil.net",
                              licence: String(localized: "CC BY 3.0, used unchanged")))
        for source in (try? store?.translationSources()) ?? [] {
            rows.append(SourceRow(id: source.key,
                                  what: String(localized: "Translation · \(LanguageName.autonym(source.language))"),
                                  name: "\(source.title) · QuranEnc.com",
                                  licence: String(localized: "Free use with credit · version \(source.version)")))
        }
        if !((try? store?.tafsirLanguages()) ?? []).isEmpty {
            rows.append(SourceRow(id: "tafsir", what: String(localized: "Explanation"),
                                  name: "Al-Mukhtasar fi Tafsir al-Qur'an · QuranEnc.com",
                                  licence: String(localized: "Free use with credit")))
        }
        rows.append(SourceRow(id: "asbab", what: String(localized: "Stories of revelation"),
                              name: "al-Wahidi, Asbab al-Nuzul · as-Suyuti, Lubab an-Nuqul",
                              licence: String(localized: "Only reports graded authentic are used")))
        rows.append(SourceRow(id: "hadith", what: String(localized: "Hadith"),
                              name: "Sahih al-Bukhari · Sahih Muslim",
                              licence: String(localized: "Number and grade shown each time")))
        if let reciter = player.reciter {
            rows.append(SourceRow(id: "recitation", what: String(localized: "Recitation"),
                                  name: "\(reciter.name) (\(reciter.riwayah))",
                                  licence: String(localized: "Shared with permission of the rights holder")))
        }
        rows.append(SourceRow(id: "font", what: String(localized: "Fonts"),
                              name: "Amiri Quran · Hind Siliguri",
                              licence: "SIL Open Font License"))
        sources = rows
    }
}

/// Privacy and Terms.
struct LegalScreen: View {
    @Environment(\.openURL) private var openURL
    let onBack: () -> Void

    @State private var showsTerms = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(showsTerms ? LegalText.termsSummary : LegalText.privacySummary)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Palette.tintInk)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                ForEach(showsTerms ? LegalText.terms : LegalText.privacy) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.heading)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text(item.text)
                            .font(.subheadline)
                            .lineSpacing(2)
                            .foregroundStyle(Palette.ink2)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last updated 12 November 2026")
                    Button("The full text is also on our website.") { openURL(AppLinks.privacyPage) }
                        .foregroundStyle(Palette.accent)
                        .frame(minHeight: 44)
                }
                .font(.caption)
                .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 8) {
                ScreenHeader(title: "Privacy and terms", onBack: onBack)
                SegmentedBar(options: [(false, String(localized: "Privacy")), (true, String(localized: "Terms"))],
                             selection: $showsTerms)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }
            .background(Palette.bg)
        }
    }
}

/// The legal text. PRIVACY.md in the repository mirrors it.
enum LegalText {
    struct Item: Identifiable {
        let id: Int
        let heading: LocalizedStringKey
        let text: LocalizedStringKey
    }

    static let privacySummary: LocalizedStringKey = "In short: nothing about you ever leaves your phone."
    static let termsSummary: LocalizedStringKey = "In short: free to use, sources always named, and not a replacement for a scholar."

    static let privacy: [Item] = [
        Item(id: 1, heading: "No account, no tracking",
             text: "You never sign up. We do not collect your name, email, location or how you use the app. There are no ads and no analytics."),
        Item(id: 2, heading: "What stays on your phone",
             text: "Your name (if you add one), topics, reminder time, languages, saved ayahs and reading progress. Deleting the app deletes all of it."),
        Item(id: 3, heading: "Reminders",
             text: "Reminders are set up on your iPhone itself. No server knows when or what you read."),
        Item(id: 4, heading: "Languages",
             text: "To decide which languages to offer, the app reads the region and language set on your iPhone. It does not use your location, and this never leaves your phone."),
        Item(id: 5, heading: "Recitation",
             text: "The Qur'an text and translations are inside the app. When you play a recitation, the audio file downloads from the recitation host. That host sees a normal web request, like any website. We send nothing about you."),
        Item(id: 6, heading: "Tips",
             text: "Tips are paid through Apple. We never see your card or Apple ID details."),
        Item(id: 7, heading: "Report a mistake",
             text: "Reporting a mistake opens your own email app or our public issue page. You choose what to send."),
        Item(id: 8, heading: "Children",
             text: "Nasuha is safe for all ages and collects nothing from anyone, including children."),
        Item(id: 9, heading: "Changes",
             text: "If this ever changes, we will tell you in the app before it happens."),
    ]

    static let terms: [Item] = [
        Item(id: 1, heading: "Free to use",
             text: "Nasuha is free. Tips are optional and give no extra features."),
        Item(id: 2, heading: "Not a fatwa",
             text: "Stories and explanations are taken from the sources we name. They are for learning and reminding, not religious rulings. For a ruling, ask a qualified scholar."),
        Item(id: 3, heading: "Mistakes",
             text: "We check everything with care, but we are human. If you find a mistake, tap Report a mistake and we will fix it, in sha Allah."),
        Item(id: 4, heading: "Respect for the Qur'an",
             text: "Please share ayahs respectfully and with their reference."),
        Item(id: 5, heading: "Content licences",
             text: "The Arabic text, translations, tafsir and recitation belong to their owners and are used under their licences, listed in About us."),
        Item(id: 6, heading: "The code",
             text: "The app's code is public under the PolyForm Noncommercial licence. You may read, copy and change it for non-commercial use. You may not sell it, and the Nasuha name and logo are not included."),
        Item(id: 7, heading: "No warranty",
             text: "The app is provided as it is. We are not responsible for missed reminders caused by your phone settings."),
    ]
}

/// Optional tips. Shown only when Apple has returned the products.
struct SupportScreen: View {
    @Environment(TipStore.self) private var tips
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Nasuha is free and always will be. A tip helps cover the costs. It is optional and gives no extra features.")
                    .font(.callout)
                    .lineSpacing(3)
                    .foregroundStyle(Palette.ink2)
                if tips.didThank {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Palette.dawn, in: Circle())
                            .accessibilityHidden(true)
                        Text("Thank you. May Allah reward you with good.")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Palette.dawnInk)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.dawnTint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                ForEach(tips.products) { product in
                    Button {
                        Task { await tips.tip(product) }
                    } label: {
                        HStack {
                            Text(verbatim: product.displayName)
                            Spacer()
                            Text(verbatim: product.displayPrice)
                                .foregroundStyle(Palette.accent)
                        }
                    }
                    .buttonStyle(OutlineButtonStyle(minHeight: 54))
                    .disabled(tips.isPurchasing)
                }
                if tips.failed {
                    Text("The tip didn't go through. You were not charged.")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                }
                Text("Tips are paid through Apple. We never see your card details.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { ScreenHeader(title: "Support Nasuha", onBack: onBack) }
        .task { await tips.load() }
    }
}
