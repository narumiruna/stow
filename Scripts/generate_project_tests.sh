#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GENERATOR="$ROOT/Scripts/generate_project.rb"
TEMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEMP_ROOT"' EXIT

if ruby "$GENERATOR" --unknown >"$TEMP_ROOT/unknown.out" 2>"$TEMP_ROOT/unknown.err"; then
  echo "Expected unknown arguments to fail" >&2
  exit 1
else
  status=$?
fi
[[ "$status" -eq 64 ]]
grep -Fq "Usage:" "$TEMP_ROOT/unknown.err"

PROJECT="$TEMP_ROOT/Stow.xcodeproj"
ruby "$GENERATOR" --output "$PROJECT" >/dev/null
ruby "$GENERATOR" --check "$PROJECT" >"$TEMP_ROOT/check.out"
grep -Fq "Xcode project is up to date" "$TEMP_ROOT/check.out"

printf '\n// drift\n' >> "$PROJECT/project.pbxproj"
if ruby "$GENERATOR" --check "$PROJECT" >"$TEMP_ROOT/drift.out" 2>"$TEMP_ROOT/drift.err"; then
  echo "Expected project drift to fail" >&2
  exit 1
fi
grep -Fq "project.pbxproj" "$TEMP_ROOT/drift.err"

# Generate and bump a separate repository for every supported arithmetic operation.
# Symlink read-only inputs; only fixture VERSION and project output are written.
for bump in major minor patch; do
  fixture="$TEMP_ROOT/$bump"
  mkdir -p "$fixture/Scripts"
  cp "$GENERATOR" "$ROOT/Scripts/bump_version.sh" "$ROOT/Scripts/verify_version.sh" "$fixture/Scripts/"
  for directory in Sources Tests Packages; do
    ln -s "$ROOT/$directory" "$fixture/$directory"
  done
  printf '1.2.3\n' > "$fixture/VERSION"
  ruby "$fixture/Scripts/generate_project.rb" >/dev/null
  "$fixture/Scripts/bump_version.sh" "$bump" >/dev/null
  ruby "$fixture/Scripts/generate_project.rb" --check >/dev/null
  "$fixture/Scripts/verify_version.sh" >/dev/null

  before="$(cksum "$fixture/Stow.xcodeproj/project.pbxproj")"
  printf '01.2.3\n' > "$fixture/VERSION"
  if ruby "$fixture/Scripts/generate_project.rb" >"$TEMP_ROOT/invalid.out" 2>"$TEMP_ROOT/invalid.err"; then
    echo "Expected malformed VERSION to fail before replacing the project" >&2
    exit 1
  fi
  [[ "$(cksum "$fixture/Stow.xcodeproj/project.pbxproj")" == "$before" ]]
done

echo "Project generator tests passed"
