import AppKit
import SwiftUI
import WebKit

/// Window controller for a single note window.
/// Uses a shared WKWebView that gets reparented to the active (key) window.
/// Inactive windows show a snapshot image of their last editor state.
class NoteWindowController: NSWindowController, NSWindowDelegate {
    // MARK: - Properties

    private var note: Note
    private weak var coordinator: AppCoordinator?
    private var pinButton: NSButton?
    private var colorButtons: [NoteColor: NSButton] = [:]
    private var opacitySlider: NSSlider?

    /// The main content container that holds either WKWebView or text preview/snapshot
    private var contentContainer: NSView!

    /// Whether the shared WKWebView is currently attached to this window
    private(set) var hasWebView = false

    /// Cached snapshot of the last rendered editor state (shown when WebView moves to another window)
    private var snapshotView: NSImageView?

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
        panel.hidesOnDeactivate = false
        if note.alwaysOnTop {
            panel.level = .popUpMenu
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isFloatingPanel = true
        } else {
            panel.level = .floating
            panel.isFloatingPanel = false
        }
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = NoteColor.from(note.colorTheme).color
        panel.alphaValue = CGFloat(note.opacity)
        panel.title = "Sticky Note"
        panel.delegate = self

        panel.minSize = NSSize(width: 280, height: 150)

        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden

