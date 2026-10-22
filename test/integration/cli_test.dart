import 'dart:convert';
import 'dart:io';

import 'package:brandguard_flutter/brandguard_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/project_builder.dart';

ProjectBuilder _project({bool broken = false}) => ProjectBuilder()
  ..binary('assets/brands/acme/logo.png', seed: 1)
  ..binary('assets/brands/nova/logo.png', seed: broken ? 1 : 2)
  ..pubspecAssets(['assets/brands/acme/', 'assets/brands/nova/'])
  ..config(
    twoBrandConfig(
      brands: '''
  - id: acme
    name: Acme
    application_id: com.example.acme
    assets: {logo: assets/brands/acme/logo.png}
  - id: nova
    name: Nova
    application_id: com.example.nova
    assets: {logo: assets/brands/nova/logo.png}
''',
    ),
  );

void main() {
  group('help and usage', () {
    test('--help lists commands and exit codes', () async {
      final cli = CliHarness(Directory.current.path);
      expect(await cli.run(['--help']), ExitCodes.passed);
      expect(
        '${cli.out}',
        allOf(
          contains('check'),
          contains('init'),
          contains('rules'),
          contains('Exit codes: 0 passed, 1 validation failed, 2'),
        ),
      );
    });

    test('check --help documents every flag', () async {
      final cli = CliHarness(Directory.current.path);
      expect(await cli.run(['check', '--help']), 0);
      for (final flag in [
        '--brand',
        '--all',
        '--format',
        '--strict',
        '--quiet',
        '--verbose',
        '--config',
        '--project',
        '--[no-]color',
      ]) {
        expect('${cli.out}', contains(flag));
      }
    });

    test('--version', () async {
      final cli = CliHarness(Directory.current.path);
      expect(await cli.run(['--version']), 0);
      expect('${cli.out}'.trim(), 'brandguard $brandGuardVersion');
    });

    test('invalid arguments exit with 2', () async {
      for (final args in [
        ['check', '--format', 'xml'],
        ['check', '--brand', 'a', '--all'],
        ['check', '--quiet', '--verbose'],
        ['check', 'extra'],
        ['frobnicate'],
      ]) {
        final cli = CliHarness(Directory.current.path);
        expect(await cli.run(args), ExitCodes.error, reason: '$args');
        expect('${cli.err}', startsWith('Error:'), reason: '$args');
      }
    });

    test('rules lists every built-in rule', () async {
      final cli = CliHarness(Directory.current.path);
      expect(await cli.run(['rules']), 0);
      for (final rule in BrandGuard.defaultRules()) {
        expect('${cli.out}', contains(rule.id));
      }
    });
  });

  group('check', () {
    test('text report, exit 0 for a clean project', () async {
      final project = _project();
      final cli = CliHarness(project.root);
      expect(await cli.run(['check', '--no-color']), 0);
      expect('${cli.out}', contains('ACME (acme)'));
      expect('${cli.out}', contains('Result: PASSED'));
      expect('${cli.out}', isNot(contains('\x1B[')));
    });

    test('warnings pass normally but fail with --strict', () async {
      final project = _project(broken: true);
      final normal = CliHarness(project.root);
      expect(await normal.run(['check']), 0);
      expect('${normal.out}', contains('WARN'));
      final strict = CliHarness(project.root);
      expect(await strict.run(['check', '--strict']), 1);
      expect('${strict.out}', contains('(fails in strict mode)'));
      expect('${strict.out}', contains('Mode: strict'));
    });

    test('--brand limits validation, unknown brands exit 2', () async {
      final project = _project();
      final one = CliHarness(project.root);
      expect(
        await one.run(['check', '--brand', 'nova', '--format', 'json']),
        0,
      );
      final json = jsonDecode('${one.out}') as Map<String, Object?>;
      expect((json['brands'] as List).map((b) => (b as Map)['id']), ['nova']);

      final unknown = CliHarness(project.root);
      expect(await unknown.run(['check', '--brand', 'zenith']), 2);
      expect('${unknown.err}', contains('Configured brands: acme, nova'));
    });

    test('--all validates every brand', () async {
      final cli = CliHarness(_project().root);
      expect(await cli.run(['check', '--all', '--format', 'json']), 0);
      final json = jsonDecode('${cli.out}') as Map<String, Object?>;
      expect((json['summary'] as Map)['brands_checked'], 2);
    });

    test('JSON follows the documented schema', () async {
      final project = _project(broken: true);
      final cli = CliHarness(project.root);
      expect(await cli.run(['check', '--format', 'json', '--strict']), 1);
      final json = jsonDecode('${cli.out}') as Map<String, Object?>;
      expect(json.keys, [
        'schema_version',
        'tool',
        'project',
        'strict',
        'result',
        'exit_code',
        'summary',
        'brands',
        'findings',
        'passed_checks',
      ]);
      expect(json['exit_code'], 1);
      final finding = (json['findings'] as List).first as Map<String, Object?>;
      expect(finding.keys, [
        'rule_id',
        'severity',
        'fails_policy',
        'certainty',
        'brand_id',
        'message',
        'file',
        'line',
        'explanation',
        'recommendation',
      ]);
      expect(finding['fails_policy'], isTrue);
      expect('${cli.err}', isEmpty);
    });

    test('quiet hides passes; verbose adds explanations', () async {
      final project = _project(broken: true);
      final quiet = CliHarness(project.root);
      await quiet.run(['check', '--quiet', '--strict']);
      expect('${quiet.out}', isNot(contains('✓')));
      expect('${quiet.out}', contains('brand_asset_leakage'));
      final verbose = CliHarness(project.root);
      await verbose.run(['check', '--verbose']);
      expect('${verbose.out}', contains('certainty: definite'));
      expect('${verbose.out}', contains('why: '));
    });

    test('--color forces ANSI codes', () async {
      final cli = CliHarness(_project().root);
      await cli.run(['check', '--color']);
      expect('${cli.out}', contains('\x1B[32m'));
    });

    test('runs from a subdirectory of the project', () async {
      final project = _project()..file('lib/src/a.dart', '');
      final cli = CliHarness(p.join(project.root, 'lib', 'src'));
      expect(await cli.run(['check']), 0);
    });

    test('non-Flutter directories exit 2 with guidance', () async {
      final project = ProjectBuilder(flutter: false);
      final cli = CliHarness(project.root);
      expect(await cli.run(['check']), 2);
      expect('${cli.err}', contains('without a Flutter dependency'));
      expect('${cli.err}', contains('--project'));
    });

    test('configuration errors exit 2 and are reported in JSON', () async {
      final project = ProjectBuilder()
        ..config('version: 1\nbrands:\n  - id: a\n  - id: a\n');
      final cli = CliHarness(project.root);
      expect(await cli.run(['check', '--format', 'json']), 2);
      final json = jsonDecode('${cli.out}') as Map<String, Object?>;
      expect(json['result'], 'error');
      final details = (json['error'] as Map)['details'] as List;
      expect((details.single as Map)['line'], 4);
      expect('${cli.err}', contains('Duplicate brand ID'));
    });

    test(
      '--config and --project are resolved from the working directory',
      () async {
        final project = _project()
          ..file('ci/bg.yaml', _project().read('.brandguard.yaml'));
        final cli = CliHarness(project.root);
        expect(
          await cli.run(['check', '--config', 'ci/bg.yaml', '--project', '.']),
          0,
        );
      },
    );
  });

  group('init', () {
    test('creates a loadable config with detected brands and locales', () async {
      final project = ProjectBuilder()
        ..binary('assets/brands/acme/app_icon.png')
        ..binary('assets/brands/acme/logo.png')
        ..file('lib/l10n/app_en.arb', '{}')
        ..file('lib/l10n/app_fr.arb', '{}')
        ..file('android/app/build.gradle.kts', '''
android { productFlavors {
  create("acme") { applicationId = "com.example.acme"; resValue("string", "app_name", "Acme Retail") }
  create("nova") { applicationId = "com.example.nova"; manifestPlaceholders["label"] = "Nova Store" }
} }
''')
        ..file(
          'android/app/src/main/AndroidManifest.xml',
          '<manifest><application android:label="@string/app_name"/></manifest>',
        )
        ..file(
          'android/app/src/nova/AndroidManifest.xml',
          '<manifest><application android:label="\${label}"/></manifest>',
        );
      final cli = CliHarness(project.root);
      expect(await cli.run(['init', '--no-input']), 0);
      expect('${cli.out}', contains('Will create:'));
      expect('${cli.out}', contains('Android product flavors: acme, nova'));
      final yaml = project.read('.brandguard.yaml');
      expect(yaml, contains('application_id: com.example.acme'));
      expect(yaml, contains("app_name: 'Acme Retail'"));
      // Resolved through the flavor manifest's placeholder.
      expect(yaml, contains("app_name: 'Nova Store'"));
      expect(yaml, contains('launcher_icon: assets/brands/acme/app_icon.png'));
      expect(yaml, contains('required_locales: [en, fr]'));
      final config = BrandGuard().loadConfig(projectDirectory: project.root);
      expect(config.brands.map((b) => b.id), ['acme', 'nova']);
    });

    test('never overwrites without approval in non-interactive mode', () async {
      final project = ProjectBuilder()
        ..config('version: 1 # mine\nbrands: []\n');
      final cli = CliHarness(project.root);
      expect(await cli.run(['init', '--no-input']), 2);
      expect('${cli.err}', contains('already exists'));
      expect(project.read('.brandguard.yaml'), contains('# mine'));
    });

    test('asks before overwriting in interactive mode', () async {
      final project = ProjectBuilder()
        ..config('version: 1 # mine\nbrands: []\n');
      final declined = CliHarness(
        project.root,
        interactive: true,
        input: ['n'],
      );
      expect(await declined.run(['init']), 0);
      expect(project.read('.brandguard.yaml'), contains('# mine'));

      final accepted = CliHarness(
        project.root,
        interactive: true,
        input: ['y'],
      );
      expect(await accepted.run(['init']), 0);
      expect(project.read('.brandguard.yaml'), contains('Generated by'));
    });

    test('treats an existing brandguard.yaml as the configuration', () async {
      final project = ProjectBuilder()
        ..file('brandguard.yaml', 'version: 1 # mine\nbrands: []\n');
      final cli = CliHarness(project.root);
      expect(await cli.run(['init', '--no-input']), 2);
      expect(project.read('brandguard.yaml'), contains('# mine'));
      expect(project.exists('.brandguard.yaml'), isFalse);
    });

    test('--force overwrites explicitly', () async {
      final project = ProjectBuilder()..config('# mine\n');
      final cli = CliHarness(project.root);
      expect(await cli.run(['init', '--force', '--no-input']), 0);
      expect(project.read('.brandguard.yaml'), contains('Generated by'));
    });

    test('generates an example brand when nothing is detected', () async {
      final project = ProjectBuilder();
      expect(await CliHarness(project.root).run(['init']), 0);
      final config = BrandGuard().loadConfig(projectDirectory: project.root);
      expect(config.brands.single.id, 'my_brand');
      expect(config.localization.enabled, isFalse);
    });

    test('fails with guidance outside a Flutter project', () async {
      final project = ProjectBuilder(flutter: false);
      final cli = CliHarness(project.root);
      expect(await cli.run(['init']), 2);
      expect('${cli.err}', contains('must run inside a Flutter project'));
      expect(project.exists('.brandguard.yaml'), isFalse);
    });

    test('--config writes to a custom path', () async {
      final project = ProjectBuilder();
      final cli = CliHarness(project.root);
      expect(await cli.run(['init', '--config', 'tool/bg.yaml']), 0);
      expect(project.exists('tool/bg.yaml'), isTrue);
      expect(project.exists('.brandguard.yaml'), isFalse);
    });
  });
}
