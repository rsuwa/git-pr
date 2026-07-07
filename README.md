# git-pr

`git-pr` is a small Git subcommand that streamlines the common GitHub pull
request flow from a terminal:

- push the current branch
- create a pull request when one does not exist
- update an existing pull request when one already exists
- request a merge for the current pull request or enable GitHub auto-merge

After installation, run it as:

```bash
git pr
```

## Requirements

- `git`
- GitHub CLI (`gh`)
- GitHub CLI authentication: `gh auth login`
- Optional: GitHub Copilot CLI (`copilot`) for `git pr copilot`

## Install

```bash
curl -fsSL https://github.com/rsuwa/git-pr/releases/latest/download/install.sh | bash
```

The installer places `git-pr` in `~/.local/bin`. Make sure that directory is in
your `PATH`. By default, the installer also downloads `SHA256SUMS` from the same
release and verifies the downloaded `git-pr` before installing it.
The `latest` URL follows whichever GitHub Release is currently marked latest.
For a reproducible install, pin both the downloaded installer and the payload
URLs:

```bash
curl -fsSL https://github.com/rsuwa/git-pr/releases/download/v0.3.1/install.sh |
  env \
    GIT_PR_INSTALL_URL="https://github.com/rsuwa/git-pr/releases/download/v0.3.1/git-pr" \
    GIT_PR_CHECKSUM_URL="https://github.com/rsuwa/git-pr/releases/download/v0.3.1/SHA256SUMS" \
    bash
```

Pin a downloaded payload by SHA256 instead of downloading `SHA256SUMS`:

```bash
curl -fsSL https://github.com/rsuwa/git-pr/releases/latest/download/install.sh |
  env GIT_PR_INSTALL_SHA256="<expected-sha256>" bash
```

Manual install:

```bash
set -e
mkdir -p ~/.local/bin
tmp_file=$(mktemp)
tmp_sums=$(mktemp)
cleanup() {
  rm -f "$tmp_file" "$tmp_sums"
}
trap cleanup EXIT
curl -fsSL https://github.com/rsuwa/git-pr/releases/latest/download/git-pr \
  -o "$tmp_file"
curl -fsSL https://github.com/rsuwa/git-pr/releases/latest/download/SHA256SUMS \
  -o "$tmp_sums"
expected=$(awk '$2 == "git-pr" { print $1 }' "$tmp_sums")
if command -v sha256sum >/dev/null 2>&1; then
  actual=$(sha256sum "$tmp_file" | awk '{ print $1 }')
else
  actual=$(shasum -a 256 "$tmp_file" | awk '{ print $1 }')
fi
[ "$actual" = "$expected" ]
bash -n "$tmp_file"
chmod 755 "$tmp_file"
mv "$tmp_file" ~/.local/bin/git-pr
```

## Usage

Push the current branch, then create or update a pull request for it:

```bash
git pr
```

Behavior summary:

| Situation | What happens |
| --- | --- |
| No PR exists | `git-pr` resolves the base branch, fetches it, pushes the current branch, then creates a PR. |
| PR exists | `git-pr` pushes the current branch and updates only the fields requested by options. |
| PR exists and no title/body option is given | A non-empty body is kept. An empty body is filled from commits. |
| `--no-edit` on an existing PR | Title/body are not edited. Metadata and explicit `--base` may still update the PR. |
| Explicit `--fill`, `--fill-first`, or `--fill-verbose` on an existing PR | The existing body is replaced with commit-derived content. |
| `git pr copilot --mode=update` | Existing body is kept; generated content is appended inside a `git-pr` managed marker block. |

Create or update a pull request and enable auto-merge:

```bash
git pr -a --delete-branch
```

Create a pull request with an explicit title and body:

```bash
git pr -t "Fix login redirect" -d "Updates the redirect target after login."
```

Read the body from a file:

```bash
git pr -t "Fix login redirect" -F /path/to/body.md
```

Use a pull request template:

```bash
git pr --template .github/pull_request_template.md
```

Open an editor for the new pull request:

```bash
git pr --editor
```

Add metadata:

```bash
git pr --label bug,backend --reviewer alice,bob --assignee alice
```

Use Copilot CLI to generate a pull request title and body from the diff:

```bash
git pr copilot --mode=create
```

Update an existing pull request with Copilot while preserving existing content:

```bash
git pr copilot --mode=update
```

Enable auto-merge for the existing pull request on the current branch:

```bash
git pr auto-merge
```

Request a merge for the existing pull request on the current branch:

```bash
git pr merge
```

Disable auto-merge:

```bash
git pr auto-merge --disable-auto-merge
```

Update `git-pr` from the latest GitHub release:

```bash
git pr update
```

`git pr update` downloads the `git-pr` asset and verifies it with the release
`SHA256SUMS` by default. It refuses symlink and directory targets and replaces
the executable only after checksum and Bash syntax validation pass.
To update from a pinned release instead of `latest`:

