// Regenerates test/fixtures/clean_project and test/fixtures/broken_project.
//
//   dart run tool/generate_fixtures.dart
//
// The broken project is the clean project plus deliberate, documented
// mistakes. Integration tests assert the exact findings for both.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../test/support/pbxproj.dart';

void main() {
  final root = p.join('test', 'fixtures');
  for (final name in ['clean_project', 'broken_project']) {
    final dir = Directory(p.join(root, name));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    _write(dir.path, _clean());
  }
  _write(p.join(root, 'broken_project'), _breakages());
  // Mistake 1: beta's configured logo does not exist.
  File(
    p.join(root, 'broken_project', 'assets/brands/beta/logo.png'),
  ).deleteSync();
  stdout.writeln('Fixtures written to $root');
}

void _write(String root, Map<String, Object> files) {
  for (final entry in files.entries) {
    final file = File(p.join(root, entry.key));
    file.parent.createSync(recursive: true);
    final value = entry.value;
    if (value is List<int>) {
      file.writeAsBytesSync(value);
    } else {
      file.writeAsStringSync(value as String);
    }
  }
}

List<int> _bytes(int seed) => List.generate(256, (i) => (i * seed + 17) % 256);

Map<String, Object> _clean() => {
  'pubspec.yaml': '''
name: fixture_app
publish_to: none
environment:
  sdk: ^3.8.0
dependencies:
  flutter:
    sdk: flutter
flutter:
  assets:
    - assets/brands/alpha/
    - assets/brands/beta/
    - config/alpha/
    - config/beta/
''',
  'brandguard.yaml': '''
version: 1
project:
  name: fixture_suite
defaults:
  environment: production
localization:
  arb_directory: lib/l10n
  base_locale: en
  required_locales: [en, de]
environments:
  production:
    files: ['config/{brand}/production.json']
    forbidden_url_patterns: [staging]
brands:
  - id: alpha
    name: Alpha Bank
    app_name: Alpha Bank
    application_id: com.fixture.alpha
    assets:
      launcher_icon: assets/brands/alpha/icon.png
      logo: assets/brands/alpha/logo.png
  - id: beta
    name: Beta Pay
    app_name: Beta Pay
    application_id: com.fixture.beta
    assets:
      launcher_icon: assets/brands/beta/icon.png
      logo: assets/brands/beta/logo.png
''',
  'android/app/build.gradle': '''
plugins {
    id "com.android.application"
    id "dev.flutter.flutter-gradle-plugin"
}

android {
    namespace "com.fixture.app"
    defaultConfig {
        applicationId "com.fixture.app"
        minSdkVersion flutter.minSdkVersion
    }
    flavorDimensions "brand"
    productFlavors {
        alpha {
            dimension "brand"
            applicationId "com.fixture.alpha"
            manifestPlaceholders = [appName: "Alpha Bank"]
        }
        beta {
            dimension "brand"
            applicationId "com.fixture.beta"
            manifestPlaceholders = [appName: "Beta Pay"]
        }
    }
}
''',
  'android/app/src/main/AndroidManifest.xml': '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="\${appName}"
        android:icon="@mipmap/ic_launcher">
    </application>
</manifest>
''',
  'ios/Runner.xcodeproj/project.pbxproj': pbxproj(
    runnerConfigs: {
      'Debug': {'PRODUCT_BUNDLE_IDENTIFIER': 'com.fixture.app'},
      'Release': {'PRODUCT_BUNDLE_IDENTIFIER': 'com.fixture.app'},
      'Release-alpha': {'PRODUCT_BUNDLE_IDENTIFIER': '"\$(BRAND_BUNDLE_ID)"'},
      'Release-beta': {'PRODUCT_BUNDLE_IDENTIFIER': '"\$(BRAND_BUNDLE_ID)"'},
    },
    xcconfigs: {
      'Release-alpha': 'Flutter/alpha.xcconfig',
      'Release-beta': 'Flutter/beta.xcconfig',
    },
  ),
  'ios/Flutter/alpha.xcconfig':
      '#include? "Generated.xcconfig"\n'
      'BRAND_BUNDLE_ID = com.fixture.alpha\n'
      'BRAND_DISPLAY_NAME = Alpha Bank\n',
  'ios/Flutter/beta.xcconfig':
      '#include? "Generated.xcconfig"\n'
      'BRAND_BUNDLE_ID = com.fixture.beta\n'
      'BRAND_DISPLAY_NAME = Beta Pay\n',
  'ios/Runner/Info.plist': infoPlist(r'$(BRAND_DISPLAY_NAME)'),
  'lib/l10n/app_en.arb': '''
{
  "@@locale": "en",
  "balance": "Balance: {amount}",
  "@balance": {"placeholders": {"amount": {"type": "double"}}},
  "transfers": "{count, plural, =0{No transfers} other{{count} transfers}}",
  "@transfers": {"placeholders": {"count": {"type": "int"}}},
  "logout": "Log out"
}
''',
  'lib/l10n/app_de.arb': '''
{
  "@@locale": "de",
  "balance": "Kontostand: {amount}",
  "transfers": "{count, plural, =0{Keine Überweisungen} other{{count} Überweisungen}}",
  "logout": "Abmelden"
}
''',
  'lib/l10n/app_localizations.dart':
      '// Generated file; must not be read as ARB.\n',
  'config/alpha/production.json':
      '{\n  "api": "https://api.alpha-bank.example/v2"\n}\n',
  'config/beta/production.json':
      '{\n  "api": "https://api.beta-pay.example/v1"\n}\n',
  'config/beta/staging.json':
      '{\n  "api": "https://staging.beta-pay.example/v1"\n}\n',
  'assets/brands/alpha/icon.png': _bytes(3),
  'assets/brands/alpha/logo.png': _bytes(5),
  'assets/brands/beta/icon.png': _bytes(7),
  'assets/brands/beta/logo.png': _bytes(11),
};

/// Intentional mistakes, all affecting brand `beta`.
Map<String, Object> _breakages() => {
  'README.md':
      '# INTENTIONALLY BROKEN FIXTURE\n\n'
      'Used by BrandGuard integration tests. Brand `beta` contains:\n\n'
      '1. A missing logo (assets/brands/beta/logo.png).\n'
      "2. A launcher icon that is a byte copy of alpha's icon.\n"
      '3. A staging URL in config/beta/production.json.\n'
      '4. A German translation missing the `logout` key.\n'
      '5. An iOS bundle ID copied from alpha (beta.xcconfig).\n'
      '6. A wrong Android app name (manifestPlaceholders).\n',
  'assets/brands/beta/icon.png': _bytes(3),
  'config/beta/production.json':
      '{\n  "api": "https://staging.beta-pay.example/v1",\n'
      '  "cdn": "https://cdn.beta-pay.example"\n}\n',
  'lib/l10n/app_de.arb': '''
{
  "@@locale": "de",
  "balance": "Kontostand: {amount}",
  "transfers": "{count, plural, =0{Keine Überweisungen} other{{count} Überweisungen}}"
}
''',
  'ios/Flutter/beta.xcconfig':
      '#include? "Generated.xcconfig"\n'
      'BRAND_BUNDLE_ID = com.fixture.alpha\n'
      'BRAND_DISPLAY_NAME = Beta Pay\n',
  'android/app/build.gradle': '''
plugins {
    id "com.android.application"
    id "dev.flutter.flutter-gradle-plugin"
}

android {
    namespace "com.fixture.app"
    defaultConfig {
        applicationId "com.fixture.app"
        minSdkVersion flutter.minSdkVersion
    }
    flavorDimensions "brand"
    productFlavors {
        alpha {
            dimension "brand"
            applicationId "com.fixture.alpha"
            manifestPlaceholders = [appName: "Alpha Bank"]
        }
        beta {
            dimension "brand"
            applicationId "com.fixture.beta"
            manifestPlaceholders = [appName: "Alpha Bank"]
        }
    }
}
''',
};
