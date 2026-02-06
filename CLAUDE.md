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
- **WKWebView + CodeMirror 6**: Markdown editor with KaTeX math
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

### Key Files

```
editor-web/src/editor.js          # 에디터 전체 (ViewPlugin + StateField + theme)
editor-web/webpack.config.cjs     # 단일 번들, 폰트 base64 인라인
Sources/StickyNotes/Views/NoteWindow/NoteWebView.swift  # WKWebView + 리소스 로딩
Sources/StickyNotes/Bridge/EditorBridge.swift            # Swift-JS 메시지 핸들러
Sources/StickyNotes/App/AppCoordinator.swift             # 앱 조율 (Combine)
```

### Swift-JS Bridge

- **JS → Swift**: `sendToBridge(action, data)` → `ready`, `contentChanged`, `requestSave`, `log`, `error`
- **Swift → JS**: `window.setContent(content)`, `window.getContent()`, `window.openSearch()`
- Console.log 인터셉트: `WKUserScript` at document start → Swift 콘솔로 전달

## Implementation Status

- **Phase 1 ✅**: App structure, NSPanel windows, persistence, WKWebView
- **Phase 2 ✅**: CodeMirror 6, syntax tree decorations, KaTeX math, cursor unfold
- **Phase 3 ✅**: 추가 마크다운 요소 (취소선, 리스트 스타일, 체크박스 위젯, 테이블)
- **Phase 4 ✅**: Titlebar 컨트롤 (핀/투명도/색깔), Always-on-top, Cmd+F/Cmd+Shift+F 검색
- **Phase 5 (진행중)**: 디자인 개선, 버그 수정, Known Issues 해결

## Gotchas

1. **`Decoration.line()` CSS**: 클래스가 `.cm-line` 요소에 직접 추가됨 — `&light .cm-heading-1` 같은 스코프 접두사 사용하면 안 됨, `.cm-heading-1`로 직접 사용
2. **ViewPlugin vs StateField**: 줄바꿈 포함 `Decoration.replace()`는 반드시 StateField. ViewPlugin에서 하면 "line break" 에러
3. **`atomicRanges` 주의**: 모든 decoration에 적용하면 커서가 여러 블록을 건너뜀 — 블록 수식 네비게이션은 커스텀 키맵(`blockMathNavKeymap`)으로 처리
4. **regex vs syntax tree**: 인라인 코드 regex는 펜스드 코드블록 내부와 충돌 — `syntaxTree().iterate()`의 노드명(`InlineCode`, `FencedCode` 등) 사용
5. **HighlightStyle 한계**: `fontSize`는 span 레벨만 적용되어 헤딩 라인 전체에 효과 없음 — `Decoration.line()` + CSS 클래스로 해결
6. **WKWebView 리소스**: `loadFileURL()`에 Resources 디렉토리 전체 read access 필요 (KaTeX 폰트)
7. **Webpack 단일 번들**: `splitChunks: false`, 폰트 `asset/inline` — WKWebView는 청크/외부 파일 로딩 불가
8. **한글 수식 필터**: KaTeX가 한글 미지원 — `/[ㄱ-ㅎㅏ-ㅣ가-힣]/` regex로 건너뛰기
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
22. **마커 숨기기 (Obsidian 스타일)**: ViewPlugin에서 커서 라인에 `cm-cursor-line` 클래스 추가, CSS로 `.cm-md-marker { font-size: 0; opacity: 0 }` + `.cm-cursor-line .cm-md-marker { font-size: inherit; opacity: 0.35 }`. 대상: `HeaderMark`, `EmphasisMark`, `QuoteMark`, `CodeMark`, `CodeInfo`
23. **블록 수식 Overlay 패턴**: `Decoration.replace({ block: true })`는 클릭 좌표가 밀림. 해결: (1) 원본 줄에 `Decoration.line()`으로 `line-height` 동적 조정 (위젯높이/줄수), `color: transparent`, (2) 첫 줄에 `Decoration.widget({ side: -1 })`로 위젯 삽입, (3) 위젯 CSS `position: absolute`, `pointerEvents: none`. 핵심: 원본 줄 총 높이 = 위젯 높이
24. **CSS `color: transparent` 상속**: 부모에 설정하면 자식도 투명해짐. 위젯 내용을 보이게 하려면 `.overlay *: { color: inherit !important }`, 단 source line 자식은 `.source-line > *:not(.overlay) { color: transparent !important }`로 구체적 선택
25. **EditorView.theme() 스코프 한계**: 테마 CSS는 `.cm-editor` 내부에서만 적용됨. 오프스크린 측정 시 테마 스타일(padding 등)이 적용 안됨 → inline style로 직접 설정 필요
26. **HR/단일라인 Overlay 패턴**: 블록 수식과 동일 원리. `HorizontalRule` 등 단일 라인도 CSS `line-height`만으로는 클릭 좌표 계산에 영향 없음 — `Decoration.line({ attributes: { style: 'height:16px;line-height:16px' } })` + `Decoration.widget()` 오버레이 조합 필요

