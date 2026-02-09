# CLAUDE.md

## Build & Run

```bash
./build-app.sh                # Full build: webpack → Swift → .app bundle
open build/StickyNotes.app    # Run
```

Prerequisites: macOS 12+, Swift 5.9+, Node.js 18+. First time: `cd editor-web && npm install`

### Dev Workflow

```bash
# Full rebuild (Swift + JS)
./build-app.sh && open build/StickyNotes.app

# JS-only fast iteration (requires .app already built)
cd editor-web && npm run build && cp dist/editor.bundle.js ../build/StickyNotes.app/Contents/Resources/Editor/ && open ../build/StickyNotes.app
```

## Architecture

Hybrid native + web macOS app:
- **Swift/SwiftUI**: App shell, NSPanel windows, UserDefaults persistence
- **Single shared WKWebView + CodeMirror 6**: Markdown editor with KaTeX math — one WKWebView reparented to the active (key) window, inactive windows show snapshots
- **Bridge**: `WKScriptMessageHandler` bidirectional messaging

### Editor Rendering (editor-web/src/editor.js)

Three-layer system:

1. **ViewPlugin** (`markdownDecoPlugin`) — syntax tree 기반
   - `syntaxTree(state).iterate()` 로 Lezer 파서 노드 순회
   - `Decoration.line()` → 헤딩 font-size, 코드블록 배경, 블록쿼트 스타일, HR
   - `Decoration.mark()` → 볼드, 이탤릭, 링크, 마커 흐리게
   - `Decoration.replace()` → 인라인 코드 위젯 (커서 unfold 지원)

2. **StateField** (`mathRenderField`) — 수식 전용
   - 블록 수식 `$$...$$`: 멀티라인 `Decoration.replace({ block: true })` — ViewPlugin에서는 불가
   - 인라인 수식 `$...$`: regex 매칭 (Lezer는 `$` 미인식)
   - `collectCodeRanges()` 로 코드블록 내부 `$` 무시
   - 선택 변경 시에도 재계산 (`tr.selection` 체크)

3. **HighlightStyle** — 보조 토큰 색상 (파싱 완료 전 기본 스타일)

### Cursor Unfold Pattern

`Decoration.replace()` 사용 시 커서가 범위 안에 있으면 위젯 대신 원본 소스 표시:
```javascript
const { from: curFrom, to: curTo } = state.selection.main;
function cursorInside(from, to) { return curFrom >= from && curTo <= to; }
if (cursorInside(node.from, node.to)) break; // skip replace, show raw
```
적용 대상: InlineCode, 인라인/블록 수식, HR, TaskMarker

### Single WKWebView Architecture

```
Before: Window1[WKWebView] Window2[WKWebView] Window3[WKWebView]  (~125MB for 5 notes)
After:  Window1[Snapshot]  Window2[WKWebView]  Window3[Snapshot]   (~30MB for 5 notes)
                           (active/key window)
```

- **SharedWebViewManager** (singleton): 단일 WKWebView 소유, EditorState 직렬화/복원으로 노트 전환
- **NoteWindowController**: `windowDidBecomeKey` → blur→snapshot→move WebView chain
- **editor.js**: `serializeState()`/`restoreState(json)` API, `noteId` 기반 bridge 메시지

**Pre-rendering**: `markReady()`에서 WebView alpha=0 상태로 비활성 노트 순차 렌더링+스냅샷. `suppressContentChange`로 contentChanged 디바운스 억제 필수 (없으면 active note 콘텐츠 덮어쓰기).

Window switch flow (synchronous): `takeSnapshot()` via RunLoop spin (WebView stays in old window, max 100ms) → show snapshot on old window → move WebView to new window → `switchToNote()` → reveal after 150ms + `focusEditor()`

### Key Files

```
editor-web/src/editor.js          # 에디터 전체 (ViewPlugin + StateField + theme)
editor-web/webpack.config.cjs     # 단일 번들, 폰트 base64 인라인
Sources/StickyNotes/App/SharedWebViewManager.swift       # 단일 WKWebView 소유, 노트 전환 (stateCache)
Sources/StickyNotes/Bridge/SharedEditorBridge.swift      # noteId 기반 Swift-JS 메시지 라우팅
Sources/StickyNotes/Views/NoteWindow/NoteWindowController.swift  # WebView reparent, snapshot/preview
Sources/StickyNotes/App/AppCoordinator.swift             # 앱 조율 (Combine)
```

### Swift-JS Bridge

