#!/usr/bin/env bats

setup() {
  export GIT_PR_TEST_BIN="$BATS_TEST_TMPDIR/bin"
  export GIT_PR_TEST_DOWNLOAD="$BATS_TEST_TMPDIR/download/git-pr"
  export GIT_PR_TEST_SUMS="$BATS_TEST_TMPDIR/download/SHA256SUMS"
  mkdir -p "$GIT_PR_TEST_BIN" "$(dirname "$GIT_PR_TEST_DOWNLOAD")"
  export PATH="$GIT_PR_TEST_BIN:$PATH"
  write_download
  write_checksums
  write_fake_curl
}

write_fake_curl() {
  cat > "$GIT_PR_TEST_BIN/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
set -euo pipefail

output=""
url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      output="$2"
      shift 2
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done

[ -n "$output" ] || exit 1
if [ -n "${GIT_PR_TEST_CURL_LOG:-}" ]; then
  printf 'curl %s\n' "$url" >> "$GIT_PR_TEST_CURL_LOG"
fi
case "$url" in
  */SHA256SUMS)
    cp "$GIT_PR_TEST_SUMS" "$output"
    ;;
  *)
    cp "$GIT_PR_TEST_DOWNLOAD" "$output"
    ;;
esac
FAKE_CURL
  chmod 755 "$GIT_PR_TEST_BIN/curl"
}

write_failing_curl() {
  cat > "$GIT_PR_TEST_BIN/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
exit 22
FAKE_CURL
  chmod 755 "$GIT_PR_TEST_BIN/curl"
}

write_checksum_failing_curl() {
  cat > "$GIT_PR_TEST_BIN/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
set -euo pipefail

output=""
url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      output="$2"
      shift 2
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done

[ -n "$output" ] || exit 1
case "$url" in
  */SHA256SUMS)
    exit 22
    ;;
  *)
    cp "$GIT_PR_TEST_DOWNLOAD" "$output"
    ;;
esac
FAKE_CURL
  chmod 755 "$GIT_PR_TEST_BIN/curl"
}

write_directory_swap_chmod() {
  cat > "$GIT_PR_TEST_BIN/chmod" <<'FAKE_CHMOD'
#!/usr/bin/env bash
set -euo pipefail

"$GIT_PR_TEST_REAL_CHMOD" "$@"
if [ -n "${GIT_PR_TEST_INSTALL_PATH:-}" ]; then
  rm -f "$GIT_PR_TEST_INSTALL_PATH"
  mkdir -p "$GIT_PR_TEST_INSTALL_PATH"
fi
FAKE_CHMOD
  chmod 755 "$GIT_PR_TEST_BIN/chmod"
}

copy_current_git_pr_for_update() {
  cp "$BATS_TEST_DIRNAME/../git-pr" "$GIT_PR_TEST_BIN/git-pr"
  chmod 755 "$GIT_PR_TEST_BIN/git-pr"
}

write_download() {
  cat > "$GIT_PR_TEST_DOWNLOAD" <<'DOWNLOAD'
#!/usr/bin/env bash
printf 'downloaded git-pr\n'
DOWNLOAD
  chmod 755 "$GIT_PR_TEST_DOWNLOAD"
}

write_invalid_download() {
  cat > "$GIT_PR_TEST_DOWNLOAD" <<'DOWNLOAD'
#!/usr/bin/env bash
if then
DOWNLOAD
  chmod 755 "$GIT_PR_TEST_DOWNLOAD"
  write_checksums
}

write_checksums() {
  printf '%s  git-pr\n' "$(sha256_of "$GIT_PR_TEST_DOWNLOAD")" > "$GIT_PR_TEST_SUMS"
}

link_tool() {
  local bin="$1"
  local tool="$2"
  local target

  target="$(command -v "$tool" 2>/dev/null || true)"
  [ -n "$target" ] || return 0
  ln -sf "$target" "$bin/$tool"
}

