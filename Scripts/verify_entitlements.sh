#!/bin/bash
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
root="$(cd "$(dirname "$0")/.." && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT

product_path() {
  local scheme="$1" sdk="${2:-}"
  local command=(xcodebuild -project "$root/Stow.xcodeproj" -scheme "$scheme" -configuration Debug -showBuildSettings CODE_SIGNING_ALLOWED=NO)
  [[ -n "$sdk" ]] && command+=( -sdk "$sdk" )
  local settings build_dir product
  settings="$(DEVELOPER_DIR="$DEVELOPER_DIR" "${command[@]}" 2>/dev/null)"
  build_dir="$(awk -F ' = ' '/ TARGET_BUILD_DIR = / { print $2; exit }' <<<"$settings")"
  product="$(awk -F ' = ' '/ FULL_PRODUCT_NAME = / { print $2; exit }' <<<"$settings")"
  printf '%s/%s' "$build_dir" "$product"
}

assert_entitlements() {
  local product="$1" expected="$2" name="$3"
  local actual="$temporary/$name.plist"
  codesign -d --entitlements :- "$product" 2>/dev/null > "$actual"
  python3 - "$expected" "$actual" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as source:
    expected = plistlib.load(source)
with open(sys.argv[2], 'rb') as source:
    actual = plistlib.load(source)
if actual != expected:
    raise SystemExit(f"entitlement mismatch:\nexpected={expected!r}\nactual={actual!r}")
PY
}

sign_and_verify() {
  local source_app="$1" host_entitlements="$2" extension_entitlements="$3" extension_relative_path="$4" label="$5"
  local copy="$temporary/$label.app"
  cp -R "$source_app" "$copy"
  local extension="$copy/$extension_relative_path"
  codesign --force --sign - --entitlements "$extension_entitlements" "$extension" >/dev/null
  codesign --force --sign - --entitlements "$host_entitlements" "$copy" >/dev/null
  assert_entitlements "$extension" "$extension_entitlements" "$label-extension"
  assert_entitlements "$copy" "$host_entitlements" "$label-host"
}

mac_app="$(product_path Stow-macOS)"
ios_app="$(product_path Stow-iOS iphonesimulator)"
[[ -d "$mac_app" ]] || { echo "Missing macOS build product: $mac_app" >&2; exit 1; }
[[ -d "$ios_app" ]] || { echo "Missing iOS build product: $ios_app" >&2; exit 1; }

sign_and_verify "$mac_app" \
  "$root/Configuration/Stow-macOS.entitlements" \
  "$root/Configuration/StowShare-macOS.entitlements" \
  "Contents/PlugIns/StowShare-macOS.appex" macOS
sign_and_verify "$ios_app" \
  "$root/Configuration/Stow-iOS.entitlements" \
  "$root/Configuration/StowShare-iOS.entitlements" \
  "PlugIns/StowShare-iOS.appex" iOS

plutil -lint "$root/Configuration/PrivacyInfo.xcprivacy" >/dev/null
echo "Entitlement and privacy-manifest checks passed"
