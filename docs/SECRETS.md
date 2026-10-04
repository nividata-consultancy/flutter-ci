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
| `GDRIVE_SERVICE_ACCOUNT_JSON` | `drive` destination | service account JSON, plain |
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

Android only.

Service accounts **have no My Drive storage quota**. Uploads into a folder that
lives in someone's My Drive fail with `storageQuotaExceeded`, even if the folder
is shared with the service account. Use a **Shared Drive**:

1. Google Cloud Console → create a service account → JSON key. Enable the
   **Google Drive API** for the project.
2. Google Drive → **Shared drives** → create one (e.g. "App builds"), or use an
   existing one. **Manage members** → add the service account email as
   **Content manager**.
3. Create a folder inside the Shared Drive and open it. The URL is
   `https://drive.google.com/drive/folders/<FOLDER_ID>`. Put `<FOLDER_ID>` in
   `destinations.drive.folder_id`.
4. GitHub: `gh secret set GDRIVE_SERVICE_ACCOUNT_JSON < drive-sa.json`.

Uploads use the Drive v3 API directly with `supportsAllDrives=true`. They need only
`curl`, `openssl` and `yq`.

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
