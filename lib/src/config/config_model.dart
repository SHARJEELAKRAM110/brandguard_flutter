import '../models/severity.dart';

/// The default configuration file name.
const defaultConfigFileName = '.brandguard.yaml';

/// Accepted non-hidden alternative to [defaultConfigFileName] (useful where
/// dotfiles are dropped, such as packages published to pub.dev). A project
/// must not contain both.
const alternateConfigFileName = 'brandguard.yaml';

/// The configuration schema version understood by this release.
const supportedConfigVersion = 1;

/// Brand fields that can be listed under `requirements.brand_fields`.
const knownBrandRequirementFields = {
  'name',
  'app_name',
  'application_id',
  'ios_bundle_id',
  'environment',
  'required_locales',
  'flavor',
};

/// Default value of `requirements.brand_fields`.
const defaultRequiredBrandFields = [
  'name',
  'app_name',
  'application_id',
  'environment',
  'required_locales',
  'assets.launcher_icon',
  'assets.logo',
];

/// The fully parsed and validated `.brandguard.yaml`.
class BrandGuardConfig {
  /// Creates a configuration. Prefer `ConfigLoader` for parsing files.
  const BrandGuardConfig({
    required this.configPath,
    required this.projectRoot,
    required this.brands,
    this.version = supportedConfigVersion,
    this.projectName,
    this.excludes = const [],
    this.defaultEnvironment,
    this.requiredBrandFields = defaultRequiredBrandFields,
    this.allowDuplicateApplicationIds = false,
    this.strict = false,
    this.assets = const AssetsConfig(),
    this.localization = const LocalizationConfig(),
    this.environments = const {},
    this.platforms = const PlatformsConfig(),
    this.rules = const {},
  });

  /// Schema version (`version:`).
  final int version;

  /// Absolute path of the configuration file.
  final String configPath;

  /// Absolute project root.
  final String projectRoot;

  /// `project.name`, if configured.
  final String? projectName;

  /// Additional glob patterns excluded from file scans (`scan.exclude`).
  final List<String> excludes;

  /// `defaults.environment`, applied to brands without `environment`.
  final String? defaultEnvironment;

  /// Fields every brand must define (`requirements.brand_fields`).
  final List<String> requiredBrandFields;

  /// `policy.allow_duplicate_application_ids`.
  final bool allowDuplicateApplicationIds;

  /// `policy.strict`: treat warnings as failures even without `--strict`.
  final bool strict;

  /// Asset validation options.
  final AssetsConfig assets;

  /// Localization validation options.
  final LocalizationConfig localization;

  /// Environment rules keyed by environment name.
  final Map<String, EnvironmentConfig> environments;

  /// Android and iOS inspection options.
  final PlatformsConfig platforms;

  /// Project-wide rule settings keyed by rule ID.
  final Map<String, RuleSettings> rules;

  /// Configured brands, in file order.
  final List<BrandConfig> brands;

  /// Returns the brand with [id], or `null`.
  BrandConfig? brandById(String id) {
    for (final brand in brands) {
      if (brand.id == id) return brand;
    }
    return null;
  }

  /// The environment of [brand] after applying defaults.
  String? environmentOf(BrandConfig brand) =>
      brand.environment ?? defaultEnvironment;

  /// The required locales of [brand] after applying defaults.
  List<String> requiredLocalesOf(BrandConfig brand) =>
      brand.requiredLocales ?? localization.requiredLocales;
}

/// Overrides for a single rule.
class RuleSettings {
  /// Creates rule settings; `null` fields inherit.
  const RuleSettings({this.enabled, this.severity});

  /// Whether the rule runs.
  final bool? enabled;

  /// The severity of the rule's primary findings.
  final Severity? severity;
}

/// One white-label brand.
class BrandConfig {
  /// Creates a brand.
  const BrandConfig({
    required this.id,
    this.name,
    this.appName,
    this.applicationId,
    this.iosBundleId,
    this.flavor,
    this.iosConfiguration,
    this.environment,
    this.assets = const {},
    this.assetRoots,
    this.requiredLocales,
    this.arbDirectory,
    this.environmentFiles = const [],
    this.rules = const {},
    this.line,
  });

  /// Unique brand ID.
  final String id;

  /// Human-readable brand name.
  final String? name;

  /// Expected launcher display name on Android and iOS.
  final String? appName;

  /// Expected Android application ID (and iOS bundle ID unless
  /// [iosBundleId] is set).
  final String? applicationId;

  /// Expected iOS bundle identifier, when it differs from [applicationId].
  final String? iosBundleId;

  /// Android product flavor / iOS configuration suffix. Defaults to [id].
  final String? flavor;

  /// Exact Xcode build configuration name to inspect, e.g. `Release-acme`.
  final String? iosConfiguration;

  /// Environment name, e.g. `production`.
  final String? environment;

  /// Asset paths keyed by asset kind (`launcher_icon`, `logo`, `fonts`, ...).
  final Map<String, List<String>> assets;

  /// Directories owned by this brand. `null` falls back to the
  /// `assets.brands_root` convention.
  final List<String>? assetRoots;

  /// Locales this brand ships. `null` inherits
  /// `localization.required_locales`.
  final List<String>? requiredLocales;

  /// Brand-specific ARB directory, overriding `localization.arb_directory`.
  final String? arbDirectory;

  /// Extra files (globs) scanned for environment URLs for this brand.
  final List<String> environmentFiles;

