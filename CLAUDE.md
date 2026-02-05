# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Quick Start

### Build the Application
```bash
./build-app.sh
```
This script handles the complete build pipeline:
1. Builds the web editor (CodeMirror bundle via webpack)
2. Compiles Swift code with `swift build -c release`
3. Creates the macOS .app bundle structure at `build/StickyNotes.app`

### Run the Application
```bash
open build/StickyNotes.app
```

### Development Workflow
```bash
# Swift code changes: rebuild and relaunch
swift build -c release
open build/StickyNotes.app

# Editor changes (JavaScript/CSS): rebuild bundle only
cd editor-web && npm run build
# Then copy to app
cp editor-web/dist/editor.bundle.js build/StickyNotes.app/Contents/Resources/Editor/

# Watch mode for editor development
cd editor-web && npm run watch
```

## Architecture Overview

This is a **hybrid native + web application** for macOS:
- **Swift/SwiftUI**: App shell, window management, data persistence
- **WKWebView**: Embedded editor powered by CodeMirror 6
- **Swift-JavaScript Bridge**: Bidirectional communication via `WKScriptMessageHandler`

### Key Architectural Decisions

**Why Hybrid?**
- Pure native (NSTextView): Would require months to build WYSIWYG markdown editor
- Electron: Rejected due to resource requirements
- Hybrid: Leverages CodeMirror 6 for editing + native macOS performance

**Why StateField over ViewPlugin?**
- CodeMirror's `ViewPlugin` decorations apply after viewport calculation (can't replace multiline)
- `StateField` decorations apply before viewport calculation (supports multiline math blocks)
- This was a critical architectural fix for reliable block math rendering

### Layer Responsibilities

1. **Swift Layer** (`Sources/StickyNotes/`)
   - `AppCoordinator`: Orchestrates app lifecycle, note management, window coordination
   - `WindowManager`: Manages NSPanel instances (floating windows)
   - `PersistenceManager`: UserDefaults-based JSON storage with debouncing
   - `NoteWebView`: WKWebView wrapper with resource loading and console interception

2. **Editor Layer** (`editor-web/`)
   - CodeMirror 6 with markdown language support
   - `StateField`-based decoration system for code/math rendering
   - Inline code: `` `code` `` → `InlineCodeWidget` with monospace font
   - Inline math: `$formula$` → `MathWidget` with KaTeX rendering
   - Block math: `$$formula$$` → Block `MathWidget` (multiline support via StateField)
   - Built as single webpack bundle (no chunk splitting for WKWebView compatibility)

3. **Communication** (`Bridge/EditorBridge.swift`)
   - Messages: content changes, save requests, logs, errors
   - Console.log interceptor injected via `WKUserScript` for JavaScript debugging

### Resource Loading Flow

The app bundle structure is:
```
StickyNotes.app/
  Contents/
    MacOS/StickyNotes (executable)
    Resources/
      Editor/
        index.html
        editor.bundle.js (webpack output)
```

Critical detail: `WKWebView.loadFileURL()` requires explicit read access to Resources directory. This is handled in `NoteWebView.swift` by allowing read access to the full Resources folder (needed for KaTeX fonts).

## Current Implementation Status

**Phase 1 ✅ Complete:**
- Swift/SwiftUI app structure with AppCoordinator
- NSPanel window management (floating, draggable, resizable)
- UserDefaults persistence with debouncing
- Basic WKWebView editor

**Phase 2 ✅ In Progress:**
- CodeMirror 6 with markdown support
- StateField-based rendering (replaces buggy ViewPlugin approach)
- Math rendering: inline `$...$` and block `$$...$$`
- Code widget rendering with monospace font
- HTML resource loading and KaTeX font loading fixed

**Fixed Issues:**
- ✅ Markdown syntax highlighting now visible with `markdownHighlightStyle` (replaces `defaultHighlightStyle`)
- ✅ Headings rendered with progressive sizing and weight
- ✅ Bold, italic, links, code all styled distinctly
- ✅ Korean text in math expressions filtered to prevent KaTeX warnings

**Known Issues:**
- Markdown blockquotes styling could be improved
- Color scheme could be more Obsidian-like (current is basic)

**Next Phases:**
- Phase 3: macOS keyboard shortcuts (Cmd+Up/Down, Opt+Left/Right, etc.)
- Phase 4: Multiple simultaneous notes
- Phase 5: Preferences window, export functionality

## Important Implementation Details

