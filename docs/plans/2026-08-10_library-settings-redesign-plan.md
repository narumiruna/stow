# Stow macOS Library and Settings Redesign Plan

**Status:** In progress (approved 2026-08-10)
**Date:** 2026-08-10

## Goal

Improve the macOS Library and Settings so people can scan, manage, edit, configure, and recover without clipped or ambiguously truncated text, unsafe state transitions, or duplicated navigation. Preserve all stored content and preferences, keep iOS/iPadOS behavior compatible, and leave the current Quick Panel visual and interaction design unchanged.

The objective is complete only when the supported Library and Settings states are implemented, the refreshed screenshots are visually approved, all required non-interactive checks and the one final local UI-test batch pass, the final diff contains no unrelated changes, and every completion checkbox is verified.

## Context

- The checked-in Library screenshot at `docs/release/assets/stow-macos-library.png` visibly clips the filter row at the List/Detail divider: `All sources` is cut off and the date filter is not visible. The list is compressed while an unselected detail column consumes most of the window.
- `Sources/StowApp/Shared/StowRootView.swift` presents Settings as a Library section even though `Sources/StowApp/macOS/StowMacApp.swift` also owns a native Settings scene. The same shared `StowSettingsView` is therefore used in two different containers.
- `Sources/StowApp/Shared/ItemCollectionView.swift` lays out three menu pickers in a horizontal row without an adaptive summary. Its empty state distinguishes search text but not active filters.
- `Sources/StowApp/Shared/StowItemDetailView.swift` records a use when detail appears, conflating Library browsing with retrieval; its `Done` action exits editing even when save fails; and its Trash action can render `Restore` with a destructive role.
- `Sources/StowApp/Shared/StowSettingsView.swift` places Privacy, Sync, Clipboard, Direct Paste, Keyboard Shortcuts, and Storage in one long grouped form. Long status and recovery copy are rendered in layouts that can compress labels and values.
- `Sources/StowApp/macOS/GlobalHotKeyService.swift` unregisters all working shortcuts before testing a replacement. A conflict can therefore leave both shortcuts unavailable instead of preserving the previous valid configuration.
- `docs/release/support.md` directs people to `Rebuild Search Index` in Settings, but the current Settings UI has no such action.
- Existing macOS visual review covers the Quick Panel, not Settings. Fresh Settings and minimum-width Library screenshots are required evidence.
- `AGENTS.md` requires all interactive UI orchestration to remain in `Scripts/ui_tests.sh`, forbids UI tests during implementation, and requires one accumulated final UI-test batch after implementation and non-interactive checks.
- A fresh local `xcodebuild` currently fails because the host Xcode cannot load `IDESimulatorFoundation` without `/Library/Developer/PrivateFrameworks/CoreSimulator.framework`. This is an environment verification risk, not a reason to weaken or mark checks complete.

## Architecture

- Introduce macOS-specific Library and Settings composition under `Sources/StowApp/macOS/` so the management experience can follow macOS window, selection, toolbar, and Settings conventions without restructuring the iPhone/iPad interface.
- Keep shared domain state and persistence in `AppModel` and `StowCore`; extract only testable presentation/state policies needed for Library editing, batch actions, filter summaries, Settings status, and shortcut transactions.
- Keep `StowRootView`, `ItemCollectionView`, `StowItemDetailView`, and the shared Settings path available to iOS/iPadOS unless a narrowly scoped shared correctness fix is required and covered on both platforms.
- Make the native macOS Settings scene the canonical Settings workspace. Keep entry points in the app menu, menu bar, and Quick Panel More menu, but remove Settings from the macOS Library sidebar.
- Preserve current UserDefaults keys (`analyticsEnabled`, `clipboardMonitoringEnabled`, `quickAddShortcut`, `quickPanelShortcut`, and per-display panel heights). Persist shortcut changes only after both proposed registrations succeed; on failure, restore the previous registrations and stored values.
- Do not change the SwiftData schema or migrate item/attachment data. Preserve IDs, capture IDs, status, pin state, timestamps, use counts, attachments, unknown persisted fields, CloudKit/App Group behavior, and the local-only development fallback.

## Non-Goals

- Redesigning or recoloring the macOS Quick Panel, renaming its modes, changing its card system, or changing its keyboard/close behavior.
- Redesigning Quick Add, share extensions, iPhone, or iPad interfaces beyond compatibility fixes required by shared code.
- Adding collections, collaboration, OCR, AI, remote analytics, permanent-delete controls, or a new persistence schema.
- Expanding the accepted release matrix to manual VoiceOver or multiple displays unless separately requested.

