# flutter-ci

Shared CI/CD for our Flutter apps: a reusable GitHub Actions workflow for
Android and Xcode Cloud scripts for iOS, driven by SemVer tags.

```
git tag v1.4.0-beta.1 && git push origin v1.4.0-beta.1   # UAT  → Play internal + TestFlight [UAT]
git tag v1.4.0        && git push origin v1.4.0          # prod → Play internal + TestFlight [PROD]
```

- **New app?** Start with [docs/NEW_PROJECT_SETUP.md](docs/NEW_PROJECT_SETUP.md).
- **Cutting releases?** See [docs/TAGGING_AND_RELEASES.md](docs/TAGGING_AND_RELEASES.md).
- **Everything else:** [docs/README.md](docs/README.md).

This repository is public and must never contain secrets, client names, bundle
IDs or internal URLs.
