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
