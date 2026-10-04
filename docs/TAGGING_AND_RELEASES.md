# Tagging and releases

A guide for app developers. Builds start **only** when you push a tag.

## Tag format

| Tag | Environment | Example | Goes to |
|---|---|---|---|
| `vX.Y.Z-beta.N` | **UAT** | `v1.4.0-beta.1` | Play internal track, TestFlight (labeled `[UAT]`), plus Firebase/Drive if configured |
| `vX.Y.Z` | **prod** | `v1.4.0` | Play internal track, TestFlight (labeled `[PROD]`) |
| anything else starting with `v` | build fails | `v1.4`, `v1.4.0-rc1` | nothing |

- UAT tags can be on **any branch**.
- Prod tags must be on a commit that is already on a prod branch (default `main`,
  set in `app.prod_branches`). Otherwise the **prod guard** fails the build.
- UAT and prod use the same app ID / bundle ID. Both are uploaded for testing
  only. CI never submits for review and never releases to users.

### Version numbers

| | Android | iOS |
|---|---|---|
| Version name | `1.4.0-beta.1` (UAT) / `1.4.0` (prod) | `1.4.0` (numbers only) |
| Build number | GitHub run number + `build_number_offset` | Xcode Cloud build number |

Because the iOS version is the same for UAT and prod, TestFlight's
**What to Test** starts with `[UAT] v1.4.0-beta.1 · abc1234` or
`[PROD] v1.4.0 · abc1234`. Play release names carry the same label.

## Cutting a UAT build

```bash
git tag v1.4.0-beta.1           # on the commit you want QA to test
git push origin v1.4.0-beta.1
```

For the next UAT build of the same version, bump N: `v1.4.0-beta.2`.

## Cutting a prod build

When QA approves a UAT build, tag the **same commit** (it must be on `main`):

```bash
git checkout main && git pull
git log --oneline -1 v1.4.0-beta.3   # the approved commit
git tag v1.4.0 v1.4.0-beta.3^{}      # tag that exact commit
git push origin v1.4.0
```

If the approved commit is on a feature branch, merge it into `main` first,
then tag the merge result. The merged code should be what QA tested; if it
differs, cut another beta.

## Promoting to production

CI stops at testing tracks. A release manager promotes manually:

**iOS (App Store Connect)**
1. Go to TestFlight → iOS builds. Find the build whose **What to Test starts with `[PROD]`**
   and the tag you expect (e.g. `[PROD] v1.4.0 · abc1234`).
2. On the App Store tab, create or open version `1.4.0`, then in **Build** select **that** build.
3. Submit for review and release when ready.

**Android (Play Console)**
1. Go to Testing → Internal testing. Find the release named `[PROD] 1.4.0 (N)`.
2. **Promote release → Production** (or to closed/open testing first). Set the
   rollout percentage and send it for review.

### The one rule

**Never submit a `[UAT]` build to the store.** UAT builds talk to UAT servers,
carry the UAT name and icon, and have pre-release version names. Always check the
`[PROD]` label before you submit.

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

To release from a maintenance branch, add it to `app.prod_branches`, e.g.
`[main, "release/1.4"]`. Tag `v1.4.1` on that branch.