make_wget_only_bin() {
  local bin="$BATS_TEST_TMPDIR/wget-only-bin"
  local tool

  mkdir -p "$bin"
  for tool in bash mkdir dirname mktemp rm awk chmod mv cp grep cat; do
    link_tool "$bin" "$tool"
  done
  if command -v sha256sum >/dev/null 2>&1; then
    link_tool "$bin" sha256sum
  else
    link_tool "$bin" shasum
  fi

  cat > "$bin/wget" <<'FAKE_WGET'
#!/usr/bin/env bash
set -euo pipefail

[ "${1-}" = "-qO" ] || exit 1
output="$2"
url="$3"

if [ -n "${GIT_PR_TEST_WGET_LOG:-}" ]; then
  printf 'wget %s\n' "$url" >> "$GIT_PR_TEST_WGET_LOG"
fi

case "$url" in
  */SHA256SUMS)
    cp "$GIT_PR_TEST_SUMS" "$output"
    ;;
  *)
    cp "$GIT_PR_TEST_DOWNLOAD" "$output"
    ;;
esac
FAKE_WGET
  chmod 755 "$bin/wget"
  printf '%s\n' "$bin"
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

@test "install verifies release SHA256SUMS by default" {
  install_dir="$BATS_TEST_TMPDIR/install"
  curl_log="$BATS_TEST_TMPDIR/curl.log"

  run env \
    -u GIT_PR_INSTALL_SHA256 \
    -u GIT_PR_CHECKSUM_URL \
    GIT_PR_TEST_CURL_LOG="$curl_log" \
    GIT_PR_INSTALL_URL="https://example.invalid/releases/latest/download/git-pr" \
    GIT_PR_INSTALL_DIR="$install_dir" \
    "$BATS_TEST_DIRNAME/../install.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Run 'git pr doctor' to check GitHub CLI setup."* ]]
  [ -x "$install_dir/git-pr" ]
  grep -F "curl https://example.invalid/releases/latest/download/git-pr" "$curl_log"
  grep -F "curl https://example.invalid/releases/latest/download/SHA256SUMS" "$curl_log"
}

@test "install verifies matching GIT_PR_INSTALL_SHA256" {
  expected="$(sha256_of "$GIT_PR_TEST_DOWNLOAD")"
  install_dir="$BATS_TEST_TMPDIR/install"
  curl_log="$BATS_TEST_TMPDIR/curl.log"

  run env \
    -u GIT_PR_CHECKSUM_URL \
    GIT_PR_TEST_CURL_LOG="$curl_log" \
    GIT_PR_INSTALL_URL="https://example.invalid/git-pr" \
    GIT_PR_INSTALL_DIR="$install_dir" \
    GIT_PR_INSTALL_SHA256="$expected" \
    "$BATS_TEST_DIRNAME/../install.sh"

  [ "$status" -eq 0 ]
  [ -x "$install_dir/git-pr" ]
  run "$install_dir/git-pr"
  [ "$output" = "downloaded git-pr" ]
  grep -F "curl https://example.invalid/git-pr" "$curl_log"
  if grep -Fq "SHA256SUMS" "$curl_log"; then
    fail "install with GIT_PR_INSTALL_SHA256 should not download SHA256SUMS"
  fi
}

@test "install checksum mismatch preserves existing executable" {
  install_dir="$BATS_TEST_TMPDIR/install"
  mkdir -p "$install_dir"
  cat > "$install_dir/git-pr" <<'OLD'
#!/usr/bin/env bash
printf 'old git-pr\n'
OLD
  chmod 755 "$install_dir/git-pr"

  run env \
    -u GIT_PR_CHECKSUM_URL \
    GIT_PR_INSTALL_URL="https://example.invalid/git-pr" \
    GIT_PR_INSTALL_DIR="$install_dir" \
    GIT_PR_INSTALL_SHA256="0000000000000000000000000000000000000000000000000000000000000000" \
    "$BATS_TEST_DIRNAME/../install.sh"

  [ "$status" -ne 0 ]
  run "$install_dir/git-pr"
  [ "$output" = "old git-pr" ]
}

