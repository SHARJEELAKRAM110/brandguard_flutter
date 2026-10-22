import '../config/config_model.dart';
import '../models/severity.dart';
import '../validators/resolved_value.dart';
import 'rule.dart';

/// Rule D: configured identifiers match Android Gradle and Xcode settings.
class ApplicationIdentifierRule extends Rule {
  /// Creates the rule.
  const ApplicationIdentifierRule();

  @override
  String get id => 'application_identifier_mismatch';

  @override
  String get description =>
      'The configured application ID matches the Android applicationId and '
      'iOS PRODUCT_BUNDLE_IDENTIFIER that can be resolved statically.';

  @override
  Severity get defaultSeverity => Severity.error;

  @override
  void run(RuleContext context, RuleReporter reporter) {
    final brands = reporter.enabledBrands
        .where((b) => b.applicationId != null || b.iosBundleId != null)
        .toList();
    if (brands.isEmpty) return;
    final android = _android(context, reporter);
    final ios = _ios(context, reporter);
    for (final brand in brands) {
      if (android != null && brand.applicationId != null) {
        _compare(
          context: context,
          reporter: reporter,
          brand: brand,
          platform: 'Android',
          label: 'application ID',
          expected: brand.applicationId!,
          expectedOf: (b) => b.applicationId,
          resolved: android(brand),
          configField: 'application_id',
        );
      }
      if (ios != null && brand.expectedIosBundleId != null) {
        _compare(
          context: context,
          reporter: reporter,
          brand: brand,
          platform: 'iOS',
          label: 'bundle ID',
          expected: brand.expectedIosBundleId!,
          expectedOf: (b) => b.expectedIosBundleId,
          resolved: ios(brand),
          configField: brand.iosBundleId != null
              ? 'ios_bundle_id'
              : 'application_id',
        );
      }
    }
  }

  ResolvedValue Function(BrandConfig)? _android(
    RuleContext context,
    RuleReporter reporter,
  ) {
    final project = context.android;
    if (project == null) {
      _skipped(
        context,
        reporter,
        'Android',
        'no Gradle files found under '
            'android/app',
      );
      return null;
    }
    return (brand) => project.applicationIdFor(brand.effectiveFlavor);
  }

  ResolvedValue Function(BrandConfig)? _ios(
    RuleContext context,
    RuleReporter reporter,
  ) {
    final project = context.ios;
    if (project == null) {
      _skipped(
        context,
        reporter,
        'iOS',
        '${context.config.platforms.ios.projectFile} not found',
      );
      return null;
    }
    if (!project.hasTarget) {
      _skipped(
        context,
        reporter,
        'iOS',
        'target `${project.config.target}` not found in '
            '${project.config.projectFile}',
      );
      return null;
    }
    return project.bundleIdFor;
  }
}

/// Rule G: configured app names match launcher labels.
class AppNameRule extends Rule {
  /// Creates the rule.
  const AppNameRule();

  @override
  String get id => 'app_name_mismatch';

  @override
  String get description =>
      'The configured app_name matches the Android android:label and iOS '
      'CFBundleDisplayName that can be resolved statically.';

  @override
  Severity get defaultSeverity => Severity.error;

  @override
  void run(RuleContext context, RuleReporter reporter) {
    final brands = reporter.enabledBrands
        .where((b) => b.appName != null)
        .toList();
    if (brands.isEmpty) return;
    final android = context.android;
    if (android == null) {
      _skipped(
        context,
        reporter,
        'Android',
        'no Gradle files found under android/app',
      );
    }
    final ios = context.ios;
    if (ios == null) {
      _skipped(
        context,
        reporter,
        'iOS',
        '${context.config.platforms.ios.projectFile} not found',
      );
    } else if (!ios.hasTarget) {
      _skipped(
        context,
        reporter,
        'iOS',
        'target `${ios.config.target}` not found',
      );
    }
    for (final brand in brands) {
      if (android != null) {
        _compare(
          context: context,
          reporter: reporter,
          brand: brand,
          platform: 'Android',
          label: 'app name',
          expected: brand.appName!,
          expectedOf: (b) => b.appName,
          resolved: android.appNameFor(brand.effectiveFlavor),
          configField: 'app_name',
        );
      }
      if (ios != null && ios.hasTarget) {
        _compare(
          context: context,
          reporter: reporter,
          brand: brand,
          platform: 'iOS',
          label: 'app name',
          expected: brand.appName!,
          expectedOf: (b) => b.appName,
          resolved: ios.displayNameFor(brand),
          configField: 'app_name',
        );
      }
    }
  }
}

