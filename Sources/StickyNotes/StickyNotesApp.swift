import SwiftUI

@main
struct StickyNotesApp: App {
    // MARK: - Properties

    @StateObject private var coordinator = AppCoordinator()

    // MARK: - App Lifecycle

    var body: some Scene {
        // Menu bar commands
        MenuBarCommands(coordinator: coordinator)
    }
}

/// Menu bar commands and actions
struct MenuBarCommands: Scene {
    @ObservedObject var coordinator: AppCoordinator

    var body: some Scene {
        // Settings window (optional, hidden for now)
        Settings {
            EmptyView()
        }
        .commands {
            // File menu
            CommandGroup(replacing: .newItem) {
                Button("New Note") {
                    coordinator.createNewNote()
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            // Edit menu - use default

            // Window menu - use default
        }
    }

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }
}
