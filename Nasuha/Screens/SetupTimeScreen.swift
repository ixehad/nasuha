import NasuhaCore
import SwiftData
import SwiftUI

/// Setup, step 2: the reminder time, how often, and languages.
struct SetupTimeScreen: View {
    @Environment(SetupDraft.self) private var draft
    @Environment(\.modelContext) private var context
    let onFinished: () -> Void
    let onBack: () -> Void

    @State private var isSaving = false
    @State private var showsReadingLanguages = false

    var body: some View {
        @Bindable var draft = draft
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What time suits you?")
                        .font(.title2.bold())
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("Tap an hour on the clock, then pick minutes.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                }

                VStack(spacing: 14) {
                    HStack(spacing: 10) {
                        Text(verbatim: readout)
                            .font(.system(size: 56, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.ink)
                            .accessibilityLabel(Text(verbatim: spokenTime))
                        VStack(spacing: 4) {
                            periodButton(isPM: false)
                            periodButton(isPM: true)
                        }
                    }
                    ClockDial(hour: $draft.time.hour)
                    HStack(spacing: 8) {
                        ForEach(ClockTime.minuteChoices, id: \.self) { minute in
                            Pill(title: String(format: ":%02d", minute), isOn: draft.time.minute == minute, showsCheck: false) {
                                draft.time.minute = minute
                            }
                            .accessibilityLabel("\(minute) minutes")
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 10) {
                    GroupLabel(text: String(localized: "How often"))
                    SegmentedBar(options: [
                        (ReminderFrequency.daily, String(localized: "Every day")),
                        (ReminderFrequency.everyTwoDays, String(localized: "Every 2 days")),
                        (ReminderFrequency.fridays, String(localized: "Fridays")),
                    ], selection: $draft.frequency)
                }

                if !draft.sources.isEmpty {
                    languageRows
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
        .background(Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) {
            SetupHeader(step: 2, onBack: onBack)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if !draft.isEditing {
                    Text("Next, iOS will ask to allow notifications. That is how your ayah reaches you.")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                }
                Button(draft.isEditing ? LocalizedStringKey("Save") : LocalizedStringKey("Start my daily ayah")) {
                    Task { await start() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSaving || draft.topics.isEmpty)
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(Palette.bg)
        }
        .sheet(isPresented: $showsReadingLanguages) {
            ReadingLanguagesSheet()
                .environment(draft)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Time

    private var readout: String {
        "\(draft.time.hour):" + String(format: "%02d", draft.time.minute)
    }

    private var spokenTime: String { formatted(draft.time) }

    private func formatted(_ time: ClockTime) -> String {
        var parts = DateComponents()
        parts.hour = time.hour24
        parts.minute = time.minute
        let date = Calendar.current.date(from: parts) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func periodButton(isPM: Bool) -> some View {
        let isOn = draft.time.isPM == isPM
        return Button {
            draft.time.isPM = isPM
        } label: {
            Text(verbatim: isPM ? Calendar.current.pmSymbol : Calendar.current.amSymbol)
                .font(.footnote.weight(.semibold))
                .frame(minWidth: 52, minHeight: 44)
                .foregroundStyle(isOn ? Palette.onAccent : Palette.ink)
                .background(isOn ? Palette.accent : Palette.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(isOn ? .clear : Palette.line, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var summary: String {
        let time = formatted(draft.time)
        switch draft.frequency {
        case .daily: return String(localized: "Every day at \(time) · change anytime")
        case .everyTwoDays: return String(localized: "Every 2 days at \(time) · change anytime")
        case .fridays: return String(localized: "Every Friday at \(time) · change anytime")
        }
    }

    // MARK: Languages

    private var languageRows: some View {
        VStack(spacing: 0) {
            Button {
                showsReadingLanguages = true
            } label: {
                languageRow(icon: "character.book.closed",
                            title: String(localized: "Read in: \(readingNames)"),
                            note: String(localized: "Translation and explanation"))
            }
            .buttonStyle(.plain)
            if draft.reminderLanguages.count > 1 {
                Divider().overlay(Palette.line)
                Menu {
                    ForEach(draft.reminderLanguages, id: \.self) { code in
                        Button {
                            draft.reminderLanguage = code
                        } label: {
                            if draft.reminderLanguage == code {
                                Label(LanguageName.autonym(code), systemImage: "checkmark")
                            } else {
                                Text(verbatim: LanguageName.autonym(code))
                            }
                        }
                    }
                } label: {
                    languageRow(icon: "bell",
                                title: String(localized: "Reminders in: \(LanguageName.autonym(draft.reminderLanguage))"),
                                note: String(localized: "Language on the lock screen"))
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.line, lineWidth: 1))
    }

    private var readingNames: String {
        let titles = draft.readingTranslations.compactMap { key in
            draft.sources.first { $0.key == key }.map { LanguageName.autonym($0.language) }
        }
        var unique: [String] = []
        for title in titles where !unique.contains(title) { unique.append(title) }
        return unique.joined(separator: " + ")
    }

    private func languageRow(icon: String, title: String, note: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Palette.accent)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 8)
            Text("Change")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    // MARK: Start

    /// Saves the choices, asks for notification permission the first time, and plans the reminders.
    private func start() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try draft.commit(to: context)
        } catch {
            return
        }
        let services = AppServices.shared
        if !(await services.notifications.isAuthorized()) {
            _ = await services.notifications.requestAuthorization()
        }
        await services.refillReminders()
        onFinished()
    }
}

/// The clock face: twelve hour buttons and a hand pointing at the chosen hour.
struct ClockDial: View {
    @Binding var hour: Int

    private let size: CGFloat = 264
    private let radius: CGFloat = 104

    var body: some View {
        ZStack {
            Circle().fill(Palette.fill)
            hand
            ForEach(ClockTime.dialHours, id: \.self) { value in
                let isOn = value == hour
                let point = position(forHour: value, radius: radius)
                Button {
                    hour = value
                } label: {
                    Text(verbatim: "\(value)")
                        .font(.system(size: 16, weight: isOn ? .bold : .medium))
                        .foregroundStyle(isOn ? Palette.onAccent : Palette.ink)
                        .frame(width: 44, height: 44)
                        .background(isOn ? Palette.accent : .clear, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(value) o'clock")
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .position(point)
            }
        }
        .frame(width: size, height: size)
        // The dial is drawn left to right in every language, like a real clock.
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clock: tap an hour")
    }

    private var hand: some View {
        let centre = CGPoint(x: size / 2, y: size / 2)
        let tip = position(forHour: hour, radius: radius - 22)
        return ZStack {
            Path { path in
                path.move(to: centre)
                path.addLine(to: tip)
            }
            .stroke(Palette.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            Circle()
                .fill(Palette.accent)
                .frame(width: 12, height: 12)
                .position(centre)
        }
        .animation(.snappy(duration: 0.2), value: hour)
        .accessibilityHidden(true)
    }

    private func position(forHour value: Int, radius: CGFloat) -> CGPoint {
        let angle = ClockTime.angle(forHour: value) * .pi / 180
        return CGPoint(x: size / 2 + radius * cos(angle), y: size / 2 + radius * sin(angle))
    }
}

/// Pick one or more translations to read with.
struct ReadingLanguagesSheet: View {
    @Environment(SetupDraft.self) private var draft
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(draft.sources) { source in
                        let isOn = draft.readingTranslations.contains(source.key)
                        Button {
                            draft.toggle(translation: source.key)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: LanguageName.autonym(source.language))
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(Palette.ink)
                                    Text(verbatim: source.title)
                                        .font(.footnote)
                                        .foregroundStyle(Palette.muted)
                                }
                                Spacer()
                                if isOn {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Palette.accent)
                                        .accessibilityHidden(true)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                } footer: {
                    Text("Pick one or more. Each translation is shown word for word from its source.")
                }
                if draft.hasArabicTafsir {
                    Section {
                        Button {
                            draft.showArabicTafsir.toggle()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Arabic explanation")
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(Palette.ink)
                                    Text(verbatim: "Al-Mukhtasar fi Tafsir al-Qur'an")
                                        .font(.footnote)
                                        .foregroundStyle(Palette.muted)
                                }
                                Spacer()
                                if draft.showArabicTafsir {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Palette.accent)
                                        .accessibilityHidden(true)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(draft.showArabicTafsir ? .isSelected : [])
                    } footer: {
                        Text("Shows Al-Mukhtasar fi Tafsir al-Qur'an in Arabic under each ayah.")
                    }
                }
            }
            .navigationTitle("Read in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
