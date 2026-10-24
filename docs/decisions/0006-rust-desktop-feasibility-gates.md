# ADR 0006: Rust Desktop Feasibility Gates

- Status: Tauri 2 approved for implementation; native acceptance gates remain open.
- Date: 2026-10-24

## Decision

Use Tauri 2 with a Rust backend and a web UI. The user explicitly approved this fallback after the `iced` accessibility blocker was reported. Do not request this approval again.

Remove the stopped `iced` sample instead of maintaining two UI implementations. Keep the current Swift desktop app and data paths until all replacement gates pass. Approval of the framework does not waive accessibility, persistence, or signed Apple integration checks.

The [rewrite plan](../plans/2026-10-24_rust-cross-platform-desktop-plan.md) requires screen-reader support and native accessibility checks before replacing the desktop UI. The selected framework does not provide the required native accessibility integration.

## Accessibility Evidence

The previously resolved `iced` 0.14 packages have no AccessKit dependency or native accessibility-tree implementation. Upstream records checked on the date above show:

- [Issue 552: Implement accessibility support](https://github.com/iced-rs/iced/issues/552) is open.
- [Pull request 1849](https://github.com/iced-rs/iced/pull/1849) is an open draft and is not merged.
- [Pull request 3111](https://github.com/iced-rs/iced/pull/3111) is an open draft and is not merged.
- [Pull request 3281](https://github.com/iced-rs/iced/pull/3281) is closed without merge.

Passing headless tests and three-platform builds do not supply this missing implementation. Do not expand the feasibility sample into the production desktop app on that basis.

## Approved Framework and Security Boundary

Tauri 2 supplies a native WebView host. The Library UI uses semantic HTML, local scripts, and local styles. Rust owns repository operations on one dedicated worker thread. The web UI has no filesystem, shell, network, or clipboard plugin permissions.

- Grant only the declared application commands to the local `main` window.
- Check the window label and embedded application origin before each command.
- Block remote navigation and new windows. Do not render saved HTML as executable content.
- Enforce a Content Security Policy without remote scripts or `unsafe-eval`.
- Do not accept library paths from the web UI. Use a separate preview application-data identity before cutover.
- Do not log content or expose attachment bytes in list responses.

The implementation must still pass native accessibility, keyboard, IME, panel focus, security, and signed Apple integration gates. This record does not establish that those checks pass.

## Windows Persistence Gate

The local repository currently depends on private directories, durable directory synchronization, and publication of attachment bytes before database references commit. A Windows port needs a supported durability protocol and secure current-user ACL creation.

`MoveFileExW` and `FlushFileBuffers` do not by themselves establish the required general, unprivileged directory synchronization contract. Do not ignore unsupported directory flush errors or request administrator access. Keep Windows storage disabled until the required protocol is established or an alternative storage design is explicitly approved. See the [storage blocker and Microsoft API references](../../Desktop/crates/stow-storage/README.md#windows-durability-blocker).

## Apple Integration Gate

The existing SwiftData store, CloudKit container, Share Extensions, and iOS app remain unchanged. A signed Rust host, its Swift bridge, and two-device iCloud tests remain necessary. Neither repository tests nor unsigned CI builds satisfy that gate.
