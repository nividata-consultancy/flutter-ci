# Secrets

This repository is public and never holds secrets. Every secret lives in the
**app repo** (GitHub) or the **Xcode Cloud workflow** (iOS).

GitHub's `secrets: inherit` only works inside one organization or enterprise.
Our apps live in different organizations, so the caller workflow
(`templates/.github/workflows/release.yml`) passes each secret explicitly. The
reusable workflow marks them all as `required: false` and checks at runtime
which ones the configured destinations need, with a clear error if one is missing.

## Overview

### GitHub (Android): app repo → Settings → Secrets and variables → Actions

| Secret | Needed when | Format |
|---|---|---|
| `ANDROID_KEYSTORE_BASE64` | always (except dry-run) | base64 of the upload keystore `.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | always (except dry-run) | text |
| `ANDROID_KEY_ALIAS` | always (except dry-run) | text |
| `ANDROID_KEY_PASSWORD` | always (except dry-run) | text |
| `PLAY_SERVICE_ACCOUNT_JSON` | `playstore` destination | service account JSON, plain |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | `firebase` destination | service account JSON, plain |
| `FIREBASE_ANDROID_APP_ID` | `firebase` destination | `1:1234567890:android:abc123…` |
| `GDRIVE_SERVICE_ACCOUNT_JSON` | `drive` destination, Option A (Shared Drive) | service account JSON, plain |
| `GDRIVE_OAUTH_CLIENT_ID` / `GDRIVE_OAUTH_CLIENT_SECRET` / `GDRIVE_OAUTH_REFRESH_TOKEN` | `drive` destination, Option B (your own My Drive) | text |
| `DART_DEFINES_UAT_JSON` | UAT dart defines not committed | JSON, plain |
| `DART_DEFINES_PROD_JSON` | prod dart defines not committed | JSON, plain |
| `SLACK_WEBHOOK_URL` | optional | `https://hooks.slack.com/services/…` |

### Xcode Cloud

