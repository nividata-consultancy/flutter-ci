# Secrets

This repository is public and never holds secrets. Every secret lives in the **app repo**
(GitHub → Settings → Secrets and variables → Actions) or in the **Xcode Cloud workflow**
(Environment → Environment Variables, marked Secret).

The app's `.github/workflows/release.yml` passes each secret to flutter-ci by name.
This is needed because apps live in different GitHub organizations, where
`secrets: inherit` doesn't work. A secret that doesn't exist is simply empty. CI tells
you which one is missing, but only when an enabled destination needs it.

Set secrets from the app folder with `gh secret set NAME`, which asks for the value, or
`gh secret set NAME < file`. List them with `gh secret list`.

## Overview

### GitHub (Android)

| Secret | Needed when |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | always (except dry runs) |
| `ANDROID_KEYSTORE_PASSWORD` | always (except dry runs) |
| `ANDROID_KEY_ALIAS` | always (except dry runs) |
| `ANDROID_KEY_PASSWORD` | always (except dry runs) |
| `PLAY_SERVICE_ACCOUNT_JSON` | `playstore` enabled |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | `firebase` enabled |
| `FIREBASE_ANDROID_APP_ID` | `firebase` enabled |
| `GDRIVE_SERVICE_ACCOUNT_JSON` | `drive` enabled, Option A (Shared Drive) |
| `GDRIVE_OAUTH_CLIENT_ID`, `GDRIVE_OAUTH_CLIENT_SECRET`, `GDRIVE_OAUTH_REFRESH_TOKEN` | `drive` enabled, Option B (your own Google account) |
| `DART_DEFINES_UAT_JSON`, `DART_DEFINES_PROD_JSON` | only if `env/uat.json` / `env/prod.json` are not committed |
| `SLACK_WEBHOOK_URL` | optional |

### Xcode Cloud (iOS)

| Variable | Secret | Needed when |
|---|---|---|
| `FLUTTER_CI_REF` = `v1` | no | always |
| `DART_DEFINES_UAT_JSON_BASE64`, `DART_DEFINES_PROD_JSON_BASE64` | yes | only if `env/*.json` are not committed (`base64 -i env/uat.json \| pbcopy`) |
| `SLACK_WEBHOOK_URL` | yes | optional |

iOS signing is handled by Xcode Cloud (cloud-managed certificates), so no signing
secrets are needed.

## Android signing

Use the app's **upload key**. Its SHA-1 must match Play Console → **App integrity → Upload
key certificate**.

```bash
keytool -list -v -keystore upload-keystore.jks -alias YOUR_ALIAS   # check alias, password, SHA-1

base64 -i upload-keystore.jks | gh secret set ANDROID_KEYSTORE_BASE64     # macOS
gh secret set ANDROID_KEYSTORE_PASSWORD
gh secret set ANDROID_KEY_ALIAS
gh secret set ANDROID_KEY_PASSWORD
```

CI writes the keystore to a temp folder outside the repo, writes `android/key.properties`,
and deletes both at the end, even when the build fails. If `android/key.properties` is
committed to git, the build stops. Remove it with `git rm --cached android/key.properties`.

Never create a new keystore for an app that is already on Play. Play rejects builds
signed with a different key.

## Google Play

1. https://console.cloud.google.com → create or pick a project → **APIs & Services →
   Library → Google Play Android Developer API → Enable**.
2. **IAM & Admin → Service Accounts → Create service account** (e.g. `play-uploader`). No
   roles are needed here → **Done**.
3. Open it → **Keys → Add key → Create new key → JSON**. A file downloads.
4. **Play Console → Users and permissions → Invite new users** → the service account email →
   **App permissions → Add app** → your app → tick:
   - View app information and download bulk reports
   - Release apps to testing tracks
   - Manage testing tracks and edit tester lists
   - **Release to production, exclude devices, and use Play App Signing**, only if the
     app uses `tracks: [… production]`. CI still only creates a draft.
5. `gh secret set PLAY_SERVICE_ACCOUNT_JSON < ~/Downloads/key.json`, then delete the file.

New service accounts can take **up to 24 hours** to work. The **first upload** of a new app
must be done by hand in Play Console.

**Internal testers** are set in Play Console → **Testing → Internal testing → Testers**
(an email list). Share the "Join on the web" link with them once.

## Firebase App Distribution

Android only.

1. Firebase console → ⚙️ **Project settings → General → Your apps**: an **Android** app with
   your package name exists (otherwise **Add app → Android**). Copy its **App ID**
   (`1:1234567890:android:abc…`).
2. **Run → App Distribution → Get started** (once per project).
3. **Testers & Groups → Add group** → add testers. Use the group **alias** (shown under its
   name) in `groups`. Several groups: `groups: "qa-team, client"`.
4. https://console.cloud.google.com, same project → **IAM & Admin → Service Accounts →
   Create** → role **Firebase App Distribution Admin** → **Keys → Add key → JSON**.
5. Secrets:
   ```bash
   gh secret set FIREBASE_SERVICE_ACCOUNT_JSON < ~/Downloads/firebase-key.json
   gh secret set FIREBASE_ANDROID_APP_ID --body "1:1234567890:android:abc123"
   ```

