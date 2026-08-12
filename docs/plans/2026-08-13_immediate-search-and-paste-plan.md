# Immediate Search and Paste Plan

**Status:** Planned

**Date:** 2026-08-13

## Goal

Make the primary Stow workflow require only three actions: open the Quick Panel, type enough to identify an item, and press Return to use it.

Success means a user never has to click Search, choose a result mode, or understand Accessibility permissions before the basic copy fallback works.

## Context

`Sources/StowApp/macOS/RetrievalPanel.swift` already supports type-to-search, live local search, automatic first-result selection, and Return.

`Sources/StowApp/macOS/RetrievalPanelController.swift` already remembers the originating application and chooses direct paste or copy-only fallback.

This plan hardens and proves that path rather than adding another search surface or redesigning the panel.

## Product Contract

- Opening the panel selects the most recent eligible item and leaves horizontal navigation ready.
- Typing an unmodified printable character opens Search and preserves the first character exactly once.
- `Command-F` remains a discoverable alternative but is never required.
- Return uses the selected result through one shared action path whether focus is in Search or the timeline.
- Direct paste closes the panel and returns to the originating application when Accessibility permission and a valid target are available.
- Copy fallback writes the same item, shows “Copied — paste with Command-V,” closes the panel, and returns focus without prompting for permission.
- An empty result set does nothing on Return and never uses a stale selection.
- Escape continues to dismiss preview/menu state, clear criteria, collapse Search, and finally close the panel in that order.

## Architecture

Keep query and selection ownership in `RetrievalPanelView`.

Keep target-application capture, panel dismissal, and paste orchestration in `RetrievalPanelController`.

Extract only the keyboard routing rules into a small pure policy type if that is required to test printable keys, modifiers, and first-character preservation without UI automation.

Keep `PlatformActions.copy` as the pasteboard-writing boundary and `ItemActionService` as the single successful-use accounting boundary.

## Non-Goals

- Do not make the search field permanently visible or focused on every open.
- Do not add fuzzy, semantic, OCR, or network search.
- Do not add another global shortcut or change the default `Command-Shift-V` shortcut.
- Do not change filters, cards, collections, or Library navigation.
- Do not auto-request Accessibility permission from the primary flow.

## Plan

- [ ] Add focused `StowAppTests` coverage for the input contract, including an ordinary printable character, Command/Control/Option-modified keys, Space, Return, empty results, and stale-selection repair; verify with `xcodebuild -project Stow.xcodeproj -scheme StowAppTests CODE_SIGNING_ALLOWED=NO test`.
- [ ] Refactor the type-to-search routing in `Sources/StowApp/macOS/RetrievalPanel.swift` into a pure policy only if the tests cannot exercise it directly, while preserving the current collapsed toolbar and keyboard shortcuts; verify the policy tests pass and the view contains only one type-to-search entry point.
- [ ] Make search-result selection deterministic so the first current result is selected, a surviving selection is retained, and zero results clear both `selection` and `selectedIDs`; verify with unit tests that Return cannot use an item excluded by the current query or filter.
- [ ] Route Return from the Search field, timeline, double-click, numbered shortcuts, and the context-menu Use action through the same `performDefault`/controller path; verify with source inspection and tests that each successful use reaches `ItemActionService` exactly once.
- [ ] Make the direct-paste decision an explicit outcome in `Sources/StowApp/macOS/RetrievalPanelController.swift`, with deterministic copy fallback when the target application is missing, terminated, or Accessibility permission is unavailable; verify with `StowAppTests` using injected paste capability and target-state doubles rather than the desktop UI.
- [ ] Preserve the existing visible Direct/Copy-only status and concise fallback message without adding a modal permission prompt; verify the relevant accessibility labels and status strings in `Tests/StowAppTests`.
- [ ] Extend the existing final macOS UI scenario to open Stow from TextEdit, type a query without clicking Search, press Return, and verify both forced direct-paste and forced copy-only outcomes; keep orchestration exclusively in `Scripts/ui_tests.sh` and do not run it until all four clipboard plans have passed non-interactive checks.
- [ ] Update `README.md` and `docs/release/v0.1-test-matrix.md` to describe the no-click type-to-search contract and the copy fallback; verify the documentation matches the tested shortcuts and result states.
- [ ] Run the non-interactive repository gate with `Scripts/ci.sh`; verify core tests, `StowAppTests`, macOS build, iOS build, and entitlement checks all pass before any interactive UI batch.

## Risks

- A root-level printable-key handler can interfere with input methods, dead keys, or accessibility input if it consumes keys before text composition.
- Multiple Return handlers can double-record use or paste a stale item unless they converge on one action boundary.
- Closing the panel before validating the originating application can create an apparent no-op even though the clipboard write succeeded.
- Making Search permanently focused would simplify one path but make arrows, Space preview, and quick item navigation less predictable.

## Completion Checklist

- [ ] Opening the panel and typing immediately is verified by a focused macOS UI assertion that does not click Search first.
- [ ] First-character preservation and modifier routing are verified by passing `StowAppTests`.
- [ ] Return never uses a stale or absent result, as verified by selection-policy tests.
- [ ] Direct paste and copy fallback each record one successful use, as verified by `ItemActionService` or controller tests.
- [ ] The complete non-interactive gate passes with `Scripts/ci.sh`.
- [ ] After all four plans are implemented, the accumulated interactive scenarios pass together in one final `Scripts/ui_tests.sh` batch.
