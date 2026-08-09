# Stow

Stow is a local-first universal content inbox for iOS, iPadOS, and macOS.

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

Run the local quality gate:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/ci.sh
```

Run the full UI suite only on the newest available iPhone simulator and the current macOS host:

```sh
RUN_UI_TESTS=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/ci.sh
```

Focused commands:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/StowCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Stow.xcodeproj -scheme Stow-macOS CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Stow.xcodeproj -scheme Stow-iOS -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Stow.xcodeproj -scheme StowMacUITests CODE_SIGN_ENTITLEMENTS='' CODE_SIGN_IDENTITY='-' test
```

Release metadata, privacy/support copy, screenshots, and the current device matrix live in [`docs/release`](docs/release).

Signing team selection and CloudKit credentials are kept in local Xcode settings and are never committed.

## macOS quick panel and clipboard monitoring

Press **Command-Shift-V** from any app to open Stow as a translucent bar along the bottom of the active display. The panel provides a single horizontal clipboard timeline, Clipboard/Inbox/Pinned modes, inline search filters, compact mode when resized, and full keyboard navigation. Use the arrow keys to select, Return to paste, Space to preview, Command-C to copy, Command-O to open, Command-E to edit, and Command-Shift-A to archive.

Close the panel with its always-visible **Close** button, by pressing **Command-Shift-V** again, or by clicking outside it. Escape works from the inside out: it closes a preview/editor, clears active search criteria, collapses Search, and then closes the panel. Unsaved edits are never discarded by an exit request without confirmation. Successful paste/open/drag actions close automatically; Command-C deliberately keeps the panel open for repeated copying. Opening Quick Add, Library, or Settings closes the panel first so Stow surfaces do not stack.

The toolbar shows whether Return will use **Direct paste** or the **Copy only** fallback, and reports when clipboard monitoring is paused. Search treats fullwidth and halfwidth Latin letters, numbers, punctuation, and spaces as equivalent, so an accidental input-mode switch does not hide matching items. Stow requests Accessibility access only for pasting directly back into the app you were using. Without access, Return safely copies the item, tells you to press Command-V, and returns focus to the originating app. Configure this under **Stow → Settings → Direct Paste**.

The menu bar item opens the quick panel, Quick Add, the management Library, monitoring controls, and Settings. The Library remains the place for Inbox processing, Archive, Trash, and detailed metadata work.

While Stow is running, it can automatically save newly copied text, links, images, and regular files to Inbox. Configure this under **Stow → Settings → Clipboard**. On macOS 15.4 or later, set Stow to **Always Allow** in **System Settings → Privacy & Security → Paste from Other Apps** for reliable background capture.
