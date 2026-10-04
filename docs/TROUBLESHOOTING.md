# Troubleshooting

Every flutter-ci error links to a section here. Errors look like
`::error::…` on GitHub (shown as an annotation) and `ERROR: …` in Xcode Cloud logs.

## Scripts not found or not executable

**Symptoms (Xcode Cloud):** the scripts don't run at all, `zsh` errors appear about
`[[`, `permission denied`, or `ci_post_clone.sh did not finish`.

- The scripts must be at `ios/ci_scripts/ci_post_clone.sh` and
  `ios/ci_scripts/ci_post_xcodebuild.sh`, next to `Runner.xcworkspace`, with these exact names.
- They must be **executable in git**. Without the bit, Xcode Cloud runs them with zsh:
  ```bash
  git update-index --chmod=+x ios/ci_scripts/ci_post_clone.sh ios/ci_scripts/ci_post_xcodebuild.sh
  git commit -m "Make ci_scripts executable"
  git ls-files -s ios/ci_scripts   # both lines must start with 100755
  ```
- `curl: (22) … 404` while downloading flutter-ci means `FLUTTER_CI_REF` names a
  ref that doesn't exist (e.g. a typo, or a tag not pushed yet).
- `ci_post_clone.sh did not finish` in the post-xcodebuild step means the clone
  step failed earlier. Scroll up to the first `ERROR:`.

## yq missing

