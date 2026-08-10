# Quick Panel Close Flow Redesign Plan

**Status:** Completed and archived
**Date:** 2026-08-09

## Goal

Make Stow's macOS Quick Panel easy and safe to leave with mouse, keyboard, and assistive technology while preserving its fast transient workflow, existing shortcuts, stored data, and copy/paste behavior.

The finished flow must provide an always-visible close action, predictable layered cancellation, safe handling of unsaved edits, focus restoration to the originating app, actionable failure states, responsive layouts, and test/documentation evidence. It must not require a new privacy permission or redesign iOS/iPadOS.

## Context

### Current evidence

- `Sources/StowApp/macOS/RetrievalPanelController.swift`
  - Hides all standard window controls and exposes no visible close button.
  - Repeated `Command-Shift-V` toggles the panel.
  - Keeps the nonactivating panel visible when focus changes (`hidesOnDeactivate = false`).
  - Closes after successful direct paste, open, and Library handoff.
  - Copy-only Return shows feedback for 0.9 seconds and then closes.
- `Sources/StowApp/macOS/RetrievalPanel.swift`
  - Escape closes a popover, clears active search/filter criteria, collapses empty search, and finally closes the panel.
  - Search mode replaces most toolbar controls, so any close control must remain outside the search field.
  - Edit and Rename own local drafts, but the parent cannot currently determine whether they are dirty.
  - Save always dismisses the editor after calling `AppModel.save`, even when persistence fails.
  - `Command-C` copies and deliberately leaves the panel open.
- `Sources/StowApp/macOS/MacAppCoordinator.swift` and `StowMacApp.swift`
  - Quick Add, Library, Settings, global shortcuts, and menu bar commands are coordinated through separate notification/scene paths.
  - Quick Add and Settings do not currently share a close-before-handoff contract with the Quick Panel.
- `Tests/StowMacUITests/StowMacUITests.swift`
  - Covers layered Escape and shortcut toggling, but not a visible close control, outside-click dismissal, dirty-edit confirmation, failed-save preservation, or close accessibility.
- `README.md`, `docs/release/v0.1-accessibility-audit.md`, and `docs/release/v0.1-test-matrix.md`
  - Describe opening and using the panel but not a complete close/cancel flow.

### Users and goals

1. Keyboard-first frequent users need to invoke, find, use, and dismiss the panel without leaving the keyboard.
2. Pointer-first and occasional users need a discoverable close action without knowing Stow shortcuts.
3. New users need to understand whether Return will paste directly or only copy.
4. VoiceOver and keyboard-navigation users need clear labels, deterministic focus order, and a reliable exit.

### Priority classification

- **Primary:** open/close, search, card selection, Return/double-click use.
- **Secondary:** preview, copy, mode switching, Quick Add, Library, and Settings handoff.
- **Advanced:** source/type/date filters, resizing, multi-selection, direct-paste permission management.
- **Destructive or consequential:** moving to Trash, discarding dirty edits, and saving edits.
- **Compatibility-only:** existing `Command-Shift-V` toggle, layered Escape semantics, `Command-C` keep-open behavior, panel-height persistence, data schema, and iOS/iPadOS behavior.

These classifications guide ordering and emphasis; they do not create Basic/Advanced navigation sections.

### Flow evaluation

| Flow | Frequency | Importance | Complexity / risk | Reversibility |
|---|---:|---:|---:|---:|
| Close or cancel | High | High | Low unless an editor is dirty | Usually reversible |
| Return/double-click use | High | High | Medium; changes pasteboard and may affect another app | Partly reversible |
| Search and selection | High | High | Low | Reversible |
| Copy | Medium-high | High | Low | Reversible |
| Edit or rename | Medium | Medium-high | Medium; drafts can be lost | Save may not be reversible |
| Pin or archive | Medium | Medium | Low | Reversible |
| Move to Trash | Low-medium | Medium-high | Medium | Reversible before purge |
| Open Library or Settings | Low | Medium | Low | Reversible |

### Usability problems to resolve

