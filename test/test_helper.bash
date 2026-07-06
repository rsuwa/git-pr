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
        printf '%s\n' "$GIT_PR_FAKE_REPO_ROOT"
        ;;
      --abbrev-ref)
        if [ "${GIT_PR_FAKE_HAS_UPSTREAM:-false}" = "true" ]; then
          printf 'origin/%s\n' "$GIT_PR_FAKE_BRANCH"
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
      printf 'git@github.com:example/repo.git\n'
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
      printf 'origin/%s\n' "${GIT_PR_FAKE_DEFAULT_BRANCH:-main}"
    else
      exit 1
    fi
    ;;
  show-ref)
    ref="${*: -1}"
    case "$ref" in
      refs/remotes/origin/*)
        exit 0
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
      printf '%s\n' "${GIT_PR_FAKE_COMMIT_COUNT:-1}"
    elif [ "${2-}" = "--reverse" ]; then
      printf 'commit-one\n'
    else
      exit 1
    fi
    ;;
  diff)
    if [ "${2-}" = "--cached" ] && [ "${3-}" = "--quiet" ]; then
      exit 0
    elif [ "${2-}" = "--quiet" ] && [ $# -eq 2 ]; then
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

fake_pr_number() {
  if [ -n "${GIT_PR_FAKE_PR_NUMBER:-}" ]; then
    printf '%s\n' "$GIT_PR_FAKE_PR_NUMBER"
  elif [ -f "$GIT_PR_FAKE_LOG.created-pr" ]; then
    cat "$GIT_PR_FAKE_LOG.created-pr"
  fi
}

case "${1-} ${2-}" in
  "auth status")
    [ "${GIT_PR_FAKE_GH_AUTH:-true}" = "true" ] || exit 1
    ;;
  "repo view")
    printf '%s\n' "${GIT_PR_FAKE_DEFAULT_BRANCH:-main}"
    ;;
  "pr view")
    json_field=""
    for ((i = 1; i <= $#; i++)); do
      if [ "${!i}" = "--json" ]; then
        next=$((i + 1))
        json_field="${!next-}"
        break
      fi
    done
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
        *)
          exit 1
          ;;
      esac
    elif [ "$#" -ge 2 ] && [ "${*: -1}" = "--web" ]; then
      exit 0
    else
      [ -n "${GIT_PR_FAKE_PR_NUMBER:-}" ] || exit 1
      printf '%s\n' "$GIT_PR_FAKE_PR_NUMBER"
    fi
    ;;
  "pr list")
    jq_expr=""
    pr_number_value="$(fake_pr_number)"
    for ((i = 1; i <= $#; i++)); do
      if [ "${!i}" = "--jq" ]; then
        next=$((i + 1))
        jq_expr="${!next-}"
        break
      fi
    done
    if [ -n "$jq_expr" ]; then
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
  "pr edit"|"pr merge")
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
