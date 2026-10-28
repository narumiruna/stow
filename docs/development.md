# Development

Build Stow from source and verify changes locally. Run all commands from the repository root.

[Back to Stow](../README.md)

## Prerequisites

- macOS with Xcode 26.6 (build 17F113) and Swift 6.3 for the local toolchain baseline.
- `just` for the build and CLI installation recipes in `justfile`.
- Ruby with the `xcodeproj` gem for project generation and generator checks.
- Python 3 for the entitlement checks, and `uv` for the iPhone simulator-selection command.
- An installed iPhone simulator runtime for iOS UI tests.

The deployment targets are iOS/iPadOS 17.0+ and macOS 14.0+.

The repository does not change the machine-wide developer directory. Prefix toolchain commands with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

Verify the toolchain:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -version
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift --version
```

The local defaults in `Scripts/ci.sh` expect Xcode 26.6 and Swift 6.3. The [GitHub CI workflow](../.github/workflows/ci.yml) instead selects Xcode 26.3 and sets `EXPECTED_XCODE_VERSION=26.3` and `EXPECTED_SWIFT_VERSION_PREFIX=6.2`. A local check on the newer toolchain does not establish compatibility with the CI toolchain.

## Build and run

Build and open the macOS app:

```sh
just macos
```

This recipe builds a Debug app under `.build/XcodeDerivedData` with ad hoc signing and without entitlements. It stops any running `Stow-macOS` process before opening the new build. This development build does not validate signed App Group or CloudKit behavior.

Simulator builds use local storage without CloudKit. Builds without CloudKit entitlement, or whose cloud-container initialization fails, also use local storage. Do not treat a successful local build as proof of cross-device sync.

For iPhone or iPad, open `Stow.xcodeproj` in Xcode, select the `Stow-iOS` scheme and an iOS simulator, then build and run. Device builds require local signing configuration.

Keep signing team selection and CloudKit credentials in local Xcode settings; never commit them. See the [release checklist](release/v0.1-external-unblock.md) for signed-device and distribution requirements.

The [CLI guide](cli.md) covers installation of the Mac command-line helper.

## Project generation

Generate the Xcode project after adding targets or source files:

```sh
ruby Scripts/generate_project.rb
```

Check generated project drift without changing the working tree:

```sh
ruby Scripts/generate_project.rb --check
```

Run the generator's argument and drift-detection tests:

```sh
Scripts/generate_project_tests.sh
```

## Non-interactive checks

Run the non-interactive quality gate used by CI:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/ci.sh
```

This checks versions and project generation, runs package and native unit tests, builds both platforms, and checks entitlements and the privacy manifest. `Scripts/ci.sh` never runs UI tests.

Focused non-interactive commands:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/StowCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Stow.xcodeproj -scheme Stow-macOS CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Stow.xcodeproj -scheme Stow-iOS -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```

## Local interactive UI tests

Finish implementation and all relevant non-interactive checks before running UI tests. Collect the required scenarios into one final verification batch. If it fails, diagnose the complete batch and group related fixes before rerunning it.

UI-test orchestration belongs only in `Scripts/ui_tests.sh`. CI scripts and workflows must not invoke UI-test schemes or this local script.

The Mac suite requires macOS Developer Mode. Local UI automation can also require system authentication. The suite stops existing Stow and UI-test runner processes and operates the desktop UI. The iOS suite boots the newest available iPhone simulator. It temporarily enables simulated biometric enrollment for App Lock tests and restores the previous enrollment state when the batch ends. The tests send simulated biometric matches from the XCTest runner; the app contains no test authentication bypass. Debug simulator tests use a separate preferences domain, with a per-test UUID for relaunch checks, and do not reset real device settings.

Run the full local suite:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/ui_tests.sh all
```

Run one platform through the same entry point when focused verification is needed:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/ui_tests.sh macos
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/ui_tests.sh ios
```

Run the confirmation and immediate-save Share Extension scenarios together when changing only iOS sharing:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/ui_tests.sh ios-share
```

The default mode is `all`. It attempts both platforms before returning a failure. The script exits without running tests when a CI environment is detected.
