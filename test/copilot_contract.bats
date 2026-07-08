#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
# Bats runs each @test in its own process; per-test fake environment exports
# are intentionally scoped to the current test.

load test_helper

setup() {
  setup_fake_cli_env
}

create_malformed_copilot() {
  cat > "$GIT_PR_FAKE_BIN/copilot" <<'FAKE_COPILOT'
#!/usr/bin/env bash
set -euo pipefail

{
  printf 'copilot'
  for arg in "$@"; do
    printf ' %q' "$arg"
  done
  printf '\n'
} >> "$GIT_PR_FAKE_LOG"

printf 'unparseable copilot response\n'
FAKE_COPILOT
  chmod 755 "$GIT_PR_FAKE_BIN/copilot"
}

create_empty_body_copilot() {
  cat > "$GIT_PR_FAKE_BIN/copilot" <<'FAKE_COPILOT'
#!/usr/bin/env bash
set -euo pipefail

{
  printf 'copilot'
  for arg in "$@"; do
    printf ' %q' "$arg"
  done
  printf '\n'
} >> "$GIT_PR_FAKE_LOG"

cat <<'COPILOT_RESPONSE'
__GIT_PR_TITLE__
Generated title
__GIT_PR_BODY__
__GIT_PR_END__
COPILOT_RESPONSE
FAKE_COPILOT
  chmod 755 "$GIT_PR_FAKE_BIN/copilot"
}

create_backslash_copilot() {
  cat > "$GIT_PR_FAKE_BIN/copilot" <<'FAKE_COPILOT'
#!/usr/bin/env bash
set -euo pipefail

{
  printf 'copilot'
  for arg in "$@"; do
    printf ' %q' "$arg"
  done
  printf '\n'
} >> "$GIT_PR_FAKE_LOG"

cat <<'COPILOT_RESPONSE'
__GIT_PR_TITLE__
Generated title
__GIT_PR_BODY__
Path C:\tmp\new and literal \n escape
__GIT_PR_END__
COPILOT_RESPONSE
FAKE_COPILOT
  chmod 755 "$GIT_PR_FAKE_BIN/copilot"
}

hide_host_copilot() {
  local tool_bin="$BATS_TEST_TMPDIR/no-host-copilot-bin"
  mkdir -p "$tool_bin"
  ln -sf "$(command -v bash)" "$tool_bin/bash"
  ln -sf "$(command -v grep)" "$tool_bin/grep"
  ln -sf "$(command -v cat)" "$tool_bin/cat"
  ln -sf "$(command -v rm)" "$tool_bin/rm"
  export PATH="$GIT_PR_FAKE_BIN:$BATS_TEST_DIRNAME/..:$tool_bin"
}

create_selective_chmod() {
  local real_chmod
  real_chmod=$(command -v chmod)
  export GIT_PR_REAL_CHMOD="$real_chmod"
  cat > "$GIT_PR_FAKE_BIN/chmod" <<'FAKE_CHMOD'
#!/usr/bin/env bash
set -euo pipefail

if [ "${GIT_PR_FAKE_CHMOD_FAIL_PRIVATE:-false}" = "true" ] && [ "${1-}" = "700" ]; then
  exit 1
fi
if [ "${1-}" = "700" ]; then
  count_file="$GIT_PR_FAKE_LOG.chmod-private-count"
  count=0
  if [ -f "$count_file" ]; then
    count=$(cat "$count_file")
  fi
  count=$((count + 1))
  printf '%s\n' "$count" > "$count_file"
  if [ -n "${GIT_PR_FAKE_CHMOD_FAIL_PRIVATE_AFTER:-}" ] && [ "$count" -gt "$GIT_PR_FAKE_CHMOD_FAIL_PRIVATE_AFTER" ]; then
    exit 1
  fi
fi
if [ -n "${GIT_PR_FAKE_CHMOD_FAIL_PATH:-}" ] && [ "${2-}" = "$GIT_PR_FAKE_CHMOD_FAIL_PATH" ]; then
  exit 1
fi

exec "$GIT_PR_REAL_CHMOD" "$@"
FAKE_CHMOD
  "$real_chmod" 755 "$GIT_PR_FAKE_BIN/chmod"
}

create_selective_mv() {
  local real_mv
  real_mv=$(command -v mv)
  export GIT_PR_REAL_MV="$real_mv"
  cat > "$GIT_PR_FAKE_BIN/mv" <<'FAKE_MV'
#!/usr/bin/env bash
set -euo pipefail

if [ "${GIT_PR_FAKE_MV_FAIL_TRUNCATED_DIFF:-false}" = "true" ] && [ "${1-}" != "${1%-truncated.txt}" ]; then
  exit 1
fi

exec "$GIT_PR_REAL_MV" "$@"
FAKE_MV
  chmod 755 "$GIT_PR_FAKE_BIN/mv"
}

