# Stow Privacy Notice

Stow is local-first. Captured links, text, code, images, files, notes, and metadata are stored on your devices and, when configured, in your private iCloud database. The developer does not operate a service that receives this content.

On macOS, an explicitly invoked local `stow` command can search, retrieve, add, or export content for processes running under the same user account. The command communicates through Stow's private App Group and does not provide a network or remote automation service.

On macOS, Stow can monitor clipboard changes while the app is running and automatically save newly copied text, links, images, and files. Monitoring can be disabled at any time in Settings. On supported macOS versions, clipboard access is controlled by Privacy & Security › Paste from Other Apps. Content already on the clipboard when monitoring starts is ignored, and clipboard content is never sent to the developer.

Before reading clipboard payloads, Stow ignores a change when any advertised item type is `org.nspasteboard.ConcealedType`, `org.nspasteboard.TransientType`, or Stow's own `dev.narumi.stow.owned-content` marker. These concealed and transient identifiers are compatibility conventions used by cooperating clipboard applications rather than a universal Apple password API. Stow does not inspect marker values, read protected payload bytes, or heuristically classify arbitrary text that merely looks like a password, token, card number, or one-time code.

For ordinary clipboard changes, Stow preserves supported original formats, not every format advertised by the source application. It may store UTF-8 plain text, RTF, HTML, HTTP/HTTPS URLs, PNG, and TIFF data. Limits are 1 MiB for plain text, 5 MiB for each rich-text format, 16 KiB for a URL, 100 MiB for an image representation, and 110 MiB across preserved representations in one capture. Unknown or app-private types, RTFD, and file promises are ignored. These preserved bytes remain local-first like other Stow content and can sync to the user's private iCloud database when configured.

Stow does not include advertising, cross-app tracking, or third-party analytics. Optional product counters are aggregate, remain on device, and can be disabled in Settings.

On iPhone and iPad, automatic link previews are off by default, including upgrades without a stored choice. Enable them under Settings → Security & Privacy to let Stow fetch saved pages, descriptions, icons, and preview images. Existing links without metadata can also be fetched. Page hosts, redirect destinations, and referenced image/icon hosts can receive these requests. The requests do not send the rest of your library. Turning the option off cancels pending work and prevents new automatic requests on that device; it cannot recall requests already sent or remove existing metadata. Metadata can still sync from another device. macOS keeps its existing automatic link-preview behavior. Opening, sharing, or exporting an item remains an explicit action through system services.

Optional iOS App Lock uses Apple's device-owner authentication, with Face ID or Touch ID where available and the system device passcode as fallback. Stow receives the authentication result, not biometric data or the device passcode. App Lock is off by default. Enabling it, disabling it, or extending its background grace period requires authentication. A new launch always starts locked when enabled. Inactive content is hidden even with App Lock off; existing editor drafts remain in memory through lock/unlock. The Share Extension can stage new incoming content while the host is locked, but cannot browse the library.

App Lock is an app-access control, not additional database or end-to-end encryption. It does not stop private iCloud sync, protect a different device, or revoke content already shared. App Lock, preview fetching, launch-page, and appearance preferences are device-local and are not added to the synced library.

Deleting an item moves it to Trash. Trashed items are permanently deleted after 30 days unless restored earlier. Private iCloud synchronization follows the iCloud account and retention behavior controlled by Apple.

Photo Library access is requested only when you choose Save Image. File and share access is limited to content you explicitly provide through Apple system pickers and share sheets.

For privacy questions, use the support contact published with the App Store listing.
