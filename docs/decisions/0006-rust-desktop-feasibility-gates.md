# ADR 0006: Rust Desktop Feasibility Gates

- Status: Blocked; no replacement UI framework is approved by this record.
- Date: 2026-10-24

## Decision

Keep the current Swift desktop app. Continue portable Rust repository work, but stop production adoption of `iced` 0.14. Do not remove accessibility or persistence requirements to proceed.

The [rewrite plan](../plans/2026-10-24_rust-cross-platform-desktop-plan.md) requires screen-reader support and native accessibility checks before replacing the desktop UI. The selected framework does not provide the required native accessibility integration.

## Accessibility Evidence

The resolved `iced` 0.14 packages have no AccessKit dependency or native accessibility-tree implementation. Upstream records checked on the date above show:

- [Issue 552: Implement accessibility support](https://github.com/iced-rs/iced/issues/552) is open.
- [Pull request 1849](https://github.com/iced-rs/iced/pull/1849) is an open draft and is not merged.
- [Pull request 3111](https://github.com/iced-rs/iced/pull/3111) is an open draft and is not merged.
- [Pull request 3281](https://github.com/iced-rs/iced/pull/3281) is closed without merge.

Passing headless tests and three-platform builds do not supply this missing implementation. Do not expand the feasibility sample into the production desktop app on that basis.

## Required Framework Decision

The plan names Tauri 2 as a possible fallback, but requires explicit approval because it changes the UI to a web UI. A Tauri implementation must still pass native accessibility, keyboard, IME, panel focus, security, and signed Apple integration gates. This record does not establish that Tauri passes them.

Do not add a second UI implementation until the framework decision is approved. Do not use an unmerged upstream branch to bypass the gate.

## Windows Persistence Gate

The local repository currently depends on private directories, durable directory synchronization, and publication of attachment bytes before database references commit. A Windows port needs a supported durability protocol and secure current-user ACL creation.

`MoveFileExW` and `FlushFileBuffers` do not by themselves establish the required general, unprivileged directory synchronization contract. Do not ignore unsupported directory flush errors or request administrator access. Keep Windows storage disabled until the required protocol is established or an alternative storage design is explicitly approved. See the [storage blocker and Microsoft API references](../../Desktop/crates/stow-storage/README.md#windows-durability-blocker).

## Apple Integration Gate

The existing SwiftData store, CloudKit container, Share Extensions, and iOS app remain unchanged. A signed Rust host, its Swift bridge, and two-device iCloud tests remain necessary. Neither repository tests nor unsigned CI builds satisfy that gate.
