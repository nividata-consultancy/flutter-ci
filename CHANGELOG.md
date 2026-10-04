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
- Prod guard (prod tags must be on a prod branch), shallow-clone safe.
- Reusable Android workflow `android-release.yml` with composite actions:
  setup-flutter, android-signing, distribute-playstore, distribute-firebase,
  distribute-drive, notify. Dry-run mode.
- Xcode Cloud scripts (`post_clone.sh`, `post_xcodebuild.sh`) and ~10-line app
  bootstraps; `[UAT]` / `[PROD]` TestFlight "What to Test" labels.
- Templates, docs, bats tests, `self-test.yml`, `release.yml`.
