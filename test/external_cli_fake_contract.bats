#!/usr/bin/env bats

load test_helper

setup() {
  setup_fake_cli_env
}

@test "fake gh rejects unsupported pr create options" {
  run gh pr create --repo example/repo --base main --head feature --fill --bogus

  [ "$status" -ne 0 ]
  [[ "$output" == *"fake gh: unsupported option for pr create: --bogus"* ]]
}

@test "fake gh rejects unsupported pr edit options" {
  run gh pr edit 123 --repo example/repo --title "Updated title" --bogus

  [ "$status" -ne 0 ]
  [[ "$output" == *"fake gh: unsupported option for pr edit: --bogus"* ]]
}

@test "fake gh rejects unsupported pr merge options" {
  run gh pr merge 123 --repo example/repo --squash --match-head-commit local-head --bogus

  [ "$status" -ne 0 ]
  [[ "$output" == *"fake gh: unsupported option for pr merge: --bogus"* ]]
}

@test "fake gh rejects admin merge bypass" {
  run gh pr merge 123 --repo example/repo --admin

  [ "$status" -ne 0 ]
  [[ "$output" == *"fake gh: unsupported option for pr merge: --admin"* ]]
}

@test "fake copilot rejects unsupported options" {
  create_fake_copilot
  prompt_file="$BATS_TEST_TMPDIR/prompt.txt"
  printf 'prompt\n' > "$prompt_file"

  run copilot -s --no-custom-instructions -p "@$prompt_file" --stream off

  [ "$status" -ne 0 ]
  [[ "$output" == *"fake copilot: unsupported option: --stream"* ]]
}

@test "fake copilot requires prompt file reference" {
  create_fake_copilot

  run copilot -s --no-custom-instructions -p "plain prompt"

  [ "$status" -ne 0 ]
  [[ "$output" == *"fake copilot: prompt must be @file"* ]]
}
