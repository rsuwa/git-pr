#!/usr/bin/env bats

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

@test "copilot update mode without an existing PR fails before push" {
  create_fake_copilot

  run "$BATS_TEST_DIRNAME/../git-pr" copilot --mode=update

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: --mode=update requires an existing PR. Use --mode=create."* ]]
  assert_no_git_push
  assert_log_not_contains "gh pr create"
}

@test "deprecated copilot flags warn and map to copilot modes" {
  create_fake_copilot

  run "$BATS_TEST_DIRNAME/../git-pr" --copilot

  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: --copilot is deprecated. Use 'git pr copilot --mode=create'."* ]]
  assert_log_contains "gh pr create --repo example/repo --base main --head feature --title Generated\\ title --body Generated\\ body"

  rm -f "$GIT_PR_FAKE_LOG.created-pr"
  : > "$GIT_PR_FAKE_LOG"

  run "$BATS_TEST_DIRNAME/../git-pr" --copilot-verbose

  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: --copilot-verbose is deprecated. Use 'git pr copilot --detail=verbose'."* ]]
  assert_log_contains "gh pr create --repo example/repo --base main --head feature --title Generated\\ title --body Generated\\ body"

  rm -f "$GIT_PR_FAKE_LOG.created-pr"
  : > "$GIT_PR_FAKE_LOG"

  run env \
    GIT_PR_FAKE_PR_NUMBER=123 \
    GIT_PR_FAKE_PR_BODY="Already written" \
    "$BATS_TEST_DIRNAME/../git-pr" --copilot-update

  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: --copilot-update is deprecated. Use 'git pr copilot --mode=update'."* ]]
  assert_log_contains "gh pr edit 123 --repo example/repo --body"
  grep -F "Already written" "$GIT_PR_FAKE_LOG.pr-edit-body"
  grep -F "Generated body" "$GIT_PR_FAKE_LOG.pr-edit-body"
  assert_log_not_contains "gh pr edit 123 --repo example/repo --title"
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
