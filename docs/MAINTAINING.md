# Maintaining flutter-ci

Every app runs this code on every release, so changes need care.

## Before you change anything

- Never commit secrets, client names, bundle IDs or internal URLs. The repo is public.
- Scripts must run on **/bin/bash 3.2** (Xcode Cloud / macOS). Don't use `mapfile`,
  associative arrays, `${var,,}` or `"${empty[@]}"` under `set -u`. Use
  `${arr[@]+"${arr[@]}"}`. The macOS bats job in `self-test.yml` catches most of this.
- Use `set -euo pipefail`, keep scripts shellcheck-clean, and never `set -x`. Pass
  secrets through env vars, not arguments.
- Errors go through `log_error` / `die` with a doc anchor:
  `die "what happened and what to do" "TROUBLESHOOTING.md#section"`.
- Scripts may only create the generated files listed in the README:
  `.flutter-ci/`, `ios/Flutter/Environment.xcconfig`, `ios/TestFlight/`,
  `ios/Runner/GoogleService-Info.plist`, and `android/key.properties` (removed after the build).

## Local checks

```bash
brew install bats-core shellcheck actionlint yq
bats tests/
git ls-files '*.sh' | xargs shellcheck -x
actionlint
```

`self-test.yml` runs the same checks on every PR, on Linux and macOS, and then a
dry-run Android build of `example/` through `android-release.yml` at the PR's commit.

## Versioning

- Releases are `vX.Y.Z` with an entry in [CHANGELOG.md](../CHANGELOG.md).
- The **major tag** `v1` always points to the newest `v1.x.y`. All apps track it
  (`@v1`, `ci-lib-ref: v1`, `FLUTTER_CI_REF=v1`).
- **Non-breaking** changes (fixes, new optional config keys, new optional inputs or
  secrets) ship as `v1.x.y`.
- **Breaking** changes ship as `v2.0.0`. A change is breaking if it adds a new
  required input or secret, bumps the config schema version, changes the tag convention,
  or removes or renames anything callers use. Add a [Migrations](#migrations) entry.

## Releasing

1. Merge to `main` with `self-test` green.
2. Validate on canary apps (below).
3. Add a `## [X.Y.Z] - YYYY-MM-DD` section to `CHANGELOG.md` and merge it.
4. Tag and push:
   ```bash
   git checkout main && git pull
   git tag v1.3.0 && git push origin v1.3.0
   ```
5. `release.yml` checks that the tag is on `main`, that the changelog has the
   section and that it is the newest `v1.x.y`. It then creates the GitHub Release
   and moves `v1` to it. From that moment, every app's next build uses it.

**Rollback:** move `v1` back with `git tag -f v1 v1.2.9 && git push -f origin v1`.
Then fix forward with `v1.3.1`.

## Canary practice

One or two internal apps run ahead of everyone else:

- GitHub: `uses: OWNER/flutter-ci/.github/workflows/android-release.yml@main` with
  `ci-lib-ref: main`.
- Xcode Cloud: `FLUTTER_CI_REF=main`.

After merging to `main`, push a beta tag on each canary app and confirm that both
platforms reach Play internal and TestFlight. Only then tag a release and move `v1`.

## Updating pinned actions

Third-party actions are pinned to full commit SHAs with a version comment.
To update one:

```bash
git ls-remote https://github.com/actions/checkout 'refs/tags/v7.0.2' 'refs/tags/v7.0.2^{}'
```

Use the last SHA (the peeled one, `^{}`, for annotated tags) and update the
comment. Check the action's changelog for breaking input changes. The
`actionlint` version in `self-test.yml` is pinned the same way.

## Replacing `OWNER`

The code uses the placeholder `OWNER` for the GitHub owner of this repository.
After forking or publishing, replace it everywhere in one go:

```bash
git grep -l 'OWNER/flutter-ci' | xargs sed -i '' 's#OWNER/flutter-ci#your-org/flutter-ci#g'   # macOS sed
```

## Migrations

Breaking changes are listed here, newest first, with exact steps for app repos.

### Template for a new entry

```
### v1 → v2
- What changed and why.
- App repo changes: …
  1. .github/workflows/release.yml: `@v1` → `@v2`, `ci-lib-ref: v2`, new secret X.
  2. Xcode Cloud: FLUTTER_CI_REF=v2.
  3. .ci/config.yaml: `version: 2`, rename key a → b.
- Apps can move one at a time; v1 keeps working (fixes only) until <date>.
```

There are no migrations yet. v1 is the first major version.
