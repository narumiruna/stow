#!/bin/bash
set -euo pipefail

# Pass --replace-existing to update existing skills.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

exec xcrun agent skills export --output-dir "$root/.agents/skills" "$@"