  /// Per-brand rule overrides.
  final Map<String, RuleSettings> rules;

  /// Line of the brand entry in the configuration file.
  final int? line;

  /// [name] when set, otherwise [id].
  String get displayName => name ?? id;

  /// The flavor name used for platform lookups.
  String get effectiveFlavor => flavor ?? id;

  /// The expected iOS bundle identifier.
  String? get expectedIosBundleId => iosBundleId ?? applicationId;
}

/// `assets:` section.
class AssetsConfig {
  /// Creates asset options.
  const AssetsConfig({
    this.requireDeclaration = true,
    this.declarationExempt = const ['launcher_icon'],
    this.brandsRoot = 'assets/brands',
    this.brandsRootExplicit = false,
    this.sharedPaths = const [],
    this.compareContent = true,
    this.pathHeuristics = true,
  });

  /// Whether existing assets must be declared under `flutter: assets:`.
  final bool requireDeclaration;

  /// Asset kinds that are not loaded at runtime and need no declaration.
  final List<String> declarationExempt;

  /// Directory containing one sub-directory per brand ID.
  final String? brandsRoot;

  /// Whether [brandsRoot] was set explicitly in the configuration.
  final bool brandsRootExplicit;

  /// Globs of assets that brands may legitimately share.
  final List<String> sharedPaths;

  /// Whether byte-identical assets across brands are reported.
  final bool compareContent;

  /// Whether directory names equal to another brand ID are reported.
  final bool pathHeuristics;
}

/// `localization:` section.
class LocalizationConfig {
  /// Creates localization options.
  const LocalizationConfig({
    this.enabled = true,
    this.arbDirectory,
    this.arbDirectoryExplicit = false,
    this.filePattern = 'app_{locale}.arb',
    this.baseLocale,
    this.requiredLocales = const [],
    this.allowEmptyTranslations = false,
  });

  /// Whether ARB validation runs.
  final bool enabled;

  /// Directory containing ARB files, relative to the project root.
  final String? arbDirectory;

  /// Whether [arbDirectory] was set explicitly (rather than discovered).
  final bool arbDirectoryExplicit;

  /// File name pattern containing `{locale}`.
  final String filePattern;

  /// Locale whose keys every other locale must contain.
  final String? baseLocale;

  /// Locales every brand must ship unless the brand overrides them.
  final List<String> requiredLocales;

  /// Whether empty translation strings are acceptable.
  final bool allowEmptyTranslations;

  /// Returns the ARB file name for [locale].
  String fileNameFor(String locale) =>
      filePattern.replaceAll('{locale}', locale);
}

/// One entry of the `environments:` section.
class EnvironmentConfig {
  /// Creates environment options.
  const EnvironmentConfig({
    required this.name,
    this.forbiddenUrlPatterns = const [],
    this.forbiddenHosts = const [],
    this.allowedHosts = const [],
    this.files = const [],
    this.blockLoopback = false,
    this.heuristics = false,
    this.heuristicMarkers = defaultHeuristicMarkers,
  });

  /// Host labels that suggest a non-production backend.
  static const defaultHeuristicMarkers = [
    'staging',
    'stage',
    'stg',
    'dev',
    'develop',
    'development',
    'test',
    'testing',
    'qa',
    'uat',
    'sandbox',
    'preprod',
    'local',
  ];

  /// Environment name.
  final String name;

  /// Case-insensitive substrings that must not appear in URL hosts (or in
  /// the full URL when the pattern contains `/` or `:`).
  final List<String> forbiddenUrlPatterns;

  /// Exact hostnames that must not appear.
  final List<String> forbiddenHosts;

  /// Hostnames that are never reported.
  final List<String> allowedHosts;

  /// Globs of files to scan. `{brand}` is replaced with the brand ID.
  final List<String> files;

  /// Whether loopback and emulator hosts are forbidden.
  final bool blockLoopback;

  /// Whether host-label heuristics run.
  final bool heuristics;

  /// Host labels that trigger the heuristic.
  final List<String> heuristicMarkers;
}

/// `platforms:` section.
class PlatformsConfig {
  /// Creates platform options.
  const PlatformsConfig({
    this.android = const AndroidPlatformConfig(),
    this.ios = const IosPlatformConfig(),
  });

  /// Android options.
  final AndroidPlatformConfig android;

  /// iOS options.
  final IosPlatformConfig ios;
}

/// `platforms.android:` section.
class AndroidPlatformConfig {
  /// Creates Android options.
  const AndroidPlatformConfig({
    this.enabled = true,
    this.gradleFiles = const [],
    this.manifest = 'android/app/src/main/AndroidManifest.xml',
  });

  /// Whether Android files are inspected.
  final bool enabled;

  /// Gradle files to inspect. Empty means `android/app/*.gradle(.kts)`.
  final List<String> gradleFiles;

  /// Main AndroidManifest.xml path.
  final String manifest;
}

/// `platforms.ios:` section.
class IosPlatformConfig {
  /// Creates iOS options.
  const IosPlatformConfig({
    this.enabled = true,
    this.projectFile = 'ios/Runner.xcodeproj/project.pbxproj',
    this.target = 'Runner',
    this.infoPlist = 'ios/Runner/Info.plist',
  });

  /// Whether iOS files are inspected.
  final bool enabled;

  /// Xcode project file.
  final String projectFile;

  /// Application target name.
  final String target;

  /// Default Info.plist path, used when `INFOPLIST_FILE` is not resolvable.
  final String infoPlist;
}
