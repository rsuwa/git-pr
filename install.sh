#!/usr/bin/env bash

set -euo pipefail

default_url="https://github.com/rsuwa/git-pr/releases/latest/download/git-pr"
install_url="${GIT_PR_INSTALL_URL:-$default_url}"
checksum_url="${GIT_PR_CHECKSUM_URL:-}"
expected_sha256_value="${GIT_PR_INSTALL_SHA256:-}"
install_dir="${GIT_PR_INSTALL_DIR:-$HOME/.local/bin}"
install_path="$install_dir/git-pr"
asset_name="git-pr"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

default_checksum_url() {
  case "$1" in
    */*)
      printf '%s/SHA256SUMS\n' "${1%/*}"
      ;;
    *)
      printf 'SHA256SUMS\n'
      ;;
  esac
}

redact_url() {
  local url="$1"
  local redacted="$url"
  local scheme
  local rest
  local authority
  local path

  case "$redacted" in
    *'#'*)
      redacted="${redacted%%#*}#REDACTED"
      ;;
  esac
  case "$redacted" in
    *'?'*)
      redacted="${redacted%%\?*}?REDACTED"
      ;;
  esac
  case "$redacted" in
    *://*@*)
      scheme="${redacted%%://*}"
      rest="${redacted#*://}"
      authority="${rest%%/*}"
      path="${rest#*/}"
      authority="${authority#*@}"
      if [ "$path" != "$rest" ]; then
        redacted="$scheme://REDACTED@$authority/$path"
      else
        redacted="$scheme://REDACTED@$authority"
      fi
      ;;
  esac

  printf '%s' "$redacted"
}

download_file() {
  local url="$1"
  local output="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$output"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$output" "$url"
  else
    die "Missing command: curl or wget"
  fi
}

require_sha256_tool() {
  if command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1; then
    return 0
  fi

  die "Missing command: sha256sum or shasum"
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

expected_sha256() {
  local expected_asset="$1"
  local sums_file="$2"

  awk -v expected_asset="$expected_asset" '
    NF >= 2 {
      file = $2
      sub(/^\*/, "", file)
      if (file == expected_asset) {
        print $1
        found = 1
        exit
      }
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "$sums_file"
}

verify_checksum() {
  local file="$1"
  local sums_file="$2"
  local expected
  local actual

  expected=$(expected_sha256 "$asset_name" "$sums_file") || return 1
  actual=$(sha256_file "$file") || return 1

  [ "$actual" = "$expected" ]
}

verify_direct_checksum() {
  local file="$1"
  local expected="$2"
  local actual

  actual=$(sha256_file "$file") || return 1
  [ "$actual" = "$expected" ]
}

ensure_install_target_is_regular_executable() {
  local target="$1"

  if [ -L "$target" ] || [ -d "$target" ] || [ ! -f "$target" ] || [ ! -x "$target" ]; then
    die "Installed git-pr target is not a regular executable file: $target"
  fi
}

if [ -z "$checksum_url" ] && [ -z "$expected_sha256_value" ]; then
  checksum_url=$(default_checksum_url "$install_url")
fi

mkdir -p "$install_dir"

if [ -L "$install_path" ]; then
  die "Refusing to install over symlink target: $install_path"
fi

if [ -d "$install_path" ]; then
  die "Refusing to install over directory target: $install_path"
fi

require_sha256_tool

temp_file=$(mktemp "$install_dir/.git-pr.XXXXXX") || die "Failed to create temporary file in $install_dir"
checksum_file=""
cleanup() {
  rm -f "$temp_file" "$checksum_file"
}
trap cleanup EXIT

download_file "$install_url" "$temp_file" || die "Failed to download git-pr from $(redact_url "$install_url")"

if [ -n "$expected_sha256_value" ]; then
  if ! verify_direct_checksum "$temp_file" "$expected_sha256_value"; then
    die "SHA256 verification failed for git-pr"
  fi
else
  checksum_file=$(mktemp "$install_dir/.git-pr.SHA256SUMS.XXXXXX") || die "Failed to create checksum temporary file in $install_dir"
  download_file "$checksum_url" "$checksum_file" || die "Failed to download SHA256SUMS from $(redact_url "$checksum_url")"

  if ! verify_checksum "$temp_file" "$checksum_file"; then
    die "SHA256 verification failed for git-pr"
  fi
fi

bash -n "$temp_file" || die "Downloaded git-pr is not valid Bash."
chmod 755 "$temp_file" || die "Failed to make downloaded git-pr executable."

if [ -L "$install_path" ]; then
  die "Refusing to install over symlink target: $install_path"
fi

if [ -d "$install_path" ]; then
  die "Refusing to install over directory target: $install_path"
fi

mv -f "$temp_file" "$install_path" || die "Failed to install git-pr to $install_path"
ensure_install_target_is_regular_executable "$install_path"

echo "Installed git-pr to $install_path"
echo "Make sure $install_dir is in PATH."
echo "Run 'git pr doctor' to check GitHub CLI setup."
