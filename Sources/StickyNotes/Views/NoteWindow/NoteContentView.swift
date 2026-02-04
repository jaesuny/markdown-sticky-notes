import SwiftUI

/// SwiftUI wrapper for the note content
struct NoteContentView: View {
    let note: Note
    weak var coordinator: AppCoordinator?

    var body: some View {
        VStack(spacing: 0) {
            // Web view containing the editor
            NoteWebViewRepresentable(note: note, coordinator: coordinator)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// SwiftUI representable for NoteWebView
struct NoteWebViewRepresentable: NSViewRepresentable {
    let note: Note
    weak var coordinator: AppCoordinator?

    func makeNSView(context: Context) -> NoteWebView {
        let webView = NoteWebView(note: note, coordinator: coordinator)
        return webView
    }

    func updateNSView(_ nsView: NoteWebView, context: Context) {
        // Update if needed
    }
}
