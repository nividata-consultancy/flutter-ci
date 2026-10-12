# Maintaining flutter-ci

Every app runs this code on every release, so change it carefully.

## Rules

- The repo is **public**: never commit secrets, client names, bundle IDs or internal URLs.
- Scripts must run on **/bin/bash 3.2** (macOS / Xcode Cloud). Don't use `mapfile`,
  associative arrays, `${var,,}`, or `"${empty[@]}"` under `set -u`. Use
  `${arr[@]+"${arr[@]}"}` instead.
- Use `set -euo pipefail` and shellcheck-clean code, never `set -x`, and pass secrets
  through env vars, not arguments.
- Errors use `die "what happened and what to do" "TROUBLESHOOTING.md#section"`. The
  section must exist.
- Builds may only create these files in the app: `.flutter-ci/` and
  `android/key.properties` (deleted after the build).
- New config keys, inputs and secrets must be **optional**. A new required one is a
  breaking change (see [Versions](#versions)).

## Local checks

```bash
brew install bats-core shellcheck actionlint yq    # once
bats tests/                                        # read the WHOLE output, not just the last line
git ls-files '*.sh' | xargs shellcheck -x
actionlint
```

`self-test.yml` runs the same on every push and PR (Linux and macOS), plus a dry-run
Android build of `example/` through `android-release.yml` at that commit.

## Versions

- Releases are `vX.Y.Z`, each with a section in [CHANGELOG.md](../../CHANGELOG.md).
- The **major tag** `v2` points to the newest `v2.x.y`. Every app tracks it
  (`@v2` + `ci-lib-ref: v2`, and `FLUTTER_CI_REF=v2`). `v1` stays where it is.
- **Non-breaking** changes (fixes, new *optional* keys, inputs or secrets) ship as `v2.x.y`.
- **Breaking** changes ship as `v3.0.0`: a new required input/secret/key, a config
  schema change, a different tag format, or anything removed or renamed. Add a
  [Migrations](#migrations) entry.

## Releasing

1. Commit with a `## [X.Y.Z] - YYYY-MM-DD` section in `CHANGELOG.md`, and push `main`.
2. Wait until **self-test** on that commit is green:
   `gh run list -R nividata-consultancy/flutter-ci --workflow self-test.yml --limit 1`.
3. Optional: check on a canary app (below).
4. Tag the same commit and push the tag:
   ```bash
   git tag -a v2.0.1 -m "flutter-ci v2.0.1" && git push origin v2.0.1
   ```
5. `release.yml` checks the tag (on `main`, has a changelog section, newest `v2.x.y`),
   creates the GitHub Release and moves `v2`. From then on, every app's next build uses it.

**Rollback:** `git tag -f v2 v2.0.0 && git push -f origin v2`, then fix forward with a new version.

## Canary apps

One or two internal apps can run ahead of everyone else:
- GitHub: `uses: nividata-consultancy/flutter-ci/.github/workflows/android-release.yml@main`
  with `ci-lib-ref: main`
- Xcode Cloud: `FLUTTER_CI_REF=main`

After merging to `main`, push a beta tag on a canary app, check both platforms, and only
then release.

## Updating pinned actions

Third-party actions are pinned to full commit SHAs, with the version as a comment. To update:
```bash
git ls-remote https://github.com/actions/checkout 'refs/tags/v7.0.2' 'refs/tags/v7.0.2^{}'
```
Use the last SHA (the `^{}` one for annotated tags), update the comment, and read the
action's changelog for input changes. The `actionlint` version in `self-test.yml` is
pinned the same way.

## Moving the repository

The owner `nividata-consultancy` appears in the workflow, the bootstraps, the templates
and the doc links. If the repo moves:
```bash
git grep -l 'nividata-consultancy/flutter-ci' | xargs sed -i '' 's#nividata-consultancy/flutter-ci#new-owner/flutter-ci#g'
```
Then update every app's `uses:` line.

## Migrations

Breaking changes, newest first, with the exact steps for app repos. Use this format:

```
### v1 → v2
- What changed and why.
- App repo changes:
  1. .github/workflows/release.yml: @v1 → @v2, ci-lib-ref: v2, …
  2. Xcode Cloud: FLUTTER_CI_REF=v2
  3. .ci/config.yaml: …
```

### v1 → v2
- `environments.<env>.dart_define_file` was removed. Flutter build flags, including the
  dart defines file, now go in the new `environments.<env>.build_args` list (Android
  and iOS). The `DART_DEFINES_<ENV>_JSON` / `_JSON_BASE64` secrets are no longer read:
  the JSON must be committed. A v2 build with `dart_define_file` still in the config
  fails, and the error shows the replacement line.
- App repo changes:
  1. `.ci/config.yaml`, under each environment: replace
     `dart_define_file: env/uat.json` with
     `build_args: ["--dart-define-from-file=env/uat.json"]`. Add other flags to the same
     list, e.g. `"--no-tree-shake-icons"`.
  2. If the defines lived only in the `DART_DEFINES_*` secrets: commit them as
     `env/uat.json` / `env/prod.json`.
  3. `.github/workflows/release.yml`: `@v1` → `@v2`, `ci-lib-ref: v2`, and delete the
     `DART_DEFINES_UAT_JSON` / `DART_DEFINES_PROD_JSON` lines.
  4. Xcode Cloud, every workflow: `FLUTTER_CI_REF` = `v2`; delete
     `DART_DEFINES_UAT_JSON_BASE64` / `DART_DEFINES_PROD_JSON_BASE64`.
  5. GitHub → Settings → Secrets: delete `DART_DEFINES_UAT_JSON` / `DART_DEFINES_PROD_JSON`.
