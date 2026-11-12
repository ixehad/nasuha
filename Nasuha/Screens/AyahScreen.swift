import NasuhaCore
import SwiftData
import SwiftUI

/// The Ayah screen and the reward screen after it, shown over Home.
struct AyahFlow: View {
    @Environment(ContentLoader.self) private var content
    @Environment(\.dismiss) private var dismiss
    @Query private var settings: [UserSettings]

    @State private var setID: String
    @State private var detail: AyahDetail?
    @State private var didLoad = false
    @State private var showsDone = false
    @State private var reader: ReaderTarget?

    init(setID: String) {
        _setID = State(initialValue: setID)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let detail {
                    AyahScreen(detail: detail, onClose: { dismiss() }, onContinue: { showsDone = true }, onReadSurah: {
                        reader = ReaderTarget(surah: detail.ayahSet.ayah.surah, ayah: detail.ayahSet.ayah.ayah,
                                              todaySetID: detail.id)
                    })
                    .id(detail.id)
                } else if didLoad {
                    missing
                } else {
                    Palette.bg.ignoresSafeArea()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $reader) { target in
                QuranScreen(target: target, onBack: { reader = nil }) { id in
                    reader = nil
                    setID = id
                }
                .toolbar(.hidden, for: .navigationBar)
            }
            .navigationDestination(isPresented: $showsDone) {
                if let detail {
                    DoneScreen(detail: detail, onNext: { next in
                        showsDone = false
                        setID = next
                    }, onHome: { dismiss() })
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
        }
        .task(id: setID) { load() }
        .onDisappear { AppServices.shared.player.stop() }
        .preferredColorScheme(settings.first?.appearance.colorScheme)
    }

    /// Shown when a link points at an ayah that is no longer in the content.
    private var missing: some View {
        VStack(spacing: 16) {
            Text("This ayah isn't available.")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            Button("Back to home") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg)
    }

    private func load() {
        defer { didLoad = true }
        guard let store = content.store else { return }
        detail = try? AyahDetailLoader(store: store)
            .load(setID: setID, preferredTranslations: settings.first?.readingTranslations ?? [],
                  extraTafsirLanguages: settings.first?.extraTafsirLanguages ?? [])
    }
}

/// One ayah with its story, its timing, the ayahs around it and its sources.
struct AyahScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(RecitationPlayer.self) private var player
    @Query private var saved: [SavedAyah]
    @Query private var reads: [ReadRecord]

    let detail: AyahDetail
    let onClose: () -> Void
    let onContinue: () -> Void
    let onReadSurah: () -> Void

    @State private var showsMore = false
    @State private var repeatsThree = false
    @State private var justRead = false

