import AppKit
import SwiftUI
import Combine

/// Main coordinator that manages the application state and components
class AppCoordinator: ObservableObject {
    // MARK: - Published Properties

    @Published var noteManager: NoteManager
    @Published var windowManager: WindowManager

    // MARK: - Properties

    /// Set to true during app termination to prevent note deletion on window close
    var isQuitting = false

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

    /// Create a new note and open its window on the current screen
    func createNewNote() {
        let position = calculateNewNotePosition()
        let note = noteManager.createNote(position: position)
        windowManager.openWindow(for: note, coordinator: self)
    }

    /// Called when a note window is closing (from windowWillClose delegate).
    /// If the app is quitting, skip — saveAllNotesImmediately() handles bulk save.
    /// Otherwise, delete the note (Apple Stickies behavior).
    func closeNoteWindow(_ noteId: UUID) {
        windowManager.removeWindow(for: noteId)

        if isQuitting {
            // saveAllNotesImmediately() already flushed JS + filtered empty notes
            return
        }
        // User explicitly closed — delete the note
        noteManager.deleteNote(noteId)
    }

    /// Handle note content changes from the editor
    func handleContentChange(noteId: UUID, content: String) {
        noteManager.updateNoteContent(noteId, content: content)
    }

    /// Handle window state changes
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

    /// Reopen windows for all existing notes
    func showAllNotes() {
        for note in noteManager.notes {
            windowManager.openWindow(for: note, coordinator: self)
        }
    }

    /// Change a note's color theme
    func changeNoteColor(noteId: UUID, colorTheme: String) {
        noteManager.updateNoteColor(noteId, colorTheme: colorTheme)
        windowManager.getWindowController(for: noteId)?.setColorTheme(colorTheme)
    }

    /// Change a note's opacity
    func setNoteOpacity(noteId: UUID, opacity: Double) {
        noteManager.updateNoteWindow(noteId, opacity: opacity)
        windowManager.getWindowController(for: noteId)?.setOpacity(opacity)
    }

    /// Get the note ID of the currently focused window
    func focusedNoteId() -> UUID? {
        guard let keyWindow = NSApp.keyWindow else { return nil }
        return windowManager.noteId(for: keyWindow)
    }

    /// Cycle focus to the next note window (Cmd+`)
    func cycleToNextWindow() {
        let allIds = windowManager.getAllWindowIds()
            .sorted { $0.uuidString < $1.uuidString }
        guard !allIds.isEmpty else { return }

        if let currentId = focusedNoteId(),
           let idx = allIds.firstIndex(of: currentId) {
            let next = allIds[(idx + 1) % allIds.count]
            windowManager.bringToFront(next)
        } else {
            windowManager.bringToFront(allIds[0])
        }
    }

    /// Flush JS editor content and save — called on app termination
    func saveAllNotesImmediately() {
        var pending = 0

        // Pull latest content from each editor's JS (bypasses the 300ms debounce)
        for note in noteManager.notes {
            guard let wc = windowManager.getWindowController(for: note.id),
                  let webView = wc.webView else { continue }

            pending += 1
            webView.evaluateJavaScript("window.getContent()") { [weak self] result, _ in
                if let content = result as? String {
                    self?.noteManager.updateNoteContent(note.id, content: content)
                }
                pending -= 1
            }
        }

        // Spin RunLoop to let async JS callbacks complete (max 0.5s)
        let deadline = Date().addingTimeInterval(0.5)
        while pending > 0 && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        // Filter out empty notes, then save to disk
        let nonEmptyNotes = noteManager.notes.filter {
            !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        persistenceManager.saveNotes(nonEmptyNotes)
    }

    // MARK: - Private Methods

    private func setupBindings() {
        noteManager.$notes
            .sink { [weak self] notes in
                self?.syncWindowsWithNotes(notes)
            }
            .store(in: &cancellables)
    }

    /// Open windows for all persisted notes
    private func openInitialWindows() {
        for note in noteManager.notes {
            windowManager.openWindow(for: note, coordinator: self)
        }
    }

    /// Calculate position for a new note: mouse cursor's screen, cascade from center
    private func calculateNewNotePosition() -> CGPoint {
        let noteSize = CGSize(width: 400, height: 500)

        // Multi-monitor: find the screen containing the mouse cursor
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let visibleFrame = screen.visibleFrame

        // Count windows already on this screen for cascade offset
        let existingFrames: [NSRect] = windowManager.getAllWindowIds().compactMap {
            windowManager.getWindowController(for: $0)?.window?.frame
        }
        let count = existingFrames.filter { visibleFrame.intersects($0) }.count

        // Cascade diagonally from screen center (down-right visually)
        let step: CGFloat = 30
        let x = visibleFrame.midX - noteSize.width / 2 + CGFloat(count) * step
        let y = visibleFrame.midY - noteSize.height / 2 - CGFloat(count) * step

        return CGPoint(
            x: min(max(x, visibleFrame.minX), visibleFrame.maxX - noteSize.width),
            y: min(max(y, visibleFrame.minY), visibleFrame.maxY - noteSize.height)
        )
    }

    private func syncWindowsWithNotes(_ notes: [Note]) {
        let noteIds = Set(notes.map { $0.id })
        let windowIds = Set(windowManager.getAllWindowIds())

        let windowsToClose = windowIds.subtracting(noteIds)
        for windowId in windowsToClose {
            windowManager.closeWindow(for: windowId)
        }
    }
}
