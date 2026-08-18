# Repository Guidelines

## Project Structure & Module Organization

This repository is a small Bash-based Git subcommand. The canonical development
source is the fixed, manifest-ordered set of fragments in `src/`. The committed
root `git-pr` executable is generated from those fragments and is the standalone
release asset; it must not load repository files at runtime. `install.sh`
handles installation and checksum validation; self-update logic lives in
`src/self-update.bash`.

Source assembly and release tooling live in `script/`:

- `script/build-git-pr` regenerates or checks the committed root executable.
- `script/build-release-assets` stages `git-pr`, `install.sh`, and
  `SHA256SUMS`.
- `script/verify-release-assets` validates checksums and isolated install/update
  flows.
- `script/verify-release-tag` checks that a pushed release tag targets the
  checked-out commit.

Tests live in `test/` and use Bats. Shared fakes and helpers are in
`test/test_helper.bash`; contract files cover CLI flow, argument validation,
external GitHub/Copilot CLI calls, source assembly, releases, install/update,
and UX behavior. GitHub Actions workflows live in `.github/workflows/`.

## Build, Test, and Development Commands

Regenerate the root executable after changing `src/`, then check that the
committed file is current:

```bash
./script/build-git-pr
./script/build-git-pr --check
```

Run the validation suite:

```bash
for script in git-pr install.sh script/build-git-pr script/build-release-assets \
  script/verify-release-assets script/verify-release-tag \
  test/test_helper.bash src/*.bash; do
  bash -n "$script"
done
shellcheck git-pr install.sh script/build-git-pr script/build-release-assets \
  script/verify-release-assets script/verify-release-tag \
  test/test_helper.bash test/*.bats
bats test
```

Exercise the command locally with `./git-pr --help` or
`PATH="$PWD:$PATH" git pr --help`.

There is no compiled build. Source assembly is nevertheless required after an
implementation or version change, and the source fragment plus regenerated
root file must be committed together.

To exercise the release contract, create an empty temporary directory and run:

```bash
release_dir=$(mktemp -d)
./script/build-release-assets "$release_dir"
./script/verify-release-assets "$release_dir"
```

Pass the intended tag as a second verifier argument when preparing a release.
Never stage release assets in the repository root or below `src/`.

## Coding Style & Generated Source

Use Bash with `set -euo pipefail` for executable scripts. Follow the existing
style: two-space indentation, lowercase snake_case function names, `local`
variables inside functions, and explicit error handling through helpers such as
`die`, `log_info`, and `log_warn`. Quote expansions unless word splitting is
intentional. Add ShellCheck disables only when narrowly justified near the
affected block.

Edit implementation code in `src/`, not directly in generated root `git-pr`.
The fixed manifest in `script/build-git-pr` defines both the allowed fragment
set and concatenation order. Run the builder, inspect the generated diff, and
then run `--check` before committing. Keep the root executable standalone; do
not introduce runtime `source src/*.bash` behavior.

## Testing Guidelines

Add or update Bats tests for behavior changes. Name test files by contract area,
for example `test/pr_flow_contract.bats`, and write descriptive `@test` names
that state the expected behavior. Prefer fake Git, GitHub CLI, and Copilot
helpers in `test/test_helper.bash` over real remotes or external requests.

Run tests before and after behavior-preserving refactors. For source assembly,
installer, updater, checksum, or release changes, also build and verify isolated
release assets. The real Copilot smoke test is opt-in and may consume account
quota; run it only when intentionally validating the live Copilot integration.

## Commit & Pull Request Guidelines

Use concise, imperative commit subjects such as `Harden install and update
target handling` and `Fix Copilot CLI streaming contract`. Keep subjects
specific and sentence case; include a PR number only when GitHub adds it during
merge.

Pull requests should explain the behavioral change, why it is needed, tests
run, risks, and rollback. Include terminal output only when CLI text, prompts,
or errors changed. Keep generated `git-pr` synchronized with `src/` in the same
PR. Release PRs must update the canonical version, regenerate `git-pr`, finalize
`CHANGELOG.md`, update versioned README examples, and account for the exact
`git-pr`, `install.sh`, and `SHA256SUMS` asset contract.