    private var isSaved: Bool { saved.contains { $0.ayahKey == detail.ayahSet.ayah.description } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ayah
                if player.isAvailable, let reciter = player.reciter {
                    recitation(reciter)
                }
                if !detail.storySteps.isEmpty || detail.oneLine != nil {
                    story
                }
                if let when = detail.ayahSet.when {
                    timing(when)
                }
                around
                if !detail.tafsir.isEmpty {
                    explanation
                }
                references
                closing
                footer
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 32)
        }
        .background(Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { header }
    }

    // MARK: 1. Header

    private var header: some View {
        HStack {
            IconButton(systemName: "xmark", label: "Close and go home", action: onClose)
            Spacer(minLength: 4)
            VStack(spacing: 1) {
                Text(verbatim: headerTitle)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                if let place = detail.place {
                    Text("Revealed in \(RevelationText.place(place))")
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            ShareLink(item: RevelationText.shareText(detail)) {
                Image(systemName: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Share")
        }
        .padding(.horizontal, 12)
        .background(Palette.bg)
    }

    private var headerTitle: String {
        [detail.surah?.nameTransliterated, detail.ayahSet.ayah.description].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: 2. The ayah

    private var ayah: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                if let topic = detail.ayahSet.topics.compactMap(TopicCatalog.topic).first {
                    badge(topic.localizedReminderTitle)
                }
                if detail.ayahSet.isSample {
                    Text("Sample content")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundStyle(Palette.muted)
                        .background(Palette.fill, in: Capsule())
                }
            }
            ArabicText(detail.arabic, size: 34, style: .largeTitle)
            ForEach(Array(detail.translations.enumerated()), id: \.element.id) { index, item in
                TranslationText(item, size: index == 0 ? 21 : 18, style: index == 0 ? .title3 : .body,
                                color: index == 0 ? Palette.ink : Palette.ink2)
            }
        }
        .padding(.top, 8)
    }

    private func badge(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(Palette.dawnInk)
            .background(Palette.dawnTint, in: Capsule())
    }

    // MARK: 3. Recitation

    private func recitation(_ reciter: Reciter) -> some View {
        let plan = PlaybackPlan(keys: [detail.ayahSet.ayah], repeatCount: repeatsThree ? PlaybackPlan.repeatChoice : 1)
        return HStack(spacing: 12) {
            PlayButton(plan: plan, label: String(localized: "Play recitation"), diameter: 46, filled: true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Listen")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(player.status == .failed
                     ? String(localized: "Couldn't load the recitation. Check your connection.")
                     : reciter.name)
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
            Button {
                repeatsThree.toggle()
            } label: {
                Text("Repeat 3×")
                    .font(.footnote.weight(repeatsThree ? .semibold : .medium))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .foregroundStyle(repeatsThree ? Palette.tintInk : Palette.ink)
                    .background(repeatsThree ? Palette.tint : Palette.fill, in: Capsule())
                    .overlay(Capsule().stroke(repeatsThree ? Palette.accent : Palette.line, lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(repeatsThree ? .isSelected : [])
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .background(Palette.surface, in: Capsule())
        .overlay(Capsule().stroke(Palette.line, lineWidth: 1))
    }

    // MARK: 4. The story of its revelation

    private var story: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("The story of its revelation")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(detail.storySteps.enumerated()), id: \.offset) { index, step in
                    let isLast = index == detail.storySteps.count - 1
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 0) {
                            Circle()
                                .fill(isLast ? Palette.dawn : Palette.accent)
                                .frame(width: 12, height: 12)
                                .padding(.top, 5)
                            if !isLast {
                                Rectangle().fill(Palette.line).frame(width: 2)
                            }
                        }
                        .accessibilityHidden(true)
                        Text(verbatim: step.text)
                            .font(step.language == "bn" ? Fonts.bangla(16, relativeTo: .callout) : .callout)
                            .lineSpacing(3)
                            .foregroundStyle(Palette.ink)
                            .padding(.bottom, isLast ? 0 : 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let oneLine = detail.oneLine {
                VStack(alignment: .leading, spacing: 4) {
                    Text("In one line")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.tintInk)
                    Text(verbatim: oneLine)
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(Palette.ink)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    // MARK: 5. When it was revealed

    private func timing(_ when: RevelationInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("When it was revealed")
            let tiles = timingTiles(when)
            if !tiles.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(tiles) { tile in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: tile.label)
                                .font(.caption)
                                .foregroundStyle(tile.highlighted ? Palette.tintInk : Palette.muted)
                            Text(verbatim: tile.value)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                            if let note = tile.note {
                                Text(verbatim: note)
                                    .font(.caption)
                                    .foregroundStyle(Palette.muted)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(tile.highlighted ? Palette.tint : Palette.fill,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if when.scholarsDiffer {
                Text("Scholars differ on the exact time, so it is shown as a range.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
            }
            if !when.refs.isEmpty {
                Text("Source: \(when.refs.map(\.display).joined(separator: " · "))")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
        }
    }

    private struct TimingTile: Identifiable {
        let id: String
        let label: String
        let value: String
        var note: String?
        var highlighted = false
    }

    private func timingTiles(_ when: RevelationInfo) -> [TimingTile] {
        var tiles: [TimingTile] = []
        if let place = when.place {
            tiles.append(TimingTile(id: "place", label: String(localized: "Place"), value: RevelationText.place(place)))
        }
        if let order = when.order {
            let formatter = NumberFormatter()
            formatter.numberStyle = .ordinal
            let ordinal = formatter.string(from: NSNumber(value: order)) ?? "\(order)"
            tiles.append(TimingTile(id: "order", label: String(localized: "Order revealed"),
                                    value: String(localized: "\(ordinal) surah")))
        }
        if let period = when.periodText, !period.isEmpty {
            tiles.append(TimingTile(id: "period", label: String(localized: "Period"), value: period))
        }
        if let age = when.ageText {
            tiles.append(TimingTile(id: "age", label: String(localized: "Age of the Prophet ﷺ"),
                                    value: String(localized: "About \(age)"),
                                    note: String(localized: "approximate"), highlighted: true))
        }
        return tiles
    }

    // MARK: 6. The ayahs around it

    private var around: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Read it with the ayahs around it")
            HStack(spacing: 14) {
                legend(String(localized: "Before"), fill: Palette.before, edge: Palette.beforeInk)
                legend(String(localized: "Today's ayah"), fill: Palette.tint, edge: Palette.accent)
                legend(String(localized: "After"), fill: Palette.dawnTint, edge: Palette.dawn)
            }
            .accessibilityHidden(true)
            if detail.hasMoreContext {
                SegmentedBar(options: [
                    (false, String(localized: "2 before · 2 after")),
                    (true, String(localized: "Show more")),
                ], selection: $showsMore)
            }
            VStack(spacing: 8) {
                ForEach(showsMore ? detail.more : detail.near) { row in
                    ContextRowView(row: row, sources: detail.translations.map(\.source), audioAvailable: player.isAvailable)
                }
            }
            HStack(spacing: 8) {
                if player.isAvailable {
                    rangeButton
                }
                Button(action: onReadSurah) {
                    Text("Read full surah")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(Palette.tintInk)
                        .background(Palette.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// "Play 93:1–5": the ayahs shown, one after another.
    private var rangeButton: some View {
        let rows = showsMore ? detail.more : detail.near
        let plan = PlaybackPlan(keys: rows.map(\.key))
        let active = player.isActive(plan) && player.isPlaying
        return Button {
            player.toggle(plan)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: active ? "pause.fill" : "play.fill")
                    .font(.footnote)
                    .accessibilityHidden(true)
                Text(active ? String(localized: "Pause") : String(localized: "Play \(rangeText(rows))"))
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(Palette.accent)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rangeText(_ rows: [ContextRow]) -> String {
        guard let first = rows.first?.key, let last = rows.last?.key else { return "" }
        if first == last { return first.description }
        return first.surah == last.surah ? "\(first.description)\u{2013}\(last.ayah)" : "\(first.description)\u{2013}\(last.description)"
    }

    private func legend(_ text: String, fill: Color, edge: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(fill)
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(edge, lineWidth: 1))
                .frame(width: 12, height: 12)
            Text(verbatim: text)
                .font(.caption)
                .foregroundStyle(Palette.muted)
        }
    }

    // MARK: 7. Explanation

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Explanation", small: true)
            ForEach(Array(detail.tafsir.enumerated()), id: \.offset) { _, excerpt in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: excerpt.text)
                        .font(excerpt.language == "bn" ? Fonts.bangla(16, relativeTo: .callout) : .callout)
                        .lineSpacing(excerpt.language == "ar" ? 8 : 3)
                        .foregroundStyle(Palette.ink2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Arabic reads right to left, whatever the app's language.
                        .environment(\.layoutDirection, excerpt.language == "ar" ? .rightToLeft : .leftToRight)
                        .environment(\.locale, Locale(identifier: excerpt.language))
                    Text(verbatim: excerpt.book)
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: 8. References and sources

    private var references: some View {
        let rows = referenceRows
        return VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(Palette.line)
            sectionTitle("References and sources", small: true)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: row.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                        ForEach(row.lines, id: \.self) { line in
                            Text(verbatim: line)
                                .font(.footnote)
                                .foregroundStyle(Palette.ink2)
                        }
                        if let note = row.note {
                            Text(verbatim: note)
                                .font(.footnote)
                                .foregroundStyle(Palette.muted)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    if index < rows.count - 1 {
                        Divider().overlay(Palette.line)
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.line, lineWidth: 1))
        }
    }

    private struct ReferenceRow: Identifiable {
        let id: String
        let title: String
        let lines: [String]
        var note: String?
    }

    private var referenceRows: [ReferenceRow] {
        var rows: [ReferenceRow] = []
        if let refs = detail.ayahSet.story?.refs, !refs.isEmpty {
            rows.append(ReferenceRow(
                id: "story", title: String(localized: "Story"), lines: refs.map(\.display),
                note: refs.contains(where: \.isNumbered) ? String(localized: "Hadith numbers follow the sunnah.com numbering") : nil))
        }
        var books: [String] = []
        for book in detail.tafsir.map(\.book) + detail.ayahSet.tafsirRefs.map(\.book) where !books.contains(book) {
            books.append(book)
        }
        if !books.isEmpty {
            rows.append(ReferenceRow(id: "tafsir", title: String(localized: "Explanation"), lines: [books.joined(separator: " · ")]))
        }
        var text: [String] = []
        if let credit = detail.textCredit, !credit.isEmpty { text.append(credit) }
        for item in detail.translations {
            text.append(String(localized: "\(item.source.title), version \(item.source.version)"))
        }
        if !text.isEmpty {
            rows.append(ReferenceRow(id: "text", title: String(localized: "Arabic text and translation"), lines: text))
        }
        if let reciter = player.reciter {
            rows.append(ReferenceRow(id: "recitation", title: String(localized: "Recitation"),
                                     lines: ["\(reciter.name), \(reciter.riwayah)"]))
        }
        return rows
    }

    // MARK: 9. Closing line

    private var closing: some View {
        VStack(spacing: 4) {
            Text(verbatim: "وَاللَّهُ أَعْلَمُ")
                .font(Fonts.arabic(20, relativeTo: .title3))
                .foregroundStyle(Palette.ink2)
                .environment(\.locale, Locale(identifier: "ar"))
            Text("And Allah knows best. May Allah forgive us for any mistake in what we share.")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    // MARK: 10. Save and "I've read it"

    @ViewBuilder
    private var footer: some View {
        if justRead {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Palette.dawn, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Alhamdulillah")
                            .font(.headline)
                            .foregroundStyle(Palette.dawnInk)
                        Text(detail.ayahSet.story == nil
                             ? LocalizedStringKey("You read today's ayah.")
                             : LocalizedStringKey("You read today's ayah and its story."))
                            .font(.subheadline)
                            .foregroundStyle(Palette.ink2)
                    }
                }
                .accessibilityElement(children: .combine)
                Button("Continue", action: onContinue)
                    .buttonStyle(PrimaryButtonStyle(minHeight: 48))
            }
            .padding(18)
            .background(Palette.dawnTint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            HStack(spacing: 8) {
                Button(action: toggleSaved) {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.title3)
                        .foregroundStyle(isSaved ? Palette.dawn : Palette.ink)
                        .frame(width: 54, height: 54)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.line, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSaved ? LocalizedStringKey("Remove from saved") : LocalizedStringKey("Save"))
                Button("I've read it") {
                    Task { await markRead() }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private func toggleSaved() {
        let key = detail.ayahSet.ayah.description
        if let existing = saved.first(where: { $0.ayahKey == key }) {
            context.delete(existing)
        } else {
            context.insert(SavedAyah(ayahKey: key, ayahSetID: detail.ayahSet.id))
        }
        try? context.save()
    }

    private func markRead() async {
        let hadStory = detail.ayahSet.story != nil
        if let reminders = AppServices.shared.reminders {
            try? await reminders.markRead(setID: detail.ayahSet.id, hadStory: hadStory)
        } else if !reads.contains(where: { $0.ayahSetID == detail.ayahSet.id }) {
            context.insert(ReadRecord(ayahSetID: detail.ayahSet.id, hadStory: hadStory))
            try? context.save()
        }
        withAnimation(.snappy) { justRead = true }
    }

    private func sectionTitle(_ key: LocalizedStringKey, small: Bool = false) -> some View {
        Text(key)
            .font(small ? .headline : .title3.bold())
            .foregroundStyle(Palette.ink)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One ayah in the context list, colour-coded and labelled by where it sits.
struct ContextRowView: View {
    let row: ContextRow
    let sources: [TranslationSource]
    var audioAvailable = false

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(bar)
                .frame(width: row.role == .today ? 5 : 3)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(verbatim: "\(row.key.description) · \(label)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ink)
                    Spacer(minLength: 0)
                    if audioAvailable {
                        PlayButton(plan: PlaybackPlan(keys: [row.key]),
                                   label: String(localized: "Play \(row.key.description)"), diameter: 36)
                    }
                }
                ArabicText(row.arabic, size: 22, style: .title3)
                ForEach(row.translations, id: \.sourceKey) { translation in
                    let language = sources.first { $0.key == translation.sourceKey }?.language ?? "en"
                    Text(verbatim: translation.text)
                        .font(language == "bn" ? Fonts.bangla(15, relativeTo: .subheadline) : .subheadline)
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(fill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var label: String {
        switch row.role {
        case .before: String(localized: "Before")
        case .today: String(localized: "Today's ayah")
        case .after: String(localized: "After")
        }
    }

    private var fill: Color {
        switch row.role {
        case .before: Palette.before
        case .today: Palette.tint
        case .after: Palette.dawnTint
        }
    }

    private var bar: Color {
        switch row.role {
        case .before: Palette.beforeInk
        case .today: Palette.accent
        case .after: Palette.dawn
        }
    }

    private var ink: Color {
        switch row.role {
        case .before: Palette.beforeInk
        case .today: Palette.tintInk
        case .after: Palette.dawnInk
        }
    }
}
