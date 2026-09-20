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

echo "Project generator tests passed"
