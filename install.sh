#!/usr/bin/env bash

set -euo pipefail

default_url="https://github.com/rsuwa/git-pr/releases/latest/download/git-pr"
install_url="${GIT_PR_INSTALL_URL:-$default_url}"
install_dir="${GIT_PR_INSTALL_DIR:-$HOME/.local/bin}"
install_path="$install_dir/git-pr"

mkdir -p "$install_dir"

temp_file=$(mktemp)
cleanup() {
  rm -f "$temp_file"
}
trap cleanup EXIT

if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$install_url" -o "$temp_file"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$temp_file" "$install_url"
else
  echo "ERROR: Missing command: curl or wget" >&2
  exit 1
fi

bash -n "$temp_file"
install -m 755 "$temp_file" "$install_path"

echo "Installed git-pr to $install_path"
echo "Make sure $install_dir is in PATH."