```bash
GIT_PR_UPDATE_URL="https://github.com/rsuwa/git-pr/releases/download/v0.3.1/git-pr" \
GIT_PR_UPDATE_CHECKSUM_URL="https://github.com/rsuwa/git-pr/releases/download/v0.3.1/SHA256SUMS" \
  git pr update
```

Print the installed version:

```bash
git pr --version
```

## Release Assets

Each GitHub Release used by `install.sh` and `git pr update` must publish these
assets:

- `git-pr`
- `install.sh`
- `SHA256SUMS`

`SHA256SUMS` must include entries for at least `git-pr` and `install.sh`.
The current `v0.3.1` release is published with all three assets.

Verify a release before using it:

```bash
gh release view v0.3.1 --json tagName,isDraft,isPrerelease,assets
curl -fsSL https://github.com/rsuwa/git-pr/releases/download/v0.3.1/SHA256SUMS
```

Release publishing is expected to run the test suite, generate checksums, smoke
test local release-style install/update flows, and only then upload the assets.

## Remote model

`git-pr` only works with a Git remote named `origin`. It checks for `origin`,
uses the GitHub repository default branch when resolving the default base, and
pushes new branches with `git push -u origin HEAD`. Existing upstreams must be
`origin/<current-branch>`. Selecting another remote is not supported.

Default base branch resolution order is:

1. explicit `--base`
2. `branch.<name>.gh-merge-base`
3. GitHub repository default branch
4. local `origin/HEAD`

When local commit ranges or Copilot diffs are generated, `git-pr` fetches the
selected base from `origin` first. Existing PR metadata-only updates do not need
a local base ref, but explicit existing-PR `--base` retargets are checked
against `origin` before pushing.

## Options

| Option | Description |
| --- | --- |
| `-b, --base <branch>` | Base branch. Defaults to `branch.<name>.gh-merge-base`, then the repository default branch, then local `origin/HEAD`. |
| `-t, --title <title>` | Pull request title. |
| `-d, --body <body>` | Pull request body. |
| `-F, --body-file <path\|->` | Pull request body file, or `-` to let `gh` read stdin. |
| `-T, --template <path>` | Starting body template passed to `gh pr create`. Create only. |
| `-e, --editor` | Open an editor while creating a pull request. Create only. |
| `--label <label>` | Add labels. Repeatable and comma-separated values are supported. |
| `--reviewer <user>` | Add reviewers. Repeatable and comma-separated values are supported. |
| `--assignee <user>` | Add assignees. Repeatable and comma-separated values are supported. |
| `--fill`, `--fill-first`, `--fill-verbose` | Use GitHub CLI fill behavior when creating a pull request. On existing PRs, explicitly replace the body with locally generated commit content. |
| `--no-fill` | Do not pass a GitHub CLI fill flag. On create, missing title/body are generated locally from commits; on existing PRs, no title/body update is made unless explicit content is provided. |
| `--no-edit` | Do not update an existing pull request title or body. Metadata and explicit `--base` may still update the PR. |
| `-a, --enable-auto-merge` | Enable auto-merge after creating or updating a pull request. |
| `-m, --merge-method <method>` | Merge method: `merge`, `squash`, or `rebase`. Requires `--enable-auto-merge`, `git pr auto-merge`, or `git pr merge`. |
| `--delete-branch` | Delete the branch after merge. Requires `--enable-auto-merge`, `git pr auto-merge`, or `git pr merge`. |
| `--admin` | Rejected with `git-pr` merge operations because it bypasses merge requirements. Use `gh pr merge --admin` directly if you intend to bypass them. |
| `--match-head-commit <sha>` | Require the pull request head commit to match the given SHA when merging. If omitted, `git-pr` uses the local `HEAD` SHA. Requires `--enable-auto-merge`, `git pr auto-merge`, or `git pr merge`. |
| `--disable-auto-merge` | Disable auto-merge on the current PR. Only valid with `git pr auto-merge`. |
| `--draft` | Create the pull request as a draft. |
| `-w, --web` | Open the pull request in a browser. |
| `--version` | Print `git-pr <version>` and exit without requiring `git` or `gh`. |

## Copilot

`git pr copilot` is optional and requires the GitHub Copilot CLI.

```bash
git pr copilot --mode=create --detail=verbose
```

Copilot options:

| Option | Description |
| --- | --- |
| `--mode <create\|update\|auto>` | `create` generates a new title/body for a new PR, `update` preserves an existing body and appends generated content inside a managed marker block, and `auto` chooses based on whether a pull request exists. |
| `--detail <normal\|verbose>` | Controls the generated body detail level. |
| `--language <en\|ja>` | Output language. Defaults to `GIT_PR_LANGUAGE`, then `git-pr.language`, then `en`. |
| `--diff-exclude <path>` | Exclude a path from the diff sent to Copilot. Repeatable. |

Copilot privacy behavior:

- Update mode uses these markers in the PR body:
  `<!-- git-pr:copilot-update:start -->` and
  `<!-- git-pr:copilot-update:end -->`. Manual content outside the block is
  preserved. If the marker block is malformed, `git-pr` refuses to edit the PR.
