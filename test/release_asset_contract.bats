#!/usr/bin/env bats

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/.."
  BUILD_RELEASE_ASSETS="$REPO_ROOT/script/build-release-assets"
  VERIFY_RELEASE_ASSETS="$REPO_ROOT/script/verify-release-assets"
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

write_checksums() {
  local release_dir="$1"

  printf '%s  git-pr\n%s  install.sh\n' \
    "$(sha256_of "$release_dir/git-pr")" \
    "$(sha256_of "$release_dir/install.sh")" \
    > "$release_dir/SHA256SUMS"
}

release_tag_for() {
  local release_dir="$1"
  local version_output

  version_output="$("$release_dir/git-pr" --version)" || return 1
  case "$version_output" in
    "git-pr "*)
      printf 'v%s\n' "${version_output#git-pr }"
      ;;
    *)
      return 1
      ;;
  esac
}

assert_checksum_diagnostic() {
  case "$output" in
    *checksum*|*Checksum*|*SHA256*)
      ;;
    *)
      printf 'expected a checksum diagnostic, got: %s\n' "$output" >&2
      return 1
      ;;
  esac
}

@test "build emits the exact release asset set with canonical bytes and checksums" {
  local release_dir="$BATS_TEST_TMPDIR/release"
  local expected_sums="$BATS_TEST_TMPDIR/expected-SHA256SUMS"

  run "$BUILD_RELEASE_ASSETS" "$release_dir"
  [ "$status" -eq 0 ]

  run env LC_ALL=C ls -A1 "$release_dir"
  [ "$status" -eq 0 ]
  [ "$output" = $'SHA256SUMS\ngit-pr\ninstall.sh' ]

  cmp "$REPO_ROOT/git-pr" "$release_dir/git-pr"
  cmp "$REPO_ROOT/install.sh" "$release_dir/install.sh"
  [ -x "$release_dir/git-pr" ]
  [ -x "$release_dir/install.sh" ]
  [ ! -x "$release_dir/SHA256SUMS" ]

  printf '%s  git-pr\n%s  install.sh\n' \
    "$(sha256_of "$release_dir/git-pr")" \
    "$(sha256_of "$release_dir/install.sh")" > "$expected_sums"
  cmp "$expected_sums" "$release_dir/SHA256SUMS"
}

@test "build rejects a non-empty destination including hidden entries" {
  local release_dir="$BATS_TEST_TMPDIR/release"

  mkdir -p "$release_dir"
  printf 'existing\n' > "$release_dir/.existing"

  run "$BUILD_RELEASE_ASSETS" "$release_dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be empty"* ]]
  [ ! -e "$release_dir/git-pr" ]
}

@test "build is deterministic across destination directories" {
  local first="$BATS_TEST_TMPDIR/release-first"
  local second="$BATS_TEST_TMPDIR/release-second"

  run "$BUILD_RELEASE_ASSETS" "$first"
  [ "$status" -eq 0 ]
  run "$BUILD_RELEASE_ASSETS" "$second"
  [ "$status" -eq 0 ]

  run diff -r "$first" "$second"
  [ "$status" -eq 0 ]
}

@test "build and verify ignore an inherited CDPATH" {
  local work_dir="$BATS_TEST_TMPDIR/work"
  local cdpath_dir="$BATS_TEST_TMPDIR/cdpath"

  mkdir -p "$work_dir" "$cdpath_dir/release"
  cd "$work_dir"

  run env CDPATH="$cdpath_dir" "$BUILD_RELEASE_ASSETS" release
  [ "$status" -eq 0 ]
  [ -f "$work_dir/release/git-pr" ]
  [ ! -e "$cdpath_dir/release/git-pr" ]

  run env CDPATH="$cdpath_dir" "$VERIFY_RELEASE_ASSETS" release
  [ "$status" -eq 0 ]
}

@test "build and verify normalize inherited glob matching options" {
  local release_dir="$BATS_TEST_TMPDIR/release"

  run bash -O failglob "$BUILD_RELEASE_ASSETS" "$release_dir"
  [ "$status" -eq 0 ]

  printf 'unexpected\n' > "$release_dir/Git-Pr"
  run bash -O nocasematch "$VERIFY_RELEASE_ASSETS" "$release_dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unexpected release asset: Git-Pr"* ]]
}

@test "build and verify reject extra entries when invoked with noglob" {
  local build_dir="$BATS_TEST_TMPDIR/non-empty"
  local release_dir="$BATS_TEST_TMPDIR/release"

  mkdir -p "$build_dir"
  printf 'existing\n' > "$build_dir/.extra"
  run bash -f "$BUILD_RELEASE_ASSETS" "$build_dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be empty"* ]]

  run "$BUILD_RELEASE_ASSETS" "$release_dir"
  [ "$status" -eq 0 ]
  printf 'unexpected\n' > "$release_dir/.extra"
  run bash -f "$VERIFY_RELEASE_ASSETS" "$release_dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unexpected release asset: .extra"* ]]
}

@test "verify accepts a valid bundle with its matching release tag" {
  local release_dir="$BATS_TEST_TMPDIR/release"
  local expected_tag

  run "$BUILD_RELEASE_ASSETS" "$release_dir"
  [ "$status" -eq 0 ]
  expected_tag="$(release_tag_for "$release_dir")"

  run "$VERIFY_RELEASE_ASSETS" "$release_dir" "$expected_tag"
  [ "$status" -eq 0 ]
}

