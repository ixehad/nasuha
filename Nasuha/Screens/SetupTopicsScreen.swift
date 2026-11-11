import NasuhaCore
import SwiftUI

/// Setup, step 1: pick topics. Only topics that have ayahs are shown.
struct SetupTopicsScreen: View {
    @Environment(ContentLoader.self) private var content
    @Environment(SetupDraft.self) private var draft
    let onNext: () -> Void
    let onBack: () -> Void

    @State private var groups: [TopicGroup] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What does your heart need?")
                        .font(.title2.bold())
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("Pick as many as you like. We mix them, one ayah a day.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                }
                if groups.isEmpty {
                    Text("No topics are available yet.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                        .padding(.top, 8)
                }
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        GroupLabel(text: group.localizedTitle)
                        if let note = group.localizedNote {
                            Text(note)
                                .font(.footnote)
                                .foregroundStyle(Palette.muted)
                        }
                        FlowLayout(spacing: 8) {
                            ForEach(group.topics) { topic in
                                Pill(title: topic.localizedLabel, isOn: draft.topics.contains(topic.id)) {
                                    draft.toggle(topic: topic.id)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
        .background(Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) {
            SetupHeader(step: 1, onBack: onBack)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                Button("Next: pick a time", action: onNext)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(draft.topics.isEmpty)
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
        .task { loadGroups() }
    }

    private var summary: String {
        let count = draft.topics.count
        if count == 0 { return String(localized: "Pick at least one topic") }
        return String(localized: "\(count) topics picked · change anytime on Home")
    }

    private func loadGroups() {
        let counts = (try? content.store?.topicSetCounts()) ?? [:]
        groups = TopicCatalog.available(setCounts: counts)
    }
}

/// Back button and step marker shared by the setup screens.
struct SetupHeader: View {
    let step: Int
    let onBack: () -> Void

    var body: some View {
        HStack {
            IconButton(systemName: "chevron.backward", label: "Back", action: onBack)
            Spacer()
            StepDots(current: step, total: 2)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 12)
        .background(Palette.bg)
    }
}
