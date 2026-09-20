# Follow-up Behavior-Preserving Simplifications Plan

## Goal

Reduce duplicated retrieval logic, shortcut configuration, fallback matching, editor state, and release metadata without changing externally observable behavior.

Execution authorized by the user on `narumi/refactor/follow-up-simplifications`, based on `origin/main` at `2143ba1`. Authorization includes the plan's minimal storage-isolation prerequisite, signed commits, push, and a pull request; releases and tags remain excluded.

## Context

The review confirmed six independently actionable opportunities, all Medium priority:

| Area | Evidence |
|---|---|
| macOS copy orchestration | `Sources/StowApp/macOS/RetrievalPanelController.swift:337,358` and `Sources/StowApp/macOS/MacLibraryView.swift:278,888` repeat representation lookup, clipboard writing, and usage accounting. |
| Shortcut configuration | `Sources/StowApp/macOS/MacSettingsModels.swift:21` duplicates `GlobalHotKeyService.swift:27`; the transaction converts the same pair of identifiers at `MacSettingsModels.swift:56`. |
| Local search fallback | `Sources/StowApp/macOS/MacLibraryView.swift:347` and `RetrievalPanel.swift:1243` repeat metadata predicates and width-normalized substring matching across six fields. |
| iOS editor state | `Sources/StowApp/iOS/StowItemDetailView.swift:181` wraps a synchronous Boolean save in a transition model whose dirty/error state has no presentation or navigation consumer in that view. |
| Library drag providers | `Sources/StowApp/iOS/StowItemDetailView.swift:321` and `Sources/StowApp/macOS/MacLibraryView.swift:955` repeat provider registration and main-actor callback forwarding. |
| Release version ownership | `Scripts/generate_project.rb:108` repeats `VERSION`; `Scripts/bump_version.sh:80` rewrites the Ruby assignment and `Scripts/verify_version.sh:41` parses its source syntax. |

Review baseline on Xcode 26.6 / Swift 6.3.3: 130 package tests and 6 share-extension tests passed; macOS app/test compilation, the iOS simulator build, version-script tests, generator checks, and static checks passed. These results are pre-change evidence, not acceptance of future implementation. Hosted `StowAppTests` and interactive UI tests were not executed.

## Architecture

- Put copy orchestration in one macOS-specific `AppModel` method; retain clipboard encoding in `PlatformActions` and panel closing/direct paste in the controller.
- Use one shortcut value throughout Settings and registration; retain registration-before-persistence as a distinct transaction boundary.
- Share only identical local predicates and Library provider construction. Keep SQLite query semantics and Quick Panel's native drag-acceptance path separate.
- Preserve the panel's editor transition model; simplify only the iOS consumer that does not use its transition policy.
- Make `VERSION` authoritative for generator input while retaining the checked-in generated project and shell-only release verification.

## Non-Goals

- Do not change persistence schemas, migrations, capture/coalescing policy, attachment materialization, App Group paths, or CLI protocol/output.
- Do not change UI copy, accessibility identifiers, navigation, search timing, ordering, matching semantics, clipboard formats, or usage accounting.
- Do not fix adjacent behavior differences, including the iOS context menu's data-only copy path or iOS navigation without discard confirmation.
- Do not introduce generic action runners, search frameworks, service locators, or interchangeable drag backends.
- Do not remove public `StowCore` APIs based only on repository-local caller counts.
- Do not change the CLI's independent version literal as part of release metadata cleanup.

## Plan

### 0. Establish safe validation prerequisites

- [x] Recheck the cited implementations and their callers against the execution revision; acceptance: record any changed scope here before editing and retain only behavior-equivalent extractions.
- [x] Verify the separately scoped [app storage test-isolation prerequisite](2026-09-12_01-app-storage-test-isolation-plan.md) before running hosted tests; acceptance: host bootstrap, connected test models, and maintenance use test-owned storage and temporary roots, with a regression proving a separate sentinel capture remains untouched. Until then, do not execute `StowAppTests` or the full `Scripts/ci.sh`; builds and isolated package/share tests remain available.

Prerequisite evidence: the XCTest host now enters only an inert AppKit event loop; connected model fixtures inject shared and temporary roots. `StowRuntimePathsTests` passed (2 tests) after successful build-for-testing on Xcode 26.6. Tests prove in-memory host storage, owned roots, capture ingestion confined to injected storage, and untouched sentinel captures/expired files in a separate runtime. Production storage resolution remains unchanged. A proposed conditional SwiftUI Scene did not compile; the explicit test entry point replaces it.

Sections 1–6 are separate reviewable changes. Apply shared-file edits sequentially. Section 6 does not depend on hosted-test isolation. Accumulate all interactive scenarios for section 7 rather than running UI tests after individual changes.

### 1. Centralize macOS copy-and-accounting behavior