See [Xcode Cloud](#xcode-cloud) below. Values are **base64** because secret
environment variables are single-line.

## Android signing

Use the **upload key** from Play App Signing, not the app signing key.

```bash
# Create one, if the app doesn't have it yet:
keytool -genkeypair -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias upload

# macOS
base64 -i upload-keystore.jks | gh secret set ANDROID_KEYSTORE_BASE64
# Linux
base64 -w0 upload-keystore.jks | gh secret set ANDROID_KEYSTORE_BASE64

gh secret set ANDROID_KEYSTORE_PASSWORD   # prompts for the value
gh secret set ANDROID_KEY_ALIAS
gh secret set ANDROID_KEY_PASSWORD
```

CI writes the keystore to the runner's temp directory (outside the repo), writes
`android/key.properties` pointing to it, and deletes both at the end, even when the
build fails. If `android/key.properties` is committed in git, the build stops.
Remove it with `git rm --cached android/key.properties` and add it to `.gitignore`.
Store the keystore and passwords in your password manager too.

## Google Play

1. **Google Cloud Console** → pick or create a project → **IAM & Admin → Service
   Accounts → Create**. No project roles are needed. Open the account and choose **Keys → Add key →
   JSON**, then download it.
2. Enable the **Google Play Android Developer API** for that project.
3. **Play Console → Users and permissions → Invite new users**. Use the service
   account email and grant, for this app: *View app information*, *Release apps
   to testing tracks* and *Manage testing tracks and edit tester lists*. If an app
   lists `production` in `playstore.tracks`, also grant *Release to production, exclude devices, and
   use Play App Signing*. CI still only creates a **draft**, which a person releases.
4. `gh secret set PLAY_SERVICE_ACCOUNT_JSON < play-sa.json`

Note that the **first upload of a new app must be done manually** in Play Console. See
[TROUBLESHOOTING.md](TROUBLESHOOTING.md#first-play-upload).

## Firebase App Distribution

Android only (iOS builds go to TestFlight only).

1. Firebase console → Project settings → **Service accounts**, or Google Cloud
   IAM. Create a service account with the role **Firebase App Distribution
   Admin**, then create a JSON key.
2. Find the Android app ID in Project settings → General → Your apps (`1:…:android:…`).
3. Create tester groups in App Distribution → Testers & Groups. Use the group
   **alias** in config (`groups: "qa-team"`).
4. GitHub:
   ```bash
   gh secret set FIREBASE_SERVICE_ACCOUNT_JSON < firebase-sa.json
   gh secret set FIREBASE_ANDROID_APP_ID --body "1:1234567890:android:abc123"
   ```

The Firebase CLI is downloaded on demand as the standalone binary from
`https://firebase.tools/bin/<os>/latest`. Set `FIREBASE_TOOLS_VERSION` (e.g. `14.20.0`)
in the environment to pin it.

## Google Drive

Android only. There are two ways to give CI access to a Drive folder. Pick one.

| | Option A: service account | Option B: your own Google account |
|---|---|---|
| Folder | Must be in a **Shared Drive** | A folder created with the helper in the account's **My Drive** |
| Needs | Google Workspace (company account) | Any Google account, including free Gmail |
| Storage used | The Shared Drive's | Your account's |
| Secrets | `GDRIVE_SERVICE_ACCOUNT_JSON` | `GDRIVE_OAUTH_CLIENT_ID`, `GDRIVE_OAUTH_CLIENT_SECRET`, `GDRIVE_OAUTH_REFRESH_TOKEN` |

If the three `GDRIVE_OAUTH_*` secrets are set, Option B is used. Otherwise Option A is used.

### Option A: service account (Shared Drive)

Service accounts **have no storage of their own**. Uploads into a folder in
someone's My Drive fail with `storageQuotaExceeded`, even if the folder is
shared with the service account.

1. Google Cloud Console → create a service account → JSON key. Enable the
   **Google Drive API** for the project.
2. Google Drive → **Shared drives** → create one (e.g. "App builds"), or use an
   existing one. **Manage members** → add the service account email as
   **Content manager**.
3. Create a folder inside the Shared Drive and open it. The URL is
   `https://drive.google.com/drive/folders/<FOLDER_ID>`. Put `<FOLDER_ID>` in
   `destinations.drive.folder_id`.
4. GitHub: `gh secret set GDRIVE_SERVICE_ACCOUNT_JSON < drive-sa.json`.

### Option B: your own Google account (My Drive)

CI uploads **as a Google account**, using a refresh token you create once.

Two safety rules:
- **Use a dedicated Google account for builds** (e.g. a new `yourcompany.builds@gmail.com`),
  not a person's own account. Builds then don't stop when someone leaves, and the
  team gets access by sharing the folder.
- **Use the limited scope `drive.file`.** The token can then only see files and folders
  that CI created, never anything else in that Drive. That's why the folder is
  created with a helper command (step 5), not by hand.

1. **Cloud project:** signed in as the builds account, open https://console.cloud.google.com →
   create a project (e.g. `flutter-ci-uploads`) → **APIs & Services → Library →
   Google Drive API → Enable**.
2. **Consent screen:** **APIs & Services → OAuth consent screen** (also called
   *Google Auth Platform*):
   - Get started → App name `flutter-ci uploads`, the builds account's email →
     **Audience: External** → create.
   - **Audience → Publish app** so the status is **In production**. In "Testing"
     status Google expires refresh tokens after 7 days. `drive.file` is a
     non-sensitive scope, so no Google verification is needed.
3. **OAuth client:** **APIs & Services → Credentials → Create credentials → OAuth
   client ID** → type **Web application** → under **Authorized redirect URIs** add
   `https://developers.google.com/oauthplayground` → **Create**. Copy the
   **Client ID** and **Client secret**.
4. **Refresh token:** open https://developers.google.com/oauthplayground
   - ⚙️ (top right) → tick **Use your own OAuth credentials** → paste the client ID and secret.
   - Left side, in **"Input your own scopes"**, type
     `https://www.googleapis.com/auth/drive.file` → **Authorize APIs**.
   - Sign in with the **builds account** → **Continue / Allow**. If a "Google hasn't
     verified this app" screen appears, click **Advanced → Go to flutter-ci uploads**.
   - Click **Exchange authorization code for tokens**. Copy the **Refresh token**.
5. **Create the build folder** with the helper (from a checkout of flutter-ci). It asks for the
   three values from steps 3–4, without showing them:
   ```bash
   ~/path/to/flutter-ci/scripts/tools/gdrive_create_folder.sh "MyApp builds"
   ```
   It prints the `folder_id`. Put it in `destinations.drive.folder_id`. To see the builds,
   open the printed link (signed in as the builds account) and **Share** the folder
   with yourself and your team. Create one folder per app, or per app and environment.
6. **GitHub secrets** (in the app folder):
   ```bash
   gh secret set GDRIVE_OAUTH_CLIENT_ID      # paste the client ID
   gh secret set GDRIVE_OAUTH_CLIENT_SECRET  # paste the client secret
   gh secret set GDRIVE_OAUTH_REFRESH_TOKEN  # paste the refresh token
   ```
   The app's `.github/workflows/release.yml` must pass these three secrets
   (they are in the template since v1.1.0).

The same client, token and builds account can be reused for all apps. The token keeps
working until access is removed (https://myaccount.google.com/permissions on the
builds account), it goes unused for 6 months, or the client secret is deleted. If
uploads fail with `invalid_grant`, repeat step 4 and update `GDRIVE_OAUTH_REFRESH_TOKEN`.

Uploads use the Drive v3 API directly. They need only `curl`, `openssl` and `yq`.

## Dart defines

Committing `env/uat.json` / `env/prod.json` is simplest when they hold only
non-secret config such as API URLs. Anything in dart defines ends up inside the app
binary, so treat it as public in any case.

If you don't want them in git:
- GitHub: `gh secret set DART_DEFINES_UAT_JSON < env/uat.json` (and `_PROD_`).
- Xcode Cloud: `DART_DEFINES_UAT_JSON_BASE64` = `base64 -i env/uat.json`.

The committed file wins when both exist. When `dart_define_file` is configured
but neither the file nor the secret exists, the build fails.

## Slack

Create an **Incoming Webhook** for the target channel and store its URL as
`SLACK_WEBHOOK_URL`, both in GitHub and, if you want iOS notifications, in Xcode Cloud.
Notification failures are logged and never fail a build.

## Xcode Cloud

Add these in the workflow's **Environment → Environment Variables**, with
**Secret** checked for anything sensitive. See [XCODE_CLOUD_SETUP.md](XCODE_CLOUD_SETUP.md#environment).

| Variable | Secret | Create with |
|---|---|---|
| `FLUTTER_CI_REF` | no | `v1` |
| `DART_DEFINES_UAT_JSON_BASE64` / `DART_DEFINES_PROD_JSON_BASE64` | yes | `base64 -i env/uat.json \| pbcopy` |
| `SLACK_WEBHOOK_URL` | yes | Slack |

iOS code signing is managed by Xcode Cloud (cloud-managed certificates), so no
signing secrets are needed.

## Rotation

- Service account keys: create a new key, update the secret, run a beta build,
  then delete the old key.
- Keystore passwords cannot change without re-creating the keystore. To replace
  a lost or compromised upload key, ask Play support to reset it.
