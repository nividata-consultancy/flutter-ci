# Xcode Cloud setup (iOS)

iOS builds go to **TestFlight only**. Each app has **one** Xcode Cloud workflow. It
starts on every tag beginning with `v`, archives the `Runner` scheme and sends the
build to an internal TestFlight group. The tag decides UAT or prod (version, dart
defines, optional name/icon). There are no separate iOS schemes.

Screen and menu names below are from Xcode 26 / App Store Connect in 2026. Apple
sometimes moves things; the concepts stay the same.

## 1. Prepare the project

Open the **workspace** (not the `.xcodeproj`): `open ios/Runner.xcworkspace`.

**1a. Signing.** Click **Runner** (blue icon) → target **Runner** → **Signing & Capabilities**:
- ✅ **Automatically manage signing**
- **Team:** your Apple developer team
- **Bundle Identifier:** the same as the app in App Store Connect

**1b. Share the Runner scheme and commit it.** Go to **Product → Scheme → Manage
Schemes…** → ✅ **Shared** next to **Runner**. Then:
```bash
git add ios/Runner.xcodeproj/xcshareddata
git commit -m "Share Runner scheme"
git ls-files ios/Runner.xcodeproj/xcshareddata/xcschemes/   # must list Runner.xcscheme
```
Without this, Xcode Cloud says *"Scheme Runner does not exist"*.

**1c. Bootstrap scripts are executable:** `git ls-files -s ios/ci_scripts` shows
`100755` for both files (NEW_PROJECT_SETUP step 1).

**1d. Your Apple account is in Xcode:** **Xcode → Settings → Accounts** lists your Apple
ID with your team.

## 2. Use the normal GitHub URL for `origin`

Xcode Cloud reads the repo's `origin` URL. An SSH alias like `github.com-work` exists
only in your Mac's `~/.ssh/config`, so Apple can't use it. Check:
```bash
git remote -v
```
If it shows something like `git@github.com-work:org/app.git`, change it to the real
host and tell git to use your work key **for this repo only**:
```bash
git remote set-url origin git@github.com:org/app.git           # same path, real host
git config core.sshCommand "ssh -i ~/.ssh/id_rsa_work -o IdentitiesOnly=yes"
git fetch                                                       # must work
```
Then restart Xcode.

## 3. Create an internal testing group

In App Store Connect → your app → **TestFlight** → **Internal Testing → +**:
1. Name it, e.g. `QA` → **Create**.
2. **Testers → +** → add people. They must be users of your App Store Connect team
   (**Users and Access**).
3. Leave **automatic distribution** on.

## 4. Create the workflow

In Xcode, go to **Integrate → Create Workflow…** (or **Integrate → Manage Workflows → +**).
Select the **Runner** product. The first time, Xcode asks to **grant access to GitHub**:
approve it. For an organization repo, an org admin may need to approve the
"Xcode Cloud" GitHub app.

Xcode creates a **Default** workflow (Branch Changes + Build). Click **Edit Workflow…**
and change it. Each part is an item in the **left sidebar**. Hover a heading such as
**START CONDITIONS** and click its **+** to add an item; right-click an item →
**Delete** to remove it.

| Sidebar | Set to |
|---|---|
| **General** | Name: `Release (tags)` |
| **Environment** | **Xcode Version:** a fixed version (the one you use), not "Latest". **Clean:** ✅. **Environment Variables:** `FLUTTER_CI_REF` = `v1` |
| **START CONDITIONS** | **Delete "Branch Changes"**. Add **Tag Changes** → Source Tags: **Custom Tags** → **+** → **Tags Beginning With** `v`. Auto-cancel: off |
| **ACTIONS** | Delete **Build**. Add **Archive** → Platform **iOS** → Scheme **Runner** → Distribution Preparation **TestFlight and App Store** |
| **POST-ACTIONS** | Add **TestFlight Internal Testing** → Groups **+** → your group (step 3) |

Click **Save**. When Xcode offers to **start a build and choose a branch**, press
**Cancel**. Branch builds stop with `CI_TAG is not set`, because flutter-ci only builds tags.

The workflow summary should then read:
```
Start Condition:  Tag Changes (v…)
Action:           Archive – iOS (Runner), TestFlight and App Store
Post-Action:      TestFlight Internal Testing → QA
Environment:      FLUTTER_CI_REF = v1
```

### Environment variables

| Name | Value | Secret | When |
|---|---|---|---|
| `FLUTTER_CI_REF` | `v1` (canary apps: `main`) | no | always |
| `DART_DEFINES_UAT_JSON_BASE64` | `base64 -i env/uat.json \| pbcopy` | yes | only if `env/uat.json` is **not** committed |
| `DART_DEFINES_PROD_JSON_BASE64` | `base64 -i env/prod.json \| pbcopy` | yes | only if `env/prod.json` is **not** committed |
| `SLACK_WEBHOOK_URL` | webhook URL | yes | optional notifications |
| `FLUTTER_CI_APP_DIR` | e.g. `apps/mobile` | no | only if the Flutter app isn't at the repo root |