@test "update verifies release SHA256SUMS by default" {
  cp "$BATS_TEST_DIRNAME/../git-pr" "$GIT_PR_TEST_BIN/git-pr"
  chmod 755 "$GIT_PR_TEST_BIN/git-pr"
  curl_log="$BATS_TEST_TMPDIR/curl.log"

  run env \
    -u GIT_PR_UPDATE_SHA256 \
    -u GIT_PR_UPDATE_CHECKSUM_URL \
    GIT_PR_TEST_CURL_LOG="$curl_log" \
    GIT_PR_UPDATE_URL="https://example.invalid/releases/latest/download/git-pr" \
    "$GIT_PR_TEST_BIN/git-pr" update

  [ "$status" -eq 0 ]
  update_output="$output"
  [[ "$update_output" == *"INFO: Update URL: https://example.invalid/releases/latest/download/git-pr"* ]]
  [[ "$update_output" == *"INFO: Checksum URL: https://example.invalid/releases/latest/download/SHA256SUMS"* ]]
  [[ "$update_output" == *"INFO: Install target: $GIT_PR_TEST_BIN/git-pr"* ]]
  run "$GIT_PR_TEST_BIN/git-pr"
  [ "$output" = "downloaded git-pr" ]
  grep -F "curl https://example.invalid/releases/latest/download/git-pr" "$curl_log"
  grep -F "curl https://example.invalid/releases/latest/download/SHA256SUMS" "$curl_log"
}

@test "update verifies matching GIT_PR_UPDATE_SHA256" {
  cp "$BATS_TEST_DIRNAME/../git-pr" "$GIT_PR_TEST_BIN/git-pr"
  chmod 755 "$GIT_PR_TEST_BIN/git-pr"
  expected="$(sha256_of "$GIT_PR_TEST_DOWNLOAD")"
  curl_log="$BATS_TEST_TMPDIR/curl.log"

  run env \
    -u GIT_PR_UPDATE_CHECKSUM_URL \
    GIT_PR_TEST_CURL_LOG="$curl_log" \
    GIT_PR_UPDATE_URL="https://example.invalid/git-pr" \
    GIT_PR_UPDATE_SHA256="$expected" \
    "$GIT_PR_TEST_BIN/git-pr" update

  [ "$status" -eq 0 ]
  update_output="$output"
  [[ "$update_output" == *"INFO: Update URL: https://example.invalid/git-pr"* ]]
  [[ "$update_output" == *"INFO: Checksum source: GIT_PR_UPDATE_SHA256"* ]]
  [[ "$update_output" == *"INFO: Install target: $GIT_PR_TEST_BIN/git-pr"* ]]
  run "$GIT_PR_TEST_BIN/git-pr"
  [ "$output" = "downloaded git-pr" ]
  grep -F "curl https://example.invalid/git-pr" "$curl_log"
  if grep -Fq "SHA256SUMS" "$curl_log"; then
    fail "update with GIT_PR_UPDATE_SHA256 should not download SHA256SUMS"
  fi
}

@test "update redacts credentials and query strings in logs" {
  cp "$BATS_TEST_DIRNAME/../git-pr" "$GIT_PR_TEST_BIN/git-pr"
  chmod 755 "$GIT_PR_TEST_BIN/git-pr"
  expected="$(sha256_of "$GIT_PR_TEST_DOWNLOAD")"

  run env \
    -u GIT_PR_UPDATE_CHECKSUM_URL \
    GIT_PR_UPDATE_URL="https://user:secret@example.invalid/git-pr?token=abc#frag" \
    GIT_PR_UPDATE_SHA256="$expected" \
    "$GIT_PR_TEST_BIN/git-pr" update

  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO: Update URL: https://REDACTED@example.invalid/git-pr?REDACTED"* ]]
  [[ "$output" != *"secret"* ]]
  [[ "$output" != *"token=abc"* ]]
}

@test "install redacts credentials and query strings in download errors" {
  install_dir="$BATS_TEST_TMPDIR/install"
  write_failing_curl

  run env \
    -u GIT_PR_INSTALL_SHA256 \
    -u GIT_PR_CHECKSUM_URL \
    GIT_PR_INSTALL_URL="https://user:secret@example.invalid/git-pr?token=abc#frag" \
    GIT_PR_INSTALL_DIR="$install_dir" \
    "$BATS_TEST_DIRNAME/../install.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: Failed to download git-pr from https://REDACTED@example.invalid/git-pr?REDACTED"* ]]
  [[ "$output" != *"secret"* ]]
  [[ "$output" != *"token=abc"* ]]
}

@test "install redacts credentials and query strings in checksum download errors" {
  install_dir="$BATS_TEST_TMPDIR/install"
  write_checksum_failing_curl

  run env \
    -u GIT_PR_INSTALL_SHA256 \
    -u GIT_PR_CHECKSUM_URL \
    GIT_PR_INSTALL_URL="https://user:secret@example.invalid/releases/latest/download/git-pr?token=abc#frag" \
    GIT_PR_INSTALL_DIR="$install_dir" \
    "$BATS_TEST_DIRNAME/../install.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: Failed to download SHA256SUMS from https://REDACTED@example.invalid/releases/latest/download/SHA256SUMS"* ]]
  [[ "$output" != *"secret"* ]]
  [[ "$output" != *"token=abc"* ]]
}

