# Changelog

All notable changes to MD Sticky Notes will be documented in this file.

## [1.0.0] - 2025-02-07

### Initial Release

#### Markdown Editor
- CodeMirror 6 professional editor with Obsidian-style live preview
- GFM (GitHub Flavored Markdown) support
  - Tables with proper alignment
  - Strikethrough (`~~text~~`)
  - Task lists (`- [ ]` / `- [x]`)
- Syntax highlighting for 15+ languages (JavaScript, Python, Swift, Go, Rust, etc.)
- KaTeX math rendering
  - Inline math: `$E = mc^2$`
  - Block math: `$$\int_0^\infty e^{-x^2} dx$$`
- Cursor unfold pattern (Obsidian-style): edit source when cursor is inside

#### Sticky Note Features
- Floating NSPanel windows that stay visible
- Pin on Top mode (Cmd+Shift+P) for always-on-top
- 6 pastel color themes: yellow, pink, blue, green, purple, orange
- Adjustable opacity with titlebar slider
- Auto-save with debouncing
- Window state persistence (position, size, opacity, color)
- Cursor and scroll position restoration

#### Keyboard Shortcuts
- Cmd+N: New note
- Cmd+Shift+P: Toggle pin on top
- Cmd+B: Bold
- Cmd+I: Italic
- Cmd+K: Insert link
- Cmd+E: Inline code
- Cmd+F: Find in note
- Cmd+Shift+F: Find and replace
- Cmd+`: Cycle through notes
- Cmd+click: Open links in browser

#### Technical
- Native macOS app (Swift/SwiftUI + AppKit)
- WKWebView-based editor with Swift-JavaScript bridge
- Single webpack bundle (~2.5MB with KaTeX fonts)
- macOS 12+ (Monterey) support

---

This changelog follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format.
