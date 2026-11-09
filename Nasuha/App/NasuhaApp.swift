import NasuhaCore
import SwiftData
import SwiftUI
import UIKit

@main
struct NasuhaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    private var services: AppServices { AppServices.shared }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services.content)
                .environment(services.router)
                .onOpenURL { url in
                    if let link = DeepLink(url: url) { services.router.open(link) }
                }
                .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                    Task { await services.refillReminders() }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    Task { await services.refillReminders() }
                }
        }
        .modelContainer(services.container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await services.refillReminders() } }
        }
        .backgroundTask(.appRefresh(AppServices.refreshTaskID)) {
            await AppServices.shared.refillReminders()
        }
    }
}
