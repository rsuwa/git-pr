#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  BUILD_GIT_PR="$REPO_ROOT/script/build-git-pr"
  BUILD_RELEASE_ASSETS="$REPO_ROOT/script/build-release-assets"
}

require_builder_contract() {
  if [ ! -x "$BUILD_GIT_PR" ]; then
    printf 'expected executable source builder: %s\n' "$BUILD_GIT_PR" >&2
    return 1
  fi
  if [ -L "$REPO_ROOT/src" ] || [ ! -d "$REPO_ROOT/src" ]; then
    printf 'expected regular source directory: %s\n' "$REPO_ROOT/src" >&2
    return 1
  fi
}

prepare_source_fixture() {
  local fixture_root="$1"

  require_builder_contract
  mkdir -p "$fixture_root/script"
  cp "$BUILD_GIT_PR" "$fixture_root/script/build-git-pr"
  cp "$BUILD_RELEASE_ASSETS" "$fixture_root/script/build-release-assets"
  cp "$REPO_ROOT/git-pr" "$fixture_root/git-pr"
  cp "$REPO_ROOT/install.sh" "$fixture_root/install.sh"
  cp -R "$REPO_ROOT/src" "$fixture_root/src"
  chmod 755 "$fixture_root/git-pr" "$fixture_root/install.sh" \
    "$fixture_root/script/build-git-pr" \
    "$fixture_root/script/build-release-assets"
}

source_file_at() {
  local fixture_root="$1"
  local position="$2"
  local selected=""
  local source

  for source in "$fixture_root"/src/*.bash; do
    if [ -f "$source" ] && [ ! -L "$source" ]; then
      selected="$source"
      [ "$position" = "last" ] || break
    fi
  done
  [ -n "$selected" ] || return 1
  printf '%s\n' "$selected"
}

assert_check_rejects_without_root_mutation() {
  local fixture_root="$1"
  local case_name="$2"
  local root_before="$fixture_root.root-before"

  cp "$fixture_root/git-pr" "$root_before"
  run "$fixture_root/script/build-git-pr" --check
  if [ "$status" -eq 0 ]; then
    printf 'source check unexpectedly accepted %s\n' "$case_name" >&2
    return 1
  fi
  cmp "$root_before" "$fixture_root/git-pr"
}

assert_no_assembly_temp_entries() {
  local fixture_root="$1"
  local entry

  for entry in "$fixture_root"/.git-pr.build.*; do
    if [ -e "$entry" ] || [ -L "$entry" ]; then
      printf 'unexpected assembly temporary entry: %s\n' "$entry" >&2
      return 1
    fi
  done
}

add_manifest_entry_after_first() {
  local fixture_root="$1"
  local manifest_entry="$2"
  local source_name
  local source_path
  local builder_tmp="$fixture_root/script/build-git-pr.manifest-entry"

  source_name="$(source_file_at "$fixture_root" first)"
  source_name="${source_name##*/}"
  source_path="src/$source_name"

  if ! awk -v path="$source_path" -v entry="$manifest_entry" '
    !changed && index($0, "\"" path "\"") {
      print
      match($0, /^[[:space:]]*/)
      print substr($0, 1, RLENGTH) "\"" entry "\""
      changed = 1
      next
    }
    { print }
    END { if (!changed) exit 1 }
  ' "$fixture_root/script/build-git-pr" > "$builder_tmp"; then
    rm -f "$builder_tmp"
    printf 'could not locate %s in the fixed source manifest\n' \
      "$source_path" >&2
    return 1
  fi

  chmod 755 "$builder_tmp"
  mv "$builder_tmp" "$fixture_root/script/build-git-pr"
}

