# Stow Support

## Common checks

- **A shared item has not appeared:** open Stow once. Atomic staged captures are retried when the app becomes active.
- **iCloud is unavailable:** Stow remains usable locally. Check the iCloud status and retry guidance in Settings, then confirm iCloud Drive is enabled for the current system account.
- **A copied item has not appeared on Mac:** keep Stow running and confirm **Automatically save copied items** is enabled under Settings › Capture. On macOS 15.4 or later, open Privacy & Security › Paste from Other Apps and set Stow to **Always Allow**. Monitoring begins with the next clipboard change; it intentionally ignores content copied before monitoring started.
- **A shared item saves before you can edit it:** on iPhone or iPad, turn off **Save shared items immediately** under Settings › Saving & Sharing to restore the Save to Stow confirmation screen.
- **A Mac shortcut does not work:** open Settings › Paste & Shortcuts from the menu bar and choose an alternate pair. Stow applies both replacements together. If either conflicts, it attempts to restore the previous pair and leaves the rejected values unsaved. If restoration also fails, neither shortcut remains registered; Stow reports the failure so you can choose another pair.
- **App Lock authentication fails:** retry **Unlock Stow** or use the system device-passcode fallback. Confirm a device passcode is set. Cancellation or biometric lockout does not turn off App Lock. Do not delete the app or library to recover access.
- **A saved link has no preview on iPhone or iPad:** automatic previews are off by default. Enable **Settings › Security & Privacy › Automatic link previews** to allow requests to saved pages and their image/icon hosts. Existing previews can still sync from other devices while local fetching is off.
- **An item was deleted:** open Trash and restore it within 30 days.
- **Search appears incomplete:** use **Rebuild Search Index** under Settings › Sync & Storage. A failed rebuild keeps the previous local index available and does not change saved items.
- **An attachment is rejected:** v0.1 accepts attachments up to 100 MiB each.

When requesting support, include the Stow version, Apple device model, OS version, and the steps that reproduce the issue. Do not send private captured content unless it is essential and you intentionally choose to share it.
