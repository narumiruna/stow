#!/bin/bash
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

xcode_version="$(xcodebuild -version)"
swift_version="$(xcrun swift --version)"
expected_xcode_version="${EXPECTED_XCODE_VERSION:-26.6}"
expected_swift_version_prefix="${EXPECTED_SWIFT_VERSION_PREFIX:-6.3}"
printf '%s\n' "$xcode_version"
printf '%s\n' "$swift_version"
grep -Fqx "Xcode $expected_xcode_version" <<<"$xcode_version"
grep -Fq "Swift version $expected_swift_version_prefix" <<<"$swift_version"
swift test --package-path Packages/StowCore
xcodebuild -project Stow.xcodeproj -scheme StowAppTests CODE_SIGNING_ALLOWED=NO test
xcodebuild -project Stow.xcodeproj -scheme Stow-macOS -configuration Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Stow.xcodeproj -scheme Stow-iOS -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
Scripts/verify_entitlements.sh

if [[ "${RUN_UI_TESTS:-0}" == "1" ]]; then
  xcodebuild -project Stow.xcodeproj -scheme StowMacUITests CODE_SIGN_ENTITLEMENTS='' CODE_SIGN_IDENTITY='-' test
  device_id="$(xcrun simctl list devices available -j | python3 -c 'import json,re,sys; d=json.load(sys.stdin)["devices"]; runtimes=sorted(d, key=lambda r: tuple(map(int, re.findall(r"\d+", r)))); print(next(x["udid"] for r in reversed(runtimes) for x in d[r] if x["name"].startswith("iPhone") and x["isAvailable"]))')"
  xcrun simctl boot "$device_id" 2>/dev/null || true
  xcrun simctl bootstatus "$device_id" -b
  xcodebuild -project Stow.xcodeproj -scheme StowUITests -destination "platform=iOS Simulator,id=$device_id" CODE_SIGNING_ALLOWED=NO test
fi
