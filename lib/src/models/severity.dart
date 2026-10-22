/// How serious a finding is.
///
/// * [error] findings always fail validation.
/// * [warning] findings fail validation only in strict mode.
/// * [info] findings never fail validation; they point out values that need
///   manual verification or checks that were skipped.
enum Severity {
  /// A definite problem that blocks a release.
  error,

  /// A likely problem, or a definite problem the project chose to tolerate.
  warning,

  /// Context, skipped checks, or values that need manual verification.
  info;

  /// Parses a severity name, returning `null` for unknown values.
  static Severity? tryParse(String value) {
    for (final severity in values) {
      if (severity.name == value) return severity;
    }
    return null;
  }

  /// Higher values are more severe.
  int get rank => switch (this) {
    Severity.error => 2,
    Severity.warning => 1,
    Severity.info => 0,
  };

  /// Returns the less severe of this and [other].
  Severity capAt(Severity other) => rank <= other.rank ? this : other;
}

/// How confident BrandGuard is in a finding.
enum Certainty {
  /// Proven by static inspection of explicitly configured or parsed values.
  definite,

  /// Inferred from naming conventions or similarity; may be a false positive.
  heuristic,

  /// The value could not be resolved statically and must be verified by hand.
  unresolved,
}
