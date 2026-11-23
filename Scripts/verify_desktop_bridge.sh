#!/bin/bash
# Headless bridge checks use only a new disposable preview store.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
if [[ "$(uname -s)" != Darwin ]]; then
  printf '%s\n' 'The Swift bridge check requires macOS.' >&2
  exit 2
fi

package="$root/Desktop/native/macos"
xcrun swift test --package-path "$package"

scratch="$(mktemp -d "${TMPDIR:-/tmp}/stow-desktop-bridge.XXXXXX")"
trap 'rm -rf -- "$scratch"' EXIT
parent="$(cd "$scratch" && pwd -P)"
preview="$parent/dev.narumi.stow.desktop-preview"
xcrun swift run --package-path "$package" StowBridgeFixture seed "$preview"

# rustup selects Desktop/rust-toolchain.toml from this working directory.
cd "$root/Desktop"
cargo run --locked --package stow-desktop --bin stow-bridge-probe -- exercise "$preview"
cargo run --locked --package stow-desktop --bin stow-bridge-probe -- reopen "$preview"
xcrun swift run --package-path "$package" StowBridgeFixture failed-save "$preview"
xcrun swift run --package-path "$package" StowBridgeFixture inspect "$preview"
