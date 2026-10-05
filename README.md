# flutter-ci

Shared CI/CD for our Flutter apps. Android builds run on GitHub Actions and iOS
builds run on Xcode Cloud. Both start when you push a tag:

```bash
git tag -a v1.4.0-beta.1 -m "Notes for testers" && git push origin v1.4.0-beta.1   # UAT
git tag -a v1.4.0 -m "Notes for testers"        && git push origin v1.4.0          # prod
```

| | Where builds can go | Chosen in |
|---|---|---|
| **Android** | Play internal testing, Play production (as a draft), Firebase App Distribution, Google Drive | `.ci/config.yaml` (`enabled: true/false` per destination) |
| **iOS** | TestFlight | the Xcode Cloud workflow |

**Set up an app:** [Android](docs/ANDROID_SETUP.md) · [iOS](docs/IOS_SETUP.md)
**Daily use:** [docs/RELEASES.md](docs/RELEASES.md) · **All docs:** [docs/README.md](docs/README.md)

This repository is public. It must never contain secrets, client names, bundle
IDs or internal URLs.
