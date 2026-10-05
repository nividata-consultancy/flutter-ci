# flutter-ci docs

flutter-ci holds the CI/CD logic for all our Flutter apps. Each app keeps only a
few small files that call into this repository, so a fix made here reaches every app.

| I want to… | Read |
|---|---|
| Set up CI for a new app | [NEW_PROJECT_SETUP.md](NEW_PROJECT_SETUP.md) |
| Set up the Xcode Cloud workflow (iOS) | [XCODE_CLOUD_SETUP.md](XCODE_CLOUD_SETUP.md) |
| Create the keys and secrets (Play, Firebase, Drive, signing) | [SECRETS.md](SECRETS.md) |
| Look up a setting in `.ci/config.yaml` | [CONFIG_REFERENCE.md](CONFIG_REFERENCE.md) |
| Cut a UAT or prod build, or release to the store | [TAGGING_AND_RELEASES.md](TAGGING_AND_RELEASES.md) |
| Fix a failing build | [TROUBLESHOOTING.md](TROUBLESHOOTING.md) |
| Change or release flutter-ci itself | [MAINTAINING.md](MAINTAINING.md) |
| See what was decided or verified, and why | [ASSUMPTIONS.md](ASSUMPTIONS.md) |

## How it works

```
 app repo                                         nividata-consultancy/flutter-ci (public)
 ────────                                         ────────────────────────────────────────
 git push origin v1.4.0-beta.1
   │
   ├─ GitHub Actions: .github/workflows/release.yml
   │     uses: …/flutter-ci/.github/workflows/android-release.yml@v1 ──► reusable workflow
   │     (secrets passed one by one)                                    ├ reads the tag + .ci/config.yaml
   │                                                                    ├ builds the AAB / APK
   │                                                                    └ sends it where enabled: Play, Firebase, Drive
   │
   └─ Xcode Cloud workflow (Tag Changes "v…", Archive Runner)
         ios/ci_scripts/ci_post_clone.sh (10 lines) ── downloads flutter-ci@v1 ──► scripts/xcode-cloud/post_clone.sh
         xcodebuild archive
         TestFlight internal testing (post-action)
```

**Tags decide everything:**

| Tag | Environment |
|---|---|
| `v1.4.0-beta.1` | UAT |
| `v1.4.0` | prod |

Both platforms use the same tag parser (`scripts/common/parse_tag.sh`).

**The config decides where builds go.** On Android, each destination has an
`enabled: true/false` switch, and Play has `tracks` (internal testing and/or a draft
production release). iOS always goes to TestFlight. Each platform can be turned off
per environment with `android.enabled` / `ios.enabled`.

**Nothing reaches real users automatically.** Play production releases are created
as drafts, and App Store submission is always manual.

**Release notes:** the message of the tag (`git tag -a … -m "…"`) becomes the release
notes in Firebase App Distribution and in the app repo's GitHub Release.

### Why the workflow checks out flutter-ci into `.flutter-ci/`

In a reusable workflow, `uses: ./actions/foo` resolves against the **caller's**
repository, not against flutter-ci. So `android-release.yml` checks out flutter-ci at
the `ci-lib-ref` input into `.flutter-ci/`, keeping only `actions/` and `scripts/`.
It then uses `./.flutter-ci/actions/...` and `./.flutter-ci/scripts/...`.

Keep `ci-lib-ref` equal to the `@ref` in the `uses:` line, so the workflow, its actions
and its scripts always come from the same version. `.flutter-ci/` is added to
`.git/info/exclude`, so it never shows up as a change.

### Versions of flutter-ci

Apps use the major tag `v1`: `@v1` on GitHub, `FLUTTER_CI_REF=v1` on Xcode Cloud.
`v1` always points to the newest `v1.x.y`, so fixes reach every app automatically.
Breaking changes would come as `v2` ([MAINTAINING.md](MAINTAINING.md)).

## Repository layout

```
.github/workflows/android-release.yml   reusable Android workflow (what apps call)
.github/workflows/self-test.yml         CI for this repo (lint, tests, dry-run build of example/)
.github/workflows/release.yml           releases flutter-ci and moves the v1 tag
actions/                                small GitHub actions used by android-release.yml
scripts/common/                         shared by GitHub and Xcode Cloud (tag, config, uploads, notes)
scripts/android/                        GitHub-only steps (signing, build, Play, summary)
scripts/xcode-cloud/                    post_clone.sh, post_xcodebuild.sh
scripts/tools/                          helpers you run on your Mac (gdrive_create_folder.sh)
templates/                              files copied into each app repo
tests/                                  bats tests
example/                                small Flutter app used by self-test
```
