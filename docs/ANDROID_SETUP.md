# Android setup

Follow the steps in order. When you're done, pushing a tag such as `v1.0.0-beta.1`
builds your app on GitHub and sends it to Play internal testing, Firebase or Google
Drive, whichever you switch on.

You need:
- the app repo on GitHub, with admin access;
- the **upload keystore** (`.jks`) and its passwords;
- on your Mac: `brew install yq gh`, then `gh auth login`.

Run all commands in your **app folder**. `~/Desktop/Projects/flutter-ci` is your local
copy of flutter-ci; change the path if yours is somewhere else.

---

## Step 1: Copy the files

```bash
CI=~/Desktop/Projects/flutter-ci
mkdir -p .github/workflows .ci ios/ci_scripts
cp "$CI/templates/.github/workflows/release.yml"        .github/workflows/release.yml
cp "$CI/templates/.ci/config.yaml"                      .ci/config.yaml
cp "$CI/templates/ios/ci_scripts/ci_post_clone.sh"      ios/ci_scripts/
cp "$CI/templates/ios/ci_scripts/ci_post_xcodebuild.sh" ios/ci_scripts/
cat "$CI/templates/.gitignore.append" >> .gitignore
chmod +x ios/ci_scripts/*.sh
```
The `ios/ci_scripts` files are for iOS later; copying them now does no harm.

If the app has no `.fvmrc` yet, pin its Flutter version:
```bash
flutter --version                       # first line, e.g. "Flutter 3.24.5"
echo '{"flutter": "3.24.5"}' > .fvmrc
```

## Step 2: Fill in the config

Open `.ci/config.yaml` and change only these:

| Key | Set to |
|---|---|
| `app.name` | Short name without spaces, e.g. `MathRiddle` |
| `app.android_package_name` | Your applicationId: `grep applicationId android/app/build.gradle*` |
| `app.build_number_offset` | If the app is already on Play: a number **higher** than the highest version code in Play Console → App bundle explorer (e.g. `100`). Otherwise `0`. |
| `app.run_tests` | `false` if the app has no working tests |
| `dart_define_file` | Uncomment it if you have `env/uat.json` / `env/prod.json` |
| `android.flavor` | Only if your Gradle file has `productFlavors` |

Leave `destinations` as it is for now; Step 5 covers it.

Check the file:
```bash
~/Desktop/Projects/flutter-ci/scripts/common/read_config.sh validate .ci/config.yaml
```
It must print `Config .ci/config.yaml is valid.`

## Step 3: Signing in Gradle

CI creates `android/key.properties` during the build. Your Gradle file must read it.
Check whether it already does:
```bash
grep -n "key.properties" android/app/build.gradle*
```
If something is found, skip to Step 4. Otherwise, edit `android/app/build.gradle.kts`.

**At the very top:**
```kotlin
import java.util.Properties
import java.io.FileInputStream
```

**Just above `android {`:**
```kotlin
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
```

**Inside `android { }`**, replace the `buildTypes { … }` block. If the old `release { }` had
other lines (like `isMinifyEnabled`), keep them in the new one:
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

<details>
<summary>Groovy (<code>build.gradle</code> without .kts)</summary>

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
</details>

## Step 4: Signing secrets

Check that the keystore is right. It asks for the password and must print the key:
```bash
keytool -list -v -keystore /path/to/upload-keystore.jks -alias YOUR_ALIAS
```
If the app is already on Play, the **SHA1** must match Play Console → App integrity →
**Upload key certificate**. Never make a new keystore for an app already on Play.

Add the four secrets to the app repo:
```bash
base64 -i /path/to/upload-keystore.jks | gh secret set ANDROID_KEYSTORE_BASE64
gh secret set ANDROID_KEYSTORE_PASSWORD       # type or paste the value
gh secret set ANDROID_KEY_ALIAS
gh secret set ANDROID_KEY_PASSWORD
```

If the app repo restricts GitHub Actions, allow flutter-ci: GitHub → app repo →
**Settings → Actions → General** → allow `nividata-consultancy/flutter-ci@*`.

## Step 5: Choose where builds go

In `.ci/config.yaml`, each destination has a switch. Builds go **only** where it says
`enabled: true`:
```yaml
      destinations:
        playstore: { enabled: true,  tracks: [internal] }   # 5A
        firebase:  { enabled: false, groups: "qa-team" }    # 5B
        drive:     { enabled: false, folder_id: "…" }       # 5C
```
UAT and prod have their own switches. Do only the parts below for what you switch on.
**Tip:** start with one destination, and add the others when it works.

### 5A: Play Store

1. **First upload by hand** (only once per app): if the app has never had a build in Play
   Console, run `flutter build appbundle` and upload it in Play Console → **Testing →
   Internal testing → Create new release**. Google doesn't allow the first upload by API.
2. **Testers:** Play Console → **Internal testing → Testers** → create an email list.
   Send the **"Join on the web"** link to the testers.
3. **Service account:**
   1. https://console.cloud.google.com → create a project → **APIs & Services → Library →
      Google Play Android Developer API → Enable**.
   2. **IAM & Admin → Service Accounts → Create service account** (name `play-uploader`) → **Done**.
   3. Open it → **Keys → Add key → Create new key → JSON**. A file downloads.
   4. Play Console → **Users and permissions → Invite new users** → the service account's
      email → **App permissions → Add app** → your app → tick **View app information**,
      **Release apps to testing tracks** and **Manage testing tracks and edit tester
      lists** → **Invite user**.