`scripts/common/read_config.sh` needs [mikefarah/yq](https://github.com/mikefarah/yq) v4.
It is preinstalled on `ubuntu-latest`. On Xcode Cloud it is installed with
Homebrew. If Homebrew fails, retry the build. A Python `yq` (kislyuk) on PATH is
not compatible.

## Pod install fails

- `CocoaPods could not find compatible versions`: run `pod repo update` locally,
  commit `ios/Podfile.lock`, and make sure the iOS deployment target in `ios/Podfile`
  matches the plugins. The script already retries once with `--repo-update`.
- `Generated.xcconfig must exist`: `flutter build ios --config-only` failed earlier.
  Check the log above it.
- Apps on Swift Package Manager without an `ios/Podfile` skip this step.

## Flutter version mismatch

- `Could not find the Flutter version`: add `.fvmrc` or `environment.flutter`. See
  [CONFIG_REFERENCE.md](CONFIG_REFERENCE.md#flutter-version).
- `must be an exact release`: replace ranges like `>=3.22.0` with `3.24.5`.
- `Could not clone Flutter X`: the version must be a tag in flutter/flutter
  (see the [Flutter release archive](https://docs.flutter.dev/release/archive)).
- Local build works but CI fails with Dart SDK errors: your local Flutter is not
  the pinned one. Run `fvm use` or update the pin.
- Xcode Cloud: an old Xcode version selected in the workflow can be too old for
  newer Flutter. Raise it in the workflow's Environment.

## versionCode already used

`APK specifies a version code that has already been used` (Play).

- The versionCode is `github.run_number + build_number_offset`. For an app that
  was uploaded before flutter-ci, raise `app.build_number_offset` above the highest
  existing versionCode.
- **Re-running** a GitHub workflow keeps the same run number. Push a new tag instead,
  e.g. `v1.4.0-beta.2`.
- Renaming or recreating the caller workflow file resets `run_number`. Raise the
  offset accordingly.

## Prod guard rejected

`Prod guard: commit abc1234 is not on any prod branch (main)`.

This only happens when the app sets `app.prod_branches`. Prod tags (`vX.Y.Z`)
must then point to a commit that is already on one of those branches. To allow
prod tags from any branch, remove `prod_branches` from `.ci/config.yaml`.

```bash
git push --delete origin v1.4.0 && git tag -d v1.4.0
# merge the change into main, then:
git checkout main && git pull && git tag v1.4.0 && git push origin v1.4.0
```

- `none of the prod branches … exist`: check the branch names in `prod_branches`.
- `could not fetch history … (shallow clone)`: Xcode Cloud could not fetch from
  `origin`. Check that the Xcode Cloud GitHub app still has access to the repository.
- For hotfix branches, add them to `prod_branches`.

## Drive upload fails

`Drive: no answer from Google while starting the upload / sending the file (HTTP 000)`
means the connection failed. The message includes curl's own error:

- `Could not resolve host` / `Connection timed out`: a temporary network problem
  on the runner. The script already retries 3 times; push a new tag to try again.
- `Operation timed out` while sending the file: the upload took longer than 30
  minutes. Upload only the APK by setting `artifacts: [apk]`, or check the runner's network.
- `URL rejected` / `No URL set`: Google returned no upload address. Report it with the log.

Other `Drive: upload failed (HTTP 4xx/5xx …)` messages include Google's reason.
`401`/`403` usually means the token or the folder permissions; see below.

## Drive: storage quota exceeded

`Drive: storage quota exceeded` / `storageQuotaExceeded` / `notFound` / `invalid_grant`.

- **Service account (`GDRIVE_SERVICE_ACCOUNT_JSON`):** service accounts have no
  storage of their own. The folder must be **inside a Shared Drive**, and the
  service account must be a member of it (Content manager). A My Drive folder
  shared with the service account is **not** enough. If you have no Shared Drive,
  use your own account instead (Option B).
- **Your own account (`GDRIVE_OAUTH_*`):** `storageQuotaExceeded` means that
  account's Drive is full. `notFound` usually means the folder was created by hand. With the
  `drive.file` scope CI only sees folders it created, so create the folder with
  `scripts/tools/gdrive_create_folder.sh`. It can also mean the folder ID is wrong. `invalid_grant`
  means the refresh token expired or was revoked (or the consent screen is still
  in "Testing", where tokens last 7 days). Create a new one.

See [SECRETS.md](SECRETS.md#google-drive) for both options.

## First Play upload

Google Play's API cannot upload the first build of a new app (`Package not
found: com.example.app`). Do it once by hand:

1. Build locally with `flutter build appbundle --release`, signed with the upload key.
2. Play Console → your app → Testing → Internal testing → Create new release →
   upload the AAB → save and roll out.
3. Complete the app content questionnaires if Play asks for them.

While the app itself is still a **draft** in Play Console (never published to any
track), uploads fail with `Only releases with status draft may be created on draft app`.
Set `playstore: { track: internal, status: draft }` until the first release is out,
then remove `status`.

## Play production draft fails

`Play production draft: … (HTTP 403)`: the Play service account needs the
*Release to production…* permission for this app (see [SECRETS.md](SECRETS.md#google-play)).

`… (HTTP 400/409)`: the production track already has a draft or an in-review
release that conflicts. Open Play Console → Production, finish or discard it, then
push a new tag. While the app is still a **draft app**, production releases are not
possible yet. Remove `production` from `playstore.tracks` until the first release is published.

## Firebase upload fails

- `403` / `PERMISSION_DENIED`: the service account needs the **Firebase App
  Distribution Admin** role in the Firebase project.
- `App not found`: the app ID must match the platform (`:android:` vs `:ios:`) and the project.
- `Invalid group alias`: use the group's alias, not its display name.
- AAB uploads need the Firebase project linked to Google Play. Build an `apk` as
  well (`artifacts: [aab, apk]`) to avoid this.

## Android build fails

- `No android/ directory`: set the `app-directory` input if the app is not at the repo root.
- `Missing signing secrets`: pass all four `ANDROID_*` secrets from the caller.
  See [SECRETS.md](SECRETS.md#android-signing).
- `The keystore could not be opened`: wrong password or alias, or the base64 value
  was truncated (use `base64 -i` on macOS or `base64 -w0` on Linux).
- `Task … not found` / `Flavor … not found`: `android.flavor` must match a Gradle
  `productFlavors` entry, or should be left out.
- Gradle/JDK errors: set `app.java_version` to what your Android Gradle Plugin needs
  (AGP 8 needs 17+).
- The release is signed with debug keys: your `build.gradle(.kts)` does not read
  `key.properties`. See [NEW_PROJECT_SETUP.md](NEW_PROJECT_SETUP.md#3-android-signing-in-gradle).

## iOS name or icon does not change per environment

- `Release.xcconfig` does not include `Environment.xcconfig`. The build log shows
  a warning about this.
- The Runner **target** still sets *Primary App Icon Set Name*. Delete it so the
  xcconfig value applies (NEW_PROJECT_SETUP step 5.3).
- `Info.plist` must use `$(APP_DISPLAY_NAME)` for `CFBundleDisplayName`.