## 5. First build

Xcode Cloud only reacts to tags pushed **after** the workflow exists:
```bash
git tag -a v0.1.0-beta.1 -m "First iOS build"
git push origin v0.1.0-beta.1
```
Use a version higher than the App Store version. Watch it in **Report navigator (`⌘9`) →
Cloud**, or in App Store Connect → **Xcode Cloud → Builds**:

1. The **ci_post_clone.sh** log ends with `ci_post_clone.sh done: [UAT] v0.1.0-beta.1 (N)`.
2. **Archive** ✅, then **TestFlight Internal Testing** ✅.
3. After 10–30 minutes of Apple processing, the build is in TestFlight.

## What the scripts do

1. `ios/ci_scripts/ci_post_clone.sh` (10 lines) downloads flutter-ci at
   `$FLUTTER_CI_REF` and runs `scripts/xcode-cloud/post_clone.sh`, which:
   - checks the tag and `.ci/config.yaml`, plus the prod guard if `app.prod_branches` is set;
   - stops at once if `ios.enabled: false`;
   - installs Flutter at the version in `.fvmrc`, then runs `flutter precache --ios` and `flutter pub get`;
   - resolves the dart defines and writes `ios/Flutter/Environment.xcconfig` (optional name/icon);
   - runs `flutter build ios --config-only --build-name X.Y.Z --build-number $CI_BUILD_NUMBER`;
   - runs `pod install` if there's an `ios/Podfile`.
2. Xcode Cloud archives `Runner`, and the post-action sends it to TestFlight.
3. `ci_post_xcodebuild.sh` only sends the optional Slack message.

The iOS version is always numbers only (`1.4.0` for both `v1.4.0-beta.1` and
`v1.4.0`), because Apple allows nothing else. The build number is Xcode Cloud's.
To see which tag made a TestFlight build, open **Xcode Cloud → Builds**.

## Turning iOS off for one environment

```yaml
environments:
  uat:
    ios: { enabled: false }
```
Xcode Cloud still starts on the tag, but the build stops in about a minute with
*"iOS is disabled for 'uat'…"* and shows as **failed**. Nothing is sent to TestFlight.
Apple doesn't let a script skip a build as "success", so the red build is expected.

## Optional: different name and icon for UAT

Only if testers should see e.g. **"MyApp UAT"** with a different icon. Apps that don't
need it skip this section. Leave `display_name` / `app_icon` out of the config.

1. **`ios/Flutter/Release.xcconfig`:** keep the existing lines and add:
   ```
   APP_DISPLAY_NAME = MyApp
   ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon

   #include? "Environment.xcconfig"
   ```
   The `#include?` must be the **last** line.
2. **`ios/Flutter/Debug.xcconfig`:** add `APP_DISPLAY_NAME = MyApp Dev` and
   `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`.
3. **Remove Xcode's own icon setting**, which would override it:
   ```bash
   sed -i '' '/ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;/d' ios/Runner.xcodeproj/project.pbxproj
   ```
4. **`ios/Runner/Info.plist`:** `<key>CFBundleDisplayName</key><string>$(APP_DISPLAY_NAME)</string>`
5. **UAT icon:** `cp -R ios/Runner/Assets.xcassets/AppIcon.appiconset ios/Runner/Assets.xcassets/AppIcon-UAT.appiconset`,
   then replace its images with a version marked "UAT".
6. **Config:**
   ```yaml
     uat:
       ios: { enabled: true, display_name: "MyApp UAT", app_icon: AppIcon-UAT }
     prod:
       ios: { enabled: true, display_name: "MyApp", app_icon: AppIcon }
   ```
7. **Check locally:**
   ```bash
   flutter build ios --config-only --release --no-codesign
   printf 'APP_DISPLAY_NAME = MyApp UAT\nASSETCATALOG_COMPILER_APPICON_NAME = AppIcon-UAT\n' > ios/Flutter/Environment.xcconfig
   xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release -showBuildSettings 2>/dev/null \
     | grep -E ' (APP_DISPLAY_NAME|ASSETCATALOG_COMPILER_APPICON_NAME) ='
   rm ios/Flutter/Environment.xcconfig
   ```

`example/ios` in this repo has this setup done. A per-environment
`GoogleService-Info.plist` works the same way: set `google_service_info: path/to/file`
and CI copies it to `ios/Runner/`.

**Apps with iOS flavors (separate schemes):** not supported yet, because one Xcode Cloud
workflow builds one fixed scheme. Ask the flutter-ci maintainers before setting one up.

## Updating flutter-ci

`FLUTTER_CI_REF=v1` picks up every non-breaking flutter-ci release automatically. To
pin an exact version, use e.g. `v1.2.0`.
