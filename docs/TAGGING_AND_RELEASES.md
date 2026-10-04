# Tagging and releases

A guide for app developers. Builds start **only** when you push a tag.

## Tag format

| Tag | Environment | Example | Goes to |
|---|---|---|---|
| `vX.Y.Z-beta.N` | **UAT** | `v1.4.0-beta.1` | Play internal track, TestFlight (labeled `[UAT]`), plus Firebase/Drive if configured |
| `vX.Y.Z` | **prod** | `v1.4.0` | Play internal track, TestFlight (labeled `[PROD]`) |
| anything else starting with `v` | build fails | `v1.4`, `v1.4.0-rc1` | nothing |

- UAT and prod tags can be on **any branch**.
- Optional **prod guard**: if the app sets `app.prod_branches` (e.g. `[main]`),
  prod tags must be on a commit already on one of those branches, otherwise the build fails.
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

## Release notes for testers

Write the notes in the **tag message** by creating an annotated tag with `-a`:

```bash
git tag -a v1.4.0-beta.1 -m "Login crash fixed
Dark mode added, please test on iPad"
```

The message is shown, after the `[UAT] v1.4.0-beta.1 · abc1234` header line, in:

| Where | Limit |
|---|---|
| TestFlight "What to Test" | 1,000 bytes |
| Firebase App Distribution release notes | 500 bytes (Android), 1,000 bytes (iOS) |
| Play Console "What's new" | 500 characters |
| GitHub Release body (with the commit list added below) | 4,000 bytes |

A plain tag without a message (`git tag v1.4.0-beta.1`) works too. The notes are then
the latest commit subjects since the previous tag. Keep the important part of
the message at the top, because longer messages are cut at the limits above.

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

Tag `v1.4.1` on the hotfix branch. If the app uses `app.prod_branches`, add the
branch to it, e.g. `[main, "release/1.4"]`.