- **JS → Swift**: `sendToBridge(action, data)` → `ready`, `contentChanged`, `requestSave`, `log`, `error` — 모든 메시지에 `noteId` 포함
- **Swift → JS**: `window.setContent(content)`, `window.getContent()`, `window.openSearch()`, `window.serializeState()`, `window.restoreState(json)`, `window.setCurrentNoteId(id)`, `window.prepareForSnapshot()` (snapshotMode + transitions 끄고 커서→0 + blur), `window.endSnapshotMode()` (snapshotMode 해제 + transitions 복원)
- Console.log 인터셉트: `WKUserScript` at document start → Swift 콘솔로 전달

## Implementation Status

- **Phase 1 ✅**: App structure, NSPanel windows, persistence, WKWebView
- **Phase 2 ✅**: CodeMirror 6, syntax tree decorations, KaTeX math, cursor unfold
- **Phase 3 ✅**: 추가 마크다운 요소 (취소선, 리스트 스타일, 체크박스 위젯, 테이블)
- **Phase 4 ✅**: Titlebar 컨트롤 (핀/투명도/색깔), Always-on-top, Cmd+F/Cmd+Shift+F 검색
- **Phase 5 ✅**: Single shared WKWebView 아키텍처 (메모리 ~80% 절감)
- **Phase 6 (진행중)**: 디자인 개선, 버그 수정, Known Issues 해결

## Gotchas

