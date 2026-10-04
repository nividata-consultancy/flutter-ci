# Changelog

All notable changes to flutter-ci. Versions follow [SemVer](https://semver.org/);
apps track the major tag (`v1`). Breaking changes and migrations are described
in [docs/MAINTAINING.md](docs/MAINTAINING.md#migrations).

## [Unreleased]

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