@test "copilot auto mode creates a new PR when none exists" {
  create_fake_copilot

  run "$BATS_TEST_DIRNAME/../git-pr" copilot --mode=auto

  [ "$status" -eq 0 ]
  assert_log_contains "gh pr create --repo example/repo --base main --head feature --title Generated\\ title --body Generated\\ body"
  assert_log_not_contains "gh pr edit"
}

@test "copilot auto mode updates an existing PR body only" {
  create_fake_copilot

  run env \
    GIT_PR_FAKE_PR_NUMBER=123 \
    GIT_PR_FAKE_PR_TITLE="Existing title" \
    GIT_PR_FAKE_PR_BODY="Already written" \
    "$BATS_TEST_DIRNAME/../git-pr" copilot --mode=auto

  [ "$status" -eq 0 ]
  assert_log_contains "gh pr edit 123 --repo example/repo --body"
  [[ "$output" == *"INFO: Updated PR #123: copilot section."* ]]
  printf '%s' $'Already written\n\n<!-- git-pr:copilot-update:start -->\nGenerated body\n<!-- git-pr:copilot-update:end -->' \
    > "$BATS_TEST_TMPDIR/expected-body.md"
  diff -u "$BATS_TEST_TMPDIR/expected-body.md" "$GIT_PR_FAKE_LOG.pr-edit-body"
  assert_log_not_contains "gh pr edit 123 --repo example/repo --title"
}

@test "copilot update appends inside existing marker block in place" {
  create_fake_copilot

  run env \
    GIT_PR_FAKE_PR_NUMBER=123 \
    GIT_PR_FAKE_PR_TITLE="Existing title" \
    GIT_PR_FAKE_PR_BODY=$'Manual intro\n\n<!-- git-pr:copilot-update:start -->\nOld generated body\n<!-- git-pr:copilot-update:end -->\n\nManual tail' \
    "$BATS_TEST_DIRNAME/../git-pr" copilot --mode=update

  [ "$status" -eq 0 ]
  printf '%s' $'Manual intro\n\n<!-- git-pr:copilot-update:start -->\nOld generated body\n\nGenerated body\n<!-- git-pr:copilot-update:end -->\n\nManual tail' \
    > "$BATS_TEST_TMPDIR/expected-body.md"
  diff -u "$BATS_TEST_TMPDIR/expected-body.md" "$GIT_PR_FAKE_LOG.pr-edit-body"
}

@test "copilot update preserves literal backslashes in generated body" {
  create_backslash_copilot

  run env \
    GIT_PR_FAKE_PR_NUMBER=123 \
    GIT_PR_FAKE_PR_TITLE="Existing title" \
    GIT_PR_FAKE_PR_BODY="Already written" \
    "$BATS_TEST_DIRNAME/../git-pr" copilot --mode=update

  [ "$status" -eq 0 ]
  printf '%s' $'Already written\n\n<!-- git-pr:copilot-update:start -->\nPath C:\\tmp\\new and literal \\n escape\n<!-- git-pr:copilot-update:end -->' \
    > "$BATS_TEST_TMPDIR/expected-body.md"
  diff -u "$BATS_TEST_TMPDIR/expected-body.md" "$GIT_PR_FAKE_LOG.pr-edit-body"
}

@test "copilot update rejects malformed marker block before edit" {
  create_fake_copilot

  run env \
    GIT_PR_FAKE_PR_NUMBER=123 \
    GIT_PR_FAKE_PR_TITLE="Existing title" \
    GIT_PR_FAKE_PR_BODY=$'Manual intro\n\n<!-- git-pr:copilot-update:start -->\nOld generated body' \
    "$BATS_TEST_DIRNAME/../git-pr" copilot --mode=update

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: Existing PR body has an invalid git-pr Copilot update marker block."* ]]
  assert_no_git_push
  assert_no_command_logged "copilot"
  assert_log_not_contains "gh pr edit 123"
}

@test "copilot create mode rejects existing PR" {
  create_fake_copilot
  export GIT_PR_FAKE_PR_NUMBER=123

  run "$BATS_TEST_DIRNAME/../git-pr" copilot --mode=create

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: --mode=create requires no existing PR. Use --mode=update."* ]]
  assert_no_git_push
  assert_log_not_contains "gh pr edit"
}

@test "copilot create mode rejects post-push discovered existing PR before edit" {
  create_fake_copilot
  export GIT_PR_FAKE_PR_NUMBER_AFTER_LIST=2

  run "$BATS_TEST_DIRNAME/../git-pr" copilot --mode=create

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: --mode=create requires no existing PR. Use --mode=update."* ]]
  assert_log_contains "git -C $GIT_PR_FAKE_REPO_ROOT push -u origin HEAD:refs/heads/feature"
  assert_no_command_logged "copilot"
  assert_log_not_contains "gh pr edit"
}

