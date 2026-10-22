import '../config/config_model.dart';
import '../models/severity.dart';
import 'rule.dart';

/// Rule H: every brand defines the fields the project requires.
class MissingBrandConfigurationRule extends Rule {
  /// Creates the rule.
  const MissingBrandConfigurationRule();

  @override
  String get id => 'missing_brand_configuration';

  @override
  String get description =>
      'Each brand defines the fields listed in requirements.brand_fields '
      'and uses a declared environment.';

  @override
  Severity get defaultSeverity => Severity.error;

  @override
  void run(RuleContext context, RuleReporter reporter) {
    final config = context.config;
    for (final brand in reporter.enabledBrands) {
      var problems = 0;
      for (final field in config.requiredBrandFields) {
        if (_hasField(config, brand, field)) continue;
        problems++;
        reporter.fail(
          brand: brand,
          message: 'Brand `${brand.id}` is missing required field `$field`.',
          file: _configFile(context),
          line: brand.line,
          explanation:
              '`$field` is listed in requirements.brand_fields, so every brand '
              'must define it before release.',
          recommendation: _hint(field, brand),
        );
      }

      final environment = config.environmentOf(brand);
      if (environment != null &&
          config.environments.isNotEmpty &&
          !config.environments.containsKey(environment)) {
        problems++;
        reporter.fail(
          brand: brand,
          message:
              'Brand `${brand.id}` uses environment `$environment`, which is '
              'not declared under `environments`.',
          file: _configFile(context),
          line: brand.line,
          explanation:
              'Undeclared environments have no URL rules, so production '
              'checks would silently be skipped.',
          recommendation:
              'Use one of: ${config.environments.keys.join(', ')}, or declare '
              '`$environment` under `environments`.',
        );
      }
      if (problems == 0) {
        reporter.pass('Brand configuration is complete', brand: brand);
      }
    }
  }

  static bool _hasField(
    BrandGuardConfig config,
    BrandConfig brand,
    String field,
  ) {
    if (field.startsWith('assets.')) {
      final kind = field.substring('assets.'.length);
      return brand.assets[kind]?.isNotEmpty ?? false;
    }
    return switch (field) {
      'name' => brand.name != null,
      'app_name' => brand.appName != null,
      'application_id' => brand.applicationId != null,
      'ios_bundle_id' => brand.iosBundleId != null,
      'flavor' => brand.flavor != null,
      'environment' => config.environmentOf(brand) != null,
      'required_locales' =>
        !config.localization.enabled ||
            config.requiredLocalesOf(brand).isNotEmpty,
      _ => true,
    };
  }

  static String _hint(String field, BrandConfig brand) {
    if (field.startsWith('assets.')) {
      final kind = field.substring('assets.'.length);
      return 'Add `assets: {$kind: <path>}` to brand `${brand.id}`.';
    }
    if (field == 'required_locales') {
      return 'Add `required_locales` to brand `${brand.id}` or set '
          '`localization.required_locales`.';
    }
    if (field == 'environment') {
      return 'Add `environment: production` (or another declared '
          'environment) to brand `${brand.id}`, or set '
          '`defaults.environment`.';
    }
    return 'Add `$field: ...` to brand `${brand.id}`.';
  }
}

/// Rule H (policy): two brands must not ship with the same identifier.
class DuplicateApplicationIdRule extends Rule {
  /// Creates the rule.
  const DuplicateApplicationIdRule();

  @override
  String get id => 'duplicate_application_id';

  @override
  String get description =>
      'No two brands share an Android application ID or iOS bundle ID '
      '(unless policy.allow_duplicate_application_ids is true).';

  @override
  Severity get defaultSeverity => Severity.error;

  @override
  void run(RuleContext context, RuleReporter reporter) {
    final config = context.config;
    if (config.allowDuplicateApplicationIds) return;
    for (final brand in reporter.enabledBrands) {
      var duplicates = 0;
      for (final (label, value, getter) in [
        (
          'application ID',
          brand.applicationId,
          (BrandConfig b) => b.applicationId,
        ),
        (
          'iOS bundle ID',
          brand.iosBundleId,
          (BrandConfig b) => b.expectedIosBundleId,
        ),
      ]) {
        if (value == null) continue;
        final others = config.brands
            .where((b) => b.id != brand.id && getter(b) == value)
            .map((b) => b.id)
            .toList();
        if (others.isEmpty) continue;
        duplicates++;
        reporter.fail(
          brand: brand,
          message:
              'Brand `${brand.id}` shares $label `$value` with '
              '${others.map((o) => '`$o`').join(', ')}.',
          file: _configFile(context),
          line: brand.line,
          explanation:
              'Store listings, push notifications and installed apps are '
              'keyed by this identifier; two brands with the same ID '
              'overwrite each other.',
          recommendation:
              'Give each brand a unique identifier, or set '
              '`policy.allow_duplicate_application_ids: true` if this is '
              'intentional.',
        );
      }
      if (duplicates == 0 && brand.applicationId != null) {
        reporter.pass('Application ID is unique', brand: brand);
      }
    }
  }
}

String _configFile(RuleContext context) {
  final root = context.config.projectRoot.replaceAll(r'\', '/');
  final path = context.config.configPath.replaceAll(r'\', '/');
  return path.startsWith('$root/') ? path.substring(root.length + 1) : path;
}
