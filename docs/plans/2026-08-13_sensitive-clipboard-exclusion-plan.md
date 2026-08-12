# Sensitive Clipboard Exclusion Plan

**Status:** Planned

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

- [ ] Add `Tests/StowAppTests/ClipboardCapturePolicyTests.swift` with failing cases for each protected marker, mixed protected/ordinary types, Stow-owned content, unknown vendor types, and ordinary supported types; verify with `xcodebuild -project Stow.xcodeproj -scheme StowAppTests CODE_SIGNING_ALLOWED=NO test`.
- [ ] Create `Sources/StowApp/macOS/ClipboardCapturePolicy.swift` with centralized pasteboard type constants and a pure capture decision that never accepts payload data; verify all policy tests pass and unknown types do not become protected by accident.
- [ ] Apply the policy at the top of `ClipboardMonitor.checkForChanges()` before `captureCurrentContent(sourceApp:)` and before any pasteboard read or staging call; verify by source inspection that every content-reading path is downstream of the decision.
- [ ] Extract a narrow pasteboard-reading adapter only if needed to prove read ordering, then add a test double that fails if content access occurs after a protected marker; verify the protected-marker test observes zero reads and zero capture callbacks.
- [ ] Preserve change-count advancement and status reporting for ignored changes without surfacing an error banner or capture notification; verify a protected change is evaluated once and does not alter `AppModel.presentedError`.
- [ ] Add regression tests for ordinary text, link, image, and file decision paths so the new preflight cannot disable valid capture; verify the focused `StowAppTests` pass without reading the process-wide general pasteboard.
- [ ] Add a final macOS UI scenario that writes a uniquely identifiable concealed fixture and proves it never appears in Clipboard, Inbox, Library search, or CLI search, followed by an ordinary fixture that does appear; keep orchestration in `Scripts/ui_tests.sh` and defer execution until all four plans pass non-interactive checks.
- [ ] Update `docs/release/privacy.md`, `README.md`, and `docs/release/v0.1-test-matrix.md` with the exact protected-marker behavior and the limitation that arbitrary secret-looking text is not heuristically classified; verify no documentation claims universal password detection.
- [ ] Run `Scripts/ci.sh` after implementation; verify core tests, `StowAppTests`, both platform builds, and entitlement checks pass before the final interactive batch.

## Risks

- Concealed and transient markers are compatibility conventions, so password-manager behavior can change across products or versions.
- Broad content heuristics would create false positives and make missing clipboard items impossible to explain.
- Checking markers after reading text or image data would still expose sensitive content to memory, conversion, or staging code.
- Tests that mutate `NSPasteboard.general` can leak real clipboard content, so unit tests must use pure policies and adapters while the final UI fixture uses deterministic cleanup.

## Completion Checklist

- [ ] Every supported protected marker returns an ignore decision in passing `ClipboardCapturePolicyTests`.
- [ ] Protected decisions perform zero payload reads and zero capture callbacks, as verified by the pasteboard adapter test double.
- [ ] Ordinary text, link, image, and file capture decisions remain covered by passing regression tests.
- [ ] Privacy documentation names the exact guarantee and its no-heuristics limitation.
- [ ] The complete non-interactive gate passes with `Scripts/ci.sh`.
- [ ] After all four plans are implemented, concealed and ordinary fixtures pass together with the other accumulated scenarios in one final `Scripts/ui_tests.sh` batch.
