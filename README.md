# Stow

Stow is a local-first universal content inbox for iOS, iPadOS, and macOS.

> [!WARNING]
> Stow is still under active development. Features may be incomplete or change without notice.

## Requirements

- Xcode 26.6 (build 17F113)
- Swift 6.3
- iOS/iPadOS 17.0+
- macOS 14.0+

The repository does not change the machine-wide developer directory. Prefix commands with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

Verify the toolchain:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -version
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift --version
```

## Development

Build and open the macOS app:

```sh
just macos
```

Generate the Xcode project after adding targets or source files:

```sh
ruby Scripts/generate_project.rb
```

Run the non-interactive quality gate used by CI:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/ci.sh
```

`Scripts/ci.sh` never runs UI tests. Run the full interactive UI suite locally, on the current macOS host and newest available iPhone simulator, through its separate entry point:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/ui_tests.sh
```

`Scripts/ui_tests.sh` is local-only and exits without running tests when a CI environment is detected.

Focused non-interactive commands:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/StowCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Stow.xcodeproj -scheme Stow-macOS CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Stow.xcodeproj -scheme Stow-iOS -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```

Focused local macOS UI test command:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Stow.xcodeproj -scheme StowMacUITests CODE_SIGN_ENTITLEMENTS='' CODE_SIGN_IDENTITY='-' test
```

Release metadata, privacy/support copy, screenshots, and the current device matrix live in [`docs/release`](docs/release).

Signing team selection and CloudKit credentials are kept in local Xcode settings and are never committed.

## macOS quick panel and clipboard monitoring

Press **Command-Shift-V** from any app to open Stow as a translucent bar along the bottom of the active display. The panel provides a single horizontal clipboard timeline, Clipboard/Inbox/Pinned modes, inline search filters, compact mode when resized, and full keyboard navigation. Use the arrow keys to select, Return to paste, Space to preview, Command-C to copy, Command-O to open, Command-E to edit, and Command-Shift-A to archive.

Close the panel with its always-visible **Close** button, by pressing **Command-Shift-V** again, or by clicking outside it. Escape works from the inside out: it closes a preview/editor, clears active search criteria, collapses Search, and then closes the panel. Unsaved edits are never discarded by an exit request without confirmation. Successful paste/open/drag actions close automatically; Command-C deliberately keeps the panel open for repeated copying. Opening Quick Add, Library, or Settings closes the panel first so Stow surfaces do not stack.

The toolbar shows whether Return will use **Direct paste** or the **Copy only** fallback, and reports when clipboard monitoring is paused. Search treats fullwidth and halfwidth Latin letters, numbers, punctuation, and spaces as equivalent, so an accidental input-mode switch does not hide matching items. Stow requests Accessibility access only for pasting directly back into the app you were using. Without access, Return safely copies the item, tells you to press Command-V, and returns focus to the originating app. Configure this under **Stow → Settings → Paste & Shortcuts**.

The menu bar item opens the quick panel, Quick Add, the management Library, monitoring controls, and Settings. The Library remains the place for Inbox processing, Archive, Trash, and detailed metadata work.

While Stow is running, it can automatically save newly copied text, links, images, and regular files to Inbox. Configure this under **Stow → Settings → Capture**. On macOS 15.4 or later, set Stow to **Always Allow** in **System Settings → Privacy & Security → Paste from Other Apps** for reliable background capture.

## macOS Library and Settings

Open **Library** for durable management rather than quick retrieval. Its sidebar contains Inbox, Recently Used, Pinned, Archive, and Trash. Search stays in the toolbar; type, source-app, and date criteria live in one adaptive Filter menu so they remain readable at the minimum window size. Select one item to preview, copy, open, share, edit, or change its Library status. Shift-select or Command-select multiple items to pin, archive, restore, or move them to Trash together. Moving items to Trash offers Undo, and Trash keeps Restore non-destructive.

Library editing uses distinct **Cancel** and **Save Changes** actions. Cancelling a dirty draft requires confirmation, and a failed save keeps the complete draft editable without replacing the previous saved item. Browsing a Library detail does not change Recently Used; only an explicit use such as copy, open, Quick Look, share, or drag does.

The native Settings window is organized into **Capture**, **Paste & Shortcuts**, **Sync & Storage**, and **Privacy**. Shortcut replacements are applied as one transaction: if either proposed shortcut conflicts, Stow restores the previous working pair and leaves the rejected values unsaved. **Sync & Storage → Rebuild Search Index** repairs local search without changing saved items and keeps the previous usable index if rebuilding fails.
