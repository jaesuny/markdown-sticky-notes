// Simple CodeMirror 6 with CSS-based markdown styling

import { EditorState } from '@codemirror/state';
import { EditorView, keymap } from '@codemirror/view';
import { defaultKeymap, history, historyKeymap } from '@codemirror/commands';
import { markdown, markdownLanguage } from '@codemirror/lang-markdown';
import { languages } from '@codemirror/language-data';
import { syntaxHighlighting, defaultHighlightStyle } from '@codemirror/language';
import katex from 'katex';
import 'katex/dist/katex.min.css';

// Bridge
function sendToBridge(action, data = {}) {
  if (window.webkit?.messageHandlers?.bridge) {
    try {
      window.webkit.messageHandlers.bridge.postMessage({ action, ...data });
    } catch (error) {
      console.error('Bridge error:', error);
    }
  }
}

function log(message) {
  console.log('[Editor]', message);
  sendToBridge('log', { message });
}

// Log all CSS classes applied to lines
function debugLineClasses(view) {
  const doc = view.state.doc;
  for (let i = 1; i <= doc.lines; i++) {
    const line = doc.line(i);
    const lineText = line.text;
    if (lineText.startsWith('#')) {
      console.log(`Line ${i}: "${lineText}"`);
      // Find the DOM element for this line
      const lineElement = view.domAtPos(line.from);
      if (lineElement.node) {
        const parent = lineElement.node.parentElement;
        console.log('  Classes:', parent?.className);
        console.log('  HTML:', parent?.outerHTML?.substring(0, 200));
      }
    }
  }
}

// Keyboard shortcuts
const macOSKeymap = [
  { key: 'Mod-ArrowUp', run: view => {
    view.dispatch(view.state.update({ selection: { anchor: 0, head: 0 } }));
    return true;
  }},
  { key: 'Mod-ArrowDown', run: view => {
    const end = view.state.doc.length;
    view.dispatch(view.state.update({ selection: { anchor: end, head: end } }));
    return true;
  }},
  { key: 'Mod-Shift-ArrowUp', run: view => {
    const { head } = view.state.selection.main;
    view.dispatch(view.state.update({ selection: { anchor: head, head: 0 } }));
    return true;
  }},
  { key: 'Mod-Shift-ArrowDown', run: view => {
    const { head } = view.state.selection.main;
    const end = view.state.doc.length;
    view.dispatch(view.state.update({ selection: { anchor: head, head: end } }));
    return true;
  }},
  { key: 'Mod-b', run: view => { wrapSelection(view, '**', '**'); return true; }},
  { key: 'Mod-i', run: view => { wrapSelection(view, '*', '*'); return true; }},
  { key: 'Mod-k', run: view => { wrapSelection(view, '[', '](url)'); return true; }},
  { key: 'Mod-e', run: view => { wrapSelection(view, '`', '`'); return true; }},
  { key: 'Mod-s', run: view => { sendToBridge('requestSave'); return true; }},
  // Debug key
  { key: 'Mod-d', run: view => {
    console.log('=== DEBUG ===');
    debugLineClasses(view);
    return true;
  }},
];

function wrapSelection(view, before, after) {
  const { state, dispatch } = view;
  const { from, to } = state.selection.main;
  const selectedText = state.doc.sliceString(from, to);
  dispatch(state.update({
    changes: { from, to, insert: before + selectedText + after },
    selection: { anchor: from + before.length, head: to + before.length }
  }));
}

