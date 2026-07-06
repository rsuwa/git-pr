#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
# Bats runs each @test in its own process; per-test fake environment exports
# are intentionally scoped to the current test.

load test_helper

setup() {
  setup_fake_cli_env
}

@test "create pushes current branch and creates a filled pull request" {
  run "$BATS_TEST_DIRNAME/../git-pr" --label bug,backend --reviewer alice,bob --assignee alice

  [ "$status" -eq 0 ]
  assert_log_contains "push -u origin HEAD"
  assert_log_contains "gh pr create --repo example/repo --base main --head feature --label bug --label backend --reviewer alice --reviewer bob --assignee alice --fill"
}

@test "existing PR with --no-edit can still update metadata" {
  export GIT_PR_FAKE_PR_NUMBER=123

  run "$BATS_TEST_DIRNAME/../git-pr" --no-edit --label bug --reviewer alice --assignee bob

  [ "$status" -eq 0 ]
  assert_log_contains "gh pr edit 123 --repo example/repo --add-label bug --add-reviewer alice --add-assignee bob"
  [[ "$output" == *"INFO: Updated PR #123: labels, reviewers, assignees."* ]]
}

@test "existing PR metadata-only update does not require local base" {
  export GIT_PR_FAKE_PR_NUMBER=123
  export GIT_PR_FAKE_REMOTE_BASE_EXISTS=false

  run "$BATS_TEST_DIRNAME/../git-pr" --no-edit --label bug

  [ "$status" -eq 0 ]
  assert_log_contains "gh pr edit 123 --repo example/repo --add-label bug"
  [[ "$output" == *"INFO: Updated PR #123: labels."* ]]
  assert_log_not_contains "git -C $GIT_PR_FAKE_REPO_ROOT fetch origin"
  assert_log_not_contains "git -C $GIT_PR_FAKE_REPO_ROOT rev-list --count"
}

@test "auto-merge subcommand assembles merge flags" {
  export GIT_PR_FAKE_PR_NUMBER=123
  export GIT_PR_FAKE_PR_HEAD_SHA=abc123

  run "$BATS_TEST_DIRNAME/../git-pr" auto-merge --merge-method squash --delete-branch --match-head-commit abc123

  [ "$status" -eq 0 ]
  assert_log_contains "gh pr merge 123 --repo example/repo --auto --squash --match-head-commit abc123 --delete-branch"
  [[ "$output" == *"INFO: Auto-merge requested for PR #123."* ]]
}

@test "auto-merge defaults match-head-commit to local HEAD" {
  export GIT_PR_FAKE_PR_NUMBER=123
  export GIT_PR_FAKE_HEAD_SHA=local-head
  export GIT_PR_FAKE_PR_HEAD_SHA=local-head

  run "$BATS_TEST_DIRNAME/../git-pr" auto-merge

  [ "$status" -eq 0 ]
  assert_log_contains "gh pr merge 123 --repo example/repo --auto --merge --match-head-commit local-head"
}

@test "deprecated merge alias warns and maps to auto-merge" {
  export GIT_PR_FAKE_PR_NUMBER=123
  export GIT_PR_FAKE_HEAD_SHA=local-head
  export GIT_PR_FAKE_PR_HEAD_SHA=local-head

  run "$BATS_TEST_DIRNAME/../git-pr" merge

  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: 'git pr merge' is deprecated. Use 'git pr auto-merge'."* ]]
  assert_log_contains "gh pr merge 123 --repo example/repo --auto --merge --match-head-commit local-head"
}

@test "auto-merge rejects stale pull request head" {
  export GIT_PR_FAKE_PR_NUMBER=123
  export GIT_PR_FAKE_HEAD_SHA=local-head
  export GIT_PR_FAKE_PR_HEAD_SHA=remote-head

  run "$BATS_TEST_DIRNAME/../git-pr" auto-merge

  [ "$status" -ne 0 ]
  [[ "$output" == *"does not match expected head SHA"* ]]
  assert_log_not_contains "gh pr merge"
}

@test "missing option values use a stable error" {
  run "$BATS_TEST_DIRNAME/../git-pr" --base

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: --base requires a value."* ]]
}

@test "copilot-only explicit options are rejected outside copilot mode" {
  run "$BATS_TEST_DIRNAME/../git-pr" --language ja

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: --language/--diff-exclude require 'git pr copilot' or --copilot."* ]]
}

@test "invalid copilot language config does not break non-copilot existing PR operations" {
  export GIT_PR_FAKE_PR_NUMBER=123
  export GIT_PR_LANGUAGE=fr

  run "$BATS_TEST_DIRNAME/../git-pr" --no-edit

  [ "$status" -eq 0 ]
  assert_log_contains "push -u origin HEAD"
  assert_log_not_contains "Invalid language"
}

