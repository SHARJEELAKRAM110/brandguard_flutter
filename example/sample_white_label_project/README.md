# sample_white_label_project

> **Demonstration project. The `nova` brand is INTENTIONALLY BROKEN.**
> Do not use it as a production template.

This is a fictional white-label Flutter app used to demonstrate
[BrandGuard](../../README.md). Both brands share `lib/main.dart` and differ only
in configuration:

- Android: product flavors `acme` and `nova` in
  `android/app/build.gradle.kts`.
- iOS: `Debug-/Release-/Profile-<brand>` build configurations and `acme` /
  `nova` schemes. `Info.plist` reads `CFBundleDisplayName` from
  `$(APP_DISPLAY_NAME)`.
- Assets: `assets/brands/<brand>/`. Shared assets live in `assets/shared/`.
- Runtime configuration: `config/<brand>/production.json` (plus a staging
  file for Acme).
- Translations: `lib/l10n/app_{en,es,fr}.arb`.

## Intentional mistakes (brand `nova`)

1. `assets/brands/nova/logo.png` is missing.
2. `assets/brands/nova/app_icon.png` is a byte-for-byte copy of Acme's icon.
3. `Release-nova` / `Profile-nova` use Acme's bundle ID `com.example.acme`.
4. The Android flavor's `app_name` is "Nova Shop" instead of "Nova Store".
5. `app_fr.arb` lacks `checkoutConfirm` and uses `{nom}` instead of `{name}`.
6. `config/nova/production.json` points at a staging API.

## Run

```bash
flutter pub get
dart run brandguard_flutter check
```

Build a brand (requires the Android/iOS toolchains):

```bash
flutter run --flavor acme --dart-define=BRAND=acme
```
