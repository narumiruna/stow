#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT

mkdir -p "$temporary/Scripts" "$temporary/Stow.xcodeproj"
cp "$root/.bumpversion.toml" "$temporary/"
cp "$root/Scripts/generate_project.rb" "$root/Scripts/verify_version.sh" "$temporary/Scripts/"
cp "$root/Stow.xcodeproj/project.pbxproj" "$temporary/Stow.xcodeproj/"

expected_version="$(awk -F '"' '/^current_version = / { print $2; exit }' "$root/.bumpversion.toml")"
baseline_version="$($temporary/Scripts/verify_version.sh)"
if [[ "$baseline_version" != "$expected_version" ]]; then
  echo "Expected baseline version $expected_version, got $baseline_version." >&2
  exit 1
fi

mutated_version="${expected_version/./x}"
mutated_version="${mutated_version/./y}"
while IFS= read -r line; do
  printf '%s\n' "${line//MARKETING_VERSION = ${expected_version};/MARKETING_VERSION = ${mutated_version};}"
done < "$temporary/Stow.xcodeproj/project.pbxproj" > "$temporary/Stow.xcodeproj/project.pbxproj.tmp"
mv "$temporary/Stow.xcodeproj/project.pbxproj.tmp" "$temporary/Stow.xcodeproj/project.pbxproj"

if "$temporary/Scripts/verify_version.sh" >/dev/null 2>&1; then
  echo "Expected non-literal Xcode versions to fail verification." >&2
  exit 1
fi

printf '%s\n' "Version verification tests passed"
