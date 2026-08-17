#!/usr/bin/env bats

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/.."
  BUILD_RELEASE_ASSETS="$REPO_ROOT/script/build-release-assets"
  VERIFY_RELEASE_ASSETS="$REPO_ROOT/script/verify-release-assets"
  VERIFY_RELEASE_TAG="$REPO_ROOT/script/verify-release-tag"
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

prepare_release_fixture() {
  local fixture_root="$1"

  mkdir -p "$fixture_root/script"
  cp "$BUILD_RELEASE_ASSETS" "$fixture_root/script/build-release-assets"
  cp "$VERIFY_RELEASE_ASSETS" "$fixture_root/script/verify-release-assets"
  cp "$REPO_ROOT/git-pr" "$fixture_root/git-pr"
  cp "$REPO_ROOT/install.sh" "$fixture_root/install.sh"
  chmod 755 "$fixture_root/git-pr" "$fixture_root/install.sh" \
    "$fixture_root/script/build-release-assets" "$fixture_root/script/verify-release-assets"
}

prepare_tag_fixture() {
  local repository="$1"
  local remote="$2"

  git init -q "$repository"
  git init -q --bare "$remote"
  git -C "$repository" config user.name "Release Contract Test"
  git -C "$repository" config user.email "release-contract@example.invalid"
  printf 'first\n' > "$repository/tracked"
  git -C "$repository" add tracked
  git -C "$repository" commit -q -m "First"
  git -C "$repository" remote add origin "$remote"
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

@test "build and verify reject directories that cannot be listed" {
  local build_dir="$BATS_TEST_TMPDIR/non-listable-build"
  local release_dir="$BATS_TEST_TMPDIR/non-listable-release"

  mkdir -p "$build_dir"
  printf 'existing\n' > "$build_dir/.extra"
  chmod 311 "$build_dir"
  run "$BUILD_RELEASE_ASSETS" "$build_dir"
  chmod 700 "$build_dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *"readable"* || "$output" == *"list"* ]]

  run "$BUILD_RELEASE_ASSETS" "$release_dir"
  [ "$status" -eq 0 ]
  printf 'unexpected\n' > "$release_dir/.extra"
  chmod 311 "$release_dir"
  run "$VERIFY_RELEASE_ASSETS" "$release_dir"
  chmod 700 "$release_dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *"readable"* || "$output" == *"list"* ]]
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

@test "build normalizes inherited failglob" {
  local release_dir="$BATS_TEST_TMPDIR/release"

  run bash -O failglob "$BUILD_RELEASE_ASSETS" "$release_dir"
  [ "$status" -eq 0 ]
}

@test "verify normalizes inherited nocasematch" {
  local fixture_root="$BATS_TEST_TMPDIR/nocasematch-repo"
  local release_dir="$BATS_TEST_TMPDIR/nocasematch-release"

  prepare_release_fixture "$fixture_root"
  # shellcheck disable=SC2016
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'case "${1-}" in' \
    '  --version) printf "GIT-PR 9.8.7\\n" ;;' \
    '  update)' \
    '    cp "${GIT_PR_UPDATE_URL#file://}" "$GIT_PR_UPDATE_INSTALL_PATH"' \
    '    chmod 755 "$GIT_PR_UPDATE_INSTALL_PATH"' \
    '    ;;' \
    'esac' \
    > "$fixture_root/git-pr"

  run "$fixture_root/script/build-release-assets" "$release_dir"
  [ "$status" -eq 0 ]

  run bash -O nocasematch "$fixture_root/script/verify-release-assets" "$release_dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid version"* ]]
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

@test "verify accepts a release path with URL and checksum-sensitive characters" {
  local release_dir="$BATS_TEST_TMPDIR/release assets #%?\\path"

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

@test "verify syntax-checks install.sh independently" {
  local fixture_root="$BATS_TEST_TMPDIR/invalid-install-repo"
  local release_dir="$BATS_TEST_TMPDIR/invalid-install-release"

  prepare_release_fixture "$fixture_root"
  printf '\nexit 0\nif\n' >> "$fixture_root/install.sh"

  run "$fixture_root/script/build-release-assets" "$release_dir"
  [ "$status" -eq 0 ]

  run "$fixture_root/script/verify-release-assets" "$release_dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *"install.sh"* ]]
}

@test "verify runs the update smoke outside the repository working directory" {
  local fixture_root="$BATS_TEST_TMPDIR/repository-cwd-repo"
  local release_dir="$BATS_TEST_TMPDIR/repository-cwd-release"

  prepare_release_fixture "$fixture_root"
  printf ':\n' > "$fixture_root/script/release-helper.bash"
  # shellcheck disable=SC2016
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'case "${1-}" in' \
    '  --version) printf "git-pr 9.8.7\\n" ;;' \
    '  update)' \
    '    source script/release-helper.bash' \
    '    cp "${GIT_PR_UPDATE_URL#file://}" "$GIT_PR_UPDATE_INSTALL_PATH.new"' \
    '    chmod 755 "$GIT_PR_UPDATE_INSTALL_PATH.new"' \
    '    mv -f "$GIT_PR_UPDATE_INSTALL_PATH.new" "$GIT_PR_UPDATE_INSTALL_PATH"' \
    '    ;;' \
    'esac' \
    > "$fixture_root/git-pr"

  run "$fixture_root/script/build-release-assets" "$release_dir"
  [ "$status" -eq 0 ]

  cd "$fixture_root"
  run "$fixture_root/script/verify-release-assets" "$release_dir" v9.8.7
  [ "$status" -ne 0 ]
}

@test "verify rejects a non-executable installed result" {
  local fixture_root="$BATS_TEST_TMPDIR/non-executable-install-repo"
  local release_dir="$BATS_TEST_TMPDIR/non-executable-install-release"

  prepare_release_fixture "$fixture_root"
  # shellcheck disable=SC2016
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'mkdir -p "$GIT_PR_INSTALL_DIR"' \
    'cp "${GIT_PR_INSTALL_URL#file://}" "$GIT_PR_INSTALL_DIR/git-pr"' \
    'chmod 644 "$GIT_PR_INSTALL_DIR/git-pr"' \
    > "$fixture_root/install.sh"

  run "$fixture_root/script/build-release-assets" "$release_dir"
  [ "$status" -eq 0 ]

  run "$fixture_root/script/verify-release-assets" "$release_dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *"regular executable"* ]]
}

@test "verify rejects a symlinked installed result" {
  local fixture_root="$BATS_TEST_TMPDIR/symlink-install-repo"
  local release_dir="$BATS_TEST_TMPDIR/symlink-install-release"

  prepare_release_fixture "$fixture_root"
  # shellcheck disable=SC2016
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'mkdir -p "$GIT_PR_INSTALL_DIR"' \
    'ln -s "${GIT_PR_INSTALL_URL#file://}" "$GIT_PR_INSTALL_DIR/git-pr"' \
    > "$fixture_root/install.sh"

  run "$fixture_root/script/build-release-assets" "$release_dir"
  [ "$status" -eq 0 ]

  run "$fixture_root/script/verify-release-assets" "$release_dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *"regular executable"* ]]
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

@test "verify rejects NUL bytes in SHA256SUMS" {
  local release_dir="$BATS_TEST_TMPDIR/nul-checksum"

  run "$BUILD_RELEASE_ASSETS" "$release_dir"
  [ "$status" -eq 0 ]
  printf '\0' >> "$release_dir/SHA256SUMS"

  run "$VERIFY_RELEASE_ASSETS" "$release_dir"
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

  prepare_release_fixture "$fixture_root"
  # shellcheck disable=SC2016
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'case "${1-}" in' \
    '  --version) printf "git-pr 9.8.7\\n" ;;' \
    '  update) exit 0 ;;' \
    'esac' \
    > "$fixture_root/git-pr"

  run "$fixture_root/script/build-release-assets" "$release_dir"
  [ "$status" -eq 0 ]

  run "$fixture_root/script/verify-release-assets" "$release_dir" v9.8.7
  [ "$status" -ne 0 ]
  [[ "$output" == *"Updated git-pr differs"* ]]
}

@test "verify rejects a release asset mutated by the update smoke" {
  local fixture_root="$BATS_TEST_TMPDIR/mutating-update-repo"
  local release_dir="$BATS_TEST_TMPDIR/mutating-update-release"

  prepare_release_fixture "$fixture_root"
  # shellcheck disable=SC2016
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'case "${1-}" in' \
    '  --version) printf "git-pr 9.8.7\\n" ;;' \
    '  update)' \
    '    source_path="${GIT_PR_UPDATE_URL#file://}"' \
    '    printf "\\n# staging mutation\\n" >> "$source_path"' \
    '    cp "$source_path" "$GIT_PR_UPDATE_INSTALL_PATH.new"' \
    '    chmod 755 "$GIT_PR_UPDATE_INSTALL_PATH.new"' \
    '    mv -f "$GIT_PR_UPDATE_INSTALL_PATH.new" "$GIT_PR_UPDATE_INSTALL_PATH"' \
    '    ;;' \
    'esac' \
    > "$fixture_root/git-pr"

  run "$fixture_root/script/build-release-assets" "$release_dir"
  [ "$status" -eq 0 ]

  run "$fixture_root/script/verify-release-assets" "$release_dir" v9.8.7
  [ "$status" -ne 0 ]
  [[ "$output" == *"SHA256SUMS"* || "$output" == *canonical* ]]
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

@test "remote tag verification accepts lightweight and annotated tags at HEAD" {
  local repository="$BATS_TEST_TMPDIR/tag-repository"
  local remote="$BATS_TEST_TMPDIR/tag-remote.git"

  prepare_tag_fixture "$repository" "$remote"
  git -C "$repository" tag v1.2.3-lightweight
  git -C "$repository" tag -a v1.2.3-annotated -m "Release"
  git -C "$repository" push -q origin \
    refs/tags/v1.2.3-lightweight refs/tags/v1.2.3-annotated

  cd "$repository"
  run "$VERIFY_RELEASE_TAG" origin v1.2.3-lightweight
  [ "$status" -eq 0 ]
  run "$VERIFY_RELEASE_TAG" origin v1.2.3-annotated
  [ "$status" -eq 0 ]
}

@test "remote tag verification rejects missing and mismatched tags" {
  local repository="$BATS_TEST_TMPDIR/tag-repository"
  local remote="$BATS_TEST_TMPDIR/tag-remote.git"

  prepare_tag_fixture "$repository" "$remote"
  git -C "$repository" tag v1.2.3-old
  git -C "$repository" push -q origin refs/tags/v1.2.3-old
  printf 'second\n' >> "$repository/tracked"
  git -C "$repository" commit -q -am "Second"

  cd "$repository"
  run "$VERIFY_RELEASE_TAG" origin v1.2.3-missing
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
  run "$VERIFY_RELEASE_TAG" origin v1.2.3-old
  [ "$status" -ne 0 ]
  [[ "$output" == *"not checked-out commit"* ]]
}
