import 'dart:io';

import 'package:path/path.dart' as p;

import 'config/config_loader.dart';
import 'config/config_model.dart';
import 'discovery/project_files.dart';
import 'discovery/project_locator.dart';
import 'models/finding.dart';
import 'models/validation_result.dart';
import 'rules/asset_rules.dart';
import 'rules/brand_rules.dart';
import 'rules/environment_rules.dart';
import 'rules/localization_rules.dart';
import 'rules/platform_rules.dart';
import 'rules/rule.dart';

/// Thrown when requested brands are not configured.
class UnknownBrandException implements Exception {
  /// Creates the exception.
  UnknownBrandException(this.unknown, this.available);

  /// Requested IDs that do not exist.
  final List<String> unknown;

  /// Configured brand IDs.
  final List<String> available;

  @override
  String toString() =>
      'Unknown brand${unknown.length == 1 ? '' : 's'}: ${unknown.join(', ')}. '
      'Configured brands: ${available.join(', ')}.';
}

/// Thrown when a rule fails with an unexpected error.
class RuleExecutionException implements Exception {
  /// Creates the exception.
  RuleExecutionException(this.ruleId, this.error, this.stackTrace);

  /// The failing rule.
  final String ruleId;

  /// The underlying error.
  final Object error;

  /// Where it happened.
  final StackTrace stackTrace;

  @override
  String toString() => 'Rule `$ruleId` failed: $error';
}

/// Locates a project, loads its configuration and runs validation rules.
///
/// ```dart
/// final guard = BrandGuard();
/// final config = guard.loadConfig(projectDirectory: '.');
/// final result = guard.validate(config, brandIds: ['acme']);
/// print(result.passed);
/// ```
class BrandGuard {
  /// Creates a validator with [rules] (defaults to [defaultRules]).
  BrandGuard({List<Rule>? rules})
    : rules = List.unmodifiable(rules ?? defaultRules()) {
    final ids = <String>{};
    for (final rule in this.rules) {
      if (!ids.add(rule.id)) {
        throw ArgumentError('Duplicate rule ID `${rule.id}`.');
      }
    }
  }

  /// The rules run by [validate], in reporting order.
  final List<Rule> rules;

  /// The built-in rules.
  static List<Rule> defaultRules() => const [
    MissingBrandConfigurationRule(),
    DuplicateApplicationIdRule(),
    MissingAssetsRule(),
    UndeclaredAssetsRule(),
    BrandAssetLeakageRule(),
    ApplicationIdentifierRule(),
    AppNameRule(),
    MissingTranslationsRule(),
    InvalidArbRule(),
    ArbPlaceholderMismatchRule(),
    ForbiddenEnvironmentUrlRule(),
    SuspiciousEnvironmentUrlRule(),
  ];

  /// Finds the project and loads its configuration.
  ///
  /// * [configPath] — explicit configuration file. Its `project.root` is
  ///   resolved relative to the file unless [projectDirectory] is given.
  /// * [projectDirectory] — project root, or a directory inside it.
  /// * [workingDirectory] — where discovery starts when neither is given.
  ///
  /// Throws [ProjectNotFoundException] or [ConfigException].
  BrandGuardConfig loadConfig({
    String? configPath,
    String? projectDirectory,
    String? workingDirectory,
  }) {
    const locator = ProjectLocator();
    final loader = ConfigLoader(knownRuleIds: rules.map((r) => r.id));
    if (configPath != null) {
      final projectRoot = projectDirectory == null
          ? null
          : locator.locate(projectDirectory).root;
      final config = loader.load(configPath, projectRootOverride: projectRoot);
      if (projectRoot == null) locator.readAt(config.projectRoot);
      return config;
    }
    final project = locator.locate(
      projectDirectory ?? workingDirectory ?? Directory.current.path,
    );
    return loader.load(
      configPathFor(project.root),
      projectRootOverride: project.root,
    );
  }

