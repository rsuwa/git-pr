#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
# Bats runs each @test in its own process; per-test fake environment exports
# are intentionally scoped to the current test.

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

@test "credentialed HTTPS origin normalizes repository owner and name" {
  export GIT_PR_FAKE_ORIGIN_URL="https://token@github.com/example/repo.git"

  run "$GIT_PR"

  [ "$status" -eq 0 ]
  assert_log_line_contains_all "gh pr create" "--repo example/repo" "--base main" "--head feature" "--fill"
  assert_log_not_contains "token@github.com"
}

@test "credentialed HTTPS origin strips query and fragment before repo use" {
  export GIT_PR_FAKE_ORIGIN_URL="https://user:secret@github.com/example/repo.git?token=abc#frag"

  run "$GIT_PR"

  [ "$status" -eq 0 ]
  assert_log_line_contains_all "gh pr create" "--repo example/repo" "--base main" "--head feature" "--fill"
  assert_log_not_contains "secret"
  assert_log_not_contains "token=abc"
}

@test "unsupported credentialed HTTPS origin redacts credentials and query" {
  export GIT_PR_FAKE_ORIGIN_URL="https://user:secret@example.invalid/org/repo/extra.git?token=abc#frag"

  run "$GIT_PR"

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: Remote 'origin' is not a supported GitHub repository URL: https://REDACTED@example.invalid/org/repo/extra.git?REDACTED"* ]]
  [[ "$output" != *"secret"* ]]
  [[ "$output" != *"token=abc"* ]]
  assert_no_git_push
  assert_log_not_contains "gh pr create"
}

