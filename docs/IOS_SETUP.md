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
| **ACTIONS** | Delete **Build**. Add **Archive** → Platform **iOS** · Scheme **Runner** · Distribution Preparation **TestFlight and App Store** |
| **POST-ACTIONS** | Add **TestFlight Internal Testing** → Groups **+** → `QA` |

4. Click **Save**.
5. If Xcode asks to **start a build and choose a branch**, press **Cancel**. Builds only
   run from tags.

Check it in **Integrate → Manage Workflows**: there must be **only** `Release (tags)`.
Delete any **Default** workflow; it would build on every commit.

**Only if `env/uat.json` / `env/prod.json` are not in git:** add the environment variables
`DART_DEFINES_UAT_JSON_BASE64` and `DART_DEFINES_PROD_JSON_BASE64` with ✅ **Secret**. Get
each value with `base64 -i env/uat.json | pbcopy`.

## Step 6: First build

Push a **new** tag. Xcode Cloud ignores tags created before the workflow existed:
```bash
git tag -a v1.0.0-beta.1 -m "First iOS build"
git push origin v1.0.0-beta.1
```
Use a version **higher** than the one on the App Store.

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

**Apps with iOS flavors (separate schemes per environment)** aren't supported yet. Ask
the flutter-ci maintainers first.
