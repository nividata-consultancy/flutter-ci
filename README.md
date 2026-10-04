# flutter-ci

Shared CI/CD for our Flutter apps: a reusable GitHub Actions workflow for
Android and Xcode Cloud scripts for iOS, driven by SemVer tags.

```
git tag -a v1.4.0-beta.1 -m "Notes for testers" && git push origin v1.4.0-beta.1   # UAT
git tag -a v1.4.0 -m "Notes for testers"        && git push origin v1.4.0          # prod
```

- **New app?** Start with [docs/NEW_PROJECT_SETUP.md](docs/NEW_PROJECT_SETUP.md).
- **Cutting releases?** See [docs/TAGGING_AND_RELEASES.md](docs/TAGGING_AND_RELEASES.md).
- **Everything else:** [docs/README.md](docs/README.md).

This repository is public and must never contain secrets, client names, bundle
IDs or internal URLs.
