#!/usr/bin/env bats

load test_helper

setup() {
  setup_fake_cli_env
}

run_git_pr_expect_error() {
  local expected="$1"
  shift

  : > "$GIT_PR_FAKE_LOG"
  run "$BATS_TEST_DIRNAME/../git-pr" "$@"

  [ "$status" -ne 0 ] || {
    printf 'Expected failure for: git-pr' >&2
    printf ' %q' "$@" >&2
    printf '\nOutput:\n%s\n' "$output" >&2
    return 1
  }

  [[ "$output" == *"ERROR: $expected"* ]] || {
    printf 'Expected error for: git-pr' >&2
    printf ' %q' "$@" >&2
    printf '\nExpected: ERROR: %s\nOutput:\n%s\n' "$expected" "$output" >&2
    return 1
  }

  assert_no_git_push
  assert_log_not_contains "gh pr create"
  assert_log_not_contains "gh pr edit"
  assert_log_not_contains "gh pr merge"
}

@test "missing values for value-taking options fail before push" {
  local option
  local -a options=(
    -b
    --base
    -t
    --title
    -d
    --body
    -F
    --body-file
    -T
    --template
    --label
    --reviewer
    --assignee
    --mode
    --detail
    --language
    --diff-exclude
    -m
    --merge-method
    --match-head-commit
  )

  for option in "${options[@]}"; do
    run_git_pr_expect_error "$option requires a value." "$option"
  done
}

@test "empty values for non-body value options fail before push" {
  run_git_pr_expect_error "--base requires a non-empty value." --base ""
  run_git_pr_expect_error "--title requires a non-empty value." --title ""
  run_git_pr_expect_error "--body-file requires a non-empty value." --body-file ""
  run_git_pr_expect_error "--template requires a non-empty value." --template ""
  run_git_pr_expect_error "--label requires a non-empty value." --label ""
  run_git_pr_expect_error "--reviewer requires a non-empty value." --reviewer ""
  run_git_pr_expect_error "--assignee requires a non-empty value." --assignee ""
  run_git_pr_expect_error "--mode requires a non-empty value." copilot --mode ""
  run_git_pr_expect_error "--detail requires a non-empty value." copilot --detail ""
  run_git_pr_expect_error "--language requires a non-empty value." copilot --language ""
  run_git_pr_expect_error "--diff-exclude requires a non-empty value." copilot --diff-exclude ""
  run_git_pr_expect_error "--merge-method requires a non-empty value." --merge-method ""
}

@test "unknown argument fails before push" {
  run_git_pr_expect_error "Unknown argument: --definitely-unknown" --definitely-unknown
}

@test "body and body-file cannot be combined" {
  run_git_pr_expect_error "--body and --body-file cannot be used together." \
    --body "Manual body" \
    --body-file "$BATS_TEST_TMPDIR/body.md"

  run_git_pr_expect_error "--body and --body-file cannot be used together." \
    --body "" \
    --body-file "$BATS_TEST_TMPDIR/body.md"
}

@test "fill modes cannot be combined" {
  local -a args
  local case_data
  local -a cases=(
    "--fill --fill-first"
    "--fill --fill-verbose"
    "--fill-first --fill"
    "--fill-first --fill-verbose"
    "--fill-verbose --fill"
    "--fill-verbose --fill-first"
  )

  for case_data in "${cases[@]}"; do
    read -r -a args <<< "$case_data"
    run_git_pr_expect_error "Choose only one of --fill, --fill-first, --fill-verbose." "${args[@]}"
  done
}

@test "no-fill cannot be combined with fill modes" {
  local -a args
  local case_data
  local -a cases=(
    "--no-fill --fill"
    "--fill --no-fill"
    "--no-fill --fill-first"
    "--fill-verbose --no-fill"
  )

  for case_data in "${cases[@]}"; do
    read -r -a args <<< "$case_data"
    run_git_pr_expect_error "--no-fill cannot be combined with --fill/--fill-first/--fill-verbose." "${args[@]}"
  done
}

@test "copilot cannot be combined with manual content" {
  run_git_pr_expect_error "--copilot cannot be combined with --title/--body/--body-file." \
    copilot --title "Manual title"

  run_git_pr_expect_error "--copilot cannot be combined with --title/--body/--body-file." \
    copilot --body "Manual body"

  run_git_pr_expect_error "--copilot cannot be combined with --title/--body/--body-file." \
    copilot --body-file "$BATS_TEST_TMPDIR/body.md"
}

