# Stow Paste-Inspired macOS Redesign Plan

**Status:** Implemented and verified
**Date:** 2026-08-09
**Chosen direction:** A — the bottom quick panel becomes Stow's primary macOS interaction surface; the full app remains a secondary library/management surface.

## 1. Goal

Redesign Stow around a fast, visual, keyboard-first retrieval flow inspired by Paste's macOS experience without copying Paste's branding.

The primary experience will be a resizable, translucent panel anchored to the bottom of the active display. It will show one horizontal timeline of content-native cards, support immediate search/filtering, and let the user paste or act on an item without leaving the app they were using.

The existing full-size Stow window will remain available for durable management tasks: Inbox processing, Archive, Trash, metadata editing, and Settings. It will no longer be treated as the main retrieval workflow.

## 2. Reference Review

This plan is based on a new review of:

- [Paste homepage](https://pasteapp.io/)
- [Paste on Mac: clipboard history & pinboards](https://pasteapp.io/help/paste-on-mac)
- Official normal/compact timeline, search, pinboard, and preview/edit screenshots linked from the help page

Observed product patterns that define the target direction:

1. A floating bar is attached to the bottom of the screen, not centered like a dialog.
2. Clips live in a single horizontal visual timeline.
3. The panel uses desktop translucency; the orange seen in marketing screenshots largely comes from the wallpaper behind it, not a mandatory orange app background.
4. Navigation is a horizontal row of list/pinboard chips, not a sidebar.
5. Search expands inside the toolbar and filters appear as inline tokens.
6. Each content type has its own card renderer rather than a generic icon/title/metadata template.
7. Selection is obvious through a thick accent outline.
8. Resizing the panel downward produces a true compact mode.
9. Preview and edit retain timeline context in a popover anchored to the selected card.
10. Keyboard navigation, direct paste, double-click, Quick Look, multi-selection, and drag-out are core interaction patterns.

## 3. Product Decisions

### 3.1 Primary and secondary surfaces

- **Primary:** `⌘⇧V` bottom retrieval panel.
- **Secondary:** Library window for Inbox, Archive, Trash, detailed editing, and Settings.
- **Quick capture:** `⌥⇧S` remains available.
- A menu bar item will expose **Show Stow**, **Quick Add**, **Open Library**, **Pause/Resume Monitoring**, and **Settings**.
- Normal launches should behave like a utility rather than forcing the management window in front. UI testing may use a launch argument to open the Library deterministically.

### 3.2 Stow navigation in the panel

Stow does not currently have Paste-style Pinboards, and this UI redesign will not silently add a new collection data model.

The toolbar will map existing Stow concepts into horizontal modes:

- **Clipboard** — recent active items, newest/last-used first
- **Inbox** — unprocessed Inbox items
- **Pinned** — existing `isPinned` items
- **Archive** — available from the overflow/menu rather than occupying primary space
- **+** — Quick Add

Trash and Settings remain management-window destinations.

### 3.3 Visual identity

- Preserve Stow's blue accent and shipping-box identity.
- Use native material/vibrancy so the panel responds to the current desktop and light/dark mode.
- Do not hardcode Paste's orange wallpaper or reuse Paste assets.
- Use type colors for card headers and selection context, with contrast verified in both appearances.
- Prefer content over chrome: no sidebar, title bar, large app logo, item-count heading, or permanent keyboard-help footer in the panel.

## 4. Target Experience

### 4.1 Panel window behavior

Implement a dedicated `NSPanel` subclass/controller with these behaviors:

- Borderless, floating, non-activating where possible, and able to become key for search/keyboard navigation.
- Appears on the display containing the pointer when the global shortcut is pressed.
- Anchored to the display's visible bottom edge with approximately 12–16 pt outer margins.
- Default height approximately 340 pt; resizable from the top edge.
- Minimum height approximately 210 pt; maximum height no more than 60% of the visible display.
- Width follows the visible display and updates when display geometry changes.
- Persist height per display; clamp persisted values when screen geometry changes.
- Rounded top/outer corners, subtle border, shadow, and `NSVisualEffectView`-backed material.
- `Escape` closes the panel. Successful use closes it and returns focus to the prior app.
- Opening the panel records the previously frontmost application so Return can paste back into the correct target.
- Repeated `⌘⇧V` toggles the panel rather than creating another window.

### 4.2 Normal and compact modes

Use explicit layout breakpoints derived from content height:

- **Normal mode:** toolbar plus taller cards with richer previews and metadata.
- **Compact mode:** one square-ish row, reduced card width/height, shorter text limits, and no secondary metadata.
- The mode transition must preserve selection and horizontal scroll position.
- Reduced Motion disables spring/scale effects and uses a simple crossfade.

### 4.3 Toolbar and search

Collapsed toolbar:

- Search button
- Clipboard, Inbox, and Pinned chips with colored markers
- Quick Add button
- Overflow for Archive, Open Library, monitoring state, and Settings

Search mode:

- Search field expands in the same toolbar.
- Typing while the panel is open also enters search.
- Results update live.
- Type, source app, and date filters appear as removable inline tokens.
- A filter button opens all available filters.
- `Command-F` opens/focuses search; `Escape` first clears/exits search, then closes the panel.
- `Tab` moves between the search field, tokens, and timeline.
- Search uses the existing app/search model rather than a second independent search implementation.

### 4.4 Card system

Create a macOS-specific card presentation model so each card receives its item, attachment/thumbnail, link metadata, source icon, and formatted labels without running an attachment query per card.

Shared anatomy:

- 14–18 pt continuous corner radius
- Type/time label at the top
- Source application icon at the top-right when available
- Content-specific body
- Thick Stow accent outline for selection
- Subtle shadow only when appropriate
- Context menu, drag source, accessibility label/value, and stable UI-test identifier

Type renderers:

- **Link:** preview image or favicon/domain treatment; title and domain remain readable.
- **Text:** the copied content is the visual focus; preserve useful line breaks and rich-looking typography.
- **Code:** dark editor-like surface, monospaced text, language label when known.
- **Image:** full-bleed thumbnail with dimensions/filename as a restrained overlay.
- **File:** native file icon/thumbnail, filename, and compact path/type information.

Source icons are best effort: resolve a running/installed application from `sourceApp`, cache its icon, and fall back to a neutral app glyph. Adding an optional bundle identifier to the schema is deferred unless name-based resolution proves inadequate.

### 4.5 Selection and actions

Required keyboard behavior:

- Left/Right: previous/next card
- Down/Up: move between toolbar/search and timeline where applicable
- Return or double-click: use the selected item
- `Command-C`: copy
- `Command-O`: open link/file
- `Command-Shift-A`: archive/restore
- Delete: move to Trash
- Space: Quick Look/preview
- `Command-E`: edit text/code
- `Command-R`: rename
- `Command-P`: pin/unpin
- `Command-1...9`: quick-use the visible numbered item while Command is held, if this does not conflict with macOS behavior

Default Return behavior should match a clipboard utility:

- Text/Code: put text on the pasteboard and paste into the previously active app.
- Link: paste the URL; opening remains `Command-O`.
- Image: put the original image representation on the pasteboard and paste.
- File: put a file URL/representation on the pasteboard and paste when supported; otherwise copy with a clear fallback state.

Introduce a `DirectPasteService` that:

1. Saves the target application before showing Stow.
2. Writes the correct pasteboard representation through the existing action/accounting boundary.
3. Hides the panel and reactivates the target application.
4. Synthesizes `Command-V` only when Accessibility trust is available.
5. Falls back to copy-only, with concise feedback, when Accessibility is unavailable.
6. Never records a successful use twice.

### 4.6 Preview, edit, and drag

- Space opens system Quick Look or the appropriate preview surface.
- Text/code editing appears in a card-anchored popover so the horizontal timeline remains visible.
- Rename uses a compact anchored editor.
- Existing item metadata and lifecycle editing remains available in the Library window.
- Cards expose existing text, URL, image, and file drag representations directly from the timeline.
- Drag completion and direct paste continue to use retrieval accounting correctly.

### 4.7 Library and Settings

- Restore the full-size window to a management-oriented layout rather than duplicating the primary visual timeline as a large grid.
- Keep Inbox, Recent, Pinned, Archive, Trash, and Settings discoverable.
- Keep bulk lifecycle work, metadata editing, search-index repair, clipboard-monitoring controls, and permission guidance here.
- Visual polish is allowed, but the panel receives implementation and review priority.
- iOS/iPadOS behavior remains unchanged in this plan except for safe shared bug fixes.

## 5. Architecture and File Plan

### Existing files to rework

- `Sources/StowApp/macOS/RetrievalPanel.swift`
  - Split window/controller mechanics from SwiftUI panel content.
  - Replace the current centered fixed-size panel and permanent search/footer layout.
- `Sources/StowApp/macOS/MacAppCoordinator.swift`
  - Track the target application, toggle panel visibility, and coordinate menu bar actions.
  - Stop activating Stow before preserving the paste target.
- `Sources/StowApp/macOS/StowMacApp.swift`
  - Add utility/menu-bar commands and explicit Library opening behavior.
- `Sources/StowApp/Shared/AppModel.swift`
  - Expose panel mode/query/filter operations without duplicating repository/search logic.
- `Sources/StowApp/Shared/PlatformActions.swift`
  - Add or reuse typed pasteboard representations needed by direct paste.
- `Sources/StowApp/Shared/StowRootView.swift`
  - Keep the full window management-oriented.

### New macOS-focused components

Exact filenames may be consolidated during implementation, but responsibilities must remain separate:

- `StowRetrievalPanel.swift` — custom `NSPanel` behavior and visual-effect host
- `RetrievalPanelController.swift` — display geometry, presentation, resizing, and focus lifecycle
- `RetrievalPanelState.swift` — mode, query, filters, selection, compact layout, and keyboard transitions
- `RetrievalTimelineView.swift` — toolbar, horizontal scrolling, empty/loading states
- `StowClipCard.swift` — shared card shell plus five type renderers
- `ClipCardPresentation.swift` — precomputed display data and attachment lookup
- `DirectPasteService.swift` — previous-app focus and Accessibility-aware paste
- `SourceAppIconProvider.swift` — cached source icon resolution
- `StowMenuBarController.swift` or `MenuBarExtra` scene — utility entry points

### Test files

- Extend `Tests/StowAppTests/StowAppSmokeTests.swift` or split focused app tests for panel geometry/state and presentation models.
- Rewrite `Tests/StowMacUITests/StowMacUITests.swift` around the new primary panel workflow.
- Keep existing `Packages/StowCore/Tests` as regression coverage for repository, action accounting, search, attachments, and lifecycle behavior.

## 6. Implementation Phases

### Phase 0 — Establish the accepted baseline

- Treat the current uncommitted full-window grid experiment as exploratory, not approved design.
- Restore the Library/detail views to the last stable management behavior before building the new primary panel.
- Retain only useful deterministic fixture improvements after verifying they do not affect production data.
- Capture baseline screenshots and test results.

**Gate 0:** clean macOS/iOS builds and existing core tests pass before structural work begins.

### Phase 1 — Panel shell and visual prototype

- Implement the bottom-anchored custom panel, active-display geometry, translucent material, resize bounds, persisted height, and toggle/close behavior.
- Add static toolbar and representative five-type cards using test fixtures.
- Implement normal/compact breakpoints without production actions yet.

**Visual review gate 1:** provide screenshots of normal mode, compact mode, light mode, and dark mode. Do not continue card/detail polish until approved.

### Phase 2 — Production timeline and card renderers

- Connect panel modes to real SwiftData items.
- Build one attachment lookup/presentation map per result set.
- Implement all five card renderers, source icons, selection, horizontal scrolling, and context menus.
- Preserve current ordering and lifecycle semantics.

**Visual review gate 2:** provide screenshots with Link, Text, Code, Image, and File selected/unselected states.

### Phase 3 — Keyboard and direct-use workflow

- Implement selection/focus state and every required shortcut.
- Add previous-app tracking and Accessibility-aware `DirectPasteService`.
- Implement copy/open/archive/trash/pin actions through existing service boundaries.
- Ensure panel dismissal/focus restoration is reliable.

**Functional gate 3:** invoke from TextEdit, paste Text/Code/Image/Link, open Link/File, and verify fallback copy behavior without Accessibility permission.

### Phase 4 — Search and filters

- Implement collapsed/expanded toolbar states, type-to-search, inline filter tokens, source/date/type menus, and keyboard focus traversal.
- Connect to the existing search/index path.
- Preserve selection where possible as results change.

**Visual/functional gate 4:** provide collapsed, active-search, token-filter, no-results, and error screenshots plus search UI-test evidence.

### Phase 5 — Preview, edit, rename, Quick Look, and drag

- Add anchored text/code edit and rename popovers.
- Add Quick Look/preview for supported content.
- Add drag-out from all card types.
- Validate retrieval accounting and item updates.

### Phase 6 — Utility lifecycle and Library handoff

- Add menu bar commands.
- Make the Library an explicit management destination instead of the default retrieval flow.
- Preserve Dock/open-file behavior and Settings access.
- Update onboarding/permission copy for direct paste and clipboard monitoring.

### Phase 7 — Accessibility, reliability, performance, and final polish

- Complete keyboard-only operation and VoiceOver labels/order.
- Verify contrast, light/dark mode, Reduce Motion, and increased contrast.
- Test multiple displays, Dock positions, full-screen Spaces, display changes, panel resizing, and rapid shortcut toggling.
- Profile 10,000-item result sets, thumbnail memory, icon caching, and scroll performance.
- Update README and release accessibility/test documentation.

## 7. Test Strategy

### Unit/integration tests

- Screen selection, bottom anchoring, resize clamping, and persisted height.
- Compact-mode thresholds.
- Mode/query/filter state transitions and selection repair after result changes.
- Card presentation for every type with/without attachments and metadata.
- Source icon fallback/cache behavior.
- Previous-app capture and direct-paste fallback state.
- One successful retrieval metric per successful action; none for cancelled/failed actions.
- Search/filter combinations, Archive/Trash changes, and attachment representations.

### macOS UI tests

- Launch from TextEdit with `⌘⇧V`; panel appears on the active display at the bottom.
- Verify no sidebar, standard title bar, permanent footer, or multi-row grid exists in the panel.
- Verify horizontal card navigation and visible selection.
- Search by title/content and filter by type/source/date.
- Return, `⌘C`, `⌘O`, `⌘⇧A`, Delete, Space, pin, rename, and edit.
- Direct-paste path where permission is available; deterministic copy fallback under a UI-test launch flag.
- Normal/compact resize behavior.
- Open Library and Settings from the panel/menu bar.
- Screenshot attachments for all visual review gates.

### Regression gates

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/StowCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Stow.xcodeproj -scheme Stow-macOS CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Stow.xcodeproj -scheme Stow-iOS -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Stow.xcodeproj -scheme StowMacUITests CODE_SIGN_ENTITLEMENTS='' CODE_SIGN_IDENTITY='-' test
```

## 8. Acceptance Criteria

The redesign is complete only when all of the following are true:

- `⌘⇧V` presents a bottom-anchored translucent panel on the active display.
- The panel is a single horizontal timeline with no sidebar or permanent action footer.
- Normal and compact modes both remain usable and preserve selection.
- Link, Text, Code, Image, and File have visibly distinct content-native cards.
- Type/time and source app are understandable at a glance.
- Selection is clear in light/dark and increased-contrast modes.
- Search expands inline and supports removable type/source/date tokens.
- The entire primary workflow is keyboard operable.
- Return attempts to paste into the previously active app and safely falls back to copy-only.
- Copy/open/archive/trash/pin/preview/edit/rename/drag actions remain functional and correctly accounted.
- The Library opens explicitly for management and retains every existing lifecycle/settings feature.
- Existing iOS behavior and core domain tests do not regress.
- Normal, compact, search, edit, light, and dark screenshots are reviewed and approved.
- macOS build, iOS build, core tests, and macOS UI tests pass with no known required work remaining.

## 9. Risks and Mitigations

- **Non-activating panel vs keyboard input:** isolate AppKit window/focus behavior in a custom panel and test target-app preservation before building the full UI.
- **Direct paste permission:** make copy-only fallback first-class and explain Accessibility permission without blocking ordinary copy/open actions.
- **Desktop material readability:** use semantic materials plus a contrast layer; validate varied light/dark wallpapers and increased contrast.
- **SwiftUI horizontal focus/scroll drift:** centralize selection in a state model and scroll to stable item IDs.
- **Per-card query/memory cost:** precompute attachment/presentation data once and use lazy card construction, thumbnail data, and cached app icons.
- **Large scope:** enforce the four review gates; defer Pinboards, collaboration, and mobile redesign rather than expanding this UI project.

## 10. Implementation Evidence

Completed on 2026-08-09:

- Full `RUN_UI_TESTS=1 Scripts/ci.sh` passed with Xcode 26.6 / Swift 6.3.3: 50 StowCore tests, 1 native smoke test, macOS and iOS builds, entitlement verification, 4 macOS UI tests, and 13 iOS UI tests.
- A second post-utility-lifecycle `StowMacUITests` run passed all 4 tests after the explicit Library window handoff was added.
- Unsigned macOS Release builds pass. Runtime window inspection verifies a normal Release launch remains alive with zero Library windows in front, while `--open-library` presents one management Library window.
- Kept screenshot attachments verify normal, compact, active search, inline filter token, no-results, anchored edit, light, dark, and Reduce Motion states.
- macOS UI coverage verifies bottom/active-display geometry, a utility launch with no forced Library, the global `Command-Shift-V` shortcut from TextEdit, Clipboard/Inbox/Pinned navigation, typed search, type filtering, Text/Code/Image pasteboard actions, Return fallback, Space preview, edit, Archive, Escape behavior, and Quick Add.
- README, accessibility audit, and release test matrix now document the new panel, direct-paste permission/fallback, utility lifecycle, and automated evidence.

## 11. Explicit Non-Goals

- Pixel-for-pixel copying of Paste, its icon, assets, typography, or brand colors.
- A new Pinboards/collections/collaboration data model.
- OCR, AI search, Paste Stack, or every advanced Paste feature.
- Redesigning iPhone/iPad in this macOS-first implementation.
- Replacing Stow's Inbox/Archive/Trash domain model with Paste's product model.
