## Commands

- If `xcodebuild` cannot load `IDESimulatorFoundation` because `CoreSimulator.framework` is missing, use an initialized Xcode or have an administrator run `xcodebuild -runFirstLaunch` before verification.
- Run `xcodebuild` commands sequentially or give each concurrent command a distinct `-derivedDataPath` to avoid locking `XCBuildData/build.db`.
- Do not add Python or `uv` dependencies to the version-bump workflow.

## Storage and sync

- If CloudKit is unavailable, open the same store locally so a later entitled launch can sync it.
- On macOS, check the runtime App Group entitlement before calling `containerURL(forSecurityApplicationGroupIdentifier:)`, and use the local fallback without touching the group container if the entitlement is absent.
- Do not use an `@MainActor` selector to observe `NSPersistentCloudKitContainer.eventChangedNotification`.

## Testing

- Keep UI test orchestration exclusively in `Scripts/ui_tests.sh`; CI scripts and workflows must never invoke UI test schemes or the local UI test script.
- Never run or ask about interactive UI tests while implementation is in progress.
- Finish the entire requested code change and all relevant non-interactive checks before starting interactive UI tests.
- Use unit tests, builds, and static checks that do not operate the desktop UI during implementation.
- When interactive UI tests are relevant, accumulate all required scenarios and run them together in one final verification batch.
- Do not run interactive UI tests after each file, controller change, or individual fix.
- If the final UI batch fails, diagnose the complete batch and group related fixes before rerunning it.
- Leave the main window open during Quick Panel tests to avoid accessibility timeouts.
- By default, validate macOS releases on one display without VoiceOver.

## macOS UI

- Keep display behavior scoped to one display unless the task explicitly covers multiple displays.
- Treat clipped, obscured, or ambiguously truncated interface text as a release blocker; use layout, wrapping, disclosure, or scrolling to keep decision-relevant text available.
- When changing Library or Settings, preserve the Quick Panel’s appearance and behavior and verify that neither regresses.