- Closing is undiscoverable because the standard close control is hidden and More has no close item.
- Escape may require one to three presses without explaining which state each press affects.
- Clicking outside leaves the transient panel on screen.
- Search's clear icon and a panel close icon need distinct placement and labels.
- Dirty edits can be discarded without a warning; failed saves can dismiss the draft.
- Quick Add, Settings, and Library can produce inconsistent stacked-surface behavior.
- Direct Paste versus Copy-only behavior is not visible until after Return.
- Search/action failures use a generic alert and may replace a valid result state with an apparent empty state.
- Existing UI tests do not prove the close, cancellation, failure, responsive, or accessibility contracts.

## Architecture

### Information architecture

Keep one shallow toolbar. From left to right it contains:

1. Search.
2. Clipboard, Inbox, and Pinned modes.
3. A concise action-state label (`Paste: Direct` or `Paste: Copy only`); show `Monitoring paused` when capture is disabled.
4. Quick Add.
5. More.
6. An always-visible Close button at the far right.

The Search field's internal button remains `Clear Search`; the toolbar button is `Close Quick Panel`. Close remains visible in normal, compact, search, empty, loading, and error states. At narrower widths, inactive mode labels and secondary actions may compress or move into More, but Search, the active mode, consequential status, and Close remain unambiguous.

Keep More as one flat group of at most six actions: Archive, Quick Add, Open Library, Settings, Monitor Clipboard, and Close Quick Panel. Do not introduce Basic/Advanced sections.

### Close request ownership

Add a single close-request path shared by:

- Toolbar Close.
- Repeated global shortcut.
- Layered Escape.
- Outside pointer click.
- Successful use/open/drag.
- Quick Add, Library, and Settings handoff.

Represent the request reason and optional destination explicitly rather than calling `dismiss()` from unrelated UI branches. `RetrievalPanelSession` carries controller-originated requests into SwiftUI; the panel view resolves local search/popover/dirty state before authorizing controller dismissal.

The close policy is:

1. An open menu or clean preview closes before the panel.
2. Escape clears active search/filter criteria, then collapses empty search, then closes the panel.
3. Toolbar Close and repeated `Command-Shift-V` request immediate panel closure without stepping through search, unless a dirty editor needs confirmation.
4. A clean edit/rename draft cancels with no persistence side effects.
5. A dirty edit/rename draft presents `Keep Editing` and `Discard Changes and Close`; keeping the editor cancels the close request.
6. Confirmed close destroys transient query/filter/selection state, removes monitors, closes the panel, and restores the originating app unless another Stow destination was requested.
7. Quick Add, Library, or Settings opens only after the panel is safely dismissed, preventing stacked Stow surfaces.

### Outside-click behavior

Install outside-click observation only while the panel is visible. It must:

- Ignore clicks inside the panel or an app-owned menu/popover.
- Ignore resize and active drag sessions.
- Let the first outside interaction dismiss an open menu/popover rather than both layers.
- Route a dirty editor through the same discard confirmation.
- Remove its monitor on every close/failure path.
- Work without prompting for Accessibility or Input Monitoring permission.

An early implementation spike will choose the least invasive AppKit mechanism (global mouse monitor or verified window lifecycle callback) and prove it against the nonactivating `NSPanel` before the production path is changed.

### Action and state behavior

| Action | Expected result |
|---|---|
| Return or double-click | Paste and close on success. |
| Return without Accessibility | Show `Copied — paste with Command-V`, then close and reactivate the target app. |
| `Command-C` | Preserve compatibility: copy, show `Copied`, and remain open. |
| Open Link/File | Close only after success; retain state and show an actionable error on failure. |
| Preview | `Done` or Escape closes only Preview. |
| Edit/Rename Save | Apply atomically and dismiss only on success; retain the draft on failure. |
| Cancel | Discard only the local draft and perform no repository write. |
| Pin/Archive | Remain open, repair selection, and show immediate feedback. |
| Move to Trash | Remain open, repair selection, and offer Undo instead of adding a routine confirmation. |
| Quick Add/Library/Settings | Close first, then open exactly one destination. |
| Successful drag-out | Close after successful drag completion; cancelled drag remains open. |

Preview uses `Done`/`Open`, editing uses `Cancel`/`Save`, and dirty close confirmation uses `Keep Editing`/`Discard Changes and Close`. Immediate filters remain visibly applied as removable tokens and need no Apply button.

