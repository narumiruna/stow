# Stow

Stow is a private inbox for links, text, code, images, and files on iPhone, iPad, and Mac. Save content now, then find and use it when you need it.

> [!WARNING]
> Stow is still under active development. Features may be incomplete or change without notice.

## What you can do

- Save content from the share sheet on iPhone and iPad.
- Save newly copied content automatically on Mac, or add items yourself.
- Keep important items pinned, process your Inbox, and archive finished items.
- Search your library and filter by content type, source, or date.
- Work offline, with private iCloud sync when configured and available.

## Supported devices and availability

- iPhone and iPad: iOS/iPadOS 17.0 or later.
- Mac: macOS 14.0 or later.

This repository does not currently provide a public app download or App Store link. GitHub releases contain source code, not installable apps. To try Stow from source, see the [development guide](docs/development.md).

## Basic use

1. **Save from iPhone or iPad.** Open another app's share sheet, choose Stow, review **Save to Stow**, and tap **Save**. For one-step saving, enable **Settings → Saving & Sharing → Save shared items immediately**.
2. **Capture on Mac.** Keep Stow running and enable **Stow → Settings → Capture → Automatically save copied items**. Disable it at any time to stop automatic capture. Monitoring starts with the next clipboard change.
3. **Find and reuse on Mac.** Press **Command-Shift-V** to open the quick panel. Type to search, use the arrow keys to select an item, and press Return to use it.
4. **Organize your library.** Open **Library** from the Mac menu bar item to pin, archive, edit, or move items to Trash.

## Privacy and permissions

Your library is stored on your devices and can sync through your private iCloud database when configured. The developer does not operate a service that receives your captured content.

On iPhone and iPad, optional App Lock uses Face ID, Touch ID, or your device passcode. Automatic link previews are off by default and can be enabled in Settings. Launch-page and appearance preferences stay on this device. See the [iOS settings guide](docs/user-guide.md#iphone-and-ipad-settings) for behavior and limits.

Mac direct paste is optional and requires Accessibility access. Without it, Return copies the item so you can paste with Command-V. Configure this under **Stow → Settings → Paste & Shortcuts**.

Clipboard capture supports selected content and formats, not everything an app can copy. Stow skips content marked as protected by cooperating apps, but does not identify all passwords or other sensitive-looking text. Disable monitoring before copying content you do not want saved.

For Mac clipboard-access settings and other common problems, see [Support](docs/release/support.md#common-checks).

- [User guide](docs/user-guide.md): sharing, quick panel shortcuts, Library, and Settings.
- [Privacy notice](docs/release/privacy.md): storage, network requests, permissions, and retention.

## Technical documentation

- [Development](docs/development.md): build from source and run checks.
- [macOS CLI](docs/cli.md): local commands for coding agents.
- [Clipboard details](docs/clipboard.md): capture rules, supported formats, and limits.
- [Releases](docs/release/README.md): release status, verification, and maintainer workflow.