@test "copilot cannot be combined with fill controls" {
  run_git_pr_expect_error "--copilot cannot be combined with --fill/--no-fill." copilot --fill
  run_git_pr_expect_error "--copilot cannot be combined with --fill/--no-fill." copilot --no-fill
}

@test "no-edit cannot be combined with content-changing options" {
  run_git_pr_expect_error "--no-edit cannot be combined with options that modify the PR body/title." \
    --no-edit --title "Manual title"

  run_git_pr_expect_error "--no-edit cannot be combined with options that modify the PR body/title." \
    --no-edit --body "Manual body"

  run_git_pr_expect_error "--no-edit cannot be combined with options that modify the PR body/title." \
    --no-edit --body-file "$BATS_TEST_TMPDIR/body.md"

  run_git_pr_expect_error "--no-edit cannot be combined with options that modify the PR body/title." \
    --no-edit --fill

  run_git_pr_expect_error "--no-edit cannot be combined with options that modify the PR body/title." \
    --no-edit --no-fill

  run_git_pr_expect_error "--no-edit cannot be combined with options that modify the PR body/title." \
    copilot --no-edit
}

@test "no-edit cannot be combined with editor or template" {
  run_git_pr_expect_error "--no-edit cannot be combined with --editor/--template." --no-edit --editor
  run_git_pr_expect_error "--no-edit cannot be combined with --editor/--template." \
    --no-edit --template pull_request_template.md
}

@test "invalid merge method is rejected" {
  run_git_pr_expect_error "Invalid merge method: fast-forward (use merge|squash|rebase)" \
    auto-merge --merge-method fast-forward
}

@test "merge method requires auto-merge context" {
  run_git_pr_expect_error "Auto-merge options require --enable-auto-merge or 'git pr auto-merge'." \
    --merge-method squash
}

@test "admin is rejected for git-pr auto-merge" {
  run_git_pr_expect_error "--admin cannot be used with git-pr auto-merge" \
    auto-merge --admin
  run_git_pr_expect_error "--admin cannot be used with git-pr auto-merge" \
    --enable-auto-merge --admin
}

@test "invalid copilot mode and detail are rejected" {
  run_git_pr_expect_error "Invalid --mode: rewrite (use create|update|auto)" \
    copilot --mode rewrite

  run_git_pr_expect_error "Invalid --detail: noisy (use normal|verbose)" \
    copilot --detail noisy
}

@test "auto-merge subcommand rejects non-auto-merge options" {
  local -a args
  local case_data
  local -a cases=(
    "--base main"
    "--draft"
    "--web"
    "--copilot"
    "--title Manual-title"
    "--body Manual-body"
    "--body-file $BATS_TEST_TMPDIR/body.md"
    "--template pull_request_template.md"
    "--editor"
    "--label bug"
    "--reviewer alice"
    "--assignee bob"
    "--fill"
    "--fill-first"
    "--fill-verbose"
    "--no-fill"
    "--no-edit"
  )

  for case_data in "${cases[@]}"; do
    read -r -a args <<< "$case_data"
    run_git_pr_expect_error "auto-merge subcommand only accepts auto-merge options." auto-merge "${args[@]}"
  done
}

@test "update subcommand rejects unrelated options" {
  local -a args
  local case_data
  local -a cases=(
    "--base main"
    "--disable-auto-merge"
    "--language ja"
    "--label bug"
    "--fill"
    "--template="
    "--match-head-commit="
  )

  for case_data in "${cases[@]}"; do
    read -r -a args <<< "$case_data"
    run_git_pr_expect_error "update subcommand does not accept PR options." update "${args[@]}"
  done
}

@test "update subcommand rejects empty-valued PR options" {
  run_git_pr_expect_error "update subcommand does not accept PR options." update --title ""
  run_git_pr_expect_error "update subcommand does not accept PR options." update --body ""
  run_git_pr_expect_error "update subcommand does not accept PR options." update --body-file ""
  run_git_pr_expect_error "update subcommand does not accept PR options." update --label ""
  run_git_pr_expect_error "update subcommand does not accept PR options." update --reviewer ""
  run_git_pr_expect_error "update subcommand does not accept PR options." update --assignee ""
}
