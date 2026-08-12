# Stow Privacy Notice

Stow is local-first. Captured links, text, code, images, files, notes, and metadata are stored on your devices and, when configured, in your private iCloud database. The developer does not operate a service that receives this content.

On macOS, an explicitly invoked local `stow` command can search, retrieve, add, or export content for processes running under the same user account. The command communicates through Stow's private App Group and does not provide a network or remote automation service.

On macOS, Stow can monitor clipboard changes while the app is running and automatically save newly copied text, links, images, and files. Monitoring can be disabled at any time in Settings. On supported macOS versions, clipboard access is controlled by Privacy & Security › Paste from Other Apps. Content already on the clipboard when monitoring starts is ignored, and clipboard content is never sent to the developer.

Before reading clipboard payloads, Stow ignores a change when any advertised item type is `org.nspasteboard.ConcealedType`, `org.nspasteboard.TransientType`, or Stow's own `dev.narumi.stow.owned-content` marker. These concealed and transient identifiers are compatibility conventions used by cooperating clipboard applications rather than a universal Apple password API. Stow does not inspect marker values, read protected payload bytes, or heuristically classify arbitrary text that merely looks like a password, token, card number, or one-time code.

For ordinary clipboard changes, Stow preserves supported original formats, not every format advertised by the source application. It may store UTF-8 plain text, RTF, HTML, HTTP/HTTPS URLs, PNG, and TIFF data. Limits are 1 MiB for plain text, 5 MiB for each rich-text format, 16 KiB for a URL, 100 MiB for an image representation, and 110 MiB across preserved representations in one capture. Unknown or app-private types, RTFD, and file promises are ignored. These preserved bytes remain local-first like other Stow content and can sync to the user's private iCloud database when configured.

Stow does not include advertising, cross-app tracking, or third-party analytics. Optional product counters are aggregate, remain on device, and can be disabled in Settings.

The app contacts a saved link's host to retrieve ordinary page title, description, and icon metadata. It does not send the rest of your library with that request. Opening, sharing, or exporting an item sends it only to the destination you choose through system services.

Deleting an item moves it to Trash. Trashed items are permanently deleted after 30 days unless restored earlier. Private iCloud synchronization follows the iCloud account and retention behavior controlled by Apple.

Photo Library access is requested only when you choose Save Image. File and share access is limited to content you explicitly provide through Apple system pickers and share sheets.

For privacy questions, use the support contact published with the App Store listing.