### Webpack Configuration
- **Entry**: `editor-web/src/editor.js`
- **Output**: `editor-web/dist/editor.bundle.js` (single file, ~2.1MB)
- **Key setting**: Inline fonts as base64 (no separate .woff2 files) because WKWebView has strict file access
- **Chunks**: Disabled (`splitChunks: false`) to avoid chunk loading errors in WKWebView

### Markdown Highlighting System
CodeMirror applies syntax highlighting through two mechanisms:

1. **Token-based highlighting** (`markdownHighlightStyle`):
   - Uses `@lezer/highlight` tags to recognize markdown tokens
   - Applies styles to: headings (H1-H6), strong, emphasis, links, code, quotes
   - Headings scale from 2em (H1) to 0.95em (H6) with bold weight
   - Links styled in blue with underline
   - Code marked with monospace font + gray background

2. **Decoration system** (`buildDecorations()` function):
   - Handles three rendering scenarios:
     1. **Inline code**: Extracts content, wraps in `InlineCodeWidget` with inline styles (monospace, background, padding)
     2. **Block math**: Multiline regex match, extracts formula, wraps in block `MathWidget`
     3. **Inline math**: Negative lookbehind to avoid matching `$$`, wraps in inline `MathWidget`
   - All widgets have `eq()` methods for optimization - CodeMirror only re-renders when content changes

**Why both systems?**
- Markdown tokens (headings, bold, italic) render via token highlighting for broad coverage
- Custom widgets (math, code) handle complex replacements not expressible as styling

### HTML/JavaScript Bridge
- Swift sends messages to JavaScript via: `EditorBridge` → `window.webkit.messageHandlers.bridge.postMessage()`
- JavaScript sends messages to Swift via: `sendToBridge()` helper → captured by `EditorBridge`
- Console.log is intercepted and sent to Swift for debugging (visible in Xcode console)

## File Organization

```
Sources/StickyNotes/
  App/                    # Application logic
    AppCoordinator.swift  # Main coordinator
    NoteManager.swift     # Note CRUD
    WindowManager.swift   # NSPanel management
    PersistenceManager.swift
  Models/Note.swift       # Data model
  Views/NoteWindow/
    NoteWindowController.swift  # NSPanel setup
    NoteWebView.swift           # WKWebView + resource loading
  Bridge/EditorBridge.swift     # Swift-JS communication
  Resources/Editor/
    index.html            # HTML shell
    editor.bundle.js      # Built by webpack (not in source)

editor-web/
  src/
    editor.js             # Main editor with StateField
    editor-simple.js      # CSS-only version (fallback)
  webpack.config.cjs      # Production bundle config
  package.json            # Dependencies: CodeMirror 6, KaTeX, etc.
```

## Debugging Tips

1. **Swift side**: Add `print()` statements - visible in Xcode console or terminal
2. **JavaScript side**: Use `console.log()` - captured by interceptor and sent to Swift
3. **Check Swift-JS bridge**: Look at `EditorBridge.swift` to see message routing
4. **Inspect WKWebView DOM**: Open Safari > Develop > [Your Mac] > StickyNotes > index.html
5. **Test editor without app**: `cd editor-web && npm run watch` then open `src/editor.html` in browser

## Key Dependencies

- **CodeMirror 6**: Advanced editor core
- **KaTeX**: Fast LaTeX rendering (no network required)
- **markdown-it**: Markdown parsing (currently not fully integrated)
- **Webpack 5**: Bundles everything into single file with inline fonts

## Common Pitfalls

1. **Resource not found errors**: Always run `./build-app.sh` after editor changes - just updating the bundle file isn't enough
2. **KaTeX font loading fails**: Make sure `NoteWebView.swift` grants read access to full Resources directory
3. **Decorations don't apply**: Remember `StateField` is needed for multiline; ViewPlugin will fail with "line break" errors
4. **Console.log invisible**: Check Xcode console, not browser console - messages are intercepted
5. **Changes in Xcode don't persist**: Close and reopen the app from `build/StickyNotes.app`, don't run from Xcode (different resource paths)

## Testing the Editor

Quick manual test flow:
```
1. Type: # Heading → should be styled large
2. Type: **bold** → should be weighted
3. Type: `code` → should be monospace with background
4. Type: $E=mc^2$ → should render as equation
5. Type: $$\int_0^\infty e^{-x^2} dx$$ → should render as larger equation
```

If any don't work, check the browser inspector (Safari Develop menu) to see if decorations are being created.
