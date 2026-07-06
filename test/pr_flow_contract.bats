#!/usr/bin/env bats

load test_helper

setup() {
  setup_fake_cli_env
  GIT_PR="$BATS_TEST_DIRNAME/../git-pr"
}

@test "explicit base is used without default branch discovery" {
  run "$GIT_PR" --base develop

  [ "$status" -eq 0 ]
  assert_log_not_contains "branch.feature.gh-merge-base"
  assert_log_not_contains "gh repo view"
  assert_log_line_contains_all "gh pr create" "--repo example/repo" "--base develop" "--head feature" "--fill"
}

@test "branch gh-merge-base config wins over repo default" {
  export GIT_PR_FAKE_MERGE_BASE=integration

  run "$GIT_PR"

  [ "$status" -eq 0 ]
  assert_log_contains "git -C $GIT_PR_FAKE_REPO_ROOT config --get branch.feature.gh-merge-base"
  assert_log_not_contains "gh repo view"
  assert_log_line_contains_all "gh pr create" "--repo example/repo" "--base integration" "--head feature" "--fill"
}

@test "repo default branch is used when no branch merge base is configured" {
  export GIT_PR_FAKE_DEFAULT_BRANCH=trunk

  run "$GIT_PR"

  [ "$status" -eq 0 ]
  assert_log_contains "gh repo view --repo example/repo --json defaultBranchRef --jq .defaultBranchRef.name"
  assert_log_line_contains_all "gh pr create" "--repo example/repo" "--base trunk" "--head feature" "--fill"
}

@test "origin HEAD is used when repo default branch lookup fails" {
  export GIT_PR_FAKE_DEFAULT_BRANCH=stable
  export GIT_PR_FAKE_REPO_VIEW_FAIL=true

  run "$GIT_PR"

  [ "$status" -eq 0 ]
  assert_log_contains "gh repo view --repo example/repo --json defaultBranchRef --jq .defaultBranchRef.name"
  assert_log_contains "git -C $GIT_PR_FAKE_REPO_ROOT symbolic-ref -q --short refs/remotes/origin/HEAD"
  assert_log_line_contains_all "gh pr create" "--repo example/repo" "--base stable" "--head feature" "--fill"
}

@test "missing base fails before pushing" {
  export GIT_PR_FAKE_REPO_VIEW_FAIL=true
  export GIT_PR_FAKE_HAS_ORIGIN_HEAD=false

  run "$GIT_PR"

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: Base branch not specified and default branch could not be determined."* ]]
  assert_no_git_push
  assert_log_not_contains "gh pr create"
}

@test "create with --fill-first passes through fill-first mode" {
  run "$GIT_PR" --fill-first

  [ "$status" -eq 0 ]
  assert_log_line_contains_all "gh pr create" "--repo example/repo" "--base main" "--head feature" "--fill-first"
}

@test "create with --fill-verbose passes through fill-verbose mode" {
  run "$GIT_PR" --fill-verbose

  [ "$status" -eq 0 ]
  assert_log_line_contains_all "gh pr create" "--repo example/repo" "--base main" "--head feature" "--fill-verbose"
}

@test "create with --no-fill generates explicit title and body" {
  run "$GIT_PR" --no-fill

  [ "$status" -eq 0 ]
  assert_log_line_contains_all "gh pr create" "--repo example/repo" "--base main" "--head feature" "--title Test\\ title" "--body -\\ Test\\ commit"
  assert_log_not_contains " --fill"
}

@test "create with explicit title and body disables fill" {
  run "$GIT_PR" --title "Manual title" --body "Manual body"

  [ "$status" -eq 0 ]
  assert_log_line_contains_all "gh pr create" "--repo example/repo" "--base main" "--head feature" "--title Manual\\ title" "--body Manual\\ body"
  assert_log_not_contains " --fill"
}

@test "create with explicit body file passes body-file to gh" {
  local body_file="$BATS_TEST_TMPDIR/body.md"
  printf 'Body from file\n' > "$body_file"

  run "$GIT_PR" --title "File title" --body-file "$body_file"

  [ "$status" -eq 0 ]
  assert_log_line_contains_all "gh pr create" "--repo example/repo" "--base main" "--head feature" "--title File\\ title" "--body-file $body_file"
  assert_log_not_contains " --fill"
}

@test "create with stdin body file passes dash to gh" {
  run "$GIT_PR" --title "Stdin title" --body-file -

  [ "$status" -eq 0 ]
  assert_log_line_contains_all "gh pr create" "--repo example/repo" "--base main" "--head feature" "--title Stdin\\ title" "--body-file -"
  assert_log_not_contains " --fill"
}

