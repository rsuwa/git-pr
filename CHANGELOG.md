# Changelog

## Unreleased

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