void _skipped(
  RuleContext context,
  RuleReporter reporter,
  String platform,
  String reason,
) {
  final platforms = context.config.platforms;
  final enabled = platform == 'Android'
      ? platforms.android.enabled
      : platforms.ios.enabled;
  if (!enabled) return; // Disabled on purpose; nothing to report.
  final key = ('skipped', reporter.rule.id, platform);
  context.cached(key, () {
    reporter.report(
      Severity.info,
      message: '$platform checks skipped: $reason.',
      certainty: Certainty.unresolved,
      recommendation:
          'Set `platforms.${platform.toLowerCase()}.enabled: false` if this '
          'project does not target $platform, or point BrandGuard at the '
          'right files under `platforms:`.',
    );
    return true;
  });
}

void _compare({
  required RuleContext context,
  required RuleReporter reporter,
  required BrandConfig brand,
  required String platform,
  required String label,
  required String expected,
  required String? Function(BrandConfig) expectedOf,
  required ResolvedValue resolved,
  required String configField,
}) {
  switch (resolved.scope) {
    case ValueScope.flavorMissing:
      reporter.report(
        Severity.warning,
        brand: brand,
        message:
            '$platform: no ${resolved.origin} entry for `${brand.id}` '
            '(flavor `${brand.effectiveFlavor}`); $label not verified.',
        file: resolved.file,
        certainty: Certainty.unresolved,
        explanation:
            'The project defines ${resolved.available.isEmpty ? 'none' : resolved.available.join(', ')}, '
            'but none matches this brand, so BrandGuard cannot tell which '
            '$label the brand ships with.',
        recommendation:
            'Set `flavor:` (Android flavor / iOS configuration suffix) or '
            '`ios_configuration:` on brand `${brand.id}`, or add the missing '
            'flavor/configuration.',
      );
      return;
    case ValueScope.flavor:
    case ValueScope.shared:
      break;
  }

  final value = resolved.value;
  if (value == null) {
    reporter.report(
      Severity.info,
      brand: brand,
      message:
          '$platform $label for `${brand.id}` needs manual verification: '
          '${resolved.unresolvedReason}',
      file: resolved.file,
      line: resolved.line,
      certainty: Certainty.unresolved,
      explanation:
          'BrandGuard reads build files statically and does not run Gradle '
          'or Xcode. Expected `$expected`.',
      recommendation:
          'Confirm the built app uses `$expected`, or replace the dynamic '
          'value with a literal so it can be checked.',
    );
    return;
  }

  if (value == expected) {
    reporter.pass('$platform $label matches ($value)', brand: brand);
    return;
  }

  final definitive =
      resolved.scope == ValueScope.flavor || !context.isMultiBrand;
  if (definitive) {
    reporter.fail(
      brand: brand,
      message:
          '$platform $label mismatch: expected `$expected`, found `$value`.',
      file: resolved.file,
      line: resolved.line,
      explanation: 'Resolved from ${resolved.origin}.',
      recommendation:
          'Change ${resolved.origin} to `$expected`, or fix `$configField` '
          'for brand `${brand.id}` in the BrandGuard configuration.',
    );
    return;
  }

  final owners = context.config.brands
      .where((b) => b.id != brand.id && expectedOf(b) == value)
      .map((b) => b.id)
      .toList();
  if (owners.isNotEmpty) {
    reporter.report(
      Severity.info,
      brand: brand,
      message:
          '$platform $label is shared by all brands and currently set to '
          '`${owners.first}` ($value); `${brand.id}` needs manual '
          'verification.',
      file: resolved.file,
      line: resolved.line,
      certainty: Certainty.unresolved,
      explanation:
          'The project has no per-brand ${platform == 'Android' ? 'product flavors' : 'build configurations'}, '
          'so the value for `${brand.id}` must be applied by external '
          'tooling before building.',
      recommendation:
          'Verify that your brand-switching step sets `$expected` before '
          'building `${brand.id}`.',
    );
  } else {
    reporter.report(
      Severity.warning,
      brand: brand,
      message:
          '$platform $label `$value` (shared by all brands) matches no '
          'configured brand; expected `$expected` for `${brand.id}`.',
      file: resolved.file,
      line: resolved.line,
      certainty: Certainty.heuristic,
      explanation: 'Resolved from ${resolved.origin}.',
      recommendation:
          'Update ${resolved.origin}, or configure per-brand flavors so each '
          'brand can be verified.',
    );
  }
}