@test "update targets the invoked script before another PATH git-pr" {
  other_bin="$BATS_TEST_TMPDIR/other-bin"
  mkdir -p "$other_bin"
  cat > "$other_bin/git-pr" <<'OTHER'
#!/usr/bin/env bash
printf 'other git-pr\n'
OTHER
  chmod 755 "$other_bin/git-pr"
  cp "$BATS_TEST_DIRNAME/../git-pr" "$GIT_PR_TEST_BIN/git-pr"
  chmod 755 "$GIT_PR_TEST_BIN/git-pr"

  run env \
    -u GIT_PR_UPDATE_SHA256 \
    -u GIT_PR_UPDATE_CHECKSUM_URL \
    PATH="$other_bin:$GIT_PR_TEST_BIN:$PATH" \
    GIT_PR_UPDATE_URL="https://example.invalid/releases/latest/download/git-pr" \
    "$GIT_PR_TEST_BIN/git-pr" update

  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO: Install target: $GIT_PR_TEST_BIN/git-pr"* ]]
  run "$GIT_PR_TEST_BIN/git-pr"
  [ "$output" = "downloaded git-pr" ]
  run "$other_bin/git-pr"
  [ "$output" = "other git-pr" ]
}

@test "update checksum mismatch preserves existing executable" {
  cp "$BATS_TEST_DIRNAME/../git-pr" "$GIT_PR_TEST_BIN/git-pr"
  chmod 755 "$GIT_PR_TEST_BIN/git-pr"

  run env \
    -u GIT_PR_UPDATE_CHECKSUM_URL \
    GIT_PR_UPDATE_URL="https://example.invalid/git-pr" \
    GIT_PR_UPDATE_SHA256="0000000000000000000000000000000000000000000000000000000000000000" \
    "$GIT_PR_TEST_BIN/git-pr" update

  [ "$status" -ne 0 ]
  run "$GIT_PR_TEST_BIN/git-pr" --version
  [[ "$output" == git-pr\ * ]]
}

@test "install fails when SHA256SUMS has no git-pr entry" {
  install_dir="$BATS_TEST_TMPDIR/install"
  printf '%s  other-asset\n' "$(sha256_of "$GIT_PR_TEST_DOWNLOAD")" > "$GIT_PR_TEST_SUMS"

  run env \
    -u GIT_PR_INSTALL_SHA256 \
    -u GIT_PR_CHECKSUM_URL \
    GIT_PR_INSTALL_URL="https://example.invalid/releases/latest/download/git-pr" \
    GIT_PR_INSTALL_DIR="$install_dir" \
    "$BATS_TEST_DIRNAME/../install.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: SHA256 verification failed for git-pr"* ]]
  [ ! -e "$install_dir/git-pr" ]
}

@test "update fails when SHA256SUMS has no git-pr entry" {
  copy_current_git_pr_for_update
  printf '%s  other-asset\n' "$(sha256_of "$GIT_PR_TEST_DOWNLOAD")" > "$GIT_PR_TEST_SUMS"

  run env \
    -u GIT_PR_UPDATE_SHA256 \
    -u GIT_PR_UPDATE_CHECKSUM_URL \
    GIT_PR_UPDATE_URL="https://example.invalid/releases/latest/download/git-pr" \
    "$GIT_PR_TEST_BIN/git-pr" update

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: SHA256 verification failed for git-pr"* ]]
  run "$GIT_PR_TEST_BIN/git-pr" --version
  [[ "$output" == git-pr\ * ]]
}

@test "install rejects invalid downloaded Bash" {
  install_dir="$BATS_TEST_TMPDIR/install"
  write_invalid_download

  run env \
    -u GIT_PR_INSTALL_SHA256 \
    -u GIT_PR_CHECKSUM_URL \
    GIT_PR_INSTALL_URL="https://example.invalid/releases/latest/download/git-pr" \
    GIT_PR_INSTALL_DIR="$install_dir" \
    "$BATS_TEST_DIRNAME/../install.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: Downloaded git-pr is not valid Bash."* ]]
  [ ! -e "$install_dir/git-pr" ]
}

