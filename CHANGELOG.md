# Changelog

All notable changes to flutter-ci. Versions follow [SemVer](https://semver.org/);
apps track the major tag (`v1`). Breaking changes and migrations are described
in [docs/maintainers/MAINTAINING.md](docs/maintainers/MAINTAINING.md#migrations).

## [Unreleased]

## [1.2.1] - 2026-10-05

### Changed
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
