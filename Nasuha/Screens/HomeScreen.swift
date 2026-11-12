import NasuhaCore
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

/// The single dashboard: today's ayah, topic chips and the next reminder.
struct HomeScreen: View {
    @Environment(ContentLoader.self) private var content
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Query private var settings: [UserSettings]
    @Query(sort: \TopicChoice.order) private var choices: [TopicChoice]
    @Query private var reads: [ReadRecord]
    @Query private var records: [ReminderRecord]

    let open: (AppRoute) -> Void

    @State private var selectedTopic: String?
    @State private var card: AyahDetail?
    @State private var topics: [Topic] = []
    @State private var notificationsAllowed = true
    @State private var readerSurah: (number: Int, name: String, ayah: Int)?
    @Query private var progress: [ReadingProgress]

    private var isSetUp: Bool { settings.first?.hasCompletedSetup ?? false }
    private var state: ReminderState { records.first?.state ?? ReminderState() }
    private var readIDs: Set<String> { Set(reads.map(\.ayahSetID)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if !topics.isEmpty {
                    chips
                }
                if let card, let topic = currentTopic {
                    TodayCard(detail: card, topic: topic, isToday: card.ayahSet.id == state.currentSetID) {
                        router.ayah = AyahTarget(setID: card.ayahSet.id)
                    }
                } else if topics.isEmpty {
                    Text("Your ayahs will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
                if readerSurah != nil {
                    readTile
                }
                if isSetUp {
                    topicsAndTime
                    if !notificationsAllowed {
                        notificationsOff
                    } else if let next = state.nextSlot {
                        nextReminder(next)
                    }
                } else if !topics.isEmpty {
                    setUpPrompt
                }
                Text("Missed a day? It's okay. Your ayahs wait for you here.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Palette.bg)
        .task { reload() }
        .task(id: scenePhase) { await checkNotifications() }
        .onChange(of: choices.map(\.topicID)) { reload() }
        .onChange(of: records.first?.updatedAt) { loadCard() }
        .onChange(of: reads.count) { loadCard() }
        .onChange(of: settings.first?.readingTranslations) { loadCard() }
        .onChange(of: selectedTopic) { loadCard() }
        .onChange(of: progress.first?.lastAyah) { loadReaderPlace() }
        .onChange(of: progress.first?.lastSurah) { loadReaderPlace() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            LogoMark(size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(greeting)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Text(verbatim: dateLine)
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var greeting: String {
        let name = (settings.first?.name ?? "").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? String(localized: "Assalamu alaikum") : String(localized: "Assalamu alaikum, \(name)")
    }

    /// "Friday 6 Nov · 26 Jumada al-Ula 1448", with the Hijri date moved by the user's offset.
    private var dateLine: String {
        let now = Date.now
        let gregorian = now.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        var hijriCalendar = Calendar(identifier: .islamicUmmAlQura)
        hijriCalendar.timeZone = .current
        let offset = min(2, max(-2, settings.first?.hijriOffset ?? 0))
        let shifted = hijriCalendar.date(byAdding: .day, value: offset, to: now) ?? now
        var style = Date.FormatStyle.dateTime.day().month(.wide).year()
        style.calendar = hijriCalendar
        return "\(gregorian) · \(shifted.formatted(style))"
    }

    // MARK: Topics

    private var chips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What does your heart need today?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(topics) { topic in
                        let isOn = topic.id == currentTopic?.id
                        Button {
                            selectedTopic = topic.id
                        } label: {
                            Text(topic.localizedLabel)
                                .font(.subheadline.weight(isOn ? .semibold : .medium))
                                .padding(.horizontal, 14)
                                .frame(minHeight: 44)
                                .foregroundStyle(isOn ? Palette.onAccent : Palette.ink)
                                .background(isOn ? Palette.accent : Palette.surface, in: Capsule())
                                .overlay(Capsule().stroke(isOn ? .clear : Palette.line, lineWidth: 1))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.horizontal, -20)
        }
    }

    private var currentTopic: Topic? {
        if let selectedTopic, let topic = topics.first(where: { $0.id == selectedTopic }) { return topic }
        if let today = state.currentTopicID, let topic = topics.first(where: { $0.id == today }) { return topic }
        return topics.first
    }

    // MARK: Rows

    private var topicsAndTime: some View {
        tile(icon: "clock", title: "Topics & time",
             note: String(localized: "\(choices.count) topics · \(reminderTime)")) {
            open(.topics)
        }
    }

    /// "Read the Qur'an", continuing from the last place.
    private var readTile: some View {
        tile(icon: "book", title: "Read the Qur'an",
             note: readerSurah.map { String(localized: "Continue: \($0.name), ayah \($0.ayah)") } ?? "") {
            guard let readerSurah else { return }
            open(.reader(ReaderTarget(surah: readerSurah.number, ayah: readerSurah.ayah)))
        }
    }

    private func tile(icon: String, title: LocalizedStringKey, note: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Palette.accent)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Text(verbatim: note)
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.muted)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(Palette.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func nextReminder(_ slot: PlannedSlot) -> some View {
        Button {
            open(.time)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bell")
                    .foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(nextText(slot.fireDate))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    if state.total > 0 {
                        Text("Ayah \(state.progress.next) of \(state.progress.total) in your topics")
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var notificationsOff: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bell.slash")
                    .foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifications are off")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Text("Turn them on in Settings to get your daily ayah. Your ayahs are always here too.")
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var setUpPrompt: some View {
        Button {
            open(.topics)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bell")
                    .foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Get one ayah a day")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Text("Pick your topics and a time. It takes 30 seconds.")
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.muted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var reminderTime: String {
        var parts = DateComponents()
        parts.hour = settings.first?.reminderHour ?? 7
        parts.minute = settings.first?.reminderMinute ?? 30
        return (Calendar.current.date(from: parts) ?? .now).formatted(date: .omitted, time: .shortened)
    }

    private func nextText(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String(localized: "Next: today at \(time)") }
        if calendar.isDateInTomorrow(date) { return String(localized: "Next: tomorrow at \(time)") }
        let day = date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        return String(localized: "Next: \(day) at \(time)")
    }

    // MARK: Loading

    private func reload() {
        let counts = (try? content.store?.topicSetCounts()) ?? [:]
        let available = TopicCatalog.available(setCounts: counts).flatMap(\.topics)
        let chosen = choices.compactMap { choice in available.first { $0.id == choice.topicID } }
        topics = chosen.isEmpty ? available : chosen
        if let selectedTopic, !topics.contains(where: { $0.id == selectedTopic }) { self.selectedTopic = nil }
        loadCard()
        loadReaderPlace()
    }

    /// Where "Read the Qur'an" continues from: the last place read, else the first surah in the content.
    private func loadReaderPlace() {
        guard let store = content.store else {
            readerSurah = nil
            return
        }
        let last = progress.first
        let surah = (last.flatMap { try? store.surah($0.lastSurah) }) ?? (try? store.surahs())?.first
        readerSurah = surah.map { (number: $0.number, name: $0.nameTransliterated,
                                   ayah: $0.number == last?.lastSurah ? min(max(last?.lastAyah ?? 1, 1), $0.ayahCount) : 1) }
    }

    private func loadCard() {
        guard let store = content.store, let topic = currentTopic,
              let setIDs = try? store.setIDs(topic: topic.id),
              let setID = TopicReading.homeSet(topic: topic.id, state: state, setIDs: setIDs, read: readIDs)
        else {
            card = nil
            return
        }
        card = try? AyahDetailLoader(store: store)
            .load(setID: setID, preferredTranslations: settings.first?.readingTranslations ?? [])
    }

    private func checkNotifications() async {
        guard isSetUp else { return }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notificationsAllowed = status != .denied
    }
}

/// The card with one ayah: Arabic, translation, the story box and "Read in context".
struct TodayCard: View {
    @Environment(RecitationPlayer.self) private var player
    let detail: AyahDetail
    let topic: Topic
    let isToday: Bool
    let onRead: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(isToday ? String(localized: "Today's ayah · \(topic.localizedLabel)") : topic.localizedLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(Palette.dawnInk)
                    .background(Palette.dawnTint, in: Capsule())
                Spacer(minLength: 8)
                Text(verbatim: detail.reference)
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
            ArabicText(detail.arabic, size: 27, style: .title2)
            ForEach(detail.translations) { item in
                TranslationText(item, size: 18, style: .body)
            }
            if let story = StoryBox(detail: detail) {
                story
            }
            HStack(spacing: 10) {
                if player.isAvailable {
                    PlayButton(plan: PlaybackPlan(keys: [detail.ayahSet.ayah]),
                               label: String(localized: "Listen to this ayah"), diameter: 48)
                        .overlay(Circle().stroke(Palette.line, lineWidth: 1).frame(width: 48, height: 48))
                }
                Button(action: onRead) {
                    HStack(spacing: 8) {
                        Text("Read in context")
                        Image(systemName: "arrow.forward")
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(PrimaryButtonStyle(minHeight: 48))
            }
        }
        .padding(18)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Palette.line, lineWidth: 1))
        .shadow(color: Color(red: 40 / 255, green: 28 / 255, blue: 90 / 255).opacity(0.06), radius: 10, y: 6)
    }
}

/// The story of the ayah's revelation on Home. Built only from what the set provides; absent when it has neither story nor timing.
struct StoryBox: View {
    let story: String?
    let when: String?
    let source: String?

    init?(detail: AyahDetail) {
        let text = detail.oneLine ?? (detail.storySteps.isEmpty ? nil : detail.storySteps.map(\.text).joined(separator: " "))
        let when = RevelationText.summary(detail)
        guard text != nil || when != nil else { return nil }
        story = text
        self.when = when
        let refs = detail.ayahSet.story?.refs ?? []
        source = text == nil || refs.isEmpty ? nil : refs.map(\.display).joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let story {
                Text("The story of its revelation")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .foregroundStyle(Palette.tintInk)
                Text(verbatim: story)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
            }
            if let when {
                Text(verbatim: when)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.tintInk)
            }
            if let source {
                Text("Source: \(source)")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
