import '../config/config_model.dart';
import '../discovery/project_files.dart';
import '../models/finding.dart';
import '../models/severity.dart';
import '../validators/android_project.dart';
import '../validators/arb_analyzer.dart';
import '../validators/ios_project.dart';
import '../validators/pubspec_assets.dart';

/// A validation rule.
///
/// Implement this interface to add a custom check, then pass the rule to
/// `BrandGuard(rules: [...BrandGuard.defaultRules(), MyRule()])`. Rules must
/// be read-only: they inspect [RuleContext] and report through
/// [RuleReporter], and never modify project files.
abstract class Rule {
  /// Allows subclasses to be const.
  const Rule();

  /// Stable, snake_case identifier used in configuration and output.
  String get id;

  /// One-line description shown by `brandguard rules`.
  String get description;

  /// Severity of the rule's primary findings unless configured otherwise.
  Severity get defaultSeverity;

  /// Runs the rule.
  void run(RuleContext context, RuleReporter reporter);
}

/// Shared, cached state available to every rule during one validation run.
class RuleContext {
  /// Creates a context.
  RuleContext({
    required this.config,
    required this.selectedBrands,
    required this.files,
  });

  /// The loaded configuration.
  final BrandGuardConfig config;

  /// Brands selected for this run, in configuration order.
  final List<BrandConfig> selectedBrands;

  /// Cached, read-only access to project files.
  final ProjectFiles files;

  final Map<Object, Object?> _cache = {};

  /// Returns the cached value for [key], computing it with [create] once.
  T cached<T>(Object key, T Function() create) {
    if (_cache.containsKey(key)) return _cache[key] as T;
    final value = create();
    _cache[key] = value;
    return value;
  }

  /// Whether more than one brand is configured.
  bool get isMultiBrand => config.brands.length > 1;

  /// Parsed `pubspec.yaml` asset declarations, or `null`.
  PubspecAssets? get pubspecAssets => cached(#pubspecAssets, () {
    final text = files.readText('pubspec.yaml');
    return text == null ? null : PubspecAssets.parse(text);
  });

  /// The Android app module, or `null` when absent or disabled.
  AndroidProject? get android => cached(
    #android,
    () => config.platforms.android.enabled
        ? AndroidProject.load(files, config.platforms.android)
        : null,
  );

  /// The iOS Runner project, or `null` when absent or disabled.
  IosProject? get ios => cached(
    #ios,
    () => config.platforms.ios.enabled
        ? IosProject.load(files, config.platforms.ios)
        : null,
  );

  /// Shared ARB analyzer.
  ArbAnalyzer get arb =>
      cached(#arb, () => ArbAnalyzer(files, config.localization));
}

/// Collects findings for one rule, applying enablement and severity
/// configuration.
class RuleReporter {
  /// Creates a reporter for [rule].
  RuleReporter(this.rule, this.context);

  /// The rule being run.
  final Rule rule;

  /// The run's context.
  final RuleContext context;

  final List<Finding> _findings = [];
  final List<PassedCheck> _passes = [];

  /// Findings reported so far.
  List<Finding> get findings => List.unmodifiable(_findings);

  /// Passed checks reported so far.
  List<PassedCheck> get passes => List.unmodifiable(_passes);

  RuleSettings? _brandSettings(BrandConfig? brand) => brand?.rules[rule.id];

  /// Whether the rule is enabled for [brand] (`null` = project-wide).
  ///
  /// Precedence: brand `rules:` > top-level `rules:` > enabled.
  bool isEnabledFor(BrandConfig? brand) =>
      _brandSettings(brand)?.enabled ??
      context.config.rules[rule.id]?.enabled ??
      true;

  /// The configured severity for [brand].
  ///
  /// Precedence: brand `rules:` > top-level `rules:` > [Rule.defaultSeverity].
  Severity severityFor(BrandConfig? brand) =>
      _brandSettings(brand)?.severity ??
      context.config.rules[rule.id]?.severity ??
      rule.defaultSeverity;

  /// Brands selected for this run on which the rule is enabled.
  List<BrandConfig> get enabledBrands =>
      context.selectedBrands.where(isEnabledFor).toList();

  /// Reports a primary finding at the configured severity.
  void fail({
    required String message,
    BrandConfig? brand,
    String? file,
    int? line,
    String? explanation,
    String? recommendation,
    Certainty certainty = Certainty.definite,
  }) => report(
    severityFor(brand),
    message: message,
    brand: brand,
    file: file,
    line: line,
    explanation: explanation,
    recommendation: recommendation,
    certainty: certainty,
  );

  /// Reports a finding at [severity], capped at the configured severity so
  /// a rule configured as `info` never produces warnings.
  void report(
    Severity severity, {
    required String message,
    BrandConfig? brand,
    String? file,
    int? line,
    String? explanation,
    String? recommendation,
    Certainty certainty = Certainty.definite,
  }) {
    if (!isEnabledFor(brand)) return;
    _findings.add(
      Finding(
        ruleId: rule.id,
        severity: severity.capAt(severityFor(brand)),
        message: message,
        brandId: brand?.id,
        file: file,
        line: line,
        explanation: explanation,
        recommendation: recommendation,
        certainty: certainty,
      ),
    );
  }

  /// Records a check that passed.
  void pass(String message, {BrandConfig? brand}) {
    if (!isEnabledFor(brand)) return;
    _passes.add(
      PassedCheck(ruleId: rule.id, message: message, brandId: brand?.id),
    );
  }
}
