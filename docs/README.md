# flutter-ci docs

flutter-ci is the shared CI/CD library for our Flutter apps. Each app keeps a
few tiny files that call into this repository, so a fix made here reaches every
app.

| I want to… | Read |
|---|---|
| Set up CI for a new app | [NEW_PROJECT_SETUP.md](NEW_PROJECT_SETUP.md) |
| Configure the Xcode Cloud workflow | [XCODE_CLOUD_SETUP.md](XCODE_CLOUD_SETUP.md) |
| Cut a UAT or prod build, or promote to the store | [TAGGING_AND_RELEASES.md](TAGGING_AND_RELEASES.md) |
| Create the secrets | [SECRETS.md](SECRETS.md) |
| Look up a config key | [CONFIG_REFERENCE.md](CONFIG_REFERENCE.md) |
| Fix a failing build | [TROUBLESHOOTING.md](TROUBLESHOOTING.md) |
| Change or release flutter-ci | [MAINTAINING.md](MAINTAINING.md) |
| See what was assumed or verified | [ASSUMPTIONS.md](ASSUMPTIONS.md) |

## How it works

```
 app repo (any GitHub org)                          OWNER/flutter-ci (public)
 ─────────────────────────                          ─────────────────────────
 git push origin v1.4.0-beta.1
   │
   ├─ GitHub Actions: .github/workflows/release.yml
   │     uses: OWNER/flutter-ci/.github/workflows/android-release.yml@v1 ──► reusable workflow
   │     secrets passed one by one                                           ├ checks out flutter-ci@ci-lib-ref → .flutter-ci/
   │                                                                         ├ scripts/common: tag, config, prod guard
   │                                                                         ├ build AAB/APK
   │                                                                         └ Play internal / Firebase / Drive / GitHub Release
   │
   └─ Xcode Cloud (Tag Changes "v*", Archive Runner)
         ios/ci_scripts/ci_post_clone.sh  (≈10 lines) ── downloads flutter-ci@FLUTTER_CI_REF ─► scripts/xcode-cloud/post_clone.sh
         xcodebuild archive
         ios/ci_scripts/ci_post_xcodebuild.sh ─────────────────────────────────────────────► scripts/xcode-cloud/post_xcodebuild.sh
         TestFlight internal testing (post-action)
```

- **Tags drive everything.** `vX.Y.Z-beta.N` builds UAT and `vX.Y.Z` builds prod. One
  parser, `scripts/common/parse_tag.sh`, serves both platforms.
- **Same app ID for UAT and prod.** Everything goes to testing tracks first (Play
  internal, TestFlight). Promotion to production is manual.
- **The repo is public** because the apps live in different GitHub organizations
  and Apple teams. It holds no secrets, client names, bundle IDs or internal URLs.

### Why the workflow checks out flutter-ci into `.flutter-ci/`

In a reusable workflow, `uses: ./actions/foo` resolves against the **caller's**
repository, not against flutter-ci. `android-release.yml` therefore checks out
`OWNER/flutter-ci` at the `ci-lib-ref` input into `.flutter-ci/` (sparse: only
`actions/` and `scripts/`) and uses `./.flutter-ci/actions/...` and
`./.flutter-ci/scripts/...`. Keep `ci-lib-ref` equal to the `@ref` in the `uses:`
line, so that the workflow, its actions and its scripts always come from the same version.
`.flutter-ci/` is added to `.git/info/exclude` so it never shows up as a change.

### How iOS environments work

An Xcode Cloud workflow builds one fixed scheme, and one tag-triggered workflow
serves both UAT and prod. flutter-ci therefore does **not** use iOS flavors or schemes. It
always archives `Runner` and applies the environment before `xcodebuild`:

- `--dart-define-from-file` with the environment's JSON. It is baked into
  `ios/Flutter/Generated.xcconfig` by `flutter build ios --config-only`.
- `ios/Flutter/Environment.xcconfig` (generated, not committed) sets
  `APP_DISPLAY_NAME`, `ASSETCATALOG_COMPILER_APPICON_NAME` and any extra
  `build_settings`. `Release.xcconfig` includes it.
- The environment's `GoogleService-Info.plist` is copied into `ios/Runner/`.

Android can use Gradle `productFlavors` (`android.flavor`) or no flavor at all.

## Repository layout

```
.github/workflows/android-release.yml   reusable Android workflow (entry point)
.github/workflows/self-test.yml         CI for this repo
.github/workflows/release.yml           releases flutter-ci, moves v1
actions/                                composite actions used by android-release.yml
scripts/common/                         shared by GitHub and Xcode Cloud (tag, config, guard, notes, uploads)
scripts/android/                        GitHub-only steps (resolve, signing, build, summary)
scripts/xcode-cloud/                    post_clone.sh, post_xcodebuild.sh
templates/                              files copied into each app repo
tests/                                  bats tests
example/                                minimal Flutter app used by self-test (dry run)
```