duplicate_first_manifest_entry() {
  local fixture_root="$1"
  local source_name
  local source_path
  local builder_tmp="$fixture_root/script/build-git-pr.duplicate"

  source_name="$(source_file_at "$fixture_root" first)"
  source_name="${source_name##*/}"
  source_path="src/$source_name"

  if ! awk -v name="$source_name" -v path="$source_path" '
    function duplicate(line, needle, start, size, left, right, token) {
      start = index(line, needle)
      size = length(needle)
      left = substr(line, start - 1, 1)
      right = substr(line, start + size, 1)
      if ((left == "\"" || left == sprintf("%c", 39)) && right == left) {
        start--
        size += 2
      }
      token = substr(line, start, size)
      changed = 1
      return substr(line, 1, start - 1) token " " token \
        substr(line, start + size)
    }
    !changed && index($0, path) { print duplicate($0, path); next }
    !changed && index($0, name) { print duplicate($0, name); next }
    { print }
    END { if (!changed) exit 1 }
  ' "$fixture_root/script/build-git-pr" > "$builder_tmp"; then
    rm -f "$builder_tmp"
    printf 'could not locate %s in the fixed source manifest\n' \
      "$source_path" >&2
    return 1
  fi

  chmod 755 "$builder_tmp"
  mv "$builder_tmp" "$fixture_root/script/build-git-pr"
}

assert_source_shape_rejected() {
  local case_name="$1"
  local fixture_root="$BATS_TEST_TMPDIR/source-$case_name"
  local source
  local target

  prepare_source_fixture "$fixture_root"
  source="$(source_file_at "$fixture_root" first)"
  case "$case_name" in
    missing)
      rm "$source"
      ;;
    extra-visible)
      printf ':\n' > "$fixture_root/src/unlisted.bash"
      ;;
    extra-hidden)
      printf ':\n' > "$fixture_root/src/.unlisted.bash"
      ;;
    directory)
      mkdir "$fixture_root/src/unlisted.bash"
      ;;
    symlink)
      target="$fixture_root/source-target"
      mv "$source" "$target"
      ln -s "$target" "$source"
      ;;
    symlinked-src)
      mv "$fixture_root/src" "$fixture_root/src-real"
      ln -s "$fixture_root/src-real" "$fixture_root/src"
      ;;
    *)
      return 64
      ;;
  esac

  assert_check_rejects_without_root_mutation "$fixture_root" "$case_name"
}

@test "source check is location and inherited-shell-state independent" {
  local outside="$BATS_TEST_TMPDIR/outside"
  local cdpath_dir="$BATS_TEST_TMPDIR/cdpath"
  local root_before="$BATS_TEST_TMPDIR/git-pr.before"

  require_builder_contract
  mkdir -p "$outside" "$cdpath_dir"
  cp "$REPO_ROOT/git-pr" "$root_before"
  cd "$outside"

  run env CDPATH="$cdpath_dir" GLOBIGNORE='*' \
    /bin/bash -f -O dotglob -O failglob "$BUILD_GIT_PR" --check
  [ "$status" -eq 0 ]
  cmp "$root_before" "$REPO_ROOT/git-pr"
}

@test "source check re-enables globbing before enforcing the reverse allowlist" {
  local fixture_root="$BATS_TEST_TMPDIR/noglob-extra-source"
  local root_before="$BATS_TEST_TMPDIR/noglob-extra-source.before"

  prepare_source_fixture "$fixture_root"
  printf ':\n' > "$fixture_root/src/unlisted.bash"
  cp "$fixture_root/git-pr" "$root_before"

  run /bin/bash -f "$fixture_root/script/build-git-pr" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unlisted source directory entry:"* ]]
  cmp "$root_before" "$fixture_root/git-pr"
  assert_no_assembly_temp_entries "$fixture_root"
}

@test "source check ignores CDPATH for a relative builder invocation" {
  local fixture_root="$BATS_TEST_TMPDIR/relative-builder"
  local shadow_root="$BATS_TEST_TMPDIR/cdpath-shadow"
  local root_before="$BATS_TEST_TMPDIR/relative-builder.before"

  prepare_source_fixture "$fixture_root"
  mkdir -p "$shadow_root/script"
  cp "$fixture_root/git-pr" "$root_before"
  cd "$fixture_root"

  run env CDPATH="$shadow_root" /bin/bash script/build-git-pr --check
  [ "$status" -eq 0 ]
  cmp "$root_before" "$fixture_root/git-pr"
  assert_no_assembly_temp_entries "$fixture_root"
}