@test "update rejects invalid downloaded Bash and preserves current executable" {
  copy_current_git_pr_for_update
  write_invalid_download

  run env \
    -u GIT_PR_UPDATE_SHA256 \
    -u GIT_PR_UPDATE_CHECKSUM_URL \
    GIT_PR_UPDATE_URL="https://example.invalid/releases/latest/download/git-pr" \
    "$GIT_PR_TEST_BIN/git-pr" update

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: Downloaded git-pr is not valid Bash."* ]]
  run "$GIT_PR_TEST_BIN/git-pr" --version
  [[ "$output" == git-pr\ * ]]
}

@test "install reports download failure" {
  install_dir="$BATS_TEST_TMPDIR/install"
  write_failing_curl

  run env \
    -u GIT_PR_INSTALL_SHA256 \
    -u GIT_PR_CHECKSUM_URL \
    GIT_PR_INSTALL_URL="https://example.invalid/releases/latest/download/git-pr" \
    GIT_PR_INSTALL_DIR="$install_dir" \
    "$BATS_TEST_DIRNAME/../install.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: Failed to download git-pr from https://example.invalid/releases/latest/download/git-pr"* ]]
  [ ! -e "$install_dir/git-pr" ]
}

@test "update reports download failure and preserves current executable" {
  copy_current_git_pr_for_update
  write_failing_curl

  run env \
    -u GIT_PR_UPDATE_SHA256 \
    -u GIT_PR_UPDATE_CHECKSUM_URL \
    GIT_PR_UPDATE_URL="https://user:secret@example.invalid/releases/latest/download/git-pr?token=abc" \
    "$GIT_PR_TEST_BIN/git-pr" update

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: Failed to download git-pr from https://REDACTED@example.invalid/releases/latest/download/git-pr?REDACTED"* ]]
  [[ "$output" != *"secret"* ]]
  [[ "$output" != *"token=abc"* ]]
  run "$GIT_PR_TEST_BIN/git-pr" --version
  [[ "$output" == git-pr\ * ]]
}

@test "install reports checksum download failure" {
  install_dir="$BATS_TEST_TMPDIR/install"
  write_checksum_failing_curl

  run env \
    -u GIT_PR_INSTALL_SHA256 \
    -u GIT_PR_CHECKSUM_URL \
    GIT_PR_INSTALL_URL="https://example.invalid/releases/latest/download/git-pr" \
    GIT_PR_INSTALL_DIR="$install_dir" \
    "$BATS_TEST_DIRNAME/../install.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: Failed to download SHA256SUMS from https://example.invalid/releases/latest/download/SHA256SUMS"* ]]
  [ ! -e "$install_dir/git-pr" ]
}

@test "update reports checksum download failure and preserves current executable" {
  copy_current_git_pr_for_update
  write_checksum_failing_curl

  run env \
    -u GIT_PR_UPDATE_SHA256 \
    -u GIT_PR_UPDATE_CHECKSUM_URL \
    GIT_PR_UPDATE_URL="https://example.invalid/releases/latest/download/git-pr" \
    "$GIT_PR_TEST_BIN/git-pr" update

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: Failed to download SHA256SUMS from https://example.invalid/releases/latest/download/SHA256SUMS"* ]]
  run "$GIT_PR_TEST_BIN/git-pr" --version
  [[ "$output" == git-pr\ * ]]
}

@test "install refuses a symlink target" {
  install_dir="$BATS_TEST_TMPDIR/install"
  mkdir -p "$install_dir"
  target="$BATS_TEST_TMPDIR/old-git-pr"
  printf '#!/usr/bin/env bash\n' > "$target"
  chmod 755 "$target"
  ln -s "$target" "$install_dir/git-pr"

  run env \
    GIT_PR_INSTALL_URL="https://example.invalid/releases/latest/download/git-pr" \
    GIT_PR_INSTALL_DIR="$install_dir" \
    "$BATS_TEST_DIRNAME/../install.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: Refusing to install over symlink target: $install_dir/git-pr"* ]]
}

@test "install refuses a directory target" {
  install_dir="$BATS_TEST_TMPDIR/install"
  mkdir -p "$install_dir/git-pr"

  run env \
    GIT_PR_INSTALL_URL="https://example.invalid/releases/latest/download/git-pr" \
    GIT_PR_INSTALL_DIR="$install_dir" \
    "$BATS_TEST_DIRNAME/../install.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: Refusing to install over directory target: $install_dir/git-pr"* ]]
}

