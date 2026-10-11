# iOS setup

Follow the steps in order. When you're done, pushing a tag such as `v1.0.0-beta.1`
makes Xcode Cloud build the app and send it to your TestFlight testers. iOS builds go to
TestFlight only.

You need:
- a Mac with Xcode, signed in with your Apple developer account;
- the app in App Store Connect, and the **Admin** or **App Manager** role.

Run all commands in your **app folder**.

---

## Step 1: Copy the files (skip if you did the Android setup)

Do [Android setup](ANDROID_SETUP.md) Step 1 (copy the files) and Step 2 (fill in the config).

**Apps with flavor main files** (no `lib/main.dart`, e.g. `lib/main_myapp.dart`): set
the iOS main file under both environments, or the archive fails with
"PhaseScriptExecution failed":
```yaml
    ios:
      enabled: true
      target: lib/main_myapp.dart
```

If you don't use Android, turn it off in `.ci/config.yaml` under both environments:
```yaml
    android:
      enabled: false
```

Check that the two scripts are executable:
```bash
git ls-files -s ios/ci_scripts
```
Both lines must start with `100755`. If not:
```bash
git update-index --chmod=+x ios/ci_scripts/ci_post_clone.sh ios/ci_scripts/ci_post_xcodebuild.sh
```

## Step 2: Prepare the Xcode project

```bash
open ios/Runner.xcworkspace
```
Open the **.xcworkspace**, not the .xcodeproj.

1. **Signing:** click **Runner** (blue icon, top left) → target **Runner** → **Signing &
   Capabilities**:
   - ✅ Automatically manage signing
   - **Team:** your team
   - **Bundle Identifier:** the same as in App Store Connect
2. **Share the scheme:** **Product → Scheme → Manage Schemes…** → ✅ **Shared** next to
   **Runner** → Close.
3. **Commit:**
   ```bash
   git add ios
   git commit -m "Prepare iOS for Xcode Cloud"
   git push
   git ls-files ios/Runner.xcodeproj/xcshareddata/xcschemes/   # must list Runner.xcscheme
   ```

## Step 3: Fix the GitHub address

Xcode Cloud needs the normal GitHub address of the repo. Check it:
```bash
git remote -v
```
- If it shows `git@github.com:…` or `https://github.com/…`, it's fine. Go to Step 4.
- If it shows an alias such as `git@github.com-work:org/app.git`, change it:
  ```bash
  git remote set-url origin git@github.com:org/app.git        # same path, real host
  git config core.sshCommand "ssh -i ~/.ssh/id_rsa_work -o IdentitiesOnly=yes"   # your work key
  git fetch                                                    # must work
  ```
  Then quit and reopen Xcode.

## Step 4: Create a TestFlight group

https://appstoreconnect.apple.com → **Apps** → your app → **TestFlight** → **Internal
Testing +** → name `QA` → **Create** → **Testers +** → add people → **Add**.

Internal testers must be users of your team (**Users and Access**). Keep **automatic
distribution** on.

## Step 5: Create the Xcode Cloud workflow

In Xcode: **Integrate → Create Workflow…** (menu bar at the top).

1. Select **Runner** → **Next**.
2. If Xcode asks to **grant access to GitHub**, approve it. For a company repo, a GitHub
   org admin may need to approve the "Xcode Cloud" app.
3. Click **Edit Workflow…**. In the editor, each part is an item in the **left sidebar**.
   To add an item, hover a heading and click its **+**. To remove one, right-click it →
   **Delete**.

