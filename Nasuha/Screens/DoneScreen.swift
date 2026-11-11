import NasuhaCore
import SwiftData
import SwiftUI

/// The small reward after "I've read it".
struct DoneScreen: View {
    @Environment(ContentLoader.self) private var content
    @Query private var reads: [ReadRecord]

    let detail: AyahDetail
    let onNext: (String) -> Void
    let onHome: () -> Void

    @State private var next: NextAyah?

    private struct NextAyah {
        let setID: String
        let reference: String
    }

    private var storyCount: Int { reads.filter(\.hadStory).count }

    private var countLabel: LocalizedStringKey {
        if storyCount > 0 {
            return storyCount == 1 ? "ayah you now understand with its story" : "ayahs you now understand with their story"
        }
        return reads.count == 1 ? "ayah you have read" : "ayahs you have read"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "checkmark")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 92, height: 92)
                    .background(Palette.dawn, in: Circle())
                    .padding(20)
                    .background(Palette.dawnTint, in: Circle())
                    .accessibilityHidden(true)
                VStack(spacing: 6) {
                    Text("Alhamdulillah")
                        .font(.title.bold())
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(detail.ayahSet.story == nil
                         ? LocalizedStringKey("You read today's ayah.")
                         : LocalizedStringKey("You read today's ayah and the story behind it."))
                        .font(.callout)
                        .foregroundStyle(Palette.ink2)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 10) {
                    Text(verbatim: (storyCount > 0 ? storyCount : reads.count).formatted())
                        .font(.title.bold())
                    Text(countLabel)
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                }
                .foregroundStyle(Palette.tintInk)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Palette.tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityElement(children: .combine)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 56)
            .padding(.bottom, 24)
        }
        .background(Palette.bg)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                if let next {
                    Button("Read the next ayah, \(next.reference)") { onNext(next.setID) }
                        .buttonStyle(PrimaryButtonStyle())
                }
                ShareLink(item: RevelationText.shareText(detail)) {
                    Text("Share with family")
                }
                .buttonStyle(OutlineButtonStyle())
                if next == nil {
                    Button("Back to home", action: onHome)
                        .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button("Back to home", action: onHome)
                        .buttonStyle(TextLinkButtonStyle())
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(Palette.bg)
        }
        .task { findNext() }
    }

    /// The next unread ayah in the same topic, if there is one.
    private func findNext() {
        guard let store = content.store else { return }
        let read = Set(reads.map(\.ayahSetID)).union([detail.ayahSet.id])
        for topic in detail.ayahSet.topics {
            guard let ids = try? store.setIDs(topic: topic),
                  let id = TopicReading.next(after: detail.ayahSet.id, in: ids, read: read),
                  let set = try? store.ayahSet(id: id)
            else { continue }
            next = NextAyah(setID: id, reference: set.ayah.description)
            return
        }
    }
}