4. **Secret:**
   ```bash
   gh secret set PLAY_SERVICE_ACCOUNT_JSON < ~/Downloads/your-key.json
   ```
   Then delete the downloaded file.

| `tracks` | Result |
|---|---|
| `[internal]` | Internal testing (UAT and prod) |
| `[internal, production]` | Internal testing + a **draft** release on Production (prod only) |
| `[production]` | Only a **draft** on Production (prod only) |

For production, also tick **Release to production, exclude devices, and use Play App
Signing** in step 3.4. A draft never reaches users until someone presses **Release** in
Play Console.

A new service account can take **up to 24 hours** to work. If the app has **never been
published**, add `status: draft`:
`playstore: { enabled: true, tracks: [internal], status: draft }`.

### 5B: Firebase App Distribution

1. Firebase console → your project → ⚙️ **Project settings → Your apps**: there must be an
   **Android** app with your package name (otherwise **Add app → Android**). Copy its **App
   ID** (`1:1234…:android:abc…`).
2. **Run → App Distribution → Get started**.
3. **Testers & Groups → Add group** → add the testers' emails. Put the group's **alias**
   (shown under its name) in the config: `groups: "qa-team"`.
4. https://console.cloud.google.com, **same project** → **IAM & Admin → Service Accounts →
   Create** → role **Firebase App Distribution Admin** → **Done** → open it → **Keys → Add
   key → JSON**.
5. **Secrets:**
   ```bash
   gh secret set FIREBASE_SERVICE_ACCOUNT_JSON < ~/Downloads/firebase-key.json
   gh secret set FIREBASE_ANDROID_APP_ID --body "1:1234567890:android:abc123"
   ```

Testers get an email and install with the **App Tester** app. The **tag message** is
used as the release notes.

### 5C: Google Drive

Pick **one** option.

#### Option 1: Shared Drive (only with Google Workspace)

1. Cloud Console → **APIs & Services → Library → Google Drive API → Enable** → create a
   service account → **Keys → JSON**.
2. Google Drive → **Shared drives → New** → **Manage members** → add the service account
   email as **Content manager**.
3. Create a folder in the shared drive, open it, and copy the ID from the address bar
   (`…/folders/<ID>`) into `folder_id`.
4. `gh secret set GDRIVE_SERVICE_ACCOUNT_JSON < ~/Downloads/drive-key.json`

#### Option 2: your own Google account

Works with a normal (free) Google account. Best practice is a separate account just for
builds (e.g. `company.builds@gmail.com`); you share the folder with the team.
Do steps 1–4 **signed in as that account**, once. After that, only step 5 is needed per app.

1. https://console.cloud.google.com → new project → **APIs & Services → Library → Google
   Drive API → Enable**.
2. **Google Auth Platform** (OAuth consent screen):
   - **Branding:** app name `flutter-ci uploads`; support email and developer email = the
     builds account; **App home page** and **Privacy policy link** = pages on your
     company website; **Authorized domains** = your company domain. **No logo.** Save.
   - **Data Access → Add or remove scopes:** add `https://www.googleapis.com/auth/drive.file`.
   - **Audience:** External → **Publish app**, so it says **In production**. Otherwise the
     token stops working after 7 days.
3. **Credentials → Create credentials → OAuth client ID** → **Web application** →
   Authorized redirect URI `https://developers.google.com/oauthplayground` → **Create**.
   Copy the **Client ID** and **Client secret**.
4. https://developers.google.com/oauthplayground → ⚙️ → ✅ **Use your own OAuth
   credentials** → paste both → in **Input your own scopes** type
   `https://www.googleapis.com/auth/drive.file` → **Authorize APIs** → sign in with the
   builds account → **Allow** → **Exchange authorization code for tokens** → copy the
   **Refresh token**.
5. **Create the folder** in the Mac Terminal. Folders made by hand in Drive don't work:
   ```bash
   ~/Desktop/Projects/flutter-ci/scripts/tools/gdrive_create_folder.sh "MathRiddle builds"
   ```
   Paste the client ID, the client secret and the refresh token when asked (the last two
   stay invisible). It prints a link and a `folder_id`. Put the `folder_id` in the config,
   then open the link and **Share** the folder with your team.
6. **Secrets** (in each app that uploads to Drive):
   ```bash
   gh secret set GDRIVE_OAUTH_CLIENT_ID
   gh secret set GDRIVE_OAUTH_CLIENT_SECRET
   gh secret set GDRIVE_OAUTH_REFRESH_TOKEN
   ```

## Step 6: First build

Check the config and commit everything:
```bash
~/Desktop/Projects/flutter-ci/scripts/common/read_config.sh validate .ci/config.yaml
gh secret list                    # all secrets for your destinations are there
git add -A && git commit -m "Set up flutter-ci" && git push
```

Push a tag. The message is the release note for Firebase:
```bash
git tag -a v1.0.0-beta.1 -m "First CI build"
git push origin v1.0.0-beta.1
```
Use a version **higher** than the one already on Play.

Open GitHub → the app repo → **Actions → Release**. After about 10 minutes, all steps are
green, and the **Summary** at the bottom lists each destination with `success`.

If a step is red, open it and read the line starting with `Error:`; it says what to fix.
See also [TROUBLESHOOTING.md](TROUBLESHOOTING.md). Always push a **new** tag for the next
try (`-beta.2`, `-beta.3`, …).

**Not setting up iOS yet?** Set `ios: { enabled: false }` under both environments in the
config. Otherwise every tag also starts Xcode Cloud, if it's already set up.

Next: [iOS setup](IOS_SETUP.md) · Daily use: [RELEASES.md](RELEASES.md)
