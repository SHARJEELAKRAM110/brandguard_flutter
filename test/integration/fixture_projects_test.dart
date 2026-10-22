import 'dart:convert';
import 'dart:io';

import 'package:brandguard_flutter/brandguard_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/project_builder.dart';

/// Copies a static fixture into a temporary directory so tests never touch
/// the checked-in files.
String copyFixture(String name) {
  final source = Directory(p.join('test', 'fixtures', name));
  final target = Directory.systemTemp.createTempSync('brandguard_$name');
  addTearDown(() => target.deleteSync(recursive: true));
  for (final entity in source.listSync(recursive: true)) {
    if (entity is! File) continue;
    final relative = p.relative(entity.path, from: source.path);
    final destination = File(p.join(target.path, relative));
    destination.parent.createSync(recursive: true);
    entity.copySync(destination.path);
  }
  return target.path;
}

void main() {
  group('clean fixture', () {
    test('passes with zero findings and full coverage of checks', () {
      final root = copyFixture('clean_project');
      final guard = BrandGuard();
      final result = guard.validate(guard.loadConfig(projectDirectory: root));
      expect(result.findings, isEmpty, reason: result.findings.join('\n'));
      expect(result.exitCode, 0);
      for (final brand in ['alpha', 'beta']) {
        final rules = result.passesFor(brand).map((p) => p.ruleId).toSet();
        expect(
          rules,
          containsAll([
            'missing_brand_configuration',
            'duplicate_application_id',
            'missing_assets',
            'undeclared_assets',
            'brand_asset_leakage',
            'application_identifier_mismatch',
            'app_name_mismatch',
            'missing_translations',
            'invalid_arb',
            'arb_placeholder_mismatch',
            'forbidden_environment_url',
          ]),
        );
      }
    });
  });

  group('broken fixture', () {
    test('reports exactly the intentional mistakes', () {
      final root = copyFixture('broken_project');
      final guard = BrandGuard();
      final result = guard.validate(guard.loadConfig(projectDirectory: root));
      final summary = result.findings
          .map(
            (f) => '${f.brandId}|${f.ruleId}|${f.severity.name}|${f.message}',
          )
          .toList();
      expect(summary, [
        'alpha|brand_asset_leakage|warning|Brand `alpha` `launcher_icon` is '
            "byte-identical to `beta`'s asset assets/brands/beta/icon.png",
        'alpha|missing_translations|error|Missing translation `logout` in locale `de`.',
        'beta|missing_assets|error|Missing asset `logo`: assets/brands/beta/logo.png',
        'beta|brand_asset_leakage|warning|Brand `beta` `launcher_icon` is '
            "byte-identical to `alpha`'s asset assets/brands/alpha/icon.png",
        'beta|application_identifier_mismatch|error|iOS bundle ID mismatch: '
            'expected `com.fixture.beta`, found `com.fixture.alpha`.',
        'beta|app_name_mismatch|error|Android app name mismatch: expected '
            '`Beta Pay`, found `Alpha Bank`.',
        'beta|missing_translations|error|Missing translation `logout` in locale `de`.',
        'beta|forbidden_environment_url|error|Production brand uses URL '
            'https://staging.beta-pay.example/v1 (matches forbidden pattern `staging`).',
      ]);
      final ios = result.findings.firstWhere(
        (f) => f.ruleId == 'application_identifier_mismatch',
      );
      expect(ios.recommendation, contains('ios/Flutter/beta.xcconfig'));
      expect(result.exitCode, 1);
    });

    test('validation is deterministic and read-only', () {
      final root = copyFixture('broken_project');
      String snapshot() {
        final files =
            Directory(root)
                .listSync(recursive: true)
                .whereType<File>()
                .map(
                  (f) =>
                      '${p.relative(f.path, from: root)}:${f.lengthSync()}:'
                      '${f.lastModifiedSync().millisecondsSinceEpoch}',
                )
                .toList()
              ..sort();
        return files.join('\n');
      }

      final before = snapshot();
      final guard = BrandGuard();
      final config = guard.loadConfig(projectDirectory: root);
      final first = const JsonReporter().render(guard.validate(config));
      final second = const JsonReporter().render(guard.validate(config));
      expect(second, first);
      expect(snapshot(), before);
    });
  });

  group('example project', () {
    test('acme passes and nova reports each documented mistake', () {
      final guard = BrandGuard();
      final config = guard.loadConfig(
        projectDirectory: p.join('example', 'sample_white_label_project'),
      );
      final result = guard.validate(config);
      expect(result.findingsFor('acme').where(result.failsPolicy), isEmpty);
      final nova = result.findingsFor('nova').map((f) => f.ruleId).toSet();
      expect(
        nova,
        containsAll([
          'missing_assets',
          'brand_asset_leakage',
          'application_identifier_mismatch',
          'app_name_mismatch',
          'missing_translations',
          'arb_placeholder_mismatch',
          'forbidden_environment_url',
        ]),
      );
      // The staging config is never scanned for the production brand.
      expect(
        result.findings.where((f) => f.file == 'config/acme/staging.json'),
        isEmpty,
      );
    });
  });

  group('compiled CLI process', () {
    Future<ProcessResult> runCli(List<String> args, {String? cwd}) =>
        Process.run(Platform.resolvedExecutable, [
          'run',
          p.absolute('bin', 'brandguard.dart'),
          ...args,
        ], workingDirectory: cwd);

    test('exit codes 0, 1 and 2 reach the operating system', () async {
      final clean = copyFixture('clean_project');
      final broken = copyFixture('broken_project');
      final passed = await runCli(['check', '--project', clean]);
      final failed = await runCli(['check', '--project', broken]);
      final error = await runCli(['check', '--bogus']);
      expect(passed.exitCode, 0, reason: '${passed.stdout}${passed.stderr}');
      expect(failed.exitCode, 1);
      expect(error.exitCode, 2);
      expect(
        error.stderr,
        contains('Could not find an option named "--bogus"'),
      );
    });

    test('JSON stdout is parseable and contains no decoration', () async {
      final broken = copyFixture('broken_project');
      final result = await runCli([
        'check',
        '--format',
        'json',
        '--brand',
        'beta',
      ], cwd: p.join(broken, 'lib', 'l10n'));
      expect(result.exitCode, 1);
      final json = jsonDecode(result.stdout as String) as Map<String, Object?>;
      expect(json['result'], 'failed');
      expect((json['summary'] as Map)['brands_checked'], 1);
      expect((result.stderr as String).trim(), isEmpty);
    });
  });

  test('ProjectBuilder sanity: builder writes Flutter pubspecs', () {
    final project = ProjectBuilder();
    expect(project.read('pubspec.yaml'), contains('sdk: flutter'));
  });
}
