# MD Sticky Notes

A native macOS sticky note app with Obsidian-style markdown live preview, built with Swift and CodeMirror 6.

![macOS 12+](https://img.shields.io/badge/macOS-12%2B-blue)
![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange)

## Features

### Markdown Editor
- **Live Preview**: Obsidian-style WYSIWYG editing with instant rendering
- **GFM Support**: Tables, strikethrough, task lists, and more
- **Syntax Highlighting**: 15+ programming languages in code blocks
- **Math Rendering**: KaTeX support for inline (`$...$`) and block (`$$...$$`) equations

### Sticky Note Experience
- **Floating Windows**: Always visible while you work
- **Pin on Top**: Keep important notes above all windows (Cmd+Shift+P)
- **Multiple Colors**: Yellow, pink, blue, green, purple, orange
- **Adjustable Opacity**: Transparency slider for each note
- **Auto-Save**: Never lose your notes

### Keyboard Shortcuts
| Shortcut | Action |
|----------|--------|
| Cmd+N | New note |
| Cmd+Shift+P | Pin on top |
| Cmd+B / I / K | Bold / Italic / Link |
| Cmd+F | Find in note |
| Cmd+Shift+F | Find and replace |
| Cmd+` | Cycle through notes |

## Installation

### Download
Download the latest release from the [Releases](https://github.com/your-repo/releases) page.

### Build from Source
```bash
# Prerequisites: macOS 12+, Swift 5.9+, Node.js 18+

# Clone and build
git clone https://github.com/your-repo/claude-sticky-md.git
cd claude-sticky-md
cd editor-web && npm install && cd ..
./build-app.sh

# Run
open build/StickyNotes.app
```

## Screenshots

*Coming soon*

## Technical Details

### Architecture
- **Swift/SwiftUI**: Native macOS app shell with NSPanel windows
- **WKWebView + CodeMirror 6**: High-performance markdown editor
- **KaTeX**: Fast LaTeX math rendering
- **Hybrid Approach**: Native performance with battle-tested web editor

### Why Hybrid?
- Pure native markdown editors require months of TextKit work
- Electron is too resource-heavy
- WKWebView is built into macOS with zero external dependencies
- CodeMirror 6 is the most advanced web editor available

## Development

```bash
# Full rebuild (Swift + JS)
./build-app.sh && open build/StickyNotes.app

# JS-only fast iteration
cd editor-web && npm run build && \
  cp dist/editor.bundle.js ../build/StickyNotes.app/Contents/Resources/Editor/ && \
  open ../build/StickyNotes.app
```

## License

MIT

## Credits

- Built with [Claude Code](https://claude.ai/code)
- Editor powered by [CodeMirror 6](https://codemirror.net/)
- Math rendering by [KaTeX](https://katex.org/)
