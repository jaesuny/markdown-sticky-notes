import Foundation
import SwiftUI
import Combine

/// Main coordinator that manages the application state and components
class AppCoordinator: ObservableObject {
    // MARK: - Published Properties

    @Published var noteManager: NoteManager
    @Published var windowManager: WindowManager

    // MARK: - Private Properties

    private let persistenceManager: PersistenceManager
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        self.persistenceManager = PersistenceManager()
        self.noteManager = NoteManager(persistenceManager: persistenceManager)
        self.windowManager = WindowManager()

        setupBindings()
        openInitialWindows()
    }

    // MARK: - Public Methods

    /// Create a new note and open its window
    func createNewNote() {
        let note = noteManager.createNote()
        windowManager.openWindow(for: note, coordinator: self)
    }

    /// Called when a note window is closing (from windowWillClose delegate)
    /// The window is already closing — only remove tracking and save.
    /// - Parameter noteId: ID of the note to close
    func closeNoteWindow(_ noteId: UUID) {
        // Remove from tracking (do NOT call close — window is already closing)
        windowManager.removeWindow(for: noteId)

        // Save the note immediately before closing
        if let note = noteManager.getNote(noteId) {
            noteManager.saveNoteImmediately(note)
        }

        // Optionally delete empty notes
        if let note = noteManager.getNote(noteId), note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            noteManager.deleteNote(noteId)
        }
    }

    /// Handle note content changes from the editor
    /// - Parameters:
    ///   - noteId: ID of the note
    ///   - content: New content
    func handleContentChange(noteId: UUID, content: String) {
        noteManager.updateNoteContent(noteId, content: content)
    }

    /// Handle window state changes
    /// - Parameters:
    ///   - noteId: ID of the note
    ///   - position: New position (optional)
    ///   - size: New size (optional)
    ///   - isMinimized: New minimized state (optional)
    func handleWindowStateChange(
        noteId: UUID,
        position: CGPoint? = nil,
        size: CGSize? = nil,
        isMinimized: Bool? = nil
    ) {
        noteManager.updateNoteWindow(
            noteId,
            position: position,
            size: size,
            isMinimized: isMinimized
        )
    }

    // MARK: - Private Methods

    /// Set up reactive bindings
    private func setupBindings() {
        // Observe note changes and sync with window manager
        noteManager.$notes
            .sink { [weak self] notes in
                self?.syncWindowsWithNotes(notes)
            }
            .store(in: &cancellables)
    }

    /// Open windows for all existing notes
    private func openInitialWindows() {
        for note in noteManager.notes {
            windowManager.openWindow(for: note, coordinator: self)
        }
    }

    /// Sync windows with notes (close windows for deleted notes, etc.)
    /// - Parameter notes: Current notes array
    private func syncWindowsWithNotes(_ notes: [Note]) {
        let noteIds = Set(notes.map { $0.id })
        let windowIds = Set(windowManager.getAllWindowIds())

        // Close windows for deleted notes
        let windowsToClose = windowIds.subtracting(noteIds)
        for windowId in windowsToClose {
            windowManager.closeWindow(for: windowId)
        }
    }
}
