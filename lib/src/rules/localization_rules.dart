import '../models/severity.dart';
import '../validators/arb_analyzer.dart';
import 'rule.dart';

/// Shared driver for the three ARB rules: analyzes each brand's locales
/// once and reports the issue kinds owned by the calling rule.
void _reportArbIssues(
  RuleContext context,
  RuleReporter reporter,
  Set<ArbIssueKind> kinds, {
  required String explanation,
  required String Function(ArbIssue) recommendation,
  bool reportSetup = false,
}) {
  final localization = context.config.localization;
  if (!localization.enabled) return;
  final base = localization.baseLocale ?? 'en';
  for (final brand in reporter.enabledBrands) {
    final locales = context.config.requiredLocalesOf(brand);
    if (locales.isEmpty) continue;
    final directory = brand.arbDirectory ?? localization.arbDirectory;
    if (directory == null || !context.files.directoryExists(directory)) {
      if (!reportSetup) continue;
      if (directory != null &&
          (localization.arbDirectoryExplicit || brand.arbDirectory != null)) {
        reporter.fail(
          brand: brand,
          message: 'ARB directory `$directory` does not exist.',
          recommendation:
              'Fix `arb_directory`, or set `localization.enabled: false` if '
              'the project does not use ARB files.',
        );
      } else {
        reporter.report(
          Severity.info,
          brand: brand,
          message:
              'No ARB directory found; translations for '
              '${locales.join(', ')} were not checked.',
          certainty: Certainty.unresolved,
          recommendation:
              'Set `localization.arb_directory`, or set '
              '`localization.enabled: false` if the project uses another '
              'localization system.',
        );
      }
      continue;
    }

    var problems = 0;
    for (final locale in {base, ...locales}) {
      final issues = context.arb.analyze(directory, base, locale);
      for (final issue in issues.where((i) => kinds.contains(i.kind))) {
        final severity = issue.maxSeverity == null
            ? reporter.severityFor(brand)
            : issue.maxSeverity!;
        if (severity != Severity.info) problems++;
        reporter.report(
          severity,
          brand: brand,
          message: issue.message,
          file: issue.file,
          line: issue.line,
          explanation: explanation,
          recommendation: recommendation(issue),
        );
      }
    }
    if (problems == 0) {
      reporter.pass(switch (reporter.rule.id) {
        'missing_translations' =>
          'Required locales present (${locales.join(', ')})',
        'invalid_arb' => 'ARB files are valid',
        _ => 'Placeholders match the base locale',
      }, brand: brand);
    }
  }
}

/// Rule E: required locales exist and contain every base-locale key.
class MissingTranslationsRule extends Rule {
  /// Creates the rule.
  const MissingTranslationsRule();

  @override
  String get id => 'missing_translations';

  @override
  String get description =>
      'Each required locale has an ARB file containing every key of the base '
      'locale, with no empty translations.';

  @override
  Severity get defaultSeverity => Severity.error;

  @override
  void run(RuleContext context, RuleReporter reporter) => _reportArbIssues(
    context,
    reporter,
    const {
      ArbIssueKind.missingFile,
      ArbIssueKind.missingKey,
      ArbIssueKind.emptyValue,
      ArbIssueKind.extraKey,
    },
    reportSetup: true,
    explanation:
        'Missing or empty translations fall back to the base locale or show '
        'blank text for users of this brand.',
    recommendation: (issue) => switch (issue.kind) {
      ArbIssueKind.missingFile =>
        'Create ${issue.file} or remove `${issue.locale}` from the brand\'s '
            'required_locales.',
      ArbIssueKind.missingKey => 'Add "${issue.key}" to ${issue.file}.',
      ArbIssueKind.emptyValue =>
        'Translate "${issue.key}" in ${issue.file}, or set '
            '`localization.allow_empty_translations: true`.',
      _ => 'Remove "${issue.key}" or add it to the base locale.',
    },
  );
}

/// Rule E: ARB files are valid JSON objects with string messages.
class InvalidArbRule extends Rule {
  /// Creates the rule.
  const InvalidArbRule();

  @override
  String get id => 'invalid_arb';

  @override
  String get description =>
      'ARB files are valid JSON objects, messages are strings, and @@locale '
      'matches the file name.';

  @override
  Severity get defaultSeverity => Severity.error;

  @override
  void run(RuleContext context, RuleReporter reporter) => _reportArbIssues(
    context,
    reporter,
    const {
      ArbIssueKind.invalidJson,
      ArbIssueKind.invalidStructure,
      ArbIssueKind.localeMismatch,
    },
    explanation:
        'flutter gen-l10n fails on malformed ARB files, which breaks the '
        'build for every brand.',
    recommendation: (issue) =>
        'Fix ${issue.file}'
        '${issue.line == null ? '' : ' around line ${issue.line}'}.',
  );
}

/// Rule E: placeholders, plural and select usage agree across locales.
class ArbPlaceholderMismatchRule extends Rule {
  /// Creates the rule.
  const ArbPlaceholderMismatchRule();

  @override
  String get id => 'arb_placeholder_mismatch';

  @override
  String get description =>
      'Translations use the same placeholders, placeholder types and '
      'plural/select structure as the base locale.';

  @override
  Severity get defaultSeverity => Severity.error;

  @override
  void run(RuleContext context, RuleReporter reporter) => _reportArbIssues(
    context,
    reporter,
    const {ArbIssueKind.placeholderMismatch},
    explanation:
        'Placeholder mismatches either fail code generation or render the '
        'wrong value at runtime.',
    recommendation: (issue) =>
        'Align "${issue.key}" in ${issue.file} with the base locale.',
  );
}
