import AppKit
import SwiftUI
import WebKit

/// Window controller for a single note window
class NoteWindowController: NSWindowController, NSWindowDelegate {
    // MARK: - Properties

    private var note: Note
    private weak var coordinator: AppCoordinator?
    private var pinButton: NSButton?
    private var colorButtons: [NoteColor: NSButton] = [:]
    private var opacitySlider: NSSlider?

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
        setupTitlebarAccessory(panel)
        setupContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup Methods

    private func setupPanel(_ panel: NSPanel) {
        // Configure panel behavior
        panel.hidesOnDeactivate = false  // Critical: keep visible when app loses focus
        if note.alwaysOnTop {
            panel.level = .popUpMenu  // Level 101
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isFloatingPanel = true
        } else {
            panel.level = .floating
            panel.isFloatingPanel = false
        }
        panel.isMovableByWindowBackground = true  // Drag to move
        panel.isOpaque = false
        panel.backgroundColor = NoteColor.from(note.colorTheme).color
        panel.alphaValue = CGFloat(note.opacity)
        panel.title = "Sticky Note"
        panel.delegate = self

        // Set minimum size
        panel.minSize = NSSize(width: 280, height: 150)

        // Enable vibrancy for modern macOS look
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden

        // Restore minimized state
        if note.isMinimized {
            panel.miniaturize(nil)
        }
    }

    private func setupTitlebarAccessory(_ panel: NSPanel) {
        // Remove any existing accessories first
        while !panel.titlebarAccessoryViewControllers.isEmpty {
            panel.removeTitlebarAccessoryViewController(at: 0)
        }


        // Use a custom container that shows arrow cursor instead of text cursor
        // Order: [slider] [pin] [color dots] — pin between slider and colors
        let container = TitlebarControlsView(frame: NSRect(x: 0, y: 0, width: 190, height: 22))

        var xOffset: CGFloat = 4

        // Opacity slider
        let slider = NSSlider(frame: NSRect(x: xOffset, y: 4, width: 50, height: 14))
        slider.minValue = 0.2
        slider.maxValue = 1.0
        slider.doubleValue = note.opacity
        slider.target = self
        slider.action = #selector(opacityChanged(_:))
        slider.controlSize = .mini
        slider.toolTip = "Opacity"
        opacitySlider = slider
        container.addSubview(slider)
        xOffset += 58  // 50 + 8px gap

        // Pin button (between slider and color dots) — subtle SF Symbol, opacity only
        let pin = NSButton(frame: NSRect(x: xOffset, y: 2, width: 18, height: 18))
        pin.wantsLayer = true
        pin.bezelStyle = .regularSquare
        pin.isBordered = false
        pin.title = ""
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        if let img = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pin")?
            .withSymbolConfiguration(config) {
            pin.image = img
        }
        // High contrast: active = dark, inactive = light (use alphaValue for reliability)
        pin.contentTintColor = .labelColor
        pin.alphaValue = note.alwaysOnTop ? 1.0 : 0.25
        pin.imagePosition = .imageOnly
        pin.target = self
        pin.action = #selector(toggleAlwaysOnTop)
        pin.toolTip = "Always on Top"
        pinButton = pin
        container.addSubview(pin)
        xOffset += 26  // 18 + 8px gap

        // Color dots
        for color in NoteColor.allCases {
            let dot = NSButton(frame: NSRect(x: xOffset, y: 5, width: 12, height: 12))
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 6
            dot.layer?.backgroundColor = color.color.cgColor
            dot.layer?.borderWidth = color.rawValue == note.colorTheme ? 2 : 1
            dot.layer?.borderColor = NSColor(white: 0, alpha: color.rawValue == note.colorTheme ? 0.4 : 0.12).cgColor
            dot.isBordered = false
            dot.title = ""
            dot.target = self
            dot.action = #selector(colorDotClicked(_:))
            dot.toolTip = color.displayName
            colorButtons[color] = dot
            container.addSubview(dot)
            xOffset += 16  // 12 + 4px gap
        }

        // Add to titlebar
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = container
        accessory.layoutAttribute = .right
        panel.addTitlebarAccessoryViewController(accessory)
    }

    @objc private func colorDotClicked(_ sender: NSButton) {
        guard let color = colorButtons.first(where: { $0.value === sender })?.key else { return }

        // Update appearance
        for (c, btn) in colorButtons {
            btn.layer?.borderWidth = c == color ? 2 : 1
            btn.layer?.borderColor = NSColor(white: 0, alpha: c == color ? 0.4 : 0.12).cgColor
        }

        // Update note
        note.colorTheme = color.rawValue
        window?.backgroundColor = color.color
        coordinator?.changeNoteColor(noteId: note.id, colorTheme: color.rawValue)

        // Update titlebar mask in JS
        webView?.evaluateJavaScript("window.setNoteColor('\(color.rawValue)')", completionHandler: nil)
    }

    @objc private func opacityChanged(_ sender: NSSlider) {
        let opacity = sender.doubleValue
        note.opacity = opacity
        window?.alphaValue = CGFloat(opacity)
        coordinator?.setNoteOpacity(noteId: note.id, opacity: opacity)
    }

    @objc private func toggleAlwaysOnTop() {
        note.alwaysOnTop.toggle()
        setAlwaysOnTop(note.alwaysOnTop)
        coordinator?.setNoteAlwaysOnTop(noteId: note.id, alwaysOnTop: note.alwaysOnTop)

        // Update button appearance — high contrast via alphaValue
        pinButton?.alphaValue = note.alwaysOnTop ? 1.0 : 0.25
    }

    private func setupContent() {
        guard let panel = window as? NSPanel else { return }

        // Create the content view (NoteWebView wrapped in SwiftUI)
        let contentView = NoteContentView(note: note, coordinator: coordinator)
        let hostingView = NSHostingView(rootView: contentView)

        // Wrap in a container with titlebar cursor overlay
        let contentRect = panel.contentRect(forFrameRect: panel.frame)
        let container = NSView(frame: NSRect(origin: .zero, size: contentRect.size))
        container.autoresizingMask = [.width, .height]
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)

        // Add invisible overlay on titlebar area (top 28px) for arrow cursor
        let titlebarOverlay = TitlebarCursorView(frame: NSRect(x: 0, y: contentRect.height - 28, width: contentRect.width, height: 28))
        titlebarOverlay.autoresizingMask = [.width, .minYMargin]
        container.addSubview(titlebarOverlay)

        panel.contentView = container
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

    /// Update always-on-top setting
    func setAlwaysOnTop(_ alwaysOnTop: Bool) {
        note.alwaysOnTop = alwaysOnTop
        guard let panel = window as? NSPanel else { return }

        if alwaysOnTop {
            // Key settings for true always-on-top
            panel.level = .popUpMenu  // Level 101, above most windows
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isFloatingPanel = true
            panel.orderFrontRegardless()  // Force to front
        } else {
            panel.level = .floating
            panel.collectionBehavior = [.managed]
            panel.isFloatingPanel = false
        }
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

// MARK: - Titlebar Views

/// Custom view that shows arrow cursor instead of I-beam text cursor
private class TitlebarControlsView: NSView {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}

/// Transparent overlay for titlebar area that sets arrow cursor but forwards mouse events
private class TitlebarCursorView: NSView {
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .cursorUpdate, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        // Forward to next responder (traffic lights, titlebar drag)
        nextResponder?.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        nextResponder?.mouseUp(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        nextResponder?.mouseDragged(with: event)
    }
}
