#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
# Bats runs each @test in its own process; per-test fake environment exports
# are intentionally scoped to the current test.

load test_helper

setup() {
  setup_fake_cli_env
  GIT_PR="$BATS_TEST_DIRNAME/../git-pr"
}

@test "existing PR explicit title update does not touch body" {
  export GIT_PR_FAKE_PR_NUMBER=123
  export GIT_PR_FAKE_PR_BODY="Already written"

  run "$GIT_PR" --title "Updated title"

  [ "$status" -eq 0 ]
  assert_log_line_contains_all "gh pr edit 123" "--repo example/repo" "--title Updated\\ title"
  assert_log_line_not_contains "gh pr edit 123" "--body"
  [ "$(cat "$GIT_PR_FAKE_LOG.pr-edit-title")" = "Updated title" ]
  [ ! -e "$GIT_PR_FAKE_LOG.pr-edit-body" ]
}

@test "existing PR accepts stdin body-file marker" {
  export GIT_PR_FAKE_PR_NUMBER=123

  run "$GIT_PR" --body-file -

  [ "$status" -eq 0 ]
  assert_log_line_contains_all "gh pr edit 123" "--repo example/repo" "--body-file -"
  [ "$(cat "$GIT_PR_FAKE_LOG.pr-edit-body-file")" = "-" ]
}

@test "existing PR explicit empty body clears body" {
  export GIT_PR_FAKE_PR_NUMBER=123
  export GIT_PR_FAKE_PR_BODY="Already written"

  run "$GIT_PR" --body ""

  [ "$status" -eq 0 ]
  assert_log_line_contains_all "gh pr edit 123" "--repo example/repo" "--body ''"
  [ -e "$GIT_PR_FAKE_LOG.pr-edit-body" ]
  [ "$(cat "$GIT_PR_FAKE_LOG.pr-edit-body")" = "" ]
}

@test "existing PR create-only draft option fails before push" {
  export GIT_PR_FAKE_PR_NUMBER=123

  run "$GIT_PR" --draft

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: --draft is only supported when creating a PR."* ]]
  assert_no_git_push
  assert_log_not_contains "gh pr edit"
}

@test "existing PR no-edit can retarget base and update metadata together" {
  export GIT_PR_FAKE_PR_NUMBER=123

  run "$GIT_PR" --no-edit --base release --label bug --reviewer alice --assignee bob

  [ "$status" -eq 0 ]
  assert_log_line_contains_all "gh pr edit 123" \
    "--repo example/repo" \
    "--base release" \
    "--add-label bug" \
    "--add-reviewer alice" \
    "--add-assignee bob"
  assert_log_line_not_contains "gh pr edit 123" "--title"
  assert_log_line_not_contains "gh pr edit 123" "--body"
  assert_log_line_not_contains "gh pr edit 123" "--body-file"
  [ "$(cat "$GIT_PR_FAKE_LOG.pr-edit-base")" = "release" ]
}