@test "source check rejects root and source drift without mutation" {
  local root_fixture="$BATS_TEST_TMPDIR/root-drift"
  local source_fixture="$BATS_TEST_TMPDIR/source-drift"
  local source
  local source_before="$BATS_TEST_TMPDIR/source.before"

  prepare_source_fixture "$root_fixture"
  printf '\n# root drift\n' >> "$root_fixture/git-pr"
  assert_check_rejects_without_root_mutation "$root_fixture" "root drift"

  prepare_source_fixture "$source_fixture"
  source="$(source_file_at "$source_fixture" first)"
  printf '\n# source drift\n' >> "$source"
  cp "$source" "$source_before"
  assert_check_rejects_without_root_mutation "$source_fixture" "source drift"
  cmp "$source_before" "$source"
}

@test "rebuild deterministically repairs stale and missing roots" {
  local stale_fixture="$BATS_TEST_TMPDIR/stale-root"
  local missing_fixture="$BATS_TEST_TMPDIR/missing-root"
  local expected="$BATS_TEST_TMPDIR/git-pr.expected"
  local first_build="$BATS_TEST_TMPDIR/git-pr.first-build"

  prepare_source_fixture "$stale_fixture"
  cp "$stale_fixture/git-pr" "$expected"
  printf '#!/usr/bin/env bash\nprintf "stale\\n"\n' > "$stale_fixture/git-pr"
  chmod 600 "$stale_fixture/git-pr"
  run "$stale_fixture/script/build-git-pr"
  [ "$status" -eq 0 ]
  cmp "$expected" "$stale_fixture/git-pr"
  [ -f "$stale_fixture/git-pr" ]
  [ ! -L "$stale_fixture/git-pr" ]
  [ -x "$stale_fixture/git-pr" ]

  cp "$stale_fixture/git-pr" "$first_build"
  run "$stale_fixture/script/build-git-pr"
  [ "$status" -eq 0 ]
  cmp "$first_build" "$stale_fixture/git-pr"

  prepare_source_fixture "$missing_fixture"
  rm "$missing_fixture/git-pr"
  run "$missing_fixture/script/build-git-pr"
  [ "$status" -eq 0 ]
  cmp "$expected" "$missing_fixture/git-pr"
  [ -x "$missing_fixture/git-pr" ]
}

@test "failed assembly preserves an existing regular root" {
  local fixture_root="$BATS_TEST_TMPDIR/invalid-bash"
  local source
  local root_before="$BATS_TEST_TMPDIR/git-pr.before"

  prepare_source_fixture "$fixture_root"
  source="$(source_file_at "$fixture_root" last)"
  printf '\nif\n' >> "$source"
  cp "$fixture_root/git-pr" "$root_before"

  run "$fixture_root/script/build-git-pr"
  [ "$status" -ne 0 ]
  cmp "$root_before" "$fixture_root/git-pr"
  assert_no_assembly_temp_entries "$fixture_root"
}

@test "rebuild rejects symlinked and non-regular roots without replacing them" {
  local symlink_fixture="$BATS_TEST_TMPDIR/symlink-root"
  local directory_fixture="$BATS_TEST_TMPDIR/directory-root"
  local target="$BATS_TEST_TMPDIR/symlink-target"
  local target_before="$BATS_TEST_TMPDIR/target.before"

  prepare_source_fixture "$symlink_fixture"
  mv "$symlink_fixture/git-pr" "$target"
  ln -s "$target" "$symlink_fixture/git-pr"
  cp "$target" "$target_before"
  run "$symlink_fixture/script/build-git-pr"
  [ "$status" -ne 0 ]
  [ -L "$symlink_fixture/git-pr" ]
  cmp "$target_before" "$target"

  prepare_source_fixture "$directory_fixture"
  rm "$directory_fixture/git-pr"
  mkdir "$directory_fixture/git-pr"
  printf 'keep\n' > "$directory_fixture/git-pr/marker"
  run "$directory_fixture/script/build-git-pr"
  [ "$status" -ne 0 ]
  [ -d "$directory_fixture/git-pr" ]
  [ "$(cat "$directory_fixture/git-pr/marker")" = "keep" ]
}

