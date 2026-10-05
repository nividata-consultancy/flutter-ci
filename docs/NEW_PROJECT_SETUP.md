# New project setup

A step-by-step checklist that takes a Flutter app to working CI. Do the steps in
order. Paths are relative to your **app repo**. `~/Desktop/Projects/flutter-ci` stands
for your local copy of this repository; change it if yours is somewhere else.

At the end:
- pushing `v0.1.0-beta.1` builds UAT (Android goes to the destinations you enabled, iOS to TestFlight);
- pushing `v0.1.0` builds prod the same way.

You can set up **Android first and iOS later** (or the other way round). Use the
platform switch in step 2.

## Before you start

- [ ] The app builds locally: `flutter build appbundle` (Android) and `flutter build ipa` (iOS).
- [ ] The Flutter version is pinned to an **exact** version in `.fvmrc`, e.g.
      `{"flutter": "3.24.5"}`. To create the file:
      `flutter --version` (first line), then `echo '{"flutter": "3.24.5"}' > .fvmrc`.
- [ ] **Google Play** (if you use it): the app exists in Play Console, and **one AAB was
      uploaded by hand** at some point. Google doesn't allow the very first upload
      through the API.
- [ ] **App Store Connect** (for iOS): the app exists, and you have the **Admin** or
      **App Manager** role.

## 1. Copy the templates

```bash
CI=~/Desktop/Projects/flutter-ci
cd your-app-folder
git checkout -b setup-flutter-ci

mkdir -p .github/workflows .ci ios/ci_scripts
cp "$CI/templates/.github/workflows/release.yml"        .github/workflows/release.yml
cp "$CI/templates/.ci/config.yaml"                      .ci/config.yaml
cp "$CI/templates/ios/ci_scripts/ci_post_clone.sh"      ios/ci_scripts/
cp "$CI/templates/ios/ci_scripts/ci_post_xcodebuild.sh" ios/ci_scripts/
cat "$CI/templates/.gitignore.append" >> .gitignore

chmod +x ios/ci_scripts/*.sh
git add .github/workflows/release.yml .ci/config.yaml ios/ci_scripts .gitignore
```

Check that the two scripts are **executable in git**:
```bash
git ls-files -s ios/ci_scripts
```
Both lines must start with `100755`. If not, run:
`git update-index --chmod=+x ios/ci_scripts/ci_post_clone.sh ios/ci_scripts/ci_post_xcodebuild.sh`.
Without this, Xcode Cloud runs them with the wrong shell.

If the app already has a `.github/workflows/release.yml`, don't overwrite it: rename
one of them first.

## 2. Fill in `.ci/config.yaml`

Open `.ci/config.yaml` and change these. Every key is explained in
[CONFIG_REFERENCE.md](CONFIG_REFERENCE.md).

**`app:`**
- `name`: a short name without spaces, e.g. `MathRiddle`. It's used in file names.
- `android_package_name`: your `applicationId`. Find it with `grep applicationId android/app/build.gradle*`.
- `build_number_offset`: if the app is already on Play, set this **higher than the
  highest version code** in Play Console → **App bundle explorer** (e.g. `100`).
  The Android versionCode is the GitHub run number plus this offset.
- `run_tests`: `false` if the app has no working tests.

**`environments.uat` and `environments.prod`:**
- `dart_define_file`: uncomment it if you have `env/uat.json` / `env/prod.json`.
- `android.enabled` / `ios.enabled`: `false` turns that platform off for that environment.
- `android.flavor`: only if `android/app/build.gradle*` has `productFlavors`.
- `android.destinations`: where Android builds go. For the first test, keep only Play
  `enabled: true` (or only Firebase), and turn the others on later:
  ```yaml
        destinations:
          playstore: { enabled: true,  tracks: [internal] }
          firebase:  { enabled: false, groups: "qa-team" }
          drive:     { enabled: false, folder_id: "…" }
  ```

Check the file, then commit:
```bash
~/Desktop/Projects/flutter-ci/scripts/common/read_config.sh validate .ci/config.yaml
git add .ci/config.yaml && git commit -m "Add flutter-ci"
```
If you get errors, each line names the exact key that's wrong.

## 3. Android signing in Gradle

CI writes `android/key.properties` (not in git) with `storeFile`, `storePassword`,
`keyAlias` and `keyPassword`. Your Gradle file must read it. Check first:

```bash
grep -n "key.properties" android/app/build.gradle*
```

If nothing is found, add this to `android/app/build.gradle.kts`.

At the top:
```kotlin
import java.util.Properties
import java.io.FileInputStream
```
Above `android {`:
```kotlin
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
```
Inside `android { }`, replacing the old `buildTypes`. Keep any extra lines your old
`release { }` block had, e.g. `isMinifyEnabled`:
```kotlin
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
            signingConfig = if (keystorePropertiesFile.exists())
                signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }
```

For a Groovy `build.gradle`, the same logic is:
```groovy
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}
android {
    signingConfigs {
        release {
            if (keystorePropertiesFile.exists()) {
                storeFile file(keystoreProperties['storeFile'])
                storePassword keystoreProperties['storePassword']
                keyAlias keystoreProperties['keyAlias']
                keyPassword keystoreProperties['keyPassword']
            }
        }
    }
    buildTypes {
        release {
            signingConfig keystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug
        }
    }
}
```

