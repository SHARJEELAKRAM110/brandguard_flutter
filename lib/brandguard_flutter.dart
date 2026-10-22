/// Validate every Flutter app brand before you ship it.
///
/// BrandGuard checks white-label Flutter projects for missing or leaked
/// brand assets, mismatched application IDs and app names, incomplete ARB
/// translations, and non-production URLs in production brands.
///
/// Use [BrandGuard] to run validation programmatically, or [BrandGuardCli]
/// to embed the command-line interface. Implement [Rule] to add checks.
library;

export 'src/brandguard.dart';
export 'src/cli/cli.dart' show BrandGuardCli, CliIO, ExitCodes;
export 'src/config/config_loader.dart';
export 'src/config/config_model.dart';
export 'src/discovery/project_files.dart';
export 'src/discovery/project_locator.dart';
export 'src/models/finding.dart';
export 'src/models/severity.dart';
export 'src/models/validation_result.dart';
export 'src/reporting/json_reporter.dart';
export 'src/reporting/text_reporter.dart';
export 'src/rules/asset_rules.dart';
export 'src/rules/brand_rules.dart';
export 'src/rules/environment_rules.dart';
export 'src/rules/localization_rules.dart';
export 'src/rules/platform_rules.dart';
export 'src/rules/rule.dart';
export 'src/validators/android_project.dart'
    show AndroidProject, AndroidGradleModel, GradleBlock, GradleValue;
export 'src/validators/arb_analyzer.dart';
export 'src/validators/icu_message.dart';
export 'src/validators/ios_project.dart'
    show IosProject, XcodeProjectModel, XcodeBuildConfiguration;
export 'src/validators/pubspec_assets.dart';
export 'src/validators/resolved_value.dart';
export 'src/validators/url_scanner.dart' show UrlOccurrence, findUrls;
export 'src/version.dart';
