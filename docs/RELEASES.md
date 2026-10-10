# Releases (daily use)

Builds start **only** when you push a tag. Normal commits do nothing.

## Tag format

| You push | Builds | Example |
|---|---|---|
| `vX.Y.Z-beta.N` | **UAT** | `v1.4.0-beta.1` |
| `vX.Y.Z` | **prod** | `v1.4.0` |

Anything else starting with `v` (e.g. `v1.4`) fails with an explanation. Tags work on
any branch.

## Version and build number

Both come from **`pubspec.yaml`**, for Android and iOS:
```yaml
version: 1.4.0+45      # 1.4.0 = version, 45 = build number
```
- The tag's version must **match**: `v1.4.0-beta.1` and `v1.4.0` only build if pubspec
  says `1.4.0+…`. Otherwise the build stops with an error that explains it.
- **Raise the build number (`+45` → `+46`) before every new tag.** Play and TestFlight
  reject a build number they've already received, including from a UAT build.
- The version and build number must be higher than what's already on the stores.

## Make a UAT build

1. In `pubspec.yaml`, set `version: 1.4.0+45` (raise the `+number`). Commit and push.
2. Tag and push:
   ```bash
   git tag -a v1.4.0-beta.1 -m "What testers should check"
   git push origin v1.4.0-beta.1
   ```
For the next UAT build: raise to `+46`, commit, then tag `v1.4.0-beta.2`.

## Make a prod build

When QA approves the last UAT build:
1. In `pubspec.yaml`, raise **only the build number** (`1.4.0+46` → `1.4.0+47`). Commit and push.
   This is needed because the UAT build already used `+46`.
2. Tag and push:
   ```bash
   git tag -a v1.4.0 -m "Release notes"
   git push origin v1.4.0
   ```

## Where builds go

| | Where | Change it in `.ci/config.yaml` |
|---|---|---|
| Android | Play internal testing, Play production (draft), Firebase, Drive | `enabled: true/false` per destination, Play `tracks` |
| iOS | TestFlight | always; turn iOS off with `ios: { enabled: false }` |

To change where the next build goes, edit the config, commit, then tag that commit.
UAT and prod have separate settings.

| To… | Set (under `uat:` or `prod:`) |
|---|---|
| Build only Android | `ios: { enabled: false }` |
| Build only iOS | `android: { enabled: false }` |
| Skip a destination | `firebase: { enabled: false, … }` |
| Also create a Play production draft (prod) | `playstore: { enabled: true, tracks: [internal, production] }` |

## Release notes

The **tag message** (`-m "…"`) becomes the release notes in **Firebase App
Distribution**, plus the GitHub Release on the app repo. Put the important part first;
Firebase shows up to 1,000 bytes. TestFlight and Play get no notes.

## Release to users

Nothing reaches users automatically.

**Android (Play Console):**
- If a production draft was created: **Production → Releases** → open `[PROD] 1.4.0 (N)`
  → set the rollout → **Release**.
- Otherwise: **Testing → Internal testing** → `[PROD] 1.4.0 (N)` → **Promote release →
  Production**.

**iOS (App Store Connect):**
1. **Xcode Cloud → Builds**: find the build of tag `v1.4.0` and note its **build number**.
2. **App Store** tab → version `1.4.0` → **Build** → choose that number → submit for review.

**Never submit a UAT (`-beta`) build to the store.** In TestFlight, UAT and prod builds
both show `1.4.0`, so always check the build number in Xcode Cloud → Builds.

## When something goes wrong

- **A build failed before uploading:** fix it and push a new tag (`-beta.2`). If anything
  was already uploaded, also raise the `+number` in `pubspec.yaml` first.
- **"Tag … is for version X, but pubspec.yaml says Y":** update `version:` in
  `pubspec.yaml`, commit, delete the tag and tag the new commit.
- **Wrong tag:** `git tag -d v1.4.0-beta.1 && git push --delete origin v1.4.0-beta.1`
- **Error messages** link to [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
