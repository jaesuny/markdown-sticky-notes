import Foundation
import Combine

/// Manages the collection of all notes
class NoteManager: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var notes: [Note] = []

    // MARK: - Private Properties

    private let persistenceManager: PersistenceManager

    // MARK: - Initialization

    init(persistenceManager: PersistenceManager = PersistenceManager()) {
        self.persistenceManager = persistenceManager
        loadNotes()
    }

    // MARK: - Public Methods

    /// Load notes from persistence
    func loadNotes() {
        notes = persistenceManager.loadNotes()

        // If no notes exist, create a default welcome note
        if notes.isEmpty {
            createDefaultNote()
        }
    }

    /// Create a new note
    /// - Parameter content: Initial content for the note
    /// - Returns: The newly created note
    @discardableResult
    func createNote(content: String = "") -> Note {
        // Calculate position offset from last note
        let offset: CGFloat = 30
        let lastPosition = notes.last?.position ?? CGPoint(x: 100, y: 100)
        let newPosition = CGPoint(
            x: lastPosition.x + offset,
            y: lastPosition.y + offset
        )

        let note = Note(
            content: content,
            position: newPosition
        )

        notes.append(note)
        persistenceManager.saveNotesDebounced(notes)

        print("[NoteManager] Created new note: \(note.id)")
        return note
    }

    /// Update an existing note
    /// - Parameter note: The updated note
    func updateNote(_ note: Note) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else {
            print("[NoteManager] Warning: Attempting to update non-existent note: \(note.id)")
            return
        }

        var updatedNote = note
        updatedNote.updateModificationDate()
        notes[index] = updatedNote

        persistenceManager.saveNotesDebounced(notes)
        print("[NoteManager] Updated note: \(note.id)")
    }

    /// Update note content
    /// - Parameters:
    ///   - noteId: ID of the note to update
    ///   - content: New content
    func updateNoteContent(_ noteId: UUID, content: String) {
        guard let index = notes.firstIndex(where: { $0.id == noteId }) else {
            return
        }

        notes[index].content = content
        notes[index].updateModificationDate()

        persistenceManager.saveNotesDebounced(notes)
    }

    /// Update note window state (position, size, opacity)
    /// - Parameters:
    ///   - noteId: ID of the note to update
    ///   - position: New window position (optional)
    ///   - size: New window size (optional)
    ///   - opacity: New opacity (optional)
    ///   - isMinimized: New minimized state (optional)
    func updateNoteWindow(
        _ noteId: UUID,
        position: CGPoint? = nil,
        size: CGSize? = nil,
        opacity: Double? = nil,
        isMinimized: Bool? = nil
    ) {
        guard let index = notes.firstIndex(where: { $0.id == noteId }) else {
            return
        }

        if let position = position {
            notes[index].position = position
        }
        if let size = size {
            notes[index].size = size
        }
        if let opacity = opacity {
            notes[index].opacity = opacity
        }
        if let isMinimized = isMinimized {
            notes[index].isMinimized = isMinimized
        }

        notes[index].updateModificationDate()
        persistenceManager.saveNotesDebounced(notes)
    }

    /// Delete a note
    /// - Parameter noteId: ID of the note to delete
    func deleteNote(_ noteId: UUID) {
        notes.removeAll { $0.id == noteId }
        persistenceManager.saveNotes(notes)
        print("[NoteManager] Deleted note: \(noteId)")
    }

    /// Save a note immediately (for critical operations)
    /// - Parameter note: The note to save
    func saveNoteImmediately(_ note: Note) {
        updateNote(note)
        persistenceManager.saveNotes(notes)
    }

    /// Get a note by ID
    /// - Parameter noteId: The note ID
    /// - Returns: The note, if found
    func getNote(_ noteId: UUID) -> Note? {
        notes.first { $0.id == noteId }
    }

    // MARK: - Private Methods

    /// Create a default welcome note
    private func createDefaultNote() {
        let welcomeContent = """
# Welcome to Sticky Notes!

This is a **markdown-enabled** sticky note.

## Features
- Live markdown preview
- Math equations: $E = mc^2$
- Code blocks
- And more!

Start typing to get started.
"""

        createNote(content: welcomeContent)
    }
}
