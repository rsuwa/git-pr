#!/usr/bin/env bats

load test_helper

setup() {
  setup_fake_cli_env
}

@test "create pushes current branch and creates a filled pull request" {
  run "$BATS_TEST_DIRNAME/../git-pr" --label bug,backend --reviewer alice,bob --assignee alice

  [ "$status" -eq 0 ]
  assert_log_contains "git push -u origin HEAD"
  assert_log_contains "gh pr create --base main --head feature --label bug --label backend --reviewer alice --reviewer bob --assignee alice --fill"
}

@test "existing PR with --no-edit can still update metadata" {
  export GIT_PR_FAKE_PR_NUMBER=123

  run "$BATS_TEST_DIRNAME/../git-pr" --no-edit --label bug --reviewer alice --assignee bob

  [ "$status" -eq 0 ]
  assert_log_contains "gh pr edit 123 --add-label bug --add-reviewer alice --add-assignee bob"
}

@test "auto-merge subcommand assembles merge flags" {
  export GIT_PR_FAKE_PR_NUMBER=123

  run "$BATS_TEST_DIRNAME/../git-pr" auto-merge --merge-method squash --delete-branch --admin --match-head-commit abc123

  [ "$status" -eq 0 ]
  assert_log_contains "gh pr merge --auto --squash 123 --delete-branch --admin --match-head-commit abc123"
}
