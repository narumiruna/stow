#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
bin_dir="${HOME}/.local/bin"
app_path=""
force=0
uninstall=0

usage() {
  cat <<'EOF'
Usage: Scripts/install_cli.sh [--app PATH] [--bin-dir PATH] [--force]
       Scripts/install_cli.sh --uninstall [--bin-dir PATH]

Installs a symlink named stow without modifying shell profiles.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      [[ $# -ge 2 ]] || { echo "--app requires a path" >&2; exit 64; }
      app_path="$2"
      shift 2
      ;;
    --bin-dir)
      [[ $# -ge 2 ]] || { echo "--bin-dir requires a path" >&2; exit 64; }
      bin_dir="$2"
      shift 2
      ;;
    --force)
      force=1
      shift
      ;;
    --uninstall)
      uninstall=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

destination="$bin_dir/stow"
if [[ "$uninstall" -eq 1 ]]; then
  if [[ -L "$destination" ]]; then
    rm "$destination"
    echo "Removed $destination"
  elif [[ -e "$destination" ]]; then
    echo "Refusing to remove non-symlink: $destination" >&2
    exit 73
  else
    echo "No Stow CLI symlink is installed at $destination"
  fi
  exit 0
fi

if [[ -z "$app_path" ]]; then
  candidates=(
    "$root/.build/XcodeDerivedData/Build/Products/Debug/Stow-macOS.app"
    "/Applications/Stow.app"
    "/Applications/Stow-macOS.app"
    "$HOME/Applications/Stow.app"
    "$HOME/Applications/Stow-macOS.app"
  )
  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate/Contents/Helpers/stow" ]]; then
      app_path="$candidate"
      break
    fi
  done
fi

[[ -n "$app_path" ]] || {
  echo "Could not find Stow.app; pass --app PATH after building or installing Stow." >&2
  exit 69
}
app_path="$(cd "$(dirname "$app_path")" && pwd -P)/$(basename "$app_path")"
helper="$app_path/Contents/Helpers/stow"
[[ -x "$helper" ]] || {
  echo "The Stow CLI helper is missing or not executable: $helper" >&2
  exit 69
}

mkdir -p "$bin_dir"
if [[ -e "$destination" || -L "$destination" ]]; then
  current="$(readlink "$destination" 2>/dev/null || true)"
  if [[ -L "$destination" && "$current" == "$helper" ]]; then
    echo "Stow CLI is already installed at $destination"
    exit 0
  fi
  managed_symlink=0
  if [[ -L "$destination" ]]; then
    case "$current" in
      *Stow.app/Contents/Helpers/stow|*Stow-macOS.app/Contents/Helpers/stow) managed_symlink=1 ;;
    esac
  fi
  if [[ "$force" -ne 1 && "$managed_symlink" -ne 1 ]]; then
    echo "Refusing to replace $destination; pass --force to replace it." >&2
    exit 73
  fi
  rm "$destination"
fi
ln -s "$helper" "$destination"
echo "Installed $destination -> $helper"
case ":${PATH}:" in
  *":${bin_dir}:"*) ;;
  *) echo "Add $bin_dir to PATH before invoking stow by name." ;;
esac
