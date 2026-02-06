import Foundation
import WebKit

/// Bridge between Swift and JavaScript editor
class EditorBridge: NSObject, WKScriptMessageHandler {
    // MARK: - Properties

    private let noteId: UUID
    private weak var coordinator: AppCoordinator?
    weak var webView: WKWebView?

    // MARK: - Initialization

    init(noteId: UUID, coordinator: AppCoordinator?) {
        self.noteId = noteId
        self.coordinator = coordinator
        super.init()
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else {
            print("[EditorBridge] Invalid message format")
            return
        }

        handleAction(action, body: body)
    }

    // MARK: - Action Handling

    private func handleAction(_ action: String, body: [String: Any]) {
        switch action {
        case "ready":
            handleEditorReady()

        case "contentChanged":
            if let content = body["content"] as? String {
                handleContentChange(content)
            }

        case "changeColor":
            if let color = body["color"] as? String {
                coordinator?.changeNoteColor(noteId: noteId, colorTheme: color)
            }

        case "changeOpacity":
            if let opacity = body["opacity"] as? Double {
                coordinator?.setNoteOpacity(noteId: noteId, opacity: opacity)
            }

        case "requestSave":
            handleSaveRequest()

        case "log":
            if let message = body["message"] as? String {
                print("[EditorBridge][JS] \(message)")
            }

        case "error":
            if let errorMessage = body["message"] as? String {
                print("[EditorBridge][JS Error] \(errorMessage)")
            }

        default:
            print("[EditorBridge] Unknown action: \(action)")
        }
    }

    // MARK: - Handler Methods

    private func handleEditorReady() {
        print("[EditorBridge] Editor ready for note: \(noteId)")

        guard let note = coordinator?.noteManager.getNote(noteId) else { return }

        // Load initial content
        let escaped = note.content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        webView?.evaluateJavaScript("window.setContent('\(escaped)')")

        // Initialize note controls (color picker + opacity slider)
        webView?.evaluateJavaScript("window.initColorPicker('\(note.colorTheme)', \(note.opacity))")
    }

    private func handleContentChange(_ content: String) {
        coordinator?.handleContentChange(noteId: noteId, content: content)
    }

    private func handleSaveRequest() {
        if let note = coordinator?.noteManager.getNote(noteId) {
            coordinator?.noteManager.saveNoteImmediately(note)
        }
    }
}
