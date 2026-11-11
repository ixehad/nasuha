import NasuhaCore
import SwiftData
import SwiftUI

/// The top of the app: the first-open screen until setup is done (or the person
/// chooses to look around), then Home. Setup, Ayah and AllRead open from here.
struct RootView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query private var settings: [UserSettings]

    @State private var path: [SetupRoute] = []
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
                    HomeScreen(openSetup: openSetup)
                } else {
                    MainScreen(onSetUp: { openSetup(.topics) }, onLookAround: { isLookingAround = true })
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SetupRoute.self) { route in
                Group {
                    switch route {
                    case .topics:
                        SetupTopicsScreen(onNext: { path.append(.time) }, onBack: back)
                    case .time:
                        SetupTimeScreen(onFinished: { path = [] }, onBack: back)
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
        }
        .fullScreenCover(isPresented: $router.showAllRead) {
            AllReadScreen(onChoice: finishAllRead)
                .environment(content)
        }
        .tint(Palette.accent)
        .preferredColorScheme(settings.first?.appearance.colorScheme)
    }

    private func openSetup(_ route: SetupRoute) {
        draft.load(from: context, store: content.store)
        path = [route]
    }

    private func back() {
        if !path.isEmpty { path.removeLast() }
    }

    private func finishAllRead(_ choice: AllReadChoice) {
        router.showAllRead = false
        switch choice {
        case .pickNewTopics: openSetup(.topics)
        case .changeTime: openSetup(.time)
        case .startAgain: break
        }
    }
}
