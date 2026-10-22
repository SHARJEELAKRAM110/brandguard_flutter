import 'severity.dart';

/// A single validation result produced by a rule.
class Finding {
  /// Creates a finding.
  const Finding({
    required this.ruleId,
    required this.severity,
    required this.message,
    this.brandId,
    this.file,
    this.line,
    this.explanation,
    this.recommendation,
    this.certainty = Certainty.definite,
  });

  /// The stable identifier of the rule that produced this finding.
  final String ruleId;

  /// The effective severity after configuration was applied.
  final Severity severity;

  /// A short, single-line description of the problem.
  final String message;

  /// The affected brand, or `null` for project-wide findings.
  final String? brandId;

  /// The affected file, relative to the project root with `/` separators.
  final String? file;

  /// The 1-based line number in [file], when known.
  final int? line;

  /// Why this matters.
  final String? explanation;

  /// How to fix it.
  final String? recommendation;

  /// How confident the rule is in this finding.
  final Certainty certainty;

  /// `file:line`, `file`, or `null`.
  String? get location {
    if (file == null) return null;
    return line == null ? file : '$file:$line';
  }

  /// Serializes this finding using the documented JSON schema.
  Map<String, Object?> toJson({required bool failsPolicy}) => {
    'rule_id': ruleId,
    'severity': severity.name,
    'fails_policy': failsPolicy,
    'certainty': certainty.name,
    'brand_id': brandId,
    'message': message,
    'file': file,
    'line': line,
    'explanation': explanation,
    'recommendation': recommendation,
  };

  @override
  String toString() =>
      '[${severity.name}] $ruleId'
      '${brandId == null ? '' : ' ($brandId)'}: $message'
      '${location == null ? '' : ' at $location'}';
}

/// A check that ran and found nothing wrong.
class PassedCheck {
  /// Creates a passed check record.
  const PassedCheck({
    required this.ruleId,
    required this.message,
    this.brandId,
  });

  /// The rule that ran.
  final String ruleId;

  /// What was verified.
  final String message;

  /// The brand that was checked, or `null` for project-wide checks.
  final String? brandId;

  /// Serializes this record using the documented JSON schema.
  Map<String, Object?> toJson() => {
    'rule_id': ruleId,
    'brand_id': brandId,
    'message': message,
  };
}
