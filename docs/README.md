# flutter-ci docs

flutter-ci builds our Flutter apps when you push a tag:
- **Android** runs on GitHub Actions and goes to Play, Firebase or Drive, whichever you switch on.
- **iOS** runs on Xcode Cloud and goes to TestFlight.

All the build logic lives in this repository. Each app only has a few small files that
call into it.

## Start here

| Step | Guide |
|---|---|
| 1. Set up Android for an app | [ANDROID_SETUP.md](ANDROID_SETUP.md) |
| 2. Set up iOS for an app | [IOS_SETUP.md](IOS_SETUP.md) |
| 3. Make builds every day | [RELEASES.md](RELEASES.md) |

You can do Android only, iOS only, or both. Turn off the platform you don't use with
`enabled: false` in the config.

## When you need more

| | |
|---|---|
| Every setting in `.ci/config.yaml` | [CONFIG_REFERENCE.md](CONFIG_REFERENCE.md) |
| A build failed | [TROUBLESHOOTING.md](TROUBLESHOOTING.md) |
| Changing flutter-ci itself | [maintainers/MAINTAINING.md](maintainers/MAINTAINING.md) |
| Why things are built this way | [maintainers/DECISIONS.md](maintainers/DECISIONS.md) |

## How it works (short)

```
push tag v1.4.0-beta.1
  ├─ GitHub Actions → app's release.yml → flutter-ci android-release.yml → Play / Firebase / Drive
  └─ Xcode Cloud   → ios/ci_scripts/ci_post_clone.sh → flutter-ci post_clone.sh → Archive → TestFlight
```

- `-beta.N` tags build **UAT**; plain `vX.Y.Z` tags build **prod**.
- Apps use flutter-ci **`v1`**, which always points to the newest `v1.x.y`, so fixes reach
  every app automatically.
