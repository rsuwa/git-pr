setup_fake_cli_env() {
  export GIT_PR_FAKE_BIN="$BATS_TEST_TMPDIR/bin"
  export GIT_PR_FAKE_LOG="$BATS_TEST_TMPDIR/calls.log"
  export GIT_PR_FAKE_REPO_ROOT="$BATS_TEST_TMPDIR/repo"
  export GIT_PR_FAKE_BRANCH="${GIT_PR_FAKE_BRANCH:-feature}"
  mkdir -p "$GIT_PR_FAKE_BIN" "$GIT_PR_FAKE_REPO_ROOT"
  : > "$GIT_PR_FAKE_LOG"
  export PATH="$GIT_PR_FAKE_BIN:$BATS_TEST_DIRNAME/..:$PATH"
  create_fake_git
  create_fake_gh
}

create_fake_git() {
  cat > "$GIT_PR_FAKE_BIN/git" <<'FAKE_GIT'
#!/usr/bin/env bash
set -euo pipefail

log_call() {
  {
    printf 'git'
    for arg in "$@"; do
      printf ' %q' "$arg"
    done
    printf '\n'
  } >> "$GIT_PR_FAKE_LOG"
}

log_call "$@"

if [ "${1-}" = "-C" ]; then
  shift 2
fi

case "${1-}" in
  rev-parse)
    case "${2-}" in
      --show-toplevel)
        [ "${GIT_PR_FAKE_IS_REPO:-true}" = "true" ] || exit 1
        printf '%s\n' "$GIT_PR_FAKE_REPO_ROOT"
        ;;
      --abbrev-ref)
        if [ "${GIT_PR_FAKE_HAS_UPSTREAM:-false}" = "true" ]; then
          printf '%s\n' "${GIT_PR_FAKE_UPSTREAM_REF:-origin/$GIT_PR_FAKE_BRANCH}"
        else
          exit 1
        fi
        ;;
      HEAD)
        printf '%s\n' "${GIT_PR_FAKE_HEAD_SHA:-local-head}"
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  branch)
    if [ "${2-}" = "--show-current" ]; then
      printf '%s\n' "$GIT_PR_FAKE_BRANCH"
    else
      exit 1
    fi
    ;;
  remote)
    if [ "${2-}" = "get-url" ] && [ "${3-}" = "origin" ]; then
      [ "${GIT_PR_FAKE_HAS_ORIGIN:-true}" = "true" ] || exit 1
      printf '%s\n' "${GIT_PR_FAKE_ORIGIN_URL:-git@github.com:example/repo.git}"
    else
      exit 1
    fi
    ;;
  check-ref-format)
    if [ "${2-}" = "--branch" ] && [ -n "${3-}" ]; then
      case "$3" in
        -*|*:*|*..*|*~*|*^*|*\\*|*[[:space:]]*|*'?'*|*'['*|*//*|*.|*/.|*.lock|*@{*|@)
          exit 1
          ;;
        *)
          printf '%s\n' "$3"
          ;;
      esac
    else
      exit 1
    fi
    ;;
  config)
    if [ "${2-}" = "--get" ] && [ "${3-}" = "branch.$GIT_PR_FAKE_BRANCH.gh-merge-base" ]; then
      [ -n "${GIT_PR_FAKE_MERGE_BASE:-}" ] || exit 1
      printf '%s\n' "$GIT_PR_FAKE_MERGE_BASE"
    elif [ "${2-}" = "--get" ] && [ "${3-}" = "git-pr.language" ]; then
      [ -n "${GIT_PR_FAKE_CONFIG_LANGUAGE:-}" ] || exit 1
      printf '%s\n' "$GIT_PR_FAKE_CONFIG_LANGUAGE"
    elif [ "${2-}" = "--get-all" ] && [ "${3-}" = "git-pr.diffExclude" ]; then
      [ -n "${GIT_PR_FAKE_CONFIG_DIFF_EXCLUDE:-}" ] || exit 1
      printf '%s\n' "$GIT_PR_FAKE_CONFIG_DIFF_EXCLUDE"
    else
      exit 1
    fi
    ;;
  symbolic-ref)
    if [ "${*: -1}" = "refs/remotes/origin/HEAD" ]; then
      [ "${GIT_PR_FAKE_HAS_ORIGIN_HEAD:-true}" = "true" ] || exit 1
      printf 'origin/%s\n' "${GIT_PR_FAKE_DEFAULT_BRANCH:-main}"
    else
      exit 1
    fi
    ;;
  show-ref)
    ref="${*: -1}"
    case "$ref" in
      refs/remotes/origin/*)
        [ "${GIT_PR_FAKE_REMOTE_BASE_EXISTS:-true}" = "true" ] || exit 1
        ;;
      refs/heads/*)
        [ "${GIT_PR_FAKE_HAS_LOCAL_BASE:-false}" = "true" ] || exit 1
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  rev-list)
    if [ "${2-}" = "--count" ]; then
      if [ -n "${GIT_PR_FAKE_REV_LIST_COUNT_STATUS:-}" ]; then
        exit "$GIT_PR_FAKE_REV_LIST_COUNT_STATUS"
      fi
      printf '%s\n' "${GIT_PR_FAKE_COMMIT_COUNT:-1}"
    elif [ "${2-}" = "--reverse" ]; then
      printf 'commit-one\n'
    else
      exit 1
    fi
    ;;
  diff)
    if [ "${2-}" = "--cached" ] && [ "${3-}" = "--quiet" ]; then
      [ "${GIT_PR_FAKE_INDEX_DIRTY:-false}" != "true" ] || exit 1
      exit 0
    elif [ "${2-}" = "--quiet" ] && [ $# -eq 2 ]; then
      [ "${GIT_PR_FAKE_WORKTREE_DIRTY:-false}" != "true" ] || exit 1
      exit 0
    elif [ "${2-}" = "--quiet" ]; then
      exit "${GIT_PR_FAKE_DIFF_QUIET_STATUS:-1}"
    elif [ "${2-}" = "--stat" ]; then
      printf ' git-pr | 2 +-\n'
    else
      printf 'diff --git a/git-pr b/git-pr\n'
    fi
    ;;
  push)
    exit 0
    ;;
  fetch)
    [ "${GIT_PR_FAKE_FETCH_FAIL:-false}" != "true" ] || exit 1
    exit 0
    ;;
  ls-remote)
    if [ "${2-}" = "--exit-code" ] && [ "${3-}" = "--heads" ] && [ "${4-}" = "origin" ] && [ -n "${5-}" ]; then
      [ "${GIT_PR_FAKE_REMOTE_BASE_EXISTS:-true}" = "true" ] || exit 2
      remote_ref="${GIT_PR_FAKE_LS_REMOTE_REF:-refs/heads/${5}}"
      printf '%s\t%s\n' "${GIT_PR_FAKE_REMOTE_BASE_SHA:-remote-base}" "$remote_ref"
    else
      exit 1
    fi
    ;;
  log)
    if [ "${2-}" = "-1" ]; then
      printf '%s\n' "${GIT_PR_FAKE_LAST_SUBJECT:-Test title}"
    else
      printf '%s\n' "${GIT_PR_FAKE_LOG_BODY:-- Test commit}"
    fi
    ;;
  *)
    printf 'fake git: unsupported command: %s\n' "$*" >&2
    exit 1
    ;;
esac
FAKE_GIT
  chmod 755 "$GIT_PR_FAKE_BIN/git"
}

create_fake_gh() {
  cat > "$GIT_PR_FAKE_BIN/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail

log_call() {
  {
    printf 'gh'
    for arg in "$@"; do
      printf ' %q' "$arg"
    done
    printf '\n'
  } >> "$GIT_PR_FAKE_LOG"
}

log_call "$@"

arg_after() {
  local needle="$1"
  local i

  shift
  for ((i = 1; i <= $#; i++)); do
    if [ "${!i}" = "$needle" ]; then
      local next=$((i + 1))
      printf '%s' "${!next-}"
      return 0
    fi
  done
  return 1
}

has_arg() {
  local needle="$1"
  local arg

  shift
  for arg in "$@"; do
    [ "$arg" != "$needle" ] || return 0
  done
  return 1
}

fake_pr_number() {
  if [ -n "${GIT_PR_FAKE_PR_NUMBER:-}" ]; then
    printf '%s\n' "$GIT_PR_FAKE_PR_NUMBER"
  elif [ -f "$GIT_PR_FAKE_LOG.created-pr" ]; then
    cat "$GIT_PR_FAKE_LOG.created-pr"
  fi
}

fake_pr_list_number() {
  local count=0

  if [ -n "${GIT_PR_FAKE_PR_NUMBER_AFTER_LIST:-}" ]; then
    if [ -f "$GIT_PR_FAKE_LOG.pr-list-count" ]; then
      count=$(cat "$GIT_PR_FAKE_LOG.pr-list-count")
    fi
    count=$((count + 1))
    printf '%s\n' "$count" > "$GIT_PR_FAKE_LOG.pr-list-count"
    if [ "$count" -ge "${GIT_PR_FAKE_PR_NUMBER_AFTER_LIST:-2}" ]; then
      printf '%s\n' "${GIT_PR_FAKE_PR_NUMBER_AFTER_LIST_VALUE:-123}"
      return 0
    fi
  fi

  fake_pr_number
}

case "${1-} ${2-}" in
  "auth status")
    auth_host="$(arg_after --hostname "$@" || true)"
    if [ -n "${GIT_PR_FAKE_EXPECT_AUTH_HOST:-}" ] && [ "$auth_host" != "$GIT_PR_FAKE_EXPECT_AUTH_HOST" ]; then
      printf 'fake gh: unexpected auth host: %s\n' "$auth_host" >&2
      exit 1
    fi
    [ "${GIT_PR_FAKE_GH_AUTH:-true}" = "true" ] || exit 1
    ;;
  "repo view")
    if has_arg --repo "$@"; then
      printf 'fake gh: repo view does not support --repo\n' >&2
      exit 1
    fi
    repo="${3-}"
    if [ -z "$repo" ] || [ "${repo#-}" != "$repo" ]; then
      printf 'fake gh: repo view missing repository argument\n' >&2
      exit 1
    fi
    if [ "$repo" != "${GIT_PR_FAKE_REPO:-example/repo}" ]; then
      printf 'fake gh: unexpected repo view repository: %s\n' "$repo" >&2
      exit 1
    fi
    [ "${GIT_PR_FAKE_REPO_VIEW_FAIL:-false}" != "true" ] || exit 1
    printf '%s\n' "${GIT_PR_FAKE_DEFAULT_BRANCH:-main}"
    ;;
  "pr view")
    json_field=""
    jq_expr=""
    repo="$(arg_after --repo "$@" || true)"
    if [ -n "$repo" ] && [ "$repo" != "${GIT_PR_FAKE_REPO:-example/repo}" ]; then
      printf 'fake gh: unexpected repo: %s\n' "$repo" >&2
      exit 1
    fi
    for ((i = 1; i <= $#; i++)); do
      if [ "${!i}" = "--json" ]; then
        next=$((i + 1))
        json_field="${!next-}"
        break
      fi
    done
    if [ -n "$json_field" ]; then
      jq_expr="$(arg_after --jq "$@" || true)"
      if [ "$jq_expr" != ".$json_field // \"\"" ]; then
        printf 'fake gh: pr view missing or unexpected --jq for %s: %s\n' "$json_field" "$jq_expr" >&2
        exit 1
      fi
    fi
    if [ -n "$json_field" ]; then
      case "$json_field" in
        number)
          [ -n "${GIT_PR_FAKE_PR_NUMBER:-}" ] || exit 1
          printf '%s\n' "$GIT_PR_FAKE_PR_NUMBER"
          ;;
        title)
          printf '%s\n' "${GIT_PR_FAKE_PR_TITLE-Existing title}"
          ;;
        body)
          printf '%s\n' "${GIT_PR_FAKE_PR_BODY-Existing body}"
          ;;
        headRefOid)
          printf '%s\n' "${GIT_PR_FAKE_PR_HEAD_SHA:-local-head}"
          ;;
        baseRefName)
          printf '%s\n' "${GIT_PR_FAKE_PR_BASE:-main}"
          ;;
        *)
          exit 1
          ;;
      esac
    elif [ "$#" -ge 2 ] && has_arg --web "$@"; then
      exit 0
    else
      [ -n "${GIT_PR_FAKE_PR_NUMBER:-}" ] || exit 1
      printf '%s\n' "$GIT_PR_FAKE_PR_NUMBER"
    fi
    ;;
  "pr list")
    jq_expr=""
    repo="$(arg_after --repo "$@" || true)"
    head="$(arg_after --head "$@" || true)"
    state="$(arg_after --state "$@" || true)"
    json_fields="$(arg_after --json "$@" || true)"
    pr_number_value="$(fake_pr_list_number)"
    for ((i = 1; i <= $#; i++)); do
      if [ "${!i}" = "--jq" ]; then
        next=$((i + 1))
        jq_expr="${!next-}"
        break
      fi
    done
    if [ "$repo" != "${GIT_PR_FAKE_REPO:-example/repo}" ]; then
      printf 'fake gh: pr list missing or unexpected --repo: %s\n' "$repo" >&2
      exit 1
    fi
    if [ "$head" != "${GIT_PR_FAKE_BRANCH:-feature}" ]; then
      printf 'fake gh: pr list missing or unexpected --head: %s\n' "$head" >&2
      exit 1
    fi
    if [ "$state" != "open" ]; then
      printf 'fake gh: pr list missing or unexpected --state: %s\n' "$state" >&2
      exit 1
    fi
    if ! printf '%s\n' "$json_fields" | grep -F 'number' >/dev/null || \
       ! printf '%s\n' "$json_fields" | grep -F 'headRepositoryOwner' >/dev/null; then
      printf 'fake gh: pr list missing or unexpected --json: %s\n' "$json_fields" >&2
      exit 1
    fi
    if [ -n "$jq_expr" ]; then
      expected_owner="${GIT_PR_FAKE_HEAD_OWNER:-example}"
      if ! printf '%s\n' "$jq_expr" | grep -F 'headRepositoryOwner.login' >/dev/null || \
         ! printf '%s\n' "$jq_expr" | grep -F "\"$expected_owner\"" >/dev/null; then
        printf 'fake gh: pr list --jq did not filter by head owner %s: %s\n' "$expected_owner" "$jq_expr" >&2
        exit 1
      fi
      [ -n "$pr_number_value" ] || exit 0
      case "$jq_expr" in
        *number*)
          printf '%s\n' "$pr_number_value"
          ;;
        *headRefOid*)
          printf '%s\n' "${GIT_PR_FAKE_PR_HEAD_SHA:-local-head}"
          ;;
        *)
          exit 1
          ;;
      esac
    elif [ -n "$pr_number_value" ]; then
      printf '[{"number":%s,"headRefOid":"%s","title":"%s","body":"%s"}]\n' \
        "$pr_number_value" \
        "${GIT_PR_FAKE_PR_HEAD_SHA:-local-head}" \
        "${GIT_PR_FAKE_PR_TITLE-Existing title}" \
        "${GIT_PR_FAKE_PR_BODY-Existing body}"
    else
      printf '[]\n'
    fi
    ;;
  "pr create")
    printf '%s\n' "${GIT_PR_FAKE_CREATED_PR_NUMBER:-1}" > "$GIT_PR_FAKE_LOG.created-pr"
    printf 'https://github.com/example/repo/pull/1\n'
    ;;
  "pr edit")
    if has_arg --title "$@"; then
      arg_after --title "$@" > "$GIT_PR_FAKE_LOG.pr-edit-title"
    fi
    if has_arg --body "$@"; then
      arg_after --body "$@" > "$GIT_PR_FAKE_LOG.pr-edit-body"
    fi
    if has_arg --body-file "$@"; then
      arg_after --body-file "$@" > "$GIT_PR_FAKE_LOG.pr-edit-body-file"
    fi
    if has_arg --base "$@"; then
      arg_after --base "$@" > "$GIT_PR_FAKE_LOG.pr-edit-base"
    fi
    exit 0
    ;;
  "pr merge")
    if has_arg --auto "$@" && has_arg --admin "$@"; then
      printf 'specify only one of `--auto`, `--disable-auto`, or `--admin`\n' >&2
      exit 1
    fi
    if has_arg --disable-auto "$@" && has_arg --admin "$@"; then
      printf 'specify only one of `--auto`, `--disable-auto`, or `--admin`\n' >&2
      exit 1
    fi
    if has_arg --auto "$@" && has_arg --disable-auto "$@"; then
      printf 'specify only one of `--auto`, `--disable-auto`, or `--admin`\n' >&2
      exit 1
    fi
    exit 0
    ;;
  *)
    printf 'fake gh: unsupported command: %s\n' "$*" >&2
    exit 1
    ;;
esac
FAKE_GH
  chmod 755 "$GIT_PR_FAKE_BIN/gh"
}

create_fake_copilot() {
  cat > "$GIT_PR_FAKE_BIN/copilot" <<'FAKE_COPILOT'
#!/usr/bin/env bash
set -euo pipefail

{
  printf 'copilot'
  for arg in "$@"; do
    printf ' %q' "$arg"
  done
  printf '\n'
} >> "$GIT_PR_FAKE_LOG"

if [ "${GIT_PR_FAKE_COPILOT_FAIL:-false}" = "true" ]; then
  exit 1
fi

cat <<'COPILOT_RESPONSE'
__GIT_PR_TITLE__
Generated title
__GIT_PR_BODY__
Generated body
__GIT_PR_END__
COPILOT_RESPONSE
FAKE_COPILOT
  chmod 755 "$GIT_PR_FAKE_BIN/copilot"
}

create_failing_download_tools() {
  cat > "$GIT_PR_FAKE_BIN/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
set -euo pipefail

{
  printf 'curl'
  for arg in "$@"; do
    printf ' %q' "$arg"
  done
  printf '\n'
} >> "$GIT_PR_FAKE_LOG"

printf 'fake curl should not be called\n' >&2
exit 97
FAKE_CURL
  chmod 755 "$GIT_PR_FAKE_BIN/curl"

  cat > "$GIT_PR_FAKE_BIN/wget" <<'FAKE_WGET'
#!/usr/bin/env bash
set -euo pipefail

{
  printf 'wget'
  for arg in "$@"; do
    printf ' %q' "$arg"
  done
  printf '\n'
} >> "$GIT_PR_FAKE_LOG"

printf 'fake wget should not be called\n' >&2
exit 97
FAKE_WGET
  chmod 755 "$GIT_PR_FAKE_BIN/wget"
}

assert_log_contains() {
  local expected="$1"
  grep -F "$expected" "$GIT_PR_FAKE_LOG" >/dev/null || {
    printf 'Expected log to contain:\n%s\n\nActual log:\n' "$expected" >&2
    cat "$GIT_PR_FAKE_LOG" >&2
    return 1
  }
}

assert_log_not_contains() {
  local unexpected="$1"
  if grep -F "$unexpected" "$GIT_PR_FAKE_LOG" >/dev/null; then
    printf 'Expected log not to contain:\n%s\n\nActual log:\n' "$unexpected" >&2
    cat "$GIT_PR_FAKE_LOG" >&2
    return 1
  fi
}

assert_no_git_push() {
  if grep -E '^git( .*)? push( |$)' "$GIT_PR_FAKE_LOG" >/dev/null; then
    printf 'Expected no git push call.\n\nActual log:\n' >&2
    cat "$GIT_PR_FAKE_LOG" >&2
    return 1
  fi
}

assert_no_command_logged() {
  local command_name="$1"

  if grep -E "^$command_name( |$)" "$GIT_PR_FAKE_LOG" >/dev/null; then
    printf 'Expected no %s command call.\n\nActual log:\n' "$command_name" >&2
    cat "$GIT_PR_FAKE_LOG" >&2
    return 1
  fi
}

assert_log_order() {
  local first="$1"
  local second="$2"
  local first_line
  local second_line

  first_line=$(grep -n -F "$first" "$GIT_PR_FAKE_LOG" | head -n 1 | cut -d: -f1)
  second_line=$(grep -n -F "$second" "$GIT_PR_FAKE_LOG" | head -n 1 | cut -d: -f1)
  if [ -z "$first_line" ] || [ -z "$second_line" ] || [ "$first_line" -ge "$second_line" ]; then
    printf 'Expected log entry:\n%s\n\nto appear before:\n%s\n\nActual log:\n' "$first" "$second" >&2
    cat "$GIT_PR_FAKE_LOG" >&2
    return 1
  fi
}

assert_log_line_contains_all() {
  local prefix="$1"
  local line
  shift

  line=$(grep -F "$prefix" "$GIT_PR_FAKE_LOG" | head -n 1) || {
    printf 'Expected log line with prefix:\n%s\n\nActual log:\n' "$prefix" >&2
    cat "$GIT_PR_FAKE_LOG" >&2
    return 1
  }
  for expected in "$@"; do
    if ! printf '%s\n' "$line" | grep -F -- "$expected" >/dev/null; then
      printf 'Expected log line:\n%s\n\nto contain:\n%s\n\nActual log:\n' "$line" "$expected" >&2
      cat "$GIT_PR_FAKE_LOG" >&2
      return 1
    fi
  done
}

assert_log_line_not_contains() {
  local prefix="$1"
  local unexpected="$2"
  local line

  line=$(grep -F "$prefix" "$GIT_PR_FAKE_LOG" | head -n 1) || {
    printf 'Expected log line with prefix:\n%s\n\nActual log:\n' "$prefix" >&2
    cat "$GIT_PR_FAKE_LOG" >&2
    return 1
  }
  if printf '%s\n' "$line" | grep -F -- "$unexpected" >/dev/null; then
    printf 'Expected log line:\n%s\n\nnot to contain:\n%s\n\nActual log:\n' "$line" "$unexpected" >&2
    cat "$GIT_PR_FAKE_LOG" >&2
    return 1
  fi
}
