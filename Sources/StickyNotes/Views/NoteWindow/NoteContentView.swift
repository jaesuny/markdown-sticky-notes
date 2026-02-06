import SwiftUI

/// SwiftUI wrapper for the note content
/// Note: Titlebar controls (color, opacity, pin) are in NoteWindowController.setupTitlebarAccessory()
struct NoteContentView: View {
    let note: Note
    weak var coordinator: AppCoordinator?

    var body: some View {
        NoteWebViewRepresentable(note: note, coordinator: coordinator)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .top)
            .background(Color.clear)
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
