import AppKit
import SwiftUI

/// Window controller for a single note window
class NoteWindowController: NSWindowController, NSWindowDelegate {
    // MARK: - Properties

    private let note: Note
    private weak var coordinator: AppCoordinator?

    // MARK: - Initialization

    init(note: Note, coordinator: AppCoordinator) {
        self.note = note
        self.coordinator = coordinator

        // Create the panel (floating window)
        let panel = NSPanel(
            contentRect: NSRect(
                origin: note.position,
                size: note.size
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        super.init(window: panel)

        setupPanel(panel)
        setupContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup Methods

    private func setupPanel(_ panel: NSPanel) {
        // Configure panel behavior
        panel.level = .floating  // Always on top
        panel.isMovableByWindowBackground = true  // Drag to move
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.alphaValue = CGFloat(note.opacity)
        panel.title = "Sticky Note"
        panel.delegate = self

        // Set minimum size
        panel.minSize = NSSize(width: 200, height: 150)

        // Enable vibrancy for modern macOS look
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden

        // Restore minimized state
        if note.isMinimized {
            panel.miniaturize(nil)
        }
    }

    private func setupContent() {
        guard let panel = window as? NSPanel else { return }

        // Create the content view (NoteWebView wrapped in SwiftUI)
        let contentView = NoteContentView(note: note, coordinator: coordinator)
        let hostingView = NSHostingView(rootView: contentView)

        panel.contentView = hostingView
    }

    // MARK: - NSWindowDelegate Methods

    func windowWillClose(_ notification: Notification) {
        // Notify coordinator that window is closing
        coordinator?.closeNoteWindow(note.id)
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = window else { return }

        // Save new size
        let newSize = window.frame.size
        coordinator?.handleWindowStateChange(
            noteId: note.id,
            size: newSize
        )
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = window else { return }

        // Save new position
        let newPosition = window.frame.origin
        coordinator?.handleWindowStateChange(
            noteId: note.id,
            position: newPosition
        )
    }

    func windowDidMiniaturize(_ notification: Notification) {
        coordinator?.handleWindowStateChange(
            noteId: note.id,
            isMinimized: true
        )
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        coordinator?.handleWindowStateChange(
            noteId: note.id,
            isMinimized: false
        )
    }

    // MARK: - Public Methods

    /// Update window opacity
    /// - Parameter opacity: New opacity value (0.0 to 1.0)
    func setOpacity(_ opacity: Double) {
        window?.alphaValue = CGFloat(opacity)
    }
}
