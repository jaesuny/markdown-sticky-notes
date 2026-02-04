# Sticky Notes - macOS Markdown Editor

A native macOS sticky note application with Obsidian-style markdown live preview, built with Swift/SwiftUI and WebKit.

## Overview

This project implements a lightweight, resource-efficient alternative to Electron-based markdown editors, using native macOS technologies for optimal performance.

## Features Implemented (Phase 1 - Foundation)

✅ **Core Architecture**
- Swift/SwiftUI app structure with coordinator pattern
- Native macOS window management using NSPanel
- Data persistence with UserDefaults
- Automatic note saving with debouncing

✅ **Window Management**
- Floating windows (always-on-top)
- Draggable window positioning
- Resizable windows with minimum size constraints
- Window state persistence (position, size, opacity)
- Minimize/restore functionality

✅ **Editor Foundation**
- WKWebView-based editor
- Swift-JavaScript bridge for bidirectional communication
- Basic text editing with textarea fallback
- Content synchronization with 300ms debounce
- Keyboard shortcut support (Cmd+S to save)

✅ **Data Models**
- `Note`: Codable struct with UUID, content, position, size, opacity, timestamps
- `PersistenceManager`: JSON-based storage with backup/recovery
- `NoteManager`: Note collection management with CRUD operations

## Project Structure

```
claude-sticky-md/
├── Package.swift                           # Swift Package Manager configuration
├── build-app.sh                             # Script to build .app bundle
├── Sources/StickyNotes/
│   ├── StickyNotesApp.swift                # App entry point
│   ├── App/
│   │   ├── AppCoordinator.swift            # Main application coordinator
│   │   ├── NoteManager.swift               # Note collection management
│   │   ├── WindowManager.swift             # Window lifecycle management
│   │   └── PersistenceManager.swift        # Data persistence
│   ├── Models/
│   │   └── Note.swift                      # Note data model
│   ├── Views/
│   │   └── NoteWindow/
│   │       ├── NoteWindowController.swift  # NSWindowController for notes
│   │       ├── NoteContentView.swift       # SwiftUI content view
│   │       └── NoteWebView.swift           # WKWebView wrapper
│   ├── Bridge/
│   │   └── EditorBridge.swift              # Swift-JavaScript bridge
│   └── Resources/
│       └── Editor/
│           └── index.html                   # Editor HTML/JS/CSS
└── build/
    └── StickyNotes.app                     # Built application bundle
```

## Building and Running

### Build the App

```bash
./build-app.sh
```

This creates a `build/StickyNotes.app` bundle.

### Run the App

```bash
open build/StickyNotes.app
```

Or double-click `StickyNotes.app` in Finder.

### Development Build

```bash
swift build           # Debug build
swift build -c release  # Release build
swift run StickyNotes   # Run directly (command-line mode)
```

### Open in Xcode

```bash
open Package.swift
```

This opens the project in Xcode for development and debugging.

## How It Works

### Architecture

1. **App Coordinator Pattern**
   - `AppCoordinator` manages the entire application lifecycle
   - Coordinates between `NoteManager` and `WindowManager`
   - Handles all note and window operations

2. **Window Management**
   - Each note gets its own `NSPanel` (floating window)
   - Panels are configured with `.floating` level for always-on-top behavior
   - `isMovableByWindowBackground` enables drag-to-move
   - Window delegates track position/size changes for persistence

3. **Swift-JavaScript Bridge**
   - WKWebView hosts the HTML editor
   - `EditorBridge` implements `WKScriptMessageHandler`
   - Messages flow bidirectionally:
     - **JS → Swift**: Content changes, save requests, logs
     - **Swift → JS**: Content updates, commands

4. **Data Persistence**
   - Notes stored as JSON in UserDefaults
   - Auto-save with 500ms debounce to reduce I/O
   - Immediate save on window close
   - Corrupted data backup and recovery

### Key Technologies

- **Swift 5.9+**: Modern Swift with concurrency support
- **SwiftUI**: Declarative UI framework
- **AppKit**: Native macOS windowing (NSPanel, NSWindow)
- **WebKit**: WKWebView for web content rendering
- **Combine**: Reactive programming for state management

## Next Steps (Future Phases)

### Phase 2: Markdown + Math Rendering
- Integrate CodeMirror 6 for advanced editing
- Implement live markdown preview
- Add KaTeX for LaTeX math rendering
- Syntax highlighting for code blocks
- Obsidian-inspired theme

### Phase 3: Keyboard Shortcuts
- macOS text navigation (Cmd+Up/Down, Opt+Left/Right)
- Markdown formatting shortcuts (Cmd+B, Cmd+I, Cmd+K)
- Custom keymap integration

### Phase 4: Multi-Window & Sticky Features
- Multiple simultaneous notes
- Enhanced transparency control
- Window positioning improvements
- Delete empty notes option

### Phase 5: Polish & Features
- Preferences window
- Export functionality (MD, HTML, PDF)
- Optional toolbar
- Performance optimization
- Error handling improvements

### Phase 6: Testing & Refinement
- Cross-version macOS testing
- Performance profiling
- Bug fixes
- Documentation completion

## Technical Decisions

### Why Hybrid (Swift + WebKit)?

- **Pure Native Rejected**: Building a WYSIWYG markdown editor in NSTextView/TextKit would require months of work
- **Electron Rejected**: Too resource-heavy (requirement)
- **Hybrid Chosen**: Leverages battle-tested web markdown editors (CodeMirror 6) while maintaining native macOS performance and window management
- **WebKit Native**: WKWebView is built into macOS, zero external dependencies

### Why SwiftUI + AppKit?

- **SwiftUI**: Modern declarative UI, excellent for app structure
- **AppKit**: Required for advanced window management (NSPanel, always-on-top, floating windows)
- **Best of Both**: Use SwiftUI where possible, drop to AppKit when needed

## Development

### Requirements

- macOS 12.0+ (Monterey or later)
- Xcode 15.0+
- Swift 5.9+

### File Organization

- **App/**: Core application logic and coordinators
- **Models/**: Data models and structures
- **Views/**: UI components and window controllers
- **Bridge/**: Swift-JavaScript communication
- **Resources/**: HTML, CSS, JS, and other assets
- **Utilities/**: Helper functions and extensions (future)

### Debugging

1. Build with `swift build` to check for compilation errors
2. Run with `swift run` to see console output
3. Open in Xcode (`open Package.swift`) for full debugging with breakpoints
4. Check logs with `print()` statements in Swift
5. Use `console.log()` in JavaScript (sent to Swift via bridge)

## Current Limitations

1. **Editor**: Currently using basic textarea, not CodeMirror yet
2. **Markdown**: No live preview yet (Phase 2)
3. **Math**: No LaTeX rendering yet (Phase 2)
4. **Shortcuts**: Limited keyboard shortcuts (Phase 3)
5. **UI**: Minimal styling, no preferences window (Phase 5)

## Contributing

This is a personal project, but suggestions and bug reports are welcome.

## License

TBD

## Credits

- Built with Claude Sonnet 4.5
- Inspired by Obsidian and marktext/muya
- macOS and Swift are trademarks of Apple Inc.
