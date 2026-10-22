import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:brandguard_flutter/brandguard_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Builds throw-away Flutter projects in a temporary directory.
class ProjectBuilder {
  ProjectBuilder._(this.root);

  /// Creates a project and registers it for deletion after the test.
  factory ProjectBuilder({String name = 'demo_app', bool flutter = true}) {
    final dir = Directory.systemTemp.createTempSync('brandguard_test_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final builder = ProjectBuilder._(dir.path);
    builder.file(
      'pubspec.yaml',
      flutter
          ? 'name: $name\n'
                'environment:\n  sdk: ^3.8.0\n'
                'dependencies:\n  flutter:\n    sdk: flutter\n'
          : 'name: $name\nenvironment:\n  sdk: ^3.8.0\n',
    );
    return builder;
  }

  /// Absolute project root.
  final String root;

  /// Writes a text file.
  ProjectBuilder file(String path, String content) {
    final file = File(p.join(root, path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return this;
  }

  /// Writes a binary file filled with [seed]-derived bytes.
  ProjectBuilder binary(String path, {int seed = 1, int length = 64}) {
    final file = File(p.join(root, path));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(
      Uint8List.fromList(List.generate(length, (i) => (i * seed + seed) % 256)),
    );
    return this;
  }

  /// Writes a JSON file.
  ProjectBuilder json(String path, Object value) =>
      file(path, const JsonEncoder.withIndent('  ').convert(value));

  /// Overwrites `pubspec.yaml` with Flutter assets.
  ProjectBuilder pubspecAssets(List<String> assets, {String extra = ''}) =>
      file(
        'pubspec.yaml',
        'name: demo_app\n'
            'environment:\n  sdk: ^3.8.0\n'
            'dependencies:\n  flutter:\n    sdk: flutter\n'
            'flutter:\n  assets:\n'
            '${assets.map((a) => '    - $a\n').join()}$extra',
      );

  /// Writes `.brandguard.yaml`.
  ProjectBuilder config(String yaml) => file('.brandguard.yaml', yaml);

  /// Whether [path] exists.
  bool exists(String path) =>
      FileSystemEntity.typeSync(p.join(root, path)) !=
      FileSystemEntityType.notFound;

  /// Reads a file.
  String read(String path) => File(p.join(root, path)).readAsStringSync();

  /// Loads the configuration and validates.
  ValidationResult validate({List<String>? brands, bool strict = false}) {
    final guard = BrandGuard();
    final config = guard.loadConfig(projectDirectory: root);
    return guard.validate(config, brandIds: brands, strict: strict);
  }
}

/// Minimal valid config for two brands without platform/localization checks.
String twoBrandConfig({
  String brands = '',
  String extra = '',
  String localization = 'localization:\n  enabled: false\n',
}) =>
    '''
version: 1
requirements:
  brand_fields: [name, application_id]
platforms:
  android: {enabled: false}
  ios: {enabled: false}
$localization$extra
brands:
$brands''';

/// Findings for [ruleId] (and optionally [brand]).
List<Finding> findingsOf(
  ValidationResult result,
  String ruleId, {
  String? brand,
}) => result.findings
    .where((f) => f.ruleId == ruleId && (brand == null || f.brandId == brand))
    .toList();

/// In-process CLI with captured output.
class CliHarness {
  CliHarness(
    this.workingDirectory, {
    List<String> input = const [],
    bool interactive = false,
  }) : _input = List.of(input),
       _interactive = interactive;

  final String workingDirectory;
  final List<String> _input;
  final bool _interactive;
  final StringBuffer out = StringBuffer();
  final StringBuffer err = StringBuffer();

  Future<int> run(List<String> args) => BrandGuardCli(
    io: CliIO(
      out: out,
      err: err,
      workingDirectory: workingDirectory,
      interactive: _interactive,
      readLine: () => _input.isEmpty ? null : _input.removeAt(0),
    ),
  ).run(args);
}
