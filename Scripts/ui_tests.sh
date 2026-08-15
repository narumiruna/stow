#!/bin/bash
set -euo pipefail

if [[ -n "${CI:-}" ]]; then
  printf '%s\n' 'Scripts/ui_tests.sh is local-only and must not run in CI.' >&2
  exit 1
fi

usage() {
  printf '%s\n' 'Usage: Scripts/ui_tests.sh [all|macos|ios]' >&2
}

if (( $# > 1 )); then
  usage
  exit 64
fi

suite="${1:-all}"
case "$suite" in
  all|macos|ios) ;;
  *)
    usage
    exit 64
    ;;
esac

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
result=0

record_failure() {
  local platform="$1"
  local status="$2"
  printf '%s UI tests failed with exit code %d.\n' "$platform" "$status" >&2
  if (( result == 0 )); then result="$status"; fi
}

run_cli_launch_smoke() {
  local app_path="$1"
  local shared_root host_pid visible_windows status=0
  shared_root="$(mktemp -d "${TMPDIR:-/tmp}/StowCLISmoke.XXXXXX")"

  STOW_SHARED_CONTAINER_PATH="$shared_root" \
    "$app_path/Contents/Helpers/stow" status --json --timeout 10 || status=$?
  if (( status == 0 )); then
    sleep 1
    if ! host_pid="$(pgrep -n -x Stow-macOS)"; then
      printf '%s\n' 'The CLI reported success without leaving the Stow host running.' >&2
      status=1
    else
      visible_windows="$(xcrun swift -e 'import CoreGraphics
let pid = Int(CommandLine.arguments[1])!
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let windows = info.filter { ($0[kCGWindowOwnerPID as String] as? Int) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
print(windows.count)' "$host_pid")"
      if [[ "$visible_windows" != "0" ]]; then
        printf 'A CLI launch presented %s visible Stow window(s).\n' "$visible_windows" >&2
        status=1
      fi
    fi
  fi

  pkill -x Stow-macOS 2>/dev/null || true
  rm -rf "$shared_root"
  return "$status"
}

run_macos_tests() {
  if ! DevToolsSecurity -status 2>/dev/null | grep -q "enabled"; then
    printf '%s\n' "macOS Developer Mode is required for macOS UI automation; run 'sudo DevToolsSecurity -enable' first." >&2
    return 77
  fi

  # A stale host with the same bundle identifier prevents XCTest from enabling UI automation.
  pkill -x Stow-macOS 2>/dev/null || true
  pkill -x StowMacUITests-Runner 2>/dev/null || true

  local -a build_arguments=(
    -project Stow.xcodeproj
    -scheme StowMacUITests
    "CODE_SIGN_ENTITLEMENTS="
    "CODE_SIGN_IDENTITY=-"
  )
  xcodebuild "${build_arguments[@]}" build-for-testing

  local built_products app_path
  built_products="$(
    xcodebuild "${build_arguments[@]}" -showBuildSettings -json |
      plutil -extract 0.buildSettings.BUILT_PRODUCTS_DIR raw -o - -
  )"
  app_path="$built_products/Stow-macOS.app"
  run_cli_launch_smoke "$app_path"

  xcodebuild "${build_arguments[@]}" test-without-building
}

run_ios_tests() {
  local device_id
  device_id="$(
    xcrun simctl list devices available -j |
      python3 -c 'import json,re,sys; devices=json.load(sys.stdin)["devices"]; runtimes=sorted(devices, key=lambda runtime: tuple(map(int, re.findall(r"\d+", runtime)))); print(next(device["udid"] for runtime in reversed(runtimes) for device in devices[runtime] if device["name"].startswith("iPhone") and device["isAvailable"]))'
  )"
  xcrun simctl boot "$device_id" 2>/dev/null || true
  xcrun simctl bootstatus "$device_id" -b
  xcodebuild -project Stow.xcodeproj -scheme StowUITests -destination "platform=iOS Simulator,id=$device_id" CODE_SIGNING_ALLOWED=NO test
}

if [[ "$suite" == "all" || "$suite" == "macos" ]]; then
  if run_macos_tests; then
    printf '%s\n' 'macOS UI tests passed.'
  else
    record_failure "macOS" "$?"
  fi
fi

if [[ "$suite" == "all" || "$suite" == "ios" ]]; then
  if run_ios_tests; then
    printf '%s\n' 'iOS UI tests passed.'
  else
    record_failure "iOS" "$?"
  fi
fi

exit "$result"
