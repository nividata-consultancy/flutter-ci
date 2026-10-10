# Config reference: `.ci/config.yaml`

Each app has one config file at `.ci/config.yaml`. Every build checks it first and
stops with a list of **all** problems. Unknown keys count as errors, so typos are caught.

Check it on your Mac:
```bash
brew install yq     # once
~/Desktop/Projects/flutter-ci/scripts/common/read_config.sh validate .ci/config.yaml
```
A commented starting file is in [`templates/.ci/config.yaml`](../templates/.ci/config.yaml).

## Full example

```yaml
version: 1

app:
  name: MyApp
  flutter_version_file: .fvmrc
  java_version: "17"
  run_tests: true
  run_analyze: false
  obfuscate: false
  android_package_name: com.example.myapp

environments:
  uat:
    dart_define_file: env/uat.json
    android:
      enabled: true
      destinations:
        playstore: { enabled: true,  tracks: [internal] }
        firebase:  { enabled: true,  groups: "qa-team" }
        drive:     { enabled: false, folder_id: "1AbCdEf…" }
    ios:
      enabled: true

  prod:
    dart_define_file: env/prod.json
    android:
      enabled: true
      destinations:
        playstore: { enabled: true,  tracks: [internal, production] }
        firebase:  { enabled: false, groups: "qa-team" }
        drive:     { enabled: false, folder_id: "1AbCdEf…" }
    ios:
      enabled: true
```

## Schema version

`version: 1` is required. A schema change would come with a new flutter-ci major version.

## App

