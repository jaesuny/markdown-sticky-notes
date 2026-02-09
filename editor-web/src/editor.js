// CodeMirror 6 Markdown Editor with Syntax Tree-based Live Preview
//
// Architecture:
//   ViewPlugin (markdownDecoPlugin) — syntax tree 순회, 라인/마크 decoration
//   StateField (mathRenderField)    — 수식 렌더링 (멀티라인 replace 필요)
//   HighlightStyle                  — 보조 토큰 색상
//   EditorView.theme()              — CSS 클래스 정의

import { EditorState, StateField, EditorSelection } from '@codemirror/state';
import { EditorView, keymap, Decoration, WidgetType, ViewPlugin } from '@codemirror/view';
import { defaultKeymap, history, historyKeymap } from '@codemirror/commands';
import { markdown } from '@codemirror/lang-markdown';
import { javascript } from '@codemirror/lang-javascript';
import { python } from '@codemirror/lang-python';
import { html } from '@codemirror/lang-html';
import { css } from '@codemirror/lang-css';
import { json } from '@codemirror/lang-json';
import { rust } from '@codemirror/lang-rust';
import { go } from '@codemirror/lang-go';
import { java } from '@codemirror/lang-java';
import { cpp } from '@codemirror/lang-cpp';
import { php } from '@codemirror/lang-php';
import { sql } from '@codemirror/lang-sql';
import { xml } from '@codemirror/lang-xml';
import { yaml } from '@codemirror/lang-yaml';
import { vue } from '@codemirror/lang-vue';
import { StreamLanguage } from '@codemirror/language';
import { shell } from '@codemirror/legacy-modes/mode/shell';

// Static language list for WKWebView (no dynamic imports)
const staticLanguages = {
  javascript: javascript(),
  js: javascript(),
  jsx: javascript({ jsx: true }),
  ts: javascript({ typescript: true }),
  tsx: javascript({ jsx: true, typescript: true }),
  typescript: javascript({ typescript: true }),
  python: python(),
  py: python(),
  html: html(),
  htm: html(),
  css: css(),
  scss: css(),
  less: css(),
  json: json(),
  rust: rust(),
  rs: rust(),
  go: go(),
  golang: go(),
  java: java(),
  cpp: cpp(),
  c: cpp(),
  'c++': cpp(),
  cc: cpp(),
  cxx: cpp(),
  php: php(),
  sql: sql(),
  xml: xml(),
  svg: xml(),
  yaml: yaml(),
  yml: yaml(),
  vue: vue(),
  // Legacy modes (StreamLanguage) — wrap in object with .language property
  shell: { language: StreamLanguage.define(shell) },
  bash: { language: StreamLanguage.define(shell) },
  sh: { language: StreamLanguage.define(shell) },
  zsh: { language: StreamLanguage.define(shell) },
};

// CodeMirror calls this with the language name string (e.g., "python", "js")
// Must return Language object, not LanguageSupport
function findLanguage(info) {
  if (!info) return null;
  const name = (typeof info === 'string' ? info : info.name || '').toLowerCase();
  const langSupport = staticLanguages[name];
  if (langSupport) {
    console.log('[Syntax] Found language:', name);
    return langSupport.language;  // Return Language, not LanguageSupport
  }
  console.log('[Syntax] Unknown language:', name);
  return null;
}
import { syntaxHighlighting, HighlightStyle, syntaxTree, defaultHighlightStyle } from '@codemirror/language';
import { tags as t } from '@lezer/highlight';
import { GFM } from '@lezer/markdown';
import { search, searchKeymap, highlightSelectionMatches, openSearchPanel } from '@codemirror/search';
import katex from 'katex';
import 'katex/dist/katex.min.css';

// ─── Bridge ────────────────────────────────────────────────────────────────

let currentNoteId = null;
let snapshotMode = false; // When true, cursorInside() always returns false (no unfolds)
let suppressContentChange = false; // When true, updateListener skips contentChanged bridge message

