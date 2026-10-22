import 'dart:convert';

import '../models/severity.dart';
import '../models/validation_result.dart';
import '../utils/paths.dart';
import '../version.dart';

/// Renders a [ValidationResult] as JSON (schema version
/// [jsonSchemaVersion]). See the README for the schema.
class JsonReporter {
  /// Creates a JSON reporter.
  const JsonReporter();

  /// Returns the report as a JSON-compatible map.
  Map<String, Object?> toMap(ValidationResult result) => {
    'schema_version': jsonSchemaVersion,
    'tool': {'name': 'brandguard', 'version': brandGuardVersion},
    'project': {
      'name': result.projectName,
      'root': toPosix(result.projectRoot),
      'config': toPosix(result.configPath),
    },
    'strict': result.strict,
    'result': result.passed ? 'passed' : 'failed',
    'exit_code': result.exitCode,
    'summary': {
      'brands_checked': result.brands.length,
      'errors': result.count(Severity.error),
      'warnings': result.count(Severity.warning),
      'infos': result.count(Severity.info),
      'failing': result.failingCount,
    },
    'brands': [
      for (final brand in result.brands)
        {
          'id': brand.id,
          'name': brand.name,
          'result': result.findingsFor(brand.id).any(result.failsPolicy)
              ? 'failed'
              : 'passed',
          'errors': _count(result, brand.id, Severity.error),
          'warnings': _count(result, brand.id, Severity.warning),
          'infos': _count(result, brand.id, Severity.info),
        },
    ],
    'findings': [
      for (final finding in result.findings)
        finding.toJson(failsPolicy: result.failsPolicy(finding)),
    ],
    'passed_checks': [for (final pass in result.passes) pass.toJson()],
  };

  /// Returns the report as indented JSON text.
  String render(ValidationResult result) =>
      const JsonEncoder.withIndent('  ').convert(toMap(result));

  /// Renders an execution or configuration error (exit code 2) as JSON.
  String renderError(
    String message, {
    List<Map<String, Object?>> details = const [],
  }) => const JsonEncoder.withIndent('  ').convert({
    'schema_version': jsonSchemaVersion,
    'tool': {'name': 'brandguard', 'version': brandGuardVersion},
    'result': 'error',
    'exit_code': 2,
    'error': {'message': message, 'details': details},
  });

  static int _count(ValidationResult result, String id, Severity severity) =>
      result.findingsFor(id).where((f) => f.severity == severity).length;
}