@test "unsafe origin owner is rejected before jq filter or push" {
  export GIT_PR_FAKE_ORIGIN_URL='https://github.com/bad"owner/repo.git'

  run "$GIT_PR"

  [ "$status" -ne 0 ]
  [[ "$output" == *'ERROR: Remote '\''origin'\'' is not a supported GitHub repository URL: https://github.com/bad"owner/repo.git'* ]]
  assert_no_git_push
  assert_log_not_contains "gh pr list"
  assert_log_not_contains "gh pr create"
}

@test "unsafe origin repository name is rejected before jq filter or push" {
  export GIT_PR_FAKE_ORIGIN_URL='https://github.com/example/repo\name.git'

  run "$GIT_PR"

  [ "$status" -ne 0 ]
  [[ "$output" == *'ERROR: Remote '\''origin'\'' is not a supported GitHub repository URL: https://github.com/example/repo\name.git'* ]]
  assert_no_git_push
  assert_log_not_contains "gh pr list"
  assert_log_not_contains "gh pr create"
}

@test "unsafe HTTPS origin host is rejected before auth guidance or push" {
  export GIT_PR_FAKE_ORIGIN_URL="https://github.com;echo-pwn/example/repo.git"

  run "$GIT_PR"

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: Remote 'origin' is not a supported GitHub repository URL: https://github.com;echo-pwn/example/repo.git"* ]]
  [[ "$output" != *"gh auth login --hostname github.com;echo-pwn"* ]]
  assert_no_git_push
  assert_log_not_contains "gh auth status"
  assert_log_not_contains "gh pr create"
}

@test "GitHub Enterprise origin uses hostname for auth and repo" {
  export GIT_PR_FAKE_ORIGIN_URL="git@ghe.example.com:octo/repo.git"
  export GIT_PR_FAKE_REPO="ghe.example.com/octo/repo"
  export GIT_PR_FAKE_EXPECT_AUTH_HOST="ghe.example.com"
  export GIT_PR_FAKE_HEAD_OWNER="octo"

  run "$GIT_PR"

  [ "$status" -eq 0 ]
  assert_log_contains "gh auth status --hostname ghe.example.com"
  assert_log_line_contains_all "gh pr create" "--repo ghe.example.com/octo/repo" "--base main" "--head feature" "--fill"
}

@test "GitHub Enterprise ssh origin strips ssh port from hostname" {
  export GIT_PR_FAKE_ORIGIN_URL="ssh://git@ghe.example.com:2222/octo/repo.git"
  export GIT_PR_FAKE_REPO="ghe.example.com/octo/repo"
  export GIT_PR_FAKE_EXPECT_AUTH_HOST="ghe.example.com"
  export GIT_PR_FAKE_HEAD_OWNER="octo"

  run "$GIT_PR"

  [ "$status" -eq 0 ]
  assert_log_contains "gh auth status --hostname ghe.example.com"
  assert_log_line_contains_all "gh pr create" "--repo ghe.example.com/octo/repo" "--base main" "--head feature" "--fill"
  assert_log_not_contains "ghe.example.com:2222/octo/repo"
}

@test "GitHub Enterprise credentialed HTTPS origin strips credentials query and fragment" {
  export GIT_PR_FAKE_ORIGIN_URL="https://token:secret@ghe.example.com/octo/repo.git?token=abc#frag"
  export GIT_PR_FAKE_REPO="ghe.example.com/octo/repo"
  export GIT_PR_FAKE_EXPECT_AUTH_HOST="ghe.example.com"
  export GIT_PR_FAKE_HEAD_OWNER="octo"

  run "$GIT_PR"

  [ "$status" -eq 0 ]
  assert_log_contains "gh auth status --hostname ghe.example.com"
  assert_log_line_contains_all "gh pr create" "--repo ghe.example.com/octo/repo" "--base main" "--head feature" "--fill"
  assert_log_not_contains "secret"
  assert_log_not_contains "token=abc"
}

@test "local path origin is rejected before push" {
  export GIT_PR_FAKE_ORIGIN_URL="../repo.git"

  run "$GIT_PR"

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: Remote 'origin' is not a supported GitHub repository URL: ../repo.git"* ]]
  assert_no_git_push
  assert_log_not_contains "gh pr create"
}

@test "scp-like absolute path origin is rejected before push" {
  export GIT_PR_FAKE_ORIGIN_URL="git@github.com:/home/me/repo.git"

  run "$GIT_PR"

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: Remote 'origin' is not a supported GitHub repository URL: git@github.com:/home/me/repo.git"* ]]
  assert_no_git_push
  assert_log_not_contains "gh pr create"
}

@test "base branch rejects raw refspec before fetch or push" {
  run "$GIT_PR" --base "main:refs/heads/pwn"

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: Invalid base branch: main:refs/heads/pwn"* ]]
  assert_log_not_contains "git -C $GIT_PR_FAKE_REPO_ROOT fetch origin"
  assert_no_git_push
  assert_log_not_contains "gh pr create"
}

@test "base branch rejects leading dash before fetch or push" {
  run "$GIT_PR" --base "-bad"

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: Invalid base branch: -bad"* ]]
  assert_log_not_contains "git -C $GIT_PR_FAKE_REPO_ROOT fetch origin"
  assert_no_git_push
  assert_log_not_contains "gh pr create"
}

@test "rev-list count failure fails before pushing" {
  export GIT_PR_FAKE_REV_LIST_COUNT_STATUS=2

  run "$GIT_PR"

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: Failed to count commits"* ]]
  assert_no_git_push
  assert_log_not_contains "gh pr create"
}

@test "create fails before push when base fetch fails" {
  export GIT_PR_FAKE_FETCH_FAIL=true

  run "$GIT_PR"

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: Failed to fetch origin/main."* ]]
  assert_no_git_push
  assert_log_not_contains "gh pr create"
}

@test "create fetches selected base before counting commits" {
  run "$GIT_PR" --base develop

  [ "$status" -eq 0 ]
  assert_log_contains "git -C $GIT_PR_FAKE_REPO_ROOT fetch origin refs/heads/develop:refs/remotes/origin/develop"
  assert_log_order \
    "git -C $GIT_PR_FAKE_REPO_ROOT fetch origin refs/heads/develop:refs/remotes/origin/develop" \
    "git -C $GIT_PR_FAKE_REPO_ROOT rev-list --count origin/develop..HEAD"
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

@test "create with explicit empty body keeps the body empty" {
  run "$GIT_PR" --title "Empty body" --body ""

  [ "$status" -eq 0 ]
  assert_log_line_contains_all "gh pr create" "--repo example/repo" "--base main" "--head feature" "--title Empty\\ body" "--body ''"
  assert_log_not_contains "-\\ Test\\ commit"
  assert_log_not_contains " --fill"
}

@test "long option equals values are accepted consistently" {
  run "$GIT_PR" --base=develop --title="Manual title" --body="Manual body" --label=bug --reviewer=alice --assignee=bob

  [ "$status" -eq 0 ]
  assert_log_line_contains_all "gh pr create" \
    "--repo example/repo" \
    "--base develop" \
    "--head feature" \
    "--label bug" \
    "--reviewer alice" \
    "--assignee bob" \
    "--title Manual\\ title" \
    "--body Manual\\ body"
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

@test "create follow-up actions run auto-merge before opening the web view" {
  run "$GIT_PR" --web --enable-auto-merge --merge-method=squash

  [ "$status" -eq 0 ]
  assert_log_line_contains_all "gh pr create" "--repo example/repo" "--base main" "--head feature" "--fill"
  assert_log_line_contains_all "gh pr merge 1" "--repo example/repo" "--auto" "--squash" "--match-head-commit local-head"
  assert_log_contains "gh pr view 1 --repo example/repo --web"
  assert_log_order "gh pr create --repo example/repo --base main --head feature --fill" "gh pr merge 1"
  assert_log_order "gh pr merge 1" "gh pr view 1 --repo example/repo --web"
}

@test "create pushes before gh pr create when upstream is missing" {
  run "$GIT_PR"

  [ "$status" -eq 0 ]
  assert_log_contains "git -C $GIT_PR_FAKE_REPO_ROOT push -u origin HEAD:refs/heads/feature"
  assert_log_order "git -C $GIT_PR_FAKE_REPO_ROOT push -u origin HEAD:refs/heads/feature" "gh pr create"
}

@test "create auto-merge accepts merge-method equals form" {
  run "$GIT_PR" --enable-auto-merge --merge-method=squash

  [ "$status" -eq 0 ]
  assert_log_line_contains_all "gh pr merge 1" "--repo example/repo" "--auto" "--squash" "--match-head-commit local-head"
}

@test "existing PR updates explicit title and body after push" {
  export GIT_PR_FAKE_PR_NUMBER=123

  run "$GIT_PR" --title "Updated title" --body "Updated body"

  [ "$status" -eq 0 ]
  assert_log_line_contains_all "gh pr edit 123" "--repo example/repo" "--title Updated\\ title" "--body Updated\\ body"
  [[ "$output" == *"INFO: Updated PR #123: title, body."* ]]
  assert_log_order "git -C $GIT_PR_FAKE_REPO_ROOT push -u origin HEAD:refs/heads/feature" "gh pr edit 123"
}

@test "existing PR explicit title and body do not require local base" {
  export GIT_PR_FAKE_PR_NUMBER=123
  export GIT_PR_FAKE_REMOTE_BASE_EXISTS=false

  run "$GIT_PR" --title "Updated title" --body "Updated body"

  [ "$status" -eq 0 ]
  assert_log_line_contains_all "gh pr edit 123" "--repo example/repo" "--title Updated\\ title" "--body Updated\\ body"
  [[ "$output" == *"INFO: Updated PR #123: title, body."* ]]
  assert_log_not_contains "git -C $GIT_PR_FAKE_REPO_ROOT fetch origin"
  assert_log_not_contains "git -C $GIT_PR_FAKE_REPO_ROOT ls-remote"
  assert_log_not_contains "git -C $GIT_PR_FAKE_REPO_ROOT rev-list --count"
  assert_log_not_contains "Base branch 'main' not found"
}

@test "existing PR explicit base cannot target current branch" {
  export GIT_PR_FAKE_PR_NUMBER=123

  run "$GIT_PR" --no-edit --base feature

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: You are on 'feature'. Create a feature branch first."* ]]
  assert_no_git_push
  assert_log_not_contains "gh pr edit"
}

@test "existing PR explicit base must exist before push" {
  export GIT_PR_FAKE_PR_NUMBER=123
  export GIT_PR_FAKE_REMOTE_BASE_EXISTS=false

  run "$GIT_PR" --no-edit --base release

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: Base branch 'release' was not found on origin. Create it or choose an existing branch with --base."* ]]
  assert_log_contains "git -C $GIT_PR_FAKE_REPO_ROOT ls-remote --exit-code --heads origin release"
  assert_no_git_push
  assert_log_not_contains "gh pr edit"
}

@test "existing PR explicit base requires exact remote ref match" {
  export GIT_PR_FAKE_PR_NUMBER=123
  export GIT_PR_FAKE_LS_REMOTE_REF="refs/heads/foo/release"

  run "$GIT_PR" --no-edit --base release

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: Base branch 'release' was not found on origin. Create it or choose an existing branch with --base."* ]]
  assert_log_contains "git -C $GIT_PR_FAKE_REPO_ROOT ls-remote --exit-code --heads origin release"
  assert_no_git_push
  assert_log_not_contains "gh pr edit"
}

@test "existing PR explicit slash base passes exact remote ref preflight" {
  export GIT_PR_FAKE_PR_NUMBER=123

  run "$GIT_PR" --no-edit --base release/2026.07

  [ "$status" -eq 0 ]
  assert_log_contains "git -C $GIT_PR_FAKE_REPO_ROOT ls-remote --exit-code --heads origin release/2026.07"
  assert_log_line_contains_all "gh pr edit 123" "--repo example/repo" "--base release/2026.07"
}

@test "existing PR updates body file only" {
  local body_file="$BATS_TEST_TMPDIR/update-body.md"
  export GIT_PR_FAKE_PR_NUMBER=123
  printf 'Updated body from file\n' > "$body_file"

  run "$GIT_PR" --body-file "$body_file"

  [ "$status" -eq 0 ]
  assert_log_line_contains_all "gh pr edit 123" "--repo example/repo" "--body-file $body_file"
  [[ "$output" == *"INFO: Updated PR #123: body file."* ]]
}

@test "existing PR explicit fill replaces a non-empty body" {
  export GIT_PR_FAKE_PR_NUMBER=123
  export GIT_PR_FAKE_PR_BODY="Already written"

  run "$GIT_PR" --fill

  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO: Replacing existing PR body because a fill option was specified."* ]]
  [[ "$output" == *"INFO: Updated PR #123: body."* ]]
  assert_log_line_contains_all "gh pr edit 123" "--repo example/repo" "--body -\\ Test\\ commit"
}

@test "existing PR explicit fill uses the pull request base branch" {
  export GIT_PR_FAKE_PR_NUMBER=123
  export GIT_PR_FAKE_PR_BODY="Already written"
  export GIT_PR_FAKE_PR_BASE=release

  run "$GIT_PR" --fill

  [ "$status" -eq 0 ]
  assert_log_contains "gh pr view 123 --repo example/repo --json baseRefName --jq .baseRefName\\ //\\ \\\"\\\""
  assert_log_contains "git -C $GIT_PR_FAKE_REPO_ROOT fetch origin refs/heads/release:refs/remotes/origin/release"
  assert_log_contains "git -C $GIT_PR_FAKE_REPO_ROOT log --pretty=-\\ %s origin/release..HEAD"
  [[ "$output" == *"INFO: Replacing existing PR body because a fill option was specified."* ]]
  [[ "$output" == *"INFO: Updated PR #123: body."* ]]
  assert_log_line_contains_all "gh pr edit 123" "--repo example/repo" "--body -\\ Test\\ commit"
}

@test "existing PR explicit fill fails before edit when base fetch fails" {
  export GIT_PR_FAKE_PR_NUMBER=123
  export GIT_PR_FAKE_PR_BODY="Already written"
  export GIT_PR_FAKE_FETCH_FAIL=true

  run "$GIT_PR" --fill

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: Failed to fetch origin/main."* ]]
  assert_log_not_contains "gh pr edit"
}

@test "existing PR explicit no-fill leaves title and body unchanged" {
  export GIT_PR_FAKE_PR_NUMBER=123

  run "$GIT_PR" --no-fill

  [ "$status" -eq 0 ]
  assert_log_contains "git -C $GIT_PR_FAKE_REPO_ROOT push -u origin HEAD:refs/heads/feature"
  assert_log_not_contains "gh pr edit"
  [[ "$output" == *"INFO: No PR fields to update."* ]]
}

@test "existing PR follow-up actions open the web view before auto-merge" {
  export GIT_PR_FAKE_PR_NUMBER=123

  run "$GIT_PR" --no-edit --web --enable-auto-merge --merge-method=squash

  [ "$status" -eq 0 ]
  assert_log_contains "git -C $GIT_PR_FAKE_REPO_ROOT push -u origin HEAD:refs/heads/feature"
  assert_log_contains "gh pr view 123 --repo example/repo --web"
  assert_log_line_contains_all "gh pr merge 123" "--repo example/repo" "--auto" "--squash" "--match-head-commit local-head"
  assert_log_order "git -C $GIT_PR_FAKE_REPO_ROOT push -u origin HEAD:refs/heads/feature" "gh pr view 123 --repo example/repo --web"
  assert_log_order "gh pr view 123 --repo example/repo --web" "gh pr merge 123"
}

@test "dirty worktree emits warning and still pushes before create" {
  export GIT_PR_FAKE_WORKTREE_DIRTY=true

  run "$GIT_PR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: Working tree has uncommitted changes. They won't be included in the PR."* ]]
  assert_log_contains "git -C $GIT_PR_FAKE_REPO_ROOT push -u origin HEAD:refs/heads/feature"
  assert_log_order "git -C $GIT_PR_FAKE_REPO_ROOT push -u origin HEAD:refs/heads/feature" "gh pr create"
}

@test "staged-only dirty index emits warning and still pushes before create" {
  export GIT_PR_FAKE_INDEX_DIRTY=true

  run "$GIT_PR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: Working tree has uncommitted changes. They won't be included in the PR."* ]]
  assert_log_contains "git -C $GIT_PR_FAKE_REPO_ROOT push -u origin HEAD:refs/heads/feature"
  assert_log_order "git -C $GIT_PR_FAKE_REPO_ROOT push -u origin HEAD:refs/heads/feature" "gh pr create"
}

@test "existing origin upstream uses explicit refspec push without setting upstream" {
  export GIT_PR_FAKE_HAS_UPSTREAM=true

  run "$GIT_PR"

  [ "$status" -eq 0 ]
  assert_log_contains "git -C $GIT_PR_FAKE_REPO_ROOT push origin HEAD:refs/heads/feature"
  assert_log_not_contains "git -C $GIT_PR_FAKE_REPO_ROOT push -u origin"
  assert_log_order "git -C $GIT_PR_FAKE_REPO_ROOT push origin HEAD:refs/heads/feature" "gh pr create"
}

@test "non-origin upstream is rejected before pushing" {
  export GIT_PR_FAKE_HAS_UPSTREAM=true
  export GIT_PR_FAKE_UPSTREAM_REF="fork/feature"

  run "$GIT_PR"

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: Existing upstream must be origin/feature"* ]]
  assert_no_git_push
  assert_log_not_contains "gh pr create"
}
