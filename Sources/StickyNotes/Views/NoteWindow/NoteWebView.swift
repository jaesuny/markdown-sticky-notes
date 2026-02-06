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
        bridge!.webView = self
        userContentController.add(bridge!, name: "bridge")

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
        // For .app bundle, resources are in Contents/Resources/
        let bundleURL = Bundle.main.bundleURL
        let htmlURL = bundleURL.appendingPathComponent("Contents/Resources/Editor/index.html")

        print("[NoteWebView] Bundle path: \(Bundle.main.bundlePath)")
        print("[NoteWebView] Looking for: \(htmlURL.path)")
        print("[NoteWebView] File exists: \(FileManager.default.fileExists(atPath: htmlURL.path))")

        guard FileManager.default.fileExists(atPath: htmlURL.path) else {
            print("[NoteWebView] Error: Could not find index.html at \(htmlURL.path)")
            loadFallbackEditor()
            return
        }

        // Allow read access to entire Resources directory so KaTeX fonts can load
        let resourcesDir = bundleURL.appendingPathComponent("Contents/Resources")
        loadFileURL(htmlURL, allowingReadAccessTo: resourcesDir)
        print("[NoteWebView] ✅ Loading editor from: \(htmlURL.path)")
        print("[NoteWebView] ✅ Read access granted to: \(resourcesDir.path)")
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

    // MARK: - Cursor Override for Titlebar Area

    private var titlebarTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        // Remove old tracking area
        if let existing = titlebarTrackingArea {
            removeTrackingArea(existing)
        }

        // Add tracking area for titlebar region (top 28px)
        let titlebarRect = NSRect(x: 0, y: bounds.height - 28, width: bounds.width, height: 28)
        titlebarTrackingArea = NSTrackingArea(
            rect: titlebarRect,
            options: [.cursorUpdate, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: ["isTitlebar": true]
        )
        addTrackingArea(titlebarTrackingArea!)
    }

    override func cursorUpdate(with event: NSEvent) {
        // Check if we're in titlebar area
        let localPoint = convert(event.locationInWindow, from: nil)
        if localPoint.y > bounds.height - 28 {
            NSCursor.arrow.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }
}
