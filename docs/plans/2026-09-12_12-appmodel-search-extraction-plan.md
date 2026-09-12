# AppModel Search Extraction Plan

## Goal

Move search-index ownership, rebuild coordination, fingerprints, and query execution out of `AppModel` into one testable component.

## Context

`AppModel.swift` currently owns UI state plus index construction, three search entry points, two generation counters, rebuild state, date translation, and cache fingerprints. Separate async flows can interleave rebuild and query operations.

## Architecture

Add a `SearchCoordinator` actor that owns `SQLiteSearchIndex`, the indexed fingerprint, atomic ensure-index-and-search operations, and explicit rebuilds. `AppModel` remains the observable UI adapter and owns only request generations and presentation state.

## Non-Goals

- Do not change search syntax, ranking, or filters.
- Do not redesign search UI.
- Do not move capture or maintenance behavior in this PR.

## Plan

- [ ] Add `SearchCoordinator` with injected index operations and methods for explicit rebuild plus atomic ensure-index-and-search.
- [ ] Move document fingerprinting and index freshness decisions into the coordinator; verify concurrent callers cannot query an index rebuilt for a different document set.
- [ ] Move date/status query construction into focused pure helpers with fixed-clock tests.
- [ ] Replace `AppModel`'s library, retrieval, and automation search implementations with thin coordinator calls while preserving their cancellation-generation behavior.
- [ ] Move search recovery tests to the coordinator where possible and add an interleaving regression test with controllable suspensions.

## Completion Checklist

- [ ] Core search tests and `SearchIndexRecoveryTests` pass.
- [ ] `StowAutomationHostServiceTests` search cases pass.
- [ ] macOS and iOS non-interactive builds pass.
- [ ] `AppModel.swift` no longer owns `SQLiteSearchIndex` or an index fingerprint.
- [ ] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/ci.sh` passes without invoking UI tests.
- [ ] `git diff --check` passes.
