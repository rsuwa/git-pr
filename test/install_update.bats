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

write_download() {
  cat > "$GIT_PR_TEST_DOWNLOAD" <<'DOWNLOAD'
#!/usr/bin/env bash
printf 'downloaded git-pr\n'
DOWNLOAD
  chmod 755 "$GIT_PR_TEST_DOWNLOAD"
}

write_checksums() {
  printf '%s  git-pr\n' "$(sha256_of "$GIT_PR_TEST_DOWNLOAD")" > "$GIT_PR_TEST_SUMS"
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

  run env \
    -u GIT_PR_INSTALL_SHA256 \
    -u GIT_PR_CHECKSUM_URL \
    GIT_PR_INSTALL_URL="https://example.invalid/releases/latest/download/git-pr" \
    GIT_PR_INSTALL_DIR="$install_dir" \
    "$BATS_TEST_DIRNAME/../install.sh"

  [ "$status" -eq 0 ]
  [ -x "$install_dir/git-pr" ]
}

@test "install verifies matching GIT_PR_INSTALL_SHA256" {
  expected="$(sha256_of "$GIT_PR_TEST_DOWNLOAD")"
  install_dir="$BATS_TEST_TMPDIR/install"

  run env \
    -u GIT_PR_CHECKSUM_URL \
    GIT_PR_INSTALL_URL="https://example.invalid/git-pr" \
    GIT_PR_INSTALL_DIR="$install_dir" \
    GIT_PR_INSTALL_SHA256="$expected" \
    "$BATS_TEST_DIRNAME/../install.sh"

  [ "$status" -eq 0 ]
  [ -x "$install_dir/git-pr" ]
  run "$install_dir/git-pr"
  [ "$output" = "downloaded git-pr" ]
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

  run env \
    -u GIT_PR_UPDATE_SHA256 \
    -u GIT_PR_UPDATE_CHECKSUM_URL \
    GIT_PR_UPDATE_URL="https://example.invalid/releases/latest/download/git-pr" \
    "$GIT_PR_TEST_BIN/git-pr" update

  [ "$status" -eq 0 ]
  run "$GIT_PR_TEST_BIN/git-pr"
  [ "$output" = "downloaded git-pr" ]
}

@test "update verifies matching GIT_PR_UPDATE_SHA256" {
  cp "$BATS_TEST_DIRNAME/../git-pr" "$GIT_PR_TEST_BIN/git-pr"
  chmod 755 "$GIT_PR_TEST_BIN/git-pr"
  expected="$(sha256_of "$GIT_PR_TEST_DOWNLOAD")"

  run env \
    -u GIT_PR_UPDATE_CHECKSUM_URL \
    GIT_PR_UPDATE_URL="https://example.invalid/git-pr" \
    GIT_PR_UPDATE_SHA256="$expected" \
    "$GIT_PR_TEST_BIN/git-pr" update

  [ "$status" -eq 0 ]
  run "$GIT_PR_TEST_BIN/git-pr"
  [ "$output" = "downloaded git-pr" ]
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