@test "copilot auto mode treats post-push discovered existing PR as an update" {
  create_fake_copilot
  export GIT_PR_FAKE_PR_NUMBER_AFTER_LIST=2
  export GIT_PR_FAKE_PR_BODY="Already written"

  run "$BATS_TEST_DIRNAME/../git-pr" copilot --mode=auto

  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO: Existing PR #123 found for feature."* ]]
  [[ "$output" == *"INFO: Updated PR #123: copilot section."* ]]
  assert_log_contains "git -C $GIT_PR_FAKE_REPO_ROOT push -u origin HEAD:refs/heads/feature"
  assert_log_line_contains_all "gh pr edit 123" "--repo example/repo" "--body"
  assert_log_line_not_contains "gh pr edit 123" "--title"
}

@test "copilot update mode without an existing PR fails before push" {
  create_fake_copilot

  run "$BATS_TEST_DIRNAME/../git-pr" copilot --mode=update

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: --mode=update requires an existing PR. Use --mode=create."* ]]
  assert_no_git_push
  assert_log_not_contains "gh pr create"
}

@test "copilot parse failure falls back to gh fill create" {
  create_malformed_copilot

  run "$BATS_TEST_DIRNAME/../git-pr" copilot

  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: Failed to parse Copilot output; falling back."* ]]
  [[ "$output" == *"WARN: Falling back to --fill."* ]]
  assert_log_contains "gh pr create --repo example/repo --base main --head feature --fill"
  assert_log_not_contains "gh pr create --repo example/repo --base main --head feature --title"
}

@test "copilot empty marked body falls back without raw parser errors" {
  create_empty_body_copilot

  run "$BATS_TEST_DIRNAME/../git-pr" copilot

  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: Failed to parse Copilot output; falling back."* ]]
  [[ "$output" == *"WARN: Falling back to --fill."* ]]
  [[ "$output" != *"cat:"* ]]
  [[ "$output" != *"body.txt"* ]]
  assert_log_contains "gh pr create --repo example/repo --base main --head feature --fill"
  assert_log_not_contains "gh pr create --repo example/repo --base main --head feature --title"
}

@test "missing copilot CLI falls back to gh fill create" {
  hide_host_copilot

  run "$BATS_TEST_DIRNAME/../git-pr" copilot

  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: Copilot CLI not found; falling back."* ]]
  [[ "$output" == *"WARN: Falling back to --fill."* ]]
  assert_log_contains "gh pr create --repo example/repo --base main --head feature --fill"
}

@test "copilot diff excludes are passed as git pathspec exclusions" {
  create_fake_copilot

  run "$BATS_TEST_DIRNAME/../git-pr" copilot --diff-exclude 'docs/**' --diff-exclude=generated/file

  [ "$status" -eq 0 ]
  assert_log_contains "git -C $GIT_PR_FAKE_REPO_ROOT diff --quiet origin/main...HEAD -- . :\\(exclude\\)docs/\\*\\* :\\(exclude\\)generated/file"
  assert_log_contains "git -C $GIT_PR_FAKE_REPO_ROOT diff --stat origin/main...HEAD -- . :\\(exclude\\)docs/\\*\\* :\\(exclude\\)generated/file"
  assert_log_contains "git -C $GIT_PR_FAKE_REPO_ROOT diff origin/main...HEAD -- . :\\(exclude\\)docs/\\*\\* :\\(exclude\\)generated/file"
}

@test "invalid copilot diff max bytes fails before copilot invocation" {
  create_fake_copilot

  run env GIT_PR_COPILOT_DIFF_MAX_BYTES=invalid "$BATS_TEST_DIRNAME/../git-pr" copilot

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: GIT_PR_COPILOT_DIFF_MAX_BYTES must be an integer."* ]]
  assert_no_git_push
  assert_no_command_logged "copilot"
  assert_log_not_contains "gh pr create"
}

@test "copilot debug log omits prompt diff and response content by default" {
  create_malformed_copilot
  log_dir="$BATS_TEST_TMPDIR/copilot-logs"

  run env GIT_PR_COPILOT_LOG_DIR="$log_dir" "$BATS_TEST_DIRNAME/../git-pr" copilot

  [ "$status" -eq 0 ]
  reason_file="$(echo "$log_dir"/*.reason)"
  [ -f "$reason_file" ]
  [ "$(cat "$reason_file")" = "copilot-parse-failed" ]
  base="${reason_file%.reason}"
  [ -f "$base.meta" ]
  grep -F "Prompt, diff, and response content omitted." "$base.meta"
  [ ! -e "$base.prompt" ]
  [ ! -e "$base.diff" ]
  [ ! -e "$base.response" ]
}

