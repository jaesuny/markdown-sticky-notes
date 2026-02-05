# Changelog

All notable changes to the Sticky Notes project will be documented in this file.

## [Unreleased]

### Phase 2: Markdown + Math Rendering ✅ COMPLETED - 2024-02-04

#### Added
- **CodeMirror 6 Integration**
  - Upgraded from basic textarea to CodeMirror 6 professional editor
  - Full ES6 module support with Webpack bundling
  - Editor bundle size: ~809KB (including KaTeX fonts)

- **Markdown Support**
  - Real-time markdown syntax highlighting
  - `@codemirror/lang-markdown` for markdown language support
  - `@codemirror/language-data` for multi-language code block support
  - Syntax highlighting for code blocks (JavaScript, Python, etc.)
  - defaultHighlightStyle for consistent code highlighting

- **Math Rendering (KaTeX)**
  - KaTeX 0.16.x integration for LaTeX math rendering
  - Inline math: `$...$` notation
  - Block math: `$$...$$` notation
  - Custom ViewPlugin for real-time math rendering
  - Math error handling with visual feedback
  - Custom math styling (inline and block)

- **Keyboard Shortcuts - macOS Text Navigation**
  - Cmd+Up/Down: Move to document start/end
  - Cmd+Shift+Up/Down: Select to document start/end
  - (Opt+Left/Right: Planned for Phase 3)

- **Keyboard Shortcuts - Markdown Formatting**
  - Cmd+B: Bold text (`**text**`)
  - Cmd+I: Italic text (`*text*`)
  - Cmd+K: Insert link (`[text](url)`)
  - Cmd+E: Inline code (`` `code` ``)
  - Cmd+S: Save note

- **Obsidian-Inspired Theme**
  - Custom editor theme with Obsidian-style aesthetics
  - Automatic dark mode detection
  - Light and dark theme support
  - Purple accent color (#5c6ac4 / #8c9eff)
  - Transparent background integration
  - Custom styling for:
    - Headings (H1-H6 with appropriate sizes)
    - Bold and italic text
    - Inline code blocks
    - Math expressions (inline and block)

- **Build System**
  - Webpack 5 configuration for editor bundling
  - Automatic editor rebuild in build-app.sh
  - npm scripts for build and watch mode
  - CSS-loader and style-loader for CSS bundling

- **Editor Features**
  - Line wrapping for better readability
  - Custom cursor color matching theme
  - Proper focus handling
  - 300ms debounce for content changes
  - Swift-JavaScript bridge integration maintained

#### Technical Details
- **JavaScript Dependencies**:
  - @codemirror/state: ^6.5.4
  - @codemirror/view: ^6.39.12
  - @codemirror/commands: ^6.10.1
  - @codemirror/lang-markdown: ^6.5.0
  - @codemirror/language: ^6.12.1
  - @codemirror/language-data: ^6.5.2
  - katex: ^0.16.28

- **Build Tools**:
  - webpack: ^5.105.0
  - webpack-cli: ^6.0.1
  - css-loader: ^7.1.3
  - style-loader: ^4.0.0

- **Project Structure**:
  - `editor-web/`: Web editor source and build
  - `editor-web/src/editor.js`: Main editor implementation
  - `editor-web/dist/editor.bundle.js`: Built bundle
  - Automatic copy to `Sources/StickyNotes/Resources/Editor/`

#### Testing
- Created `MARKDOWN_TEST.md` with comprehensive test cases
- Tested all heading levels (H1-H6)
- Tested text formatting (bold, italic, combination)
- Tested lists (ordered, unordered, nested)
- Tested links and images
- Tested inline and block code
- Tested inline and block math equations
- Tested blockquotes, tables, horizontal rules

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

---

## Version History

### v0.2.0 - Phase 2 Complete (2024-02-04)
- Added CodeMirror 6 professional editor
- Added KaTeX math rendering
- Added markdown syntax highlighting
- Added macOS keyboard shortcuts
- Added Obsidian-inspired theme
- Improved editor experience significantly

### v0.1.0 - Phase 1 Foundation (2024-02-04)
- Initial release with basic sticky note functionality
- Native macOS app with floating windows
- Basic text editing with auto-save
- Window state persistence

---

## Planned Features

### Phase 3: Enhanced Keyboard Shortcuts (Next)
- Additional macOS text navigation (Opt+Left/Right, etc.)
- More markdown formatting shortcuts
- App-level shortcut improvements
- Keyboard shortcut customization

### Phase 4: Multi-Window & Polish
- Enhanced window management
- Improved transparency controls
- Better window positioning
- UI refinements

### Phase 5: Advanced Features
- Preferences window
- Export functionality (MD, HTML, PDF)
- Optional toolbar
- Performance optimizations

### Phase 6: Testing & Release
- Comprehensive testing
- Bug fixes
- Documentation completion
- Public release preparation

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
