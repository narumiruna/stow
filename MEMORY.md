## GOTCHA

- Symptom: a signed/simulator app using CloudKit traps in `_dispatch_assert_queue_fail` when sync starts. Cause: `NSPersistentCloudKitContainer.eventChangedNotification` may be posted from a Core Data queue, so an `@MainActor` selector observer is unsafe. Fix: register a block observer on `OperationQueue.main` and enter `MainActor.assumeIsolated` only there.
- Symptom: an ad-hoc or simulator app can crash asynchronously in CloudKit even though `ModelContainer` initialization succeeded. Cause: the process lacks the configured iCloud-container entitlement. Fix: inspect the runtime entitlement before enabling CloudKit and otherwise open the same App Group store locally.
- Symptom: macOS XCUITest waits 60 seconds for accessibility even though the app process is idle. Cause: a prior test closed the restored main window with `⌘W`. Fix: do not close the main window during panel tests and launch UI tests with `-ApplePersistenceIgnoreState YES`.

## TASTE

## CONVENTIONS