- [x] Add one macOS-specific `AppModel` copy method accepting the item, attachment, and paste format, then replace the four implementations in `RetrievalPanelController.swift` and `MacLibraryView.swift`; acceptance: one method owns representation lookup and `performUse(.copy, .itemCopied)`, while callers retain their existing feedback, direct-paste, and closing behavior.
- [x] Preserve the current operation sequence and failure behavior in that method; acceptance: isolated orchestration tests cover original/plain-text formats, missing attachments, failed writes, and representation-fetch failure, asserting unchanged clipboard payload, usage count, metrics, and error presentation. A failed representation lookup must retain the existing continue-with-empty-representations behavior.
- [x] Run `PlatformActionsPasteTests` and package `ItemActionServiceTests` plus the new orchestration tests; acceptance: all pass without operating the general clipboard or desktop UI.

Copy evidence: 3 orchestration tests, 2 platform paste tests, and 2 package action tests passed. The fixture uses an independently owned `ModelContext`; the initial fixture incorrectly let the container's main context outlive its container and crashed, corrected before acceptance. No general clipboard access.

### 2. Use one shortcut configuration value

- [x] Replace `MacShortcutConfiguration` and `GlobalHotKeyService.Configuration` with one mutable value used by `MacSettingsView`, `MacAppCoordinator`, `MacShortcutTransaction`, and `GlobalHotKeyService`; acceptance: no pair-to-pair conversion or duplicated default identifiers remain.
- [x] Consolidate configuration loading and persistence without moving preference writes into registration; acceptance: existing preference keys, raw values, unknown-key fallback, registration labels, error messages, and rollback behavior remain unchanged.
- [x] Run isolated `GlobalHotKeyServiceTests` and `MacSettingsModelsTests`, extending fixtures for absent and unknown preference values; acceptance: both candidate-conflict positions, restoration failure, explicit registration without preference writes, and preservation of unrelated defaults pass.

Shortcut evidence: all 9 registration/settings tests passed with fake backends and isolated defaults, including missing/unknown values and both rollback conflict positions. Settings and coordinator already consumed the retained value type, so no changes to their UI/transaction callers were needed.

### 3. Share the local-search fallback

- [x] Extract domain-specific metadata and per-field text predicates from `MacLibraryView` and `RetrievalPanel`; acceptance: both call the same implementation for type/source/date filtering and width-normalized substring matching, with collection membership, result freshness, fallback selection, and ordering still owned by the callers.
- [x] Add table-driven fallback tests using fixed dates; acceptance: title, text, URL, source domain, note, and filename each match as before, including empty queries, fullwidth text, punctuation, exact source comparison, and date boundaries. Preserve per-field matching rather than joining fields or applying SQLite token/prefix rules.
- [x] Run the new isolated fallback tests, `SearchIndexRecoveryTests`, and package `SearchServiceTests`; acceptance: local matching and indexed search retain their separate semantics and cancellation/recovery behavior.

Search evidence: 4 local fallback tests, 9 search recovery tests, and 6 package search tests passed. Fixed Gregorian/UTC fixtures cover exact lower boundaries and the existing inclusion of future dates; fields remain independently matched. Caller-specific indexed-result freshness, membership and ordering are unchanged.

### 4. Remove unused iOS editor transition state

- [x] Replace `StowItemDetailView.toggleEditing()` with direct handling of `AppModel.save` success and remove this view's transition-model state and four dirty observers; acceptance: draft fields and `editing` remain, success exits editing, and failure leaves the complete draft editable with the existing global alert.
- [x] Preserve the shared panel transition model and iOS navigation behavior; acceptance: diff review shows no change to panel discard policy, draft initialization, field normalization, navigation interception, or user-facing controls.
- [ ] Build the iOS target and add failure-and-retry coverage alongside `testDetailEditingPersistsNote` in `Tests/StowUITests/StowUITests.swift`; acceptance: compilation passes and the new scenario verifies retained draft, unchanged saved content after failure, and successful retry. Execute these UI scenarios only in section 7.

iOS evidence: the simulator app build passed for both architectures. The new code-item failure/retry scenario checks all draft fields and the unchanged saved preview using empty-content validation, without a new production failure hook. UI execution remains deferred to the final batch, so the scenario's acceptance task remains open.

### 5. Share Library drag-provider construction

- [x] Add a shared Library `NSItemProvider` helper accepting `DragPayload` and a main-actor callback, then delegate both Library detail views to it; acceptance: one implementation registers the data representation and suggested name, and the two forwarding success-token classes are removed without replacement unchecked-concurrency wrappers.
- [x] Add non-interactive provider-loading tests and run package `DragPayloadTests`; acceptance: bytes, type identifier, suggested name, visibility, and callback order/frequency remain unchanged, with no callback before a load and one callback for each load request.
- [x] Keep Quick Panel's `PanelCardDragSourceView` and `NSDraggingSession` completion handling separate; acceptance: no changes to destination-acceptance accounting, cancellation, panel closing, or temporary-file cleanup in that path.

