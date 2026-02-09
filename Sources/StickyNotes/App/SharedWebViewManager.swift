import AppKit
import WebKit

/// Singleton that owns the single WKWebView shared across all note windows.
/// Active window gets the live WKWebView; inactive windows show snapshots.
class SharedWebViewManager {
    static let shared = SharedWebViewManager()

    // MARK: - Properties

    /// The single shared WKWebView
    let webView: WKWebView

    /// The bridge handling JS→Swift messages
    let bridge: SharedEditorBridge

    /// Currently active note ID (the note being edited)
    private(set) var activeNoteId: UUID?

    /// Cached serialized EditorState per note (JSON string from serializeState)
    private var stateCache: [UUID: String] = [:]

    /// Whether the editor JS has finished loading
    private(set) var isReady = false

    /// Coordinator reference for bridge callbacks
    weak var coordinator: AppCoordinator?

    // MARK: - Initialization

    private init() {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let userContentController = WKUserContentController()
        configuration.userContentController = userContentController

        // Inject console.log interceptor
        let consoleScript = WKUserScript(
            source: """
            (function() {
                var originalLog = console.log;
                console.log = function() {
                    var message = Array.prototype.slice.call(arguments).join(' ');
                    window.webkit.messageHandlers.bridge.postMessage({
                        action: 'log',
                        message: message
                    });
                    originalLog.apply(console, arguments);
                };
                var originalError = console.error;
                console.error = function() {
                    var message = Array.prototype.slice.call(arguments).join(' ');
                    window.webkit.messageHandlers.bridge.postMessage({
                        action: 'error',
                        message: 'ERROR: ' + message
                    });
                    originalError.apply(console, arguments);
                };
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(consoleScript)

        // Create bridge and register
        let bridge = SharedEditorBridge()
        userContentController.add(bridge, name: "bridge")
        self.bridge = bridge

        // Create the single WKWebView
        let wv = WKWebView(frame: .zero, configuration: configuration)
        wv.setValue(false, forKey: "drawsBackground")
        self.webView = wv

        // Load the editor HTML
        loadEditor()
    }

    // MARK: - Editor Loading

    private func loadEditor() {
        let bundleURL = Bundle.main.bundleURL
        let htmlURL = bundleURL.appendingPathComponent("Contents/Resources/Editor/index.html")

        guard FileManager.default.fileExists(atPath: htmlURL.path) else {
            print("[SharedWebViewManager] Error: Could not find index.html at \(htmlURL.path)")
            return
        }

        let resourcesDir = bundleURL.appendingPathComponent("Contents/Resources")
        webView.loadFileURL(htmlURL, allowingReadAccessTo: resourcesDir)
        print("[SharedWebViewManager] Loading editor from: \(htmlURL.path)")
    }

    // MARK: - Note Switching

    /// Called by the bridge when JS editor signals "ready".
    /// Pre-renders all inactive notes (WebView is still alpha=0) then loads the active note.
    func markReady() {
        isReady = true
        print("[SharedWebViewManager] Editor is ready")

        // Pre-render inactive notes while WebView is still hidden (alpha=0)
        preRenderInactiveNotes { [weak self] in
            guard let self = self else { return }

            // Load the active note
            if let noteId = self.activeNoteId,
               let note = self.coordinator?.noteManager.getNote(noteId) {
                self.loadNoteContent(noteId, note: note)
            }

            // Reveal WebView in the active window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self = self,
                      let noteId = self.activeNoteId,
                      let wc = self.coordinator?.windowManager.getWindowController(for: noteId) else { return }
                wc.revealWebView()
            }
        }
    }

    // MARK: - Pre-rendering

    /// Render each inactive note in the hidden WebView, take a snapshot, and show it on its window.
    private func preRenderInactiveNotes(completion: @escaping () -> Void) {
        guard let coordinator = coordinator else {
            completion()
            return
        }

        let otherNotes = coordinator.noteManager.notes
            .filter { $0.id != activeNoteId }
            .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !otherNotes.isEmpty else {
            completion()
            return
        }

        preRenderNext(notes: otherNotes, index: 0, completion: completion)
    }

    /// Recursively pre-render one note at a time: setContent → wait → snapshot → next.
    private func preRenderNext(notes: [Note], index: Int, completion: @escaping () -> Void) {
        guard index < notes.count else {
            completion()
            return
        }

        let note = notes[index]

        // Set content + enter snapshot mode in one JS call (single transaction, single DOM update).
        // suppressContentChange in JS prevents the contentChanged debounce from firing
        // and corrupting the active note's content in NoteManager.
        webView.callAsyncJavaScript(
            """
            window.setContentForSnapshot(content);
            await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
            """,
            arguments: ["content": note.content],
            in: nil,
            in: .page
        ) { [weak self] _ in
            guard let self = self else { return }

            // Double-rAF completed — compositor has painted, safe to snapshot
            self.webView.takeSnapshot(with: WKSnapshotConfiguration()) { [weak self] image, _ in
                guard let self = self else { return }

                self.webView.evaluateJavaScript("window.endSnapshotMode()")

                if let image = image {
                    self.coordinator?.windowManager.getWindowController(for: note.id)?.showSnapshot(image)
                }

                // Continue to next note
                self.preRenderNext(notes: notes, index: index + 1, completion: completion)
            }
        }
    }

    /// Switch the editor to a different note.
    /// Serializes current note state, then loads the target note.
    func switchToNote(_ noteId: UUID, note: Note) {
        guard isReady else {
            // Editor not ready yet — markReady() will call loadNoteContent
            activeNoteId = noteId
            return
        }

        // If already showing this note, nothing to do
        if activeNoteId == noteId { return }

        // 1. Serialize current note state (if any).
        //    JS evaluations are queued in order, so serializeState() executes
        //    BEFORE setContent/restoreState below, capturing the OLD content.
        if let currentId = activeNoteId {
            webView.evaluateJavaScript("window.serializeState()") { [weak self] result, _ in
                guard let self = self, let json = result as? String else { return }
                self.cacheSerializedState(json, for: currentId)
            }
        }

        // 2. Set the new note ID and load content
        activeNoteId = noteId
        loadNoteContent(noteId, note: note)
    }

    /// Load note content into the editor (shared by switchToNote and markReady)
    private func loadNoteContent(_ noteId: UUID, note: Note) {
        // Set noteId in JS
        let idString = noteId.uuidString
        webView.evaluateJavaScript("window.setCurrentNoteId('\(idString)')")

        // Restore cached state or load fresh content
        if let cached = stateCache[noteId] {
            // Use callAsyncJavaScript to pass JSON directly — avoids fragile string escaping
            webView.callAsyncJavaScript(
                "window.restoreState(state)",
                arguments: ["state": cached],
                in: nil,
                in: .page,
                completionHandler: nil
            )
        } else {
            // First time — load from Note model via callAsyncJavaScript
            webView.callAsyncJavaScript(
                "window.setContent(content)",
                arguments: ["content": note.content],
                in: nil,
                in: .page,
                completionHandler: nil
            )

            // Restore cursor position
            if note.cursorPosition > 0 {
                webView.evaluateJavaScript("window.setCursorPosition(\(note.cursorPosition))")
            }

            // Restore scroll position
            if note.scrollTop > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.webView.evaluateJavaScript("window.setScrollTop(\(note.scrollTop))")
                }
            }
        }

        // Initialize note controls (titlebar mask color)
        webView.evaluateJavaScript("window.initNoteControls('\(note.colorTheme)', \(note.opacity), \(note.alwaysOnTop))")

        print("[SharedWebViewManager] Loaded note: \(noteId)")
    }

    /// Cache a serialized editor state for a note (called from attachWebView before cursor reset).
    /// Extracts doc, cursor position, and scroll top to persist in NoteManager.
    func cacheSerializedState(_ json: String, for noteId: UUID) {
        stateCache[noteId] = json
        if let data = json.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let doc = obj["doc"] as? String {
                coordinator?.handleContentChange(noteId: noteId, content: doc)
            }
            if let anchor = obj["anchor"] as? Int {
                coordinator?.noteManager.updateNoteCursorPosition(noteId, cursorPosition: anchor)
            }
            if let scrollTop = obj["scrollTop"] as? Double {
                coordinator?.noteManager.updateNoteScrollTop(noteId, scrollTop: scrollTop)
            }
        }
    }

    /// Switch to a note without re-serializing the old note (state was already cached externally).
    func switchToNoteSkippingSerialization(_ noteId: UUID, note: Note) {
        guard isReady else {
            activeNoteId = noteId
            return
        }
        activeNoteId = noteId
        loadNoteContent(noteId, note: note)
    }

    /// Flush current note's content/cursor/scroll to NoteManager (for app termination)
    func flushCurrentNoteState() {
        guard let currentId = activeNoteId else { return }

        var pending = 3

        webView.evaluateJavaScript("window.getContent()") { [weak self] result, _ in
            if let content = result as? String {
                self?.coordinator?.noteManager.updateNoteContent(currentId, content: content)
            }
            pending -= 1
        }

        webView.evaluateJavaScript("window.getCursorPosition()") { [weak self] result, _ in
            if let position = result as? Int {
                self?.coordinator?.noteManager.updateNoteCursorPosition(currentId, cursorPosition: position)
            }
            pending -= 1
        }

        webView.evaluateJavaScript("window.getScrollTop()") { [weak self] result, _ in
            if let scrollTop = result as? Double {
                self?.coordinator?.noteManager.updateNoteScrollTop(currentId, scrollTop: scrollTop)
            }
            pending -= 1
        }

        // Spin RunLoop to let async JS callbacks complete (max 0.5s)
        let deadline = Date().addingTimeInterval(0.5)
        while pending > 0 && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    /// Remove cached state for a deleted note
    func removeCachedState(for noteId: UUID) {
        stateCache.removeValue(forKey: noteId)
        if activeNoteId == noteId {
            activeNoteId = nil
        }
    }

}