1. **`Decoration.line()` CSS**: 클래스가 `.cm-line` 요소에 직접 추가됨 — `&light .cm-heading-1` 같은 스코프 접두사 사용하면 안 됨, `.cm-heading-1`로 직접 사용
2. **ViewPlugin vs StateField**: 줄바꿈 포함 `Decoration.replace()`는 반드시 StateField. ViewPlugin에서 하면 "line break" 에러
3. **`atomicRanges` 주의**: 모든 decoration에 적용하면 커서가 여러 블록을 건너뜀 — 블록 수식 네비게이션은 커스텀 키맵(`blockMathNavKeymap`)으로 처리
4. **regex vs syntax tree**: 인라인 코드 regex는 펜스드 코드블록 내부와 충돌 — `syntaxTree().iterate()`의 노드명(`InlineCode`, `FencedCode` 등) 사용
5. **HighlightStyle 한계**: `fontSize`는 span 레벨만 적용되어 헤딩 라인 전체에 효과 없음 — `Decoration.line()` + CSS 클래스로 해결
6. **WKWebView 리소스**: `loadFileURL()`에 Resources 디렉토리 전체 read access 필요 (KaTeX 폰트)
7. **Webpack 단일 번들**: `splitChunks: false`, 폰트 `asset/inline` — WKWebView는 청크/외부 파일 로딩 불가
8. **~~한글 수식 필터~~** (제거됨): KaTeX `strict: false`로 충분. 한글이 포함된 수식도 렌더링 시도 — 에러 시 KaTeX가 에러 메시지 표시
9. **`defaultKeymap` macOS 바인딩**: Cmd+Arrow, Cmd+Shift+Arrow, Opt+Arrow 등 이미 포함됨 — 커스텀 핸들러로 재정의하면 scrollIntoView, goal column 등 네이티브 동작이 깨짐. 포맷팅 키(Cmd+B/I/K)만 추가할 것
10. **`markdown({ base: markdownLanguage })` GFM 손실**: `parser.configure()` 내부 호출이 GFM 확장을 덮어씀 — `import { GFM } from '@lezer/markdown'` 후 `markdown({ extensions: GFM })` 사용
11. **NSWindow 이중 close**: `windowWillClose` → `closeWindow()` → `close()` → `windowWillClose` 무한 재귀 — `windowWillClose`에서는 `removeWindow()`(딕셔너리 제거만), `closeWindow()`는 `syncWindowsWithNotes`에서만 사용
12. **macOS 메뉴 단축키 가로채기**: Cmd+F 등 시스템 단축키는 WKWebView에 도달 전 메뉴 바에서 소비됨 — `CommandGroup(replacing: .textEditing)`로 Swift 메뉴에서 잡아 `evaluateJavaScript("window.openSearch()")`로 JS에 전달하는 패턴 사용
13. **검색 패널 색상**: `rgba(0,0,0,alpha)` 텍스트 색상은 어떤 배경에서든 회색으로 보임 — 버튼/레이블/체크박스는 `color: inherit` + `opacity` 또는 `currentColor`로 부모 텍스트 색 상속. hover 배경은 `rgba(255,255,255,alpha)` 밝은 방향으로
14. **`@codemirror/search` 패널 DOM**: `<br>`로 레이아웃 → `& br: { display: 'none' }` + `display: flex` 적용. 체크박스는 `<label>` 안에 `<input type=checkbox>`. 닫기 버튼은 `button[name="close"]`. `style-mod`이 `&` 중첩 셀렉터 지원
15. **타이틀바 커스텀 버튼**: `NSTitlebarAccessoryViewController` + `.layoutAttribute = .right`로 타이틀바 우측에 버튼 추가. `titlebarAppearsTransparent = true`와 함께 사용 시 윈도우 배경색 위에 자연스럽게 표시
16. **WKWebView 커서 제어**: AppKit의 `resetCursorRects`, `cursorUpdate`는 WKWebView가 내부적으로 무시함 — HTML `<div>`에 `cursor: default` + `pointer-events: auto`로 시도. 단, overlay가 콘텐츠 영역 덮으면 클릭 좌표 어긋남
17. **NSPanel 최소 크기**: traffic lights (~70px) + `NSTitlebarAccessoryViewController` 너비 합산 + 여유분. 예: 슬라이더(50) + 핀(18) + 색깔점(12×6) = 약 190px → 최소 너비 280px
18. **검색 패널 버튼/체크박스 타겟팅**: `button[name="select"]` (All), `button[name="replace"]`, `input[name="re"]` (regexp), `input[name="word"]`, `input[name="case"]`. CSS `:has()` 셀렉터로 부모 label 선택: `label:has(input[name="re"])`
19. **검색 Replace 토글 패턴**: CSS로 replace 요소 기본 숨김, `.show-replace` 클래스로 표시. JS에서 `panel.classList.add('show-replace')` 토글. Cmd+F vs Cmd+Shift+F 분리 구현
20. **Syntax Highlighting codeLanguages**: `markdown({ codeLanguages: fn })`의 함수는 `Language` 객체 반환 필요. `javascript()` 등은 `LanguageSupport` 반환하므로 `.language` 속성 사용: `return langSupport.language`
21. **언어 패키지 정적 import**: `@codemirror/language-data`는 동적 import로 청크 생성 → WKWebView 불가. `@codemirror/lang-javascript` 등 개별 패키지 직접 import
22. **마커 숨기기 (Obsidian 스타일)**: ViewPlugin에서 커서 라인에 `cm-cursor-line` 클래스 추가, CSS로 `.cm-md-marker { font-size: 0; opacity: 0 }` + `.cm-cursor-line .cm-md-marker { font-size: inherit; opacity: 0.35 }`. 대상: `EmphasisMark`, `QuoteMark`, `CodeMark`, `CodeInfo`. **`HeaderMark` 주의**: 줄 시작의 여는 `#`만 마커 처리 (`node.from === line.from`), trailing `#`은 `cm-md-marker-trailing` + `color: inherit !important`로 헤딩 텍스트 색 유지
23. **블록 수식 Overlay 패턴**: `Decoration.replace({ block: true })`는 클릭 좌표가 밀림. 해결: (1) 원본 줄에 `Decoration.line()`으로 `line-height` 동적 조정 (위젯높이/줄수), `color: transparent`, (2) 첫 줄에 `Decoration.widget({ side: -1 })`로 위젯 삽입, (3) 위젯 CSS `position: absolute`, `pointerEvents: none`. 핵심: 원본 줄 총 높이 = 위젯 높이
24. **CSS `color: transparent` + HighlightStyle 충돌**: 부모에 `color: transparent` 설정해도 HighlightStyle이 자식 `<span>`에 직접 color를 적용하여 무시됨. 해결: `.cm-math-source-line * { color: transparent !important }` + overlay는 `color: #000 !important`. Editing 시: `.cm-math-editing * { color: inherit !important }`로 복원 — `!important` 동일 시 더 구체적인 셀렉터가 이김
25. **EditorView.theme() 스코프 한계**: 테마 CSS는 `.cm-editor` 내부에서만 적용됨. 오프스크린 측정 시 테마 스타일(padding 등)이 적용 안됨 → inline style로 직접 설정 필요
26. **HR/단일라인 Overlay 패턴**: 블록 수식과 동일 원리. `HorizontalRule` 등 단일 라인도 CSS `line-height`만으로는 클릭 좌표 계산에 영향 없음 — `Decoration.line({ attributes: { style: 'height:16px;line-height:16px' } })` + `Decoration.widget()` 오버레이 조합 필요
27. **Block 요소 애니메이션 (수식/HR)**: Overlay 패턴에서 애니메이션 추가: (1) 소스 라인에 `color: transparent` + `transition`, (2) 위젯에 `opacity` + `transition`, (3) 커서 진입 시 `cm-*-editing` 클래스 토글로 소스 visible/위젯 fade out. `cursorInside()` 체크 후 데코레이션 제거 대신 클래스만 변경
28. **CSS 텍스트 노드 타겟 불가**: CodeMirror가 텍스트를 `<span>` 없이 직접 텍스트 노드로 렌더링하는 경우 있음. CSS는 텍스트 노드 선택 불가 → 부모 `.cm-line`에 `color: transparent` 적용하고 위젯에서 `color: #000 !important`로 오버라이드
29. **Inline 요소 애니메이션 한계**: `Decoration.replace()`는 소스를 DOM에서 제거 → crossfade 불가. `mark + widget` 조합은 sibling으로 배치되어 둘 다 공간 차지 → line-height 증가. `font-size: 0`도 레이아웃에 영향. Block은 `position: absolute` overlay 가능하지만 inline은 텍스트 흐름 때문에 불가. **현재 결론: inline math는 애니메이션 없이 즉시 전환**
30. **EditorView.theme()에서 @keyframes 미지원**: `style-mod` 라이브러리 기반이라 `@keyframes` 정의 불가 — `document.head.appendChild(style)`로 별도 `<style>` 요소에 keyframes 주입, theme에서는 `animation` 속성만 참조
31. **리스트 마커 위젯 패턴**: `ListMark` 노드를 `Decoration.replace()` + 커스텀 위젯으로 교체. Bullet은 `•` 문자, Ordered는 숫자 + `.`. `cursorOnLine()` 체크로 커서가 있을 때만 원본 마커 표시 (편집 가능). 다색 배경 대응: `color: inherit` + `opacity`로 어떤 파스텔 배경에서든 조화
32. **Single WKWebView 전환 순서**: 윈도우 전환 시 반드시 blur→snapshot→move 순서. WebView를 새 윈도우로 먼저 옮기면 구 윈도우가 빈 상태로 보임. `takeSnapshot()`은 WebView가 아직 구 윈도우에 있을 때 호출해야 올바른 크기/내용 캡처
33. **switchToNote 내 콘텐츠 추출**: `evaluateJavaScript("getContent()")` 별도 호출은 비동기 타이밍에 의해 새 노트의 content를 반환할 수 있음 — `serializeState()` JSON에서 `doc` 필드를 추출하는 방식으로 해결 (직렬화 시점에 캡처됨)
34. **windowDidResignKey 비움 패턴**: detach를 resignKey에서 하면 새 윈도우의 `attachWebView()`와 타이밍 경합 발생 — detach는 새 윈도우의 `attachWebView()` 내부에서만 수행. resignKey는 의도적으로 비워둠
35. **WKWebView 포커스 복원**: `makeFirstResponder(wv)` 만으로는 CodeMirror 에디터에 포커스가 안 감 — `evaluateJavaScript("window.focusEditor()")` 추가 호출 필요. `editorView.focus()`를 래핑한 JS API
36. **RunLoop spin으로 동기 스냅샷**: 비동기 `takeSnapshot` 체인은 타이밍 갭으로 빈 창/깜빡임 유발 — `flushCurrentNoteState()`와 동일한 RunLoop spin 패턴으로 동기적 처리. `RunLoop.current.run(mode: .default, before:)` 반복으로 콜백 수신 (최대 100ms)
37. **Pre-rendering 잘못된 콘텐츠 → `suppressContentChange`로 해결**: pre-rendering 중 `setContentForSnapshot()` → `dispatch()` → `updateListener` → `contentChanged` 디바운스 → `currentNoteId`가 null이라 `activeNoteId`로 라우팅 → active note의 콘텐츠가 pre-render 중인 노트의 것으로 덮어써짐. compositor 타이밍이 아니라 **bridge 메시지 라우팅 버그**. `suppressContentChange` 플래그로 프로그래밍적 콘텐츠 변경(`setContent`/`restoreState`/`setContentForSnapshot`) 시 `contentChanged` 발생 억제
38. **스냅샷 모드 (`cm-snapshot-mode`)**: `prepareForSnapshot()`은 JS 플래그 + CSS 이중 방어: (1) `snapshotMode=true` → `cursorInside()`/`cursorOnLine()` false, `cm-cursor-line` 미추가, (2) CSS `!important`로 `.cm-md-marker`, `.cm-md-url` 강제 숨김 + `.cm-cursorLayer/.cm-selectionLayer { display: none }` + `transition: none`. JS 분기만으로는 CodeMirror decoration diffing 타이밍에 의해 이전 `cm-cursor-line` 클래스가 잔존할 수 있으므로 CSS override 필수
39. **CSS transition과 스냅샷 경합**: overlay 패턴의 CSS transition (HR 300ms, math 200ms)이 스냅샷 캡처와 경합 — transition 진행 중에 snapshot하면 소스 텍스트가 반투명하게 보임. `cm-snapshot-mode` 클래스가 `transition: none !important`로 해결. Compositor wait도 50ms로 단축 가능
40. **`callAsyncJavaScript` 활용**: 두 가지 용도 — (1) 복잡한 문자열 전달 (JSON 등 이스케이핑 우회), (2) `await` + `requestAnimationFrame`으로 compositor paint 완료 대기. 단순 함수 호출은 `evaluateJavaScript`가 안정적 (microtask 지연 없음). Pre-rendering은 `callAsyncJavaScript`로 content 전달 + double-rAF await를 단일 호출에서 처리. 파라미터: `callAsyncJavaScript("fn(arg)", arguments: ["arg": value], in: nil, in: .page)` — `in:` 두 개 (frame, contentWorld)
41. **`suppressContentChange` 패턴**: `setContent`/`restoreState`/`setContentForSnapshot`에서 `clearTimeout(debounceTimer)` + `suppressContentChange=true` → `dispatch()` → `suppressContentChange=false`. CodeMirror `dispatch`는 동기적이므로 `updateListener`가 플래그 활성 중에 호출됨. 프로그래밍적 콘텐츠 교체가 `contentChanged` bridge 메시지를 발생시키지 않도록 방어. 없으면: (1) pre-rendering 중 active note 콘텐츠 덮어쓰기, (2) 노트 전환 시 이전 노트의 디바운스가 새 noteId로 잘못된 콘텐츠 저장
42. **`attachWebView` isReady 가드**: 에디터가 `markReady()` 전에 다른 윈도우로 전환되면 `serializeState()`가 빈 에디터 상태(`""`)를 직렬화하여 기존 콘텐츠 삭제. `manager.isReady` 체크로 방어 — false면 직렬화/스냅샷 건너뛰고 text preview 표시
43. **`cacheSerializedState` 전체 상태 저장**: `serializeState()` JSON에는 `{doc, anchor, head, scrollTop}` 포함. 기존에는 `doc`만 추출하여 NoteManager에 저장 → 앱 재시작 시 cursor/scroll 소실. `anchor` → `updateNoteCursorPosition`, `scrollTop` → `updateNoteScrollTop` 추가로 영속화. `switchToNote`의 중복 코드도 `cacheSerializedState` 재사용으로 정리

