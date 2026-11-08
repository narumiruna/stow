#!/bin/bash
set -euo pipefail

if [[ -n "${CI:-}" ]]; then
  printf '%s\n' 'Scripts/ui_tests.sh is local-only and must not run in CI.' >&2
  exit 1
fi

# Rust preview native acceptance handoff:
# - Finish implementation and all required headless checks before one final batch.
# - Verify isolated Library create/edit/search/restart and unavailable capabilities.
# - Verify save/discard/cancel, close/quit during storage work, and early quit before
#   the frontend handshake. Check that shutdown finishes without a blocked window.
# - Verify keyboard focus, IME, and screen-reader access on each native platform.
# Existing suites below target the Swift app, not Tauri. They do not establish
# Rust preview runtime acceptance. Keep any future automated UI orchestration here.

usage() {
  printf '%s\n' 'Usage: Scripts/ui_tests.sh [all|macos|ios|ios-share|ios-link-refresh]' >&2
}

if (( $# > 1 )); then
  usage
  exit 64
fi

suite="${1:-all}"
case "$suite" in
  all|macos|ios|ios-share|ios-link-refresh) ;;
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
  shared_root="$(mktemp -d "${TMPDIR:-/tmp}/StowCLISmoke.XXXXXX")" || return $?

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
print(windows.count)' "$host_pid")" || status=$?
      if (( status == 0 )) && [[ "$visible_windows" != "0" ]]; then
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
  xcodebuild "${build_arguments[@]}" build-for-testing || return $?

  local built_products app_path
  built_products="$(
    xcodebuild "${build_arguments[@]}" -showBuildSettings -json |
      plutil -extract 0.buildSettings.BUILT_PRODUCTS_DIR raw -o - -
  )" || return $?
  app_path="$built_products/Stow-macOS.app"
  run_cli_launch_smoke "$app_path" || return $?

  xcodebuild "${build_arguments[@]}" test-without-building
}

# Use a fresh Simulator for captures and authentication notifications.
# Do not clone or stop the development device.
run_ios_tests() (
  local device_spec device_type runtime_id device_id result_bundle enrollment_state old_enrollment=""
  device_spec="$(
    xcrun simctl list devices available -j |
      uv run python -c 'import json,re,sys; devices=json.load(sys.stdin)["devices"]; runtimes=sorted(devices, key=lambda runtime: tuple(map(int, re.findall(r"\d+", runtime)))); print(next(device["deviceTypeIdentifier"] + " " + runtime for runtime in reversed(runtimes) for device in devices[runtime] if device["name"].startswith("iPhone") and device["isAvailable"]))'
  )" || return $?
  read -r device_type runtime_id <<<"$device_spec"
  device_id="$(xcrun simctl create "Stow UI Tests-$(uuidgen)" "$device_type" "$runtime_id")" || return $?
  printf 'Using fresh iOS test simulator %s (%s, %s).\n' "$device_id" "$device_type" "$runtime_id"
  trap 'status=$?; trap - EXIT
    if [[ -n "$old_enrollment" ]] && ! xcrun simctl spawn "$device_id" notifyutil -s com.apple.BiometricKit.enrollmentChanged "$old_enrollment" -p com.apple.BiometricKit.enrollmentChanged; then
      printf "%s\n" "Failed to restore Simulator biometric enrollment state." >&2
      if (( status == 0 )); then status=1; fi
    fi
    xcrun simctl shutdown "$device_id" 2>/dev/null || true
    if ! xcrun simctl delete "$device_id"; then
      printf "%s\n" "Failed to delete the temporary UI-test Simulator." >&2
      if (( status == 0 )); then status=1; fi
    fi
    if [[ "$device_id" =~ ^[0-9A-Fa-f-]{36}$ ]]; then
      rm -rf "/tmp/StowSimulatorAppGroup/$device_id"
    fi
    exit "$status"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  xcrun simctl boot "$device_id" 2>/dev/null || true
  xcrun simctl bootstatus "$device_id" -b || return $?

  enrollment_state="$(xcrun simctl spawn "$device_id" notifyutil -g com.apple.BiometricKit.enrollmentChanged)" || return $?
  if [[ "$enrollment_state" =~ ([0-9]+)[[:space:]]*$ ]]; then
    old_enrollment="${BASH_REMATCH[1]}"
  else
    printf 'Cannot read Simulator biometric enrollment state: %s\n' "$enrollment_state" >&2
    return 1
  fi
  xcrun simctl spawn "$device_id" notifyutil -s com.apple.BiometricKit.enrollmentChanged 1 -p com.apple.BiometricKit.enrollmentChanged || return $?

  mkdir -p "$PWD/.build/ui-test-results" || return $?
  result_bundle="$PWD/.build/ui-test-results/StowUITests-$device_id.xcresult"
  printf 'Saving iOS UI test results to %s.\n' "$result_bundle"
  if [[ "$suite" == "ios-share" ]]; then
    xcodebuild -project Stow.xcodeproj -scheme StowUITests -destination "platform=iOS Simulator,id=$device_id" -resultBundlePath "$result_bundle" -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
      -only-testing:StowUITests/StowUITests/testSafariShareExtensionCapturesURLInOneSave \
      -only-testing:StowUITests/StowUITests/testSafariShareExtensionCanSaveImmediately \
      test
  elif [[ "$suite" == "ios-link-refresh" ]]; then
    xcodebuild -project Stow.xcodeproj -scheme StowUITests -destination "platform=iOS Simulator,id=$device_id" -resultBundlePath "$result_bundle" -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
      -only-testing:StowUITests/StowUITests/testLinkDetailsPullToRefreshAddsMissingContentAndRefreshesExistingPreview \
      -only-testing:StowUITests/StowUITests/testDetailEditingPersistsNote \
      -only-testing:StowUITests/StowUITests/testDetailSaveFailureRetainsDraftAndAllowsRetry \
      -only-testing:StowUITests/StowUITests/testTypeSpecificDetailsExposeRequiredActions \
      test
  else
    xcodebuild -project Stow.xcodeproj -scheme StowUITests -destination "platform=iOS Simulator,id=$device_id" -resultBundlePath "$result_bundle" -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
  fi
)

if [[ "$suite" == "all" || "$suite" == "macos" ]]; then
  if run_macos_tests; then
    printf '%s\n' 'macOS UI tests passed.'
  else
    record_failure "macOS" "$?"
  fi
fi

if [[ "$suite" == "all" || "$suite" == "ios" || "$suite" == "ios-share" || "$suite" == "ios-link-refresh" ]]; then
  if run_ios_tests; then
    printf '%s\n' 'iOS UI tests passed.'
  else
    record_failure "iOS" "$?"
  fi
fi

exit "$result"