  /// The configuration file of the project at [projectRoot]:
  /// `.brandguard.yaml`, or `brandguard.yaml` when only that exists.
  ///
  /// Throws [ConfigException] when both exist.
  static String configPathFor(String projectRoot) {
    final dotted = p.join(projectRoot, defaultConfigFileName);
    final plain = p.join(projectRoot, alternateConfigFileName);
    final hasDotted = File(dotted).existsSync();
    final hasPlain = File(plain).existsSync();
    if (hasDotted && hasPlain) {
      throw ConfigException(dotted, [
        const ConfigIssue(
          'Both $defaultConfigFileName and $alternateConfigFileName exist. '
          'Remove one so the configuration is unambiguous.',
        ),
      ]);
    }
    return hasPlain ? plain : dotted;
  }

  /// Validates [config].
  ///
  /// [brandIds] limits validation to those brands (`null` = all). Shared
  /// configuration is still consulted, e.g. other brands' asset roots.
  /// [strict] makes warnings fail; `policy.strict` in the configuration has
  /// the same effect.
  ///
  /// Throws [UnknownBrandException] or [RuleExecutionException].
  ValidationResult validate(
    BrandGuardConfig config, {
    List<String>? brandIds,
    bool strict = false,
  }) {
    final selected = _select(config, brandIds);
    final context = RuleContext(
      config: config,
      selectedBrands: selected,
      files: ProjectFiles(config.projectRoot, excludes: config.excludes),
    );
    final findings = <Finding>[];
    final passes = <PassedCheck>[];
    for (final rule in rules) {
      final reporter = RuleReporter(rule, context);
      try {
        rule.run(context, reporter);
      } on Exception catch (error, stackTrace) {
        throw RuleExecutionException(rule.id, error, stackTrace);
      } on Error catch (error, stackTrace) {
        throw RuleExecutionException(rule.id, error, stackTrace);
      }
      findings.addAll(reporter.findings);
      passes.addAll(reporter.passes);
    }

    final brandOrder = {
      for (var i = 0; i < config.brands.length; i++) config.brands[i].id: i,
    };
    final ruleOrder = {for (var i = 0; i < rules.length; i++) rules[i].id: i};
    int compare(Finding a, Finding b) {
      final byBrand = (brandOrder[a.brandId] ?? -1).compareTo(
        brandOrder[b.brandId] ?? -1,
      );
      if (byBrand != 0) return byBrand;
      final byRule = ruleOrder[a.ruleId]!.compareTo(ruleOrder[b.ruleId]!);
      if (byRule != 0) return byRule;
      final byFile = (a.file ?? '').compareTo(b.file ?? '');
      if (byFile != 0) return byFile;
      final byLine = (a.line ?? 0).compareTo(b.line ?? 0);
      if (byLine != 0) return byLine;
      return a.message.compareTo(b.message);
    }

    findings.sort(compare);
    return ValidationResult(
      projectName:
          config.projectName ??
          _pubspecName(context.files) ??
          p.basename(config.projectRoot),
      projectRoot: config.projectRoot,
      configPath: config.configPath,
      brands: [
        for (final brand in selected)
          CheckedBrand(id: brand.id, name: brand.name),
      ],
      findings: findings,
      passes: passes,
      strict: strict || config.strict,
    );
  }

  List<BrandConfig> _select(BrandGuardConfig config, List<String>? ids) {
    if (ids == null || ids.isEmpty) return config.brands;
    final available = config.brands.map((b) => b.id).toList();
    final unknown = ids.where((id) => !available.contains(id)).toList();
    if (unknown.isNotEmpty) throw UnknownBrandException(unknown, available);
    return config.brands.where((b) => ids.contains(b.id)).toList();
  }

  static String? _pubspecName(ProjectFiles files) {
    final text = files.readText('pubspec.yaml');
    if (text == null) return null;
    return RegExp(r'^name:\s*([\w]+)', multiLine: true).firstMatch(text)?[1];
  }
}
