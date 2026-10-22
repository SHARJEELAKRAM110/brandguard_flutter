# brandguard_flutter

**Catch white-label mistakes before release.**

BrandGuard is a read-only command-line tool and Dart library that validates
every brand of a white-label Flutter app before you build it for development,
staging or production.

White-label apps share one codebase across many brands. That makes it easy to
ship a client the wrong launcher icon, another client's application ID, a
staging API URL, or a translation file with missing keys. BrandGuard reads
your brand configuration, Flutter assets, ARB files, Android Gradle files and
the Xcode project, and reports these mistakes with file, line and fix.

- Pure Dart. No Flutter runtime dependency, no network access, no build
  execution.
- Never modifies your project.
- Readable terminal output, stable JSON for CI, and documented exit codes.

---

## Contents

1. [What it checks](#what-it-checks)
2. [Installation](#installation)
3. [Quick start](#quick-start)
4. [CLI usage](#cli-usage)
5. [Configuration reference](#configuration-reference)
6. [Rules](#rules)
7. [Severities, strict mode and exit codes](#severities-strict-mode-and-exit-codes)
8. [Output formats](#output-formats)
9. [Localization validation](#localization-validation)
10. [Android and iOS identifier and app name checks](#android-and-ios-identifier-and-app-name-checks)
11. [Environment URL checks](#environment-url-checks)
12. [Brand asset isolation](#brand-asset-isolation)
13. [Project discovery and exclusions](#project-discovery-and-exclusions)
14. [CI/CD integration](#cicd-integration)
15. [Library API and custom rules](#library-api-and-custom-rules)
16. [Known limitations](#known-limitations)
17. [Development and testing](#development-and-testing)
18. [Contributing, license and changelog](#contributing-license-and-changelog)

---

## What it checks

| Area | Rule IDs | What is detected |
| --- | --- | --- |
| Brand configuration | `missing_brand_configuration`, `duplicate_application_id` | Missing required brand fields, undeclared environments, two brands with the same application/bundle ID |
| Assets | `missing_assets`, `undeclared_assets` | Configured files that do not exist or escape the project root; existing files that are not declared under `flutter: assets:`/`fonts:` or are restricted to other flavors |
| Brand isolation | `brand_asset_leakage` | A brand using another brand's asset directory, the same file as another brand, or a byte-identical copy of another brand's asset |
| Identifiers | `application_identifier_mismatch` | Configured ID vs. Android `applicationId` (flavor, suffixes) and iOS `PRODUCT_BUNDLE_IDENTIFIER` (including xcconfig variables) |
| App names | `app_name_mismatch` | Configured name vs. Android `android:label` (resValue, manifest placeholders, `strings.xml`) and iOS `CFBundleDisplayName` |
| Localization | `missing_translations`, `invalid_arb`, `arb_placeholder_mismatch` | Missing ARB files and keys, empty translations, invalid JSON, `@@locale` mismatches, placeholder/plural/select mismatches |
| Environments | `forbidden_environment_url`, `suspicious_environment_url` | Staging/dev/loopback URLs in production brand files (configured patterns are definite; host-name heuristics are warnings) |

Run `brandguard rules` to list the rules with their default severities.

## Installation

BrandGuard needs the Dart SDK 3.8 or later. Flutter is **not** required to run
it.

**As a dev dependency of your Flutter app** (recommended, version-pinned with
your project):

```bash
flutter pub add --dev brandguard_flutter
dart run brandguard_flutter check
```

**As a global tool** (no changes to your app's `pubspec.yaml`):

```bash
dart pub global activate brandguard_flutter
brandguard check
```

The `brandguard` command is available once the pub cache `bin` directory is on
your `PATH`; otherwise use `dart pub global run brandguard_flutter:brandguard`.

Inside a project that depends on the package, `dart run brandguard_flutter`
and `dart run brandguard_flutter:brandguard` are equivalent.

## Quick start

```bash
cd my_flutter_app
dart run brandguard_flutter init    # creates a commented .brandguard.yaml
# review and edit .brandguard.yaml
dart run brandguard_flutter check
```

`init` inspects the project (without modifying it) and pre-fills the
configuration from what it finds:

- brands from Android product flavors (with their literal `applicationId`
  and `app_name` resValue) and from `assets/brands/<id>/` directories;
- launcher icon and logo candidates inside those directories;
- the ARB directory (from `l10n.yaml` or `lib/l10n`) and available locales.

It never overwrites an existing configuration without approval: it asks in an
interactive terminal, and fails with exit code 2 otherwise unless you pass
`--force`. Use `--no-input` in CI to guarantee it never prompts.

## CLI usage

```
brandguard <command> [arguments]

Commands:
  check   Validate brands and report findings.
  init    Create a commented .brandguard.yaml for this Flutter project.
  rules   List validation rules and default severities.

Global options:
  -h, --help       Print usage information.
      --version    Print the BrandGuard version.
```

### `check`

| Option | Description |
| --- | --- |
| `-p, --project <path>` | Flutter project root or a directory inside it. Default: search upward from the current directory. |
| `-c, --config <path>` | Configuration file. Default: `<project>/.brandguard.yaml` (or `brandguard.yaml` if only that exists). |
| `-b, --brand <id>` | Validate only this brand. Repeatable (`-b acme -b nova`) or comma-separated (`-b acme,nova`). |
| `--all` | Validate every configured brand (the default when `--brand` is absent). Cannot be combined with `--brand`. |
| `-f, --format text\|json` | Output format (default `text`). |
| `--strict` | Warnings also fail validation. |
| `-q, --quiet` | Text only: print failing findings and the summary. |
| `-v, --verbose` | Text only: add explanations and certainty for each finding. |
| `--[no-]color` | Force ANSI colors on/off. Default: on only for terminals that support them and when `NO_COLOR` is unset. |

Examples:

```bash
dart run brandguard_flutter check                      # all brands
dart run brandguard_flutter check --brand acme         # one brand
dart run brandguard_flutter check --all --strict       # release gate
dart run brandguard_flutter check --format json > brandguard.json
dart run brandguard_flutter check --project apps/retail --config ci/brandguard.yaml
```

When a brand is selected, BrandGuard still reads the rest of the
configuration where a check needs it (for example, other brands' asset
directories for isolation checks), but reports findings only for the
selected brands.

### `init`

| Option | Description |
| --- | --- |
| `-p, --project <path>` | Flutter project to initialize. |
| `-c, --config <path>` | Where to write the configuration. |
| `--force` | Overwrite an existing configuration without asking. |
| `--no-input` | Never prompt; fail if the file exists and `--force` is absent. |

## Configuration reference

The default file is `.brandguard.yaml` in the project root. A visible
`brandguard.yaml` is also accepted when `.brandguard.yaml` does not exist.
Having both is an error. Unknown keys, wrong types and invalid values are
**errors** (exit code 2) reported with the line number and field path.
Misspelled keys get a suggestion. BrandGuard never silently ignores
configuration.

A complete, working example (this is the configuration of the bundled
[sample project](example/sample_white_label_project/brandguard.yaml), which
uses the visible file name because pub.dev drops dotfiles from packages):

```yaml
version: 1                       # required; only 1 is supported

project:
  name: retail_suite             # shown in reports (default: pubspec name)
  root: .                        # relative to this file (default: .)

scan:
  exclude: [generated/**]        # extra globs excluded from file scans

requirements:
  brand_fields:                  # fields every brand must define
    - name
    - app_name
    - application_id
    - environment
    - required_locales
    - assets.launcher_icon       # assets.<kind> for any asset kind
    - assets.logo

defaults:
  environment: production        # for brands without `environment`

policy:
  allow_duplicate_application_ids: false
  strict: false                  # true = always behave like --strict

assets:
  require_declaration: true      # existing assets must be in pubspec.yaml
  declaration_exempt: [launcher_icon]   # kinds used only at build time
  brands_root: assets/brands     # <brands_root>/<brand id>/ belongs to that brand
  isolation:
    shared_paths: [assets/shared/**]    # globs brands may share
    compare_content: true        # flag byte-identical assets across brands
    path_heuristics: true        # flag paths in a directory named after another brand

localization:
  enabled: true                  # false if the app does not use ARB files
  arb_directory: lib/l10n        # default: from l10n.yaml, else lib/l10n
  file_pattern: 'app_{locale}.arb'
  base_locale: en                # default: from l10n.yaml template, else en
  required_locales: [en, es, fr] # default for brands without their own list
  allow_empty_translations: false

environments:
  production:
    files: ['config/{brand}/production.json']  # globs; {brand} and {flavor} are substituted
    forbidden_url_patterns: [staging, dev-api] # substrings of the URL host
    forbidden_hosts: [api.internal.example]    # exact hosts
    allowed_hosts: []                          # never reported
    block_loopback: true          # default true for production/prod
    heuristics: true              # default true for production/prod
    heuristic_markers: [staging, stage, stg, dev, test, qa, uat, sandbox]  # optional
  staging:
    files: ['config/{brand}/staging.json']
    forbidden_url_patterns: [production-api]

platforms:
  android:
    enabled: true
    gradle_files: []             # default: android/app/*.gradle and *.gradle.kts
    manifest: android/app/src/main/AndroidManifest.xml
  ios:
    enabled: true
    project_file: ios/Runner.xcodeproj/project.pbxproj
    target: Runner
    info_plist: ios/Runner/Info.plist

rules:                           # per-rule overrides (see "Rules")
  brand_asset_leakage:
    severity: warning
  undeclared_assets: warning     # shorthand for severity
  suspicious_environment_url: false   # shorthand for enabled: false

brands:
  - id: acme                     # required, unique; letters, digits, _ and -
    name: Acme Retail
    app_name: Acme Retail        # expected launcher label / display name
    application_id: com.example.acme   # Android ID; also the iOS bundle ID by default
    # ios_bundle_id: com.example.acme.ios
    # flavor: acmeProd           # Android flavor / iOS configuration suffix (default: id)
    # ios_configuration: Release-acme    # exact Xcode configuration (overrides flavor matching)
    environment: production
    required_locales: [en, es]   # replaces localization.required_locales
    # arb_directory: lib/l10n/acme
    # asset_roots: [assets/brands/acme]  # explicit ownership (default: brands_root convention)
    # environment_files: [lib/brands/acme/endpoints.dart]
    assets:                      # kind: path, or kind: [paths]; directories allowed
      launcher_icon: assets/brands/acme/app_icon.png
      logo: assets/brands/acme/logo.png
      fonts: [assets/fonts/Acme-Regular.ttf]   # kinds `font`/`fonts` are checked against flutter: fonts:
    rules:
      brand_asset_leakage: {enabled: false}   # per-brand override
```

### Precedence

- **Rule settings:** brand `rules:` > top-level `rules:` > rule default.
- **Brand environment:** brand `environment` > `defaults.environment`.
- **Brand locales:** brand `required_locales` > `localization.required_locales`.
- **ARB directory:** brand `arb_directory` > `localization.arb_directory` > `l10n.yaml` `arb-dir` > `lib/l10n` (if it exists).
- **Project root:** `--project` > `project.root` (relative to the config file).

All paths are relative to the project root. Absolute paths and paths that
escape the root (`../`) are rejected.

## Rules

| Rule ID | Default | Certainty | Description |
| --- | --- | --- | --- |
| `missing_brand_configuration` | error | definite | Brand lacks a field in `requirements.brand_fields`, or uses an environment not declared under `environments`. |
| `duplicate_application_id` | error | definite | Two brands share an application ID or iOS bundle ID (unless `policy.allow_duplicate_application_ids`). |
| `missing_assets` | error | definite | A configured asset is missing, absolute, outside the project, or a symlink leaving the project. |
| `undeclared_assets` | warning | definite | An existing asset is not covered by `flutter: assets:` (directory entries cover direct children only, as in Flutter), a font is missing from `flutter: fonts:`, or the asset entry is restricted to other `flavors:`. |
| `brand_asset_leakage` | warning | definite or heuristic | See [Brand asset isolation](#brand-asset-isolation). |
| `application_identifier_mismatch` | error | definite or unresolved | See [identifier checks](#android-and-ios-identifier-and-app-name-checks). |
| `app_name_mismatch` | error | definite or unresolved | See [identifier checks](#android-and-ios-identifier-and-app-name-checks). |
| `missing_translations` | error | definite | Missing ARB file or key, empty translation; extra keys are `info`. |
| `invalid_arb` | error | definite | Invalid JSON, non-object root, non-string message, malformed `@key` metadata, `@@locale` mismatch. |
| `arb_placeholder_mismatch` | error | definite | Unknown placeholder, kind mismatch (simple/plural/select), plural or select without `other`, type mismatch in metadata, invalid ICU braces. A translation that *omits* a base placeholder or select case is a `warning`. |
| `forbidden_environment_url` | error | definite | URL host matches `forbidden_hosts`, `forbidden_url_patterns`, or (with `block_loopback`) `localhost`, `127.x.x.x`, `0.0.0.0`, `10.0.2.2`, `::1`. A configured file glob that matches nothing is a `warning`. |
| `suspicious_environment_url` | warning | heuristic | A host label equals a marker such as `staging`, `dev` or `qa` (for example `api.qa.example.com`, but not `devices.example.com`). |

Every finding carries a `certainty`:

- **definite** — proven from configured values or parsed files.
- **heuristic** — inferred from naming or conventions; may be a false positive.
- **unresolved** — the value exists but cannot be resolved statically. These
  are reported as `info` (or a `warning` when a brand's flavor/configuration
  is missing) and need manual verification.

## Severities, strict mode and exit codes

| Severity | Meaning | Fails validation |
| --- | --- | --- |
| `error` | A definite release blocker. | Always |
| `warning` | A likely problem, or a heuristic. | Only with `--strict` or `policy.strict: true` |
| `info` | Skipped checks and values that need manual verification. | Never |

A rule's configured severity applies to its primary findings. Secondary
findings that a rule reports at a lower severity (for example, unresolved
values as `info`) are capped at the configured severity, so a rule set to
`info` never produces warnings or errors.

| Exit code | Meaning |
| --- | --- |
| `0` | Validation passed under the active policy. |
| `1` | At least one finding fails the policy. |
| `2` | Invalid arguments, configuration errors, unknown brand, project not found, or an internal rule failure. |

## Output formats

### Text

Real output from the bundled sample project (`acme` is correct; `nova`
contains intentional mistakes):

```
BrandGuard — White-Label Validation
Project: retail_suite
Brands checked: 2

ACME RETAIL (acme)
  ✓ Brand configuration is complete
  ✓ Application ID is unique
  ✓ All 3 configured assets exist
  ✓ Assets are declared in pubspec.yaml
  ✓ Android application ID matches (com.example.acme)
  ✓ iOS bundle ID matches (com.example.acme)
  ✓ Android app name matches (Acme Retail)
  ✓ iOS app name matches (Acme Retail)
  ✓ Required locales present (en, es)
  ✓ ARB files are valid
  ✓ Placeholders match the base locale
  ✓ No forbidden URLs in 1 production file
  ⚠ WARN  Brand `acme` `launcher_icon` is byte-identical to `nova`'s asset assets/brands/nova/app_icon.png [brand_asset_leakage]
      at assets/brands/acme/app_icon.png
      fix: Replace assets/brands/acme/app_icon.png with `acme`'s real asset, or add it to `assets.isolation.shared_paths` if sharing is intended.

NOVA STORE (nova)
  ✓ Brand configuration is complete
  ✓ Application ID is unique
  ✓ Assets are declared in pubspec.yaml
  ✓ Android application ID matches (com.example.nova)
  ✓ iOS app name matches (Nova Store)
  ✓ ARB files are valid
  ✗ ERROR Missing asset `logo`: assets/brands/nova/logo.png [missing_assets]
      at assets/brands/nova/logo.png
      fix: Add the file at `assets/brands/nova/logo.png` or fix the path in the brand configuration.
  ⚠ WARN  Brand `nova` `launcher_icon` is byte-identical to `acme`'s asset assets/brands/acme/app_icon.png [brand_asset_leakage]
      at assets/brands/nova/app_icon.png
      fix: Replace assets/brands/nova/app_icon.png with `nova`'s real asset, or add it to `assets.isolation.shared_paths` if sharing is intended.
  ✗ ERROR iOS bundle ID mismatch: expected `com.example.nova`, found `com.example.acme`. [application_identifier_mismatch]
      at ios/Runner.xcodeproj/project.pbxproj:1087
      fix: Change PRODUCT_BUNDLE_IDENTIFIER (Release-nova) to `com.example.nova`, or fix `application_id` for brand `nova` in the BrandGuard configuration.
  ✗ ERROR Android app name mismatch: expected `Nova Store`, found `Nova Shop`. [app_name_mismatch]
      at android/app/build.gradle.kts:46
      fix: Change productFlavors.nova.resValue(app_name) to `Nova Store`, or fix `app_name` for brand `nova` in the BrandGuard configuration.
  ✗ ERROR Missing translation `checkoutConfirm` in locale `fr`. [missing_translations]
      at lib/l10n/app_fr.arb
      fix: Add "checkoutConfirm" to lib/l10n/app_fr.arb.
  ⚠ WARN  Translation `welcomeMessage` (fr) does not use placeholder `{name}` from the base locale. [arb_placeholder_mismatch]
      at lib/l10n/app_fr.arb:4
      fix: Align "welcomeMessage" in lib/l10n/app_fr.arb with the base locale.
  ✗ ERROR Translation `welcomeMessage` (fr) uses placeholder `{nom}`, which the base locale does not define. [arb_placeholder_mismatch]
      at lib/l10n/app_fr.arb:4
      fix: Align "welcomeMessage" in lib/l10n/app_fr.arb with the base locale.
  ✗ ERROR Production brand uses URL https://staging-api.novastore.example/v1 (matches forbidden pattern `staging`). [forbidden_environment_url]
      at config/nova/production.json:3
      fix: Replace it with the production endpoint, or add the host to `environments.production.allowed_hosts` if it is correct.

Summary:
  6 errors
  3 warnings
  0 infos
  2 brands checked
Result: FAILED (6 failing findings)
```

Severity is always spelled out (`ERROR`, `WARN`, `INFO`), so the report does
not depend on color. Findings shared by the whole project (for example,
"iOS checks skipped") appear under `PROJECT`.

### JSON (schema version 1)

`--format json` writes exactly one JSON document to stdout and nothing else.
Diagnostics go to stderr.

```jsonc
{
  "schema_version": 1,
  "tool": {"name": "brandguard", "version": "0.1.0"},
  "project": {"name": "retail_suite", "root": "/abs/path", "config": "/abs/path/.brandguard.yaml"},
  "strict": false,
  "result": "failed",              // "passed" | "failed"
  "exit_code": 1,
  "summary": {"brands_checked": 1, "errors": 6, "warnings": 2, "infos": 0, "failing": 6},
  "brands": [
    {"id": "nova", "name": "Nova Store", "result": "failed", "errors": 6, "warnings": 2, "infos": 0}
  ],
  "findings": [
    {
      "rule_id": "missing_assets",
      "severity": "error",           // "error" | "warning" | "info"
      "fails_policy": true,          // counts toward exit code 1
      "certainty": "definite",       // "definite" | "heuristic" | "unresolved"
      "brand_id": "nova",            // null for project-wide findings
      "message": "Missing asset `logo`: assets/brands/nova/logo.png",
      "file": "assets/brands/nova/logo.png",   // relative, "/"-separated, or null
      "line": null,                  // 1-based or null
      "explanation": "…",
      "recommendation": "…"
    }
  ],
  "passed_checks": [{"rule_id": "missing_brand_configuration", "brand_id": "nova", "message": "Brand configuration is complete"}]
}
```

On exit code 2, the JSON document is:

```json
{
  "schema_version": 1,
  "tool": {"name": "brandguard", "version": "0.1.0"},
  "result": "error",
  "exit_code": 2,
  "error": {"message": "Invalid configuration in …", "details": [{"message": "…", "field": "brands[2].id", "line": 14}]}
}
```

Fields are only added in a minor version. Removing or renaming a field
increments `schema_version`. Findings are sorted by brand (configuration
order, project-wide first), rule, file, line and message, so output is
deterministic for unchanged inputs.

## Localization validation

BrandGuard reads Flutter `gen-l10n` ARB files. File names follow
`localization.file_pattern` (default `app_{locale}.arb`, for example
`app_pt_BR.arb`). For each brand it checks the base locale plus the brand's
required locales:

- Keys starting with `@` are metadata and `@@` keys are global metadata. They
  are never treated as translations.
- Generated Dart files (`app_localizations*.dart`) are never read.
- Placeholders are compared using the ICU message structure, including
  arguments nested inside plural/select cases. Plural case sets may differ
  between languages; only `other` is required.
- Translation files rarely repeat metadata. When they do, placeholder types
  are compared with the base locale.

If your app uses another localization system, set
`localization.enabled: false`.

## Android and iOS identifier and app name checks

BrandGuard reads build files **statically**. It never runs Gradle, Xcode or
build scripts.

**Android** (`android/app/*.gradle` and `*.gradle.kts`, Groovy or Kotlin DSL):

- `defaultConfig`, `productFlavors` (`acme { }`, `create("acme") { }`,
  `register(...)`), and `buildTypes` (`release`, `getByName("release")`).
- `applicationId`, plus `applicationIdSuffix` from `defaultConfig`, the
  flavor and the `release` build type.
- App name: `android:label` in the flavor manifest
  (`src/<flavor>/AndroidManifest.xml`) or the main manifest, resolved through
  `resValue("string", ...)`, `src/<flavor>/res/values/strings.xml`,
  `src/main/res/values/strings.xml`, or `manifestPlaceholders` (Groovy map,
  Kotlin `[key] =`, `put`, `mapOf`).
- `namespace` is not the application ID and is ignored. Commented-out code is
  ignored.

**iOS** (`ios/Runner.xcodeproj/project.pbxproj`):

- Configurations of the `Runner` target named `Release-<flavor>`,
  `Release_<flavor>`, `<flavor>Release` and similar (or `ios_configuration`).
- `PRODUCT_BUNDLE_IDENTIFIER` from target settings, its
  `baseConfigurationReference` xcconfig (with `#include`), and project-level
  settings, following Xcode's precedence. `$(VAR)` references are expanded.
- `CFBundleDisplayName` (or `CFBundleName`) from `Info.plist`, expanded the
  same way, or `INFOPLIST_KEY_CFBundleDisplayName`.

**How results are classified:**

| Situation | Result |
| --- | --- |
| Brand's flavor/configuration found, value resolved, equal | pass |
| Brand's flavor/configuration found, value resolved, different | `error` (definite) |
| Value uses a variable, `$(inherited)`, a modifier such as `:rfc1034identifier`, or a generated xcconfig | `info` (unresolved, manual verification) |
| Project has flavors/configurations, but none for this brand | `warning` (unresolved) |
| No flavors at all, single-brand configuration | compared definitively |
| No flavors, several brands: the shared value belongs to another brand | `info` (brand switching happens outside the build files) |
| No flavors, several brands: the shared value matches no brand | `warning` (heuristic) |

Localized names (`values-xx/strings.xml`, `InfoPlist.strings`) are not
compared. BrandGuard never edits identifiers or names.

## Environment URL checks

Only files you list are scanned. That is `environments.<env>.files` plus the
brand's `environment_files`, with `{brand}` and `{flavor}` substituted. Only
`http(s)://` and `ws(s)://` URLs are considered, so the word "staging" in
plain text is never reported. Lines that start with a comment (`//`, `#`, `*`,
`/*`, `<!--`, `--`) are skipped.

- `forbidden_hosts` match the exact host.
- `forbidden_url_patterns` are case-insensitive substrings of the host. A
  pattern containing `/` or `:` is matched against the whole URL.
- `block_loopback` reports localhost, loopback addresses and the Android
  emulator host.
- `heuristics` reports hosts with a label such as `staging` or `qa` as a
  separate, heuristic rule.
- `allowed_hosts` suppresses all of the above for a host.

Reported URLs are redacted. User info becomes `***@`, and values of query
parameters such as `token`, `api_key`, `secret`, `password` and `signature`
become `***`. Fragments are dropped. No network requests are made.

## Brand asset isolation

`brand_asset_leakage` reports, for each asset of a brand that is not in the
brand's own directory and not matched by `assets.isolation.shared_paths`:

1. **Owned by another brand.** The path is inside another brand's
   `asset_roots`, or inside `<brands_root>/<other id>/`. This is definite when
   ownership is configured explicitly (`asset_roots`, or `assets.brands_root`
   set in the file) and heuristic when it relies on the default
   `assets/brands` convention.
2. **Same file.** Another brand references the identical path (definite).
3. **Byte-identical copy.** The file content equals another brand's asset
   (definite fact; up to 10 MB per file). This finds an icon that was copied
   and never replaced. Both brands are reported, because BrandGuard cannot
   know which one is the original.
4. **Directory named after another brand.** A directory segment of the path
   equals another brand ID. File names alone are never used. This is
   heuristic and can be disabled with `path_heuristics: false`.

BrandGuard does not judge whether an icon *looks* right. It only checks that
the file exists and belongs to the brand.

## Project discovery and exclusions

Without `--project`, BrandGuard walks up from the current directory to the
first `pubspec.yaml` that depends on the Flutter SDK (or has a `flutter:`
section). It stops at the repository root (a directory containing `.git`)
and never scans the file system above it.

File scans (environment globs, xcconfig lookup, init detection) walk the
project once and:

- skip `.dart_tool`, `.git`, `.gradle`, `.idea`, `.vscode`, `.fvm`,
  `.pub-cache`, `.symlinks`, `.cxx`, `build`, `ephemeral`, `node_modules`,
  `Pods` and `DerivedData`, plus any `scan.exclude` globs;
- never follow symbolic links;
- skip files larger than 2 MB and binary files when reading text.

Asset paths that you configure explicitly are always checked, even inside
excluded directories.

## CI/CD integration

BrandGuard needs only the Dart SDK. Because the JSON output and exit codes are
stable, any CI system works. These examples have not been executed in a
hosted CI environment as part of this release, so verify them in your own
pipeline.

**GitHub Actions** (Flutter app that has `brandguard_flutter` as a dev
dependency): see [`doc/ci/github-actions.yml`](doc/ci/github-actions.yml).

```yaml
name: White-Label Validation
on: [pull_request, push]
jobs:
  validate-brands:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter pub get
      - name: Validate brands
        run: dart run brandguard_flutter check --all --strict --no-color
```

**GitLab CI and generic shells:** see
[`doc/ci/gitlab-ci.yml`](doc/ci/gitlab-ci.yml) and
[`doc/ci/brandguard.sh`](doc/ci/brandguard.sh). The script writes a JSON
report as a build artifact and propagates the exit code.

Typical release gate before `flutter build`:

```bash
dart run brandguard_flutter check --brand "$BRAND" --strict || exit $?
flutter build appbundle --flavor "$BRAND" --release
```

## Library API and custom rules

```dart
import 'package:brandguard_flutter/brandguard_flutter.dart';

void main() {
  final guard = BrandGuard();
  final config = guard.loadConfig(projectDirectory: '.');
  final result = guard.validate(config, brandIds: ['acme'], strict: true);
  for (final finding in result.findings) {
    print('${finding.severity.name} ${finding.ruleId}: ${finding.message}');
  }
  print(const JsonReporter().render(result));
}
```

To add a check, implement `Rule` and pass it with the built-in rules. Rules
receive a `RuleContext` (configuration, selected brands, cached read-only
`ProjectFiles`, and lazily parsed `android`, `ios`, `arb` and `pubspecAssets`)
and report through `RuleReporter`, which applies enablement and severity
configuration:

```dart
class SplashScreenRule extends Rule {
  const SplashScreenRule();

  @override
  String get id => 'missing_splash';

  @override
  String get description => 'Every brand configures a splash image.';

  @override
  Severity get defaultSeverity => Severity.warning;

  @override
  void run(RuleContext context, RuleReporter reporter) {
    for (final brand in reporter.enabledBrands) {
      if (brand.assets['splash'] == null) {
        reporter.fail(
          brand: brand,
          message: 'Brand `${brand.id}` has no splash asset.',
          recommendation: 'Add `assets: {splash: ...}`.',
        );
      } else {
        reporter.pass('Splash configured', brand: brand);
      }
    }
  }
}

final guard = BrandGuard(rules: [...BrandGuard.defaultRules(), const SplashScreenRule()]);
```

The custom rule ID is then accepted under `rules:` in `.brandguard.yaml`. To
use custom rules from the command line, build your own entry point with
`BrandGuardCli(guard: guard).run(args)`.

## Known limitations

- **Static analysis only.** Values computed in Gradle (variables, functions,
  `.properties` files, `buildConfigField`), flavors applied by plugins or
  scripts, Xcode values from generated or CI-provided xcconfigs, `$(inherited)`
  and build setting modifiers are reported as needing manual verification, not
  guessed.
- Gradle parsing understands common DSL shapes, not the full Groovy/Kotlin
  language. Flavors declared in loops or in other modules are not seen.
- Only the `Runner` target (configurable) and its configurations are
  inspected. iOS flavors with unusual configuration names need
  `ios_configuration`.
- Localized app names and per-locale `InfoPlist.strings` are not checked.
- URL detection covers `http(s)` and `ws(s)` URLs in configured files. Hosts
  without a scheme, or URLs assembled from parts at runtime, are not detected.
  Comment detection is line-based.
- ICU parsing follows `gen-l10n` defaults without `use-escaping`.
- Byte-identical comparison flags intentionally shared assets unless they are
  listed in `shared_paths`.
- BrandGuard does not check image dimensions, formats or visual similarity.

## Development and testing

```bash
dart pub get
dart format .
dart analyze
dart test                      # unit, integration and CLI process tests
dart run tool/generate_fixtures.dart   # regenerate test/fixtures
```

`test/fixtures/clean_project` must produce no findings, and
`test/fixtures/broken_project` (labeled as intentionally broken) must produce
exactly the documented findings. The sample in
`example/sample_white_label_project` is a real `flutter create` project with
two brand flavors. See [example/README.md](example/README.md).

## Contributing, license and changelog

- [CONTRIBUTING.md](CONTRIBUTING.md)
- [CHANGELOG.md](CHANGELOG.md)
- License: [MIT](LICENSE)
#   b r a n d g u a r d _ f l u t t e r  
 