@test "copilot debug log keeps prompt diff and response when content opt-in is set" {
  create_malformed_copilot
  log_dir="$BATS_TEST_TMPDIR/copilot-logs"

  run env \
    GIT_PR_COPILOT_LOG_DIR="$log_dir" \
    GIT_PR_COPILOT_LOG_CONTENT=1 \
    "$BATS_TEST_DIRNAME/../git-pr" copilot

  [ "$status" -eq 0 ]
  reason_file="$(echo "$log_dir"/*.reason)"
  [ -f "$reason_file" ]
  [ "$(cat "$reason_file")" = "copilot-parse-failed" ]
  base="${reason_file%.reason}"
  [ -f "$base.prompt" ]
  [ -f "$base.diff" ]
  [ -f "$base.response" ]
  [ ! -e "$base.meta" ]
  grep -F "Input:" "$base.prompt"
  grep -F "diff --git a/git-pr b/git-pr" "$base.diff"
  grep -F "unparseable copilot response" "$base.response"
}

@test "copilot refuses to build prompt when temporary directory cannot be secured" {
  create_fake_copilot
  create_selective_chmod
  tmp_root="$BATS_TEST_TMPDIR/private-tmp"
  mkdir -p "$tmp_root"

  run env \
    TMPDIR="$tmp_root" \
    GIT_PR_FAKE_CHMOD_FAIL_PRIVATE=true \
    "$BATS_TEST_DIRNAME/../git-pr" copilot

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: Failed to secure temporary directory:"* ]]
  assert_no_git_push
  assert_no_command_logged "copilot"
  assert_log_not_contains "gh pr create"
  [ -z "$(find "$tmp_root" -mindepth 1 -maxdepth 1 -name 'git-pr.*' -print -quit)" ]
}

@test "copilot diff truncation write failure falls back without invoking copilot" {
  create_fake_copilot
  create_selective_mv

  run env \
    GIT_PR_COPILOT_DIFF_MAX_BYTES=1 \
    GIT_PR_FAKE_MV_FAIL_TRUNCATED_DIFF=true \
    "$BATS_TEST_DIRNAME/../git-pr" copilot

  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: Failed to prepare Copilot prompt; falling back."* ]]
  assert_no_command_logged "copilot"
  assert_log_contains "gh pr create --repo example/repo --base main --head feature --fill"
}

@test "copilot reuses preflighted private temp directory after push" {
  create_fake_copilot
  create_selective_chmod

  run env \
    GIT_PR_FAKE_CHMOD_FAIL_PRIVATE_AFTER=1 \
    "$BATS_TEST_DIRNAME/../git-pr" copilot

  [ "$status" -eq 0 ]
  [ "$(cat "$GIT_PR_FAKE_LOG.chmod-private-count")" = "1" ]
  assert_log_contains "git -C $GIT_PR_FAKE_REPO_ROOT push -u origin HEAD:refs/heads/feature"
  assert_log_contains "copilot -s --no-custom-instructions -p"
  assert_log_contains "gh pr create --repo example/repo --base main --head feature --title Generated\\ title --body Generated\\ body"
}

@test "copilot debug log is skipped when log directory cannot be secured" {
  create_malformed_copilot
  create_selective_chmod
  log_dir="$BATS_TEST_TMPDIR/copilot-logs"

  run env \
    GIT_PR_COPILOT_LOG_DIR="$log_dir" \
    GIT_PR_COPILOT_LOG_CONTENT=1 \
    GIT_PR_FAKE_CHMOD_FAIL_PATH="$log_dir" \
    "$BATS_TEST_DIRNAME/../git-pr" copilot

  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: Skipping Copilot debug log because directory could not be secured: $log_dir"* ]]
  [ -z "$(find "$log_dir" -type f -print -quit 2>/dev/null)" ]
  assert_log_contains "gh pr create --repo example/repo --base main --head feature --fill"
}

@test "copilot update skips insecure debug log and preserves existing body" {
  create_malformed_copilot
  create_selective_chmod
  log_dir="$BATS_TEST_TMPDIR/copilot-logs"

  run env \
    GIT_PR_COPILOT_LOG_DIR="$log_dir" \
    GIT_PR_COPILOT_LOG_CONTENT=1 \
    GIT_PR_FAKE_CHMOD_FAIL_PATH="$log_dir" \
    GIT_PR_FAKE_PR_NUMBER=123 \
    GIT_PR_FAKE_PR_BODY="Already written" \
    "$BATS_TEST_DIRNAME/../git-pr" copilot --mode=update

  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: Skipping Copilot debug log because directory could not be secured: $log_dir"* ]]
  [[ "$output" == *"WARN: Copilot failed; leaving existing PR title/body unchanged."* ]]
  [ -z "$(find "$log_dir" -type f -print -quit 2>/dev/null)" ]
  assert_log_not_contains "gh pr edit 123"
}
