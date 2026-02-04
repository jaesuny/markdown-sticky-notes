import Foundation
import WebKit

/// Bridge between Swift and JavaScript editor
class EditorBridge: NSObject, WKScriptMessageHandler {
    // MARK: - Properties

    private let noteId: UUID
    private weak var coordinator: AppCoordinator?

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

        // Could send initial configuration here
        // For example: theme, font size, etc.
    }

    private func handleContentChange(_ content: String) {
        // Notify coordinator of content change
        coordinator?.handleContentChange(noteId: noteId, content: content)
    }

    private func handleSaveRequest() {
        // Handle explicit save request from editor
        if let note = coordinator?.noteManager.getNote(noteId) {
            coordinator?.noteManager.saveNoteImmediately(note)
        }
    }
}
