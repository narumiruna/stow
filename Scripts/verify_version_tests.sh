#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT

mkdir -p "$temporary/Scripts" "$temporary/Stow.xcodeproj"
cp "$root/Scripts/verify_version.sh" "$temporary/Scripts/"
verify="$temporary/Scripts/verify_version.sh"
project="$temporary/Stow.xcodeproj/project.pbxproj"

reset_fixture() {
  printf '1.2.3\n' > "$temporary/VERSION"
  printf 'MARKETING_VERSION = 1.2.3;\nMARKETING_VERSION = 1.2.3;\n' > "$project"
}

assert_rejected() {
  if "$verify" "$@" >/dev/null 2>&1; then
    echo "Expected version verification to fail: $*" >&2
    exit 1
  fi
}

reset_fixture
[[ "$("$verify")" == 1.2.3 ]]
[[ "$("$verify" --tag v1.2.3)" == 1.2.3 ]]
for tag in v1.2.4 1.2.3 v01.2.3 v1.2.3-beta v1x2y3; do
  assert_rejected --tag "$tag"
done
assert_rejected --unknown
assert_rejected --tag
for invalid in '01.2.3' '1.2' '1x2y3' '1.2.3-beta' ' 1.2.3' ''; do
  printf '%s\n' "$invalid" > "$temporary/VERSION"
  assert_rejected
done
printf '1.2.3' > "$temporary/VERSION"
assert_rejected
printf '1.2.3\n\n' > "$temporary/VERSION"
assert_rejected
rm "$temporary/VERSION"
assert_rejected

reset_fixture
printf 'MARKETING_VERSION = 1x2y3;\n' > "$project"
assert_rejected
reset_fixture
printf 'MARKETING_VERSION = 9.9.9;\n' >> "$project"
assert_rejected
printf '// no version settings\n' > "$project"
assert_rejected
rm "$project"
assert_rejected

# Check the actual repository metadata without copying or loading generator source.
[[ "$("$root/Scripts/verify_version.sh")" == "$(cat "$root/VERSION")" ]]
printf '%s\n' 'Version verification tests passed'
