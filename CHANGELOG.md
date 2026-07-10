# Changelog

## Unreleased

- Refactor global option initialization, repository context loading, and PR flow
  state boundaries without changing the CLI contract.

## 0.3.5 - 2026-07-09

- Fix default branch discovery with current GitHub CLI by using the supported
  positional repository argument for `gh repo view`.
- Keep `git pr` usable without `--base` when no branch `gh-merge-base` is set
  and `origin/HEAD` is unavailable.
- Add parser boundary characterization tests and split argument parsing helpers
  without changing the CLI contract.

## 0.3.4 - 2026-07-09

- Refactor origin URL parsing, option parsing, and PR flow runner boundaries
  without changing the CLI contract.
- Revalidate newly discovered existing pull requests after push before
  applying create-only or Copilot create-mode behavior.
- Fail local `--body-file` and create-mode `--template` validation earlier,
  before avoidable GitHub/default-branch/fetch work.
- Suppress raw parser file errors when Copilot returns a marked response with
  an empty body.
- Document `--template` support for Copilot create mode in help and README.

## 0.3.3 - 2026-07-08

- Harden base branch fetches by validating branch names and using explicit
  remote refspecs.
- Push the current branch with an explicit `HEAD:refs/heads/<branch>` refspec.
- Reject unsafe GitHub repository owner and name path parts parsed from
  `origin`.
- Fall back to GitHub CLI fill mode when Copilot prompt preparation fails.
- Extract main PR flow helpers without changing the CLI contract.

## 0.3.2 - 2026-07-07

- Add `git pr doctor` to check required GitHub CLI setup, with optional
  Copilot CLI executable checks via `--with-copilot`.
- Document GitHub CLI and Copilot CLI setup paths, and improve dependency
  failure guidance.
- Reject unsafe GitHub remote hostnames before using them in GitHub CLI auth
  guidance.

## 0.3.1 - 2026-07-07

- Clarify `git pr merge` messaging and documentation around merge queues and
  admin bypass behavior.

## 0.3.0 - 2026-07-06

- Remove deprecated option aliases: `--copilot`, `--copilot-verbose`,
  `--copilot-update`, and `--auto-merge`.
- Change `git pr merge` from a deprecated alias for `git pr auto-merge` into a
  separate merge request command. It now calls `gh pr merge` without `--auto`
  while keeping the existing merge method and head-SHA safety checks. Use
  `git pr auto-merge` for the old auto-merge behavior.

## 0.2.1 - 2026-07-06

- Redact credentials and query strings in more install/update/remote failure
  messages, and let `git pr update` target the invoked executable or an
  explicit `GIT_PR_UPDATE_INSTALL_PATH`.
- Reject unsafe `git-pr` auto-merge use of `--admin`, warn for the deprecated
  `git pr merge` alias, and clarify that GitHub CLI may merge or enqueue when
  auto-merge requirements are already met.
- Validate explicit existing-PR base retargets against `origin` before pushing.
- Refuse Copilot prompt generation before pushing when temporary files cannot
  be secured, and skip Copilot debug logs when the log directory cannot be made
  private.
- Run CI on Linux and macOS, shellcheck Bats files, and smoke-test release-style
  install/update assets before publishing releases.
- Fix Bash 3.2 empty-array handling for macOS compatibility.
- Document release asset requirements, `latest` URL tradeoffs, and pinned-tag
  install/update examples.
- Fix the real Copilot CLI noninteractive prompt contract by avoiding truncated
  `--stream off` output and tightening the opt-in smoke test.

## 0.2.0 - 2026-07-06

- Add `git pr --version`.
- Require SHA256 verification for `install.sh` and `git pr update` using
  release `SHA256SUMS` by default, with direct SHA overrides for mirrors/tests.
- Avoid unsafe existing-PR body overwrites, validate more inputs before push,
  and fail on GitHub CLI query/auth errors instead of treating them as no PR.
- Use Copilot triple-dot diffs, private temp files, safer debug logs, and
  mode-aware Copilot update fallback.
- Guard auto-merge with `--match-head-commit` by default.
- Document the origin-only remote model, Copilot temp/log privacy behavior,
  auto-merge contract flags, `--no-fill`, update/install environment variables,
  and deprecated aliases.

## 0.1.0

- Initial public release.
- Add `git pr`, `git pr auto-merge`, `git pr copilot`, and `git pr update`.
- Add configurable Copilot language and diff excludes.
