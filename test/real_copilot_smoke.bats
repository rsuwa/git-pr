#!/usr/bin/env bats

setup() {
  if [ "${GIT_PR_RUN_REAL_COPILOT_SMOKE:-}" != "1" ]; then
    skip "set GIT_PR_RUN_REAL_COPILOT_SMOKE=1 to run the real Copilot CLI smoke test"
  fi

  if ! command -v copilot >/dev/null 2>&1; then
    skip "copilot CLI is not available"
  fi
}

@test "real Copilot CLI accepts the noninteractive prompt contract" {
  cd "$BATS_TEST_TMPDIR" || return

  if ! command -v timeout >/dev/null 2>&1; then
    skip "timeout command is not available"
  fi

  prompt_file="$BATS_TEST_TMPDIR/copilot-smoke-prompt.txt"
  sentinel="GIT_PR_REAL_COPILOT_SMOKE_OK"
  printf 'Reply with exactly this token and no extra text: %s\n' "$sentinel" > "$prompt_file"

  run timeout "${GIT_PR_REAL_COPILOT_SMOKE_TIMEOUT:-30s}" copilot \
    -s \
    --no-custom-instructions \
    --stream off \
    -p "@$prompt_file"

  [ "$status" -eq 0 ]
  [[ "$output" == *"$sentinel"* ]]
}
