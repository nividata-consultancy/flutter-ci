# Tagging and releases

A guide for app developers. Builds start **only** when you push a tag.

## Tag format

| Tag | Environment | Example | Goes to |
|---|---|---|---|
| `vX.Y.Z-beta.N` | **UAT** | `v1.4.0-beta.1` | Android: the destinations with `enabled: true` in `environments.uat` (Play internal testing, Firebase, Drive). iOS: TestFlight |
| `vX.Y.Z` | **prod** | `v1.4.0` | Android: the destinations with `enabled: true` in `environments.prod` (Play internal testing and/or a draft production release, Firebase, Drive). iOS: TestFlight |
| anything else starting with `v` | build fails | `v1.4`, `v1.4.0-rc1` | nothing |

- UAT and prod tags can be on **any branch**.
- Optional **prod guard**: if the app sets `app.prod_branches` (e.g. `[main]`),
  prod tags must be on a commit already on one of those branches, otherwise the build fails.
- UAT and prod use the same app ID / bundle ID. CI never submits for App Store
  review and never releases to users. The Play production release is created
  as a **draft**, and a person presses **Release** in Play Console.

### Version numbers

| | Android | iOS |
|---|---|---|
| Version name | `1.4.0-beta.1` (UAT) / `1.4.0` (prod) | `1.4.0` (numbers only) |
| Build number | GitHub run number + `build_number_offset` | Xcode Cloud build number |

### Telling UAT and prod builds apart

The iOS version is the same for UAT and prod (`1.4.0`), and TestFlight gets no
release notes. To tell the builds apart:
- **On the device:** the UAT build has the UAT name (e.g. "MyApp UAT") and the UAT icon.
- **In App Store Connect:** go to **Xcode Cloud → Builds**. Each build shows the tag
  that started it (`v1.4.0-beta.3` or `v1.4.0`) and its build number. The same
  number appears in TestFlight.
- **On Play:** release names are labeled `[UAT] 1.4.0-beta.1 (N)` / `[PROD] 1.4.0 (N)`.

## Release notes

Release notes go to **Firebase App Distribution only**. Testers in Firebase see
them; TestFlight and Play get none. Write them in the **tag message** by creating
an annotated tag with `-a`:

```bash
git tag -a v1.4.0-beta.1 -m "Login crash fixed
Dark mode added, please test on a tablet"
```

Firebase then shows (up to 1,000 bytes):

```
[UAT] v1.4.0-beta.1 · abc1234
Login crash fixed
Dark mode added, please test on a tablet
```

A plain tag without a message (`git tag v1.4.0-beta.1`) works too. The notes are then
the latest commit subjects since the previous tag. Firebase sends them to the
`groups` set in config. The GitHub Release on the app repo (for developers) shows
the tag message plus the commit list.

## Choosing where a build goes

Android destinations are switched on and off in `.ci/config.yaml` with
`enabled: true|false` (see [CONFIG_REFERENCE.md](CONFIG_REFERENCE.md#destinations)).
To send the next build somewhere else, change the switches, commit, then tag that commit.

To build **only one platform**, set `android.enabled: false` or `ios.enabled: false`
for that environment (see [CONFIG_REFERENCE.md](CONFIG_REFERENCE.md#platform-switches)).

## Cutting a UAT build

```bash
git tag -a v1.4.0-beta.1 -m "What testers should check"   # on the commit QA should test
git push origin v1.4.0-beta.1
```

For the next UAT build of the same version, bump N: `v1.4.0-beta.2`.

## Cutting a prod build

When QA approves a UAT build, tag the **same commit**:

```bash
git tag -a v1.4.0 -m "Release notes for this version" v1.4.0-beta.3^{}   # the approved commit
git push origin v1.4.0
```

Any branch works. If the app sets `app.prod_branches`, the commit must
already be on one of those branches (merge first, then tag the merged commit).

## Promoting to production

CI stops at testing tracks. A release manager promotes manually:

**iOS (App Store Connect)**
1. Go to **Xcode Cloud → Builds** and find the build started by the prod tag
   (e.g. `v1.4.0`). Note its **build number**.
2. On the App Store tab, create or open version `1.4.0`. In **Build**, select the
   build with **that number**.
3. Submit for review and release when ready.

**Android (Play Console)**
- With `production` in `playstore.tracks`: go to **Production → Releases**, open the draft
  `[PROD] 1.4.0 (N)`, review it, set the rollout percentage and press **Release**
  (Play then reviews it).
- With `[internal]` only: go to **Testing → Internal testing**, find `[PROD] 1.4.0 (N)` and
  choose **Promote release → Production**.

### The one rule

**Never submit a UAT build to the store.** UAT builds talk to UAT servers and
carry the UAT name and icon. Before submitting, check that the build number
belongs to a prod tag (`vX.Y.Z`, no `-beta`).

## Fixing mistakes

- **Wrong tag pushed:** delete it locally and remotely, then tag again.
  Use a new beta number if a build already went out.
  ```bash
  git tag -d v1.4.0-beta.1 && git push --delete origin v1.4.0-beta.1
  ```
- **Prod guard rejected the tag:** see [TROUBLESHOOTING.md](TROUBLESHOOTING.md#prod-guard-rejected).
- **"versionCode already used" on Play:** see [TROUBLESHOOTING.md](TROUBLESHOOTING.md#versioncode-already-used).
- **Re-running a build:** re-running the GitHub workflow uses the same run number
  (same versionCode), so Play rejects a second upload. Push a new tag instead.

## Hotfixes

Tag `v1.4.1` on the hotfix branch. If the app uses `app.prod_branches`, add the
branch to it, e.g. `[main, "release/1.4"]`.
