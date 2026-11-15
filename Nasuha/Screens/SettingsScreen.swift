import NasuhaCore
import SwiftData
import SwiftUI

/// Settings: the daily ayah, languages, reading and about.
struct SettingsScreen: View {
    @Environment(ContentLoader.self) private var content
    @Environment(RecitationPlayer.self) private var player
    @Environment(TipStore.self) private var tips
    @Environment(SetupDraft.self) private var draft
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query private var allSettings: [UserSettings]
    @Query(sort: \TopicChoice.order) private var choices: [TopicChoice]
    @Query private var records: [ReminderRecord]

    let open: (AppRoute) -> Void
    let onBack: () -> Void

    @State private var showsTranslations = false
    @State private var confirmsStartAgain = false
    @State private var reminderLanguages: [String] = []

    private var state: ReminderState { records.first?.state ?? ReminderState() }

    var body: some View {
        ScrollView {
            if let settings = allSettings.first {
                VStack(alignment: .leading, spacing: 22) {
                    dailyAyah(settings)
                    language(settings)
                    reading(settings)
                    about
                    Text("Nasuha \(AppLinks.appVersion) · Free · Nothing leaves your phone")
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .background(Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { ScreenHeader(title: "Settings", onBack: onBack) }
        .task {
            _ = try? UserSettings.current(in: context)
            loadLanguages()
            await tips.load()
        }
        .sheet(isPresented: $showsTranslations, onDismiss: saveReading) {
            ReadingLanguagesSheet()
                .environment(draft)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Start again from the first ayah?", isPresented: $confirmsStartAgain, titleVisibility: .visible) {
            Button("Start again") {
                Task {
                    try? await AppServices.shared.reminders?.answerAllRead(.startAgain)
                    await AppServices.shared.refillReminders()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your reminders will go through the same ayahs again.")
        }
    }

    // MARK: Your daily ayah

    private func dailyAyah(_ settings: UserSettings) -> some View {
        RowGroup("Your daily ayah") {
            NavRow(title: "Topics", value: String(localized: "\(choices.count) topics")) { open(.topics) }
            RowDivider()
            NavRow(title: "Time", value: timeText(settings)) { open(.time) }
            RowDivider()
            ChoiceRow(title: "How often", options: [
                (ReminderFrequency.daily, String(localized: "Every day")),
                (ReminderFrequency.everyTwoDays, String(localized: "Every 2 days")),
                (ReminderFrequency.fridays, String(localized: "Fridays")),
            ], selection: Binding(get: { settings.frequency }, set: { settings.frequency = $0; remindersChanged() }))
            if state.total > 0 {
                RowDivider()
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("When all ayahs are read")
                            .font(.callout)
                            .foregroundStyle(Palette.ink)
                        Text("Ayah \(state.progress.next) of \(state.progress.total) in your topics")
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                    }
                    Spacer(minLength: 8)
                    Button("Start again") { confirmsStartAgain = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                        .frame(minHeight: 44)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .frame(minHeight: 52)
            }
            RowDivider()
            pauseRow(settings)
        }
    }

    private func pauseRow(_ settings: UserSettings) -> some View {
        let paused = settings.pausedUntil.flatMap { $0 > .now ? $0 : nil }
        return Menu {
            ForEach(PauseLength.allCases, id: \.self) { length in
                Button(pauseTitle(length)) {
                    settings.pausedUntil = length.resumeDate(from: .now, calendar: .current)
                    remindersChanged()
                }
            }
            if paused != nil {
                Button("Turn reminders back on") {
                    settings.pausedUntil = nil
                    remindersChanged()
                }
            }
        } label: {
            RowLabel(title: "Pause reminders for a while",
                     note: paused.map { String(localized: "Paused until \($0.formatted(date: .abbreviated, time: .omitted))") })
        }
        .buttonStyle(.plain)
    }

    private func pauseTitle(_ length: PauseLength) -> String {
        switch length {
        case .oneDay: String(localized: "For 1 day")
        case .threeDays: String(localized: "For 3 days")
        case .oneWeek: String(localized: "For 1 week")
        }
    }

    private func timeText(_ settings: UserSettings) -> String {
        var parts = DateComponents()
        parts.hour = settings.reminderHour
        parts.minute = settings.reminderMinute
        return (Calendar.current.date(from: parts) ?? .now).formatted(date: .omitted, time: .shortened)
    }

    // MARK: Language

    private func language(_ settings: UserSettings) -> some View {
        RowGroup("Language") {
            NavRow(title: "Translation", value: translationNames(settings)) {
                draft.load(from: context, store: content.store)
                showsTranslations = true
            }
            if reminderLanguages.count > 1 {
                RowDivider()
                ChoiceRow(title: "Reminder language",
                          options: reminderLanguages.map { ($0, LanguageName.autonym($0)) },
                          selection: Binding(get: { settings.reminderLanguage },
                                             set: { settings.reminderLanguage = $0; remindersChanged() }))
            }
        }
    }

    private func translationNames(_ settings: UserSettings) -> String {
        let sources = (try? content.store?.translationSources()) ?? []
        var names: [String] = []
        for key in settings.readingTranslations {
            if let source = sources.first(where: { $0.key == key }) {
                let name = LanguageName.autonym(source.language)
                if !names.contains(name) { names.append(name) }
            }
        }
        if settings.showArabicTafsir { names.append(LanguageName.autonym("ar")) }
        return names.joined(separator: ", ")
    }

    private func loadLanguages() {
        draft.load(from: context, store: content.store)
        reminderLanguages = draft.reminderLanguages
    }

    private func saveReading() {
        try? draft.commitReading(to: context)
        loadLanguages()
    }

    // MARK: Reading

    private func reading(_ settings: UserSettings) -> some View {
        RowGroup("Reading") {
            ChoiceRow(title: "Light or dark", options: [
                (AppearanceMode.system, String(localized: "Follows iPhone")),
                (AppearanceMode.light, String(localized: "Light")),
                (AppearanceMode.dark, String(localized: "Dark")),
            ], selection: Binding(get: { settings.appearance }, set: { settings.appearance = $0 }))
            RowDivider()
            ChoiceRow(title: "Text size", options: [
                (TextSizeStep.small, String(localized: "Smaller")),
                (TextSizeStep.standard, String(localized: "Same as iPhone")),
                (TextSizeStep.large, String(localized: "Large")),
                (TextSizeStep.larger, String(localized: "Larger")),
            ], selection: Binding(get: { settings.textSize }, set: { settings.textSize = $0 }))
            RowDivider()
            hijriRow(settings)
            if player.isAvailable, let reciter = player.reciter {
                RowDivider()
                RowLabel(title: "Reciter", value: reciter.name, showsChevron: false)
            }
            RowDivider()
            SwitchRow(title: "Keep Arabic off the lock screen",
                      note: String(localized: "Out of respect, Arabic shows only inside the app"),
                      isOn: Binding(get: { settings.keepArabicOffLockScreen },
                                    set: { settings.keepArabicOffLockScreen = $0; remindersChanged() }))
        }
    }

    private func hijriRow(_ settings: UserSettings) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hijri date")
                    .font(.callout)
                    .foregroundStyle(Palette.ink)
                Text("Match your local moon sighting")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 8)
            stepButton("minus", label: "One day earlier", enabled: settings.hijriOffset > -2) {
                settings.setHijriOffset(settings.hijriOffset - 1)
                remindersChanged()
            }
            Text(verbatim: hijriText(settings.hijriOffset))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .frame(minWidth: 64)
            stepButton("plus", label: "One day later", enabled: settings.hijriOffset < 2) {
                settings.setHijriOffset(settings.hijriOffset + 1)
                remindersChanged()
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .frame(minHeight: 52)
    }

    private func stepButton(_ icon: String, label: LocalizedStringKey, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.footnote.weight(.bold))
                .foregroundStyle(enabled ? Palette.accent : Palette.line)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func hijriText(_ offset: Int) -> String {
        if offset == 0 { return String(localized: "No change") }
        return offset > 0 ? String(localized: "+\(offset) days") : String(localized: "−\(-offset) days")
    }

    // MARK: About

    private var about: some View {
        RowGroup("About") {
            NavRow(title: "About us and sources") { open(.about) }
            RowDivider()
            NavRow(title: "Privacy and terms") { open(.legal) }
            if tips.isAvailable {
                RowDivider()
                NavRow(title: "Support Nasuha", value: String(localized: "Optional tip")) { open(.support) }
            }
            RowDivider()
            NavRow(title: "Report a mistake") {
                let version = (try? content.store?.meta().contentVersion) ?? ""
                if let url = AppLinks.mistakeReport(contentVersion: version) { openURL(url) }
            }
        }
    }

    /// Saves and brings the reminders in line with the new settings.
    private func remindersChanged() {
        try? context.save()
        Task { await AppServices.shared.refillReminders() }
    }
}
