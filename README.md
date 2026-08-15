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

## Agent-first macOS CLI

The `stow` CLI lets a coding agent use the local Stow library without opening the SwiftData or CloudKit store itself.

Build the macOS app and install a symlink for the current user:

```sh
just install-cli
```

The installer writes only `~/.local/bin/stow`, never requests administrator access, and never edits a shell profile.

Add `~/.local/bin` to `PATH` yourself if it is not already present.

Check the host and discover commands:

```sh
stow status --json
stow help
stow version --json
```

Add code safely through standard input:

```sh
printf 'let answer = 42\n' | \
  stow add --type code --title 'Answer' --language swift --stdin --json
```

Reuse an explicit request ID when a timed-out mutation must be retried:

```sh
request_id="$(uuidgen)"
printf 'idempotent body\n' | \
  stow add --type text --stdin --request-id "$request_id" --json

export_request_id="$(uuidgen)"
stow export ITEM_UUID --request-id "$export_request_id" --json
```

Retry either command with its original request ID to recover a response that completed after the caller timed out without repeating host-side mutation work.

Search returns compact metadata and bounded snippets, while `get` returns the complete text fields and attachment metadata:

```sh
stow search --status inbox --limit 20 --json
stow search 'SwiftData migration' --type code --limit 10 --json
stow get ITEM_UUID --json
```

`get` never inserts Base64 attachment bytes into JSON.

Export an image or file to a private App Group path that a local coding agent can read:

```sh
stow export ITEM_UUID --json
stow export ITEM_UUID --attachment ATTACHMENT_UUID --json
```

Request a separate destination copy when needed:

```sh
stow export ITEM_UUID --output /tmp/stow-image.png --json
```

An existing destination is preserved unless `--force` is explicit, and sandbox policy can reject an arbitrary destination while leaving the returned App Group export path available.

JSON mode writes exactly one response document to standard output, writes diagnostics to standard error, uses ISO 8601 dates and lowercase enums, and never prompts or invokes a pager.

Errors include a stable code, message, retryable flag, and request ID, while an export-copy error also includes `fallback_path` for the readable App Group copy.

Exit codes are 64 for usage, 65 for validation, 66 for missing content, 69 for an unavailable host, 70 for protocol or internal failure, 74 for I/O failure, and 75 for timeout.

The CLI supports coding agents on the same Mac and user account only, and it does not expose HTTP, remote, SSH, MCP, or iCloud automation access.

Remove the symlink without changing saved Stow data:

```sh
just uninstall-cli
```

## Releases

Release metadata, privacy/support copy, screenshots, and the current device matrix live in [`docs/release`](docs/release).

After the release gates pass on `main`, run **Bump Version** from the GitHub Actions page and choose `patch`, `minor`, or `major`.
The workflow uses `Scripts/bump_version.sh` to update `VERSION`, the project generator, and every Xcode `MARKETING_VERSION`, then atomically pushes one `chore(release)` commit and an annotated `vMAJOR.MINOR.PATCH` tag.
The tag triggers **Release**, which runs `Scripts/verify_version.sh` and creates a source-only GitHub release with generated notes.
Run `Scripts/verify_version.sh` locally when checking version consistency without starting a release.

Configure the repository Actions secret `PAT_TOKEN` with repository contents write access.
The bump workflow needs this token because events pushed with the built-in `GITHUB_TOKEN` do not start the separate release workflow.
If the atomic push is rejected because `main` changed, rerun **Bump Version** from the latest `main`; do not force-push the release commit or tag.

Signing team selection and CloudKit credentials are kept in local Xcode settings and are never committed.

## macOS quick panel and clipboard monitoring

Press **Command-Shift-V** from any app to open Stow as a translucent bar along the bottom of the active display. The most recent eligible item is selected automatically. Start typing to open Search without clicking it; Stow preserves the first character, selects the first matching result, and uses that result when you press Return. Command-F remains an optional way to open Search. The panel provides a single horizontal clipboard timeline, Clipboard/Inbox/Pinned modes, inline search filters, compact mode when resized, and full keyboard navigation. Use the arrow keys to select, Return to paste, Space to preview, Command-C to copy, Command-O to open, Command-E to edit, and Command-Shift-A to archive.

