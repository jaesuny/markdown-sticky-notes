import Foundation
import AppKit

/// Manages all note windows
class WindowManager: ObservableObject {
    // MARK: - Private Properties

    /// Dictionary mapping note IDs to their window controllers
    private var windowControllers: [UUID: NoteWindowController] = [:]

    // MARK: - Public Methods

    /// Open a window for a note
    /// - Parameters:
    ///   - note: The note to display
    ///   - coordinator: The app coordinator
    func openWindow(for note: Note, coordinator: AppCoordinator) {
        // Check if window already exists
        if let existingController = windowControllers[note.id] {
            existingController.showWindow(nil)
            return
        }

        // Create new window controller
        let windowController = NoteWindowController(note: note, coordinator: coordinator)
        windowControllers[note.id] = windowController
        windowController.showWindow(nil)

        print("[WindowManager] Opened window for note: \(note.id)")
    }

    /// Remove a window controller from tracking (does NOT call close)
    /// - Parameter noteId: ID of the note
    func removeWindow(for noteId: UUID) {
        guard windowControllers.removeValue(forKey: noteId) != nil else {
            return
        }
        print("[WindowManager] Removed window for note: \(noteId)")
    }

    /// Close a window for a note (used by syncWindowsWithNotes only)
    /// - Parameter noteId: ID of the note
    func closeWindow(for noteId: UUID) {
        guard let windowController = windowControllers.removeValue(forKey: noteId) else {
            return
        }
        windowController.close()
        print("[WindowManager] Closed window for note: \(noteId)")
    }

    /// Get window controller for a note
    /// - Parameter noteId: ID of the note
    /// - Returns: The window controller, if it exists
    func getWindowController(for noteId: UUID) -> NoteWindowController? {
        windowControllers[noteId]
    }

    /// Get all window IDs
    /// - Returns: Set of all note IDs that have open windows
    func getAllWindowIds() -> Set<UUID> {
        Set(windowControllers.keys)
    }

    /// Find which note a given NSWindow belongs to
    func noteId(for window: NSWindow) -> UUID? {
        windowControllers.first(where: { $0.value.window === window })?.key
    }

    /// Close all windows
    func closeAllWindows() {
        for (noteId, _) in windowControllers {
            closeWindow(for: noteId)
        }
    }

    /// Bring window to front
    /// - Parameter noteId: ID of the note
    func bringToFront(_ noteId: UUID) {
        guard let windowController = windowControllers[noteId] else {
            return
        }

        windowController.window?.makeKeyAndOrderFront(nil)
    }

    /// Get count of open windows
    var openWindowCount: Int {
        windowControllers.count
    }
}
