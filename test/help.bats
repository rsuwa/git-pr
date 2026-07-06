#!/usr/bin/env bats

setup() {
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
}

@test "git-pr prints help" {
  run "$BATS_TEST_DIRNAME/../git-pr" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: git pr"* ]]
}

@test "git invokes git-pr as a subcommand" {
  run git pr -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: git pr"* ]]
}

@test "git-pr prints version without requiring git or gh" {
  run env PATH="/usr/bin:/bin" "$BATS_TEST_DIRNAME/../git-pr" --version
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^git-pr\ [0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "help documents CLI contract flags" {
  run "$BATS_TEST_DIRNAME/../git-pr" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--version"* ]]
  [[ "$output" == *"--no-fill"* ]]
  [[ "$output" == *"--admin"* ]]
  [[ "$output" == *"--match-head-commit"* ]]
  [[ "$output" == *"--disable-auto-merge"* ]]
  [[ "$output" == *"--copilot                (deprecated)"* ]]
  [[ "$output" == *"--copilot-verbose        (deprecated)"* ]]
  [[ "$output" == *"--copilot-update         (deprecated)"* ]]
  [[ "$output" == *"--auto-merge             (deprecated)"* ]]
}
