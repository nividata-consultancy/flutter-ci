# Releases (daily use)

Builds start **only** when you push a tag. Normal commits do nothing.

## Tag format

| You push | Builds | Example |
|---|---|---|
| `vX.Y.Z-beta.N` | **UAT** | `v1.4.0-beta.1` |
| `vX.Y.Z` | **prod** | `v1.4.0` |

Anything else starting with `v` (e.g. `v1.4`) fails with an explanation. Tags work on
any branch. The version must be **higher** than the one already on the stores.

## Make a UAT build

```bash
git tag -a v1.4.0-beta.1 -m "What testers should check"
git push origin v1.4.0-beta.1
```
For the next one, raise the last number: `v1.4.0-beta.2`.

## Make a prod build

When QA approves a UAT build, tag the **same commit**:
```bash
git tag -a v1.4.0 -m "Release notes" v1.4.0-beta.3^{}
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

- **A build failed:** fix it, then push a **new** tag (`-beta.2`). Don't use "Re-run" on
  GitHub; Play rejects the repeated build number.
- **Wrong tag:** `git tag -d v1.4.0-beta.1 && git push --delete origin v1.4.0-beta.1`
- **Error messages** link to [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