## Assumptions

- The supported macOS Library minimum remains `840×560`; representative verification widths are 840, 1080, and a wide desktop window.
- The native Settings window may enforce a larger practical minimum width than today when necessary to prevent clipping, but long guidance and errors must still wrap rather than disappear.
- `Recently Used` is a clearer macOS Library label for the existing `Recent` behavior; the underlying query semantics remain based on `lastUsedAt`.
- Multi-selection belongs in the management Library, while the Quick Panel remains unchanged.
- App-owned text clipping, overlap, or decision-relevant ellipsis is release-blocking. User content such as long titles and filenames may use bounded truncation only when the full value remains available through detail, selection, or an accessibility value and the truncation is visually unambiguous.

## Risks

- A macOS-specific Library can drift from shared lifecycle/search behavior. Mitigation: reuse `AppModel` operations, test section/filter semantics, and compile/run the iOS path after each shared change.
- NavigationSplitView sizing can vary by macOS release. Mitigation: use explicit practical column minima, adaptive toolbar disclosure, frame-containment assertions, and screenshots at every supported width instead of relying on one ideal layout.
- Multi-selection can make mixed Pin or lifecycle actions ambiguous. Mitigation: define `Pin All` when any selected item is unpinned, `Unpin All` only when all are pinned, and expose Archive/Restore actions only in sections where the result is uniform.
- Shortcut replacement touches global Carbon registrations. Mitigation: separate registration from persistence, use a fake registrar for deterministic failure tests, and restore the last valid pair before reporting failure.
- Permission and sync state can change while Settings remains open. Mitigation: refresh on scene activation and keep denied/paused states actionable without repeatedly prompting.
- Visual evidence cannot be regenerated until the Xcode installation is repaired. All affected checks stay unchecked until the commands and screenshot batch actually succeed.

## Rollback / Recovery

- Keep the redesign isolated to macOS views and testable policies so reverting the macOS composition restores the prior Library/Settings UI without data migration.
- Do not delete or rewrite existing preferences. If a new presentation preference becomes necessary, provide a default compatible with absent values and leave unknown keys untouched.
- On shortcut apply failure, re-register and display the previous valid configuration before returning control to Settings; never persist the rejected candidate.
- On Library edit failure, retain the complete draft and previous saved item. On cancellation, discard only the draft. On Trash actions, preserve the existing 30-day restore path and offer immediate Undo where the row leaves the current section.

## Plan