@test "source check enforces the exact regular source allowlist" {
  local case_name

  for case_name in missing extra-visible extra-hidden directory symlink symlinked-src; do
    assert_source_shape_rejected "$case_name"
  done
}

@test "source builder rejects a duplicate fixed-manifest entry" {
  local fixture_root="$BATS_TEST_TMPDIR/duplicate-manifest"
  local root_before="$BATS_TEST_TMPDIR/duplicate-root.before"

  prepare_source_fixture "$fixture_root"
  duplicate_first_manifest_entry "$fixture_root"
  cp "$fixture_root/git-pr" "$root_before"

  run "$fixture_root/script/build-git-pr"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Duplicate source manifest entry"* ]]
  cmp "$root_before" "$fixture_root/git-pr"
  assert_no_assembly_temp_entries "$fixture_root"
}

@test "source builder rejects manifest entries outside direct visible Bash fragments" {
  local case_name
  local fixture_root
  local manifest_entry
  local root_before

  for case_name in traversal duplicate-alias hidden non-bash; do
    fixture_root="$BATS_TEST_TMPDIR/manifest-shape-$case_name"
    root_before="$BATS_TEST_TMPDIR/manifest-shape-$case_name.before"
    prepare_source_fixture "$fixture_root"

    case "$case_name" in
      traversal)
        manifest_entry="src/../install.sh"
        ;;
      duplicate-alias)
        manifest_entry="src/./entrypoint.bash"
        ;;
      hidden)
        manifest_entry="src/.listed.bash"
        printf ':\n' > "$fixture_root/$manifest_entry"
        ;;
      non-bash)
        manifest_entry="src/notes.txt"
        printf ':\n' > "$fixture_root/$manifest_entry"
        ;;
    esac

    add_manifest_entry_after_first "$fixture_root" "$manifest_entry"
    cp "$fixture_root/git-pr" "$root_before"

    run "$fixture_root/script/build-git-pr"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid source manifest entry"* ]]
    cmp "$root_before" "$fixture_root/git-pr"
    assert_no_assembly_temp_entries "$fixture_root"
  done
}

@test "release build rejects drift before creating its destination" {
  local fixture_root="$BATS_TEST_TMPDIR/release-drift"
  local release_dir="$BATS_TEST_TMPDIR/release-assets"
  local fake_bin="$BATS_TEST_TMPDIR/fake-bin"

  prepare_source_fixture "$fixture_root"
  printf '\n# root drift\n' >> "$fixture_root/git-pr"
  mkdir "$fake_bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$fake_bin/build-git-pr"
  chmod 755 "$fake_bin/build-git-pr"

  run env PATH="$fake_bin:$PATH" \
    "$fixture_root/script/build-release-assets" "$release_dir"
  [ "$status" -ne 0 ]
  [ ! -e "$release_dir" ]
}

@test "release build rejects staging below canonical source without leaving drift" {
  local fixture_root="$BATS_TEST_TMPDIR/release-under-source"
  local release_parent="$fixture_root/src/.release-assets"
  local release_dir="$release_parent/nested"
  local source_alias="$BATS_TEST_TMPDIR/release-source-alias"

  prepare_source_fixture "$fixture_root"

  run "$fixture_root/script/build-release-assets" "$release_dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Release directory must not be inside the canonical source directory."* ]]
  [ ! -e "$release_parent" ]

  run "$fixture_root/script/build-git-pr" --check
  [ "$status" -eq 0 ]

  ln -s "$fixture_root/src" "$source_alias"
  run "$fixture_root/script/build-release-assets" \
    "$source_alias/.release-assets-via-alias/nested"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Release directory must not be inside the canonical source directory."* ]]
  [ ! -e "$fixture_root/src/.release-assets-via-alias" ]

  run "$fixture_root/script/build-git-pr" --check
  [ "$status" -eq 0 ]
}
