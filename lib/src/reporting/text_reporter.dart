import '../models/finding.dart';
import '../models/severity.dart';
import '../models/validation_result.dart';

/// How much detail [TextReporter] prints.
enum Verbosity {
  /// Only failing findings and the summary.
  quiet,

  /// Passed checks, findings with recommendations, and the summary.
  normal,

  /// Everything, including explanations, certainty and info findings'
  /// details.
  verbose,
}

/// Renders a [ValidationResult] for terminals and CI logs.
///
/// Severity is always spelled out (`ERROR`, `WARN`, `INFO`), so the output
/// does not depend on color.
class TextReporter {
  /// Creates a text reporter.
  const TextReporter({
    this.color = false,
    this.unicode = true,
    this.verbosity = Verbosity.normal,
  });

  /// Whether to emit ANSI color codes.
  final bool color;

  /// Whether to use Unicode symbols (✓ ✗ ⚠ ℹ) instead of ASCII.
  final bool unicode;

  /// Detail level.
  final Verbosity verbosity;

  /// Renders the full report.
  String render(ValidationResult result) {
    final out = StringBuffer();
    if (verbosity != Verbosity.quiet) {
      out
        ..writeln(_bold('BrandGuard — White-Label Validation'))
        ..writeln('Project: ${result.projectName}')
        ..writeln('Brands checked: ${result.brands.length}')
        ..writeln(result.strict ? 'Mode: strict (warnings fail)' : '')
        ..writeln();
    }

    final shared = result.findingsFor(null);
    if (_visible(result, shared).isNotEmpty) {
      out.writeln(_bold('PROJECT'));
      _section(out, result, shared, const []);
      out.writeln();
    }

    for (final brand in result.brands) {
      final findings = result.findingsFor(brand.id);
      final passes = result.passesFor(brand.id);
      if (verbosity == Verbosity.quiet && !findings.any(result.failsPolicy)) {
        continue;
      }
      out.writeln(_bold('${brand.displayName.toUpperCase()} (${brand.id})'));
      _section(out, result, findings, passes);
      out.writeln();
    }

    final errors = result.count(Severity.error);
    final warnings = result.count(Severity.warning);
    final infos = result.count(Severity.info);
    out
      ..writeln('Summary:')
      ..writeln('  ${_plural(errors, 'error')}')
      ..writeln('  ${_plural(warnings, 'warning')}')
      ..writeln('  ${_plural(infos, 'info')}')
      ..writeln('  ${_plural(result.brands.length, 'brand')} checked')
      ..writeln(
        'Result: ${result.passed ? _paint('PASSED', _green) : _paint('FAILED', _red)}'
        '${result.passed ? '' : ' (${_plural(result.failingCount, 'failing finding')})'}',
      );
    return out.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }

  List<Finding> _visible(ValidationResult result, List<Finding> findings) =>
      verbosity == Verbosity.quiet
      ? findings.where(result.failsPolicy).toList()
      : findings;

  void _section(
    StringBuffer out,
    ValidationResult result,
    List<Finding> findings,
    List<PassedCheck> passes,
  ) {
    if (verbosity != Verbosity.quiet) {
      for (final pass in passes) {
        out.writeln(
          '  ${_paint(unicode ? '✓' : '[ok]', _green)} ${pass.message}',
        );
      }
    }
    for (final finding in _visible(result, findings)) {
      final (symbol, label, colorCode) = switch (finding.severity) {
        Severity.error => (unicode ? '✗' : '[x]', 'ERROR', _red),
        Severity.warning => (unicode ? '⚠' : '[!]', 'WARN ', _yellow),
        Severity.info => (unicode ? 'ℹ' : '[i]', 'INFO ', _cyan),
      };
      final failing =
          result.failsPolicy(finding) && finding.severity == Severity.warning
          ? ' (fails in strict mode)'
          : '';
      out.writeln(
        '  ${_paint('$symbol $label', colorCode)} ${finding.message}'
        '${_dim(' [${finding.ruleId}]')}$failing',
      );
      if (finding.location != null) {
        out.writeln('      at ${finding.location}');
      }
      if (verbosity == Verbosity.verbose) {
        out.writeln('      certainty: ${finding.certainty.name}');
        if (finding.explanation != null) {
          out.writeln('      why: ${finding.explanation}');
        }
      }
      if (finding.recommendation != null &&
          (verbosity == Verbosity.verbose ||
              finding.severity != Severity.info)) {
        out.writeln('      fix: ${finding.recommendation}');
      }
    }
  }

  static String _plural(int count, String noun) =>
      '$count $noun${count == 1 ? '' : 's'}';

  static const _red = '31';
  static const _green = '32';
  static const _yellow = '33';
  static const _cyan = '36';

  String _paint(String text, String code) =>
      color ? '\x1B[${code}m$text\x1B[0m' : text;

  String _bold(String text) => color ? '\x1B[1m$text\x1B[0m' : text;

  String _dim(String text) => color ? '\x1B[2m$text\x1B[0m' : text;
}