- Update mode includes the current PR title and body in the prompt sent to
  Copilot so it can avoid duplicate generated content.

- `git-pr` writes temporary prompt, diff, title, and body files in a private
  temp directory outside the repository and removes them when the process exits.
- On Copilot failure or parse failure, debug logs are saved under
  `${XDG_STATE_HOME:-$HOME/.local/state}/git-pr/copilot-logs` by default.
  Set `GIT_PR_COPILOT_LOG` to a non-empty value to keep logs after a successful
  generation.
- Debug logs omit prompt, diff, and response content by default. Set
  `GIT_PR_COPILOT_LOG_CONTENT=1` only when you intentionally want to persist
  that content for debugging.
- Temporary directories must be secured with `chmod 700` before Copilot runs.
  Debug logs are skipped when the log directory cannot be made private. This
  privacy hardening depends on the filesystem enforcing POSIX permissions.

Configuration:

```bash
git config git-pr.language ja
git config --add git-pr.diffExclude generated
git config --add git-pr.diffExclude vendor
```

Environment variables:

| Variable | Description |
| --- | --- |
| `GIT_PR_INSTALL_URL` | Override the URL used by `install.sh`. |
| `GIT_PR_CHECKSUM_URL` | Override the `SHA256SUMS` URL used by `install.sh`. |
| `GIT_PR_INSTALL_DIR` | Override the installation directory used by `install.sh`. |
| `GIT_PR_INSTALL_SHA256` | Expected SHA256 for the file downloaded by `install.sh`; skips `SHA256SUMS` download when set. |
| `GIT_PR_LANGUAGE` | Default Copilot output language: `en` or `ja`. |
| `GIT_PR_DIFF_EXCLUDES` | Comma-separated paths excluded from the Copilot diff. |
| `GIT_PR_COPILOT_DIFF_MAX_BYTES` | Maximum diff bytes sent to Copilot. Default: `20000`. |
| `GIT_PR_COPILOT_LOG_DIR` | Directory for Copilot debug logs. Default: `${XDG_STATE_HOME:-$HOME/.local/state}/git-pr/copilot-logs`. Logs are skipped if the directory cannot be secured with `chmod 700`. |
| `GIT_PR_COPILOT_LOG` | Set to a non-empty value to keep Copilot debug logs on success. |
| `GIT_PR_COPILOT_LOG_CONTENT` | Set to a non-empty value to persist prompt, diff, and response content in Copilot debug logs. |
| `GIT_PR_UPDATE_URL` | Override the update URL used by `git pr update`. |
| `GIT_PR_UPDATE_CHECKSUM_URL` | Override the `SHA256SUMS` URL used by `git pr update`. |
| `GIT_PR_UPDATE_SHA256` | Expected SHA256 for the file downloaded by `git pr update`; skips `SHA256SUMS` download when set. |
| `GIT_PR_UPDATE_INSTALL_PATH` | Override the executable path replaced by `git pr update`. |

SHA256 checks use `sha256sum` when available, then `shasum -a 256`.
`git pr update` reports the update URL, checksum source, and install target
before downloading. URL userinfo, query strings, and fragments are redacted in
these status messages.

`git pr merge` delegates to `gh pr merge` without `--auto`, similar to pressing
GitHub's Merge button for the current pull request. Depending on repository
rules and merge queue state, GitHub CLI may merge immediately or add the pull
request to a merge queue. `git pr auto-merge` delegates to
`gh pr merge --auto`, which asks GitHub to merge later when requirements are
satisfied.

## Existing Pull Requests

When a pull request already exists for the current branch, `git pr` pushes the
branch and updates metadata requested by options. The title is kept unless
`--title` is provided. The body is kept when it is non-empty unless a fill
option, `--body`, `--body-file`, or `git pr copilot --mode=update` is
explicitly used.
If the existing body is empty, the default `git pr` flow fills it from commits.

Use `--no-edit` to avoid title/body edits while still allowing metadata and
explicit base updates.
When `--base` is used on an existing PR, `git-pr` verifies that the target base
branch exists on `origin` before pushing the current branch.

## Development

Run the test suite:

```bash
bash -n git-pr install.sh test/test_helper.bash
shellcheck git-pr install.sh test/test_helper.bash test/*.bats
npx -y bats test
```

CI runs these checks on Linux and macOS. It also exercises release-style
`install.sh` and `git pr update` flows against local `file://` assets with
`SHA256SUMS`.

The real Copilot CLI smoke test is opt-in and skipped by default. It performs a
real Copilot request and may consume account quota and time. To run it, install
and authenticate `copilot`, then set:

```bash
GIT_PR_RUN_REAL_COPILOT_SMOKE=1 npx -y bats test/real_copilot_smoke.bats
```

The smoke test uses `timeout` and defaults to `30s`. Override it with
`GIT_PR_REAL_COPILOT_SMOKE_TIMEOUT` when needed.

## License

MIT