@test "install refuses a directory target created before final move" {
  install_dir="$BATS_TEST_TMPDIR/install"
  install_path="$install_dir/git-pr"
  real_chmod="$(command -v chmod)"
  write_directory_swap_chmod

  run env \
    -u GIT_PR_INSTALL_SHA256 \
    -u GIT_PR_CHECKSUM_URL \
    GIT_PR_TEST_REAL_CHMOD="$real_chmod" \
    GIT_PR_TEST_INSTALL_PATH="$install_path" \
    GIT_PR_INSTALL_URL="https://example.invalid/releases/latest/download/git-pr" \
    GIT_PR_INSTALL_DIR="$install_dir" \
    "$BATS_TEST_DIRNAME/../install.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: Refusing to install over directory target: $install_path"* ]]
  [ -d "$install_path" ]
}

@test "update refuses a symlink target" {
  target="$BATS_TEST_TMPDIR/current-git-pr"
  cp "$BATS_TEST_DIRNAME/../git-pr" "$target"
  chmod 755 "$target"
  ln -s "$target" "$GIT_PR_TEST_BIN/git-pr"

  run env \
    GIT_PR_UPDATE_INSTALL_PATH="$GIT_PR_TEST_BIN/git-pr" \
    GIT_PR_UPDATE_URL="https://example.invalid/releases/latest/download/git-pr" \
    "$GIT_PR_TEST_BIN/git-pr" update

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: Refusing to update symlink target: $GIT_PR_TEST_BIN/git-pr"* ]]
}

@test "update refuses a directory target" {
  home="$BATS_TEST_TMPDIR/home"
  install_path="$home/.local/bin/git-pr"
  mkdir -p "$install_path"
  tool_bin="$(make_wget_only_bin)"

  run env \
    HOME="$home" \
    PATH="$tool_bin" \
    GIT_PR_UPDATE_URL="https://example.invalid/releases/latest/download/git-pr" \
    GIT_PR_UPDATE_INSTALL_PATH="$install_path" \
    "$BATS_TEST_DIRNAME/../git-pr" update

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: Refusing to update directory target: $install_path"* ]]
}

@test "install falls back to wget when curl is unavailable" {
  install_dir="$BATS_TEST_TMPDIR/install"
  tool_bin="$(make_wget_only_bin)"
  wget_log="$BATS_TEST_TMPDIR/wget.log"

  run env \
    -u GIT_PR_INSTALL_SHA256 \
    -u GIT_PR_CHECKSUM_URL \
    PATH="$tool_bin" \
    GIT_PR_TEST_WGET_LOG="$wget_log" \
    GIT_PR_INSTALL_URL="https://example.invalid/releases/latest/download/git-pr" \
    GIT_PR_INSTALL_DIR="$install_dir" \
    "$BATS_TEST_DIRNAME/../install.sh"

  [ "$status" -eq 0 ]
  [ -x "$install_dir/git-pr" ]
  grep -F "wget https://example.invalid/releases/latest/download/git-pr" "$wget_log"
  grep -F "wget https://example.invalid/releases/latest/download/SHA256SUMS" "$wget_log"
}

@test "update falls back to wget when curl is unavailable" {
  tool_bin="$(make_wget_only_bin)"
  wget_log="$BATS_TEST_TMPDIR/wget.log"
  cp "$BATS_TEST_DIRNAME/../git-pr" "$tool_bin/git-pr"
  chmod 755 "$tool_bin/git-pr"

  run env \
    -u GIT_PR_UPDATE_SHA256 \
    -u GIT_PR_UPDATE_CHECKSUM_URL \
    PATH="$tool_bin" \
    GIT_PR_TEST_WGET_LOG="$wget_log" \
    GIT_PR_UPDATE_URL="https://example.invalid/releases/latest/download/git-pr" \
    "$tool_bin/git-pr" update

  [ "$status" -eq 0 ]
  grep -F "wget https://example.invalid/releases/latest/download/git-pr" "$wget_log"
  grep -F "wget https://example.invalid/releases/latest/download/SHA256SUMS" "$wget_log"
  run "$tool_bin/git-pr"
  [ "$output" = "downloaded git-pr" ]
}
