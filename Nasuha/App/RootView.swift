import NasuhaCore
import SwiftData
import SwiftUI

/// The top of the app: the first-open screen until setup is done (or the person
/// chooses to look around), then Home. Setup, Ayah and AllRead open from here.
struct RootView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var systemTextSize
    @Query private var settings: [UserSettings]

    @State private var path: [AppRoute] = []
    @State private var draft = SetupDraft()
    @State private var isLookingAround = false

    private var showsHome: Bool {
        isLookingAround || (settings.first?.hasCompletedSetup ?? false)
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $path) {
            Group {
                if showsHome {
                    HomeScreen(open: open)
                } else {
                    MainScreen(onSetUp: { open(.topics) }, onLookAround: { isLookingAround = true })
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AppRoute.self) { route in
                Group {
                    switch route {
                    case .topics:
                        SetupTopicsScreen(onNext: { path.append(.time) }, onBack: back)
                    case .time:
                        SetupTimeScreen(onFinished: { path.removeAll(where: \.isSetup) }, onBack: back)
                    case .settings:
                        SettingsScreen(open: open, onBack: back)
                    case .profile:
                        ProfileScreen(open: open, onBack: back)
                    case .saved:
                        SavedScreen(open: open, onBack: back)
                    case .about:
                        AboutScreen(open: open, onBack: back)
                    case .legal:
                        LegalScreen(onBack: back)
                    case .support:
                        SupportScreen(onBack: back)
                    case let .reader(target):
                        QuranScreen(target: target, onBack: back) { setID in
                            self.router.ayah = AyahTarget(setID: setID)
                        }
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
            }
        }
        .environment(draft)
        .fullScreenCover(item: $router.ayah) { target in
            AyahFlow(setID: target.setID)
                .environment(content)
                .environment(self.router)
                .environment(AppServices.shared.player)
                .dynamicTypeSize(textSize)
        }
        .fullScreenCover(isPresented: $router.showAllRead) {
            AllReadScreen(onChoice: finishAllRead)
                .environment(content)
                .dynamicTypeSize(textSize)
        }
        .tint(Palette.accent)
        .dynamicTypeSize(textSize)
        .preferredColorScheme(settings.first?.appearance.colorScheme)
    }

    /// The phone's text size, moved up or down by the Text size setting.
    private var textSize: DynamicTypeSize {
        let all = DynamicTypeSize.allCases
        let index = all.firstIndex(of: systemTextSize) ?? 3
        return all[(settings.first?.textSize ?? .standard).shifted(index, count: all.count)]
    }

    private func open(_ route: AppRoute) {
        if route.isSetup { draft.load(from: context, store: content.store) }
        // Setup started from Home replaces what is on screen; everything else is pushed on top.
        if route == .topics, !path.contains(.settings) {
            path = [route]
        } else if path.last != route {
            path.append(route)
        }
    }

    private func back() {
        if !path.isEmpty { path.removeLast() }
    }

    private func finishAllRead(_ choice: AllReadChoice) {
        router.showAllRead = false
        switch choice {
        case .pickNewTopics: open(.topics)
        case .changeTime: open(.time)
        case .startAgain: break
        }
    }
}
