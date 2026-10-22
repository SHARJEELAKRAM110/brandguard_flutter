import 'package:brandguard_flutter/brandguard_flutter.dart';
import 'package:test/test.dart';

import '../support/pbxproj.dart';
import '../support/project_builder.dart';

const _acme = '''
  - id: acme
    name: Acme
    application_id: com.example.acme
''';
const _nova = '''
  - id: nova
    name: Nova
    application_id: com.example.nova
''';

void main() {
  group('missing_brand_configuration', () {
    test('reports each missing required field per brand', () {
      final project = ProjectBuilder()
        ..config('''
version: 1
requirements:
  brand_fields: [name, app_name, application_id, environment, assets.logo, required_locales]
localization:
  required_locales: []
environments:
  production: {}
platforms: {android: {enabled: false}, ios: {enabled: false}}
brands:
  - id: acme
    name: Acme
    app_name: Acme
    application_id: com.example.acme
    environment: production
    required_locales: [en]
    assets: {logo: assets/brands/acme/logo.png}
  - id: nova
    environment: qa
''')
        ..binary('assets/brands/acme/logo.png');
      final result = project.validate();
      final findings = findingsOf(result, 'missing_brand_configuration');
      expect(findings.where((f) => f.brandId == 'acme'), isEmpty);
      expect(
        findings.map((f) => f.message),
        unorderedEquals([
          contains('missing required field `name`'),
          contains('missing required field `app_name`'),
          contains('missing required field `application_id`'),
          contains('missing required field `assets.logo`'),
          contains('missing required field `required_locales`'),
          contains('environment `qa`, which is not declared'),
        ]),
      );
      expect(findings.first.file, '.brandguard.yaml');
      expect(findings.first.line, 17);
      expect(
        result.passesFor('acme').map((p) => p.message),
        contains('Brand configuration is complete'),
      );
    });
  });

  group('duplicate_application_id', () {
    test('reports shared IDs unless the policy allows them', () {
      const brands = '''
  - id: acme
    name: A
    application_id: com.example.shared
  - id: nova
    name: N
    application_id: com.example.shared
''';
      final project = ProjectBuilder()..config(twoBrandConfig(brands: brands));
      final findings = findingsOf(
        project.validate(),
        'duplicate_application_id',
      );
      expect(findings.map((f) => f.brandId), ['acme', 'nova']);
      expect(findings.first.message, contains('`nova`'));

      project.config(
        twoBrandConfig(
          brands: brands,
          extra: 'policy:\n  allow_duplicate_application_ids: true\n',
        ),
      );
      expect(
        findingsOf(project.validate(), 'duplicate_application_id'),
        isEmpty,
      );
    });

    test('only reports selected brands', () {
      final project = ProjectBuilder()
        ..config(
          twoBrandConfig(
            brands: '''
  - id: a
    name: A
    application_id: com.example.x
  - id: b
    name: B
    application_id: com.example.x
  - id: c
    name: C
    application_id: com.example.c
''',
          ),
        );
      expect(
        findingsOf(project.validate(brands: ['c']), 'duplicate_application_id'),
        isEmpty,
      );
    });
  });

  group('missing_assets', () {
    test('passes for existing files and directories', () {
      final project = ProjectBuilder()
        ..binary('assets/brands/acme/icon.png')
        ..binary('assets/brands/acme/images/hero.png')
        ..config(
          twoBrandConfig(
            brands:
                '''
$_acme    assets:
      launcher_icon: assets/brands/acme/icon.png
      images: [assets/brands/acme/images/]
''',
          ),
        );
      final result = project.validate();
      expect(findingsOf(result, 'missing_assets'), isEmpty);
      expect(
        result.passesFor('acme').map((p) => p.message),
        contains('All 2 configured assets exist'),
      );
    });

    test('reports missing files and invalid paths', () {
      final project = ProjectBuilder()
        ..config(
          twoBrandConfig(
            brands:
                '''
$_acme    assets:
      logo: assets/brands/acme/logo.png
      fonts: [../outside/font.ttf, /etc/passwd]
''',
          ),
        );
      final findings = findingsOf(project.validate(), 'missing_assets');
      expect(
        findings.map((f) => f.message),
        unorderedEquals([
          'Missing asset `logo`: assets/brands/acme/logo.png',
          contains('`../outside/font.ttf` is absolute or points outside'),
          contains('`/etc/passwd` is absolute or points outside'),
        ]),
      );
      expect(findings.every((f) => f.severity == Severity.error), isTrue);
    });

    test(
      'explicit asset paths are checked even inside excluded directories',
      () {
        final project = ProjectBuilder()
          ..binary('generated/brand/logo.png')
          ..config(
            twoBrandConfig(
              extra: 'scan:\n  exclude: [generated]\n',
              brands:
                  '$_acme    assets:\n      logo: generated/brand/logo.png\n',
            ),
          );
        expect(findingsOf(project.validate(), 'missing_assets'), isEmpty);
      },
    );
  });

  group('undeclared_assets', () {
    test('distinguishes undeclared files from missing ones', () {
      final project = ProjectBuilder()
        ..binary('assets/brands/acme/logo.png')
        ..binary('assets/brands/acme/deep/banner.png')
        ..binary('assets/brands/acme/icon.png')
        ..binary('fonts/Acme.ttf')
        ..pubspecAssets(['assets/brands/acme/'])
        ..config(
          twoBrandConfig(
            brands:
                '''
$_acme    assets:
      launcher_icon: assets/brands/acme/icon.png
      logo: assets/brands/acme/logo.png
      banner: assets/brands/acme/deep/banner.png
      fonts: [fonts/Acme.ttf]
      missing: assets/brands/acme/nope.png
''',
          ),
        );
      final findings = findingsOf(project.validate(), 'undeclared_assets');
      expect(
        findings.map((f) => f.message),
        unorderedEquals([
          contains('`banner` exists but is not declared'),
          contains('Font `fonts/Acme.ttf` exists but is not declared'),
        ]),
      );
      expect(findings.every((f) => f.severity == Severity.warning), isTrue);
    });

    test('checks flavor-restricted declarations and fonts', () {
      final project = ProjectBuilder()
        ..binary('assets/brands/nova/logo.png')
        ..binary('fonts/Nova.ttf')
        ..pubspecAssets(
          [],
          extra: '''
    - path: assets/brands/nova/
      flavors: [acme]
  fonts:
    - family: Nova
      fonts:
        - asset: fonts/Nova.ttf
''',
        )
        ..config(
          twoBrandConfig(
            brands:
                '''
$_nova    assets:
      logo: assets/brands/nova/logo.png
      fonts: fonts/Nova.ttf
''',
          ),
        );
      final findings = findingsOf(project.validate(), 'undeclared_assets');
      expect(
        findings.single.message,
        contains('declared only for flavor(s) acme, not `nova`'),
      );
      expect(findings.single.line, isNotNull);
    });

    test('can be disabled with require_declaration: false', () {
      final project = ProjectBuilder()
        ..binary('assets/logo.png')
        ..config(
          twoBrandConfig(
            extra: 'assets:\n  require_declaration: false\n',
            brands: '$_acme    assets:\n      logo: assets/logo.png\n',
          ),
        );
      expect(findingsOf(project.validate(), 'undeclared_assets'), isEmpty);
    });
  });

  group('brand_asset_leakage', () {
    test('reports assets under another brand directory (convention)', () {
      final project = ProjectBuilder()
        ..binary('assets/brands/acme/logo.png', seed: 1)
        ..binary('assets/brands/nova/logo.png', seed: 2)
        ..config(
          twoBrandConfig(
            brands:
                '''
$_acme    assets:
      logo: assets/brands/acme/logo.png
$_nova    assets:
      logo: assets/brands/acme/logo.png
''',
          ),
        );
      final findings = findingsOf(project.validate(), 'brand_asset_leakage');
      expect(findings.single.brandId, 'nova');
      expect(
        findings.single.message,
        contains('uses `logo` from brand `acme`'),
      );
      expect(findings.single.certainty, Certainty.heuristic);
      expect(findings.single.severity, Severity.warning);
    });

    test('explicit asset_roots make ownership definite', () {
      final project = ProjectBuilder()
        ..binary('art/a/logo.png', seed: 1)
        ..config(
          twoBrandConfig(
            brands:
                '''
$_acme    asset_roots: [art/a]
    assets:
      logo: art/a/logo.png
$_nova    asset_roots: [art/n]
    assets:
      logo: art/a/logo.png
''',
          ),
        );
      final finding = findingsOf(
        project.validate(),
        'brand_asset_leakage',
      ).single;
      expect(finding.certainty, Certainty.definite);
    });

    test('reports the same file used by two brands outside owned roots', () {
      final project = ProjectBuilder()
        ..binary('assets/icon.png')
        ..config(
          twoBrandConfig(
            extra: 'assets:\n  brands_root: null\n',
            brands:
                '''
$_acme    assets:
      launcher_icon: assets/icon.png
$_nova    assets:
      launcher_icon: assets/icon.png
''',
          ),
        );
      final findings = findingsOf(project.validate(), 'brand_asset_leakage');
      expect(findings.map((f) => f.brandId), ['acme', 'nova']);
      expect(findings.first.message, contains('same `launcher_icon` file'));
    });

    test('reports byte-identical copies and respects shared_paths', () {
      final project = ProjectBuilder()
        ..binary('assets/brands/acme/icon.png', seed: 7)
        ..binary('assets/brands/nova/icon.png', seed: 7)
        ..binary('assets/shared/a.png', seed: 3)
        ..binary('assets/shared/b.png', seed: 3)
        ..config(
          twoBrandConfig(
            extra:
                'assets:\n  isolation:\n    shared_paths: [assets/shared/**]\n',
            brands:
                '''
$_acme    assets:
      launcher_icon: assets/brands/acme/icon.png
      placeholder: assets/shared/a.png
$_nova    assets:
      launcher_icon: assets/brands/nova/icon.png
      placeholder: assets/shared/b.png
''',
          ),
        );
      final findings = findingsOf(project.validate(), 'brand_asset_leakage');
      expect(findings.map((f) => f.brandId), ['acme', 'nova']);
      expect(findings.last.message, contains('byte-identical'));
      expect(findings.last.message, contains('assets/brands/acme/icon.png'));
    });

    test('path heuristic only fires on directory names, and can be disabled', () {
      final project = ProjectBuilder()
        ..binary('assets/images/nova/acme_promo.png', seed: 1)
        ..binary('assets/images/novalike/x.png', seed: 2)
        ..config(
          twoBrandConfig(
            extra: 'assets:\n  brands_root: null\n',
            brands:
                '''
$_acme    assets:
      promo: assets/images/nova/acme_promo.png
      other: assets/images/novalike/x.png
$_nova
''',
          ),
        );
      final findings = findingsOf(project.validate(), 'brand_asset_leakage');
      expect(
        findings.single.message,
        contains('directory named after brand `nova`'),
      );
      expect(findings.single.certainty, Certainty.heuristic);

      project.config(
        twoBrandConfig(
          extra:
              'assets:\n  brands_root: null\n  isolation:\n    path_heuristics: false\n',
          brands:
              '$_acme    assets:\n      promo: assets/images/nova/acme_promo.png\n$_nova',
        ),
      );
      expect(findingsOf(project.validate(), 'brand_asset_leakage'), isEmpty);
    });
  });

  group('environment URLs', () {
    ProjectBuilder envProject(
      String acmeJson, {
      String env = '',
      String brand = 'production',
    }) => ProjectBuilder()
      ..file('config/acme/production.json', acmeJson)
      ..file(
        'config/acme/staging.json',
        '{"api": "https://staging-api.acme.example"}',
      )
      ..config(
        twoBrandConfig(
          extra:
              '''
environments:
  production:
    files: ['config/{brand}/production.json']
    forbidden_url_patterns: [staging, dev-api]
    forbidden_hosts: [api.internal.example]
$env  staging:
    files: ['config/{brand}/staging.json']
    forbidden_url_patterns: [production-api]
''',
          brands: '$_acme    environment: $brand\n',
        ),
      );

    test('reports staging URLs in production with redacted credentials', () {
      final project = envProject('''
{
  "api": "https://staging-api.acme.example/v1?token=SECRET123",
  "auth": "https://user:hunter2@api.internal.example/login",
  "local": "http://localhost:8080"
}
''');
      final findings = findingsOf(
        project.validate(),
        'forbidden_environment_url',
      );
      expect(findings.map((f) => f.line), [2, 3, 4]);
      final text = findings.map((f) => f.message).join('\n');
      expect(text, contains('matches forbidden pattern `staging`'));
      expect(text, contains('listed in forbidden_hosts'));
      expect(text, contains('local/loopback host'));
      expect(text, isNot(contains('SECRET123')));
      expect(text, isNot(contains('hunter2')));
      expect(text, contains('token=***'));
    });

    test('valid production URLs pass and staging files are not scanned', () {
      final project = envProject('{"api": "https://api.acme.example/v1"}');
      final result = project.validate();
      expect(findingsOf(result, 'forbidden_environment_url'), isEmpty);
      expect(findingsOf(result, 'suspicious_environment_url'), isEmpty);
      expect(
        result.passesFor('acme').map((p) => p.message),
        contains('No forbidden URLs in 1 production file'),
      );
    });

    test('staging brands use staging rules', () {
      final project = envProject('{}', brand: 'staging');
      expect(project.validate().findings, isEmpty);
    });

    test('heuristics warn, allowed_hosts suppress', () {
      final project = envProject('''
{"a": "https://api.qa.acme.example", "b": "https://devices.acme.example",
 "c": "https://api.uat.acme.example"}
''', env: '    allowed_hosts: [api.uat.acme.example]\n');
      final result = project.validate();
      final heuristic = findingsOf(result, 'suspicious_environment_url');
      expect(heuristic.single.message, contains('host contains `qa`'));
      expect(heuristic.single.severity, Severity.warning);
      expect(heuristic.single.certainty, Certainty.heuristic);
      expect(findingsOf(result, 'forbidden_environment_url'), isEmpty);
    });

    test('ignores the word staging outside URLs and commented-out URLs', () {
      final project =
          envProject('''
{
  "environment_label": "not staging",
  "api": "https://api.acme.example"
}
''')..file(
            'config/acme/production.json',
            '# api: https://staging.acme.example\napi: https://api.acme.example\n',
          );
      expect(
        findingsOf(project.validate(), 'forbidden_environment_url'),
        isEmpty,
      );
    });

    test('warns when a file pattern matches nothing', () {
      final project = envProject('{}')..file('config/acme/production.json', '');
      project.config(
        project
            .read('.brandguard.yaml')
            .replaceFirst(
              "files: ['config/{brand}/production.json']",
              "files: ['config/{brand}/production.json', 'config/{brand}/prod.env']",
            ),
      );
      final finding = findingsOf(
        project.validate(),
        'forbidden_environment_url',
      ).single;
      expect(finding.severity, Severity.warning);
      expect(finding.message, contains('config/acme/prod.env'));
    });

    test('reports skipped checks when no files are configured', () {
      final project = ProjectBuilder()
        ..config(
          twoBrandConfig(
            extra: 'environments:\n  production: {}\n',
            brands: '$_acme    environment: production\n',
          ),
        );
      final finding = findingsOf(
        project.validate(),
        'forbidden_environment_url',
      ).single;
      expect(finding.severity, Severity.info);
      expect(finding.certainty, Certainty.unresolved);
    });

    test('excluded directories are not scanned', () {
      final project = envProject('{}')
        ..file(
          'build/acme/production.json',
          '{"a": "https://staging.x.example"}',
        );
      project.config(
        project
            .read('.brandguard.yaml')
            .replaceFirst(
              "'config/{brand}/production.json'",
              "'config/{brand}/production.json', '**/production.json'",
            ),
      );
      expect(
        findingsOf(project.validate(), 'forbidden_environment_url'),
        isEmpty,
      );
    });
  });

  group('localization rules', () {
    ProjectBuilder l10nProject() => ProjectBuilder()
      ..file(
        'lib/l10n/app_en.arb',
        '{"hello": "Hello {name}", "@hello": {"placeholders": {"name": {}}}, "bye": "Bye"}',
      )
      ..file('lib/l10n/app_es.arb', '{"hello": "Hola {name}", "bye": "Adiós"}')
      ..file('lib/l10n/app_fr.arb', '{"hello": "Bonjour {nom}"}')
      ..file('lib/l10n/app_de.arb', '{"hello": "Hallo {name}", "bye": ')
      ..config(
        twoBrandConfig(
          localization: '''
localization:
  arb_directory: lib/l10n
  base_locale: en
  required_locales: [en, es]
''',
          brands:
              '''
$_acme$_nova    required_locales: [en, fr, de, it]
''',
        ),
      );

    test('per-brand locales: clean brand passes, broken brand fails', () {
      final result = l10nProject().validate();
      expect(result.findingsFor('acme'), isEmpty);
      expect(
        result.passesFor('acme').map((p) => p.message),
        contains('Required locales present (en, es)'),
      );

      final missing = findingsOf(result, 'missing_translations', brand: 'nova');
      expect(
        missing.map((f) => f.message),
        unorderedEquals([
          'Missing translation `bye` in locale `fr`.',
          contains('ARB file for locale `it` not found'),
        ]),
      );
      final invalid = findingsOf(result, 'invalid_arb', brand: 'nova').single;
      expect(invalid.file, 'lib/l10n/app_de.arb');
      final placeholders = findingsOf(
        result,
        'arb_placeholder_mismatch',
        brand: 'nova',
      );
      expect(
        placeholders.map((f) => f.severity),
        unorderedEquals([Severity.error, Severity.warning]),
      );
    });

    test('a configured ARB directory that does not exist is an error', () {
      final project = ProjectBuilder()
        ..config(
          twoBrandConfig(
            localization:
                'localization:\n  arb_directory: lib/i18n\n  required_locales: [en]\n',
            brands: _acme,
          ),
        );
      final finding = findingsOf(
        project.validate(),
        'missing_translations',
      ).single;
      expect(finding.message, contains('lib/i18n'));
      expect(finding.severity, Severity.error);
    });

    test('localization can be disabled for non-ARB projects', () {
      final project = l10nProject();
      project.config(
        project
            .read('.brandguard.yaml')
            .replaceFirst(
              'localization:\n',
              'localization:\n  enabled: false\n',
            ),
      );
      final result = project.validate();
      expect(
        result.findings.where(
          (f) => f.ruleId.contains('arb') || f.ruleId == 'missing_translations',
        ),
        isEmpty,
      );
    });
  });

  group('platform rules', () {
    ProjectBuilder platformProject({
      required String gradle,
      String? pbx,
      String brands = '$_acme$_nova',
    }) {
      final project = ProjectBuilder()
        ..file('android/app/build.gradle', gradle)
        ..file(
          'android/app/src/main/AndroidManifest.xml',
          '<manifest><application android:label="@string/app_name"/></manifest>',
        )
        ..config('''
version: 1
requirements: {brand_fields: []}
localization: {enabled: false}
brands:
$brands''');
      if (pbx != null) {
        project
          ..file('ios/Runner.xcodeproj/project.pbxproj', pbx)
          ..file('ios/Runner/Info.plist', infoPlist(r'$(APP_DISPLAY_NAME)'));
      }
      return project;
    }

    const flavors = '''
android {
  defaultConfig { applicationId "com.example.base" }
  productFlavors {
    acme { applicationId "com.example.acme"; resValue "string", "app_name", "Acme" }
    nova { applicationId "com.example.acme" }
  }
}
''';

    test('Android match, mismatch and missing flavor', () {
      final project = platformProject(
        gradle: flavors,
        brands:
            '$_acme    app_name: Acme\n$_nova  - id: orbit\n    application_id: com.example.orbit\n',
      );
      final result = project.validate();
      final ids = findingsOf(result, 'application_identifier_mismatch');
      expect(ids.where((f) => f.brandId == 'acme'), isEmpty);
      final nova = ids.firstWhere((f) => f.brandId == 'nova');
      expect(nova.severity, Severity.error);
      expect(
        nova.message,
        'Android application ID mismatch: expected `com.example.nova`, found `com.example.acme`.',
      );
      expect((nova.file, nova.line), ('android/app/build.gradle', 5));
      final orbit = ids.firstWhere((f) => f.brandId == 'orbit');
      expect(orbit.severity, Severity.warning);
      expect(orbit.certainty, Certainty.unresolved);
      expect(orbit.explanation, contains('acme, nova'));
      expect(
        result.passesFor('acme').map((p) => p.message),
        containsAll([
          'Android application ID matches (com.example.acme)',
          'Android app name matches (Acme)',
        ]),
      );
      // No iOS project: one informational, project-wide note per rule.
      expect(
        result.findingsFor(null).map((f) => (f.ruleId, f.severity)),
        contains(('application_identifier_mismatch', Severity.info)),
      );
    });

    test('unresolvable Gradle variables need manual verification', () {
      final project = platformProject(
        gradle: '''
android { productFlavors {
  acme { applicationId flavorConfig.acmeId }
  nova { applicationId "com.example.\${suffix}" }
} }
''',
      );
      final ids = findingsOf(
        project.validate(),
        'application_identifier_mismatch',
      ).where((f) => f.brandId != null);
      expect(
        ids.map((f) => (f.severity, f.certainty)),
        everyElement((Severity.info, Certainty.unresolved)),
      );
      expect(ids.first.message, contains('needs manual verification'));
    });

    test(
      'without flavors a multi-brand project cannot be verified definitively',
      () {
        final project = platformProject(
          gradle:
              'android { defaultConfig { applicationId "com.example.acme" } }',
        );
        final ids = findingsOf(
          project.validate(),
          'application_identifier_mismatch',
        ).where((f) => f.brandId != null).toList();
        expect(ids.single.brandId, 'nova');
        expect(ids.single.severity, Severity.info);
        expect(ids.single.message, contains('currently set to `acme`'));
      },
    );

    test('without flavors a single-brand project is checked definitively', () {
      final project = platformProject(
        gradle:
            'android { defaultConfig { applicationId "com.example.other" } }',
        brands: _acme,
      );
      final finding = findingsOf(
        project.validate(),
        'application_identifier_mismatch',
      ).firstWhere((f) => f.brandId == 'acme');
      expect(finding.severity, Severity.error);
    });

    test('iOS bundle ID and display name match and mismatch', () {
      final project = platformProject(
        gradle: flavors.replaceFirst(
          'nova { applicationId "com.example.acme" }',
          'nova { applicationId "com.example.nova"; resValue "string", "app_name", "Nova" }',
        ),
        pbx: pbxproj(
          runnerConfigs: {
            'Release-acme': {
              'PRODUCT_BUNDLE_IDENTIFIER': 'com.example.acme',
              'APP_DISPLAY_NAME': '"Acme"',
            },
            'Release-nova': {
              'PRODUCT_BUNDLE_IDENTIFIER': 'com.example.acme',
              'APP_DISPLAY_NAME': '"Nova Shop"',
            },
          },
        ),
        brands: '$_acme    app_name: Acme\n$_nova    app_name: Nova\n',
      );
      final result = project.validate();
      expect(result.findingsFor('acme'), isEmpty);
      final nova = result.findingsFor('nova');
      expect(
        nova.map((f) => f.message),
        unorderedEquals([
          'iOS bundle ID mismatch: expected `com.example.nova`, found `com.example.acme`.',
          'iOS app name mismatch: expected `Nova`, found `Nova Shop`.',
        ]),
      );
      expect(
        nova.first.file,
        anyOf('ios/Runner.xcodeproj/project.pbxproj', 'ios/Runner/Info.plist'),
      );
    });

    test('missing platform configuration is reported as skipped, once', () {
      final project = ProjectBuilder()
        ..config(
          'version: 1\nrequirements: {brand_fields: []}\n'
          'localization: {enabled: false}\nbrands:\n$_acme    app_name: A\n$_nova',
        );
      final shared = project.validate().findingsFor(null);
      expect(
        shared.map((f) => f.message),
        unorderedEquals([
          startsWith('Android checks skipped'),
          startsWith('iOS checks skipped'),
          startsWith('Android checks skipped'),
          startsWith('iOS checks skipped'),
        ]),
      );
      expect(shared.every((f) => f.severity == Severity.info), isTrue);
    });
  });

  group('policy and overrides', () {
    ProjectBuilder warningProject(String rules) => ProjectBuilder()
      ..binary('assets/brands/acme/logo.png', seed: 1)
      ..pubspecAssets(['assets/brands/acme/'])
      ..config(
        twoBrandConfig(
          extra: rules,
          brands:
              '''
$_acme    assets:
      logo: assets/brands/acme/logo.png
$_nova    assets:
      logo: assets/brands/acme/logo.png
''',
        ),
      );

    test('warnings pass normally and fail in strict mode', () {
      final project = warningProject('');
      final normal = project.validate();
      expect(normal.count(Severity.warning), greaterThan(0));
      expect(normal.count(Severity.error), 0);
      expect(normal.exitCode, 0);
      final strict = project.validate(strict: true);
      expect(strict.exitCode, 1);
      expect(strict.findings.where(strict.failsPolicy), isNotEmpty);
    });

    test('policy.strict has the same effect as --strict', () {
      expect(
        warningProject('policy:\n  strict: true\n').validate().exitCode,
        1,
      );
    });

    test('global severity overrides and per-brand overrides', () {
      final project = warningProject('''
rules:
  brand_asset_leakage: error
''');
      expect(project.validate().exitCode, 1);

      project.config(
        project
            .read('.brandguard.yaml')
            .replaceFirst(
              '  - id: nova\n',
              '  - id: nova\n    rules:\n      brand_asset_leakage: {enabled: false}\n',
            ),
      );
      final result = project.validate();
      expect(findingsOf(result, 'brand_asset_leakage', brand: 'nova'), isEmpty);
    });

    test('a rule configured as info never emits warnings', () {
      final result = warningProject(
        'rules:\n  brand_asset_leakage: info\n',
      ).validate(strict: true);
      expect(
        findingsOf(result, 'brand_asset_leakage').map((f) => f.severity),
        everyElement(Severity.info),
      );
      expect(result.exitCode, 0);
    });

    test('unknown brands are rejected', () {
      expect(
        () => warningProject('').validate(brands: ['zenith']),
        throwsA(
          isA<UnknownBrandException>().having((e) => e.available, 'available', [
            'acme',
            'nova',
          ]),
        ),
      );
    });
  });

  group('custom rules', () {
    test('can be added through the public API and configured', () {
      final project = ProjectBuilder()
        ..config(
          twoBrandConfig(
            brands:
                '$_acme${_nova.replaceFirst('name: Nova', 'name: Nova Store')}',
            extra: 'rules:\n  brand_name_length: warning\n',
          ),
        );
      final guard = BrandGuard(
        rules: [...BrandGuard.defaultRules(), _NameLengthRule()],
      );
      final result = guard.validate(
        guard.loadConfig(projectDirectory: project.root),
      );
      final finding = findingsOf(result, 'brand_name_length').single;
      expect(finding.brandId, 'acme');
      expect(finding.severity, Severity.warning);
    });

    test('duplicate rule IDs are rejected', () {
      expect(
        () => BrandGuard(rules: [_NameLengthRule(), _NameLengthRule()]),
        throwsArgumentError,
      );
    });

    test('crashing rules surface as RuleExecutionException', () {
      final project = ProjectBuilder()..config(twoBrandConfig(brands: _acme));
      final guard = BrandGuard(rules: [_CrashingRule()]);
      expect(
        () => guard.validate(guard.loadConfig(projectDirectory: project.root)),
        throwsA(isA<RuleExecutionException>()),
      );
    });
  });
}

class _NameLengthRule extends Rule {
  @override
  String get id => 'brand_name_length';
  @override
  String get description => 'Brand names are longer than 4 characters.';
  @override
  Severity get defaultSeverity => Severity.error;
  @override
  void run(RuleContext context, RuleReporter reporter) {
    for (final brand in reporter.enabledBrands) {
      if (brand.displayName.length <= 4) {
        reporter.fail(
          brand: brand,
          message: '`${brand.displayName}` is short.',
        );
      }
    }
  }
}

class _CrashingRule extends Rule {
  @override
  String get id => 'crash';
  @override
  String get description => 'Always throws.';
  @override
  Severity get defaultSeverity => Severity.error;
  @override
  void run(RuleContext context, RuleReporter reporter) =>
      throw StateError('boom');
}
