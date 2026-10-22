# Changelog

## 0.1.0

Initial release (not yet published).

- `brandguard check`: validates brands with text or JSON (schema version 1)
  output, `--brand`/`--all` selection, `--strict`, `--quiet`, `--verbose`,
  `--[no-]color`, `--project` and `--config`. Exit codes: 0 passed, 1 failed,
  2 usage, configuration or execution error.
- `brandguard init`: creates a commented `.brandguard.yaml` prefilled from
  Android flavors, `assets/brands/*` and ARB files. It never overwrites
  without approval, and `--no-input` makes it safe for CI.
- `brandguard rules`: lists rules and default severities.
- Rules: `missing_brand_configuration`, `duplicate_application_id`,
  `missing_assets`, `undeclared_assets`, `brand_asset_leakage`,
  `application_identifier_mismatch`, `app_name_mismatch`,
  `missing_translations`, `invalid_arb`, `arb_placeholder_mismatch`,
  `forbidden_environment_url`, `suspicious_environment_url`.
- Static readers for Gradle (Groovy and Kotlin DSL), `project.pbxproj` with
  xcconfig resolution, `Info.plist`, `AndroidManifest.xml`, `strings.xml`,
  pubspec asset and font declarations (including flavor-restricted assets),
  and ARB/ICU messages.
- Public library API: `BrandGuard`, `Rule`, `RuleContext`, `RuleReporter`,
  `ValidationResult`, `TextReporter`, `JsonReporter`.
