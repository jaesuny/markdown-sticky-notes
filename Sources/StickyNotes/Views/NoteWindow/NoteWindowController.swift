import AppKit
import SwiftUI
import WebKit

/// Window controller for a single note window
class NoteWindowController: NSWindowController, NSWindowDelegate {
    // MARK: - Properties

    private var note: Note
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
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow, .fullSizeContentView],
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
        panel.backgroundColor = NoteColor.from(note.colorTheme).color
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

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let coordinator = coordinator else { return true }
        if coordinator.isQuitting { return true }

        // Empty note → close silently
        guard let current = coordinator.noteManager.getNote(note.id),
              !current.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }

        // Note has content → confirm deletion
        let alert = NSAlert()
        alert.messageText = "Delete this note?"
        alert.informativeText = "This note has content that will be lost."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        return alert.runModal() == .alertFirstButtonReturn
    }

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
    func setOpacity(_ opacity: Double) {
        window?.alphaValue = CGFloat(opacity)
    }

    /// Update window color theme
    func setColorTheme(_ theme: String) {
        note.colorTheme = theme
        window?.backgroundColor = NoteColor.from(theme).color
    }

    /// Get note ID
    var noteId: UUID { note.id }

    /// Find the WKWebView in the window's view hierarchy
    var webView: WKWebView? {
        findWebView(in: window?.contentView)
    }

    private func findWebView(in view: NSView?) -> WKWebView? {
        if let wk = view as? WKWebView { return wk }
        for sub in view?.subviews ?? [] {
            if let found = findWebView(in: sub) { return found }
        }
        return nil
    }
}
