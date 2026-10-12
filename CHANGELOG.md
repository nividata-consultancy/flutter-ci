# Changelog

All notable changes to flutter-ci. Versions follow [SemVer](https://semver.org/);
apps track the major tag (`v2`). Breaking changes and migrations are described
in [docs/maintainers/MAINTAINING.md](docs/maintainers/MAINTAINING.md#migrations).

## [Unreleased]

## [2.0.1] - 2026-10-12

### Fixed
- Android: GitHub-hosted Linux runners could run out of disk ("No space left on
  device", a runner crash). A new **Free disk space** step deletes preinstalled tools
  the build doesn't use (.NET, Swift, Haskell, CodeQL, browsers, Docker images) before
  setting up Flutter. The Android SDK is kept; self-hosted runners are not touched.

## [2.0.0] - 2026-10-12

Breaking: see "v1 → v2" in `docs/maintainers/MAINTAINING.md#migrations`.

### Added
- `environments.<env>.build_args`: extra `flutter build` flags (e.g.
  `--no-tree-shake-icons`) for that environment, on Android and iOS. Flags flutter-ci
  sets itself are refused. See "Extra build flags" in `docs/CONFIG_REFERENCE.md`.

### Removed
- `environments.<env>.dart_define_file`. Pass the file in `build_args` instead:
  `build_args: ["--dart-define-from-file=env/uat.json"]`. A config that still has
  `dart_define_file` fails validation, and the error shows the replacement line.
- The `DART_DEFINES_<ENV>_JSON` (GitHub) and `DART_DEFINES_<ENV>_JSON_BASE64` (Xcode
  Cloud) secrets are no longer read; commit the JSON instead. The reusable workflow
  still accepts the two GitHub secrets, so older app workflows don't fail to parse.

## [1.4.0] - 2026-10-11

### Added
- iOS flavors: `ios.flavor` (the Xcode scheme name) is passed as `--flavor` to
  `flutter build ios --config-only`. Use one Xcode Cloud workflow per flavor; the build
  stops early if the workflow's scheme doesn't match. See "Apps with flavors" in
  `docs/IOS_SETUP.md`.

## [1.3.2] - 2026-10-11

### Fixed
- Docs: the iOS build number is set by Xcode Cloud (its own counter), not by
  `pubspec.yaml`. New "iOS build number" section in `docs/IOS_SETUP.md` explains how to
  line them up with Xcode Cloud's "Next Build Number" setting.

### Added
- Xcode Cloud: `ci_post_clone.sh` warns when the Xcode Cloud build number differs from
  the pubspec build number.

## [1.3.1] - 2026-10-11

### Added
- Xcode Cloud: installs the FlutterFire CLI when the Xcode project has the
  `flutterfire upload-crashlytics-symbols` build phase (otherwise the archive fails
  with "PhaseScriptExecution failed").
- Xcode Cloud: `ci_post_clone.sh` stops early with a clear message when the iOS main
  file (`ios.target`, default `lib/main.dart`) doesn't exist, instead of a later
  "PhaseScriptExecution failed" in the archive.
- Several apps (flavors) from one repo: one config file and one job per app; their
  builds run in parallel (the concurrency group now includes `config-path`).
  See "Several apps from one repo" in `docs/ANDROID_SETUP.md`.

### Changed
- Template and docs: how to use `app-directory` for apps in a subfolder of the
  repo (workflow at the repo root, `config-path` relative to the app folder).
- `app.run_tests` now defaults to `false` (like `run_analyze`). Set it to `true`
  to run `flutter test` before the Android build.

### Removed
- `app.obfuscate`: builds are no longer obfuscated (iOS symbols were never kept,
  and obfuscated crash reports were unreadable without manual steps). An existing
  `obfuscate:` line is ignored with a warning.

## [1.3.0] - 2026-10-10

### Changed
- **Version and build number now come from `pubspec.yaml`** (`version: X.Y.Z+N`) on
  Android and iOS. The tag's version must match `X.Y.Z` (the build stops otherwise).
  Raise `+N` before every tag. `app.build_number_offset` is ignored with a warning.
- Docs: how to pick `java_version` (same as `flutter doctor -v` shows) and a
  reminder to commit `.fvmrc`.

## [1.2.1] - 2026-10-05

### Changed
- Android build files are chosen automatically: CI always builds the APK (kept on
  the GitHub run, sent to Firebase and Drive) and adds an AAB only when Play is
  enabled. The `artifacts` config key is no longer used; existing configs keep
  working with a warning.
- Docs: one step-by-step guide per platform (`docs/ANDROID_SETUP.md`,
  `docs/IOS_SETUP.md`) and `docs/RELEASES.md` for daily use; maintainer docs moved
  to `docs/maintainers/`.
- All docs rewritten for the current setup (Android destinations and Play tracks,
  iOS to TestFlight only, platform switches, Drive options, Xcode Cloud steps as
  they appear in current Xcode). Removed notes about features that no longer exist.
- `templates/.ci/config.yaml`: safer defaults for a new app (dart defines and the
  iOS name/icon commented out, Play prod on `[internal]`).
- Xcode Cloud only warns about `Environment.xcconfig` when the config sets a name,
  icon or build settings.

## [1.2.0] - 2026-10-04

### Added
- Platform switches `environments.<env>.android.enabled` and
  `environments.<env>.ios.enabled` (default `true`). Android skips the job (green);
  iOS stops in `ci_post_clone.sh` before building (shown as failed, nothing sent to TestFlight).

### Fixed
- Drive uploads: errors show the failing phase and curl's own message (no more
  "HTTP 000 … see log"), network errors are retried, and a missing upload
  address is caught. New troubleshooting section "Drive upload fails".
- A self-test assertion that was outdated in v1.1.0.

## [1.1.0] - 2026-10-04

### Added
- Google Drive uploads as your own Google account (OAuth refresh token):
  new optional secrets `GDRIVE_OAUTH_CLIENT_ID`, `GDRIVE_OAUTH_CLIENT_SECRET`,
  `GDRIVE_OAUTH_REFRESH_TOKEN`. Works with any My Drive folder, no Shared Drive
  or Google Workspace needed. Recommended with a dedicated builds account and the
  limited `drive.file` scope; `scripts/tools/gdrive_create_folder.sh` creates the
  target folder. The service account method is unchanged.

## [1.0.0] - 2026-10-04

### Added
- Tag convention: `vX.Y.Z-beta.N` → UAT, `vX.Y.Z` → prod, single parser for
  GitHub Actions and Xcode Cloud (`scripts/common/parse_tag.sh`).
- `.ci/config.yaml` schema version 1 with fail-fast validation.
- Optional prod guard (`app.prod_branches`): when set, prod tags must be on one of
  those branches; when unset, prod tags build from any branch. Shallow-clone safe.
- Release notes from the annotated tag message (`git tag -a … -m …`), falling
  back to commit subjects; sent to Firebase App Distribution (and the GitHub Release).
- Android destinations per app, each with a required `enabled: true|false` switch:
  Google Play `tracks` (`[internal]`, `[production]` as a draft, or both; production
  only for prod),
  Firebase App Distribution with tester groups, Shared Drive.
- iOS builds go to TestFlight only.
- Reusable Android workflow `android-release.yml` with composite actions:
  setup-flutter, android-signing, distribute-playstore, distribute-firebase,
  distribute-drive, notify. Dry-run mode.
- Xcode Cloud scripts (`post_clone.sh`, `post_xcodebuild.sh`) and ~10-line app
  bootstraps.
- Templates, docs, bats tests, `self-test.yml`, `release.yml`.
