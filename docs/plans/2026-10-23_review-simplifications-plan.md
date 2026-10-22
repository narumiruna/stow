# Review Simplifications

## Goal

Resolve the four confirmed review findings without changing capture, selection, attachment ordering, CLI syntax, or public APIs.

## Non-Goals

- Do not redesign views, merge persistence paths, change schemas, or add generic helpers.
- Do not change `AGENTS.md`; no instruction-file findings were reported.
- Do not publish packages, create version tags, or dispatch release workflows; the current delivery request authorizes the focused branch, commits, push, and pull request.

## Plan

- [x] Confirm current callers, applicable instructions, and existing tests; acceptance: both clipboard readers override snapshots, selected-item policy only checks visible membership, detail attachment consumers only use the first match, and status/get option loops are identical.
- [x] Remove unused clipboard primitive-read requirements/default snapshot and obsolete conformer methods; acceptance: snapshot/image reads remain and clipboard policy tests pass.
- [ ] Verify the implemented direct selected-item lookup in the final macOS UI batch; acceptance: repair tests remain and Return, Shift-Return, and Copy cannot use stale items after zero results (blocked by local Automation Mode authentication).
- [x] Use one optional first attachment in macOS/iOS detail views; acceptance: first-match/nil behavior is checked without adding a utility layer and both platforms build.
- [x] Share only status/get common-option parsing; acceptance: focused tests preserve defaults, repeated options, exact errors, timeout rules, and leading UUID order.
- [x] Run package/native tests, both platform builds, project drift, and static checks; acceptance: all relevant non-interactive checks pass before UI execution.
- [ ] Complete `Scripts/ui_tests.sh all` verification after local macOS Automation Mode authentication; acceptance: required macOS/iOS scenarios pass (iOS passed; macOS runner is blocked before execution).
- [x] Review the final diff; acceptance: only the four simplifications, their tests, the verified shared Safari page-readiness fixture correction, and this temporary plan are changed.

## Verification

`Scripts/ci.sh` exited 0 on Xcode 26.6 / Swift 6.3.3: 133 package tests, 87 native app tests, 6 share tests, both platform builds, version/generator checks, and entitlement/privacy-manifest checks passed. Embedded Python checks ran through an exported `python3` shell function that invokes `uv run python`; no repository script was changed. The read-only-store warning is expected from the persistence-failure fixture. Six standalone Swift fixtures confirm old/new first-attachment lookup equivalence for empty, unrelated, single, and multiple matching attachments, including reversed matching order. Swift parsing of the changed UI test, Bash/Ruby syntax, plist validation, and `git diff --check` passed. Independent diff review found no behavior regressions. Existing helper-only selection assertions moved to the real UI action path; repair coverage remains.

No public API, schema, preferences, build membership, or CI/UI orchestration changes were made. Local results do not verify CI's Xcode 26.3 toolchain.

The first final `Scripts/ui_tests.sh all` batch exited 65. macOS built successfully and passed the isolated CLI background-launch smoke check, but the UI runner timed out before any scenario: `testmanagerd` reports that the writer daemon requires authentication to enable Automation Mode. No authentication-policy changes were made. Result: `Test-StowMacUITests-2026.10.23_01-14-12-+0800.xcresult`.

iOS 26.5 / iPhone 17 Pro passed 13 of 15 tests, including all detail previews and failed-save/retry coverage. Both failures were in the unchanged Safari helper at `StowUITests.swift:365`, before opening the share sheet. The exported failure hierarchy proves the external page loaded with an `Other` container labeled `Example Domain` but no matching `StaticText` heading. The grouped test-only correction waits for that labeled container inside Safari's web views. Both changed UI test files parse and `git diff --check` passes. Result: `Test-StowUITests-2026.10.23_01-15-30-+0800.xcresult`. The second complete `Scripts/ui_tests.sh all` batch again exited 65 solely because the macOS runner could not enable Automation Mode. All 15 iOS tests passed after the fixture correction, including both Safari share scenarios and type-specific attachment previews. Final results: `Test-StowMacUITests-2026.10.23_01-23-09-+0800.xcresult` and `Test-StowUITests-2026.10.23_01-24-21-+0800.xcresult` under Xcode DerivedData. No implementation changes followed the non-interactive gate; only the diagnosed shared UI fixture changed. No further batch was run.

The delivery attempt uses `narumi/refactor/review-simplifications`, created from the current `origin/main` (`4e22cba`) with all existing implementation work preserved. The focused CLI parser suite (9 tests), full non-interactive gate (133 package / 87 app / 6 share tests and both builds), static checks, and complete diff review passed again before committing. Review covered correctness, security, lifecycle safety, compatibility, regressions, and scope: no new asynchronous lifetimes, persistence writes, public contracts, protected-content reads, or attachment-order changes were introduced.

A fresh read-only check confirms Developer Mode is enabled but Automation Mode is disabled and requires user authentication. No further UI batch was run against that unchanged blocker. The pull request must remain draft until the open UI criteria pass or the user explicitly accepts the missing evidence; CI's configured toolchain also remains unverified until its actual run passes.

Required external action: complete the local macOS `Enable UI Automation` authentication, then rerun `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/ui_tests.sh all`. Developer Mode is already enabled; no privilege or authentication settings were changed. The macOS no-stale-use and Library preview scenarios remain unverified. Agent-created log and hierarchy exports were removed; original Xcode result bundles remain available.

## Completion Checklist

- [x] All four changes and regression coverage are complete.
- [x] Relevant non-interactive checks pass.
- [ ] The complete final UI batch passes, or the user explicitly accepts missing evidence.
- [x] Final diff is scoped and temporary diagnostic files are removed.

Delete this plan only when every completion check passes; otherwise retain it with missing evidence stated.
