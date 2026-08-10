## GOTCHA

- Symptom: a signed/simulator app using CloudKit traps in `_dispatch_assert_queue_fail` when sync starts. Cause: `NSPersistentCloudKitContainer.eventChangedNotification` may be posted from a Core Data queue, so an `@MainActor` selector observer is unsafe. Fix: register a block observer on `OperationQueue.main` and enter `MainActor.assumeIsolated` only there.
- Symptom: an ad-hoc or simulator app can crash asynchronously in CloudKit even though `ModelContainer` initialization succeeded. Cause: the process lacks the configured iCloud-container entitlement. Fix: inspect the runtime entitlement before enabling CloudKit and otherwise open the same App Group store locally.
- Symptom: macOS XCUITest waits 60 seconds for accessibility even though the app process is idle. Cause: a prior test closed the restored main window with `⌘W`. Fix: do not close the main window during panel tests and launch UI tests with `-ApplePersistenceIgnoreState YES`.
- Symptom: an ad-hoc macOS build repeatedly asks to “access data from other apps.” Cause: calling `containerURL(forSecurityApplicationGroupIdentifier:)` without the committed App Group entitlement triggers macOS container privacy. Fix: inspect the runtime App Group entitlement first and use the development fallback without touching the group container when it is absent.
- Symptom: GitHub Actions selects a requested Xcode but `Scripts/ci.sh` reports the runner default. Cause: a hardcoded `DEVELOPER_DIR` overrides `setup-xcode`'s `MD_APPLE_SDK_ROOT`. Fix: prefer an existing `DEVELOPER_DIR`, then derive it from `MD_APPLE_SDK_ROOT`, and use `/Applications/Xcode.app` only as the local fallback.
- CI must not run interactive `StowMacUITests`, `StowUITests`, or `Scripts/ui_tests.sh`; keep UI test orchestration in that local-only script and run it as one final verification batch.

## TASTE

- Prefer macOS release validation without VoiceOver and scope display behavior to a single display unless explicitly requested.