@test "create with template resolves the template and derives a title" {
  printf 'template body\n' > "$GIT_PR_FAKE_REPO_ROOT/pull_request_template.md"

  run "$GIT_PR" --template pull_request_template.md

  [ "$status" -eq 0 ]
  assert_log_line_contains_all "gh pr create" "--repo example/repo" "--base main" "--head feature" "--title Test\\ title" "--template $GIT_PR_FAKE_REPO_ROOT/pull_request_template.md"
  assert_log_not_contains " --fill"
}

@test "create with editor and draft passes both flags before fill" {
  run "$GIT_PR" --editor --draft

  [ "$status" -eq 0 ]
  assert_log_line_contains_all "gh pr create" "--repo example/repo" "--base main" "--head feature" "--draft" "--editor" "--fill"
}

@test "create with web opens the created PR after creation" {
  run "$GIT_PR" --web

  [ "$status" -eq 0 ]
  assert_log_line_contains_all "gh pr create" "--repo example/repo" "--base main" "--head feature" "--fill"
  assert_log_line_not_contains "gh pr create" "--web"
  assert_log_contains "gh pr view 1 --repo example/repo --web"
  assert_log_order "gh pr create --repo example/repo --base main --head feature --fill" "gh pr view 1 --repo example/repo --web"
}

@test "create pushes before gh pr create when upstream is missing" {
  run "$GIT_PR"

  [ "$status" -eq 0 ]
  assert_log_contains "git -C $GIT_PR_FAKE_REPO_ROOT push -u origin HEAD"
  assert_log_order "git -C $GIT_PR_FAKE_REPO_ROOT push -u origin HEAD" "gh pr create"
}

@test "existing PR updates explicit title and body after push" {
  export GIT_PR_FAKE_PR_NUMBER=123

  run "$GIT_PR" --title "Updated title" --body "Updated body"

  [ "$status" -eq 0 ]
  assert_log_line_contains_all "gh pr edit 123" "--repo example/repo" "--title Updated\\ title" "--body Updated\\ body"
  assert_log_order "git -C $GIT_PR_FAKE_REPO_ROOT push -u origin HEAD" "gh pr edit 123"
}

@test "existing PR updates body file only" {
  local body_file="$BATS_TEST_TMPDIR/update-body.md"
  export GIT_PR_FAKE_PR_NUMBER=123
  printf 'Updated body from file\n' > "$body_file"

  run "$GIT_PR" --body-file "$body_file"

  [ "$status" -eq 0 ]
  assert_log_line_contains_all "gh pr edit 123" "--repo example/repo" "--body-file $body_file"
}

@test "existing PR explicit fill replaces a non-empty body" {
  export GIT_PR_FAKE_PR_NUMBER=123
  export GIT_PR_FAKE_PR_BODY="Already written"

  run "$GIT_PR" --fill

  [ "$status" -eq 0 ]
  assert_log_line_contains_all "gh pr edit 123" "--repo example/repo" "--body -\\ Test\\ commit"
}

@test "existing PR explicit no-fill leaves title and body unchanged" {
  export GIT_PR_FAKE_PR_NUMBER=123

  run "$GIT_PR" --no-fill

  [ "$status" -eq 0 ]
  assert_log_contains "git -C $GIT_PR_FAKE_REPO_ROOT push -u origin HEAD"
  assert_log_not_contains "gh pr edit"
  [[ "$output" == *"INFO: No PR fields to update."* ]]
}

@test "dirty worktree emits warning and still pushes before create" {
  export GIT_PR_FAKE_WORKTREE_DIRTY=true

  run "$GIT_PR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: Working tree has uncommitted changes. They won't be included in the PR."* ]]
  assert_log_contains "git -C $GIT_PR_FAKE_REPO_ROOT push -u origin HEAD"
  assert_log_order "git -C $GIT_PR_FAKE_REPO_ROOT push -u origin HEAD" "gh pr create"
}

@test "existing upstream uses plain git push" {
  export GIT_PR_FAKE_HAS_UPSTREAM=true

  run "$GIT_PR"

  [ "$status" -eq 0 ]
  assert_log_contains "git -C $GIT_PR_FAKE_REPO_ROOT push"
  assert_log_not_contains "push -u origin HEAD"
  assert_log_order "git -C $GIT_PR_FAKE_REPO_ROOT push" "gh pr create"
}
