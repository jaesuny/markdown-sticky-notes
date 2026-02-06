import SwiftUI
import AppKit

// MARK: - App Delegate

/// Keeps the app alive when all windows are closed and provides dock menu
class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.isQuitting = true
        coordinator.saveAllNotesImmediately()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let newNoteItem = NSMenuItem(
            title: "New Note",
            action: #selector(createNewNote),
            keyEquivalent: ""
        )
        newNoteItem.target = self
        menu.addItem(newNoteItem)
        return menu
    }

    @objc func createNewNote() {
        coordinator.createNewNote()
    }
}

// MARK: - App Entry Point

@main
struct StickyNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarCommands(coordinator: appDelegate.coordinator)
    }
}

// MARK: - Menu Bar

struct MenuBarCommands: Scene {
    @ObservedObject var coordinator: AppCoordinator

    var body: some Scene {
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

                Divider()

                Button("Show All Notes") {
                    coordinator.showAllNotes()
                }
            }

            // Edit menu — Find in note (Cmd+F → WKWebView)
            CommandGroup(replacing: .textEditing) {
                Button("Find...") {
                    if let noteId = coordinator.focusedNoteId(),
                       let wc = coordinator.windowManager.getWindowController(for: noteId),
                       let webView = wc.webView {
                        webView.evaluateJavaScript("window.openSearch()")
                    }
                }
                .keyboardShortcut("f", modifiers: .command)
            }

            // Window menu — Cmd+` to cycle between note windows
            CommandGroup(before: .windowList) {
                Button("Cycle Through Notes") {
                    coordinator.cycleToNextWindow()
                }
                .keyboardShortcut("`", modifiers: .command)
            }

            // Format menu
            CommandMenu("Format") {
                Menu("Note Color") {
                    ForEach(NoteColor.allCases, id: \.self) { color in
                        Button(color.displayName) {
                            if let noteId = coordinator.focusedNoteId() {
                                coordinator.changeNoteColor(noteId: noteId, colorTheme: color.rawValue)
                            }
                        }
                    }
                }

                Divider()

                Menu("Opacity") {
                    Button("100%") { setOpacity(1.0) }
                    Button("75%") { setOpacity(0.75) }
                    Button("50%") { setOpacity(0.5) }
                    Button("25%") { setOpacity(0.25) }
                }
            }
        }
    }

    private func setOpacity(_ opacity: Double) {
        if let noteId = coordinator.focusedNoteId() {
            coordinator.setNoteOpacity(noteId: noteId, opacity: opacity)
        }
    }

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }
}