// VERY AGGRESSIVE CSS THEME
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
  '.cm-line': {
    lineHeight: '1.8',
    padding: '4px 0',
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

  // Try ALL possible heading class names
  '.cm-heading, .ͼ2.cm-heading, .ͼd, .ͼe, .ͼf, .ͼg, .ͼh, .ͼi': {
    backgroundColor: 'yellow !important',
    color: 'red !important',
    fontSize: '2em !important',
    fontWeight: '900 !important',
    display: 'block !important',
  },

  // Target by line content (this might not work but worth trying)
  '.cm-line:has(.cm-heading)': {
    backgroundColor: 'yellow !important',
    fontSize: '2em !important',
  },

  // Try the ATX syntax tree node names
  '.ͼ2': { fontSize: '2em !important', fontWeight: '900 !important', color: 'red !important' },
  '.ͼ3': { fontSize: '1.8em !important', fontWeight: '900 !important', color: 'orange !important' },
  '.ͼ4': { fontSize: '1.6em !important', fontWeight: '900 !important', color: 'green !important' },

  // Bold and italic
  '.cm-strong, .ͼj': {
    fontWeight: '900 !important',
    color: 'blue !important',
  },
  '.cm-emphasis, .ͼk': {
    fontStyle: 'italic !important',
    color: 'purple !important',
  },

  // Inline code
  '.cm-code, .cm-monospace': {
    fontFamily: '"SF Mono", Monaco, monospace !important',
    backgroundColor: 'rgba(92, 106, 196, 0.2) !important',
    padding: '2px 6px !important',
    borderRadius: '4px !important',
    fontSize: '0.9em !important',
    color: '#c7254e !important',
  },

  // Links
  '.cm-link': {
    color: '#5c6ac4 !important',
    textDecoration: 'underline !important',
  },

  // Lists
  '.cm-list': {
    color: '#5c6ac4 !important',
    fontWeight: '600 !important',
  },
}, { dark: false });

const darkTheme = EditorView.theme({
  '.cm-content': {
    color: '#e0e0e0',
    caretColor: '#8c9eff',
  },
  '.cm-cursor': {
    borderLeftColor: '#8c9eff',
  },
}, { dark: true });

// Editor
let editorView;
let debounceTimer;

function initEditor(initialContent = '') {
  log('Initializing editor with aggressive CSS...');

  const startState = EditorState.create({
    doc: initialContent,
    extensions: [
      history(),
      keymap.of([...macOSKeymap, ...defaultKeymap, ...historyKeymap]),
      markdown({
        base: markdownLanguage,
        codeLanguages: languages,
      }),
      syntaxHighlighting(defaultHighlightStyle),
      editorTheme,
      window.matchMedia('(prefers-color-scheme: dark)').matches ? darkTheme : [],
      EditorView.updateListener.of(update => {
        if (update.docChanged) {
          clearTimeout(debounceTimer);
          debounceTimer = setTimeout(() => {
            sendToBridge('contentChanged', { content: update.state.doc.toString() });
          }, 300);

          // Auto-debug on change
          if (update.state.doc.toString().includes('#')) {
            console.log('Document contains #, checking classes...');
            setTimeout(() => debugLineClasses(editorView), 100);
          }
        }
      }),
      EditorView.lineWrapping,
    ]
  });

  editorView = new EditorView({
    state: startState,
    parent: document.getElementById('editor-container')
  });

  log('Editor ready! Press Cmd+D to debug line classes');

  // Expose for debugging
  window.editor = editorView;
  window.debugLines = () => debugLineClasses(editorView);
}

// Expose
window.setContent = function(content) {
  if (editorView) {
    editorView.dispatch(editorView.state.update({
      changes: { from: 0, to: editorView.state.doc.length, insert: content }
    }));
    log('Content set: ' + content.length + ' chars');
  }
};

window.getContent = function() {
  return editorView ? editorView.state.doc.toString() : '';
};

// Init
document.addEventListener('DOMContentLoaded', () => {
  log('DOM ready');
  initEditor();
  sendToBridge('ready');
  setTimeout(() => {
    editorView.focus();
    log('Ready! Type "# heading" and press Cmd+D to debug');
  }, 100);
});

window.addEventListener('error', (e) => {
  console.error('ERROR:', e);
  sendToBridge('error', { message: e.message });
});

log('Script loaded');
