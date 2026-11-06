import NasuhaCore
import SwiftData
import SwiftUI

@main
struct NasuhaApp: App {
    private let container: ModelContainer
    @State private var content = ContentLoader()

    init() {
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
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(content)
        }
        .modelContainer(container)
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
