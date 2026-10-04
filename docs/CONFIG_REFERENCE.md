# Config reference: `.ci/config.yaml`

Each app keeps one config file, by default at `.ci/config.yaml`. Change the path
with the `config-path` input on GitHub or `FLUTTER_CI_CONFIG_PATH` on Xcode Cloud.
Every build validates it first and stops with a list of **all** problems found.
Unknown keys are errors, so typos don't fail silently.

Validate locally:

```bash
brew install yq
path/to/flutter-ci/scripts/common/read_config.sh validate .ci/config.yaml
```

The template with comments is in [`templates/.ci/config.yaml`](../templates/.ci/config.yaml).

## Schema version

```yaml
version: 1
```

Required. A flutter-ci major version supports exactly one schema version. Schema
changes are breaking and ship in a new major version (`v2`), with migration notes in
[MAINTAINING.md](MAINTAINING.md#migrations).

## App

| Key | Type | Default | Description |
|---|---|---|---|
| `name` | string | **required** | Short app name, used in artifact names, release names and notifications. |
| `flutter_version_file` | `.fvmrc` \| `pubspec.yaml` | auto | Where the Flutter version is pinned. See [Flutter version](#flutter-version). |
| `java_version` | string/int | `"17"` | JDK major version for Gradle (Temurin). |
| `prod_branches` | list | none | Optional. When set, prod tags must be on a commit reachable from one of these branches. When unset, prod tags build from any branch. |
| `build_number_offset` | int ≥ 0 | `0` | Android versionCode = GitHub run number + offset. |
| `run_tests` | bool | `true` | Run `flutter test` (if `test/` exists) before building Android. |
| `run_analyze` | bool | `false` | Run `flutter analyze` before building Android. |
| `obfuscate` | bool | `false` | `--obfuscate --split-debug-info`. Symbols are uploaded as a run artifact on Android. |
| `android_package_name` | string | — | Android applicationId. Required when a `playstore` destination is configured. |
| `github_release.enabled` | bool | `true` | Create a GitHub Release for the tag (prerelease for UAT). |
| `github_release.attach_artifacts` | bool | `false` | Attach the AAB/APK/mapping to the release. The repo must be private if the binaries are confidential. |

Tests and analysis run on GitHub (Android) only. iOS builds on Xcode Cloud do not run them again.

## Flutter version

Pin an **exact** version. Ranges (`>=3.22.0`), carets and channel names are rejected.

- `.fvmrc` (FVM 3): `{"flutter": "3.24.5"}`. A `@channel` suffix is ignored.
- `pubspec.yaml`: `environment: { sdk: ^3.5.0, flutter: "3.24.5" }`.

Without `flutter_version_file`, `.fvmrc` is used if present, otherwise
`pubspec.yaml`. Pre-releases like `3.27.0-0.1.pre` select the beta channel.

## Environments

```yaml
environments:
  uat: { … }   # built for vX.Y.Z-beta.N tags
  prod: { … }  # built for vX.Y.Z tags
```

Only `uat` and `prod` are allowed. An environment may be left out, but a tag
for a missing environment fails.

| Key | Type | Description |
|---|---|---|
| `dart_define_file` | path (`.json`) | Passed as `--dart-define-from-file`. See [Dart defines](#dart-defines). |
| `android` | map | See [Android](#android). |
| `ios` | map | See [iOS](#ios). |

## Dart defines

Order of precedence:
1. `dart_define_file` committed in the repo.
2. Secret `DART_DEFINES_<ENV>_JSON` (GitHub) or `DART_DEFINES_<ENV>_JSON_BASE64`
   (Xcode Cloud), written to a private temp file.
3. None: a warning, and the build continues without defines.

If `dart_define_file` is set and neither 1 nor 2 exists, the build fails. The
JSON must be valid.

## Android

| Key | Type | Default | Description |
|---|---|---|---|
| `flavor` | string | none | `--flavor`. Must exist in Gradle `productFlavors`. Leave it out for apps without flavors. |
| `target` | path | `lib/main.dart` | `--target`. |
| `artifacts` | list of `aab`, `apk` | `[aab]` | What to build. Play needs `aab`. Firebase prefers `apk`. |
| `destinations` | map | none | See [Destinations](#destinations). |

Build arguments: `--release [--flavor F] [--target T] [--dart-define-from-file=…]
--build-name=<VERSION_NAME_FULL> --build-number=<run_number+offset> [--obfuscate --split-debug-info=…]`.
On Android, `versionName` is the full tag version (`1.4.0-beta.1`).

## iOS

| Key | Type | Default | Description |
|---|---|---|---|
| `display_name` | string | from `Release.xcconfig` | Written as `APP_DISPLAY_NAME` to `Environment.xcconfig`. Must not contain `//`. |
| `app_icon` | string | from `Release.xcconfig` | Written as `ASSETCATALOG_COMPILER_APPICON_NAME` (e.g. `AppIcon-UAT`). |
| `google_service_info` | path (`.plist`) | none | Copied to `ios/Runner/GoogleService-Info.plist`. |
| `build_settings` | map `KEY: value` | none | Extra lines in `Environment.xcconfig` (UPPER_SNAKE_CASE keys). |
| `target` | path | `lib/main.dart` | `--target` for `flutter build ios --config-only`. |
| `destinations` | map | none | `firebase` and/or `drive`. TestFlight is configured in Xcode Cloud, not here. |

The iOS version is always `X.Y.Z` and the build number is `CI_BUILD_NUMBER`.

## Destinations

All destinations are skipped when the workflow runs with `dry-run: true`.

```yaml
destinations:
  playstore: { track: internal, status: completed }   # Android only
  firebase:  { groups: "qa-team", testers: "a@x.com" }
  drive:     { folder_id: "0AbC…" }
```

| Destination | Keys | Notes |
|---|---|---|
| `playstore` | `track` (default `internal`; any testing track, **not** `production`), `status` (`completed` default, or `draft` while the app is still a draft in Play Console) | Uploads the AAB, release notes (≤500 chars) and `mapping.txt`. Release name: `[UAT] 1.4.0-beta.1 (123)`. |
| `firebase` | `groups`, `testers` (comma-separated, both optional) | Android uploads the APK if built, otherwise the AAB (which requires the Firebase project to be linked to Play). iOS uploads the ad hoc IPA. |
| `drive` | `folder_id` (**required**, a folder inside a **Shared Drive**) | Android uploads APK and AAB. iOS uploads the ad hoc IPA. |

## Full example

```yaml
version: 1
app:
  name: MyApp
  flutter_version_file: .fvmrc
  java_version: "17"
  # prod_branches: [main]   # optional prod guard
  build_number_offset: 0
  run_tests: true
  run_analyze: false
  obfuscate: false
  android_package_name: com.example.myapp

environments:
  uat:
    dart_define_file: env/uat.json
    android:
      flavor: uat
      target: lib/main.dart
      artifacts: [aab, apk]
      destinations:
        playstore: { track: internal }
        firebase:  { groups: "qa-team" }
        drive:     { folder_id: "0AbCdEfGhIjK" }
    ios:
      display_name: "MyApp UAT"
      app_icon: AppIcon-UAT
      google_service_info: ios/config/uat/GoogleService-Info.plist
      destinations:
        firebase: { groups: "qa-team" }
        drive:    { folder_id: "0AbCdEfGhIjK" }
  prod:
    dart_define_file: env/prod.json
    android:
      artifacts: [aab]
      destinations:
        playstore: { track: internal }
    ios:
      display_name: "MyApp"
      app_icon: AppIcon
```
