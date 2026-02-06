import SwiftUI

/// SwiftUI wrapper for the note content with titlebar controls
struct NoteContentView: View {
    let note: Note
    weak var coordinator: AppCoordinator?
    @State private var opacity: Double
    @State private var currentColor: String

    init(note: Note, coordinator: AppCoordinator?) {
        self.note = note
        self.coordinator = coordinator
        self._opacity = State(initialValue: note.opacity)
        self._currentColor = State(initialValue: note.colorTheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Titlebar toolbar — color dots + opacity slider
            titlebarToolbar

            // Web view containing the editor
            NoteWebViewRepresentable(note: note, coordinator: coordinator)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.clear)
    }

    // MARK: - Titlebar Toolbar

    private var titlebarToolbar: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 68)

            // Opacity slider
            Slider(value: $opacity, in: 0.25...1.0)
                .controlSize(.mini)
                .frame(width: 60)
                .onChange(of: opacity) { newValue in
                    coordinator?.setNoteOpacity(noteId: note.id, opacity: newValue)
                }

            Spacer().frame(width: 8)

            // Color picker — rounded squares, right-aligned
            HStack(spacing: 4) {
                ForEach(NoteColor.allCases, id: \.self) { color in
                    colorSwatch(for: color)
                }
            }

            Spacer().frame(width: 8)
        }
        .frame(height: 28)
    }

    private func colorSwatch(for color: NoteColor) -> some View {
        let isSelected = color.rawValue == currentColor
        return RoundedRectangle(cornerRadius: 3)
            .fill(Color(nsColor: color.color))
            .frame(width: 14, height: 14)
            .overlay(
                RoundedRectangle(cornerRadius: 3).strokeBorder(
                    isSelected ? Color.primary.opacity(0.5) : Color.primary.opacity(0.12),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
            )
            .onTapGesture {
                currentColor = color.rawValue
                coordinator?.changeNoteColor(noteId: note.id, colorTheme: color.rawValue)
            }
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
