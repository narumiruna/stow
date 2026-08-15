#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 {major|minor|patch}" >&2
  exit 64
fi

bump_type="$1"
case "$bump_type" in
  major|minor|patch) ;;
  *)
    echo "Unsupported bump type: $bump_type" >&2
    exit 64
    ;;
esac

current_version="$(Scripts/verify_version.sh)"
IFS=. read -r major minor patch <<< "$current_version"
case "$bump_type" in
  major) new_version="$((major + 1)).0.0" ;;
  minor) new_version="${major}.$((minor + 1)).0" ;;
  patch) new_version="${major}.${minor}.$((patch + 1))" ;;
esac

project_setting_count="$(grep -Fc "MARKETING_VERSION = ${current_version};" Stow.xcodeproj/project.pbxproj)"
temporary="$(mktemp -d)"
restore_files=false
cleanup() {
  status=$?
  if [[ "$restore_files" == true ]]; then
    cat "$temporary/original-version" > VERSION
    cat "$temporary/original-generator" > Scripts/generate_project.rb
    cat "$temporary/original-project" > Stow.xcodeproj/project.pbxproj
  fi
  rm -rf "$temporary"
  exit "$status"
}
trap cleanup EXIT

cp VERSION "$temporary/original-version"
cp Scripts/generate_project.rb "$temporary/original-generator"
cp Stow.xcodeproj/project.pbxproj "$temporary/original-project"

render_updated_file() {
  local source="$1"
  local needle="$2"
  local replacement="$3"
  local expected_count="$4"
  local output="$5"

  awk -v needle="$needle" -v replacement="$replacement" -v expected="$expected_count" '
    function replace_literal(value,    position, result) {
      result = ""
      while ((position = index(value, needle)) > 0) {
        result = result substr(value, 1, position - 1) replacement
        value = substr(value, position + length(needle))
        replacements++
      }
      return result value
    }
    { print replace_literal($0) }
    END {
      if (replacements != expected) {
        printf "Expected %d version replacements, found %d.\n", expected, replacements > "/dev/stderr"
        exit 1
      }
    }
  ' "$source" > "$output"
}

render_updated_file VERSION \
  "$current_version" \
  "$new_version" \
  1 \
  "$temporary/updated-version"
render_updated_file Scripts/generate_project.rb \
  "settings[\"MARKETING_VERSION\"] = \"${current_version}\"" \
  "settings[\"MARKETING_VERSION\"] = \"${new_version}\"" \
  1 \
  "$temporary/updated-generator"
render_updated_file Stow.xcodeproj/project.pbxproj \
  "MARKETING_VERSION = ${current_version};" \
  "MARKETING_VERSION = ${new_version};" \
  "$project_setting_count" \
  "$temporary/updated-project"

restore_files=true
cat "$temporary/updated-version" > VERSION
cat "$temporary/updated-generator" > Scripts/generate_project.rb
cat "$temporary/updated-project" > Stow.xcodeproj/project.pbxproj

verified_version="$(Scripts/verify_version.sh)"
if [[ "$verified_version" != "$new_version" ]]; then
  echo "Version verification returned $verified_version, expected $new_version." >&2
  exit 1
fi
restore_files=false

printf '%s\n' "$new_version"
