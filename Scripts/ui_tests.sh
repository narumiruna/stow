#!/bin/bash
set -euo pipefail

if [[ -n "${CI:-}" ]]; then
  printf '%s\n' 'Scripts/ui_tests.sh is local-only and must not run in CI.' >&2
  exit 1
fi

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if ! DevToolsSecurity -status 2>/dev/null | grep -q "enabled"; then
  echo "macOS Developer Mode is required for UI automation; run 'sudo DevToolsSecurity -enable' first." >&2
  exit 77
fi

# A stale host with the same bundle identifier prevents XCTest from enabling UI automation.
pkill -x Stow-macOS 2>/dev/null || true
pkill -x StowMacUITests-Runner 2>/dev/null || true

xcodebuild -project Stow.xcodeproj -scheme StowMacUITests CODE_SIGN_ENTITLEMENTS='' CODE_SIGN_IDENTITY='-' test

device_id="$(
  xcrun simctl list devices available -j |
    python3 -c 'import json,re,sys; devices=json.load(sys.stdin)["devices"]; runtimes=sorted(devices, key=lambda runtime: tuple(map(int, re.findall(r"\d+", runtime)))); print(next(device["udid"] for runtime in reversed(runtimes) for device in devices[runtime] if device["name"].startswith("iPhone") and device["isAvailable"]))'
)"
xcrun simctl boot "$device_id" 2>/dev/null || true
xcrun simctl bootstatus "$device_id" -b
xcodebuild -project Stow.xcodeproj -scheme StowUITests -destination "platform=iOS Simulator,id=$device_id" CODE_SIGNING_ALLOWED=NO test
