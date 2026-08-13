#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

usage() {
  echo "Usage: $0 [--tag vMAJOR.MINOR.PATCH]" >&2
}

expected_tag=""
if [[ $# -eq 2 && "$1" == "--tag" ]]; then
  expected_tag="$2"
elif [[ $# -ne 0 ]]; then
  usage
  exit 64
fi

project_version="$(awk -F '"' '/^current_version = / { print $2; exit }' .bumpversion.toml)"
if [[ ! "$project_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "Configured version ${project_version:-<missing>} is not MAJOR.MINOR.PATCH." >&2
  exit 1
fi

if [[ -n "$expected_tag" ]]; then
  if [[ ! "$expected_tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "Tag $expected_tag is not a supported vMAJOR.MINOR.PATCH release tag." >&2
    exit 1
  fi
  if [[ "$expected_tag" != "v${project_version}" ]]; then
    echo "Tag $expected_tag does not match project version v${project_version}." >&2
    exit 1
  fi
fi

generator_setting_count="$(grep -Ec 'settings\["MARKETING_VERSION"\] = "[^"]+"' Scripts/generate_project.rb)"
generator_version="$(sed -n 's/.*settings\["MARKETING_VERSION"\] = "\([^"]*\)".*/\1/p' Scripts/generate_project.rb | head -n 1)"
if [[ "$generator_setting_count" -ne 1 || "$generator_version" != "$project_version" ]]; then
  echo "Project generator version ${generator_version:-<missing>} does not match ${project_version}." >&2
  exit 1
fi

version_setting_count="$(grep -Ec 'MARKETING_VERSION = ' Stow.xcodeproj/project.pbxproj)"
matching_setting_count="$(grep -Ec "MARKETING_VERSION = ${project_version};" Stow.xcodeproj/project.pbxproj)"
if [[ "$version_setting_count" -eq 0 || "$matching_setting_count" -ne "$version_setting_count" ]]; then
  echo "Not every Xcode MARKETING_VERSION matches ${project_version}." >&2
  exit 1
fi

printf '%s\n' "$project_version"
