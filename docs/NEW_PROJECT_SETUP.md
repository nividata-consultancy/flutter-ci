# New project setup

A copy-paste checklist that takes a Flutter app to working CI. Work through it
top to bottom; most steps take a few minutes. When you are done, pushing
`v0.1.0-beta.1` produces an Android UAT build on Play internal testing and an
iOS UAT build in TestFlight labeled `[UAT]`, and pushing `v0.1.0`
produces `[PROD]` builds in both places.

Paths below are relative to your app repo. `nividata-consultancy/flutter-ci` is this
repository.

## Before you start

- [ ] The app builds locally with `flutter build appbundle` and `flutter build ipa`.
- [ ] The app pins its Flutter version in `.fvmrc` (`{"flutter": "3.24.5"}`) or in
      `pubspec.yaml` (`environment: flutter: "3.24.5"`), as an exact version.
- [ ] **Google Play:** the app exists in Play Console, and **one AAB has been uploaded
      manually** (to any testing track). The Play API cannot create an app or do the
      first upload. See [TROUBLESHOOTING.md](TROUBLESHOOTING.md#first-play-upload).
- [ ] **App Store Connect:** the app record exists (same bundle ID for UAT and prod).
- [ ] You are an admin of the GitHub repo and have the App Manager or Admin role in App Store Connect.

## 1. Copy the templates

From a checkout of `flutter-ci` (or download the files from GitHub):

```bash
APP=~/src/my-app                     # your app repo
CI=~/src/flutter-ci                  # a checkout of nividata-consultancy/flutter-ci

mkdir -p "$APP/.github/workflows" "$APP/.ci" "$APP/ios/ci_scripts"
cp "$CI/templates/.github/workflows/release.yml"   "$APP/.github/workflows/release.yml"
cp "$CI/templates/.ci/config.yaml"                 "$APP/.ci/config.yaml"
cp "$CI/templates/ios/ci_scripts/ci_post_clone.sh"      "$APP/ios/ci_scripts/"
cp "$CI/templates/ios/ci_scripts/ci_post_xcodebuild.sh" "$APP/ios/ci_scripts/"
cat "$CI/templates/.gitignore.append" >> "$APP/.gitignore"

cd "$APP"
chmod +x ios/ci_scripts/*.sh
git add ios/ci_scripts/*.sh
git update-index --chmod=+x ios/ci_scripts/ci_post_clone.sh ios/ci_scripts/ci_post_xcodebuild.sh
```

The execute bit matters. Without it, Xcode Cloud runs the scripts with `zsh`
and ignores the `#!/bin/bash` line. Check it with `git ls-files -s ios/ci_scripts`,
where both files must show `100755`.

`ios/ci_scripts/` must sit next to `Runner.xcworkspace`, which is the default
Flutter layout.

## 2. Fill in `.ci/config.yaml`

Edit the copied file. The full schema is in [CONFIG_REFERENCE.md](CONFIG_REFERENCE.md).

- `app.name`: a short name used in artifact names and notifications.
- `app.android_package_name`: your `applicationId`. It is the same for UAT and prod.
- `app.build_number_offset`: Android `versionCode` = GitHub run number + offset.
  If the app is already on Play, set the offset above the highest versionCode
  already uploaded, e.g. `1000`.
- `environments.uat` / `environments.prod`: dart define files, Android artifacts and
  destinations, and iOS display name and icon.
- Dart defines: commit `env/uat.json` and `env/prod.json`, **or** keep them out of git and
  use the `DART_DEFINES_UAT_JSON` / `DART_DEFINES_PROD_JSON` secrets (step 4).

Validate the file locally:

```bash
brew install yq   # mikefarah/yq v4
"$CI/scripts/common/read_config.sh" validate .ci/config.yaml
```

## 3. Android signing in Gradle

CI writes `android/key.properties` (outside git) with `storeFile`,
`storePassword`, `keyAlias` and `keyPassword`. Your `android/app/build.gradle.kts`
must read it. This is the standard Flutter setup:

```kotlin
import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    // ...
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
```

`example/android/app/build.gradle.kts` in this repo has a working version
that falls back to debug keys when `key.properties` is missing.

**Flavors (optional):** if you set `environments.<env>.android.flavor`, the
flavor must exist in `productFlavors`. If you don't set one, the build runs without `--flavor`.

## 4. Add the GitHub secrets

In the app repo, go to **Settings → Secrets and variables → Actions → New repository secret**,
or use the `gh` CLI. You need at least the four signing secrets plus one secret per destination
you use. [SECRETS.md](SECRETS.md) shows how to create each one.

```bash
base64 -i upload-keystore.jks | gh secret set ANDROID_KEYSTORE_BASE64
gh secret set ANDROID_KEYSTORE_PASSWORD
gh secret set ANDROID_KEY_ALIAS
gh secret set ANDROID_KEY_PASSWORD
gh secret set PLAY_SERVICE_ACCOUNT_JSON < play-service-account.json
```

Then delete the lines for unused destinations from `.github/workflows/release.yml`
(unused lines are harmless).

## 5. One-time iOS project setup

flutter-ci always builds the `Runner` scheme and changes the per-environment
settings through a generated `ios/Flutter/Environment.xcconfig`. Wire it up
once:

1. **`ios/Flutter/Release.xcconfig`**: add defaults and the optional include
   (`#include?` does not fail when the file is missing locally):

   ```
   #include "Generated.xcconfig"

   APP_DISPLAY_NAME = MyApp
   ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon

   #include? "Environment.xcconfig"
   ```

   If you use CocoaPods, keep the Pods include line that is already there
   (`#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.release.xcconfig"`).

2. **`ios/Flutter/Debug.xcconfig`**: add the same two defaults (for local runs):

   ```
   APP_DISPLAY_NAME = MyApp Dev
   ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon
   ```

3. **Remove the target-level app icon setting.** Xcode's target settings
   override xcconfig files. Open `ios/Runner.xcworkspace`, select
   **Runner (target) → Build Settings → All**, search for `App Icon`, select the
   **Primary App Icon Set Name** row and press **Delete**. The value should
   then come from the xcconfig (it shows `AppIcon`, no longer bold). Or, from the
   terminal:

   ```bash
   sed -i '' '/ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;/d' ios/Runner.xcodeproj/project.pbxproj
   ```

4. **`ios/Runner/Info.plist`**: use the variable for the display name:

   ```xml
   <key>CFBundleDisplayName</key>
   <string>$(APP_DISPLAY_NAME)</string>
   ```

5. **UAT icon**: in `ios/Runner/Assets.xcassets`, add an app icon set named
   `AppIcon-UAT`, e.g. the normal icon with a "UAT" banner. To start with a copy:
   `cp -R ios/Runner/Assets.xcassets/AppIcon.appiconset ios/Runner/Assets.xcassets/AppIcon-UAT.appiconset`.

6. **Firebase (optional):** to use a different `GoogleService-Info.plist` per
   environment, commit them at the paths you set in `google_service_info`, e.g.
   `ios/config/uat/GoogleService-Info.plist`. CI copies the right one to
   `ios/Runner/GoogleService-Info.plist`.

Check the result locally:

```bash
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release -showBuildSettings \
  | grep -E ' (APP_DISPLAY_NAME|ASSETCATALOG_COMPILER_APPICON_NAME) ='
```

`example/ios` in this repo has this setup done.

## 6. Create the Xcode Cloud workflow

Follow [XCODE_CLOUD_SETUP.md](XCODE_CLOUD_SETUP.md). In short:
- Start condition: **Tag Changes**, custom tags beginning with `v`.
- Action: **Archive** of `Runner`, with distribution preparation **TestFlight and App Store** (so `[PROD]` builds can be submitted).
- Post-action: **TestFlight Internal Testing** to your QA group.
- Environment variables: `FLUTTER_CI_REF=v1`, plus any base64 secrets.

## 7. First test build (UAT)

Commit everything and push. Then create an **annotated** tag. Its message
becomes the release notes testers see in TestFlight, Firebase and Play:

```bash
git tag -a v0.1.0-beta.1 -m "First CI build
Please check login and the home screen"
git push origin v0.1.0-beta.1
```

- **GitHub → Actions → Release**: the run should finish green. The job summary
  shows the environment, version, versionCode and destinations. The AAB is on
  Play's internal track as `[UAT] 0.1.0-beta.1 (N)`.
- **App Store Connect → Xcode Cloud**: the build runs and reaches TestFlight. Its
  "What to Test" starts with `[UAT] v0.1.0-beta.1 · <sha>`, and the app is
  named "MyApp UAT" with the UAT icon.

If something fails, the error message links to the right section of
[TROUBLESHOOTING.md](TROUBLESHOOTING.md).

Tip: to test the Android side without distributing anything, temporarily set
`dry-run: true` in `.github/workflows/release.yml`.

## 8. First prod build

Tag the commit QA approved. Any branch works, unless you set `app.prod_branches`:

```bash
git tag -a v0.1.0 -m "First release"
git push origin v0.1.0
```

This produces `[PROD]` builds on Play internal testing and in TestFlight. Promote
them manually as described in [TAGGING_AND_RELEASES.md](TAGGING_AND_RELEASES.md#promoting-to-production).

## Done checklist

- [ ] `v0.1.0-beta.1` gives an Android UAT build on Play internal and an iOS `[UAT]` build in TestFlight
- [ ] `v0.1.0` gives `[PROD]` builds in both places
- [ ] Testers see your tag message as the release notes (TestFlight "What to Test", Firebase, Play)
- [ ] The team knows the rules in [TAGGING_AND_RELEASES.md](TAGGING_AND_RELEASES.md)
