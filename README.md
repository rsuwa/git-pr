# git-pr

`git-pr` is a small Git subcommand that streamlines the common GitHub pull
request flow from a terminal:

- push the current branch
- create a pull request when one does not exist
- update an existing pull request when one already exists
- optionally enable GitHub auto-merge

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

Pin a downloaded payload by SHA256 instead of downloading `SHA256SUMS`:

```bash
curl -fsSL https://github.com/rsuwa/git-pr/releases/latest/download/install.sh |
  env GIT_PR_INSTALL_SHA256="<expected-sha256>" bash
```

Manual install:

```bash
mkdir -p ~/.local/bin
tmp_file=$(mktemp)
tmp_sums=$(mktemp)
curl -fsSL https://github.com/rsuwa/git-pr/releases/latest/download/git-pr \
  -o "$tmp_file"
curl -fsSL https://github.com/rsuwa/git-pr/releases/latest/download/SHA256SUMS \
  -o "$tmp_sums"
expected=$(awk '$2 == "git-pr" { print $1 }' "$tmp_sums")
actual=$(sha256sum "$tmp_file" | awk '{ print $1 }')
[ "$actual" = "$expected" ]
chmod 755 "$tmp_file"
mv "$tmp_file" ~/.local/bin/git-pr
rm -f "$tmp_sums"
```

## Usage

Create or update a pull request for the current branch:

```bash
git pr
```

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

Disable auto-merge:

```bash
git pr auto-merge --disable-auto-merge
```

Update `git-pr` from the latest GitHub release:

```bash
git pr update
```

Print the installed version:

```bash
git pr --version
```

## Remote model

`git-pr` only works with a Git remote named `origin`. It checks for `origin`,
uses the GitHub repository default branch when resolving the default base, and
pushes new branches with `git push -u origin HEAD`. Selecting another remote is
not supported.

## Options

| Option | Description |
| --- | --- |
| `-b, --base <branch>` | Base branch. Defaults to `branch.<name>.gh-merge-base`, then the repository default branch. |
| `-t, --title <title>` | Pull request title. |
| `-d, --body <body>` | Pull request body. |
| `-F, --body-file <path>` | Pull request body file. |
| `-T, --template <path>` | Pull request template file. |
| `-e, --editor` | Open an editor while creating a pull request. |
| `--label <label>` | Add labels. Repeatable and comma-separated values are supported. |
| `--reviewer <user>` | Add reviewers. Repeatable and comma-separated values are supported. |
| `--assignee <user>` | Add assignees. Repeatable and comma-separated values are supported. |
| `--fill`, `--fill-first`, `--fill-verbose` | Use GitHub CLI fill behavior when creating a pull request. On existing PRs, explicitly replace the body with locally generated commit content. |
| `--no-fill` | Do not pass a GitHub CLI fill flag. On create, missing title/body are generated locally from commits; on existing PRs, no title/body update is made unless explicit content is provided. |
| `--no-edit` | Push only; do not update an existing pull request title or body. |
| `-a, --enable-auto-merge` | Enable auto-merge after creating or updating a pull request. |
| `-m, --merge-method <method>` | Auto-merge method: `merge`, `squash`, or `rebase`. |
| `--delete-branch` | Delete the branch after auto-merge. |
| `--admin` | Pass `--admin` to `gh pr merge` for auto-merge. |
| `--match-head-commit <sha>` | Require the pull request head commit to match the given SHA when enabling auto-merge. If omitted, `git-pr` uses the local `HEAD` SHA. |
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
| `--mode <create\|update\|auto>` | `create` generates a new title/body, `update` preserves an existing body and fills missing details, and `auto` chooses based on whether a pull request exists. |
| `--detail <normal\|verbose>` | Controls the generated body detail level. |
| `--language <en\|ja>` | Output language. Defaults to `GIT_PR_LANGUAGE`, then `git-pr.language`, then `en`. |
| `--diff-exclude <path>` | Exclude a path from the diff sent to Copilot. Repeatable. |

Copilot privacy behavior:

- `git-pr` writes temporary prompt, diff, title, and body files in a private
  temp directory outside the repository and removes them when the process exits.
- On Copilot failure or parse failure, debug logs are saved under
  `${XDG_STATE_HOME:-$HOME/.local/state}/git-pr/copilot-logs` by default.
  Set `GIT_PR_COPILOT_LOG` to a non-empty value to keep logs after a successful
  generation.
- Debug logs omit prompt, diff, and response content by default. Set
  `GIT_PR_COPILOT_LOG_CONTENT=1` only when you intentionally want to persist
  that content for debugging.

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
| `GIT_PR_COPILOT_LOG_DIR` | Directory for Copilot debug logs. Default: `${XDG_STATE_HOME:-$HOME/.local/state}/git-pr/copilot-logs`. |
| `GIT_PR_COPILOT_LOG` | Set to a non-empty value to keep Copilot debug logs on success. |
| `GIT_PR_COPILOT_LOG_CONTENT` | Set to a non-empty value to persist prompt, diff, and response content in Copilot debug logs. |
| `GIT_PR_UPDATE_URL` | Override the update URL used by `git pr update`. |
| `GIT_PR_UPDATE_CHECKSUM_URL` | Override the `SHA256SUMS` URL used by `git pr update`. |
| `GIT_PR_UPDATE_SHA256` | Expected SHA256 for the file downloaded by `git pr update`; skips `SHA256SUMS` download when set. |

SHA256 checks use `sha256sum` when available, then `shasum -a 256`.

## Deprecated aliases

These aliases are still accepted for compatibility and may be removed in a
future release:

| Deprecated alias | Use instead |
| --- | --- |
| `--copilot` | `git pr copilot --mode=create` |
| `--copilot-verbose` | `git pr copilot --mode=create --detail=verbose` |
| `--copilot-update` | `git pr copilot --mode=update` |
| `--auto-merge` | `--enable-auto-merge` |
| `git pr merge` | `git pr auto-merge` |

## Existing Pull Requests

When a pull request already exists for the current branch, `git pr` pushes the
branch and updates metadata requested by options. The title is kept unless
`--title` is provided. The body is kept when it is non-empty unless `--fill`,
`--body`, `--body-file`, or `git pr copilot` is explicitly used. If the existing
body is empty, the default `git pr` flow fills it from commits.

Use `--no-edit` to push without editing the pull request.

## License

MIT
