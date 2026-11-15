import NasuhaCore
import SwiftData
import SwiftUI
import UIKit

/// Profile: an optional local name, gentle progress, and links.
struct ProfileScreen: View {
    @Environment(ContentLoader.self) private var content
    @Environment(RecitationPlayer.self) private var player
    @Environment(TipStore.self) private var tips
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query private var allSettings: [UserSettings]
    @Query(sort: \TopicChoice.order) private var choices: [TopicChoice]
    @Query private var reads: [ReadRecord]
    @Query private var saved: [SavedAyah]
    @Query private var progress: [ReadingProgress]

    let open: (AppRoute) -> Void
    let onBack: () -> Void

    @State private var isEditingName = false
    @State private var nameDraft = ""
    @State private var topics: [TopicProgress] = []

    private var name: String { (allSettings.first?.name ?? "").trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                identity
                stats
                if !topics.isEmpty {
                    topicBars
                }
                RowGroup {
                    NavRow(title: "Saved ayahs", value: saved.count.formatted()) { open(.saved) }
                    if player.isAvailable, let reciter = player.reciter {
                        RowDivider()
                        RowLabel(title: "Reciter", value: reciter.name, showsChevron: false)
                    }
                    RowDivider()
                    NavRow(title: "App language", value: LanguageName.autonym(appLanguage)) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    RowDivider()
                    NavRow(title: "All settings") { open(.settings) }
                }
                RowGroup {
                    NavRow(title: "About us") { open(.about) }
                    RowDivider()
                    NavRow(title: "Privacy and terms") { open(.legal) }
                    if tips.isAvailable {
                        RowDivider()
                        NavRow(title: "Support Nasuha", value: String(localized: "Optional tip")) { open(.support) }
                    }
                }
                Text("May Allah accept from you and from us.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { ScreenHeader(title: "Profile", onBack: onBack) }
        .task {
            loadTopics()
            await tips.load()
        }
        .onChange(of: reads.count) { loadTopics() }
        .alert("Your name", isPresented: $isEditingName) {
            TextField("Name", text: $nameDraft)
                .textInputAutocapitalization(.words)
            Button("Save") { saveName() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It stays on this phone. Leave it empty to remove it.")
        }
    }

    // MARK: Name

    private var identity: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(verbatim: name.first.map { String($0).uppercased() } ?? "")
                    .font(.title2.bold())
                    .foregroundStyle(Palette.tintInk)
                    .frame(width: 56, height: 56)
                    .background(Palette.tint, in: Circle())
                    .overlay {
                        if name.isEmpty {
                            Image(systemName: "person")
                                .font(.title3)
                                .foregroundStyle(Palette.tintInk)
                        }
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name.isEmpty ? String(localized: "Add your name") : name)
                        .font(.title3.bold())
                        .foregroundStyle(Palette.ink)
                    if let since = sinceText {
                        Text(verbatim: since)
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                    }
                }
                Spacer(minLength: 8)
                Button("Edit") {
                    nameDraft = name
                    isEditingName = true
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.accent)
                .frame(minWidth: 44, minHeight: 44)
            }
            Text("No account. Your name and progress stay on this phone.")
                .font(.footnote)
                .foregroundStyle(Palette.muted)
        }
    }

    /// "Reading with Nasuha since Shawwal 1447", in the Hijri calendar.
    private var sinceText: String? {
        guard let joined = allSettings.first?.joinedAt else { return nil }
        var calendar = Calendar(identifier: .islamicUmmAlQura)
        calendar.timeZone = .current
        var style = Date.FormatStyle.dateTime.month(.wide).year()
        style.calendar = calendar
        return String(localized: "Reading with Nasuha since \(joined.formatted(style))")
    }

    private func saveName() {
        guard let settings = try? UserSettings.current(in: context) else { return }
        settings.name = String(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        try? context.save()
    }

    private var appLanguage: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    // MARK: Progress

    private var stats: some View {
        let items = statItems
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(items, id: \.label) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: item.value)
                        .font(.title3.bold())
                        .foregroundStyle(Palette.ink)
                    Text(verbatim: item.label)
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var statItems: [(value: String, label: String)] {
        var items: [(String, String)] = [
            (reads.count.formatted(), String(localized: "Ayahs read")),
            (reads.filter(\.hadStory).count.formatted(), String(localized: "Stories learned")),
            ((progress.first?.surahsOpened.count ?? 0).formatted(), String(localized: "Surahs opened")),
        ]
        let seconds = progress.first?.listeningSeconds ?? 0
        if player.isAvailable || seconds > 0 {
            items.append((Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .narrow)),
                          String(localized: "Listening")))
        }
        return items
    }

    private var topicBars: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your topics")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(topics.map(\.read).reduce(0, +)) of \(topics.map(\.total).reduce(0, +)) ayahs")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
            ForEach(topics) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(verbatim: TopicCatalog.topic(item.topicID)?.localizedLabel ?? item.topicID)
                            .font(.subheadline)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text("\(item.read) of \(item.total)")
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.line)
                            Capsule().fill(Palette.dawn).frame(width: proxy.size.width * item.fraction)
                        }
                    }
                    .frame(height: 6)
                    .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func loadTopics() {
        guard let store = content.store else { return }
        var sets: [String: [String]] = [:]
        for choice in choices { sets[choice.topicID] = (try? store.setIDs(topic: choice.topicID)) ?? [] }
        topics = TopicProgress.all(topics: choices.map(\.topicID), setsByTopic: sets, read: Set(reads.map(\.ayahSetID)))
    }
}

