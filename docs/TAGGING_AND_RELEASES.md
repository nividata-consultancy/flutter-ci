# Tagging and releases

A guide for app developers. Builds start **only** when you push a tag. Normal commits
and branches don't start anything.

## Tag format

| Tag | Environment | Example |
|---|---|---|
| `vX.Y.Z-beta.N` | **UAT** | `v1.4.0-beta.1` |
| `vX.Y.Z` | **prod** | `v1.4.0` |
| anything else starting with `v` | the build fails with an explanation | `v1.4`, `v1.4.0-rc1` |

- Tags can be on **any branch**. An app can restrict prod tags to certain branches
  with `app.prod_branches: [main]` (the "prod guard").
- UAT and prod use the same app ID / bundle ID.

## Where a build goes

| | UAT tag | prod tag |
|---|---|---|
| **Android** | Each destination in `environments.uat.android.destinations` with `enabled: true`: Play internal testing, Firebase App Distribution, Google Drive | The same for `environments.prod`. Play can also create a **draft** production release (`tracks: [internal, production]` or `[production]`). |
| **iOS** | TestFlight internal group | TestFlight internal group |

To change where builds go, edit `.ci/config.yaml` (the `enabled` switches and Play
`tracks`), commit, then tag that commit. To build **only one platform**, set
`android.enabled: false` or `ios.enabled: false` for that environment. Details are in
[CONFIG_REFERENCE.md](CONFIG_REFERENCE.md#destinations).

Nothing reaches real users automatically. See [Releasing to users](#releasing-to-users).

## Version numbers

| | Android | iOS |
|---|---|---|
| Version name | `1.4.0-beta.1` (UAT) / `1.4.0` (prod) | `1.4.0` (numbers only, for both) |
| Build number | GitHub run number + `build_number_offset` | Xcode Cloud build number |

The tag version must be **higher than the version already on the stores**.

## Release notes

Write the notes in the **tag message**, using `-a`:

```bash
git tag -a v1.4.0-beta.1 -m "Login crash fixed
Dark mode added, please test on a tablet"
```

They appear in **Firebase App Distribution**, sent to the `groups` from the config, and in
the app repo's **GitHub Release**, together with the commit list:
```
[UAT] v1.4.0-beta.1 · abc1234
Login crash fixed
Dark mode added, please test on a tablet
```

- Firebase shows up to 1,000 bytes, so put the important part first.
- A tag without a message (`git tag v1.4.0-beta.1`) works too. The notes are then the
  latest commit titles.
- TestFlight and Play get **no** release notes.

## Cutting a UAT build

```bash
git tag -a v1.4.0-beta.1 -m "What testers should check"   # on the commit QA should test
git push origin v1.4.0-beta.1
```
For the next UAT build of the same version, raise N: `v1.4.0-beta.2`.

## Cutting a prod build

When QA approves a UAT build, tag **the same commit**:
```bash
git tag -a v1.4.0 -m "Release notes" v1.4.0-beta.3^{}   # ^{} = the commit of that beta tag
git push origin v1.4.0
```

## Telling UAT and prod builds apart

| Where | How |
|---|---|
| Play Console | Release names `[UAT] 1.4.0-beta.1 (N)` and `[PROD] 1.4.0 (N)` |
| Firebase | Notes start with `[UAT]` or `[PROD]` |
| TestFlight | Both show version `1.4.0`. Check the build number in App Store Connect → **Xcode Cloud → Builds**, which shows the tag of each build. If the app uses a UAT name and icon, you can also see it on the phone. |

## Releasing to users

CI never releases to users. A release manager does it by hand.

**Android (Play Console)**
- With `production` in `tracks`: go to **Production → Releases**, open the draft
  `[PROD] 1.4.0 (N)`, check it, set the rollout percentage and press **Release**.
- With `tracks: [internal]` only: go to **Testing → Internal testing**, find `[PROD] 1.4.0 (N)`
  and choose **Promote release → Production**.

**iOS (App Store Connect)**
1. Go to **Xcode Cloud → Builds**, find the build of the prod tag (e.g. `v1.4.0`) and
   note its **build number**.
2. On the **App Store** tab, create or open version `1.4.0`. Under **Build**, select the
   build with that number.
3. Submit for review, then release when it's approved.

**Never submit a UAT build to the store.** UAT builds use UAT servers. Always check
that the build number belongs to a `vX.Y.Z` tag without `-beta`.

## Fixing mistakes

- **Wrong tag pushed:** delete it, then tag again with a new beta number if a build
  already went out.
  ```bash
  git tag -d v1.4.0-beta.1 && git push --delete origin v1.4.0-beta.1
  ```
- **Build failed:** fix it and push a **new tag**. Don't press "Re-run" on GitHub: it
  reuses the same build number, and Play rejects a version code that was already used.
- **Prod guard rejected the tag:** see [TROUBLESHOOTING.md](TROUBLESHOOTING.md#prod-guard-rejected).
- **"Version code already used":** see [TROUBLESHOOTING.md](TROUBLESHOOTING.md#versioncode-already-used).