Use the **upload key** that Play expects. Its SHA-1 must match Play Console → **App integrity
→ Upload key certificate**. Check with:
`keytool -list -v -keystore upload-keystore.jks -alias YOUR_ALIAS`.

```bash
git add android/app/build.gradle* && git commit -m "Read release signing from key.properties"
```

## 4. GitHub settings and signing secrets

**4a. Allow the app repo to use flutter-ci.** In the app repo on GitHub, go to
**Settings → Actions → General**. "Allow all actions and reusable workflows" works.
If actions are restricted, add `nividata-consultancy/flutter-ci@*` to the allowed list
(an org admin may need to do this).

**4b. The four signing secrets** (run in the app folder):
```bash
base64 -i /path/to/upload-keystore.jks | gh secret set ANDROID_KEYSTORE_BASE64
gh secret set ANDROID_KEYSTORE_PASSWORD     # asks for the value
gh secret set ANDROID_KEY_ALIAS
gh secret set ANDROID_KEY_PASSWORD
```
You can also add them on the website: **Settings → Secrets and variables → Actions**.

## 5. Android destinations

Do only the parts for the destinations you set to `enabled: true` in step 2. Each
part is explained click by click in [SECRETS.md](SECRETS.md).

| Destination | One-time setup | Secrets |
|---|---|---|
| **Play internal testing / production draft** | Service account with Play permissions ([SECRETS.md → Google Play](SECRETS.md#google-play)). In Play Console → Internal testing → **Testers**, add an email list and share the "Join on the web" link. | `PLAY_SERVICE_ACCOUNT_JSON` |
| **Firebase App Distribution** | App Distribution turned on, a tester group (use its **alias** in `groups`), and a service account ([SECRETS.md → Firebase](SECRETS.md#firebase-app-distribution)) | `FIREBASE_SERVICE_ACCOUNT_JSON`, `FIREBASE_ANDROID_APP_ID` |
| **Google Drive** | Option A, Shared Drive (Google Workspace only), or Option B, your own Google account plus the folder helper ([SECRETS.md → Google Drive](SECRETS.md#google-drive)) | A: `GDRIVE_SERVICE_ACCOUNT_JSON`<br>B: `GDRIVE_OAUTH_CLIENT_ID`, `GDRIVE_OAUTH_CLIENT_SECRET`, `GDRIVE_OAUTH_REFRESH_TOKEN` |

`gh secret list` shows which secrets exist. You don't need to edit
`.github/workflows/release.yml`; it passes every secret, and missing ones are simply empty.

## 6. iOS: Xcode Cloud

Follow [XCODE_CLOUD_SETUP.md](XCODE_CLOUD_SETUP.md). In short:
1. Signing team set and the **Runner** scheme shared and committed.
2. The app repo's `origin` uses the normal GitHub URL (not an SSH alias).
3. Create the workflow: start on **Tag Changes** (`v…`) → **Archive** of Runner →
   **TestFlight Internal Testing** to your group. Set the environment variable `FLUTTER_CI_REF=v1`.

A different app name or icon for UAT builds is **optional**; see the end of
XCODE_CLOUD_SETUP.md.

## 7. First UAT build

Push your branch, then a tag. The tag message becomes the Firebase release notes.

```bash
git push -u origin setup-flutter-ci
git tag -a v0.1.0-beta.1 -m "First CI build"
git push origin v0.1.0-beta.1
```

The version must be **higher than the version already on the stores**. If the store
has `2.3.0`, use `v2.3.1-beta.1`.

| Where | Success looks like |
|---|---|
| GitHub → **Actions → Release** | All steps green. The summary lists each destination with `success`. |
| Play Console → Internal testing | Release `[UAT] 0.1.0-beta.1 (N)` |
| Firebase → App Distribution | Release `0.1.0-beta.1 (N)` with your tag message |
| Drive | `MathRiddle-uat-0.1.0-beta.1-N.apk` / `.aab` in the folder |
| App Store Connect → Xcode Cloud → Builds | Build for `v0.1.0-beta.1`, then in TestFlight after 10–30 minutes |

If something fails, the error message links to the right part of
[TROUBLESHOOTING.md](TROUBLESHOOTING.md). Always use a **new tag** for the next try.

## 8. First prod build

Tag the commit that QA approved:
```bash
git tag -a v0.1.0 -m "First release"
git push origin v0.1.0
```
To also create a **draft production release** on Play, set
`playstore: { enabled: true, tracks: [internal, production] }` under `environments.prod`
first. The service account then also needs the "Release to production" permission.
How to release builds to users is in [TAGGING_AND_RELEASES.md](TAGGING_AND_RELEASES.md#releasing-to-users).

## Done checklist

- [ ] `v…-beta.N` tags build UAT and reach every enabled destination and TestFlight
- [ ] `v…` tags build prod and reach the same places (plus the Play production draft, if enabled)
- [ ] Firebase testers see the tag message as release notes
- [ ] The team knows the rules in [TAGGING_AND_RELEASES.md](TAGGING_AND_RELEASES.md)
