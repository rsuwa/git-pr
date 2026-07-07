#!/usr/bin/env bats

load test_helper

setup() {
  setup_fake_cli_env
}

path_without_host_optional_tools() {
  local tool_bin="$BATS_TEST_TMPDIR/no-host-tools"
  mkdir -p "$tool_bin"
  ln -sf /bin/bash "$tool_bin/bash"
  printf '%s:%s' "$GIT_PR_FAKE_BIN" "$tool_bin"
}

@test "doctor succeeds when required dependencies and gh auth are ready" {
  run env PATH="$(path_without_host_optional_tools)" "$BATS_TEST_DIRNAME/../git-pr" doctor

  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO: git: found"* ]]
  [[ "$output" == *"INFO: GitHub CLI: found"* ]]
  [[ "$output" == *"INFO: GitHub CLI auth: ok (github.com)"* ]]
  [[ "$output" == *"INFO: Copilot CLI: not found (optional; needed only for 'git pr copilot')."* ]]
  [[ "$output" == *"INFO: Doctor checks passed."* ]]
  assert_log_contains "gh auth status --hostname github.com"
  assert_no_git_push
  assert_no_command_logged "copilot"
}

@test "doctor uses GitHub Enterprise host from origin for auth check" {
  run env \
    GIT_PR_FAKE_ORIGIN_URL="git@ghe.example.com:octo/repo.git" \
    GIT_PR_FAKE_REPO="ghe.example.com/octo/repo" \
    GIT_PR_FAKE_EXPECT_AUTH_HOST="ghe.example.com" \
    "$BATS_TEST_DIRNAME/../git-pr" doctor

  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO: GitHub CLI auth: ok (ghe.example.com)"* ]]
  assert_log_contains "gh auth status --hostname ghe.example.com"
  assert_no_git_push
}

@test "doctor falls back to github.com when not run inside a git repository" {
  run env GIT_PR_FAKE_IS_REPO=false "$BATS_TEST_DIRNAME/../git-pr" doctor

  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO: No git repository found; checking GitHub CLI auth for github.com."* ]]
  [[ "$output" == *"INFO: GitHub CLI auth: ok (github.com)"* ]]
  assert_log_contains "gh auth status --hostname github.com"
  assert_no_git_push
}

@test "doctor fails with auth setup instructions when gh is not authenticated" {
  run env GIT_PR_FAKE_GH_AUTH=false "$BATS_TEST_DIRNAME/../git-pr" doctor

  [ "$status" -ne 0 ]
  [[ "$output" == *"WARN: GitHub CLI auth: failed (github.com)."* ]]
  [[ "$output" == *"Run: gh auth login --hostname github.com."* ]]
  [[ "$output" == *"Check with: gh auth status --hostname github.com."* ]]
  assert_log_contains "gh auth status --hostname github.com"
  assert_no_git_push
}

@test "doctor reports missing gh without running auth check" {
  rm -f "$GIT_PR_FAKE_BIN/gh"

  run env PATH="$(path_without_host_optional_tools)" "$BATS_TEST_DIRNAME/../git-pr" doctor

  [ "$status" -ne 0 ]
  [[ "$output" == *"WARN: GitHub CLI: missing"* ]]
  [[ "$output" == *"GitHub CLI setup: install gh from https://github.com/cli/cli#installation"* ]]
  assert_log_not_contains "gh auth status"
  assert_no_git_push
}

@test "doctor reports missing git without probing the repository" {
  rm -f "$GIT_PR_FAKE_BIN/git"

  run env PATH="$(path_without_host_optional_tools)" "$BATS_TEST_DIRNAME/../git-pr" doctor

  [ "$status" -ne 0 ]
  [[ "$output" == *"WARN: git: missing"* ]]
  [[ "$output" == *"INFO: GitHub CLI auth: ok (github.com)"* ]]
  assert_log_contains "gh auth status --hostname github.com"
  assert_no_git_push
}

@test "doctor --with-copilot requires the optional copilot CLI" {
  run env PATH="$(path_without_host_optional_tools)" "$BATS_TEST_DIRNAME/../git-pr" doctor --with-copilot

  [ "$status" -ne 0 ]
  [[ "$output" == *"WARN: Copilot CLI: missing. Install GitHub Copilot CLI:"* ]]
  assert_log_contains "gh auth status --hostname github.com"
  assert_no_git_push
}

@test "doctor --with-copilot succeeds when copilot is on PATH without invoking it" {
  create_fake_copilot

  run "$BATS_TEST_DIRNAME/../git-pr" doctor --with-copilot

  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO: Copilot CLI: found on PATH"* ]]
  [[ "$output" == *"INFO: Doctor checks passed."* ]]
  assert_no_command_logged "copilot"
  assert_no_git_push
}

@test "doctor rejects pull request options" {
  run "$BATS_TEST_DIRNAME/../git-pr" doctor --base main

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: doctor subcommand only accepts --with-copilot."* ]]
  assert_log_not_contains "gh auth status"
  assert_no_git_push
}

@test "doctor rejects unsafe origin hosts before printing auth guidance" {
  run env \
    GIT_PR_FAKE_ORIGIN_URL="https://github.com;echo-pwn/example/repo.git" \
    GIT_PR_FAKE_GH_AUTH=false \
    "$BATS_TEST_DIRNAME/../git-pr" doctor

  [ "$status" -ne 0 ]
  [[ "$output" == *"WARN: Remote 'origin' is not a supported GitHub repository URL: https://github.com;echo-pwn/example/repo.git"* ]]
  [[ "$output" == *"Run: gh auth login --hostname github.com."* ]]
  [[ "$output" != *"gh auth login --hostname github.com;echo-pwn"* ]]
  assert_log_contains "gh auth status --hostname github.com"
  assert_no_git_push
}

@test "--with-copilot is only accepted by doctor" {
  run "$BATS_TEST_DIRNAME/../git-pr" --with-copilot

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: --with-copilot requires 'git pr doctor'."* ]]
  assert_log_not_contains "gh auth status"
  assert_no_git_push
}

@test "regular PR flow reports GitHub CLI setup when gh is missing" {
  rm -f "$GIT_PR_FAKE_BIN/gh"

  run env PATH="$(path_without_host_optional_tools)" "$BATS_TEST_DIRNAME/../git-pr"

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: Missing command: gh. Install GitHub CLI: https://github.com/cli/cli#installation. Then run: gh auth login"* ]]
  assert_log_not_contains "gh auth status"
  assert_no_git_push
}
