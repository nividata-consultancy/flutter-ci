# Xcode Cloud setup

Each app has **one** Xcode Cloud workflow. It builds both UAT and prod from tags.
The workflow always archives the `Runner` scheme. The environment comes from the
tag, and flutter-ci's scripts apply it before `xcodebuild` runs (see
[README.md](README.md#how-ios-environments-work)).

Labels below match App Store Connect / Xcode at the time of writing. Apple
renames things occasionally, but the concepts stay the same.

## Prerequisites

- The app repo is connected to Xcode Cloud. In Xcode, open
  `ios/Runner.xcworkspace` and choose **Product → Xcode Cloud → Create Workflow**.
  The first time, Xcode asks you to grant access to the repository (GitHub app install).
- `ios/ci_scripts/ci_post_clone.sh` and `ci_post_xcodebuild.sh` are committed **with the
  execute bit** (`git ls-files -s ios/ci_scripts` shows `100755`).
- The one-time project setup in [NEW_PROJECT_SETUP.md](NEW_PROJECT_SETUP.md#5-one-time-ios-project-setup) is done.

## Create the workflow

In Xcode, open **Report navigator → Cloud → Manage Workflows → +**, or go to App Store
Connect → your app → **Xcode Cloud → Manage Workflows**.

### General

- **Name:** `Release (tags)`.
- **Repository / Project or Workspace:** `ios/Runner.xcworkspace`.
- **Restrict editing:** recommended, so that only admins can change it.

### Environment

- **Xcode Version:** pick a specific version that supports your Flutter version,
  not "Latest Release", so builds are reproducible. Raise it on purpose when you
  upgrade Flutter.
- **macOS Version:** "Automatically select" is fine.
- **Clean:** on. Flutter and Pods are installed by the scripts anyway.
- **Environment Variables:**

  | Name | Value | Secret | Needed for |
  |---|---|---|---|
  | `FLUTTER_CI_REF` | `v1` (canary apps: `main`) | no | always |
  | `DART_DEFINES_UAT_JSON_BASE64` | `base64` of `env/uat.json` | yes | only if `env/uat.json` is not committed |
  | `DART_DEFINES_PROD_JSON_BASE64` | `base64` of `env/prod.json` | yes | only if `env/prod.json` is not committed |
  | `FIREBASE_SERVICE_ACCOUNT_JSON_BASE64` | base64 service account JSON | yes | iOS `firebase` destination |
  | `FIREBASE_IOS_APP_ID` | `1:123…:ios:abc…` | no | iOS `firebase` destination |
  | `GDRIVE_SERVICE_ACCOUNT_JSON_BASE64` | base64 service account JSON | yes | iOS `drive` destination |
  | `SLACK_WEBHOOK_URL` | webhook URL | yes | optional notifications |
  | `FLUTTER_CI_APP_DIR` | e.g. `apps/mobile` | no | only if the Flutter app is not at the repo root |
  | `FLUTTER_CI_STRICT` | `1` | no | optional: fail the build when Firebase/Drive uploads fail |

  Create the base64 values with `base64 -i file.json | pbcopy`. See [SECRETS.md](SECRETS.md#xcode-cloud).

### Start condition

Remove the default "Branch Changes" condition and add **Tag Changes**:

- **Source Tags:** choose **Custom Tags**, then **Tags beginning with** `v`.
- **Auto-cancel builds:** off. Each tag is its own release.
- **Files and folders:** leave as "Any changes".

The scripts require `CI_TAG`. If you start a build manually from a branch,
`ci_post_clone.sh` stops with an error that explains this. To rebuild a release,
re-push a new tag (e.g. `v1.4.0-beta.2`).

### Actions

Add one action: **Archive**.

- **Platform:** iOS.
- **Scheme:** `Runner`. Mark it **Shared** in Xcode (Product → Scheme → Manage
  Schemes → Shared) and commit `ios/Runner.xcodeproj/xcshareddata`.
- **Distribution Preparation:** **TestFlight and App Store**. This is needed so a
  `[PROD]` build can later be submitted for review. "TestFlight (Internal Testing
  Only)" builds cannot be submitted.
- **Requirements:** "Required to pass".

### Post-actions

Add **TestFlight Internal Testing** and select your internal testing group
(e.g. "QA"). External groups are optional and need Beta App Review.

CI never submits for App Store review and never releases to users.

### Save, then build

Push a tag such as `v0.1.0-beta.1`. In the build log, check:
- the `ci_post_clone.sh` output, which ends with `ci_post_clone.sh done: [UAT] v0.1.0-beta.1 (N)`;
- that TestFlight shows the build with "What to Test" starting with `[UAT] v0.1.0-beta.1 · <sha>`.

## How the scripts run

1. Xcode Cloud clones the repo and runs `ios/ci_scripts/ci_post_clone.sh`, the
   ~10-line bootstrap. It downloads
   `https://codeload.github.com/OWNER/flutter-ci/tar.gz/$FLUTTER_CI_REF` into
   `$CI_PRIMARY_REPOSITORY_PATH/.flutter-ci` and runs
   `scripts/xcode-cloud/post_clone.sh`. That script:
   - checks the tag, the config and the prod guard;
   - installs Flutter at the pinned version into `~/flutter`, then runs `precache` and `pub get`;
   - resolves the dart defines and writes `ios/Flutter/Environment.xcconfig`;
   - copies `GoogleService-Info.plist`;
   - runs `flutter build ios --config-only` with `--build-name X.Y.Z --build-number $CI_BUILD_NUMBER`;
   - runs `pod install`;
   - saves `.flutter-ci/state.env`.
2. Xcode Cloud archives `Runner`.
3. `ci_post_xcodebuild.sh` runs `scripts/xcode-cloud/post_xcodebuild.sh`, which
   only acts when `CI_XCODEBUILD_ACTION=archive`. It:
   - writes `ios/TestFlight/WhatToTest.en-US.txt`;
   - optionally uploads the ad hoc IPA to Firebase and Drive;
   - optionally notifies Slack.
4. The TestFlight post-action distributes the build to internal testers.

iOS version numbers are always `X.Y.Z`, because Apple only allows numbers.
The build number is Xcode Cloud's `CI_BUILD_NUMBER`. UAT and prod builds can
therefore show the same version in TestFlight. **The `[UAT]` / `[PROD]` label in
"What to Test" is how you tell them apart.**

## Ad hoc IPA for Firebase and Drive

TestFlight needs nothing extra. If `.ci/config.yaml` lists `firebase` or
`drive` under `environments.<env>.ios.destinations`, `ci_post_xcodebuild.sh`
uploads the **ad hoc-signed** IPA from `$CI_AD_HOC_SIGNED_APP_PATH`.

- Ad hoc builds install **only on devices registered** in the Apple Developer
  account (Certificates, IDs & Profiles → Devices) at the time of the build. If
  you add a tester's device, the next build includes it. Older builds do not.
- Apple's documentation lists `CI_AD_HOC_SIGNED_APP_PATH` for archive actions but
  does not say which distribution settings produce it (see
  [ASSUMPTIONS.md](ASSUMPTIONS.md)). If the variable is empty, the script logs
  `ERROR: No ad hoc IPA found…`, still lets the build and TestFlight succeed, and
  reports it in Slack. Set `FLUTTER_CI_STRICT=1` to make this fail the build instead.
- On the first build with these destinations, check the log for
  `Uploading … to Firebase App Distribution` / `Google Drive`.

## Updating flutter-ci

`FLUTTER_CI_REF=v1` picks up every non-breaking flutter-ci release automatically.
To pin an exact version, use e.g. `v1.2.3`. To move to a new major version, change
it to `v2` after reading the migration notes in [MAINTAINING.md](MAINTAINING.md#migrations).