@test "verify accepts a release directory whose path contains spaces" {
  local release_dir="$BATS_TEST_TMPDIR/release assets"

  run "$BUILD_RELEASE_ASSETS" "$release_dir"
  [ "$status" -eq 0 ]

  run "$VERIFY_RELEASE_ASSETS" "$release_dir"
  [ "$status" -eq 0 ]
}

@test "verify ignores inherited direct checksum overrides" {
  local release_dir="$BATS_TEST_TMPDIR/release"

  run "$BUILD_RELEASE_ASSETS" "$release_dir"
  [ "$status" -eq 0 ]

  run env GIT_PR_INSTALL_SHA256=invalid "$VERIFY_RELEASE_ASSETS" "$release_dir"
  [ "$status" -eq 0 ]

  run env GIT_PR_UPDATE_SHA256=invalid "$VERIFY_RELEASE_ASSETS" "$release_dir"
  [ "$status" -eq 0 ]
}

@test "verify rejects a tampered asset and a tampered checksum file" {
  local asset_bundle="$BATS_TEST_TMPDIR/tampered-asset"
  local checksum_bundle="$BATS_TEST_TMPDIR/tampered-checksum"

  run "$BUILD_RELEASE_ASSETS" "$asset_bundle"
  [ "$status" -eq 0 ]
  printf '\n# tampered\n' >> "$asset_bundle/git-pr"

  run "$VERIFY_RELEASE_ASSETS" "$asset_bundle"
  [ "$status" -ne 0 ]
  assert_checksum_diagnostic

  run "$BUILD_RELEASE_ASSETS" "$checksum_bundle"
  [ "$status" -eq 0 ]
  printf '%064d  git-pr\n%s  install.sh\n' \
    0 "$(sha256_of "$checksum_bundle/install.sh")" \
    > "$checksum_bundle/SHA256SUMS"

  run "$VERIFY_RELEASE_ASSETS" "$checksum_bundle"
  [ "$status" -ne 0 ]
  assert_checksum_diagnostic
}

@test "verify rejects staged bytes that differ from the canonical files even with matching checksums" {
  local release_dir="$BATS_TEST_TMPDIR/release"

  run "$BUILD_RELEASE_ASSETS" "$release_dir"
  [ "$status" -eq 0 ]
  printf '\n# staged mutation\n' >> "$release_dir/git-pr"
  write_checksums "$release_dir"

  run "$VERIFY_RELEASE_ASSETS" "$release_dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *canonical* ]]
}

@test "verify rejects hidden extra assets" {
  local release_dir="$BATS_TEST_TMPDIR/release"

  run "$BUILD_RELEASE_ASSETS" "$release_dir"
  [ "$status" -eq 0 ]
  printf 'unexpected\n' > "$release_dir/.extra"

  run "$VERIFY_RELEASE_ASSETS" "$release_dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unexpected release asset: .extra"* ]]
}

@test "verify rejects symlinked release assets" {
  local release_dir="$BATS_TEST_TMPDIR/release"

  run "$BUILD_RELEASE_ASSETS" "$release_dir"
  [ "$status" -eq 0 ]
  rm "$release_dir/install.sh"
  ln -s "$REPO_ROOT/install.sh" "$release_dir/install.sh"

  run "$VERIFY_RELEASE_ASSETS" "$release_dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing regular release asset: install.sh"* ]]
}

@test "verify rejects an update smoke command that succeeds without replacing the target" {
  local fixture_root="$BATS_TEST_TMPDIR/no-op-update-repo"
  local release_dir="$BATS_TEST_TMPDIR/no-op-update-release"

  mkdir -p "$fixture_root/script"
  cp "$BUILD_RELEASE_ASSETS" "$fixture_root/script/build-release-assets"
  cp "$VERIFY_RELEASE_ASSETS" "$fixture_root/script/verify-release-assets"
  cp "$REPO_ROOT/install.sh" "$fixture_root/install.sh"
  # shellcheck disable=SC2016
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'case "${1-}" in' \
    '  --version) printf "git-pr 9.8.7\\n" ;;' \
    '  update) exit 0 ;;' \
    'esac' \
    > "$fixture_root/git-pr"
  chmod 755 "$fixture_root/git-pr" "$fixture_root/install.sh" \
    "$fixture_root/script/build-release-assets" "$fixture_root/script/verify-release-assets"

  run "$fixture_root/script/build-release-assets" "$release_dir"
  [ "$status" -eq 0 ]

  run "$fixture_root/script/verify-release-assets" "$release_dir" v9.8.7
  [ "$status" -ne 0 ]
  [[ "$output" == *"Updated git-pr differs"* ]]
}

@test "verify rejects a release tag that does not match the bundled version" {
  local release_dir="$BATS_TEST_TMPDIR/release"
  local expected_tag
  local mismatched_tag="v0.0.0"

  run "$BUILD_RELEASE_ASSETS" "$release_dir"
  [ "$status" -eq 0 ]
  expected_tag="$(release_tag_for "$release_dir")"
  if [ "$expected_tag" = "$mismatched_tag" ]; then
    mismatched_tag="v0.0.1"
  fi

  run "$VERIFY_RELEASE_ASSETS" "$release_dir" "$mismatched_tag"
  [ "$status" -ne 0 ]
  [[ "$output" == *tag* || "$output" == *Tag* || "$output" == *version* || "$output" == *Version* ]]
}
