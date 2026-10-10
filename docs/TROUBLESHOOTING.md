# Troubleshooting

flutter-ci errors start with `Error:` (GitHub, shown in red) or `ERROR:` (Xcode Cloud log).
Most end with a link to a section on this page. After fixing, always push a **new tag**.

## Workflow starts when it shouldn't, or not at all

| What you see | Cause and fix |
|---|---|
| GitHub: "Invalid workflow file … secret X is not defined in the referenced workflow" | The app passes a secret that the flutter-ci version it uses doesn't know yet. Check that `@v1` is up to date, or remove that line from the app's `release.yml`. |
| GitHub: a failed run on every push | Usually an invalid workflow file (see above). GitHub then can't read the triggers. flutter-ci's template only starts on tags. |
| GitHub: a run on a commit | Another workflow file in the app's `.github/workflows/` starts on push. flutter-ci runs show the **tag** as their branch. |
| Xcode Cloud: a build on every commit | The workflow still has **Branch Changes**, or a leftover **Default** workflow exists. Remove them ([IOS_SETUP.md](IOS_SETUP.md#step-5-create-the-xcode-cloud-workflow)). |
| Xcode Cloud: nothing starts on a tag | The tag was pushed before the workflow existed, or the start condition isn't **Tag Changes → beginning with `v`**. Push a new tag. |
| Xcode Cloud: `CI_TAG is not set` | Someone started a build from a branch. Only tags work. |

## Scripts not found or not executable

Xcode Cloud: the scripts don't run, or you see `zsh` errors, `permission denied` or
`ci_post_clone.sh did not finish`.

- The files must be `ios/ci_scripts/ci_post_clone.sh` and `ci_post_xcodebuild.sh`, next to
  `Runner.xcworkspace`.
- They must be executable in git:
  ```bash
  git ls-files -s ios/ci_scripts          # both lines start with 100755
  git update-index --chmod=+x ios/ci_scripts/ci_post_clone.sh ios/ci_scripts/ci_post_xcodebuild.sh
  ```
- `curl: (22) … 404` while downloading flutter-ci means `FLUTTER_CI_REF` names a tag or
  branch that doesn't exist.

## Xcode setup problems

| Problem | Fix |
|---|---|
| No "Xcode Cloud" in the Product menu | It's under **Integrate → Create Workflow…** |
| Xcode shows the wrong GitHub URL (e.g. `github.com-work`) | Use the normal URL for `origin` ([IOS_SETUP.md](IOS_SETUP.md#step-3-fix-the-github-address)) |
| "Scheme Runner does not exist" | Share the Runner scheme and commit `ios/Runner.xcodeproj/xcshareddata` |
| No group in TestFlight Internal Testing | Create one in App Store Connect → TestFlight → Internal Testing → + |
| Signing error during Archive | Runner target → Signing & Capabilities: automatic signing on, Team set |
| "Version must be higher" in App Store Connect | Use a tag version above the current App Store version |

## yq missing

The scripts need [mikefarah/yq](https://github.com/mikefarah/yq) v4. It's preinstalled on
GitHub's runners and installed automatically on Xcode Cloud. On your Mac, run
`brew install yq`.

## Pod install fails

- Run `cd ios && pod install` locally, commit `ios/Podfile.lock`, push and use a new tag.
- `Generated.xcconfig must exist`: `flutter build ios --config-only` failed earlier. Look
  above in the log.
- Apps without an `ios/Podfile` (Swift Package Manager) skip this step.

## Flutter version mismatch

- `Could not find the Flutter version`: add `.fvmrc` with `{"flutter": "X.Y.Z"}`.
- `must be an exact release`: use e.g. `3.24.5`, not `>=3.22.0` or `stable`.
- `Could not clone Flutter X`: X must be a real Flutter release
  ([release list](https://docs.flutter.dev/release/archive)).
- Xcode Cloud fails with SDK errors: the Xcode version chosen in the workflow is too old
  for this Flutter version. Choose a newer one.

## Android build fails

- `Missing signing secrets`: add the four `ANDROID_*` secrets ([ANDROID_SETUP.md](ANDROID_SETUP.md#step-4-signing-secrets)).
- `The keystore could not be opened`: wrong password or alias, or the base64 value is
  incomplete. Set `ANDROID_KEYSTORE_BASE64` again with `base64 -i file.jks | gh secret set …`.
- `No android/ directory`: the app isn't at the repo root. Set `app-directory` in the
  app's `release.yml`.
- `Flavor … not found`: `android.flavor` must match `productFlavors`, or be removed.
- The build is signed with debug keys: the Gradle file doesn't read `key.properties`
  ([ANDROID_SETUP.md](ANDROID_SETUP.md#step-3-signing-in-gradle)).

## versionCode already used

`Version code X has already been used` (Play), or TestFlight says the build number was
already used: the `+N` in `pubspec.yaml` was uploaded before, for example by the UAT
build of the same version. Raise it (`+45` → `+46`, higher than anything on the store),
commit, and push a new tag.

## Tag and pubspec version don't match

`Tag v1.4.0-beta.1 is for version 1.4.0, but pubspec.yaml says 1.3.9+44`: set
`version: 1.4.0+<next number>` in `pubspec.yaml`, commit, then delete the tag and tag
the new commit:
```bash
git push --delete origin v1.4.0-beta.1 && git tag -d v1.4.0-beta.1
```

`pubspec.yaml must have 'version: X.Y.Z+N'`: add or fix the `version:` line, e.g.
`version: 1.4.0+45`. The `+N` build number is required.

## Prod guard rejected

Only for apps with `app.prod_branches`. The prod tag's commit isn't on one of those
branches. Delete the tag, merge the commit into the branch, and tag the merged commit:
```bash
git push --delete origin v1.4.0 && git tag -d v1.4.0
```
To allow prod tags from any branch, remove `prod_branches` from the config.

## First Play upload

`Package not found`: Google doesn't allow the very first upload of a new app through
the API. Upload one AAB by hand in Play Console → Testing → Internal testing → Create
new release.

`Only releases with status draft may be created on draft app`: the app has never been
published. Set `playstore: { enabled: true, tracks: [internal], status: draft }` until
the first release is out. Each build then waits as a draft in Play Console.

## Play production draft fails

- `HTTP 403`: the Play service account needs the "Release to production…" permission
  ([ANDROID_SETUP.md](ANDROID_SETUP.md#5a-play-store)).
- `HTTP 400 / 409`: another draft or a release under review blocks it. Finish or
  discard it in Play Console → Production.
- Not possible on a **draft app** (never published). Use `tracks: [internal]` until the
  first release.
- New service accounts can take up to 24 hours to get their permissions.

## Firebase upload fails

- `PERMISSION_DENIED` / `403`: the service account needs the **Firebase App Distribution
  Admin** role, in the **same** Firebase project.
- `App not found`: `FIREBASE_ANDROID_APP_ID` is wrong, or belongs to another project.
- `Invalid group alias`: use the group's **alias**, not its display name.

## Drive upload fails

`Drive: no answer from Google while starting the upload / sending the file (HTTP 000)`
is a connection problem. The message includes curl's own error:
- `Could not resolve host` / `Connection timed out`: a temporary network problem.
  The script already retries 3 times; push a new tag.
- `Operation timed out` while sending: the upload took too long. Push a new tag to try again.

Other `Drive: upload failed (HTTP …)` errors include Google's reason:
- `401` / `invalid_grant`: the refresh token expired or was removed, or the consent
  screen is still in "Testing". Make a new token ([ANDROID_SETUP.md](ANDROID_SETUP.md#option-2-your-own-google-account)).
- `403 … has not been used in project`: enable the **Google Drive API** in that Cloud project.

Errors from the folder helper (`gdrive_create_folder.sh`):
- `The OAuth client was not found` / `not an OAuth client ID`: wrong client ID. It must
  end with `.apps.googleusercontent.com`.
- `invalid_client`: the client secret doesn't match the client ID.
- `invalid_grant`: the refresh token belongs to another client. Make it again in the
  Playground with "Use your own OAuth credentials".

## Drive: storage quota exceeded

- **Service account (Option 1):** the folder must be inside a **Shared Drive**. A My Drive
  folder doesn't work, even when shared. Without Google Workspace, use Option 2.
- **Own account (Option 2):** that account's Drive is full.
- `notFound` (Option 2): the folder was made by hand. Create it with
  `scripts/tools/gdrive_create_folder.sh`, then use the printed `folder_id`.
