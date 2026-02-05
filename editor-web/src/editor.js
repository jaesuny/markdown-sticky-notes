// CodeMirror 6 Markdown Editor with Live Preview and Math Support

import { EditorState, StateField } from '@codemirror/state';
import { EditorView, keymap, Decoration, WidgetType } from '@codemirror/view';
import { defaultKeymap, history, historyKeymap } from '@codemirror/commands';
import { markdown, markdownLanguage } from '@codemirror/lang-markdown';
import { syntaxHighlighting, defaultHighlightStyle } from '@codemirror/language';
// Don't use language-data - it causes dynamic imports
import katex from 'katex';
import 'katex/dist/katex.min.css';

// Bridge helper functions
function sendToBridge(action, data = {}) {
  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.bridge) {
    try {
      window.webkit.messageHandlers.bridge.postMessage({
        action: action,
        ...data
      });
    } catch (error) {
      console.error('Bridge error:', error);
    }
  }
}

function log(message) {
  console.log('[Editor]', message);
  sendToBridge('log', { message: message });
}

// Math Widget
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
        displayMode: this.isBlock
      });
    } catch (e) {
      console.error(`[KaTeX] Error rendering "${this.formula}":`, e.message);
      wrap.textContent = this.formula;
      wrap.className += ' cm-math-error';
    }

    return wrap;
  }

  ignoreEvent() {
    return false;
  }
}

// Inline code widget
class InlineCodeWidget extends WidgetType {
  constructor(code) {
    super();
    this.code = code;
  }

  eq(other) {
    return other.code === this.code;
  }

  toDOM() {
    const span = document.createElement('span');
    span.className = 'cm-code-widget';
    span.textContent = this.code;
    span.style.fontFamily = 'Monaco, Menlo, "Courier New", Courier, monospace';
    span.style.backgroundColor = 'rgba(175, 184, 193, 0.2)';
    span.style.padding = '2px 4px';
    span.style.borderRadius = '3px';
    span.style.fontSize = '0.9em';
    return span;
  }

  ignoreEvent() {
    return false;
  }
}

// Headings are rendered via CSS, not widgets

