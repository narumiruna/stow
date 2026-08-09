# Stow Support

## Common checks

- **A shared item has not appeared:** open Stow once. Atomic staged captures are retried when the app becomes active.
- **iCloud is unavailable:** Stow remains usable locally. Check the iCloud status and retry guidance in Settings, then confirm iCloud Drive is enabled for the current system account.
- **A copied item has not appeared on Mac:** keep Stow running and confirm **Automatically save copied items** is enabled in Settings. On macOS 15.4 or later, open Privacy & Security › Paste from Other Apps and set Stow to **Always Allow**. Monitoring begins with the next clipboard change; it intentionally ignores content copied before monitoring started.
- **A Mac shortcut does not work:** open Settings and choose an alternate shortcut. Another app may own the default combination.
- **An item was deleted:** open Trash and restore it within 30 days.
- **Search appears incomplete:** use Rebuild Search Index in Settings.
- **An attachment is rejected:** v0.1 accepts attachments up to 100 MB each.

When requesting support, include the Stow version, Apple device model, OS version, and the steps that reproduce the issue. Do not send private captured content unless it is essential and you intentionally choose to share it.
