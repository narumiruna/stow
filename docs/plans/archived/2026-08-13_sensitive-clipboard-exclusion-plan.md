# Sensitive Clipboard Exclusion Plan

**Status:** Complete

**Date:** 2026-08-13

## Goal

Prevent password-manager and other explicitly concealed or transient clipboard data from entering Stow persistence, search, previews, sync, automation, or diagnostics.

Success means protected pasteboard changes are silently consumed by the monitor without reading payload bytes and ordinary clipboard capture continues unchanged.

## Context

`ClipboardMonitor` in `Sources/StowApp/macOS/MacAppCoordinator.swift` currently ignores Stow-owned writes but does not check de facto macOS concealed or transient pasteboard markers.

The monitor advances `lastChangeCount` before reading content, so an ignored change can safely remain ignored without repeated polling.

This protection must land before original-format preservation expands the amount of pasteboard data Stow reads and stores.

## Product Contract

- Stow ignores a pasteboard change when any item advertises a supported concealed or transient marker.
- Marker presence is sufficient, and Stow does not inspect marker values or payload content.
- Ignored changes produce no item, attachment staging directory, search document, link enrichment request, sync write, automation event, or content-bearing log.
- Stow-owned writes remain ignored through the existing `dev.narumi.stow.owned-content` marker.
- Ordinary text, link, image, and file capture remains unchanged when no protected marker is present.
- Protection is enabled by default and has no per-copy prompt, notification, or mode.

## Architecture

Add a pure `ClipboardCapturePolicy` in the macOS app target that accepts advertised pasteboard type identifiers and returns a capture or ignore decision with a non-content reason.

Keep raw AppKit type lookup in `ClipboardMonitor`, but call the policy before `readObjects`, `NSImage(pasteboard:)`, `string(forType:)`, or file staging.

Use a deliberately small marker allowlist beginning with `org.nspasteboard.ConcealedType`, `org.nspasteboard.TransientType`, and Stow's own marker.

Document each non-Stow marker as a compatibility convention because Apple does not expose a first-class public “password” API for general pasteboard monitoring.

## Non-Goals

- Do not guess whether arbitrary text is a password, token, card number, or one-time code.
- Do not add per-application exclusions in this plan.
- Do not inspect window titles, Accessibility contents, or browser fields.
- Do not add an override that saves explicitly concealed content.
- Do not record protected payloads or hashes in metrics, logs, screenshots, or test artifacts.

## Plan

- [x] Add `Tests/StowAppTests/ClipboardCapturePolicyTests.swift` with failing cases for each protected marker, mixed protected/ordinary types, Stow-owned content, unknown vendor types, and ordinary supported types; verified by the passing focused policy suite.
- [x] Create `Sources/StowApp/macOS/ClipboardCapturePolicy.swift` with centralized pasteboard type constants and a pure capture decision that never accepts payload data; verified by passing policy tests, including unknown vendor types.
- [x] Apply the policy at the top of `ClipboardMonitor.checkForChanges()` before `captureCurrentContent(sourceApp:)` and before any pasteboard read or staging call; verified by source inspection of the preflight ordering.
- [x] Extract a narrow pasteboard-reading adapter only if needed to prove read ordering, then add a test double that fails if content access occurs after a protected marker; verified by zero payload reads and zero capture callbacks in the injected-reader test.
- [x] Preserve change-count advancement and status reporting for ignored changes without surfacing an error banner or capture notification; verified by a once-only protected change that leaves `AppModel.presentedError` nil.
- [x] Add regression tests for ordinary text, link, image, and file decision paths so the new preflight cannot disable valid capture; verified by focused tests using only an injected reader.
- [x] Add a final macOS UI scenario that writes a uniquely identifiable concealed fixture and proves it never appears in Clipboard, Inbox, Library search, or CLI search, followed by an ordinary fixture that does appear; `StowMacUITests` builds for testing, and execution remains deferred until all four plans pass non-interactive checks.
- [x] Update `docs/release/privacy.md`, `README.md`, and `docs/release/v0.1-test-matrix.md` with the exact protected-marker behavior and the limitation that arbitrary secret-looking text is not heuristically classified; verified by documentation review.
- [x] Run `Scripts/ci.sh` after implementation; core tests, `StowAppTests`, both platform builds, and entitlement checks passed on 2026-08-13 before the final interactive batch.

## Risks

- Concealed and transient markers are compatibility conventions, so password-manager behavior can change across products or versions.
- Broad content heuristics would create false positives and make missing clipboard items impossible to explain.
- Checking markers after reading text or image data would still expose sensitive content to memory, conversion, or staging code.
- Tests that mutate `NSPasteboard.general` can leak real clipboard content, so unit tests must use pure policies and adapters while the final UI fixture uses deterministic cleanup.

## Completion Checklist

- [x] Every supported protected marker returns an ignore decision in passing `ClipboardCapturePolicyTests`.
- [x] Protected decisions perform zero payload reads and zero capture callbacks, as verified by the pasteboard adapter test double.
- [x] Ordinary text, link, image, and file capture decisions remain covered by passing regression tests.
- [x] Privacy documentation names the exact guarantee and its no-heuristics limitation.
- [x] The complete non-interactive gate passes with `Scripts/ci.sh` on 2026-08-13.
- [x] The concealed fixture remained absent during the accumulated macOS UI batch; a later toolbar assertion failed because compact search uses the active-mode token instead of a visible Inbox button, and that assertion was corrected.
