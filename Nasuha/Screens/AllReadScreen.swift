import NasuhaCore
import SwiftData
import SwiftUI

/// Shown after the last ayah in the chosen topics has been sent.
struct AllReadScreen: View {
    @Environment(ContentLoader.self) private var content
    @Query private var settings: [UserSettings]
    @Query(sort: \TopicChoice.order) private var choices: [TopicChoice]
    @Query private var reads: [ReadRecord]
    @Query private var saved: [SavedAyah]
    @Query private var records: [ReminderRecord]

    let onChoice: (AllReadChoice) -> Void

    @State private var pick: AllReadChoice = .pickNewTopics
    @State private var untried = 0
    @State private var isWorking = false

    private var state: ReminderState { records.first?.state ?? ReminderState() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Palette.dawnInk)
                        .frame(width: 64, height: 64)
                        .background(Palette.dawnTint, in: Circle())
                        .accessibilityHidden(true)
                    Text("Alhamdulillah, all done")
                        .font(.title2.bold())
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    if !topicNames.isEmpty {
                        Text("You read every ayah in \(topicNames).")
                            .font(.subheadline)
                            .foregroundStyle(Palette.ink2)
                            .multilineTextAlignment(.center)
                    }
                    FlowLayout(spacing: 8) {
                        stat("\(state.total) ayahs")
                        if storyCount > 0 { stat("\(storyCount) stories") }
                        if !saved.isEmpty { stat("\(saved.count) saved") }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)

                VStack(alignment: .leading, spacing: 8) {
                    Text("What next?")
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    if untried > 0 {
                        option(.pickNewTopics, title: "Pick new topics",
                               note: String(localized: "\(untried) topics you haven't tried yet"))
                    } else {
                        option(.pickNewTopics, title: "Pick new topics",
                               note: String(localized: "Choose a different mix of topics"))
                    }
                    option(.changeTime, title: "Change time or how often",
                           note: String(localized: "Keep your topics, read them again at a new time"))
                    option(.startAgain, title: "Start again from the first",
                           note: String(localized: "Read the same ayahs again, from the first one"))
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
        .background(Palette.bg)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                Button(goLabel) {
                    Task { await go() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isWorking)
                Text("If you don't choose, we start again from the first ayah at your next reminder.")
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
        .task { countUntried() }
        .preferredColorScheme(settings.first?.appearance.colorScheme)
    }

    private var storyCount: Int { reads.filter(\.hadStory).count }

    private var topicNames: String {
        ListFormatter.localizedString(byJoining: choices.compactMap { TopicCatalog.topic($0.topicID)?.localizedLabel })
    }

    private var goLabel: LocalizedStringKey {
        switch pick {
        case .pickNewTopics: "Pick new topics"
        case .changeTime: "Change time"
        case .startAgain: "Start again"
        }
    }

    private func stat(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .frame(minHeight: 30)
            .foregroundStyle(Palette.ink)
            .background(Palette.fill, in: Capsule())
    }

    private func option(_ choice: AllReadChoice, title: LocalizedStringKey, note: String) -> some View {
        let isOn = pick == choice
        return Button {
            pick = choice
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .strokeBorder(isOn ? Palette.accent : Palette.line, lineWidth: isOn ? 6 : 2)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Text(verbatim: note)
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(isOn ? Palette.tint : Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isOn ? Palette.accent : Palette.line, lineWidth: isOn ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func countUntried() {
        let counts = (try? content.store?.topicSetCounts()) ?? [:]
        let available = TopicCatalog.available(setCounts: counts).flatMap(\.topics).map(\.id)
        let chosen = Set(choices.map(\.topicID))
        untried = available.filter { !chosen.contains($0) }.count
    }

    private func go() async {
        isWorking = true
        defer { isWorking = false }
        try? await AppServices.shared.reminders?.answerAllRead(pick)
        onChoice(pick)
    }
}