/// The ayahs the person kept.
struct SavedScreen: View {
    @Environment(ContentLoader.self) private var content
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedAyah.savedAt, order: .reverse) private var saved: [SavedAyah]
    @Query private var allSettings: [UserSettings]

    let open: (AppRoute) -> Void
    let onBack: () -> Void

    @State private var items: [Item] = []

    private struct Item: Identifiable {
        var id: String { key.description }
        let key: AyahKey
        let setID: String?
        let reference: String
        let arabic: String
        let translation: SourcedTranslation?
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if items.isEmpty {
                    Text("Ayahs you save will be kept here.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, minHeight: 160)
                }
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(verbatim: item.reference)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.dawnInk)
                            Spacer()
                            Button {
                                remove(item.key)
                            } label: {
                                Image(systemName: "bookmark.fill")
                                    .foregroundStyle(Palette.dawn)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove from saved")
                        }
                        Button {
                            show(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ArabicText(item.arabic, size: 24, style: .title2)
                                if let translation = item.translation {
                                    TranslationText(translation, size: 16, style: .callout, color: Palette.ink2)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 6)
                    .padding(.bottom, 16)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.line, lineWidth: 1))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { ScreenHeader(title: "Saved ayahs", onBack: onBack) }
        .task { load() }
        .onChange(of: saved.count) { load() }
    }

    private func load() {
        guard let store = content.store else { return }
        let sources = (try? AyahDetailLoader(store: store)
            .resolveSources(preferred: allSettings.first?.readingTranslations ?? [])) ?? []
        items = saved.compactMap { record in
            guard let key = AyahKey(record.ayahKey), let ayah = try? store.ayah(key) else { return nil }
            let name = (try? store.surah(key.surah))?.nameTransliterated
            let text = (try? store.translations(for: [key], sources: sources.prefix(1).map(\.key)))?[key]?.first
            let translation = text.flatMap { t in sources.first.map { SourcedTranslation(source: $0, translation: t) } }
            return Item(key: key, setID: record.ayahSetID,
                        reference: [name, key.description].compactMap { $0 }.joined(separator: " "),
                        arabic: ayah.arabic, translation: translation)
        }
    }

    /// Opens the ayah with its story when it came from a topic, else in the reader.
    private func show(_ item: Item) {
        if let setID = item.setID, (try? content.store?.ayahSet(id: setID)) != nil {
            router.ayah = AyahTarget(setID: setID)
        } else {
            open(.reader(ReaderTarget(surah: item.key.surah, ayah: item.key.ayah)))
        }
    }

    private func remove(_ key: AyahKey) {
        if let record = saved.first(where: { $0.ayahKey == key.description }) {
            context.delete(record)
            try? context.save()
        }
    }
}
