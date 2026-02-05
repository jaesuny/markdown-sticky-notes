// CodeMirror 6 Markdown Editor with Syntax Tree-based Live Preview
//
// Architecture:
//   ViewPlugin (markdownDecoPlugin) — syntax tree 순회, 라인/마크 decoration
//   StateField (mathRenderField)    — 수식 렌더링 (멀티라인 replace 필요)
//   HighlightStyle                  — 보조 토큰 색상
//   EditorView.theme()              — CSS 클래스 정의

import { EditorState, StateField } from '@codemirror/state';
import { EditorView, keymap, Decoration, WidgetType, ViewPlugin } from '@codemirror/view';
import { defaultKeymap, history, historyKeymap } from '@codemirror/commands';
import { markdown, markdownLanguage } from '@codemirror/lang-markdown';
import { syntaxHighlighting, HighlightStyle, syntaxTree } from '@codemirror/language';
import { tags as t } from '@lezer/highlight';
import katex from 'katex';
import 'katex/dist/katex.min.css';

// ─── Bridge ────────────────────────────────────────────────────────────────

function sendToBridge(action, data = {}) {
  if (window.webkit?.messageHandlers?.bridge) {
    try {
      window.webkit.messageHandlers.bridge.postMessage({ action, ...data });
    } catch (e) {
      console.error('Bridge error:', e);
    }
  }
}

function log(message) {
  console.log('[Editor]', message);
  sendToBridge('log', { message });
}

// ─── Widgets ───────────────────────────────────────────────────────────────

class MathWidget extends WidgetType {
  constructor(formula, isBlock) {
    super();
    this.formula = formula;
    this.isBlock = isBlock;
  }

  eq(other) {
    return other.formula === this.formula && other.isBlock === this.isBlock;
  }

  toDOM() {
    const wrap = document.createElement(this.isBlock ? 'div' : 'span');
    wrap.className = this.isBlock ? 'cm-math-block' : 'cm-math-inline';
    try {
      katex.render(this.formula, wrap, {
        throwOnError: false,
        displayMode: this.isBlock,
      });
    } catch (e) {
      wrap.textContent = this.formula;
      wrap.className += ' cm-math-error';
    }
    return wrap;
  }

  ignoreEvent() { return false; }
}

class InlineCodeWidget extends WidgetType {
  constructor(code) {
    super();
    this.code = code;
  }

  eq(other) { return other.code === this.code; }

  toDOM() {
    const span = document.createElement('code');
    span.className = 'cm-inline-code-widget';
    span.textContent = this.code;
    return span;
  }

  ignoreEvent() { return false; }
}

// ─── ViewPlugin: Syntax-tree markdown decorations ──────────────────────────

