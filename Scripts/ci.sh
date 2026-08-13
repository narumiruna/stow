#!/bin/bash
set -euo pipefail

if [[ -z "${DEVELOPER_DIR:-}" && -n "${MD_APPLE_SDK_ROOT:-}" ]]; then
  export DEVELOPER_DIR="$MD_APPLE_SDK_ROOT/Contents/Developer"
fi
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

xcode_version="$(xcodebuild -version)"
swift_version="$(xcrun swift --version)"
expected_xcode_version="${EXPECTED_XCODE_VERSION:-26.6}"
expected_swift_version_prefix="${EXPECTED_SWIFT_VERSION_PREFIX:-6.3}"
printf '%s\n' "$xcode_version"
printf '%s\n' "$swift_version"
grep -Fqx "Xcode $expected_xcode_version" <<<"$xcode_version"
grep -Fq "Swift version $expected_swift_version_prefix" <<<"$swift_version"
Scripts/verify_version_tests.sh
Scripts/verify_version.sh
swift test --package-path Packages/StowCore
xcodebuild -project Stow.xcodeproj -scheme StowAppTests CODE_SIGNING_ALLOWED=NO test
xcodebuild -project Stow.xcodeproj -scheme Stow-macOS -configuration Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Stow.xcodeproj -scheme Stow-iOS -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
Scripts/verify_entitlements.sh