## Lezer Markdown Node Names

에디터에서 사용하는 syntax tree 노드:
`ATXHeading1`~`6`, `HeaderMark`, `StrongEmphasis`, `Emphasis`, `EmphasisMark`, `InlineCode`, `CodeMark`, `CodeInfo`, `FencedCode`, `Link`, `LinkMark`, `URL`, `Blockquote`, `QuoteMark`, `HorizontalRule`, `BulletList`, `OrderedList`, `ListItem`, `ListMark`, `Strikethrough`, `StrikethroughMark`, `Table`, `TableHeader`, `TableRow`, `TableCell`, `TableDelimiter`, `Task`, `TaskMarker`

## Known Issues (미해결)

- **수식/테이블 블록 주변 커서 이동**: 렌더된 수식 블록($$...$$)과 테이블 주변에서 화살표 키가 macOS 네이티브와 다르게 동작. 노트 끝에서 위/아래 화살표 반복 시 커서가 문서 맨 처음으로 점프하는 버그 있음. `blockMathNavKeymap` 개선 필요
- **Inline math 애니메이션**: 현재 즉시 전환 (crossfade 불가). Block은 overlay 패턴으로 해결했지만 inline은 텍스트 흐름 때문에 불가

## Debugging

- **Swift**: `print()` → Xcode/terminal 콘솔
- **JS**: `console.log()` → Swift 콘솔로 전달됨
- **DOM 검사**: Safari > Develop > [Mac] > StickyNotes > index.html
- **Syntax tree 덤프**: Safari 콘솔에서 `dumpTree()` 실행 — 모든 노드명/위치/텍스트 출력