- [x] Add executable macOS presentation/state specifications before behavior changes: create focused `StowAppTests` for filter-summary rules, section labels, Library selection not counting as retrieval, mixed-selection batch labels, edit cancellation/save failure, Settings page/status models, and transactional shortcut replacement using a fake registrar; verify each new behavior test fails for the intended reason with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Stow.xcodeproj -scheme StowAppTests CODE_SIGNING_ALLOWED=NO test`, or record the current Xcode environment failure while leaving this item unchecked.
  - Evidence: the four new `StowAppTests` files fail to compile against pre-redesign commit `be1bfdd` (missing Library policy, transactional shortcut backend, and rebuild-recovery APIs), then pass as 24/24 native app tests on the completed implementation.

- [x] Establish macOS-only composition boundaries without changing observable behavior: route the macOS Library window and managed Library handoff to a dedicated Library root, route the native Settings scene to a dedicated macOS Settings root, retain the shared iOS/iPadOS roots, and regenerate `Stow.xcodeproj` if files are added; verify with `ruby Scripts/generate_project.rb`, the focused `StowAppTests`, and unsigned macOS/iOS builds before proceeding to visual restructuring. **Safe checkpoint:** revert only the new composition wiring if either platform no longer builds.
  - Evidence: macOS uses `MacLibraryView` and `MacSettingsView`, `StowRootView` remains the iOS root, project generation is stable, and `Scripts/ci.sh` passes both platform builds, 54 core tests, 24 app tests, entitlements, and privacy-manifest checks.

- [ ] Rebuild the macOS Library information architecture around management: show Inbox, Recently Used, Pinned, Archive, and Trash in the sidebar; remove only the duplicate macOS Library Settings row; keep search, Quick Add, standard sidebar disclosure, current item data, and explicit Settings entry points elsewhere; verify destination labels, keyboard traversal, empty selection, and app/menu/panel Settings handoffs with unit assertions plus the final macOS UI batch.

- [ ] Replace the clipping-prone three-picker strip with an adaptive Library filter control: provide one clearly labeled Filter menu for type/source/date, show active criteria as removable summaries only when they fit, collapse to a count/summary at constrained widths, distinguish active-filter empty results from a genuinely empty section, and provide `Clear Filters`; verify filter combinations and empty-state copy with focused state tests, then verify no control or active criterion crosses the list/detail divider at 840, 1080, and wide widths in the final UI screenshots.

- [ ] Make Library columns and rows resilient to real content: assign practical sidebar/list/detail minima, let secondary toolbar actions move into labeled disclosure before text clips, wrap the privacy/storage footer, keep source/time/status readable, expose full long titles/filenames through detail and accessibility values, and prevent critical labels from using ambiguous ellipsis; verify with deterministic short/long fixtures, frame-containment UI assertions, English localization export, and visual inspection at minimum and wide window sizes.

- [ ] Implement explicit Library selection and lifecycle behavior: support single selection for detail and multi-selection for management; use deterministic `Pin All`/`Unpin All`, Archive/Restore, and Move to Trash actions; omit inapplicable Archive actions in Trash; render Restore as non-destructive; label deletion consistently as `Move to Trash`; and provide Undo when an item leaves the current section; verify every single/multi/mixed action with focused tests and final keyboard/pointer UI scenarios.

- [ ] Make Library preview and editing safe and semantically accurate: stop recording `lastUsedAt`/use count merely because a Library detail appears, record use only for explicit Copy/Open/Quick Look/Share/drag actions as appropriate, replace `Done` editing with distinct `Cancel` and `Save Changes`, confirm dirty dismissal, apply successful edits atomically, and retain the full draft plus previous saved state on failure; verify red→green tests for counters, clean/dirty cancellation, successful save, failed save, focus return, and navigation away.

- [ ] Reorganize native macOS Settings by user goal without creating Basic/Advanced tiers: provide Capture, Paste & Shortcuts, Sync & Storage, and Privacy destinations; use aligned native controls; render long guidance, status, errors, and recovery actions as full-width wrapping rows; keep permission requests explicit and user-initiated; and refresh Accessibility, clipboard, sync, storage, and registration state when the scene becomes active; verify each idle/loading/available/denied/paused/error state through injected deterministic state and minimum-width screenshots.

- [ ] Make shortcut changes transactional: refactor `GlobalHotKeyService` to register an explicit candidate configuration independently of UserDefaults, apply both shortcuts as one transaction, persist only on success, and restore the previous pair and visible selections on any conflict; keep the existing keys and alternatives; verify success, first-shortcut conflict, second-shortcut conflict, restoration failure reporting, relaunch persistence, and unchanged Quick Panel/Quick Add invocation with fake-registrar unit tests plus the final macOS UI batch.

- [x] Restore promised Settings recovery behavior: add a `Rebuild Search Index` action backed by an explicit `AppModel` recovery operation, show in-progress/success/failure feedback locally, retain the existing index and usable search state until replacement succeeds, and keep Settings usable offline; verify deterministic rebuild success/failure tests and reconcile `docs/release/support.md` with the implemented behavior.
  - Evidence: `SQLiteSearchIndex.rebuild` rolls back an injected replacement failure while preserving the previous index; all three recovery tests pass and `docs/release/support.md` documents the non-destructive failure path.

- [x] Add accessibility and regression instrumentation before interactive verification: assign stable identifiers and meaningful labels/values to new Library/Settings controls, define logical keyboard/focus order, avoid color-only state, respect Dark Mode/Increase Contrast/Reduce Motion, remove any app-owned text-clipping exception introduced by the redesign, add deterministic launch fixtures for long text, permission denial, sync pause, save failure, and shortcut conflict, and confirm no production or sensitive content is captured; verify through `StowAppTests`, source inspection, and successful compilation without running UI tests yet.
  - Evidence: deterministic DEBUG-only fixtures and stable identifiers cover Library, Settings, editing, failure, and recovery states; 24 app tests pass and both UI schemes compile with `build-for-testing` before interactive execution.

- [ ] Update user-facing and release documentation after behavior stabilizes: revise `README.md`, `docs/release/support.md`, `docs/release/v0.1-accessibility-audit.md`, `docs/release/v0.1-test-matrix.md`, and App Store screenshot metadata; add a bounded Library/Settings visual-review document covering normal, minimum-width, long-content, empty, editing, failure, permission, shortcut-conflict, light/dark, Reduce Motion, and Increase Contrast states; verify every documented control and recovery path exists in the built app and that Quick Panel documentation remains unchanged.

- [x] Run all non-interactive quality gates before any UI test: execute `ruby Scripts/generate_project.rb`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/StowCore`, the `StowAppTests` scheme, unsigned Debug macOS and iOS builds, localization export, entitlement verification, and finally `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/ci.sh`; fix implementation failures, but leave checks unchecked and report the external blocker if the host Xcode plugin failure persists.
  - Evidence: project generation is idempotent; 54 core and 24 app tests pass; unsigned macOS/iOS builds, English localization export, entitlement/privacy checks, and the final original-Xcode `Scripts/ci.sh` run all exit successfully.

