
download_update_file() {
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

verify_update_checksum() {
  local file="$1"
  local sums_file="$2"
  local expected
  local actual

  expected=$(expected_sha256 "git-pr" "$sums_file") || return 1
  actual=$(sha256_file "$file") || return 1

  [ "$actual" = "$expected" ]
}

verify_direct_update_checksum() {
  local file="$1"
  local expected="$2"
  local actual

  actual=$(sha256_file "$file") || return 1
  [ "$actual" = "$expected" ]
}

cleanup_update_files() {
  local path

  for path in "$@"; do
    [ -n "$path" ] || continue
    rm -f "$path"
    unregister_cleanup_path "$path"
  done
}

resolve_update_install_path() {
  local install_path
  local invoked="${BASH_SOURCE[0]:-$0}"
  local invoked_base
  local invoked_dir

  if [ -n "${GIT_PR_UPDATE_INSTALL_PATH:-}" ]; then
    printf '%s' "$GIT_PR_UPDATE_INSTALL_PATH"
    return 0
  fi

  case "$invoked" in
    */*)
      if [ -e "$invoked" ]; then
        invoked_dir="${invoked%/*}"
        invoked_base="${invoked##*/}"
        install_path=$(cd "$invoked_dir" && printf '%s/%s' "$(pwd -P)" "$invoked_base")
        printf '%s' "$install_path"
        return 0
      fi
      ;;
  esac

  install_path=$(command -v git-pr 2>/dev/null || true)
  if [ -z "$install_path" ]; then
    install_path="${HOME}/.local/bin/git-pr"
  fi
  printf '%s' "$install_path"
}

ensure_update_target_is_safe() {
  local install_path="$1"

  if [ -L "$install_path" ]; then
    die "Refusing to update symlink target: $install_path"
  fi

  if [ -d "$install_path" ]; then
    die "Refusing to update directory target: $install_path"
  fi
}

verify_downloaded_update() {
  local temp_file="$1"
  local checksum_file="$2"
  local checksum_url="$3"
  local expected_sha256_value="$4"

  if [ -n "$expected_sha256_value" ]; then
    verify_direct_update_checksum "$temp_file" "$expected_sha256_value"
    return $?
  fi

  download_update_file "$checksum_url" "$checksum_file" || die "Failed to download SHA256SUMS from $(redact_url "$checksum_url")"
  verify_update_checksum "$temp_file" "$checksum_file"
}

install_downloaded_update() {
  local temp_file="$1"
  local install_path="$2"

  bash -n "$temp_file" || die "Downloaded git-pr is not valid Bash."
  chmod 755 "$temp_file" || die "Failed to make downloaded git-pr executable."
  ensure_update_target_is_safe "$install_path"
  mv -f "$temp_file" "$install_path" || die "Failed to install git-pr to $install_path"
  if [ -L "$install_path" ] || [ -d "$install_path" ] || [ ! -f "$install_path" ] || [ ! -x "$install_path" ]; then
    die "Updated git-pr target is not a regular executable file: $install_path"
  fi
}

update_self() {
  local default_update_url="https://github.com/rsuwa/git-pr/releases/latest/download/git-pr"
  local update_url="${GIT_PR_UPDATE_URL:-$default_update_url}"
  local checksum_url="${GIT_PR_UPDATE_CHECKSUM_URL:-}"
  local expected_sha256_value="${GIT_PR_UPDATE_SHA256:-}"
  local install_path
  local install_dir
  local temp_file
  local checksum_file

  install_path=$(resolve_update_install_path)
  if [ -z "$checksum_url" ] && [ -z "$expected_sha256_value" ]; then
    checksum_url=$(default_update_checksum_url "$update_url")
  fi
  install_dir=$(dirname "$install_path")
  mkdir -p "$install_dir"
  ensure_update_target_is_safe "$install_path"

  require_sha256_tool

  log_info "Update URL: $(redact_url "$update_url")"
  if [ -n "$expected_sha256_value" ]; then
    log_info "Checksum source: GIT_PR_UPDATE_SHA256"
  else
    log_info "Checksum URL: $(redact_url "$checksum_url")"
  fi
  log_info "Install target: $install_path"

  temp_file=$(mktemp "$install_dir/.git-pr.XXXXXX") || die "Failed to create temporary file in $install_dir"
  register_cleanup_path "$temp_file"
  checksum_file=""

  download_update_file "$update_url" "$temp_file" || {
    cleanup_update_files "$temp_file" "$checksum_file"
    die "Failed to download git-pr from $(redact_url "$update_url")"
  }

  if [ -z "$expected_sha256_value" ]; then
    checksum_file=$(mktemp "$install_dir/.git-pr.SHA256SUMS.XXXXXX") || {
      cleanup_update_files "$temp_file" "$checksum_file"
      die "Failed to create checksum temporary file in $install_dir"
    }
    register_cleanup_path "$checksum_file"
  fi

  if ! verify_downloaded_update "$temp_file" "$checksum_file" "$checksum_url" "$expected_sha256_value"; then
    cleanup_update_files "$temp_file" "$checksum_file"
    die "SHA256 verification failed for git-pr"
  fi

  install_downloaded_update "$temp_file" "$install_path"
  unregister_cleanup_path "$temp_file"
  temp_file=""
  cleanup_update_files "$temp_file" "$checksum_file"

  log_info "Updated git-pr at $install_path"
}