Close the panel with its always-visible **Close** button, by pressing **Command-Shift-V** again, or by clicking outside it. Escape works from the inside out: it closes a preview/editor, clears active search criteria, collapses Search, and then closes the panel. Unsaved edits are never discarded by an exit request without confirmation. Successful paste/open/drag actions close automatically; Command-C deliberately keeps the panel open for repeated copying. Opening Quick Add, Library, or Settings closes the panel first so Stow surfaces do not stack.

The toolbar shows whether Return will use **Direct paste** or the **Copy only** fallback, and reports when clipboard monitoring is paused. Search treats fullwidth and halfwidth Latin letters, numbers, punctuation, and spaces as equivalent, so an accidental input-mode switch does not hide matching items. Stow requests Accessibility access only for pasting directly back into the app you were using. Without access—or when the originating app is missing or has quit—Return copies the same item, shows **Copied — paste with Command-V**, closes the panel, and returns focus when the originating app is still available. The primary workflow never prompts for Accessibility permission. Configure direct paste under **Stow → Settings → Paste & Shortcuts**.

The menu bar item opens the quick panel, Quick Add, the management Library, monitoring controls, and Settings. The Library remains the place for Inbox processing, Archive, Trash, and detailed metadata work.

While Stow is running, it can automatically save newly copied text, links, images, and regular files to Inbox. When automatic monitoring sees exactly the same canonical content again, Stow keeps one item, preserves its edits and lifecycle state, updates the source app and capture activity, and moves it to the front of Clipboard. Matching Trash content is never restored; it creates a new Inbox item. Text matching normalizes Unicode and line endings but preserves case and meaningful whitespace. Links use their normalized HTTP/HTTPS URL, images use original bytes and type, and files also include the normalized filename. Quick Add, share extensions, and CLI adds still create new items, and independently synced cross-device duplicates are not reconciled.

Stow ignores clipboard items marked with the macOS compatibility types `org.nspasteboard.ConcealedType` or `org.nspasteboard.TransientType`, as well as Stow-owned writes, before reading their payload. This protects cooperating password managers and transient clipboard tools; Stow does not guess whether arbitrary secret-looking text is sensitive. Configure capture under **Stow → Settings → Capture**. On macOS 15.4 or later, set Stow to **Always Allow** in **System Settings → Privacy & Security → Paste from Other Apps** for reliable background capture.

Stow preserves supported original formats rather than every format an app advertises. The initial allowlist is UTF-8 plain text up to 1 MiB, RTF and HTML up to 5 MiB each, URLs up to 16 KiB, and PNG or TIFF images up to 100 MiB, with a 110 MiB total representation limit per capture. App-private formats, RTFD, file promises, and unknown types are ignored. Return, double-click, numbered Use shortcuts, and context-menu **Use** restore the supported original formats when available. Press **Shift-Return** or choose **Paste as Plain Text** for text, code, and links to write only their canonical string. Older items without preserved representations continue to use their type-based paste fallback.

## macOS Library and Settings

Open **Library** for durable management rather than quick retrieval. Its sidebar contains Inbox, Recently Used, Pinned, Archive, and Trash. Search stays in the toolbar; type, source-app, and date criteria live in one adaptive Filter menu so they remain readable at the minimum window size. Select one item to preview, copy, open, share, edit, or change its Library status. Shift-select or Command-select multiple items to pin, archive, restore, or move them to Trash together. Moving items to Trash offers Undo, and Trash keeps Restore non-destructive.

Library editing uses distinct **Cancel** and **Save Changes** actions. Cancelling a dirty draft requires confirmation, and a failed save keeps the complete draft editable without replacing the previous saved item. Browsing a Library detail does not change Recently Used; only an explicit use such as copy, open, Quick Look, share, or drag does.

The native Settings window is organized into **Capture**, **Paste & Shortcuts**, **Sync & Storage**, and **Privacy**. Shortcut replacements are applied as one transaction: if either proposed shortcut conflicts, Stow restores the previous working pair and leaves the rejected values unsaved. **Sync & Storage → Rebuild Search Index** repairs local search without changing saved items and keeps the previous usable index if rebuilding fails.
