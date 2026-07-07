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
  [[ "$output" == *"--with-copilot"* ]]
  [[ "$output" == *"git pr merge [options]"* ]]
  [[ "$output" == *"git pr doctor [--with-copilot]"* ]]
  [[ "$output" == *"Pushes the current branch, then creates or updates a GitHub pull request."* ]]
  [[ "$output" == *"--body-file <path|->"* ]]
  [[ "$output" == *"--no-edit                Do not edit existing PR title/body; metadata/base may update"* ]]
  [[ "$output" == *"--fill                   Create: gh fill; existing PR: replace body from commits"* ]]
  [[ "$output" == *"--admin                  Rejected; use gh directly to bypass requirements"* ]]
  [[ "$output" != *"--copilot"* ]]
  [[ "$output" != *"--copilot-verbose"* ]]
  [[ "$output" != *"--copilot-update"* ]]
  [[ "$output" != *"--auto-merge"* ]]
  [[ "$output" != *"(deprecated)"* ]]
}