- [ ] Run one accumulated final interactive batch only after all implementation and non-interactive checks pass: execute `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/ui_tests.sh`, capture the complete macOS Library and Settings screenshot matrix from the passing result bundle, regenerate `docs/release/assets/stow-macos-library.png` and approved new Settings assets, inspect every screenshot for clipping/overlap/ambiguous truncation/disruptive shifts, and compare existing Quick Panel screenshots and workflows for regressions; if the batch fails, group related fixes and rerun the complete batch rather than individual UI tests.

- [ ] Audit the final diff and plan evidence: compare every changed file against this scope, confirm no Quick Panel presentation/interaction source changed, confirm no SwiftData migration or preference loss was introduced, confirm the pre-existing untracked `package-lock.json` was not incorporated, append concise command/screenshot evidence to each completed checkbox, and request renewed approval before continuing if any major scope, architecture, risk, or acceptance criterion changed.

## Completion Checklist

- [ ] The macOS Library has Inbox, Recently Used, Pinned, Archive, and Trash management with no duplicate Settings destination, verified by focused tests and the passing final macOS UI navigation scenario.
- [ ] At 840×560, 1080×720, and a wide Library window, app-owned labels, filters, statuses, actions, footer copy, and decision-relevant values are not clipped, obscured, or ambiguously truncated, verified by frame assertions and approved screenshots with short and long fixtures.
- [ ] Library filtering exposes type/source/date criteria, active summaries, removal, clear, loading/empty/error distinctions, and usable narrow behavior, verified by focused tests and final screenshots.
- [ ] Library browsing does not mutate retrieval history; explicit use actions do; editing has distinct Cancel/Save Changes, dirty confirmation, atomic success, and draft-preserving failure, verified by passing counter and editing tests.
- [ ] Single and multi-item Pin, Archive/Restore, Move to Trash, Undo, and Trash Restore behavior is deterministic, correctly labeled, and never styles Restore as destructive, verified by focused tests and final UI scenarios.
- [ ] Native macOS Settings is organized into Capture, Paste & Shortcuts, Sync & Storage, and Privacy; all relevant loading, available, denied, paused, conflict, success, and failure states wrap and remain actionable at minimum width, verified by approved light/dark/accessibility screenshots.
- [ ] Shortcut replacement is atomic and preserves both prior working registrations and stored values on conflict, verified by fake-registrar tests and a passing final shortcut UI scenario.
- [ ] Search-index recovery in Settings matches support documentation and preserves the previous usable state on failure, verified by deterministic tests and documentation inspection.
- [ ] Existing item/attachment data, unknown persisted fields, UserDefaults keys, local-only/CloudKit behavior, Trash retention, and iOS/iPadOS compatibility are preserved without a schema migration, verified by core tests, schema inspection, and unsigned platform builds.
- [ ] The current Quick Panel visual and interaction design is unchanged, verified by an empty relevant source diff or explicitly justified non-presentation fix, passing existing Quick Panel UI scenarios, and comparison with the approved screenshot set.
- [ ] `Scripts/ci.sh` and the one final `Scripts/ui_tests.sh` batch pass on the required toolchain, with failures or environment blockers left plainly unchecked rather than inferred complete.
- [ ] README, support, accessibility audit, test matrix, App Store screenshot metadata, and the new Library/Settings visual review match the implemented experience, verified by source-to-document inspection.
- [ ] The final diff contains no unrelated changes and does not include the pre-existing untracked `package-lock.json`, verified by `git status --short`, `git diff --check`, and final diff review.
- [ ] Every Plan and Completion Checklist item contains current verification evidence; then set this plan status to `DONE`, move it to `docs/plans/archived/2026-08-10_library-settings-redesign-plan.md`, and report the archived path without overwriting an existing file.
