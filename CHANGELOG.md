# Changelog

## Unreleased

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
