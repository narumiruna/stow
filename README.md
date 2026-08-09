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

## macOS clipboard monitoring

While Stow is running, it can automatically save newly copied text, links, images, and regular files to Inbox. Configure this under **Stow → Settings → Clipboard**. On macOS 15.4 or later, set Stow to **Always Allow** in **System Settings → Privacy & Security → Paste from Other Apps** for reliable background capture.
