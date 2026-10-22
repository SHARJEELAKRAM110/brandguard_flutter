import 'finding.dart';
import 'severity.dart';

/// Identifies a brand that was validated.
class CheckedBrand {
  /// Creates a brand reference.
  const CheckedBrand({required this.id, this.name});

  /// The brand ID from the configuration.
  final String id;

  /// The human-readable brand name, when configured.
  final String? name;

  /// [name] when set, otherwise [id].
  String get displayName => name ?? id;
}

/// The outcome of validating a project.
class ValidationResult {
  /// Creates a validation result. Findings are kept in the given order.
  ValidationResult({
    required this.projectName,
    required this.projectRoot,
    required this.configPath,
    required List<CheckedBrand> brands,
    required List<Finding> findings,
    required List<PassedCheck> passes,
    required this.strict,
  }) : brands = List.unmodifiable(brands),
       findings = List.unmodifiable(findings),
       passes = List.unmodifiable(passes);

  /// The project name from the configuration or `pubspec.yaml`.
  final String projectName;

  /// The absolute project root.
  final String projectRoot;

  /// The absolute path of the configuration file.
  final String configPath;

  /// Brands that were validated, in configuration order.
  final List<CheckedBrand> brands;

  /// All findings, sorted deterministically.
  final List<Finding> findings;

  /// Checks that passed.
  final List<PassedCheck> passes;

  /// Whether warnings fail the policy.
  final bool strict;

  /// Whether [finding] causes validation to fail under the current policy.
  bool failsPolicy(Finding finding) =>
      finding.severity == Severity.error ||
      (strict && finding.severity == Severity.warning);

  /// Number of findings with [severity].
  int count(Severity severity) =>
      findings.where((f) => f.severity == severity).length;

  /// Number of findings that fail the policy.
  int get failingCount => findings.where(failsPolicy).length;

  /// Whether validation passed.
  bool get passed => failingCount == 0;

  /// The process exit code: `0` when passed, `1` otherwise.
  int get exitCode => passed ? 0 : 1;

  /// Findings for [brandId] (`null` selects project-wide findings).
  List<Finding> findingsFor(String? brandId) =>
      findings.where((f) => f.brandId == brandId).toList();

  /// Passed checks for [brandId] (`null` selects project-wide checks).
  List<PassedCheck> passesFor(String? brandId) =>
      passes.where((p) => p.brandId == brandId).toList();
}
