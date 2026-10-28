# User Guide

Save content, retrieve it from the Mac quick panel, and manage your library.

[Back to Stow](../README.md)

## iPhone and iPad sharing

By default, the Stow Share Extension opens **Save to Stow**. You can edit the title, note, pin, code, or archive options before saving.

Enable **Settings → Saving & Sharing → Save shared items immediately** to stage supported share-sheet content for Inbox and return to the source app without the confirmation form. If direct saving fails, Stow keeps the extension open with the confirmation form, error, and draft so you can retry.

Sharing saves one supported representation from the first shared item, not every attachment in a multi-item share. Attachments are limited to 100 MiB each.

If a shared item has not appeared, open Stow once so it can import staged captures. See [Support](release/support.md#common-checks) for more checks.

## iPhone and iPad settings

Settings has four groups: **Security & Privacy**, **Saving & Sharing**, **Appearance & Browsing**, and **Sync & Data**.

### App Lock

**Security & Privacy → App Lock** is off by default. Enabling it requires system authentication. Use Face ID or Touch ID where available, or your device passcode. Stow does not store biometric data or provide a separate password.

Choose **Immediately**, **1 minute**, or **5 minutes** under **Lock after backgrounding**. The default is Immediately. Returning before the interval expires restores the current session. A new launch always starts locked. Tap **Unlock Stow** to authenticate. Turning off App Lock or choosing a longer interval requires authentication again.

The app hides its content when inactive, including editors and native previews. Locking does not discard an unsaved draft. Sharing from another app can still add incoming content while Stow is locked; the Share Extension cannot browse existing items.

App Lock protects access to this iOS app. It does not add database encryption, stop private iCloud sync, or protect other devices. If authentication is interrupted, retry or use the system device-passcode fallback. Do not delete the app or its data to resolve an authentication failure.

### Link previews

**Security & Privacy → Automatic link previews** is off by default, including when upgrading without a previous choice. When enabled, Stow fetches saved pages and their icons and preview images. This can include existing links that have no preview. The page, redirect, and image hosts can receive network requests.

Turning this off cancels pending preview work and prevents new automatic requests from this device. Requests already sent cannot be recalled. Existing metadata is kept, and previews can still arrive through iCloud from another device. Opening a link yourself is unchanged. The Mac continues its existing automatic preview behavior.

### Browsing and appearance

**Appearance & Browsing → Launch page** offers Inbox, Pinned, Recently Used, or Last Library Section. Inbox is the default. Last Library Section restores Inbox, Recent, Pinned, or Archive, but never Settings or Trash. Changing this setting does not move you away from the current page, and returning to an open app keeps its current navigation.

**Appearance & Browsing → Appearance** offers System, Light, or Dark. System is the default. The choice applies to the app and lock screen. The separate Share Extension follows the system.

These new settings stay on this device; they do not sync through iCloud. **Sync & Data** retains account/status guidance, attachment usage, and the fixed 30-day Trash policy. On-device metrics remain optional under **Security & Privacy**.

## Mac clipboard capture

Keep Stow running to save newly copied text, links, images, and regular files automatically. Enable or disable **Automatically save copied items** under **Stow → Settings → Capture**. Monitoring starts with the next clipboard change and ignores content copied before it started.

For clipboard-access settings, see [Support](release/support.md#common-checks). For duplicate matching, sensitive-content exclusions, format limits, and original/plain-text paste behavior, see [Clipboard Details](clipboard.md).

## Mac quick panel

Press **Command-Shift-V** from any app to open Stow as a translucent bar along the bottom of the active display. The most recent eligible item is selected automatically.

Start typing to open Search without clicking it. Stow preserves the first character, selects the first matching result, and uses that result when you press Return. Command-F is an optional way to open Search.

The panel has a single horizontal clipboard timeline, Clipboard/Inbox/Pinned modes, inline search filters, and a compact mode when resized. Search treats fullwidth and halfwidth Latin letters, numbers, punctuation, and spaces as equivalent.

### Keyboard reference

| Key | Action |
|---|---|
| Command-Shift-V | Open or close the quick panel |
| Arrow keys | Select an item |
| Return | Use the selected item |
| Space | Preview |
| Command-C | Copy and keep the panel open |
| Command-O | Open |
| Command-E | Edit |
| Command-Shift-A | Archive |
| Command-F | Open Search |

### Close the panel

Use the always-visible **Close** button or press **Command-Shift-V** again. Clicking outside closes the panel when no menu, preview, or editor is open. Otherwise, it can dismiss only that layer; a modified editor requires confirmation.

Escape works from the inside out: close a preview/editor, clear active search criteria, collapse Search, then close the panel. An exit request never discards unsaved edits without confirmation.

Successful paste, open, and drag actions close the panel automatically. Command-C keeps it open for repeated copying. Opening Quick Add, Library, or Settings closes the panel first so Stow windows do not stack.

### Direct paste and copy only

The toolbar shows whether Return will use **Direct paste** or the **Copy only** fallback. It also reports when clipboard monitoring is paused.

Stow requests Accessibility access only for direct paste back into the app you were using. The primary workflow never prompts for this permission. Configure direct paste under **Stow → Settings → Paste & Shortcuts**.

Without access, or when the originating app is missing or has quit, Return copies the same item and shows **Copied — paste with Command-V**. The panel closes and returns focus when the originating app is still available.

Direct paste sends Command-V to the originating app after activation. It does not verify that the destination accepted the paste.

### Menu bar access

The menu bar item opens the quick panel, Quick Add, Library, monitoring controls, and Settings. The default Quick Add shortcut is **Option-Shift-S**. Use Library for Inbox processing, Archive, Trash, and detailed metadata work.

## Mac Library

Open **Library** for persistent organization rather than quick retrieval. Its sidebar contains Inbox, Recently Used, Pinned, Archive, and Trash.

Search stays in the toolbar. Type, source-app, and date criteria are in one adaptive Filter menu so they remain readable at the minimum window size.

Select one item to preview, copy, open, share, edit, or change its Library status. Shift-select or Command-select multiple items to pin, archive, restore, or move them to Trash together. Moving items to Trash offers Undo. Restore does not permanently delete an item. Trashed items expire after 30 days and are permanently removed during maintenance; restore them before then.

### Edit and save

Library editing has separate **Cancel** and **Save Changes** actions. Cancelling a modified draft requires confirmation. A failed save keeps the complete draft editable without replacing the previous saved item.

Browsing a Library detail does not change Recently Used. Only an explicit use, such as copy, open, Quick Look, share, or drag, changes it.

## Mac Settings

The native Settings window has four sections: **Capture**, **Paste & Shortcuts**, **Sync & Storage**, and **Privacy**.

Choose from the predefined shortcut alternatives under **Paste & Shortcuts**, then select **Apply Shortcuts**. Replacements are applied together. If either proposed shortcut conflicts, Stow attempts to restore the previous working pair and leaves the rejected values unsaved. If restoration also fails, Stow reports the failure and neither shortcut remains registered. Use the menu bar to open Settings and choose another pair.

Use **Sync & Storage → Rebuild Search Index** to repair local search without changing saved items. If rebuilding fails, Stow keeps the previous usable index.

Your library remains usable offline. Private iCloud sync depends on configuration and availability. See the [privacy notice](release/privacy.md) for storage, network requests, and retention, or [Support](release/support.md) for troubleshooting.