## Lezer Markdown Node Names

에디터에서 사용하는 syntax tree 노드:
`ATXHeading1`~`6`, `HeaderMark`, `StrongEmphasis`, `Emphasis`, `EmphasisMark`, `InlineCode`, `CodeMark`, `CodeInfo`, `FencedCode`, `Link`, `LinkMark`, `URL`, `Blockquote`, `QuoteMark`, `HorizontalRule`, `BulletList`, `OrderedList`, `ListItem`, `ListMark`, `Strikethrough`, `StrikethroughMark`, `Table`, `TableHeader`, `TableRow`, `TableCell`, `TableDelimiter`, `Task`, `TaskMarker`

## Known Issues (미해결)

- ~~**Task list `-` 마커 숨기기**~~: 해결됨 — TaskMarker의 `Decoration.replace()` 범위를 `- [x]` 전체로 확장. 이전 실패 원인은 앱 미재시작 (WKWebView 캐시)
- **수식/테이블 블록 주변 커서 이동**: 렌더된 수식 블록($$...$$)과 테이블 주변에서 화살표 키가 macOS 네이티브와 다르게 동작. 노트 끝에서 위/아래 화살표 반복 시 커서가 문서 맨 처음으로 점프하는 버그 있음. `blockMathNavKeymap` 개선 필요
- ~~**수식 블록 아래 클릭 시 커서 위치 밀림**~~: 해결됨 — Overlay 접근법: `Decoration.replace()` 대신 원본 줄에 `line-height` 조정 + `color: transparent`, 위젯은 `position: absolute`로 오버레이. 원본 줄 높이 = 위젯 높이로 맞춰서 클릭 좌표 정확
- ~~**HR (---) 아래 클릭 시 커서 위치 밀림**~~: 해결됨 — 블록 수식과 동일한 overlay 패턴 적용. CSS `line-height`/`height`만으로는 CodeMirror 좌표 계산에 영향 없음, `Decoration.line()` + `Decoration.widget()` 조합 필요
- ~~**헤딩 밑줄 제거 안됨**~~: 해결됨 — `Decoration.line()`은 `.cm-line`에 적용되지만, `defaultHighlightStyle`의 `t.heading` 밑줄은 내부 `<span>`에 적용됨. `markdownHighlightStyle`에서 `{ tag: t.heading, textDecoration: 'none' }` 추가로 해결
- ~~**Always-on-top이 시스템 전체에서 작동 안 함**~~: 해결됨 — `hidesOnDeactivate = false` (critical), `level = .popUpMenu`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`, `isFloatingPanel = true`, `orderFrontRegardless()` 조합
- ~~**타이틀바 영역 마우스 커서**~~: 해결됨 — HTML overlay div (80px×28px, traffic lights 영역만)에 `cursor: default` + `pointer-events: auto`
- ~~**타이틀바/검색 UI 정렬**~~: 해결됨 — `.cm-content` padding-top: 32px, `.cm-panels-top` marginTop: 28px, `#titlebar-mask` div에 노트 색상 동기화

## Debugging

- **Swift**: `print()` → Xcode/terminal 콘솔
- **JS**: `console.log()` → Swift 콘솔로 전달됨
- **DOM 검사**: Safari > Develop > [Mac] > StickyNotes > index.html
- **Syntax tree 덤프**: Safari 콘솔에서 `dumpTree()` 실행 — 모든 노드명/위치/텍스트 출력
