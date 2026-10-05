# Decisions and verification notes

Why flutter-ci works the way it does, and which outside facts it relies on.
Last checked: **2026-10-05**.

## Verified facts

| Topic | Finding | Source |
|---|---|---|
| `secrets: inherit` | Only works when the caller and the reusable workflow are in the same organization or enterprise. Our apps live in different orgs, so every secret is passed by name. | [GitHub: reusing workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows) |
| Reusable workflows across orgs | A repo in another org can call a public reusable workflow if its Actions policy allows it. A new secret in the caller that the called version doesn't declare makes the caller's workflow file **invalid**. | GitHub docs; seen in practice (v1.1.0 rollout) |
| `--build-name 1.4.0-beta.1` | Android keeps it unchanged (an APK showed `versionName='0.1.0-beta.1'`). iOS strips non-digits (it would become `1.4.0.1`, which Apple rejects), so flutter-ci passes `X.Y.Z` on iOS. | `flutter_tools/lib/src/build_info.dart`, local build |
| Xcode Cloud variables | `CI_TAG` (only for tag start conditions), `CI_BUILD_NUMBER`, `CI_COMMIT`, `CI_PRIMARY_REPOSITORY_PATH`, `CI_XCODEBUILD_ACTION` | [Environment variable reference](https://developer.apple.com/documentation/xcode/environment-variable-reference) |
| Xcode Cloud scripts | Only `ci_post_clone.sh`, `ci_pre_xcodebuild.sh` and `ci_post_xcodebuild.sh` in `ci_scripts/` next to the workspace. They run with **zsh** unless the file is executable and has a shebang. No `sudo`. Homebrew is available. | [Writing custom build scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts) |
| Xcode Cloud repo URL | Xcode Cloud uses the repo's `origin` URL. SSH host aliases from `~/.ssh/config` don't work. | seen in practice |
| Xcode menu | In current Xcode, Xcode Cloud is under **Integrate → Create/Manage Workflows**. | seen in practice |
| Play upload | `r0adkll/upload-google-play` v1.1.5 (`e738b9d…`). It applies one `status` to all tracks, and the first upload of a new app must be manual. Draft apps only accept `status: draft`. | [upload-google-play](https://github.com/r0adkll/upload-google-play) |
| Firebase CLI | The standalone binary from `https://firebase.tools/bin/<os>/latest` needs no `sudo`. The upload uses `firebase appdistribution:distribute` with `GOOGLE_APPLICATION_CREDENTIALS`. | [Firebase CLI](https://firebase.google.com/docs/cli) |
| Drive and service accounts | Service accounts have no storage; they can only upload into **Shared Drives** (Google Workspace). | [Shared drives](https://developers.google.com/workspace/drive/api/guides/about-shareddrives) |
| Google OAuth consent screen | External apps in "Testing" get refresh tokens that expire after 7 days. Publishing needs app name, support email, home page, privacy policy and an authorized domain. `drive.file` is a non-sensitive scope (no verification needed). | Google Cloud Console; seen in practice |
| Pinned action SHAs | Read with `git ls-remote`: checkout v7.0.1, setup-java v6.0.1, upload-artifact v7.0.1, flutter-action v2.23.0, action-gh-release v3.0.3, upload-google-play v1.1.5, actionlint v1.7.12 | `git ls-remote` |

## Not verified end to end

| Topic | Assumption | Safety net |
|---|---|---|
| Xcode Cloud clone depth | Probably shallow (Apple's own examples deepen history). | The prod guard fetches the needed history. Tested against a `--depth 1` clone. |
| Play production draft with `[internal, production]` | Uploads once to the testing track, then adds that versionCode to production as a draft through the Play API (retried with `changesNotSentForReview=true` if Play asks). | Clear error and a TROUBLESHOOTING section. Check on the first prod tag. |
| Drive via own account | Refresh token from the OAuth Playground with the project's own Web client; `drive.file` scope. | The folder helper checks the client ID format. Errors show Google's reason. |
| `CI_XCODEBUILD_EXIT_CODE` | Used if present, only for the Slack message. | Harmless if missing. |

## Decisions

1. **Owner:** the repo is `nividata-consultancy/flutter-ci` and public.
2. **bash 3.2:** all scripts run on macOS `/bin/bash`. The tests also run on macOS in self-test.
3. **Builds start only from tags:** `vX.Y.Z-beta.N` builds UAT, `vX.Y.Z` builds prod. The tag
   parser is shared by both platforms.
4. **The prod guard is optional** (`app.prod_branches`). By default, prod tags work on any branch.
5. **All secrets are optional** in `android-release.yml`. Signing is enforced at runtime
   (except dry runs), and destination secrets only when that destination is enabled.
   This keeps self-test working without secrets.
6. **Extra workflow inputs:** `ci-lib-repository` (forks/self-test), `app-directory`
   (monorepos, `example/`), `tag` (simulate a tag, **only with `dry-run: true`**), `timeout-minutes`.
7. **Destinations are switched on explicitly:** every Android destination needs
   `enabled: true|false`.
8. **Platform switches:** `android.enabled` / `ios.enabled` per environment (default `true`).
   A disabled iOS build has to fail visibly, because Xcode Cloud can't skip a started build.
9. **Play tracks:** `[internal]`, `[production]` or `[internal, production]`. Production is
   always a **draft** and only allowed for prod tags. Nothing reaches users without a person
   pressing Release.
10. **iOS goes to TestFlight only.** No Firebase or Drive for iOS, and no TestFlight notes.
11. **Release notes = the tag message** (fallback: commit titles). They go to Firebase and the
    app's GitHub Release only.
12. **iOS uses one scheme (`Runner`).** An optional per-environment name, icon and build
    settings come from a generated `Environment.xcconfig`. Apps with iOS flavor schemes are
    not supported yet.
13. **Drive has two options:** a service account plus a Shared Drive (Workspace), or your own
    Google account plus `drive.file` and a folder created by `scripts/tools/gdrive_create_folder.sh`.
    The Drive API is called directly (curl + openssl), with no rclone.
14. **flutter-ci's own scripts live in `.flutter-ci/`** (sparse checkout of `actions/` and
    `scripts/`), so the workflow, actions and scripts always come from the same version.
15. **The Flutter install on Xcode Cloud never deletes** an existing SDK. If the version
    differs, it stops with an error.
