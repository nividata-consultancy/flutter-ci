# Assumptions and verification notes

This file records the decisions made where the brief left room, and the facts
checked against official documentation or real runs. Checked on **2026-10-04**.
Re-check the items marked *unverified* when something behaves differently.

## Verified facts

| Topic | Finding | How verified |
|---|---|---|
| `secrets: inherit` across orgs | Works only when caller and reusable workflow are in the **same organization or enterprise**. Cross-org callers must pass each secret explicitly. A private repo in another org can call a public repo's reusable workflow if its org policy allows public actions/workflows. Secrets only reach the directly called workflow. | [GitHub: Reusing workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows) |
| `flutter build --build-name` with SemVer pre-release | **Android: accepted unchanged.** A dry-run build of `example/` with `--build-name=0.1.0-beta.1` produced `versionName='0.1.0-beta.1' versionCode='7'` (checked with `aapt2 dump badging`, Flutter 3.41.9). **iOS: flutter strips non-digits**, so `1.4.0-beta.1` would become `1.4.0.1`, which App Store Connect rejects. flutter-ci therefore passes `X.Y.Z` on iOS. | `flutter_tools/lib/src/build_info.dart` → `validatedBuildNameForPlatform`, plus a local build |
| Xcode Cloud env vars | `CI_TAG` (only for tag start conditions), `CI_BUILD_NUMBER`, `CI_COMMIT`, `CI_PRIMARY_REPOSITORY_PATH`, `CI_XCODEBUILD_ACTION` (`archive`, `build`, `analyze`, …), and for archive actions `CI_ARCHIVE_PATH`, `CI_AD_HOC_SIGNED_APP_PATH`, `CI_APP_STORE_SIGNED_APP_PATH`, `CI_DEVELOPMENT_SIGNED_APP_PATH`. (`CI_WORKSPACE` is actually `CI_WORKSPACE_PATH`; flutter-ci does not use it.) | [Environment variable reference](https://developer.apple.com/documentation/xcode/environment-variable-reference) |
| Xcode Cloud custom scripts | Only `ci_post_clone.sh`, `ci_pre_xcodebuild.sh` and `ci_post_xcodebuild.sh` at the top of `ci_scripts/`, next to the project/workspace. The default shell is **zsh**, and the shebang is only honored when the file is **executable**. `ci_post_xcodebuild.sh` also runs when xcodebuild fails. No `sudo`. | [Writing custom build scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts) |
| Homebrew on Xcode Cloud | Available. Third-party tools are not preinstalled. flutter-ci installs `yq` and `cocoapods` with `HOMEBREW_NO_AUTO_UPDATE=1`. | [Making dependencies available to Xcode Cloud](https://developer.apple.com/documentation/xcode/making-dependencies-available-to-xcode-cloud) |
| TestFlight "What to Test" file | `TestFlight/WhatToTest.<locale>.txt` in the **same folder as the Xcode project/workspace**, i.e. next to `ci_scripts`. For Flutter that is `ios/TestFlight/WhatToTest.en-US.txt`. Apple's example writes it in `ci_post_xcodebuild.sh`. | [Including notes for testers](https://developer.apple.com/documentation/xcode/including-notes-for-testers-with-a-beta-release-of-your-app) |
| Firebase CLI on CI | Firebase recommends the standalone binary for CI (`curl -sL https://firebase.tools \| bash`). That installer writes to `/usr/local/bin` and Xcode Cloud has no `sudo`, so flutter-ci downloads the binary directly from `https://firebase.tools/bin/<macos\|linux>/latest` (or `v<FIREBASE_TOOLS_VERSION>`) into `~/.flutter-ci/bin`. Upload command: `firebase appdistribution:distribute <file> --app … --groups … --release-notes-file …` with `GOOGLE_APPLICATION_CREDENTIALS`. | [Firebase CLI](https://firebase.google.com/docs/cli), [App Distribution CLI](https://firebase.google.com/docs/app-distribution/android/distribute-cli) |
| Play upload | `r0adkll/upload-google-play` v1.1.5 (`e738b9d…`, node24). Inputs used: `serviceAccountJsonPlainText`, `packageName`, `releaseFiles`, `releaseName`, `track`, `status`, `whatsNewDirectory` (`whatsnew-en-US`), `mappingFile`. The first upload of a new app must be manual. While the app is a draft, only `status: draft` works. | [upload-google-play README](https://github.com/r0adkll/upload-google-play) |
| Drive and service accounts | "Service accounts don't have storage quota … they must upload files and folders into shared drives." flutter-ci calls Drive v3 directly (resumable upload, `supportsAllDrives=true`) with a JWT signed by `openssl`. No rclone needed. | [Shared drives guide](https://developers.google.com/workspace/drive/api/guides/about-shareddrives) |
| Pinned action SHAs | Read with `git ls-remote` (annotated tags peeled): `actions/checkout` v7.0.1 `3d3c42e…`, `actions/setup-java` v6.0.1 `de7274f…`, `actions/upload-artifact` v7.0.1 `043fb46…`, `subosito/flutter-action` v2.23.0 `1a44944…`, `softprops/action-gh-release` v3.0.3 `efb3536…`, `r0adkll/upload-google-play` v1.1.5 `e738b9d…`, actionlint v1.7.12 `914e7df…`. `rhysd/actionlint` has no `action.yml`, so self-test runs its download script. | `git ls-remote` |
| iOS environment wiring | In a fresh `flutter create` project, the Runner target sets `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` at **target level**, which overrides xcconfig values. It must be removed (NEW_PROJECT_SETUP step 5.3). With the setup applied to `example/`, `xcodebuild -showBuildSettings` resolved `APP_DISPLAY_NAME = Example UAT` and `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon-UAT`. `Generated.xcconfig` had `FLUTTER_BUILD_NAME=0.1.0`, `FLUTTER_BUILD_NUMBER=12` and the dart defines. | A local simulation of `post_clone.sh` with `CI_*` variables |

## Unverified / inferred

| Topic | Assumption | Mitigation |
|---|---|---|
| Xcode Cloud clone depth | Not documented. Apple's own WhatToTest sample runs `git fetch --deepen`, which suggests the clone is **shallow**, and tags other than the triggering one may be missing. | The prod guard unshallows from `origin` when `git rev-parse --is-shallow-repository` is true and fetches the prod branch explicitly. Release notes deepen by 50 commits, best effort. This was tested against a `--depth 1` clone locally. |
| `origin` fetch credentials on Xcode Cloud | Assumed: `git fetch origin` works inside the build because Xcode Cloud's GitHub app has repo access. | If it fails, the prod guard stops with "could not fetch history" and a doc link. |
| When `CI_AD_HOC_SIGNED_APP_PATH` is set | Apple lists it under archive actions without saying which Distribution Preparation produces it. | `post_xcodebuild.sh` checks that the path exists and otherwise logs an error that doesn't fail the build (TestFlight still proceeds). `FLUTTER_CI_STRICT=1` makes it fatal. Confirm on the first app that uses iOS Firebase/Drive. |
| `CI_XCODEBUILD_EXIT_CODE` | Used if present, to skip uploads after a failed archive. Not found in the reference. | If absent, a failed archive produces no IPA, so uploads are skipped anyway. |
| WhatToTest size limit | The brief requires < 1 KB. App Store Connect's field limit is 4,000 characters (not stated on Apple's page). | Notes are capped at 1,000 bytes, with valid UTF-8 kept. |
| Firebase role name | "Firebase App Distribution Admin". The page did not render during verification. | Documented in SECRETS.md. The error message points to it. |

## Design decisions (where the brief left room)

1. **Repository owner** is `nividata-consultancy` (public repo `nividata-consultancy/flutter-ci`). MAINTAINING.md explains how to change it if the repo moves.
2. **bash 3.2 compatibility** is treated as a hard requirement, because Xcode Cloud runs macOS `/bin/bash`. All scripts use `#!/bin/bash`, and the bats suite also runs on macOS.
3. **All secrets in `android-release.yml` are `required: false`**, including the keystore. This lets `self-test.yml` run a dry-run build of `example/` without secrets (forks have none). The workflow enforces the keystore secrets at runtime unless `dry-run: true`, and enforces destination secrets only for configured destinations, each with a pointer to SECRETS.md.
4. **Extra workflow inputs beyond the brief:** `ci-lib-repository` (forks and self-test of PRs from forks), `app-directory` (monorepos and `example/`), `tag` (simulate a tag, **only honored with `dry-run: true`**, so it cannot bypass the tag-only rule), and `timeout-minutes`.
5. **Extra config keys beyond the starting schema:**
   - `app.android_package_name`: needed by the Play upload. Not stored in this repo.
   - `app.github_release.{enabled,attach_artifacts}`: release creation defaults on, attaching artifacts defaults off.
   - `destinations.playstore.status`: `completed`/`draft`, for apps still in draft.
   - `destinations.firebase.testers`.
   - `ios.build_settings` and `ios.target`.
   - The `production` Play track is **rejected**, because CI never releases to production.
6. **`scripts/android/`** was added next to `scripts/common` and `scripts/xcode-cloud`, so composite actions stay thin and the logic is shellcheck-able.
7. **`scripts/common/context.sh`** turns tag, config and Flutter version into one set of values for both platforms. This keeps config reading in one place.
8. **Java + Flutter setup** live in one composite action, `setup-flutter`. Gradle caching uses `actions/setup-java`'s `cache: gradle` instead of a separate `actions/cache` step.
9. **`.flutter-ci/` is a sparse checkout** (`actions/`, `scripts/` only). This stops `flutter analyze` in the app from picking up `example/`. It is also added to `.git/info/exclude`.
10. **Release notes:** Play gets ≤500 bytes (Play's limit), Firebase gets the same short notes, the GitHub Release gets up to 4 KB, and TestFlight ≤1,000 bytes. Commits are listed since the previous tag; prod compares with the previous **prod** tag.
11. **Destination failures on iOS don't fail the build by default** (so TestFlight is never blocked by Drive/Firebase). On Android they do fail the job, because there is no later step they could block.
12. **Tests and analyze run on GitHub only.** iOS does not repeat them.
13. **Android artifacts are named** `<App>-<env>-<versionName>-<versionCode>.{aab,apk}`, plus `-mapping.txt` and `-debug-symbols.zip` when available.
14. **The Flutter install on Xcode Cloud never deletes** an existing SDK directory. If `~/flutter` exists with a different version, the build stops with an error.
15. **Tagging `v1.0.0` / `v1`:** created locally only; push them when the remote is reachable.
16. **Prod guard is opt-in** (changed on request): prod tags build from any branch unless `app.prod_branches` is set.
17. **Release notes come from the annotated tag message** (requested), with commit subjects as fallback, and go to **Firebase App Distribution only**. Play gets no "What's new" text and TestFlight gets no "What to Test" file. The GitHub Release on the app repo keeps the notes for developers. On GitHub the tag object is re-fetched with the job token, because `actions/checkout` may store tags as lightweight refs and credentials are not persisted.
18. **iOS goes to TestFlight only** (requested). The iOS `firebase`/`drive` destinations and the TestFlight `[UAT]`/`[PROD]` label were removed. The "ad hoc IPA" and "WhatToTest" rows above are kept for reference only. UAT and prod builds are told apart by name and icon, and by the tag in Xcode Cloud → Builds.
19. **Play production draft** (requested): `playstore.tracks` lists `[internal]`, `[production]` or both (production only in the prod environment, always `status: draft`). `[production]` alone uploads the AAB straight to production as a draft with `upload-google-play`. `[internal, production]` uploads once to the testing track, then adds that same versionCode to the production track with `status: draft` through the Play Developer API (edits → tracks.update → commit, retried with `changesNotSentForReview=true` if Play asks for it). `upload-google-play` was not used for this because it applies one status to all tracks, and uploading the same AAB twice would be rejected. *Unverified on a live app*: confirm on the first prod tag.