// Build decorations for code and math rendering
function buildDecorations(state) {
  const widgets = [];
  const doc = state.doc;
  const text = doc.toString();

  // 1. Inline code: `code`
  const inlineCodeRegex = /`([^`\n]*)`/g;
  let match;
  while ((match = inlineCodeRegex.exec(text)) !== null) {
    widgets.push(
      Decoration.replace({
        widget: new InlineCodeWidget(match[1])
      }).range(match.index, match.index + match[0].length)
    );
  }

  // 2. Block math (multiline): $$\n...\n$$
  // 한글이 포함된 경우 건너뛰기 (KaTeX는 한글 지원 안 함)
  const blockMathRegex = /\$\$[\s\S]*?\$\$/g;
  while ((match = blockMathRegex.exec(text)) !== null) {
    const formula = match[0].replace(/^\$\$\s*/, '').replace(/\s*\$\$$/, '').trim();
    // 한글 체크: 한글이 있으면 렌더링하지 않음
    if (formula.length > 0 && !/[ㄱ-ㅎ|ㅏ-ㅣ|가-힣]/.test(formula)) {
      widgets.push(
        Decoration.replace({
          widget: new MathWidget(formula, true),
          block: true
        }).range(match.index, match.index + match[0].length)
      );
    }
  }

  // 3. Inline math: $x^2$
  const inlineMathRegex = /(?<!\$)\$(?!\$)([^\$\n]+?)\$(?!\$)/g;
  // Reset regex
  inlineMathRegex.lastIndex = 0;
  while ((match = inlineMathRegex.exec(text)) !== null) {
    const formula = match[1].trim();
    // 한글이 있거나 빈 문자열이면 건너뛰기
    if (formula.length === 0 || /[ㄱ-ㅎ|ㅏ-ㅣ|가-힣]/.test(formula)) continue;

    widgets.push(
      Decoration.replace({
        widget: new MathWidget(formula, false)
      }).range(match.index, match.index + match[0].length)
    );
  }

  return Decoration.set(widgets, true);
}

// StateField for math and code rendering
const mathRenderField = StateField.define({
  create(state) {
    return buildDecorations(state);
  },

  update(decorations, tr) {
    if (!tr.docChanged) {
      return decorations.map(tr.changes);
    }
    return buildDecorations(tr.state);
  },

  provide(field) {
    return EditorView.decorations.from(field);
  }
});

// macOS keyboard shortcuts
const macOSKeymap = [
  { key: 'Mod-ArrowUp', run: view => {
    const { state, dispatch } = view;
    dispatch(state.update({ selection: { anchor: 0, head: 0 } }));
    return true;
  }},
  { key: 'Mod-ArrowDown', run: view => {
    const { state, dispatch } = view;
    const end = state.doc.length;
    dispatch(state.update({ selection: { anchor: end, head: end } }));
    return true;
  }},
  { key: 'Mod-Shift-ArrowUp', run: view => {
    const { state, dispatch } = view;
    const { head } = state.selection.main;
    dispatch(state.update({ selection: { anchor: head, head: 0 } }));
    return true;
  }},
  { key: 'Mod-Shift-ArrowDown', run: view => {
    const { state, dispatch } = view;
    const { head } = state.selection.main;
    const end = state.doc.length;
    dispatch(state.update({ selection: { anchor: head, head: end } }));
    return true;
  }},
  { key: 'Mod-b', run: view => {
    wrapSelection(view, '**', '**');
    return true;
  }},
  { key: 'Mod-i', run: view => {
    wrapSelection(view, '*', '*');
    return true;
  }},
  { key: 'Mod-k', run: view => {
    wrapSelection(view, '[', '](url)');
    return true;
  }},
  { key: 'Mod-e', run: view => {
    wrapSelection(view, '`', '`');
    return true;
  }},
  { key: 'Mod-s', run: view => {
    sendToBridge('requestSave');
    return true;
  }},
];

function wrapSelection(view, before, after) {
  const { state, dispatch } = view;
  const { from, to } = state.selection.main;
  const selectedText = state.doc.sliceString(from, to);
  const replacement = before + selectedText + after;

  dispatch(state.update({
    changes: { from, to, insert: replacement },
    selection: { anchor: from + before.length, head: to + before.length }
  }));
}

// Editor theme with very visible heading styles
const editorTheme = EditorView.theme({
  '&': {
    fontSize: '14px',
    height: '100%',
    backgroundColor: 'transparent',
  },
  '.cm-content': {
    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
    padding: '16px',
    minHeight: '100%',
    caretColor: '#5c6ac4',
  },
  // Force monospace for all code-related elements
  '.cm-content .cm-line:has(code), .cm-content code': {
    fontFamily: 'Monaco, Menlo, "Courier New", Courier, monospace !important',
  },
  '.cm-line': {
    lineHeight: '1.8',
    padding: '2px 0',
  },
  '.cm-scroller': {
    overflow: 'auto',
  },
  '&.cm-focused': {
    outline: 'none',
  },
  '.cm-cursor': {
    borderLeftColor: '#5c6ac4',
  },

  // Math styling
  '.cm-math-inline': {
    backgroundColor: 'rgba(92, 106, 196, 0.1)',
    padding: '2px 6px',
    borderRadius: '4px',
    margin: '0 2px',
    display: 'inline-block',
  },
  '.cm-math-block': {
    backgroundColor: 'rgba(92, 106, 196, 0.05)',
    padding: '16px',
    borderRadius: '8px',
    margin: '12px 0',
    display: 'block',
    overflow: 'auto',
  },
  '.cm-math-error': {
    color: '#d73a49',
    backgroundColor: 'rgba(215, 58, 73, 0.1)',
  },

  // Heading styles - Obsidian-like
  // CodeMirror adds .cm-heading-N classes automatically
  '.cm-line:has(.cm-headerMark)': {
    fontWeight: '700',
    lineHeight: '1.4',
  },
  '.cm-line:has(.cm-atx-1)': {
    fontSize: '2em',
    fontWeight: '700',
    marginTop: '16px',
    marginBottom: '8px',
  },
  '.cm-line:has(.cm-atx-2)': {
    fontSize: '1.5em',
    fontWeight: '700',
    marginTop: '14px',
    marginBottom: '6px',
  },
  '.cm-line:has(.cm-atx-3)': {
    fontSize: '1.25em',
    fontWeight: '700',
    marginTop: '12px',
    marginBottom: '4px',
  },
  '.cm-line:has(.cm-atx-4)': {
    fontSize: '1.1em',
    fontWeight: '700',
  },
  '.cm-line:has(.cm-atx-5)': {
    fontSize: '1em',
    fontWeight: '700',
  },
  '.cm-line:has(.cm-atx-6)': {
    fontSize: '0.95em',
    fontWeight: '700',
  },
  // Hide the ### markers
  '.cm-headerMark': {
    opacity: 0.3,
  },

  // Markdown syntax highlighting
  '.cm-strong': {
    fontWeight: '700',
    color: '#1a1a1a',
  },
  '.cm-emphasis': {
    fontStyle: 'italic',
  },
  '.cm-link': {
    color: '#5c6ac4',
    textDecoration: 'underline',
  },
}, { dark: false });

// Dark theme
const darkTheme = EditorView.theme({
  '.cm-content': {
    color: '#e0e0e0',
    caretColor: '#8c9eff',
  },
  '.cm-cursor': {
    borderLeftColor: '#8c9eff',
  },
  '.cm-heading': {
    color: '#e0e0e0',
  },
  '.cm-heading-1, .cm-heading-2': {
    borderBottomColor: '#404040',
  },
  '.cm-strong': {
    color: '#e0e0e0',
  },
}, { dark: true });

// Initialize editor
let editorView;
let debounceTimer;

function initEditor(initialContent = '') {
  log('Creating editor state...');

  const startState = EditorState.create({
    doc: initialContent,
    extensions: [
      history(),
      keymap.of([
        ...macOSKeymap,
        ...defaultKeymap,
        ...historyKeymap,
      ]),
      markdown({
        base: markdownLanguage,
        // codeLanguages disabled to avoid dynamic imports
      }),
      syntaxHighlighting(defaultHighlightStyle),
      mathRenderField,  // StateField for code and math rendering
      editorTheme,
      window.matchMedia('(prefers-color-scheme: dark)').matches ? darkTheme : [],
      EditorView.updateListener.of(update => {
        if (update.docChanged) {
          clearTimeout(debounceTimer);
          debounceTimer = setTimeout(() => {
            const content = update.state.doc.toString();
            sendToBridge('contentChanged', { content });
          }, 300);
        }
      }),
      EditorView.lineWrapping,
    ]
  });

  log('Creating editor view...');

  editorView = new EditorView({
    state: startState,
    parent: document.getElementById('editor-container')
  });

  log('Editor created successfully!');
  console.log('Editor object:', editorView);
}

// Expose to Swift
window.setContent = function(content) {
  if (editorView) {
    const transaction = editorView.state.update({
      changes: { from: 0, to: editorView.state.doc.length, insert: content }
    });
    editorView.dispatch(transaction);
    log('Content set: ' + content.length + ' characters');
  }
};

window.getContent = function() {
  return editorView ? editorView.state.doc.toString() : '';
};

// Debug function
window.testHeading = function() {
  console.log('=== TEST HEADING ===');
  const testContent = '# Test Heading\n\nSome text here.';
  window.setContent(testContent);
  console.log('Content set to:', testContent);
  console.log('Editor state:', editorView.state.doc.toString());
};

// Initialize
document.addEventListener('DOMContentLoaded', () => {
  log('DOM ready, initializing editor...');
  initEditor();
  sendToBridge('ready');

  setTimeout(() => {
    editorView.focus();
    log('Editor focused');

    // Debug: Type backtick code backtick and log classes
    setTimeout(() => {
      window.debugCodeClasses = () => {
        console.log('=== DEBUGGING DECORATION ===');

        const lines = document.querySelectorAll('.cm-line');
        lines.forEach(line => {
          if (line.textContent.includes('`')) {
            console.log('--- Line with backtick ---');
            console.log('Text:', line.textContent);
            console.log('HTML:', line.innerHTML);

            // Check for cm-inline-code class
            const codeSpans = line.querySelectorAll('.cm-inline-code');
            console.log('.cm-inline-code elements found:', codeSpans.length);
            codeSpans.forEach((span, i) => {
              console.log(`  [${i}]:`, {
                tag: span.tagName,
                text: span.textContent,
                innerHTML: span.innerHTML.substring(0, 50),
                font: window.getComputedStyle(span).fontFamily
              });
            });
          }
        });
      };
      log('Type `code` and call window.debugCodeClasses() to see classes');
    }, 1000);
  }, 100);
});

window.addEventListener('error', (e) => {
  console.error('ERROR:', e);
  sendToBridge('error', { message: 'Error: ' + e.message });
});

log('Editor script loaded - ready for markdown rendering!');
