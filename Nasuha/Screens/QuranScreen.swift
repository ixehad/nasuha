import NasuhaCore
import SwiftData
import SwiftUI

/// Where the reader should open.
struct ReaderTarget: Hashable {
    var surah: Int
    /// The ayah to scroll to. Nil opens at the top.
    var ayah: Int?
    /// The curated set whose ayah is marked TODAY, with the ayahs around it colour-coded.
    var todaySetID: String?
}

/// The Qur'an reader: one surah at a time, with a surah picker and search.
struct QuranScreen: View {
    @Environment(ContentLoader.self) private var content
    @Environment(RecitationPlayer.self) private var player
    @Environment(\.modelContext) private var context
    @Query private var settings: [UserSettings]
    @Query private var saved: [SavedAyah]
    @Query private var records: [ReminderRecord]
    @AppStorage("readerShowsTranslation") private var showsTranslation = true

    let target: ReaderTarget
    let onBack: () -> Void
    /// Opens the story of today's ayah.
    let onStory: (String) -> Void

    @State private var surahs: [Surah] = []
    @State private var surah: Surah?
    @State private var ayahs: [Ayah] = []
    @State private var sources: [TranslationSource] = []
    @State private var translations: [String: [Int: Translation]] = [:]
    @State private var today: AyahSet?
    @State private var visibleAyah: Int?
    @State private var showsPicker = false
    @State private var didOpen = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if let surah {
                    if let today, today.ayah.surah == surah.number {
                        todayBanner(today)
                            .padding(.bottom, 6)
                    }
                    if let bismillah = surah.bismillah, !bismillah.isEmpty {
                        Text(verbatim: bismillah)
                            .font(Fonts.arabic(26, relativeTo: .title2))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(Palette.ink)
                            .environment(\.locale, Locale(identifier: "ar"))
                    }
                    ForEach(ayahs) { ayah in
                        ReaderRow(
                            ayah: ayah,
                            role: role(of: ayah.key),
                            isReciting: player.currentKey == ayah.key && player.status != .idle,
                            translations: showsTranslation ? texts(for: ayah.key.ayah) : [],
                            isSaved: saved.contains { $0.ayahKey == ayah.key.description },
                            audioAvailable: player.isAvailable,
                            onSave: { toggleSaved(ayah.key) })
                            .id(ayah.key.ayah)
                    }
                    neighbours(of: surah)
                        .padding(.top, 10)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .scrollPosition(id: $visibleAyah, anchor: .top)
        .background(Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if player.isAvailable, let surah {
                playerBar(surah)
            }
        }
        .sheet(isPresented: $showsPicker) {
            SurahPicker(surahs: surahs, current: surah?.number) { number in
                open(surah: number, ayah: nil)
            }
        }
        .task { start() }
        .onChange(of: visibleAyah) { remember() }
        .onChange(of: player.currentKey) { _, key in follow(key) }
        .onChange(of: settings.first?.readingTranslations) { loadTranslations() }
        .onDisappear { try? context.save() }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                IconButton(systemName: "chevron.backward", label: "Back", action: onBack)
                Spacer(minLength: 4)
                Button {
                    showsPicker = true
                } label: {
                    VStack(spacing: 1) {
                        HStack(spacing: 4) {
                            Text(verbatim: surah.map { "\($0.number) · \($0.nameTransliterated)" } ?? "")
                                .font(.callout.weight(.semibold))
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.bold))
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(Palette.ink)
                        if let surah {
                            Text(verbatim: subtitle(surah))
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                        }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the list of surahs")
                Spacer(minLength: 4)
                IconButton(systemName: "magnifyingglass", label: "Find a surah") { showsPicker = true }
            }
            .padding(.horizontal, 10)
            SegmentedBar(options: [
                (true, String(localized: "Arabic + translation")),
                (false, String(localized: "Arabic only")),
            ], selection: $showsTranslation)
            .padding(.horizontal, 18)
            .padding(.bottom, 8)
        }
        .background(Palette.bg)
    }

    private func subtitle(_ surah: Surah) -> String {
        var parts = [surah.nameEnglish]
        if let place = surah.place {
            parts.append(place == .makkah ? String(localized: "Makki") : String(localized: "Madani"))
        }
        parts.append(String(localized: "\(surah.ayahCount) ayahs"))
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: Today's ayah

    private func todayBanner(_ set: AyahSet) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sunrise")
                .accessibilityHidden(true)
            Text("Ayah \(set.ayah.ayah) is today's ayah.")
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Story") { onStory(set.id) }
                .font(.footnote.weight(.bold))
                .foregroundStyle(Palette.accent)
                .frame(minWidth: 44, minHeight: 44)
        }
        .foregroundStyle(Palette.tintInk)
        .padding(.horizontal, 12)
        .background(Palette.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func role(of key: AyahKey) -> ContextRole? {
        guard let today, today.ayah.surah == key.surah else { return nil }
        if key == today.ayah { return .today }
        if today.before.suffix(2).contains(key) { return .before }
        if today.after.prefix(2).contains(key) { return .after }
        return nil
    }

    // MARK: Previous and next

    private func neighbours(of surah: Surah) -> some View {
        let index = surahs.firstIndex { $0.number == surah.number }
        let previous = index.flatMap { $0 > 0 ? surahs[$0 - 1] : nil }
        let next = index.flatMap { $0 + 1 < surahs.count ? surahs[$0 + 1] : nil }
        return HStack(alignment: .top, spacing: 8) {
            if let previous {
                neighbour(previous, label: "Previous", icon: "arrow.backward", alignment: .leading)
            }
            if let next {
                neighbour(next, label: "Next", icon: "arrow.forward", alignment: .trailing)
            }
        }
    }

    private func neighbour(_ surah: Surah, label: LocalizedStringKey, icon: String, alignment: HorizontalAlignment) -> some View {
        Button {
            open(surah: surah.number, ayah: nil)
        } label: {
            VStack(alignment: alignment, spacing: 2) {
                HStack(spacing: 4) {
                    if alignment == .leading { Image(systemName: icon).accessibilityHidden(true) }
                    Text(label)
                    if alignment == .trailing { Image(systemName: icon).accessibilityHidden(true) }
                }
                .font(.caption)
                .foregroundStyle(Palette.muted)
                Text(verbatim: "\(surah.number) · \(surah.nameTransliterated)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: alignment == .leading ? .leading : .trailing)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Player

    private func playerBar(_ surah: Surah) -> some View {
        let plan = PlaybackPlan(surah: surah.number, ayahCount: surah.ayahCount)
        let active = player.isActive(plan)
        return HStack(spacing: 12) {
            PlayButton(plan: plan, label: String(localized: "Play the whole surah"), diameter: 46, filled: true)
            VStack(alignment: .leading, spacing: 1) {
                if active, let key = player.currentKey {
                    Text("\(surah.nameTransliterated) · ayah \(key.ayah)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                } else {
                    Text("Play \(surah.nameTransliterated)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                }
                Text(player.status == .failed
                     ? LocalizedStringKey("Couldn't load the recitation. Check your connection.")
                     : LocalizedStringKey("Follows along, ayah by ayah"))
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
            if active {
                IconButton(systemName: "stop.fill", label: "Stop") { player.stop() }
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(Palette.surface, in: Capsule())
        .overlay(Capsule().stroke(Palette.line, lineWidth: 1))
        .shadow(color: Color(red: 40 / 255, green: 28 / 255, blue: 90 / 255).opacity(0.10), radius: 12, y: 8)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    private func follow(_ key: AyahKey?) {
        guard let key, key.surah == surah?.number else { return }
        withAnimation(.easeInOut(duration: 0.3)) { visibleAyah = key.ayah }
    }

    // MARK: Loading

    private func start() {
        guard !didOpen, let store = content.store else { return }
        didOpen = true
        surahs = (try? store.surahs()) ?? []
        let todayID = target.todaySetID ?? records.first?.state.currentSetID
        today = todayID.flatMap { try? store.ayahSet(id: $0) }
        open(surah: target.surah, ayah: target.ayah)
    }

    private func open(surah number: Int, ayah: Int?) {
        guard let store = content.store,
              let next = surahs.first(where: { $0.number == number }) ?? surahs.first else { return }
        surah = next
        ayahs = (try? store.ayahs(inSurah: next.number)) ?? []
        loadTranslations()
        // Scroll once the new rows are laid out; setting it in the same pass can be ignored.
        let destination = ayah ?? 1
        visibleAyah = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            if surah?.number == next.number { visibleAyah = destination }
        }
        if let progress = try? ReadingProgress.current(in: context) {
            progress.markOpened(surah: next.number)
            progress.lastAyah = ayah ?? 1
        }
    }

    private func loadTranslations() {
        guard let store = content.store, let surah else { return }
        sources = (try? AyahDetailLoader(store: store)
            .resolveSources(preferred: settings.first?.readingTranslations ?? [])) ?? []
        var loaded: [String: [Int: Translation]] = [:]
        for source in sources {
            loaded[source.key] = try? store.translations(inSurah: surah.number, source: source.key)
        }
        translations = loaded
    }

    private func texts(for ayah: Int) -> [ReaderRow.Line] {
        sources.compactMap { source in
            translations[source.key]?[ayah].map { ReaderRow.Line(language: source.language, text: $0.text) }
        }
    }

    /// Remembers the place, so "Continue" on Home comes back here.
    private func remember() {
        guard let surah, let visibleAyah, let progress = try? ReadingProgress.current(in: context) else { return }
        progress.lastSurah = surah.number
        progress.lastAyah = visibleAyah
    }

    private func toggleSaved(_ key: AyahKey) {
        if let existing = saved.first(where: { $0.ayahKey == key.description }) {
            context.delete(existing)
        } else {
            context.insert(SavedAyah(ayahKey: key.description))
        }
        try? context.save()
    }
}

/// One ayah in the reader.
struct ReaderRow: View {
    struct Line: Hashable {
        let language: String
        let text: String
    }

    let ayah: Ayah
    let role: ContextRole?
    let isReciting: Bool
    let translations: [Line]
    let isSaved: Bool
    let audioAvailable: Bool
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(bar)
                .frame(width: role == .today ? 5 : 3)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(verbatim: "\(ayah.key.ayah)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .frame(minWidth: 28, minHeight: 28)
                        .foregroundStyle(role == .today ? Palette.onAccent : Palette.ink2)
                        .background(role == .today ? Palette.accent : Palette.fill, in: Capsule())
                        .accessibilityLabel("Ayah \(ayah.key.ayah)")
                    if let label {
                        Text(verbatim: label)
                            .font(.caption2.weight(.bold))
                            .textCase(.uppercase)
                            .tracking(0.4)
                            .foregroundStyle(ink)
                    }
                    Spacer(minLength: 0)
                    if audioAvailable {
                        PlayButton(plan: PlaybackPlan(keys: [ayah.key]),
                                   label: String(localized: "Play ayah \(ayah.key.ayah)"), diameter: 36)
                    }
                    Button(action: onSave) {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.subheadline)
                            .foregroundStyle(isSaved ? Palette.dawn : Palette.muted)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isSaved
                                        ? String(localized: "Remove ayah \(ayah.key.ayah) from saved")
                                        : String(localized: "Save ayah \(ayah.key.ayah)"))
                }
                ArabicText(ayah.arabic, size: 24, style: .title2)
                ForEach(translations, id: \.self) { item in
                    Text(verbatim: item.text)
                        .font(item.language == "bn" ? Fonts.bangla(15, relativeTo: .subheadline) : .subheadline)
                        .foregroundStyle(Palette.ink2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .padding(.bottom, 14)
            .padding(.top, 4)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(fill)
        .clipShape(RoundedRectangle(cornerRadius: role == nil ? 0 : 14, style: .continuous))
        .overlay {
            if isReciting {
                RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.accent, lineWidth: 2)
            }
        }
        .overlay(alignment: .bottom) {
            if role == nil, !isReciting {
                Rectangle().fill(Palette.line).frame(height: 1)
            }
        }
    }

    private var label: String? {
        switch role {
        case .before: String(localized: "Before")
        case .today: String(localized: "Today")
        case .after: String(localized: "After")
        case nil: nil
        }
    }

    private var fill: Color {
        switch role {
        case .before: Palette.before
        case .today: Palette.tint
        case .after: Palette.dawnTint
        case nil: .clear
        }
    }

    private var bar: Color {
        switch role {
        case .before: Palette.beforeInk
        case .today: Palette.accent
        case .after: Palette.dawn
        case nil: .clear
        }
    }

    private var ink: Color {
        switch role {
        case .before: Palette.beforeInk
        case .today: Palette.tintInk
        case .after: Palette.dawnInk
        case nil: Palette.muted
        }
    }
}

/// The list of surahs, with search by name or number.
struct SurahPicker: View {
    @Environment(\.dismiss) private var dismiss
    let surahs: [Surah]
    let current: Int?
    let onPick: (Int) -> Void

    @State private var query = ""

    private var matches: [Surah] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return surahs }
        return surahs.filter { surah in
            "\(surah.number)" == text
                || surah.nameTransliterated.localizedStandardContains(text)
                || surah.nameEnglish.localizedStandardContains(text)
                || surah.nameArabic.contains(text)
        }
    }

    var body: some View {
        NavigationStack {
            List(matches) { surah in
                Button {
                    onPick(surah.number)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Text(verbatim: "\(surah.number)")
                            .font(.footnote.weight(.semibold))
                            .frame(minWidth: 32, minHeight: 32)
                            .foregroundStyle(surah.number == current ? Palette.onAccent : Palette.ink2)
                            .background(surah.number == current ? Palette.accent : Palette.fill, in: Capsule())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: surah.nameTransliterated)
                                .font(.body.weight(.medium))
                                .foregroundStyle(Palette.ink)
                            Text(verbatim: surah.nameEnglish)
                                .font(.footnote)
                                .foregroundStyle(Palette.muted)
                        }
                        Spacer(minLength: 8)
                        Text(verbatim: surah.nameArabic)
                            .font(Fonts.arabic(20, relativeTo: .title3))
                            .foregroundStyle(Palette.ink)
                            .environment(\.locale, Locale(identifier: "ar"))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(surah.number == current ? .isSelected : [])
            }
            .listStyle(.plain)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Surah name or number"))
            .navigationTitle("Surahs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