| Sidebar | What to set |
|---|---|
| **General** | Name: `Release (tags)` |
| **Environment** | **Xcode Version:** the same version you use (not "Latest") · **Clean:** ✅ · **Environment Variables → +:** `FLUTTER_CI_REF` = `v1` |
| **START CONDITIONS** | Delete **Branch Changes**. Add **Tag Changes** → **Custom Tags** → **+** → **Tags Beginning With** → `v` |
| **ACTIONS** | Delete **Build**. Add **Archive** → Platform **iOS** · Scheme **Runner** ([flavor apps](#apps-with-flavors): the flavor's scheme) · Distribution Preparation **App Store** (older Xcode: "TestFlight and App Store"; never **None**) |
| **POST-ACTIONS** | Add **TestFlight Internal Testing** → Groups **+** → `QA`. Greyed out? Save first, and check that the `QA` group (Step 4) and the app exist in App Store Connect. |

4. Click **Save**.
5. If Xcode asks to **start a build and choose a branch**, press **Cancel**. Builds only
   run from tags.

Check it in **Integrate → Manage Workflows**: there must be **only** `Release (tags)`.
Delete any **Default** workflow; it would build on every commit.

**Only if the app is in a subfolder of the repo:** add `FLUTTER_CI_APP_DIR` = the folder
(e.g. `my_app`). **Only if the config file isn't `.ci/config.yaml`:** add
`FLUTTER_CI_CONFIG_PATH` (relative to that folder, e.g. `.ci/juna_bhajan.yaml`).

**Only if `env/uat.json` / `env/prod.json` are not in git:** add the environment variables
`DART_DEFINES_UAT_JSON_BASE64` and `DART_DEFINES_PROD_JSON_BASE64` with ✅ **Secret**. Get
each value with `base64 -i env/uat.json | pbcopy`.

## Step 6: First build

Push a **new** tag. Xcode Cloud ignores tags created before the workflow existed.
The tag's version must match `version:` in `pubspec.yaml` (e.g. `1.0.0+101` → `v1.0.0-beta.1`),
and the version and build number must be higher than what's already on App Store Connect:
```bash
git tag -a v1.0.0-beta.1 -m "First iOS build"
git push origin v1.0.0-beta.1
```

Watch it in Xcode → **Report navigator (`⌘9`) → Cloud**, or in App Store Connect → your app
→ **Xcode Cloud → Builds**:
1. **ci_post_clone.sh** ends with `ci_post_clone.sh done: [UAT] v1.0.0-beta.1 (N)`.
2. **Archive** ✅, then **TestFlight Internal Testing** ✅.
3. After 10–30 minutes, the build is in TestFlight and your testers get it.

If something fails, open the red step and read the line starting with `ERROR:`.
See [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

**Not building iOS for some tags?** Set `ios: { enabled: false }` for that environment.
The Xcode Cloud build then stops after about a minute with "iOS is disabled" and shows
red. That's expected.

Daily use: [RELEASES.md](RELEASES.md)

## iOS build number

Xcode Cloud **replaces** the build number when it prepares the build for TestFlight. It
uses its own counter (`CI_BUILD_NUMBER`), which goes up by 1 for **every** Xcode Cloud
build of the app, failed ones included. The version (`1.9.16`) still comes from pubspec.

To start the counter where pubspec is (e.g. pubspec says `+42`):
App Store Connect → your app → **Xcode Cloud** → **Settings** → **Build Number** →
**Next Build Number** → `42` (or higher than the last build in TestFlight) → **Save**.

After that, the numbers only stay equal if every tag raises pubspec by 1 and no Xcode
Cloud build fails or is disabled. The `ci_post_clone.sh` log warns when they differ.

---

## Optional: different name and icon for UAT

Only if testers should see e.g. **"MyApp UAT"** with a different icon. Most apps don't
need this.

1. `ios/Flutter/Release.xcconfig`: keep the existing lines and add, with the `#include?`
   line **last**:
   ```
   APP_DISPLAY_NAME = MyApp
   ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon

   #include? "Environment.xcconfig"
   ```
2. `ios/Flutter/Debug.xcconfig`: add `APP_DISPLAY_NAME = MyApp Dev` and
   `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`.
3. Remove Xcode's own icon setting:
   `sed -i '' '/ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;/d' ios/Runner.xcodeproj/project.pbxproj`
4. `ios/Runner/Info.plist`: set `CFBundleDisplayName` to `$(APP_DISPLAY_NAME)`.
5. UAT icon: `cp -R ios/Runner/Assets.xcassets/AppIcon.appiconset ios/Runner/Assets.xcassets/AppIcon-UAT.appiconset`,
   then replace its images.
6. Config:
   ```yaml
     uat:
       ios: { enabled: true, display_name: "MyApp UAT", app_icon: AppIcon-UAT }
     prod:
       ios: { enabled: true, display_name: "MyApp", app_icon: AppIcon }
   ```
7. Commit, push, and use a new tag.

## Apps with flavors

For apps with one Xcode scheme per flavor (e.g. `westWind`, `santaCruz`), each flavor is
a separate app with its own config file (see
[ANDROID_SETUP.md → Several apps from one repo](ANDROID_SETUP.md#several-apps-from-one-repo)).

1. In each config, set the flavor and its main file under both environments:
   ```yaml
       ios:
         enabled: true
         flavor: westWind              # the Xcode scheme name
         target: lib/west_wind_main.dart
   ```
2. Share **every** flavor scheme (Step 2, ✅ **Shared**) and commit them.
3. Create **one Xcode Cloud workflow per flavor** (Step 5), each in that flavor's app in
   App Store Connect, with:
   - **Archive → Scheme:** the flavor's scheme (e.g. `westWind`), not `Runner`;
   - **Environment Variables:** `FLUTTER_CI_CONFIG_PATH` = that flavor's config
     (e.g. `.ci/west_wind.yaml`), plus `FLUTTER_CI_REF` = `v1`.

If the workflow's scheme and `ios.flavor` don't match, the build stops early and says so.
Every flavor's workflow starts on every tag.