| Key | Type | Default | Description |
|---|---|---|---|
| `name` | string | **required** | Short app name, used in file names, release names and messages |
| `flutter_version_file` | `.fvmrc` \| `pubspec.yaml` | auto | Where the Flutter version is pinned. See [Flutter version](#flutter-version). |
| `java_version` | string/number | `"17"` | Java used by Gradle on GitHub. Use the same major version as your Mac: `flutter doctor -v` → Android toolchain → Java version (e.g. `21.0.10` → `"21"`). |
| `prod_branches` | list | none | Optional prod guard: prod tags must be on one of these branches. Without it, prod tags work on any branch. |
| `run_tests` | bool | `true` | Run `flutter test` (if `test/` exists) before the Android build |
| `run_analyze` | bool | `false` | Run `flutter analyze` before the Android build |
| `obfuscate` | bool | `false` | `--obfuscate --split-debug-info` (the symbols are kept with the Android build files) |
| `android_package_name` | string | — | `applicationId`. Required when Play is enabled. |
| `github_release.enabled` | bool | `true` | Create a GitHub Release on the app repo for each tag (prerelease for UAT) |
| `github_release.attach_artifacts` | bool | `false` | Attach the APK to that release |

Tests and analysis run on GitHub only. iOS doesn't run them again.

## Version and build number

They are **not** set here. Both come from `version: X.Y.Z+N` in the app's
`pubspec.yaml`, for Android and iOS. The tag's version must match `X.Y.Z`.
See [RELEASES.md](RELEASES.md#version-and-build-number).

## Flutter version

Pin an **exact** version. Ranges (`>=3.22.0`), `^` and channel names are refused.
- `.fvmrc`: `{"flutter": "3.24.5"}` (a `@stable` suffix is ignored)
- `pubspec.yaml`: `environment: { flutter: "3.24.5" }`

Without `flutter_version_file`, `.fvmrc` is used if it exists, otherwise `pubspec.yaml`.

## Environments

Only `uat` (tags `vX.Y.Z-beta.N`) and `prod` (tags `vX.Y.Z`) are allowed.

| Key | Description |
|---|---|
| `dart_define_file` | Optional JSON file passed as `--dart-define-from-file`. See [Dart defines](#dart-defines). |
| `android` | See [Android](#android) |
| `ios` | See [iOS](#ios) |

## Platform switches

`android.enabled` and `ios.enabled` turn a whole platform off for one environment.
The default is `true`.

| `enabled: false` | Result |
|---|---|
| Android | The GitHub job ends at once, **green**, with "Android is disabled". Nothing is built or uploaded. |
| iOS | The Xcode Cloud build stops in about a minute with "iOS is disabled…" and shows as **failed**. Nothing goes to TestFlight. Apple can't skip a tag build, so red is expected. |

## Dart defines

Order of precedence:
1. `dart_define_file`, if the file is committed in the repo.
2. Secret `DART_DEFINES_<ENV>_JSON` (GitHub) or `DART_DEFINES_<ENV>_JSON_BASE64` (Xcode Cloud).
3. None: the build continues without dart defines, with a warning.

If `dart_define_file` is set but neither 1 nor 2 exists, the build fails.

## Android

| Key | Type | Default | Description |
|---|---|---|---|
| `enabled` | bool | `true` | See [Platform switches](#platform-switches) |
| `flavor` | string | none | `--flavor`. Only if Gradle has `productFlavors`. |
| `target` | path | `lib/main.dart` | `--target` |
| `destinations` | map | none | See [Destinations](#destinations) |

CI always builds an **APK**. That APK goes to Firebase and Drive, and is kept on the
GitHub run (Actions → run → Artifacts). When Play is enabled, CI also builds an **AAB**,
only for the Play upload, because Play accepts nothing else. Files are named
`<name>-<env>-<version>-<build>.apk`. Version and build number come from `pubspec.yaml`.

## Destinations

Android only. Each destination has a **required** `enabled: true|false`. A build goes
**only** where `enabled: true`. Settings of disabled destinations are kept but not checked.
Everything is skipped in a dry run.

```yaml
destinations:
  playstore: { enabled: true,  tracks: [internal] }
  firebase:  { enabled: true,  groups: "qa-team", testers: "a@x.com" }
  drive:     { enabled: false, folder_id: "1AbCdEf…" }
```

| Destination | Keys | What happens |
|---|---|---|
| `playstore` | `enabled`, `tracks` (**required**, see below), `status` (`completed` by default; `draft` while the app has never been published) | Uploads the AAB and `mapping.txt`. Release name `[UAT] 1.4.0-beta.1 (N)`. No release notes. Needs `app.android_package_name`. |
| `firebase` | `enabled`, `groups` (comma-separated group aliases), `testers` (comma-separated emails) | Uploads the APK. Release notes = tag message. |
| `drive` | `enabled`, `folder_id` (**required** when enabled, from the folder URL) | Uploads the APK. See [ANDROID_SETUP.md → Google Drive](ANDROID_SETUP.md#5c-google-drive) for the two ways to give access. |

### Play tracks

| `tracks` | Result | Allowed in |
|---|---|---|
| `[internal]` | Internal testing (testers get it right away) | uat, prod |
| `[production]` | Production only, as a **draft** | prod |
| `[internal, production]` | Internal testing **and** a draft production release of the same build | prod |

- Instead of `internal` you can use another testing track (`alpha`, `beta` or a custom
  closed track), but only one per environment.
- Production is **always a draft**. Nobody gets it until someone presses **Release** in
  Play Console.

## iOS

iOS builds go to **TestFlight only**, through the Xcode Cloud workflow. A
`destinations` block under `ios` is an error.

| Key | Type | Default | Description |
|---|---|---|---|
| `enabled` | bool | `true` | See [Platform switches](#platform-switches) |
| `display_name` | string | none | Optional app name for this environment. Needs the [one-time Xcode setup](IOS_SETUP.md#optional-different-name-and-icon-for-uat). |
| `app_icon` | string | none | Optional icon set, e.g. `AppIcon-UAT`. Same one-time setup. |
| `google_service_info` | path | none | Copied to `ios/Runner/GoogleService-Info.plist` |
| `build_settings` | map | none | Extra Xcode build settings (`KEY: value`) for this environment. Same one-time setup. |
| `target` | path | `lib/main.dart` | `--target` |

The iOS version and build number come from `pubspec.yaml` too.