Testers get an email and install builds with the **App Tester** app. The tag message is
used as the release notes. The Firebase CLI is downloaded on demand; set
`FIREBASE_TOOLS_VERSION` (e.g. `14.20.0`) to pin it.

## Google Drive

Android only. There are two ways. Pick one.

| | Option A: service account | Option B: your own Google account |
|---|---|---|
| Needs | **Google Workspace** with Shared Drives | any Google account (free Gmail works) |
| Folder | inside a **Shared Drive** | created with the helper, in that account's My Drive |
| Secrets | `GDRIVE_SERVICE_ACCOUNT_JSON` | `GDRIVE_OAUTH_CLIENT_ID`, `GDRIVE_OAUTH_CLIENT_SECRET`, `GDRIVE_OAUTH_REFRESH_TOKEN` |

If the three `GDRIVE_OAUTH_*` secrets exist, Option B is used.

### Option A: service account (Shared Drive)

Service accounts have **no storage of their own**, so a My Drive folder fails with
`storageQuotaExceeded`, even when shared.

1. Cloud Console → enable **Google Drive API** → create a service account → **JSON key**.
2. Google Drive → **Shared drives** → create one → **Manage members** → add the service
   account email as **Content manager**.
3. Create a folder inside it, open it, and copy the ID from the URL:
   `drive.google.com/drive/folders/<FOLDER_ID>`.
4. `gh secret set GDRIVE_SERVICE_ACCOUNT_JSON < drive-key.json`

### Option B: your own Google account (My Drive)

CI uploads as a Google account with a refresh token. Two safety rules:
- Use a **separate Google account just for builds** (e.g. `company.builds@gmail.com`) and
  share the folder with the team, so nothing depends on one person.
- Use the limited scope **`drive.file`**. The token can then only touch files CI created,
  never the rest of the Drive. That's why the folder must be created with the helper (step 5).

Do steps 1–4 **signed in as the builds account**:

1. https://console.cloud.google.com → new project (e.g. `flutter-ci-uploads`) → **APIs &
   Services → Library → Google Drive API → Enable**.
2. **Google Auth Platform** (also called *OAuth consent screen*):
   - **Branding:** App name `flutter-ci uploads`, support email and developer contact =
     the builds account, **App home page** and **Privacy policy link** = your company
     website pages, **Authorized domains** = your company domain (e.g. `nividata.com`). No logo.
   - **Audience:** External → **Publish app**, so the status is **In production**.
     In "Testing", the token stops working after 7 days.
   - **Data Access → Add or remove scopes:** add `https://www.googleapis.com/auth/drive.file`.
     It must be listed under **non-sensitive** scopes.
3. **Credentials → Create credentials → OAuth client ID** → **Web application** →
   Authorized redirect URI `https://developers.google.com/oauthplayground` → copy the
   **Client ID** (ends with `.apps.googleusercontent.com`) and the **Client secret**.
4. https://developers.google.com/oauthplayground → ⚙️ → ✅ **Use your own OAuth
   credentials** → paste both → in **Input your own scopes** type
   `https://www.googleapis.com/auth/drive.file` → **Authorize APIs** → sign in with the
   builds account → Allow → **Exchange authorization code for tokens** → copy the
   **Refresh token**.
5. **Create the folder** in the Mac Terminal. It asks for the three values; the client ID
   is shown, the others stay hidden:
   ```bash
   ~/Desktop/Projects/flutter-ci/scripts/tools/gdrive_create_folder.sh "MyApp builds"
   ```
   It prints a link and the `folder_id` for the config. Open the link (as the builds
   account) → **Share** with the team. Folders made by hand in Drive don't work with
   `drive.file`. You can move the created folder anywhere afterwards.
6. Secrets, in each app that uploads:
   ```bash
   gh secret set GDRIVE_OAUTH_CLIENT_ID
   gh secret set GDRIVE_OAUTH_CLIENT_SECRET
   gh secret set GDRIVE_OAUTH_REFRESH_TOKEN
   ```

The same client, token and builds account work for all apps; only step 5 is per app.
The token keeps working until access is removed (builds account →
https://myaccount.google.com/permissions), it goes unused for 6 months, or the client
secret is deleted. On `invalid_grant`, repeat step 4.

## Dart defines

Committing `env/uat.json` / `env/prod.json` is simplest for non-secret settings such as
API URLs. Everything in dart defines ends up inside the app, so treat it as public in
any case. Otherwise:
- GitHub: `gh secret set DART_DEFINES_UAT_JSON < env/uat.json` (and `_PROD_`)
- Xcode Cloud: `DART_DEFINES_UAT_JSON_BASE64` = output of `base64 -i env/uat.json`

A committed file wins over the secret. If `dart_define_file` is set but neither exists,
the build fails.

## Slack

Create an **Incoming Webhook** for the channel and store the URL as `SLACK_WEBHOOK_URL`, in
GitHub and/or Xcode Cloud. A failed notification never fails a build.

## Rotating keys

- Service account keys: create a new key, update the secret, check with a beta tag, then
  delete the old key.
- Drive refresh token: repeat Option B step 4 and update `GDRIVE_OAUTH_REFRESH_TOKEN`.
- A lost or leaked upload keystore can only be replaced through Play Console support
  ("Request upload key reset").