### Loading, empty, success, error, disabled, and partial states

- **Loading:** retain the previous valid timeline while search is in progress and expose a small labelled progress indicator.
- **Empty mode:** explain the selected mode and provide a relevant Quick Add or Library action.
- **No results:** preserve the visible query/tokens and offer `Clear Search and Filters`.
- **Success:** provide concise feedback for Copy, Archive, Trash, and fallback copy before any scheduled dismissal.
- **Error:** preserve selection, the previous valid result set, and dirty drafts; identify the failed action and offer Retry, Open Settings, or dismiss as applicable.
- **Disabled:** show `Paste: Copy only` before Return when Accessibility is unavailable; Return remains functional.
- **Partial:** missing thumbnails, attachments, or source icons use existing fallbacks without disabling unrelated cards/actions.

`AppModel.save` (or a panel-specific result wrapper) must return success/failure so the editor never infers success from a fire-and-forget call. Search must distinguish loading, failed, empty, and stale-but-valid results instead of treating every failure as zero results.

### Accessibility and responsive behavior

- Close and Clear Search use different labels, identifiers, tooltips, and positions.
- Close has at least a 28 x 28 pt pointer target and remains reachable at the supported minimum width.
- VoiceOver order is toolbar, active search/status, timeline, then presented popover/confirmation.
- A presented confirmation receives focus; cancelling returns focus to the editor; successful close returns focus to the originating app.
- Status is expressed in text/icon semantics, never color alone.
- Verify normal and compact heights, at least 480 pt content width, light/dark appearance, Increase Contrast, Reduce Motion, and current-display geometry without overflow or ambiguous truncation.

## Assumptions

- The approved default is a transient panel: outside click closes when no protected edit/menu/drag state exists.
- Toolbar Close and repeated `Command-Shift-V` are fast exits; Escape remains layered and context-sensitive.
- `Command-C` continues to copy without closing to preserve the current expert/batch workflow.
- Dirty drafts receive confirmation; search/filter state is disposable and does not.
- English remains the current UI language, using localizable SwiftUI strings.
- No user preference for close behavior is added initially; a single predictable default is preferable to another setting.
- XCUITest is not run during implementation; accumulated UI scenarios run together once as the final verification batch, with related failures fixed in batches before any rerun.
- Existing item data, unknown UserDefaults keys, shortcut selections, monitoring state, and per-display panel height remain unchanged.
- Release verification is limited to the current single-display Mac, and VoiceOver is not used; existing AX automation validates accessible names, focus, status semantics, and keyboard exit.

## Unknowns

- The reliable outside-click mechanism for a nonactivating panel must be proven not to trigger a new macOS privacy prompt and not to interfere with SwiftUI menus, popovers, or drag sessions.
- Cross-process outside-click automation may be less deterministic than the close state reducer; if XCUITest cannot prove it reliably, retain the automated state/in-app test and record a bounded manual current-macOS check in the release matrix.
- SwiftUI Settings scene opening may require a dedicated AppKit/notification bridge so close-before-open can be tested deterministically.

These unknowns are resolved in the first implementation tasks after approval, before visual or behavioral expansion.

## Non-Goals

- Redesigning the card visuals, Library, Quick Add form, Settings content, or iOS/iPadOS.
- Adding a new data schema, cloud migration, close-behavior preference, pinboard model, or Paste branding.
- Confirming every reversible action; Trash uses Undo and only permanent deletion remains confirmation-worthy.
- Changing the existing global shortcut choices or `Command-C` keep-open behavior.

## Risks

- **Outside monitor lifecycle leak:** centralize install/remove in `RetrievalPanelController` and assert cleanup after every dismissal route.
- **Accidental draft loss:** gate all controller-originated close requests on reported editor dirtiness and test repository immutability on cancellation.
- **Focus theft or wrong paste target:** preserve target capture before presentation and test focus restoration for explicit close, fallback copy, and destination handoff.
- **Toolbar crowding:** keep Close and consequential status fixed, compress secondary controls at explicit breakpoints, and capture narrow/compact screenshots.
- **False success:** change save/use handoffs to return an explicit result and keep the previous valid state on failure.
- **Regression in nonactivating behavior:** run the global-shortcut-from-TextEdit UI test after each controller change.
- **Added confirmation friction:** confirm only a genuinely changed edit/rename draft; clean cancellation stays immediate.