@test "missing body file fails before push" {
  run "$BATS_TEST_DIRNAME/../git-pr" --body-file "$BATS_TEST_TMPDIR/missing.md"

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: Body file not found:"* ]]
  assert_no_git_push
}

@test "existing PR create-only template option fails before push" {
  export GIT_PR_FAKE_PR_NUMBER=123
  printf 'template\n' > "$GIT_PR_FAKE_REPO_ROOT/pull_request_template.md"

  run "$BATS_TEST_DIRNAME/../git-pr" --template pull_request_template.md

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: --editor/--template are only supported when creating a PR."* ]]
  assert_no_git_push
}

@test "existing PR create-only template option is rejected before template lookup" {
  export GIT_PR_FAKE_PR_NUMBER=123

  run "$BATS_TEST_DIRNAME/../git-pr" --template missing-template.md

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: --editor/--template are only supported when creating a PR."* ]]
  [[ "$output" != *"Template file not found"* ]]
  assert_no_git_push
}

@test "existing PR with non-empty body keeps body unless fill is explicit" {
  export GIT_PR_FAKE_PR_NUMBER=123
  export GIT_PR_FAKE_PR_BODY="Already written"

  run "$BATS_TEST_DIRNAME/../git-pr"

  [ "$status" -eq 0 ]
  assert_log_contains "push -u origin HEAD"
  assert_log_not_contains "gh pr edit 123 --body"
}

@test "existing PR with empty body is auto-filled" {
  export GIT_PR_FAKE_PR_NUMBER=123
  export GIT_PR_FAKE_PR_BODY=""

  run "$BATS_TEST_DIRNAME/../git-pr"

  [ "$status" -eq 0 ]
  assert_log_contains "gh pr edit 123 --repo example/repo --body"
}

@test "existing PR explicit base retargets the PR" {
  export GIT_PR_FAKE_PR_NUMBER=123

  run "$BATS_TEST_DIRNAME/../git-pr" --no-edit --base develop

  [ "$status" -eq 0 ]
  assert_log_contains "gh pr edit 123 --repo example/repo --base develop"
  [[ "$output" == *"INFO: Updated PR #123: base."* ]]
}

@test "web option creates through CLI then opens the created PR" {
  run "$BATS_TEST_DIRNAME/../git-pr" --web

  [ "$status" -eq 0 ]
  assert_log_contains "gh pr create --repo example/repo --base main --head feature --fill"
  assert_log_not_contains "gh pr create --repo example/repo --base main --head feature --web"
  assert_log_contains "gh pr view 1 --repo example/repo --web"
}

@test "copilot mode uses PR triple-dot diff and scripted copilot flags" {
  create_fake_copilot

  run "$BATS_TEST_DIRNAME/../git-pr" copilot

  [ "$status" -eq 0 ]
  assert_log_contains "git -C $GIT_PR_FAKE_REPO_ROOT diff --quiet origin/main...HEAD -- ."
  assert_log_contains "copilot -s --no-custom-instructions -p @"
  assert_log_contains "gh pr create --repo example/repo --base main --head feature --title Generated\\ title --body Generated\\ body"
}

@test "copilot update failure preserves existing PR body" {
  create_fake_copilot
  export GIT_PR_FAKE_COPILOT_FAIL=true
  export GIT_PR_FAKE_PR_NUMBER=123
  export GIT_PR_FAKE_PR_BODY="Already written"

  run "$BATS_TEST_DIRNAME/../git-pr" copilot --mode=update

  [ "$status" -eq 0 ]
  assert_log_not_contains "gh pr edit 123 --body"
}

@test "copilot update without copilot does not fetch base" {
  local tool_bin="$BATS_TEST_TMPDIR/no-copilot-bin"
  mkdir -p "$tool_bin"
  ln -sf "$(command -v bash)" "$tool_bin/bash"
  ln -sf "$(command -v grep)" "$tool_bin/grep"
  ln -sf "$(command -v cat)" "$tool_bin/cat"
  ln -sf "$(command -v rm)" "$tool_bin/rm"
  export PATH="$GIT_PR_FAKE_BIN:$BATS_TEST_DIRNAME/..:$tool_bin"
  export GIT_PR_FAKE_PR_NUMBER=123
  export GIT_PR_FAKE_PR_BODY="Already written"

  run "$BATS_TEST_DIRNAME/../git-pr" copilot --mode=update

  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: Copilot CLI not found; falling back."* ]]
  assert_log_not_contains "git -C $GIT_PR_FAKE_REPO_ROOT fetch origin"
  assert_log_not_contains "gh pr edit 123 --body"
}
