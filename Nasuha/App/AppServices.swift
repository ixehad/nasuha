import BackgroundTasks
import NasuhaCore
import SwiftData
import SwiftUI

/// Shared services, created once at launch. The app delegate needs them before the
/// first scene exists (a notification tap can launch the app), so they live here.
@MainActor
final class AppServices {
    static let shared = AppServices()
    static let refreshTaskID = "app.nasuha.ios.refill"

    let container: ModelContainer
    let content: ContentLoader
    let router = AppRouter()
    let notifications = UserNotificationScheduler()
    let player = RecitationPlayer(catalog: .bundled())
    /// Nil only when the content database is missing.
    let reminders: ReminderController?

    private init() {
        if let onDisk = try? NasuhaSchema.container() {
            container = onDisk
        } else if let inMemory = try? NasuhaSchema.container(inMemory: true) {
            // The on-device store could not open. Keep the app usable for this session
            // rather than crashing; settings are kept in memory until the next launch.
            container = inMemory
        } else {
            // Only reachable if the schema itself is invalid, which the tests rule out.
            preconditionFailure("The data model could not be created.")
        }
        let loader = ContentLoader()
        content = loader
        let scheduler = notifications
        let context = container.mainContext
        reminders = loader.store.map { store in
            ReminderController(
                context: context,
                service: ReminderService(source: store, notifications: scheduler, localizer: CatalogLocalizer()))
        }
        if let store = loader.store {
            player.titleFor = { key in
                [(try? store.surah(key.surah))?.nameTransliterated, key.description].compactMap { $0 }.joined(separator: " ")
            }
        }
        player.onListened = { seconds in
            guard let progress = try? ReadingProgress.current(in: context) else { return }
            progress.listeningSeconds += seconds
            try? context.save()
        }
    }

    /// Registers the notification actions. "Listen" appears only when recitation is available.
    func registerNotificationActions() {
        notifications.registerCategories(
            listenTitle: String(localized: "Listen"),
            snoozeTitle: String(localized: "Remind me in 1 hour"),
            saveTitle: String(localized: "Save"),
            audioAvailable: player.isAvailable)
    }

    /// Brings reminders up to date and asks iOS for the next background refresh.
    func refillReminders() async {
        guard let reminders else { return }
        do {
            try await reminders.refill()
        } catch {
            // A failed refill leaves the previous schedule in place; the next open retries.
        }
        router.showAllRead = reminders.shouldShowAllRead
        scheduleBackgroundRefresh()
    }

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3_600)
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// Opens the bundled content database once.
@Observable
final class ContentLoader {
    let store: ContentStore?
    let error: Error?

    init() {
        do {
            store = try ContentStore.bundled()
            error = nil
        } catch {
            store = nil
            self.error = error
        }
    }
}

/// An ayah set to open on the Ayah screen.
struct AyahTarget: Identifiable, Hashable {
    let setID: String
    var id: String { setID }
}

/// Where the app should go next: a notification tap, a `nasuha://` link, or AllRead.
/// Set on cold start too; the screens read it once they appear.
@Observable
final class AppRouter {
    var ayah: AyahTarget?
    var showAllRead = false

    func open(_ link: DeepLink) {
        switch link {
        case .allRead: showAllRead = true
        case let .ayah(setID): ayah = AyahTarget(setID: setID)
        }
    }
}

/// Reads reminder text from the String Catalog in the reminder language,
/// which can differ from the phone's language.
struct CatalogLocalizer: Localizer {
    func string(_ key: String, language: String) -> String {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return Bundle.main.localizedString(forKey: key, value: key, table: nil) }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
