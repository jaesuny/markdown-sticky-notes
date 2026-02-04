import AppKit
import WebKit

/// WKWebView subclass for displaying and editing note content
class NoteWebView: WKWebView {
    // MARK: - Properties

    private let note: Note
    private weak var coordinator: AppCoordinator?
    private var bridge: EditorBridge?

    // MARK: - Initialization

    init(note: Note, coordinator: AppCoordinator?) {
        self.note = note
        self.coordinator = coordinator

        // Configure WKWebView
        let configuration = WKWebViewConfiguration()
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        // Set up user content controller for JavaScript bridge
        let userContentController = WKUserContentController()
        configuration.userContentController = userContentController

        super.init(frame: .zero, configuration: configuration)

        // Set up bridge
        self.bridge = EditorBridge(noteId: note.id, coordinator: coordinator)
        userContentController.add(bridge!, name: "bridge")

        // Configure web view appearance
        setValue(false, forKey: "drawsBackground")

        // Load the editor HTML
        loadEditor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Editor Loading

    private func loadEditor() {
        guard let htmlURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Resources/Editor") else {
            print("[NoteWebView] Error: Could not find index.html")
            loadFallbackEditor()
            return
        }

        loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        print("[NoteWebView] Loading editor from: \(htmlURL.path)")
    }

    /// Load a fallback inline editor if the HTML file is not found
    private func loadFallbackEditor() {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                * {
                    margin: 0;
                    padding: 0;
                    box-sizing: border-box;
                }

                html, body {
                    width: 100%;
                    height: 100%;
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
                    font-size: 14px;
                    background: transparent;
                }

                #editor {
                    width: 100%;
                    height: 100%;
                    padding: 16px;
                    border: none;
                    outline: none;
                    resize: none;
                    background: rgba(255, 255, 255, 0.95);
                    color: #333;
                    line-height: 1.6;
                }

                #editor:focus {
                    outline: none;
                }

                @media (prefers-color-scheme: dark) {
                    #editor {
                        background: rgba(30, 30, 30, 0.95);
                        color: #e0e0e0;
                    }
                }
            </style>
        </head>
        <body>
            <textarea id="editor" placeholder="Start typing..."></textarea>
            <script>
                const editor = document.getElementById('editor');

                // Set initial content
                editor.value = `\(note.content.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "`", with: "\\`"))`;

                // Send content changes to Swift
                let debounceTimer;
                editor.addEventListener('input', () => {
                    clearTimeout(debounceTimer);
                    debounceTimer = setTimeout(() => {
                        window.webkit.messageHandlers.bridge.postMessage({
                            action: 'contentChanged',
                            content: editor.value
                        });
                    }, 300);
                });

                // Notify Swift that editor is ready
                window.webkit.messageHandlers.bridge.postMessage({
                    action: 'ready'
                });

                // Expose setContent method for Swift
                window.setContent = function(content) {
                    editor.value = content;
                };
            </script>
        </body>
        </html>
        """

        loadHTMLString(html, baseURL: nil)
        print("[NoteWebView] Loaded fallback editor")
    }

    // MARK: - Public Methods

    /// Set editor content from Swift
    /// - Parameter content: The content to set
    func setContent(_ content: String) {
        let escapedContent = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")

        let javascript = "window.setContent && window.setContent(\"\(escapedContent)\");"
        evaluateJavaScript(javascript) { result, error in
            if let error = error {
                print("[NoteWebView] Error setting content: \(error)")
            }
        }
    }

    /// Get current editor content
    /// - Parameter completion: Callback with the content
    func getContent(completion: @escaping (String?) -> Void) {
        let javascript = "document.getElementById('editor')?.value || editor?.state?.doc?.toString() || '';"
        evaluateJavaScript(javascript) { result, error in
            if let error = error {
                print("[NoteWebView] Error getting content: \(error)")
                completion(nil)
                return
            }

            completion(result as? String)
        }
    }
}