        if note.isMinimized {
            panel.miniaturize(nil)
        }
    }

    private func setupTitlebarAccessory(_ panel: NSPanel) {
        while !panel.titlebarAccessoryViewControllers.isEmpty {
            panel.removeTitlebarAccessoryViewController(at: 0)
        }

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
        xOffset += 58

        // Pin button
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
        pin.contentTintColor = .labelColor
        pin.alphaValue = note.alwaysOnTop ? 1.0 : 0.25
        pin.imagePosition = .imageOnly
        pin.target = self
        pin.action = #selector(toggleAlwaysOnTop)
        pin.toolTip = "Always on Top"
        pinButton = pin
        container.addSubview(pin)
        xOffset += 26

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
            xOffset += 16
        }

        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = container
        accessory.layoutAttribute = .right
        panel.addTitlebarAccessoryViewController(accessory)
    }

    @objc private func colorDotClicked(_ sender: NSButton) {
        guard let color = colorButtons.first(where: { $0.value === sender })?.key else { return }

        for (c, btn) in colorButtons {
            btn.layer?.borderWidth = c == color ? 2 : 1
            btn.layer?.borderColor = NSColor(white: 0, alpha: c == color ? 0.4 : 0.12).cgColor
        }

        note.colorTheme = color.rawValue
        window?.backgroundColor = color.color
        coordinator?.changeNoteColor(noteId: note.id, colorTheme: color.rawValue)

        // Update titlebar mask in JS (only if we have the webview)
        if hasWebView {
            SharedWebViewManager.shared.webView.evaluateJavaScript(
                "window.setNoteColor('\(color.rawValue)')", completionHandler: nil
            )
        }
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
        pinButton?.alphaValue = note.alwaysOnTop ? 1.0 : 0.25
    }

    private func setupContent() {
        guard let panel = window as? NSPanel else { return }

        let contentRect = panel.contentRect(forFrameRect: panel.frame)

        // Main container
        let container = NSView(frame: NSRect(origin: .zero, size: contentRect.size))
        container.autoresizingMask = [.width, .height]

        // Content container (will hold WKWebView or snapshot)
        contentContainer = NSView(frame: container.bounds)
        contentContainer.autoresizingMask = [.width, .height]
        container.addSubview(contentContainer)

        // Titlebar cursor overlay
        let titlebarOverlay = TitlebarCursorView(
            frame: NSRect(x: 0, y: contentRect.height - 28, width: contentRect.width, height: 28)
        )
        titlebarOverlay.autoresizingMask = [.width, .minYMargin]
        container.addSubview(titlebarOverlay)

        panel.contentView = container

        // Start with text preview of note content
        showTextPreview()
    }

    // MARK: - WebView Attach / Detach

    /// Attach the shared WKWebView to this window and switch editor to this note.
    /// Uses synchronous RunLoop-spin snapshot to avoid async timing gaps.
    func attachWebView() {
        guard !hasWebView else { return }

        let manager = SharedWebViewManager.shared
        let wv = manager.webView

        let oldWC: NoteWindowController? = {
            guard let id = manager.activeNoteId, id != note.id else { return nil }
            return coordinator?.windowManager.getWindowController(for: id)
        }()
        let oldHadWebView = oldWC?.hasWebView ?? false

        guard let currentNote = coordinator?.noteManager.getNote(note.id) else { return }

        // 1. Synchronous snapshot of old content (WebView still in old window)
        if oldHadWebView {
            oldWC?.hasWebView = false

            if manager.isReady {
                // A. Serialize state first (preserves cursor position before we reset it)
                var serializedState: String?
                var serializeDone = false
                wv.evaluateJavaScript("window.serializeState()") { result, _ in
                    serializedState = result as? String
                    serializeDone = true
                }
                let serializeDeadline = Date().addingTimeInterval(0.1)
                while !serializeDone && Date() < serializeDeadline {
                    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
                }
                if let json = serializedState, let oldId = manager.activeNoteId {
                    manager.cacheSerializedState(json, for: oldId)
                }

                // B. Collapse all cursor unfolds, disable transitions, and blur
                var prepareDone = false
                wv.evaluateJavaScript("window.prepareForSnapshot()") { _, _ in
                    prepareDone = true
                }
                let prepareDeadline = Date().addingTimeInterval(0.1)
                while !prepareDone && Date() < prepareDeadline {
                    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
                }

                // C. Wait for compositor (transitions disabled, just need one paint cycle)
                let renderDeadline = Date().addingTimeInterval(0.05)
                while Date() < renderDeadline {
                    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
                }

                // D. Take snapshot
                var snapshot: NSImage?
                var done = false
                wv.takeSnapshot(with: WKSnapshotConfiguration()) { image, _ in
                    snapshot = image
                    done = true
                }
                let deadline = Date().addingTimeInterval(0.1)
                while !done && Date() < deadline {
                    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
                }

                // E. Re-enable transitions
                wv.evaluateJavaScript("window.endSnapshotMode()")

                if let image = snapshot {
                    oldWC?.showSnapshot(image)
                } else {
                    oldWC?.showTextPreview()
                }
            } else {
                // Editor not ready yet — show text preview (don't serialize empty editor state)
                oldWC?.showTextPreview()
            }
        }

        // 2. Move WebView to this window (hidden behind existing preview)
        wv.alphaValue = 0
        wv.frame = contentContainer.bounds
        wv.autoresizingMask = [.width, .height]
        contentContainer.addSubview(wv)
        hasWebView = true

        // 3. Switch editor to this note's content (skip serialization — already cached above)
        manager.switchToNoteSkippingSerialization(note.id, note: currentNote)

        // 4. Reveal after content renders (skip if editor not ready — markReady handles reveal)
        if manager.isReady {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.revealWebView()
            }
        }

        print("[NoteWindowController] Attached WebView for note: \(note.id)")
    }

    /// Reveal the hidden WebView, remove preview underneath, and focus the editor.
    func revealWebView() {
        guard hasWebView else { return }
        let wv = SharedWebViewManager.shared.webView
        wv.alphaValue = 1
        removeNonWebViewSubviews()
        wv.window?.makeFirstResponder(wv)
        wv.evaluateJavaScript("window.focusEditor()")
    }

    /// Show a snapshot of the last rendered editor state (preserves markdown rendering)
    func showSnapshot(_ image: NSImage) {
        removeNonWebViewSubviews()

        let imageView = NSImageView(frame: contentContainer.bounds)
        imageView.autoresizingMask = [.width, .height]
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignTopLeft
        snapshotView = imageView
        contentContainer.addSubview(imageView)
    }

    /// Show a plain-text preview of the note content (used on first load before any snapshot exists)
    func showTextPreview() {
        removeNonWebViewSubviews()

        let content = coordinator?.noteManager.getNote(note.id)?.content ?? note.content

        // Empty note — just show note color background
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let scrollView = NSScrollView(frame: contentContainer.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 32)
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = NSColor(white: 0.1, alpha: 0.75)
        textView.string = content
        textView.textContainer?.lineFragmentPadding = 4

        scrollView.documentView = textView
        contentContainer.addSubview(scrollView)
    }

    /// Remove all subviews except the WKWebView from contentContainer
    private func removeNonWebViewSubviews() {
        for sub in contentContainer.subviews where !(sub is WKWebView) {
            sub.removeFromSuperview()
        }
        snapshotView = nil
    }

    // MARK: - NSWindowDelegate Methods

    func windowDidBecomeKey(_ notification: Notification) {
        attachWebView()
    }

    func windowDidResignKey(_ notification: Notification) {
        // Detach is handled by the NEW window's attachWebView().
        // This avoids the async timing race where detach would run
        // after the new window has already switched content.
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let coordinator = coordinator else { return true }
        if coordinator.isQuitting { return true }

        guard let current = coordinator.noteManager.getNote(note.id),
              !current.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }

        let alert = NSAlert()
        alert.messageText = "Delete this note?"
        alert.informativeText = "This note has content that will be lost."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        return alert.runModal() == .alertFirstButtonReturn
    }

    func windowWillClose(_ notification: Notification) {
        // If this window has the WebView, detach it
        if hasWebView {
            SharedWebViewManager.shared.webView.removeFromSuperview()
            hasWebView = false
        }
        coordinator?.closeNoteWindow(note.id)
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = window else { return }
        coordinator?.handleWindowStateChange(noteId: note.id, size: window.frame.size)
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = window else { return }
        coordinator?.handleWindowStateChange(noteId: note.id, position: window.frame.origin)
    }

    func windowDidMiniaturize(_ notification: Notification) {
        coordinator?.handleWindowStateChange(noteId: note.id, isMinimized: true)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        coordinator?.handleWindowStateChange(noteId: note.id, isMinimized: false)
    }

    // MARK: - Public Methods

    func setOpacity(_ opacity: Double) {
        window?.alphaValue = CGFloat(opacity)
    }

    func setColorTheme(_ theme: String) {
        note.colorTheme = theme
        window?.backgroundColor = NoteColor.from(theme).color
    }

    func setAlwaysOnTop(_ alwaysOnTop: Bool) {
        note.alwaysOnTop = alwaysOnTop
        guard let panel = window as? NSPanel else { return }

        if alwaysOnTop {
            panel.level = .popUpMenu
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isFloatingPanel = true
            panel.orderFrontRegardless()
        } else {
            panel.level = .floating
            panel.collectionBehavior = [.managed]
            panel.isFloatingPanel = false
        }

        pinButton?.alphaValue = alwaysOnTop ? 1.0 : 0.25
    }

    var noteId: UUID { note.id }

    /// Access the shared WKWebView (only valid when this window is active)
    var webView: WKWebView? {
        hasWebView ? SharedWebViewManager.shared.webView : nil
    }
}

// MARK: - Titlebar Views

private class TitlebarControlsView: NSView {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}

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
        nextResponder?.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        nextResponder?.mouseUp(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        nextResponder?.mouseDragged(with: event)
    }
}