function sendToBridge(action, data = {}) {
  if (window.webkit?.messageHandlers?.bridge) {
    try {
      window.webkit.messageHandlers.bridge.postMessage({ action, noteId: currentNoteId, ...data });
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

// Cache for measured math widget heights (formula -> height in px)
const mathHeightCache = new Map();

// Measure math height by rendering inside editor container (cached)
// Uses editor container width for accurate measurement
let measureContainer = null;

function measureMathHeight(formula, isBlock) {
  const cacheKey = `${isBlock ? 'block' : 'inline'}:${formula}`;
  const cached = mathHeightCache.get(cacheKey);
  if (cached !== undefined) return cached;

  // Create hidden container inside editor for accurate width
  if (!measureContainer) {
    measureContainer = document.createElement('div');
    measureContainer.style.cssText = 'visibility:hidden;position:absolute;left:0;right:0;top:-9999px;overflow:hidden;';
    const editorContainer = document.getElementById('editor-container');
    if (editorContainer) {
      editorContainer.appendChild(measureContainer);
    } else {
      document.body.appendChild(measureContainer);
    }
  }

  const temp = document.createElement(isBlock ? 'div' : 'span');
  temp.className = isBlock ? 'cm-math-block' : 'cm-math-inline';
  // Apply same styles as theme (EditorView.theme styles don't apply outside .cm-editor)
  if (isBlock) {
    temp.style.cssText = 'padding:8px;display:block;';
  }
  measureContainer.appendChild(temp);

  try {
    katex.render(formula, temp, {
      throwOnError: false,
      displayMode: isBlock,
      strict: false,
    });
  } catch (e) {
    temp.textContent = formula;
  }

  const height = temp.offsetHeight;
  measureContainer.removeChild(temp);

  mathHeightCache.set(cacheKey, height);
  return height;
}

class MathWidget extends WidgetType {
  constructor(formula, isBlock, height) {
    super();
    this.formula = formula;
    this.isBlock = isBlock;
    this._height = height;
  }

  eq(other) {
    return other.formula === this.formula && other.isBlock === this.isBlock;
  }

  get estimatedHeight() {
    return this._height;
  }

  toDOM() {
    const wrap = document.createElement(this.isBlock ? 'div' : 'span');
    wrap.className = this.isBlock ? 'cm-math-block' : 'cm-math-inline';
    try {
      katex.render(this.formula, wrap, {
        throwOnError: false,
        displayMode: this.isBlock,
        strict: false,
      });
    } catch (e) {
      wrap.textContent = this.formula;
      wrap.className += ' cm-math-error';
    }
    return wrap;
  }

  ignoreEvent() { return false; }
}

// Overlay widget for block math - positioned absolute over source lines
class MathOverlayWidget extends WidgetType {
  constructor(formula, height) {
    super();
    this.formula = formula;
    this._height = height;
  }

  eq(other) {
    return other.formula === this.formula;
  }

  toDOM() {
    const wrap = document.createElement('div');
    wrap.className = 'cm-math-overlay';
    wrap.style.height = this._height + 'px';
    try {
      katex.render(this.formula, wrap, {
        throwOnError: false,
        displayMode: true,
        strict: false,
      });
    } catch (e) {
      console.warn('[KaTeX block error]', e.message, '\nFormula:', JSON.stringify(this.formula));
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

// Overlay widget for HR - thin line positioned absolute over source
class HROverlayWidget extends WidgetType {
  constructor() {
    super();
  }

  eq(other) {
    return true; // All HRs are visually equivalent
  }

  toDOM() {
    const wrap = document.createElement('div');
    wrap.className = 'cm-hr-overlay';
    return wrap;
  }

  ignoreEvent() { return false; }
}

class TaskCheckboxWidget extends WidgetType {
  constructor(checked, pos) {
    super();
    this.checked = checked;
    this.pos = pos;
  }

  eq(other) { return other.checked === this.checked && other.pos === this.pos; }

  toDOM(view) {
    const input = document.createElement('input');
    input.type = 'checkbox';
    input.checked = this.checked;
    input.className = 'cm-task-checkbox';
    input.addEventListener('mousedown', (e) => {
      e.preventDefault();
      const newText = this.checked ? '[ ]' : '[x]';
      view.dispatch({ changes: { from: this.pos, to: this.pos + 3, insert: newText } });
    });
    return input;
  }

  ignoreEvent() { return false; }
}

// Bullet list marker widget (renders as styled dot)
class BulletMarkerWidget extends WidgetType {
  constructor() {
    super();
  }

  eq(other) { return true; }

  toDOM() {
    const span = document.createElement('span');
    span.className = 'cm-bullet-marker';
    span.textContent = '•';
    return span;
  }

  ignoreEvent() { return false; }
}

// Ordered list marker widget (renders as styled number)
class OrderedMarkerWidget extends WidgetType {
  constructor(number) {
    super();
    this.number = number;
  }

  eq(other) { return other.number === this.number; }

  toDOM() {
    const span = document.createElement('span');
    span.className = 'cm-ordered-marker';
    span.textContent = this.number + '.';
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
    if (snapshotMode) return false;
    return curFrom >= from && curTo <= to;
  }

  function addLineDeco(pos, cls) {
    const lineStart = view.state.doc.lineAt(pos).from;
    const key = `${lineStart}:${cls}`;
    if (lineDecoSet.has(key)) return;
    lineDecoSet.add(key);
    builder.push(Decoration.line({ class: cls }).range(lineStart));
  }

  // Check if position is on the same line as cursor
  const cursorLine = view.state.doc.lineAt(curFrom).number;
  function cursorOnLine(pos) {
    if (snapshotMode) return false;
    return view.state.doc.lineAt(pos).number === cursorLine;
  }

  // Add cursor line decoration for marker visibility (skip in snapshot mode)
  if (!snapshotMode) {
    addLineDeco(view.state.doc.line(cursorLine).from, 'cm-cursor-line');
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

          // ── Markers (hidden when cursor not on line) ──────
          case 'HeaderMark': {
            const hLine = view.state.doc.lineAt(node.from);
            if (node.from === hLine.from) {
              // Opening # marks — hide when cursor not on line
              builder.push(
                Decoration.mark({ class: 'cm-md-marker' }).range(node.from, node.to)
              );
            } else {
              // Trailing # marks — inherit heading text color
              builder.push(
                Decoration.mark({ class: 'cm-md-marker-trailing' }).range(node.from, node.to)
              );
            }
            break;
          }
          case 'EmphasisMark':
          case 'QuoteMark':
          case 'CodeMark':  // ``` fenced code markers
          case 'CodeInfo':  // language name after ```
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
              let classes = 'cm-md-fenced-code';
              if (i === startLine) classes += ' cm-md-fenced-code-first';
              if (i === endLine) classes += ' cm-md-fenced-code-last';
              addLineDeco(view.state.doc.line(i).from, classes);
            }
            break;
          }

          // ── Horizontal Rule (overlay with animation) ───
          case 'HorizontalRule': {
            const lineStart = view.state.doc.lineAt(node.from).from;
            const isEditing = cursorInside(node.from, node.to);
            const hrClass = isEditing ? 'cm-hr-source-line cm-hr-editing' : 'cm-hr-source-line';
            // Source line: fixed height, toggle editing class
            builder.push(
              Decoration.line({
                attributes: {
                  class: hrClass,
                  style: 'height:16px;line-height:16px;',
                },
              }).range(lineStart)
            );
            // Overlay widget: positioned absolute, visual HR
            builder.push(
              Decoration.widget({
                widget: new HROverlayWidget(),
                side: -1,
              }).range(lineStart)
            );
            break;
          }

          // ── Strikethrough ───────────────────────────────────
          case 'Strikethrough':
            builder.push(
              Decoration.mark({ class: 'cm-md-strikethrough' }).range(node.from, node.to)
            );
            break;
          case 'StrikethroughMark':
            builder.push(
              Decoration.mark({ class: 'cm-md-marker' }).range(node.from, node.to)
            );
            break;

          // ── Lists ───────────────────────────────────────────
          case 'ListMark': {
            // Task list dashes are handled by TaskMarker case
            if (view.state.sliceDoc(node.to, node.to + 2).startsWith(' [')) break;

            // Don't replace when cursor is on this line (allow editing)
            if (cursorOnLine(node.from)) {
              builder.push(
                Decoration.mark({ class: 'cm-md-list-mark' }).range(node.from, node.to)
              );
              break;
            }

            const markerText = view.state.sliceDoc(node.from, node.to).trim();
            // Check if ordered (number) or unordered (-, *, +)
            if (/^\d+\.$/.test(markerText)) {
              // Ordered list: extract number
              const num = parseInt(markerText, 10);
              builder.push(
                Decoration.replace({
                  widget: new OrderedMarkerWidget(num),
                }).range(node.from, node.to)
              );
            } else {
              // Unordered list: -, *, +
              builder.push(
                Decoration.replace({
                  widget: new BulletMarkerWidget(),
                }).range(node.from, node.to)
              );
            }
            break;
          }

          // ── Task List ───────────────────────────────────────
          // Replace "- [x]" or "- [ ]" as a single unit with a checkbox widget
          case 'TaskMarker': {
            // Find the ListMark before this TaskMarker: "- " precedes "[x]"
            const listMarkFrom = node.from - 2; // "- " is 2 chars before TaskMarker
            const fullFrom = listMarkFrom >= 0 &&
              view.state.sliceDoc(listMarkFrom, node.from) === '- '
              ? listMarkFrom : node.from;
            if (cursorInside(fullFrom, node.to)) break;
            const markerText = view.state.sliceDoc(node.from, node.to);
            const checked = markerText.includes('x') || markerText.includes('X');
            builder.push(
              Decoration.replace({
                widget: new TaskCheckboxWidget(checked, node.from),
              }).range(fullFrom, node.to)
            );
            break;
          }

          // ── Table ───────────────────────────────────────────
          case 'Table': {
            const startLine = view.state.doc.lineAt(node.from).number;
            const endLine = view.state.doc.lineAt(node.to).number;
            for (let i = startLine; i <= endLine; i++) {
              addLineDeco(view.state.doc.line(i).from, 'cm-md-table');
            }
            break;
          }
          case 'TableHeader':
            addLineDeco(node.from, 'cm-md-table-header');
            break;
          case 'TableDelimiter':
            addLineDeco(node.from, 'cm-md-table-delimiter');
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
    if (snapshotMode) return false;
    return curFrom >= from && curTo <= to;
  }

  // 1. Block math: $$...$$  (multiline ok)
  // Overlay approach with animation: always render, toggle class for cursor state
  const blockRe = /\$\$[\s\S]*?\$\$/g;
  while ((match = blockRe.exec(text)) !== null) {
    if (isInsideCode(match.index, codeRanges)) continue;
    const mFrom = match.index, mTo = mFrom + match[0].length;
    const formula = match[0].slice(2, -2).trim();
    if (!formula) continue;

    const isEditing = cursorInside(mFrom, mTo);

    // When editing: skip ALL decorations — lines stay normal (no spacing jump)
    // When not editing: overlay pattern with adjusted line-height
    if (!isEditing) {
      const measuredHeight = measureMathHeight(formula, true);
      const startLine = state.doc.lineAt(mFrom);
      const endLine = state.doc.lineAt(mTo);
      const lineCount = endLine.number - startLine.number + 1;
      const minLineHeight = 22;
      const lineHeight = Math.max(Math.ceil(measuredHeight / lineCount), minLineHeight);
      const totalHeight = lineHeight * lineCount;

      for (let i = startLine.number; i <= endLine.number; i++) {
        const line = state.doc.line(i);
        widgets.push(
          Decoration.line({
            attributes: {
              style: `line-height:${lineHeight}px;height:${lineHeight}px;`,
              class: 'cm-math-source-line',
            },
          }).range(line.from)
        );
      }

      widgets.push(
        Decoration.widget({
          widget: new MathOverlayWidget(formula, totalHeight),
          side: -1,
        }).range(startLine.from)
      );
    }
  }

  // 2. Inline math: $...$  (single line, not $$)
  // Use Decoration.replace() - true crossfade not possible for inline elements
  const inlineRe = /(?<!\$)\$(?!\$)([^\$\n]+?)\$(?!\$)/g;
  while ((match = inlineRe.exec(text)) !== null) {
    if (isInsideCode(match.index, codeRanges)) continue;
    const mFrom = match.index, mTo = mFrom + match[0].length;
    if (cursorInside(mFrom, mTo)) continue; // show raw source
    const formula = match[1].trim();
    if (!formula) continue;
    const height = measureMathHeight(formula, false);
    widgets.push(
      Decoration.replace({
        widget: new MathWidget(formula, false, height),
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

// Helper: find if a document position is inside any rendered block math range
function findBlockMathAt(state, pos) {
  const ranges = getRenderedBlockMathRanges(state);
  return ranges.find(r => pos >= r.from && pos <= r.to) || null;
}

const blockMathNavKeymap = [
  {
    key: 'ArrowDown',
    run: (view) => {
      const { head } = view.state.selection.main;
      const line = view.state.doc.lineAt(head);
      if (line.number >= view.state.doc.lines) return false;
      const nextLine = view.state.doc.line(line.number + 1);
      const r = findBlockMathAt(view.state, nextLine.from);
      if (!r) return false;
      // Jump past the block math
      const afterPos = Math.min(r.to + 1, view.state.doc.length);
      const target = afterPos >= view.state.doc.length
        ? view.state.doc.length
        : view.state.doc.lineAt(afterPos).from;
      view.dispatch({
        selection: { anchor: target },
        scrollIntoView: true,
      });
      return true;
    },
  },
  {
    key: 'ArrowUp',
    run: (view) => {
      const { head } = view.state.selection.main;
      const line = view.state.doc.lineAt(head);
      if (line.number <= 1) return false;
      const prevLine = view.state.doc.line(line.number - 1);
      const r = findBlockMathAt(view.state, prevLine.from);
      if (!r) return false;
      // Jump before the block math
      const target = r.from === 0
        ? 0
        : view.state.doc.lineAt(r.from).from > 0
          ? view.state.doc.lineAt(r.from - 1).to
          : 0;
      view.dispatch({
        selection: { anchor: target },
        scrollIntoView: true,
      });
      return true;
    },
  },
];

// ─── HighlightStyle (fallback token colours) ───────────────────────────────

const markdownHighlightStyle = HighlightStyle.define([
  { tag: t.heading, fontWeight: 'bold', textDecoration: 'none' },
  { tag: t.strong, fontWeight: 'bold' },
  { tag: t.emphasis, fontStyle: 'italic' },
  { tag: t.link, color: '#0969da' },
  { tag: t.monospace, fontFamily: 'Monaco, Menlo, monospace' },
  { tag: t.quote, color: '#656d76', fontStyle: 'italic' },
]);

// ─── Formatting Keymap ─────────────────────────────────────────────────────
// Navigation keybindings (Cmd+Arrow, Cmd+Shift+Arrow, Opt+Arrow, etc.) are
// already provided by CodeMirror's defaultKeymap. We only add markdown
// formatting shortcuts here.

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

const formattingKeymap = [
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
    color: '#1a1a1a',
  },
  '.cm-content': {
    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif',
    padding: '32px 16px 16px 16px',  // top: 32px for titlebar spacing
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
  '.cm-heading-1': { fontSize: '1.8em', lineHeight: '1.3', fontWeight: '700', padding: '4px 0', textDecoration: 'none' },
  '.cm-heading-2': { fontSize: '1.5em', lineHeight: '1.3', fontWeight: '700', padding: '4px 0', textDecoration: 'none' },
  '.cm-heading-3': { fontSize: '1.25em', lineHeight: '1.3', fontWeight: '700', padding: '4px 0', textDecoration: 'none' },
  '.cm-heading-4': { fontSize: '1.1em', lineHeight: '1.3', fontWeight: '700', padding: '3px 0', textDecoration: 'none' },
  '.cm-heading-5': { fontSize: '1.05em', lineHeight: '1.3', fontWeight: '700', padding: '2px 0', textDecoration: 'none' },
  '.cm-heading-6': { fontSize: '1em', lineHeight: '1.3', fontWeight: '700', padding: '2px 0', textDecoration: 'none' },

  // ── Cursor line (for marker visibility) ─────────────
  '.cm-cursor-line': {
    // Markers are visible only on cursor line
  },

  // ── Markers (hidden by default, visible on cursor line) ──
  '.cm-md-marker': {
    fontSize: '0',
    opacity: '0',
    transition: 'opacity 0.1s, font-size 0.1s',
  },
  '.cm-cursor-line .cm-md-marker': {
    fontSize: 'inherit',
    opacity: '0.35',
  },
  '.cm-md-marker-trailing, .cm-md-marker-trailing *': {
    color: 'inherit !important',
  },

  // ── Bold / Italic ─────────────────────────────────────
  '.cm-md-bold': { fontWeight: '700' },
  '.cm-md-italic': { fontStyle: 'italic' },

  // ── Link ──────────────────────────────────────────────
  '.cm-md-link': {
    color: '#0969da',
    textDecoration: 'underline',
    textDecorationColor: 'rgba(9, 105, 218, 0.3)',
    borderRadius: '2px',
    transition: 'background-color 0.15s, text-decoration-color 0.15s',
    cursor: 'pointer',
  },
  '.cm-md-link:hover': {
    backgroundColor: 'rgba(9, 105, 218, 0.1)',
    textDecorationColor: 'rgba(9, 105, 218, 0.6)',
  },

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
    backgroundColor: 'rgba(175, 184, 193, 0.15)',
    fontFamily: 'Monaco, Menlo, "Courier New", monospace',
    fontSize: '0.9em',
    marginLeft: '-8px',
    marginRight: '-8px',
    paddingLeft: '12px',
    paddingRight: '12px',
  },
  '.cm-md-fenced-code-first': {
    borderTopLeftRadius: '6px',
    borderTopRightRadius: '6px',
    paddingTop: '2px',
  },
  '.cm-md-fenced-code-last': {
    borderBottomLeftRadius: '6px',
    borderBottomRightRadius: '6px',
    paddingBottom: '2px',
  },

  // ── Blockquote (line decoration) ──────────────────────
  '.cm-md-blockquote': {
    borderLeft: '3px solid #d0d7de',
    paddingLeft: '12px',
    color: '#656d76',
  },

  // ── Horizontal Rule (overlay with animation — slower) ─────────────────
  '.cm-hr-source-line': {
    position: 'relative',
  },
  '.cm-hr-source-line > *:not(.cm-hr-overlay)': {
    opacity: '0',
    transition: 'opacity 0.3s ease-out',
  },
  '.cm-hr-overlay': {
    position: 'absolute',
    left: '0',
    right: '0',
    top: '50%',
    transform: 'translateY(-50%)',
    height: '2px',
    backgroundColor: '#d0d7de',
    borderRadius: '1px',
    pointerEvents: 'none',
    opacity: '1',
    transition: 'opacity 0.3s ease-out',
  },
  // Editing state: show source, hide overlay
  '.cm-hr-source-line.cm-hr-editing > *:not(.cm-hr-overlay)': {
    opacity: '1',
  },
  '.cm-hr-source-line.cm-hr-editing .cm-hr-overlay': {
    opacity: '0',
  },

  // ── URL (hidden when cursor not on line) ──────────────
  '.cm-md-url': {
    fontSize: '0',
    opacity: '0',
    transition: 'opacity 0.1s, font-size 0.1s',
  },
  '.cm-cursor-line .cm-md-url': {
    fontSize: '0.85em',
    opacity: '0.4',
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
    padding: '8px',
    borderRadius: '8px',
    margin: '4px 0',
    display: 'block',
    overflow: 'auto',
  },
  '.cm-math-error': {
    color: '#d73a49',
    backgroundColor: 'rgba(215, 58, 73, 0.1)',
  },
  // Overlay approach for block math - widget positioned over transparent source
  '.cm-math-overlay': {
    position: 'absolute',
    left: '0',
    right: '0',
    top: '0',
    backgroundColor: 'rgba(92, 106, 196, 0.05)',
    padding: '8px',
    borderRadius: '8px',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    overflow: 'hidden',
    pointerEvents: 'none', // Allow clicks to pass through to source lines
    zIndex: '10',
    boxSizing: 'border-box',
    color: '#000 !important', // Override inherited transparent color
    opacity: '1',
    transition: 'opacity 0.15s ease-out',
  },
  '.cm-math-overlay *': {
    color: 'inherit !important', // Ensure KaTeX content is visible
  },
  '.cm-line.cm-math-source-line': {
    position: 'relative', // For overlay positioning context
    color: 'transparent', // Hide text nodes (CSS can't target text nodes directly)
    transition: 'color 0.2s ease-out',
  },
  // Force all syntax-highlighted spans transparent (they have explicit colors that override inherited transparent)
  '.cm-line.cm-math-source-line *': {
    color: 'transparent !important',
  },
  // But keep overlay and its children visible
  '.cm-line.cm-math-source-line .cm-math-overlay, .cm-line.cm-math-source-line .cm-math-overlay *': {
    color: '#000 !important',
  },
  // Editing state: show source text, hide overlay
  '.cm-line.cm-math-source-line.cm-math-editing': {
    color: 'inherit',
  },
  '.cm-line.cm-math-source-line.cm-math-editing *': {
    color: 'inherit !important',
  },
  '.cm-line.cm-math-source-line.cm-math-editing .cm-math-overlay': {
    opacity: '0',
  },

  // ── Strikethrough ──────────────────────────────────────
  '.cm-md-strikethrough': { textDecoration: 'line-through', opacity: '0.6' },

  // ── List markers ───────────────────────────────────────
  // Source markers (visible when cursor on line)
  '.cm-md-list-mark': {
    color: 'inherit',
    opacity: '0.35',
  },
  // Bullet marker widget (•)
  '.cm-bullet-marker': {
    color: 'inherit',
    opacity: '0.7',
    fontWeight: '900',
    fontSize: '0.9em',
    marginRight: '4px',
  },
  // Ordered marker widget (1. 2. 3.)
  '.cm-ordered-marker': {
    color: 'inherit',
    opacity: '0.55',
    fontWeight: '600',
    fontSize: '0.85em',
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
    marginRight: '3px',
    minWidth: '1.4em',
    display: 'inline-block',
    textAlign: 'right',
  },

  // ── Task checkbox ──────────────────────────────────────
  '.cm-task-checkbox': {
    cursor: 'pointer',
    margin: '0 4px 0 0',
    transform: 'scale(1.15)',
    verticalAlign: 'middle',
  },

  // ── Table ──────────────────────────────────────────────
  '.cm-md-table': {
    fontFamily: 'Monaco, Menlo, "Courier New", monospace',
    fontSize: '0.85em',
    backgroundColor: 'rgba(0, 0, 0, 0.06)',
    padding: '4px 12px',
    marginLeft: '-8px',
    marginRight: '-8px',
    borderLeft: '3px solid rgba(0, 0, 0, 0.15)',
  },
  '.cm-md-table-header': {
    fontWeight: '700',
    backgroundColor: 'rgba(0, 0, 0, 0.1)',
  },
  '.cm-md-table-delimiter': {
    opacity: '0.3',
    fontSize: '0.8em',
    color: 'rgba(0, 0, 0, 0.4)',
  },

  // ── Search Panel ────────────────────────────────────────
  // base theme의 #f5f5f5 회색 배경 제거 — 노트 배경색이 보이도록
  '.cm-panels.cm-panels': {
    backgroundColor: 'transparent',
    color: 'inherit',
  },
  '.cm-panels-top.cm-panels-top': {
    borderBottom: 'none',
    marginTop: '28px',  // below titlebar
  },
  '.cm-panel.cm-search': {
    padding: '6px 10px',
    backgroundColor: 'rgba(255, 255, 255, 0.18)',
    borderBottom: '1px solid rgba(0, 0, 0, 0.08)',
    fontSize: '12px',
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
    color: 'inherit',
    display: 'flex',
    flexWrap: 'wrap',
    alignItems: 'center',
    gap: '3px 6px',
    '& br': { display: 'none' },
  },
  // Text inputs (search / replace) — 밝은 배경으로 입력 영역 강조
  '.cm-panel.cm-search input.cm-textfield': {
    fontSize: '12px',
    padding: '4px 8px',
    borderRadius: '5px',
    border: '1px solid rgba(0, 0, 0, 0.1)',
    backgroundColor: 'rgba(255, 255, 255, 0.7)',
    color: 'inherit',
    outline: 'none',
    fontFamily: 'inherit',
    transition: 'all 0.15s',
    boxShadow: '0 1px 2px rgba(0, 0, 0, 0.06)',
  },
  '.cm-panel.cm-search input.cm-textfield:focus': {
    backgroundColor: 'rgba(255, 255, 255, 0.85)',
    borderColor: 'rgba(0, 0, 0, 0.15)',
    boxShadow: '0 1px 3px rgba(0, 0, 0, 0.1)',
  },
  // Action buttons (next, prev, all, replace, replace all)
  // base theme이 &light .cm-button에 회색 gradient 배경 설정 — 리셋 필요
  '.cm-panel.cm-search button.cm-button.cm-button': {
    fontSize: '11px',
    fontWeight: '500',
    padding: '3px 8px',
    borderRadius: '4px',
    border: '1px solid rgba(0, 0, 0, 0.08)',
    backgroundColor: 'rgba(255, 255, 255, 0.65)',
    backgroundImage: 'none',
    cursor: 'pointer',
    fontFamily: 'inherit',
    transition: 'all 0.12s',
    color: 'inherit',
    lineHeight: '1.4',
    boxShadow: '0 1px 1px rgba(0, 0, 0, 0.04)',
  },
  '.cm-panel.cm-search button.cm-button.cm-button:hover': {
    backgroundColor: 'rgba(255, 255, 255, 0.65)',
    backgroundImage: 'none',
    borderColor: 'rgba(0, 0, 0, 0.12)',
  },
  '.cm-panel.cm-search button.cm-button.cm-button:active': {
    backgroundColor: 'rgba(255, 255, 255, 0.75)',
    backgroundImage: 'none',
    transform: 'scale(0.97)',
    boxShadow: 'none',
  },
  // Hide regexp and by-word options
  '.cm-panel.cm-search label:has(input[name="re"])': { display: 'none' },
  '.cm-panel.cm-search label:has(input[name="word"])': { display: 'none' },
  // Match case label — show as "Aa" icon
  '.cm-panel.cm-search label:has(input[name="case"])': {
    fontSize: '0px',  // hide original text
    padding: '3px 5px',
    opacity: '0.4',
    '&::after': {
      content: '"Aa"',
      fontSize: '12px',
      fontWeight: '600',
      fontFamily: '-apple-system, BlinkMacSystemFont, sans-serif',
    },
    '&:has(input:checked)': {
      opacity: '0.9',
      backgroundColor: 'rgba(255, 255, 255, 0.25)',
    },
  },
  '.cm-panel.cm-search label:has(input[name="case"]) input': {
    display: 'none',  // hide checkbox, just show Aa
  },
  // Other checkbox labels (if any remain)
  '.cm-panel.cm-search label': {
    fontSize: '10.5px',
    color: 'inherit',
    opacity: '0.6',
    display: 'inline-flex',
    alignItems: 'center',
    gap: '3px',
    padding: '2px 6px',
    borderRadius: '4px',
    cursor: 'pointer',
    transition: 'all 0.12s',
    border: '1px solid transparent',
    userSelect: 'none',
    '&:hover': {
      opacity: '0.85',
      backgroundColor: 'rgba(255, 255, 255, 0.15)',
    },
  },
  // Custom checkbox — hide native, draw a rounded box
  '.cm-panel.cm-search input[type=checkbox]': {
    appearance: 'none',
    WebkitAppearance: 'none',
    width: '12px',
    height: '12px',
    borderRadius: '3px',
    border: '1.5px solid currentColor',
    opacity: '0.5',
    backgroundColor: 'transparent',
    cursor: 'pointer',
    position: 'relative',
    flexShrink: '0',
    transition: 'all 0.12s',
    margin: '0',
  },
  '.cm-panel.cm-search input[type=checkbox]:checked': {
    backgroundColor: 'currentColor',
    opacity: '0.8',
  },
  '.cm-panel.cm-search input[type=checkbox]:checked::after': {
    content: '""',
    position: 'absolute',
    left: '3px',
    top: '0.5px',
    width: '4px',
    height: '7px',
    border: 'solid rgba(255, 255, 255, 0.9)',
    borderWidth: '0 1.5px 1.5px 0',
    transform: 'rotate(45deg)',
  },
  // Hide "All" button (select all matches)
  '.cm-panel.cm-search button[name="select"]': {
    display: 'none',
  },
  // Hide replace section by default
  '.cm-panel.cm-search input[name="replace"]': {
    display: 'none',
  },
  '.cm-panel.cm-search button[name="replace"]': {
    display: 'none',
  },
  '.cm-panel.cm-search button[name="replaceAll"]': {
    display: 'none',
  },
  // Show replace when .show-replace class is added
  '.cm-panel.cm-search.show-replace input[name="replace"]': {
    display: 'block',
  },
  '.cm-panel.cm-search.show-replace button[name="replace"]': {
    display: 'inline-block',
  },
  '.cm-panel.cm-search.show-replace button[name="replaceAll"]': {
    display: 'inline-block',
  },
  // Close button (×)
  '.cm-panel.cm-search button[name="close"]': {
    marginLeft: 'auto',
    color: 'inherit',
    opacity: '0.35',
    fontSize: '16px',
    cursor: 'pointer',
    padding: '1px 4px',
    borderRadius: '4px',
    border: 'none',
    backgroundColor: 'transparent',
    lineHeight: '1',
    transition: 'all 0.12s',
    '&:hover': { opacity: '0.6', backgroundColor: 'rgba(255, 255, 255, 0.2)' },
  },
  // Match highlights in editor
  '.cm-searchMatch': {
    backgroundColor: 'rgba(255, 180, 50, 0.4)',
    borderRadius: '2px',
    boxShadow: '0 0 0 1px rgba(255, 150, 0, 0.5)',
  },
  '.cm-searchMatch-selected': {
    backgroundColor: 'rgba(255, 130, 0, 0.5)',
    boxShadow: '0 0 0 2px rgba(255, 100, 0, 0.6)',
  },
  '.cm-selectionMatch': {
    backgroundColor: 'rgba(255, 255, 255, 0.2)',
    borderRadius: '2px',
  },

  // ── Snapshot mode (disable transitions, hide cursor/selection) ──
  '&.cm-snapshot-mode, &.cm-snapshot-mode *': {
    transition: 'none !important',
  },
  '&.cm-snapshot-mode .cm-cursorLayer': {
    display: 'none !important',
  },
  '&.cm-snapshot-mode .cm-selectionLayer': {
    display: 'none !important',
  },
  '&.cm-snapshot-mode .cm-md-marker': {
    fontSize: '0 !important',
    opacity: '0 !important',
  },
  '&.cm-snapshot-mode .cm-md-url': {
    fontSize: '0 !important',
    opacity: '0 !important',
  },

}, { dark: false });

// ─── Note Controls ──────────────────────────────────────────────────────────
// Note controls (color, opacity, pin) are now handled in Swift titlebar.
// This stub exists for backward compatibility with EditorBridge.

// Color hex map matching NoteColor.swift
const noteColorHex = {
  yellow: '#FFF9C4',
  pink: '#FCE4EC',
  blue: '#E3F2FD',
  green: '#E8F5E9',
  purple: '#F3E5F5',
  orange: '#FFF3E0',
};

window.initNoteControls = function (currentColor, currentOpacity, currentAlwaysOnTop) {
  // Set titlebar mask color to match note background
  window.setNoteColor(currentColor);
};

// Update titlebar mask color (called from Swift when color changes)
window.setNoteColor = function (color) {
  const mask = document.getElementById('titlebar-mask');
  if (mask) {
    mask.style.backgroundColor = noteColorHex[color] || noteColorHex.yellow;
  }
};

window.initColorPicker = window.initNoteControls;

// ─── Editor initialization ─────────────────────────────────────────────────

let editorView;
let debounceTimer;

function initEditor(initialContent = '') {
  log('Initializing editor...');

  const state = EditorState.create({
    doc: initialContent,
    extensions: [
      history(),
      keymap.of([...blockMathNavKeymap, ...formattingKeymap, ...searchKeymap, ...defaultKeymap, ...historyKeymap]),
      markdown({ extensions: GFM, codeLanguages: findLanguage }),
      syntaxHighlighting(markdownHighlightStyle),
      syntaxHighlighting(defaultHighlightStyle),  // Code block syntax colors
      markdownDecoPlugin,
      mathRenderField,
      search({ top: true }),
      highlightSelectionMatches(),
      editorTheme,
      EditorView.updateListener.of((update) => {
        if (update.docChanged && !suppressContentChange) {
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

  // Cmd+click to open links
  editorView.dom.addEventListener('click', (e) => {
    if (!e.metaKey) return;  // Only handle Cmd+click

    const pos = editorView.posAtCoords({ x: e.clientX, y: e.clientY });
    if (pos === null) return;

    // Find Link node at position
    let url = null;
    syntaxTree(editorView.state).iterate({
      from: pos,
      to: pos,
      enter(node) {
        if (node.name === 'Link') {
          // Find URL child node
          let urlNode = node.node.getChild('URL');
          if (urlNode) {
            url = editorView.state.sliceDoc(urlNode.from, urlNode.to);
          }
        }
      },
    });

    if (url) {
      e.preventDefault();
      // Send to Swift to open URL
      sendToBridge('openURL', { url });
      log('Opening URL: ' + url);
    }
  });

  log('Editor ready');

  // GFM verification: test parse after a short delay
  setTimeout(() => {
    const testState = EditorState.create({
      doc: '- [x] test\n~~strike~~',
      extensions: [markdown({ extensions: GFM })],
    });
    const nodes = [];
    syntaxTree(testState).iterate({ enter(n) { nodes.push(n.name); } });
    log('GFM nodes: ' + nodes.join(', '));
  }, 500);
}

// ─── Swift bridge interface ────────────────────────────────────────────────

window.setContent = function (content) {
  if (!editorView) return;
  clearTimeout(debounceTimer);
  suppressContentChange = true;
  editorView.dispatch(
    editorView.state.update({
      changes: { from: 0, to: editorView.state.doc.length, insert: content },
    })
  );
  suppressContentChange = false;
};

window.getContent = function () {
  return editorView ? editorView.state.doc.toString() : '';
};

// Open search panel (called from Swift via Cmd+F menu)
window.openSearch = function () {
  if (!editorView) return;
  openSearchPanel(editorView);
  // Remove show-replace class if present (search only)
  setTimeout(() => {
    const panel = document.querySelector('.cm-panel.cm-search');
    if (panel) panel.classList.remove('show-replace');
  }, 10);
};

// Open search panel with replace visible (Cmd+Shift+F)
window.openSearchWithReplace = function () {
  if (!editorView) return;
  openSearchPanel(editorView);
  // Add show-replace class to reveal replace inputs
  setTimeout(() => {
    const panel = document.querySelector('.cm-panel.cm-search');
    if (panel) {
      panel.classList.add('show-replace');
      // Focus the replace input
      const replaceInput = panel.querySelector('input[name="replace"]');
      if (replaceInput) replaceInput.focus();
    }
  }, 10);
};

// Get current cursor position (character offset)
window.getCursorPosition = function () {
  return editorView ? editorView.state.selection.main.head : 0;
};

// Set cursor position and scroll into view
window.setCursorPosition = function (pos) {
  if (!editorView) return;
  const docLength = editorView.state.doc.length;
  const safePos = Math.min(Math.max(0, pos), docLength);
  editorView.dispatch({
    selection: { anchor: safePos, head: safePos },
    scrollIntoView: true,
  });
};

// Get current scroll position (pixels from top)
window.getScrollTop = function () {
  if (!editorView) return 0;
  return editorView.scrollDOM.scrollTop;
};

// Set scroll position
window.setScrollTop = function (top) {
  if (!editorView) return;
  editorView.scrollDOM.scrollTop = top;
};

// Debug: dump syntax tree nodes
window.dumpTree = function () {
  if (!editorView) return;
  const nodes = [];
  syntaxTree(editorView.state).iterate({
    enter(node) {
      const text = editorView.state.sliceDoc(node.from, Math.min(node.to, node.from + 30));
      nodes.push(`${node.name} [${node.from}-${node.to}] "${text}"`);
    }
  });
  console.log(nodes.join('\n'));
};

// ─── Shared WebView APIs ────────────────────────────────────────────────────

// Set the current note ID (called from Swift before loading content)
window.setCurrentNoteId = function (id) {
  currentNoteId = id;
};

// Serialize current editor state to JSON (doc + selection + scroll)
window.serializeState = function () {
  if (!editorView) return null;
  const doc = editorView.state.doc.toString();
  const sel = editorView.state.selection.main;
  const scrollTop = editorView.scrollDOM.scrollTop;
  return JSON.stringify({
    doc,
    anchor: sel.anchor,
    head: sel.head,
    scrollTop,
  });
};

// Restore editor state from JSON
window.restoreState = function (json) {
  if (!editorView || !json) return;
  try {
    const s = typeof json === 'string' ? JSON.parse(json) : json;
    const doc = s.doc || '';
    const docLength = doc.length;
    const anchor = Math.min(Math.max(0, s.anchor || 0), docLength);
    const head = Math.min(Math.max(0, s.head || 0), docLength);
    clearTimeout(debounceTimer);
    suppressContentChange = true;
    editorView.dispatch({
      changes: { from: 0, to: editorView.state.doc.length, insert: doc },
      selection: EditorSelection.single(anchor, head),
    });
    suppressContentChange = false;
    if (s.scrollTop > 0) {
      requestAnimationFrame(() => {
        editorView.scrollDOM.scrollTop = s.scrollTop;
      });
    }
  } catch (e) {
    console.error('[Editor] restoreState error:', e);
  }
};

window.focusEditor = function () {
  if (editorView) editorView.focus();
};

// Prepare for snapshot: disable transitions, collapse all cursor-unfolds, hide cursor.
// Does NOT scroll — preserves the user's viewport for an accurate snapshot.
window.prepareForSnapshot = function () {
  if (!editorView) return;
  snapshotMode = true;
  editorView.dom.classList.add('cm-snapshot-mode');
  editorView.dispatch({
    selection: EditorSelection.single(0, 0),
  });
  editorView.contentDOM.blur();
};

// Set content and prepare for snapshot in one call — single transaction, single DOM update.
// Used by pre-rendering to eliminate intermediate states between setContent and prepareForSnapshot.
window.setContentForSnapshot = function (content) {
  if (!editorView) return;
  clearTimeout(debounceTimer);
  suppressContentChange = true;
  snapshotMode = true;
  editorView.dom.classList.add('cm-snapshot-mode');
  editorView.dispatch(
    editorView.state.update({
      changes: { from: 0, to: editorView.state.doc.length, insert: content },
      selection: EditorSelection.single(0, 0),
    })
  );
  suppressContentChange = false;
  editorView.contentDOM.blur();
};

// Re-enable transitions and cursor unfold behavior after snapshot.
window.endSnapshotMode = function () {
  if (!editorView) return;
  snapshotMode = false;
  editorView.dom.classList.remove('cm-snapshot-mode');
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
