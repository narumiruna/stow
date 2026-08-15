#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT

make_fixture() {
  local fixture="$1"
  mkdir -p "$fixture/Scripts" "$fixture/Stow.xcodeproj"
  printf '%s\n' "1.2.3" > "$fixture/VERSION"
  cat > "$fixture/Scripts/generate_project.rb" <<'RUBY'
settings["MARKETING_VERSION"] = "1.2.3"
RUBY
  cat > "$fixture/Stow.xcodeproj/project.pbxproj" <<'PBX'
MARKETING_VERSION = 1.2.3;
MARKETING_VERSION = 1.2.3;
PBX
  cp "$root/Scripts/bump_version.sh" "$root/Scripts/verify_version.sh" "$fixture/Scripts/"
}

assert_bump() {
  local bump_type="$1"
  local expected_version="$2"
  local fixture="$temporary/$bump_type"
  make_fixture "$fixture"

  actual_version="$($fixture/Scripts/bump_version.sh "$bump_type")"
  if [[ "$actual_version" != "$expected_version" ]]; then
    echo "Expected $bump_type bump $expected_version, got $actual_version." >&2
    exit 1
  fi
  if [[ "$($fixture/Scripts/verify_version.sh)" != "$expected_version" ]]; then
    echo "$bump_type bump left inconsistent version metadata." >&2
    exit 1
  fi
}

assert_bump patch 1.2.4
assert_bump minor 1.3.0
assert_bump major 2.0.0

invalid_fixture="$temporary/invalid"
make_fixture "$invalid_fixture"
before="$(cksum "$invalid_fixture/VERSION" "$invalid_fixture/Scripts/generate_project.rb" "$invalid_fixture/Stow.xcodeproj/project.pbxproj")"
set +e
"$invalid_fixture/Scripts/bump_version.sh" prerelease >/dev/null 2>&1
status=$?
set -e
if [[ "$status" -ne 64 ]]; then
  echo "Expected an unsupported bump type to exit 64, got $status." >&2
  exit 1
fi
after="$(cksum "$invalid_fixture/VERSION" "$invalid_fixture/Scripts/generate_project.rb" "$invalid_fixture/Stow.xcodeproj/project.pbxproj")"
if [[ "$after" != "$before" ]]; then
  echo "Unsupported bump type changed version files." >&2
  exit 1
fi

inconsistent_fixture="$temporary/inconsistent"
make_fixture "$inconsistent_fixture"
printf '%s\n' "MARKETING_VERSION = 9.9.9;" >> "$inconsistent_fixture/Stow.xcodeproj/project.pbxproj"
before="$(cksum "$inconsistent_fixture/VERSION" "$inconsistent_fixture/Scripts/generate_project.rb" "$inconsistent_fixture/Stow.xcodeproj/project.pbxproj")"
if "$inconsistent_fixture/Scripts/bump_version.sh" patch >/dev/null 2>&1; then
  echo "Expected inconsistent version metadata to reject a bump." >&2
  exit 1
fi
after="$(cksum "$inconsistent_fixture/VERSION" "$inconsistent_fixture/Scripts/generate_project.rb" "$inconsistent_fixture/Stow.xcodeproj/project.pbxproj")"
if [[ "$after" != "$before" ]]; then
  echo "Rejected bump changed inconsistent version files." >&2
  exit 1
fi

printf '%s\n' "Version bump tests passed"