function buildMarkdownDecos(view) {
  const builder = [];
  const lineDecoSet = new Set();
  // Cursor position — skip Decoration.replace() when cursor is inside the range
  const { from: curFrom, to: curTo } = view.state.selection.main;

  function cursorInside(from, to) {
    return curFrom >= from && curTo <= to;
  }

  function addLineDeco(pos, cls) {
    const lineStart = view.state.doc.lineAt(pos).from;
    const key = `${lineStart}:${cls}`;
    if (lineDecoSet.has(key)) return;
    lineDecoSet.add(key);
    builder.push(Decoration.line({ class: cls }).range(lineStart));
  }

  for (const { from, to } of view.visibleRanges) {
    syntaxTree(view.state).iterate({
      from,
      to,
      enter(node) {
        switch (node.name) {
          // ── Headings ──────────────────────────────────────
          case 'ATXHeading1':
            addLineDeco(node.from, 'cm-heading-1');
            break;
          case 'ATXHeading2':
            addLineDeco(node.from, 'cm-heading-2');
            break;
          case 'ATXHeading3':
            addLineDeco(node.from, 'cm-heading-3');
            break;
          case 'ATXHeading4':
            addLineDeco(node.from, 'cm-heading-4');
            break;
          case 'ATXHeading5':
            addLineDeco(node.from, 'cm-heading-5');
            break;
          case 'ATXHeading6':
            addLineDeco(node.from, 'cm-heading-6');
            break;

          // ── Markers (dim) ─────────────────────────────────
          case 'HeaderMark':
          case 'EmphasisMark':
          case 'QuoteMark':
            builder.push(
              Decoration.mark({ class: 'cm-md-marker' }).range(node.from, node.to)
            );
            break;

          // ── Bold ──────────────────────────────────────────
          case 'StrongEmphasis':
            builder.push(
              Decoration.mark({ class: 'cm-md-bold' }).range(node.from, node.to)
            );
            break;

          // ── Italic ────────────────────────────────────────
          case 'Emphasis':
            builder.push(
              Decoration.mark({ class: 'cm-md-italic' }).range(node.from, node.to)
            );
            break;

          // ── Inline Code → widget (unfold when cursor inside) ─
          case 'InlineCode': {
            if (cursorInside(node.from, node.to)) break; // show raw source
            const text = view.state.sliceDoc(node.from, node.to);
            const backtickMatch = text.match(/^(`+)([\s\S]*?)\1$/);
            if (backtickMatch) {
              const inner = backtickMatch[2].trim();
              builder.push(
                Decoration.replace({
                  widget: new InlineCodeWidget(inner),
                }).range(node.from, node.to)
              );
            }
            break;
          }

          // ── Link ──────────────────────────────────────────
          case 'Link': {
            // Style the whole link node, then let LinkMark/URL children
            // be styled separately (markers dim, URL dim)
            builder.push(
              Decoration.mark({ class: 'cm-md-link' }).range(node.from, node.to)
            );
            break;
          }

          // ── Link sub-parts: dim brackets and URL ──────────
          case 'LinkMark':
            builder.push(
              Decoration.mark({ class: 'cm-md-marker' }).range(node.from, node.to)
            );
            break;
          case 'URL':
            builder.push(
              Decoration.mark({ class: 'cm-md-url' }).range(node.from, node.to)
            );
            break;

          // ── Blockquote (line decoration per line) ─────────
          case 'Blockquote': {
            const startLine = view.state.doc.lineAt(node.from).number;
            const endLine = view.state.doc.lineAt(node.to).number;
            for (let i = startLine; i <= endLine; i++) {
              addLineDeco(view.state.doc.line(i).from, 'cm-md-blockquote');
            }
            break;
          }

          // ── Fenced Code Block (line decoration per line) ──
          case 'FencedCode': {
            const startLine = view.state.doc.lineAt(node.from).number;
            const endLine = view.state.doc.lineAt(node.to).number;
            for (let i = startLine; i <= endLine; i++) {
              addLineDeco(view.state.doc.line(i).from, 'cm-md-fenced-code');
            }
            break;
          }

          // ── Horizontal Rule (unfold when cursor on line) ───
          case 'HorizontalRule':
            if (!cursorInside(node.from, node.to)) {
              addLineDeco(node.from, 'cm-md-hr');
            }
            break;
        }
      },
    });
  }

  // Sort by position (required by Decoration.set)
  return Decoration.set(builder, true);
}

const markdownDecoPlugin = ViewPlugin.fromClass(
  class {
    constructor(view) {
      this.decorations = buildMarkdownDecos(view);
    }
    update(update) {
      if (update.docChanged || update.viewportChanged || update.selectionSet) {
        this.decorations = buildMarkdownDecos(update.view);
      }
    }
  },
  { decorations: (v) => v.decorations }
);

// ─── StateField: Math rendering ────────────────────────────────────────────
//
// Uses StateField (not ViewPlugin) because block math $$...$$ can span
// multiple lines, and only StateField can do multiline Decoration.replace().
// Also uses the syntax tree to avoid matching $ inside code blocks.

const KOREAN_RE = /[ㄱ-ㅎㅏ-ㅣ가-힣]/;

function collectCodeRanges(state) {
  const ranges = [];
  syntaxTree(state).iterate({
    enter(node) {
      if (node.name === 'FencedCode' || node.name === 'InlineCode') {
        ranges.push({ from: node.from, to: node.to });
      }
    },
  });
  return ranges;
}

function isInsideCode(pos, ranges) {
  return ranges.some((r) => pos >= r.from && pos < r.to);
}

function buildMathDecorations(state) {
  const widgets = [];
  const text = state.doc.toString();
  const codeRanges = collectCodeRanges(state);
  const { from: curFrom, to: curTo } = state.selection.main;
  let match;

  function cursorInside(from, to) {
    return curFrom >= from && curTo <= to;
  }

  // 1. Block math: $$...$$  (multiline ok)
  const blockRe = /\$\$[\s\S]*?\$\$/g;
  while ((match = blockRe.exec(text)) !== null) {
    if (isInsideCode(match.index, codeRanges)) continue;
    const mFrom = match.index, mTo = mFrom + match[0].length;
    if (cursorInside(mFrom, mTo)) continue; // show raw source
    const formula = match[0].slice(2, -2).trim();
    if (!formula || KOREAN_RE.test(formula)) continue;
    widgets.push(
      Decoration.replace({
        widget: new MathWidget(formula, true),
        block: true,
      }).range(mFrom, mTo)
    );
  }

  // 2. Inline math: $...$  (single line, not $$)
  const inlineRe = /(?<!\$)\$(?!\$)([^\$\n]+?)\$(?!\$)/g;
  while ((match = inlineRe.exec(text)) !== null) {
    if (isInsideCode(match.index, codeRanges)) continue;
    const mFrom = match.index, mTo = mFrom + match[0].length;
    if (cursorInside(mFrom, mTo)) continue; // show raw source
    const formula = match[1].trim();
    if (!formula || KOREAN_RE.test(formula)) continue;
    widgets.push(
      Decoration.replace({
        widget: new MathWidget(formula, false),
      }).range(mFrom, mTo)
    );
  }

  return Decoration.set(widgets, true);
}

const mathRenderField = StateField.define({
  create(state) {
    return buildMathDecorations(state);
  },
  update(decos, tr) {
    // Rebuild on doc change OR selection change (cursor-aware unfold)
    if (tr.docChanged || tr.selection) {
      return buildMathDecorations(tr.state);
    }
    return decos;
  },
  provide(field) {
    return EditorView.decorations.from(field);
  },
});

// ─── Block math navigation ─────────────────────────────────────────────────
// When a block math widget is rendered (cursor outside), arrow keys should
// jump over it instead of getting stuck.

function getRenderedBlockMathRanges(state) {
  const ranges = [];
  const text = state.doc.toString();
  const { from: curFrom, to: curTo } = state.selection.main;
  const blockRe = /\$\$[\s\S]*?\$\$/g;
  let match;
  while ((match = blockRe.exec(text)) !== null) {
    const mFrom = match.index, mTo = mFrom + match[0].length;
    // Only include ranges that are actually rendered (cursor NOT inside)
    if (!(curFrom >= mFrom && curTo <= mTo)) {
      ranges.push({ from: mFrom, to: mTo });
    }
  }
  return ranges;
}

const blockMathNavKeymap = [
  {
    key: 'ArrowDown',
    run: (view) => {
      const { head } = view.state.selection.main;
      const line = view.state.doc.lineAt(head);
      if (line.number >= view.state.doc.lines) return false;
      const nextLine = view.state.doc.line(line.number + 1);
      for (const r of getRenderedBlockMathRanges(view.state)) {
        // Next line falls inside a rendered block math → jump past it
        if (nextLine.from >= r.from && nextLine.from <= r.to) {
          const afterPos = Math.min(r.to + 1, view.state.doc.length);
          const target = afterPos >= view.state.doc.length
            ? view.state.doc.length
            : view.state.doc.lineAt(afterPos).from;
          view.dispatch({ selection: { anchor: target } });
          return true;
        }
      }
      return false;
    },
  },
  {
    key: 'ArrowUp',
    run: (view) => {
      const { head } = view.state.selection.main;
      const line = view.state.doc.lineAt(head);
      if (line.number <= 1) return false;
      const prevLine = view.state.doc.line(line.number - 1);
      for (const r of getRenderedBlockMathRanges(view.state)) {
        // Previous line falls inside a rendered block math → jump before it
        if (prevLine.from >= r.from && prevLine.to <= r.to) {
          const target = r.from === 0
            ? 0
            : view.state.doc.lineAt(r.from - 1).to;
          view.dispatch({ selection: { anchor: target } });
          return true;
        }
      }
      return false;
    },
  },
];

// ─── HighlightStyle (fallback token colours) ───────────────────────────────

const markdownHighlightStyle = HighlightStyle.define([
  { tag: t.heading, fontWeight: 'bold' },
  { tag: t.strong, fontWeight: 'bold' },
  { tag: t.emphasis, fontStyle: 'italic' },
  { tag: t.link, color: '#0969da' },
  { tag: t.monospace, fontFamily: 'Monaco, Menlo, monospace' },
  { tag: t.quote, color: '#656d76', fontStyle: 'italic' },
]);

// ─── macOS Keymap ──────────────────────────────────────────────────────────

function wrapSelection(view, before, after) {
  const { state, dispatch } = view;
  const { from, to } = state.selection.main;
  const sel = state.doc.sliceString(from, to);
  dispatch(
    state.update({
      changes: { from, to, insert: before + sel + after },
      selection: { anchor: from + before.length, head: to + before.length },
    })
  );
}

const macOSKeymap = [
  // Navigation
  {
    key: 'Mod-ArrowUp',
    run: (v) => {
      v.dispatch(v.state.update({ selection: { anchor: 0 } }));
      return true;
    },
  },
  {
    key: 'Mod-ArrowDown',
    run: (v) => {
      const end = v.state.doc.length;
      v.dispatch(v.state.update({ selection: { anchor: end } }));
      return true;
    },
  },
  {
    key: 'Mod-Shift-ArrowUp',
    run: (v) => {
      const head = v.state.selection.main.head;
      v.dispatch(v.state.update({ selection: { anchor: head, head: 0 } }));
      return true;
    },
  },
  {
    key: 'Mod-Shift-ArrowDown',
    run: (v) => {
      const head = v.state.selection.main.head;
      const end = v.state.doc.length;
      v.dispatch(v.state.update({ selection: { anchor: head, head: end } }));
      return true;
    },
  },
  // Formatting
  { key: 'Mod-b', run: (v) => { wrapSelection(v, '**', '**'); return true; } },
  { key: 'Mod-i', run: (v) => { wrapSelection(v, '*', '*'); return true; } },
  { key: 'Mod-k', run: (v) => { wrapSelection(v, '[', '](url)'); return true; } },
  { key: 'Mod-e', run: (v) => { wrapSelection(v, '`', '`'); return true; } },
  { key: 'Mod-s', run: () => { sendToBridge('requestSave'); return true; } },
];

// ─── Theme (CSS) ───────────────────────────────────────────────────────────

const editorTheme = EditorView.theme({
  '&': {
    fontSize: '14px',
    height: '100%',
    backgroundColor: 'transparent',
  },
  '.cm-content': {
    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif',
    padding: '16px',
    minHeight: '100%',
    caretColor: '#5c6ac4',
  },
  '.cm-line': {
    lineHeight: '1.7',
    padding: '1px 0',
  },
  '.cm-scroller': { overflow: 'auto' },
  '&.cm-focused': { outline: 'none' },
  '.cm-cursor': { borderLeftColor: '#5c6ac4' },

  // ── Headings (line decorations → class on .cm-line) ──
  // Decoration.line() adds class to the .cm-line element
  '.cm-heading-1': { fontSize: '1.8em', lineHeight: '1.3', fontWeight: '700', padding: '4px 0' },
  '.cm-heading-2': { fontSize: '1.5em', lineHeight: '1.3', fontWeight: '700', padding: '4px 0' },
  '.cm-heading-3': { fontSize: '1.25em', lineHeight: '1.3', fontWeight: '700', padding: '4px 0' },
  '.cm-heading-4': { fontSize: '1.1em', lineHeight: '1.3', fontWeight: '700', padding: '3px 0' },
  '.cm-heading-5': { fontSize: '1.05em', lineHeight: '1.3', fontWeight: '700', padding: '2px 0' },
  '.cm-heading-6': { fontSize: '1em', lineHeight: '1.3', fontWeight: '700', padding: '2px 0' },

  // ── Markers (dim) ─────────────────────────────────────
  '.cm-md-marker': { opacity: '0.3' },

  // ── Bold / Italic ─────────────────────────────────────
  '.cm-md-bold': { fontWeight: '700' },
  '.cm-md-italic': { fontStyle: 'italic' },

  // ── Link ──────────────────────────────────────────────
  '.cm-md-link': { color: '#0969da', textDecoration: 'underline' },

  // ── Inline Code Widget ────────────────────────────────
  '.cm-inline-code-widget': {
    fontFamily: 'Monaco, Menlo, "Courier New", monospace',
    fontSize: '0.9em',
    backgroundColor: 'rgba(175, 184, 193, 0.2)',
    padding: '2px 5px',
    borderRadius: '3px',
  },

  // ── Fenced Code Block (line decoration) ───────────────
  '.cm-md-fenced-code': {
    backgroundColor: 'rgba(175, 184, 193, 0.1)',
    fontFamily: 'Monaco, Menlo, "Courier New", monospace',
    fontSize: '0.9em',
  },

  // ── Blockquote (line decoration) ──────────────────────
  '.cm-md-blockquote': {
    borderLeft: '3px solid #d0d7de',
    paddingLeft: '12px',
    color: '#656d76',
  },

  // ── Horizontal Rule ───────────────────────────────────
  '.cm-md-hr': {
    borderBottom: '2px solid #d0d7de',
    color: 'transparent',
    height: '0',
    overflow: 'hidden',
    margin: '8px 0',
  },

  // ── URL (dim) ─────────────────────────────────────────
  '.cm-md-url': {
    opacity: '0.4',
    fontSize: '0.85em',
  },

  // ── Math ──────────────────────────────────────────────
  '.cm-math-inline': {
    backgroundColor: 'rgba(92, 106, 196, 0.08)',
    padding: '2px 6px',
    borderRadius: '4px',
    display: 'inline-block',
  },
  '.cm-math-block': {
    backgroundColor: 'rgba(92, 106, 196, 0.05)',
    padding: '16px',
    borderRadius: '8px',
    margin: '8px 0',
    display: 'block',
    overflow: 'auto',
  },
  '.cm-math-error': {
    color: '#d73a49',
    backgroundColor: 'rgba(215, 58, 73, 0.1)',
  },
}, { dark: false });

const darkTheme = EditorView.theme({
  '.cm-content': { color: '#e0e0e0', caretColor: '#8c9eff' },
  '.cm-cursor': { borderLeftColor: '#8c9eff' },
  '.cm-md-bold': { color: '#e0e0e0' },
  '.cm-md-marker': { opacity: '0.25' },
  '.cm-md-link': { color: '#8c9eff' },
  '.cm-md-blockquote': { borderLeftColor: '#555', color: '#aaa' },
  '.cm-md-fenced-code': { backgroundColor: 'rgba(255,255,255,0.05)' },
  '.cm-inline-code-widget': { backgroundColor: 'rgba(255,255,255,0.1)' },
  '.cm-math-inline': { backgroundColor: 'rgba(140,158,255,0.1)' },
  '.cm-math-block': { backgroundColor: 'rgba(140,158,255,0.07)' },
}, { dark: true });

// ─── Editor initialization ─────────────────────────────────────────────────

let editorView;
let debounceTimer;

function initEditor(initialContent = '') {
  log('Initializing editor...');

  const state = EditorState.create({
    doc: initialContent,
    extensions: [
      history(),
      keymap.of([...blockMathNavKeymap, ...macOSKeymap, ...defaultKeymap, ...historyKeymap]),
      markdown({ base: markdownLanguage }),
      syntaxHighlighting(markdownHighlightStyle),
      markdownDecoPlugin,
      mathRenderField,
      editorTheme,
      window.matchMedia('(prefers-color-scheme: dark)').matches ? darkTheme : [],
      EditorView.updateListener.of((update) => {
        if (update.docChanged) {
          clearTimeout(debounceTimer);
          debounceTimer = setTimeout(() => {
            sendToBridge('contentChanged', {
              content: update.state.doc.toString(),
            });
          }, 300);
        }
      }),
      EditorView.lineWrapping,
    ],
  });

  editorView = new EditorView({
    state,
    parent: document.getElementById('editor-container'),
  });

  log('Editor ready');
}

// ─── Swift bridge interface ────────────────────────────────────────────────

window.setContent = function (content) {
  if (!editorView) return;
  editorView.dispatch(
    editorView.state.update({
      changes: { from: 0, to: editorView.state.doc.length, insert: content },
    })
  );
};

window.getContent = function () {
  return editorView ? editorView.state.doc.toString() : '';
};

// ─── Bootstrap ─────────────────────────────────────────────────────────────

document.addEventListener('DOMContentLoaded', () => {
  log('DOM ready');
  initEditor();
  sendToBridge('ready');
  setTimeout(() => editorView?.focus(), 100);
});

window.addEventListener('error', (e) => {
  sendToBridge('error', { message: 'Error: ' + e.message });
});

log('Editor script loaded');