## Rollback / Recovery

No persistence migration is planned. If the new close coordinator or outside-click observer causes regressions, revert the controller/view routing and retain the existing Escape/shortcut paths; stored items, unknown configuration fields, monitoring settings, and panel-height defaults remain readable. Any newly introduced transient UI state must not be persisted.

## Plan

### Approval and baseline

- [x] Obtain explicit user approval for the proposed close hierarchy, outside-click default, dirty-edit confirmation, and `Command-C` keep-open compatibility. Evidence: the active goal explicitly requested implementation of this plan on 2026-08-09.
- [x] Run the current macOS app tests and UI workflow before implementation. Evidence: the pre-implementation `StowMacUITests` baseline passed all 4 tests in 112.230 seconds on 2026-08-09. Per the subsequently specified local cadence, no further XCUITest runs occur until the single final batch.
- [x] Prototype outside-click observation with the nonactivating panel in `RetrievalPanelController.swift`; global and local AppKit monitors plus app-resignation handling were selected. Targeted automation preserves TextEdit as the frontmost app, dismisses on a click there, ignores panel-owned layers, and triggered no permission prompt.

### Close state and controller lifecycle

- [x] Add a testable close-request/reducer model under `Sources/StowApp/macOS/` for Escape, explicit Close, shortcut toggle, outside click, dirty editor, menu layering, and destination handoff; `QuickPanelClosePolicyTests` cover these branches.
- [x] Update `RetrievalPanelSession` and `RetrievalPanelController` to route all close reasons through one request path, restore the target app when appropriate, and remove key/outside monitors exactly once; state tests and rapid-toggle UI coverage pass.
- [x] Add outside-click installation and cleanup to `RetrievalPanelController` using the proven mechanism; automated same-app, active cross-app, and already-active originating-app clicks pass while menus and accepted drags remain protected.
- [x] Route Quick Add, Library, and Settings through close-before-handoff destinations in `MacAppCoordinator.swift`, `StowMacApp.swift`, and the panel callbacks; automation verifies one destination surface and dirty-edit blocking.

### Visible controls and responsive toolbar

- [x] Add an always-visible `Close Quick Panel` button to `RetrievalPanel.swift`, outside the Search field and retained in normal, compact, search, empty, loading, and error layouts; its tooltip, accessibility identifier/label, target size, and screenshots are verified.
- [x] Add `Close Quick Panel` to the flat More surface without creating Basic/Advanced sections; it contains six consistently labelled actions and participates in layered close policy.
- [x] Add visible `Paste: Direct`/`Paste: Copy only` and conditional `Monitoring paused` state using responsive toolbar rules; 480 pt automation verifies text semantics independent of color.
- [x] Define and implement toolbar breakpoints that preserve Search, active mode, consequential status, and Close before secondary actions. Normal, compact, 480 pt, light, dark, Reduce Motion, and Increase Contrast captures pass without overflow or ambiguous truncation; evidence is published in `docs/release/v0.1-quick-panel-visual-review.md`.

### Layered cancellation and safe editing

- [x] Replace generation-based Escape branching with the close state model while preserving menu/preview, search-clear, search-collapse, and final-close order; UI and transition tests cover the sequence.
- [x] Make `RetrievalItemPopover` report draft dirtiness and distinguish Preview Done/Open, Edit/Rename Cancel/Save, and dirty-close confirmation; clean cancel and both Keep/Discard routes pass.
- [x] Add a result-returning panel save boundary so the editor closes only on successful atomic persistence; deterministic failure retains the exact draft and shows an inline actionable error.
- [x] Ensure cancellation and `Keep Editing` perform no repository writes, metrics, clipboard changes, or destination handoff; repository/state tests and dirty-editor UI coverage pass.

### Action outcomes and system states

