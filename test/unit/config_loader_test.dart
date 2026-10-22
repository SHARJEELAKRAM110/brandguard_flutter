import 'dart:io';

import 'package:brandguard_flutter/brandguard_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/project_builder.dart';

ConfigLoader _loader() =>
    ConfigLoader(knownRuleIds: BrandGuard().rules.map((r) => r.id));

BrandGuardConfig _parse(String yaml, {String root = '/project'}) =>
    _loader().parse(yaml, configPath: p.join(root, '.brandguard.yaml'));

List<ConfigIssue> _issues(String yaml) {
  try {
    _parse(yaml);
  } on ConfigException catch (e) {
    return e.issues;
  }
  fail('Expected a ConfigException');
}

void main() {
  group('ConfigLoader', () {
    test('parses a complete configuration', () {
      final config = _parse('''
version: 1
project:
  name: retail_suite
scan:
  exclude: [generated/**]
defaults:
  environment: production
policy:
  strict: true
assets:
  brands_root: assets/brands
  declaration_exempt: [launcher_icon, splash]
localization:
  arb_directory: lib/l10n
  base_locale: en
  required_locales: [en, es]
environments:
  production:
    forbidden_url_patterns: [staging]
    files: ['config/{brand}/prod.json']
  staging: {}
rules:
  brand_asset_leakage:
    severity: error
  missing_translations: false
  undeclared_assets: info
brands:
  - id: acme
    name: Acme Retail
    app_name: Acme
    application_id: com.example.acme
    ios_bundle_id: com.example.acme-ios
    flavor: acmeFlavor
    assets:
      launcher_icon: assets/brands/acme/icon.png
      fonts: [fonts/a.ttf, fonts/b.ttf]
    required_locales: [en]
    rules:
      missing_assets: {enabled: false}
''');
      expect(config.projectName, 'retail_suite');
      expect(config.strict, isTrue);
      expect(config.excludes, ['generated/**']);
      expect(config.assets.declarationExempt, ['launcher_icon', 'splash']);
      expect(config.localization.requiredLocales, ['en', 'es']);
      expect(config.environments.keys, ['production', 'staging']);
      expect(config.environments['production']!.blockLoopback, isTrue);
      expect(config.environments['production']!.heuristics, isTrue);
      expect(config.environments['staging']!.blockLoopback, isFalse);
      expect(config.rules['brand_asset_leakage']!.severity, Severity.error);
      expect(config.rules['missing_translations']!.enabled, isFalse);
      expect(config.rules['undeclared_assets']!.severity, Severity.info);
      final brand = config.brands.single;
      expect(brand.expectedIosBundleId, 'com.example.acme-ios');
      expect(brand.effectiveFlavor, 'acmeFlavor');
      expect(brand.assets['fonts'], ['fonts/a.ttf', 'fonts/b.ttf']);
      expect(brand.rules['missing_assets']!.enabled, isFalse);
      expect(config.environmentOf(brand), 'production');
      expect(config.requiredLocalesOf(brand), ['en']);
    });

    test('reports invalid YAML with a line number', () {
      final issues = _issues('version: 1\nbrands:\n  - id: a\n   bad: [');
      expect(issues.single.message, startsWith('Invalid YAML'));
      expect(issues.single.line, isNotNull);
    });

    test('reports missing required fields', () {
      final issues = _issues('project:\n  name: x\n');
      final messages = issues.map((i) => i.message).join('\n');
      expect(messages, contains('Missing required field `version`'));
      expect(messages, contains('Missing required field `brands`'));
    });

    test('rejects unsupported versions', () {
      final issues = _issues('version: 2\nbrands:\n  - id: a\n');
      expect(issues.single.message, contains('Unsupported configuration'));
      expect(issues.single.line, 1);
    });

    test('detects duplicate brand IDs with both lines', () {
      final issues = _issues('''
version: 1
brands:
  - id: acme
  - id: nova
  - id: acme
''');
      expect(issues.single.message, contains('Duplicate brand ID `acme`'));
      expect(issues.single.message, contains('line 3'));
      expect(issues.single.line, 5);
      expect(issues.single.field, 'brands[2].id');
    });

    test('rejects invalid severities and unknown rules', () {
      final issues = _issues('''
version: 1
rules:
  missing_assets:
    severity: critical
  not_a_rule: true
brands:
  - id: a
''');
      expect(
        issues.map((i) => i.message),
        containsAll([
          contains('Invalid severity `critical`'),
          contains('Unknown rule `not_a_rule`'),
        ]),
      );
    });

    test('rejects unknown fields and suggests close matches', () {
      final issues = _issues('''
version: 1
brands:
  - id: a
    aplication_id: com.example.a
''');
      expect(issues.single.message, contains('Unknown field'));
      expect(issues.single.message, contains('Did you mean `application_id`'));
      expect(issues.single.line, 4);
    });

    test('rejects wrong value types instead of ignoring them', () {
      final issues = _issues('''
version: 1
localization:
  enabled: yes please
  required_locales: en
brands:
  - id: a
    name: 42
    assets: [a.png]
''');
      final messages = issues.map((i) => i.message).toList();
      expect(messages, contains(contains('`localization.enabled` must be')));
      expect(
        messages,
        contains(contains('`localization.required_locales` must be a list')),
      );
      expect(messages, contains(contains('`brands[0].name` must be a string')));
      expect(messages, contains(contains('`brands[0].assets` must map')));
    });

    test('validates application identifiers', () {
      final issues = _issues('''
version: 1
brands:
  - id: a
    application_id: com.example.my-app
  - id: b
    application_id: nodots
''');
      expect(issues, hasLength(2));
      expect(issues.first.message, contains('not a valid Android'));
    });

    test('rejects brand IDs with spaces and missing IDs', () {
      final issues = _issues('''
version: 1
brands:
  - id: my brand
  - name: no id
''');
      expect(issues.map((i) => i.message), [
        contains('may only contain'),
        contains('missing required field `id`'),
      ]);
    });

    test('requires `{locale}` in the ARB file pattern', () {
      final issues = _issues('''
version: 1
localization:
  file_pattern: strings.arb
brands:
  - id: a
''');
      expect(issues.single.message, contains('{locale}'));
    });

    test('reports undeclared default environment', () {
      final issues = _issues('''
version: 1
defaults: {environment: prod}
environments:
  production: {}
brands:
  - id: a
''');
      expect(issues.single.message, contains('not declared'));
    });

    test('resolves project.root relative to the configuration file', () {
      final project = ProjectBuilder();
      project.file('tools/brandguard.yaml', '''
version: 1
project:
  root: ..
brands:
  - id: a
''');
      final config = _loader().load(
        p.join(project.root, 'tools', 'brandguard.yaml'),
      );
      expect(p.equals(config.projectRoot, project.root), isTrue);
    });

    test('discovers the ARB directory and base locale from l10n.yaml', () {
      final project = ProjectBuilder()
        ..file(
          'l10n.yaml',
          'arb-dir: res/strings\ntemplate-arb-file: app_de.arb\n',
        )
        ..config('version: 1\nbrands:\n  - id: a\n');
      final config = BrandGuard().loadConfig(projectDirectory: project.root);
      expect(config.localization.arbDirectory, 'res/strings');
      expect(config.localization.baseLocale, 'de');
      expect(config.localization.arbDirectoryExplicit, isFalse);
    });

    test('reports a missing configuration file helpfully', () {
      final project = ProjectBuilder();
      expect(
        () => BrandGuard().loadConfig(projectDirectory: project.root),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.issues.single.message,
            'message',
            contains('brandguard init'),
          ),
        ),
      );
    });

    test('loads a custom configuration path', () {
      final project = ProjectBuilder()
        ..file(
          'ci/custom.yaml',
          'version: 1\nproject: {root: ..}\nbrands:\n  - id: z\n',
        );
      final config = BrandGuard().loadConfig(
        configPath: p.join(project.root, 'ci', 'custom.yaml'),
      );
      expect(config.brands.single.id, 'z');
      expect(p.equals(config.projectRoot, project.root), isTrue);
    });

    test('accepts brandguard.yaml and rejects having both names', () {
      final project = ProjectBuilder()
        ..file('brandguard.yaml', 'version: 1\nbrands:\n  - id: visible\n');
      final config = BrandGuard().loadConfig(projectDirectory: project.root);
      expect(config.brands.single.id, 'visible');
      expect(p.basename(config.configPath), 'brandguard.yaml');

      project.config('version: 1\nbrands:\n  - id: hidden\n');
      expect(
        () => BrandGuard().loadConfig(projectDirectory: project.root),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.issues.single.message,
            'message',
            contains('Both .brandguard.yaml and brandguard.yaml exist'),
          ),
        ),
      );
    });

    test('a custom configuration must still point at a Flutter project', () {
      final project = ProjectBuilder(flutter: false)
        ..config('version: 1\nbrands:\n  - id: z\n');
      expect(
        () => BrandGuard().loadConfig(
          configPath: p.join(project.root, '.brandguard.yaml'),
        ),
        throwsA(isA<ProjectNotFoundException>()),
      );
    });

    test('unreadable configuration path fails safely', () {
      final dir = Directory.systemTemp.createTempSync('bg_cfg');
      addTearDown(() => dir.deleteSync(recursive: true));
      expect(
        () => _loader().load(p.join(dir.path, 'missing.yaml')),
        throwsA(isA<ConfigException>()),
      );
    });
  });
}
