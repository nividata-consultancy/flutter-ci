# Config reference: `.ci/config.yaml`

Each app has one config file at `.ci/config.yaml`, inside the app folder (next to
`pubspec.yaml`). If the app is in a subfolder of the repo, or the file has another name,
set `app-directory` / `config-path` in the app's `release.yml`; `config-path` is relative
to `app-directory`. Every build checks it first and
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
  run_tests: false
  run_analyze: false
  android_package_name: com.example.myapp

environments:
  uat:
    build_args: ["--dart-define-from-file=env/uat.json"]
    android:
      enabled: true
      destinations:
        playstore: { enabled: true,  tracks: [internal] }
        firebase:  { enabled: true,  groups: "qa-team" }
        drive:     { enabled: false, folder_id: "1AbCdEf…" }
    ios:
      enabled: true

  prod:
    build_args: ["--dart-define-from-file=env/prod.json"]
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
| `run_tests` | bool | `false` | `true` runs `flutter test` (if `test/` exists) before the Android build. A failing test stops the build. |
| `run_analyze` | bool | `false` | `true` runs `flutter analyze` before the Android build. Any issue, even a lint hint, stops the build. |
| `android_package_name` | string | — | `applicationId`. Required when Play is enabled. |
| `github_release.enabled` | bool | `true` | Create a GitHub Release on the app repo for each tag (prerelease for UAT) |
| `github_release.attach_artifacts` | bool | `false` | Attach the APK to that release |

Tests and analysis run on GitHub only. iOS doesn't run them again.

## Version and build number

They are **not** set here. Both come from `version: X.Y.Z+N` in the app's
`pubspec.yaml`. The tag's version must match `X.Y.Z`. (On iOS, Xcode Cloud uses its own
build number.)
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
| `build_args` | Optional extra `flutter build` flags for this environment, Android and iOS, including `--dart-define-from-file`. See [Extra build flags](#extra-build-flags). |
| `android` | See [Android](#android) |
| `ios` | See [iOS](#ios) |

## Platform switches

`android.enabled` and `ios.enabled` turn a whole platform off for one environment.
The default is `true`.

| `enabled: false` | Result |
|---|---|
| Android | The GitHub job ends at once, **green**, with "Android is disabled". Nothing is built or uploaded. |
| iOS | The Xcode Cloud build stops in about a minute with "iOS is disabled…" and shows as **failed**. Nothing goes to TestFlight. Apple can't skip a tag build, so red is expected. |

## Extra build flags

`environments.<env>.build_args` adds flags to that environment's `flutter build`, on
Android and iOS. It's only allowed at the environment level.

```yaml
environments:
  uat:
    build_args: ["--dart-define-from-file=env/uat.json", "--no-tree-shake-icons"]
```

- One flag per item. A flag with a value is one item: `"--dart-define=KEY=some value"`.
- Flags flutter-ci already sets are refused: `--release`/`--debug`/`--profile`,
  `--flavor`, `--target`/`-t`, `--build-name`, `--build-number`, `--config-only`,
  `--codesign`/`--no-codesign`. Use the matching config key instead. `--obfuscate` is
  refused too.
- **Dart defines:** `"--dart-define-from-file=env/uat.json"`. The path is relative to
  the app root, and the file must be committed (Flutter fails the build if it's
  missing). Secrets like `DART_DEFINES_<ENV>_JSON` are not used.
- On iOS the flags go to `flutter build ios --config-only` in Xcode Cloud, which writes
  them to `Generated.xcconfig` for the archive. Flags that only change the Dart build
  (`--no-tree-shake-icons`, `--dart-define`, `--split-debug-info`) work there.

## Android

| Key | Type | Default | Description |
|---|---|---|---|
| `enabled` | bool | `true` | See [Platform switches](#platform-switches) |
| `flavor` | string | none | `--flavor`. Only if Gradle has `productFlavors`. |
| `target` | path | `lib/main.dart` | `--target` |
| `destinations` | map | none | See [Destinations](#destinations) |

CI always builds an **APK**. That APK goes to Firebase and Drive, and is kept on the
GitHub run (Actions → run → Artifacts). When Play is enabled, CI also builds an **AAB**
for the Play upload, because Play accepts nothing else. The APK is then made from that
AAB with Google's `bundletool` (a universal APK with every ABI, signed with the same
upload key) instead of a second Gradle build. Files are named
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
| `flavor` | string | none | `--flavor`: the Xcode scheme name. Only for apps with one scheme per flavor; see [IOS_SETUP.md → Apps with flavors](IOS_SETUP.md#apps-with-flavors). |

The iOS version comes from `pubspec.yaml` too. The iOS **build number** is set by Xcode
Cloud; see [IOS_SETUP.md → Build number](IOS_SETUP.md#ios-build-number).