Drag evidence: real `NSItemProvider` loading passed for text, URL and binary attachment payloads, two requests apiece, with no callback at construction; both package payload tests passed. Static review confirms unchanged `.all` visibility and completion-before-main-actor-task order in the single registration handler. Foundation can deliver its public client callback later than that handler's completion, so an initial test incorrectly requiring client delivery before accounting was removed; that stronger ordering was never guaranteed by either old implementation. No provider backend or unchecked forwarding wrapper was added; native panel drag handling is untouched.

### 6. Derive generator version input from VERSION

- [ ] Read `VERSION` once in `Scripts/generate_project.rb` instead of embedding a release literal; acceptance: generation at the current version produces byte-for-byte identical project settings and schemes.
- [ ] Remove generator-source replacement, backup, and literal parsing from `Scripts/bump_version.sh` and `Scripts/verify_version.sh`; acceptance: shell-only scripts still enforce strict version/tag syntax, consistent Xcode settings, existing bump arithmetic, and rollback on failed updates, without requiring Ruby or `xcodeproj` on Ubuntu.
- [ ] Update version-test fixtures, `.github/workflows/bump-version.yml` staging paths, and README release instructions; acceptance: a bump changes only `VERSION` and the project's version settings, preserves output and tag conventions, and no longer stages generator source.
- [ ] Run `Scripts/bump_version_tests.sh`, `Scripts/verify_version_tests.sh`, `Scripts/verify_version.sh`, `Scripts/generate_project_tests.sh`, and `ruby Scripts/generate_project.rb --check`; acceptance: all pass, rejected bumps leave fixtures unchanged, and isolated major/minor/patch fixtures agree with regenerated projects. Do not bump the working repository or publish a release to perform these checks.

### 7. Verify the complete implementation

- [ ] Regenerate `Stow.xcodeproj` if source membership changed and inspect the resulting diff; acceptance: both platforms include only intended files, and `ruby Scripts/generate_project.rb --check` passes without modifying the tree.
- [ ] Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/ci.sh` only after section 0's isolation prerequisite is satisfied; acceptance: package/native tests, both platform builds, script checks, and entitlement checks pass without UI-test invocation. Record the toolchain used; local Xcode 26.6 results do not establish compatibility with CI's configured Xcode 26.3 / Swift 6.2 toolchain.
- [ ] Verify the non-interactive gate with CI's configured toolchain before claiming CI compatibility; acceptance: record a passing result, or leave this check open with the unavailable toolchain stated. Do not dispatch remote workflows without authorization.
- [ ] Run one final local `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/ui_tests.sh all` batch after every implementation change and non-interactive check is complete; acceptance: both platforms pass, including original/plain-text copy, copy-only/direct-paste closing, search-failure local matches, shortcut rollback, iOS save failure/retry, and existing panel drag acceptance. If the batch fails, diagnose the complete batch and group related fixes before rerunning it.
- [ ] Review the final diff against the six proposals and run `git diff --check`; acceptance: no unrelated implementation changes, behavioral fixes, schema/protocol changes, or unowned temporary files remain, and validation evidence is recorded here.

## Risks

- Shared copy orchestration can accidentally change error clearing or record usage before clipboard success; lock the existing sequence down with orchestration tests.
- Local fallback differs intentionally from indexed search; preserve per-field substring rules and caller-specific fallback activation.
- Provider data loading is not drag acceptance; preserve callback frequency rather than adding deduplication or panel semantics.
- iOS failed-save safety depends on retaining draft state and honoring the Boolean save result, not on the unused transition state.
- Native tests currently have live-storage side effects; the isolation prerequisite is mandatory, not satisfied by an in-memory model alone.
- Simplifying version ownership must not introduce Ruby dependencies into Linux release jobs or weaken consistency/rollback checks.

## Rollback / Recovery

Deliver each section as a separately reviewable diff so it can be reversed without reverting unrelated work. No persisted-data or protocol migration is required, and rollback must not delete capture spools, saved items, or attachment data.

For version-script changes, retain backups and rollback for `VERSION` and `Stow.xcodeproj/project.pbxproj` until post-update verification succeeds. If pre-release checks fail, restore both together and rerun verification. Do not create, move, delete, or force-push release tags as part of this plan.

## Completion Checklist

- [ ] All six simplifications meet their stated acceptance tests, with no speculative abstractions or adjacent behavior changes.
- [ ] Hosted-test storage isolation is proven and all required non-interactive checks pass after the final change.
- [ ] Compatibility with the configured CI toolchain is verified, and the accumulated macOS/iOS UI batch passes.
- [ ] Version generation and bumping agree for all supported bump types, with failure rollback verified in isolated fixtures.
- [ ] Final diff review confirms unchanged public APIs, persisted formats, CLI output, UI behavior, preference keys, and usage accounting.
- [ ] Required review feedback is resolved, temporary verification artifacts are removed, and the implementation is ready for handoff; no commit, merge, push, or deployment is implied without separate authorization.
