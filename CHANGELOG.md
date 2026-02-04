# Changelog

All notable changes to the Sticky Notes project will be documented in this file.

## [Unreleased]

### Phase 1: Foundation ✅ COMPLETED - 2024-02-04

#### Added
- **Core Application Structure**
  - SwiftUI-based macOS application with coordinator pattern
  - `AppCoordinator` for managing application state and lifecycle
  - `NoteManager` for note collection management
  - `WindowManager` for window lifecycle management
  - `PersistenceManager` for UserDefaults-based data storage

- **Data Models**
  - `Note` struct with Codable conformance
    - UUID-based identification
    - Content storage
    - Window position and size tracking
    - Opacity settings
    - Creation and modification timestamps
  - Custom Codable implementation for CGPoint and CGSize

- **Window Management**
  - `NoteWindowController` using NSPanel for floating windows
  - Always-on-top behavior (`.floating` level)
  - Draggable windows (`isMovableByWindowBackground`)
  - Resizable with minimum size constraints (200x150)
  - Transparent/semi-transparent support
  - Window state persistence (position, size, minimized state)
  - Window delegate callbacks for tracking changes

- **Editor Foundation**
  - `NoteWebView` wrapper for WKWebView
  - Basic HTML/CSS/JS editor with textarea
  - Fallback editor implementation
  - Dark mode support
  - Swift-JavaScript bridge (`EditorBridge`)
  - Bidirectional communication between Swift and JavaScript
  - Content change debouncing (300ms)
  - Auto-save functionality

- **Swift-JavaScript Bridge**
  - `EditorBridge` implementing `WKScriptMessageHandler`
  - Message types:
    - `ready`: Editor initialization complete
    - `contentChanged`: Content updates from editor
    - `requestSave`: Explicit save requests (Cmd+S)
    - `log`: JavaScript console logging
    - `error`: JavaScript error reporting

- **Keyboard Shortcuts**
  - Cmd+N: Create new note (via menu bar)
  - Cmd+S: Save note (in editor)

- **Data Persistence**
  - JSON-based storage in UserDefaults
  - Auto-save with 500ms debounce
  - Immediate save on window close
  - Corrupted data backup and recovery
  - Import/export functionality (infrastructure)

- **Build System**
  - Swift Package Manager configuration
  - Build script for creating .app bundle
  - Proper Info.plist configuration
  - Resource bundling

- **Development Tools**
  - Test script for verifying app structure
  - README with comprehensive documentation
  - .gitignore for Swift/macOS projects

- **Default Content**
  - Welcome note created on first launch
  - Markdown-formatted example content

#### Technical Details
- **Minimum macOS Version**: 12.0 (Monterey)
- **Swift Version**: 5.9+
- **Architecture**: Hybrid native (Swift/SwiftUI + WebKit)
- **Window Technology**: NSPanel (AppKit)
- **Web View**: WKWebView (WebKit)
- **State Management**: Combine framework

#### Known Limitations
- Basic textarea editor (CodeMirror integration pending)
- No markdown live preview yet
- No LaTeX math rendering yet
- Limited keyboard shortcuts
- No preferences window
- No export functionality (UI)
- Cannot delete notes via UI (only through empty note cleanup)

### Phase 2: Markdown + Math Rendering (Planned)

#### Planned Features
- CodeMirror 6 integration
- Live markdown preview with ViewPlugin
- KaTeX for LaTeX math rendering
- Syntax highlighting for code blocks
- Obsidian-inspired theming (light + dark)
- Markdown element styling (headings, lists, blockquotes, etc.)

### Phase 3: Keyboard Shortcuts (Planned)

#### Planned Features
- macOS text navigation shortcuts
  - Cmd+Up/Down: Document start/end
  - Cmd+Shift+Up/Down: Select to document start/end
  - Opt+Left/Right: Move by word
  - Opt+Shift+Left/Right: Select by word
  - Cmd+Backspace: Delete line
  - Opt+Backspace: Delete word
- Markdown formatting shortcuts
  - Cmd+B: Bold
  - Cmd+I: Italic
  - Cmd+K: Insert link
  - Cmd+Shift+C: Code block
  - Cmd+E: Inline code
- App-level shortcuts
  - Cmd+W: Close window
  - Cmd+M: Minimize
  - Cmd+,: Preferences

### Phase 4: Multi-Window & Sticky Features (Planned)

#### Planned Features
- Enhanced transparency controls
- Window positioning improvements
- Empty note deletion option
- Window cascade positioning
- Better window restoration

### Phase 5: Polish & Features (Planned)

#### Planned Features
- Preferences window
  - Theme selection (light/dark/auto)
  - Default transparency
  - Font size adjustment
  - Shortcut customization
- Menu bar enhancements
  - File, Edit, View, Help menus
- Export functionality
  - Export to .md
  - Export to HTML
  - Export to PDF
- Optional toolbar
  - Formatting buttons
  - Quick actions
- Performance optimizations
  - Viewport-only rendering
  - KaTeX caching
  - Memory leak fixes
- Error handling improvements
- Animation polish

### Phase 6: Testing & Refinement (Planned)

#### Planned Tasks
- Cross-version macOS testing (12, 13, 14)
- Edge case testing
- Performance profiling
- Memory leak detection
- Bug fixes
- Complete documentation

---

## Version History

### v0.1.0 - Phase 1 Foundation (2024-02-04)
- Initial release with basic sticky note functionality
- Native macOS app with floating windows
- Basic text editing with auto-save
- Window state persistence

---

## Format

This changelog follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format.

### Categories
- **Added**: New features
- **Changed**: Changes to existing functionality
- **Deprecated**: Soon-to-be removed features
- **Removed**: Removed features
- **Fixed**: Bug fixes
- **Security**: Security fixes
