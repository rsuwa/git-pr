#!/bin/bash
# git-pr: Create a PR from the current branch and optionally enable auto-merge.

set -euo pipefail

GIT_PR_VERSION="0.3.6"
COPILOT_UPDATE_START_MARKER="<!-- git-pr:copilot-update:start -->"
COPILOT_UPDATE_END_MARKER="<!-- git-pr:copilot-update:end -->"
GITHUB_CLI_INSTALL_URL="https://github.com/cli/cli#installation"
GITHUB_CLI_AUTH_URL="https://cli.github.com/manual/gh_auth_login"
COPILOT_CLI_INSTALL_URL="https://docs.github.com/copilot/how-tos/set-up/install-copilot-cli"
COPILOT_CLI_USAGE_URL="https://docs.github.com/copilot/how-tos/copilot-cli/cli-getting-started"
cleanup_paths=()
cleanup_trap_registered="false"
copilot_private_temp_dir=""

usage() {
  cat <<'USAGE'
Usage: git pr [create] [options]
       git pr auto-merge [options]
       git pr merge [options]
       git pr copilot [options]
       git pr doctor [--with-copilot]
       git pr update

Pushes the current branch, then creates or updates a GitHub pull request.

Options:
  -b, --base <branch>      Base branch (default: gh-merge-base, repo default, origin/HEAD)
  -t, --title <title>      PR title (disables --fill)
  -d, --body <body>        PR body (disables --fill)
  -F, --body-file <path|-> PR body from file or stdin (disables --fill)
  -e, --editor             Open editor to edit title/body (create only)
  -T, --template <path>    Starting PR body template for gh/Copilot (create only)
  --label <label>          Add label(s) (repeatable, comma-separated ok)
  --reviewer <user>        Add reviewer(s) (repeatable, comma-separated ok)
  --assignee <user>        Add assignee(s) (repeatable, comma-separated ok)
  --mode <m>               Copilot mode (copilot only): create|update|auto (default: auto)
  --detail <d>             Copilot detail (copilot only): normal|verbose (default: normal)
  --language <lang>        Copilot output language: en|ja (default: env/config or en)
  --diff-exclude <path>    Exclude path from Copilot diff (repeatable)
  --fill                   Create: gh fill; existing PR: replace body from commits
  --fill-first             Create: gh fill-first; existing PR: replace from first commit
  --fill-verbose           Create: gh fill-verbose; existing PR: replace verbose body
  --no-fill                Create: generate missing local body; existing PR: no implicit body update
  --no-edit                Do not edit existing PR title/body; metadata/base may update
  -a, --enable-auto-merge  Enable auto-merge after checks pass (for create/update)
  -m, --merge-method <m>   merge|squash|rebase (merge actions; default: merge)
  --delete-branch          Delete branch after merge
  --admin                  Rejected; use gh directly to bypass requirements
  --match-head-commit <s>  Require head SHA to match for merge
  --disable-auto-merge     Disable auto-merge for existing PR (auto-merge only)
  --with-copilot           Doctor: require optional Copilot CLI on PATH
  --draft                  Create as draft
  -w, --web                Open the PR in a browser
  --version                Show version
  -h, --help               Show help
USAGE
}

version() {
  printf 'git-pr %s\n' "$GIT_PR_VERSION"
}

log_info() {
  printf 'INFO: %s\n' "$*"
}

log_warn() {
  printf 'WARN: %s\n' "$*" >&2
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

require_gh_cli() {
  command -v gh >/dev/null 2>&1 || \
    die "Missing command: gh. Install GitHub CLI: $GITHUB_CLI_INSTALL_URL. Then run: gh auth login"
}

github_cli_auth_message() {
  local host="$1"

  printf 'Run: gh auth login --hostname %s. Check with: gh auth status --hostname %s. See: %s' \
    "$host" "$host" "$GITHUB_CLI_AUTH_URL"
}

copilot_cli_install_message() {
  printf 'Install GitHub Copilot CLI: %s' "$COPILOT_CLI_INSTALL_URL"
}