- [x] Route Return, direct paste, fallback copy, open, copy, drag, archive, pin, and Trash through explicit success/failure outcomes; successful close/stay-open and failure preservation match the action table.
- [x] Add immediate feedback and Undo for reversible Trash actions without routine confirmation; atomic batch rollback and undo restoration are covered by repository tests.
- [x] Represent retrieval search as loading, valid, empty, and failed states while retaining local/stale valid results during work/failure; no-results, failure, retry, clear-filter, and fullwidth input paths are covered.
- [x] Implement mode-empty, copy-success, copy-only, disabled direct paste, missing attachment/icon, and action-error presentations with actionable labels; focused tests and deterministic Debug-only UI fixtures cover these states.

### Accessibility, compatibility, and documentation

- [x] Extend `StowMacUITests.swift` for visible Close, layered More/Escape, shortcut toggle, outside click, focus restoration, clean/dirty cancellation, discard confirmation, exact Save-failure draft retention, destination handoff, accepted drag, fullwidth search input, action outcomes, and responsive states.
- [x] Add accessibility assertions for unique Close/Clear Search names, toolbar-to-timeline focus order, confirmation focus, status semantics, and keyboard-only exit. Evidence: named-control, status, focus, confirmation, and keyboard automation is implemented; Increase Contrast passes visual inspection; on 2026-08-09 the owner excluded VoiceOver and accepted the current single-display Mac as the release scope.
- [x] Verify backward compatibility for item data, unknown UserDefaults values, shortcut choices, clipboard-monitoring state, per-display height, `Command-C` keep-open behavior, and unchanged iOS compilation/tests; evidence is recorded in the release matrix.
- [x] Update `README.md`, `docs/release/v0.1-accessibility-audit.md`, and `docs/release/v0.1-test-matrix.md` with the close/cancel flow, direct/copy-only status, dirty-edit behavior, keyboard controls, fullwidth-input tolerance, automated evidence, and bounded manual checks.

### Final verification and handoff

- [x] `git diff --check` passed after the completed implementation.
- [x] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/StowCore` passed: 54 tests, 0 failures.
- [x] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Stow.xcodeproj -scheme Stow-macOS CODE_SIGNING_ALLOWED=NO build` succeeded.
- [x] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Stow.xcodeproj -scheme Stow-iOS -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build` succeeded.
- [x] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Stow.xcodeproj -scheme StowMacUITests CODE_SIGN_ENTITLEMENTS='' CODE_SIGN_IDENTITY='-' test` passed after the completed implementation and grouped test cleanup: 9 tests, 0 failures in 263.209 seconds; result bundle `/tmp/StowMacUITests-final.xcresult`.
- [x] Present normal, compact, search, copy-only, dirty-confirmation, error, light, dark, and narrow screenshots for user review. Evidence: the complete capture set is published in `docs/release/v0.1-quick-panel-visual-review.md`, and the owner explicitly approved it on 2026-08-09.
- [x] Move this fully checked plan to `docs/plans/archived/2026-08-09_quick-panel-close-flow-plan.md`. Evidence: all implementation and completion items were checked before archival on 2026-08-09.

## Completion Checklist

- [x] The user approved the interaction design before implementation began.
- [x] Pointer, keyboard, shortcut, outside-click, and destination close routes share one tested policy.
- [x] Close is always visible and distinct from Clear Search in every supported layout/state.
- [x] Escape is predictably layered; explicit Close remains fast; focus returns to the correct app.
- [x] Dirty edits cannot be lost silently, cancellation has no side effects, and failed saves retain drafts.
- [x] Loading, empty, success, error, disabled, and partial states are distinct and actionable.
- [x] Direct Paste/Copy-only and paused-monitoring states are visible where they affect decisions.
- [x] Primary actions, confirmation, cancellation, navigation, failure, responsive, automated accessibility, and compatibility tests pass.
- [x] Existing workflows, data, unknown settings, panel height, macOS shortcuts, and iOS behavior remain compatible.
- [x] User-facing documentation and release evidence describe the final behavior.
- [x] Final screenshots received explicit owner approval on 2026-08-09.
- [x] The completed plan is archived with all evidence and no unchecked tasks at `docs/plans/archived/2026-08-09_quick-panel-close-flow-plan.md`.
