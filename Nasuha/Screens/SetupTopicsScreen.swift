import NasuhaCore
import SwiftUI

/// Setup, step 1: pick topics. Only topics that have ayahs are shown.
struct SetupTopicsScreen: View {
    @Environment(ContentLoader.self) private var content
    @Environment(SetupDraft.self) private var draft
    let onNext: () -> Void
    let onBack: () -> Void

    @State private var groups: [TopicGroup] = []
    @State private var query = ""
    @State private var showsMore = false
    @FocusState private var isSearching: Bool

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
                if !groups.isEmpty {
                    searchField
                }
                if !TopicSearch.words(query).isEmpty {
                    searchResults
                } else {
                    ForEach(groups.compactMap { $0.keeping(\.isFeatured) }) { group in
                        groupView(group)
                    }
                    let more = groups.compactMap { $0.keeping { !$0.isFeatured } }
                    if !more.isEmpty {
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { showsMore.toggle() }
                        } label: {
                            HStack(spacing: 6) {
                                Text("More topics")
                                Image(systemName: showsMore ? "chevron.up" : "chevron.down")
                                    .accessibilityHidden(true)
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.accent)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if showsMore {
                            ForEach(more) { group in
                                groupView(group)
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

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Palette.muted)
                .accessibilityHidden(true)
            TextField("Search topics", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isSearching)
                .foregroundStyle(Palette.ink)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.muted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, query.isEmpty ? 12 : 0)
        .frame(minHeight: 48)
        .background(Palette.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        // The whole box starts the search, not only the text inside it.
        .contentShape(Rectangle())
        .onTapGesture { isSearching = true }
    }

    @ViewBuilder private var searchResults: some View {
        let found = TopicSearch.matches(query, in: groups) { $0.localizedLabel }
        if found.isEmpty {
            Text("No topic matches “\(query.trimmingCharacters(in: .whitespaces))”.")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
        } else {
            pills(found)
        }
    }

    private func groupView(_ group: TopicGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GroupLabel(text: group.localizedTitle)
            if let note = group.localizedNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
            }
            pills(group.topics)
        }
    }

    private func pills(_ topics: [Topic]) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(topics) { topic in
                Pill(title: topic.localizedLabel, isOn: draft.topics.contains(topic.id)) {
                    draft.toggle(topic: topic.id)
                }
            }
        }
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
