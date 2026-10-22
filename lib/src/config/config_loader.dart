import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../models/severity.dart';
import '../utils/paths.dart';
import 'config_model.dart';

/// A single problem in the configuration file.
class ConfigIssue {
  /// Creates a configuration issue.
  const ConfigIssue(this.message, {this.field, this.line});

  /// What is wrong and how to fix it.
  final String message;

  /// Dotted path of the offending field, e.g. `brands[1].application_id`.
  final String? field;

  /// 1-based line in the configuration file, when known.
  final int? line;

  @override
  String toString() {
    final where = [
      if (line != null) 'line $line',
      if (field != null) field,
    ].join(', ');
    return where.isEmpty ? message : '$message ($where)';
  }
}

/// Thrown when the configuration cannot be loaded or is invalid.
class ConfigException implements Exception {
  /// Creates a configuration exception.
  ConfigException(this.configPath, List<ConfigIssue> issues)
    : issues = List.unmodifiable(issues);

  /// The configuration file that failed to load.
  final String configPath;

  /// Every problem that was found.
  final List<ConfigIssue> issues;

  @override
  String toString() =>
      'Invalid configuration in $configPath:\n'
      '${issues.map((i) => '  - $i').join('\n')}';
}

/// Parses and validates `.brandguard.yaml` files.
class ConfigLoader {
  /// Creates a loader that accepts settings for [knownRuleIds].
  ConfigLoader({required Iterable<String> knownRuleIds})
    : knownRuleIds = Set.unmodifiable(knownRuleIds);

  /// Rule IDs accepted under `rules:`.
  final Set<String> knownRuleIds;

  /// Loads [configPath]. When [projectRootOverride] is given it replaces
  /// `project.root`.
  BrandGuardConfig load(String configPath, {String? projectRootOverride}) {
    final file = File(configPath);
    if (!file.existsSync()) {
      throw ConfigException(configPath, [
        const ConfigIssue(
          'Configuration file not found. Run `brandguard init` to create one '
          'or pass --config <path>.',
        ),
      ]);
    }
    final String text;
    try {
      text = file.readAsStringSync();
    } on FileSystemException catch (e) {
      throw ConfigException(configPath, [
        ConfigIssue('Could not read configuration file: ${e.message}'),
      ]);
    }
    return parse(
      text,
      configPath: configPath,
      projectRootOverride: projectRootOverride,
    );
  }

  /// Parses configuration [text] that was read from [configPath].
  BrandGuardConfig parse(
    String text, {
    required String configPath,
    String? projectRootOverride,
  }) {
    final absoluteConfigPath = p.normalize(p.absolute(configPath));
    final reader = _Reader(absoluteConfigPath, knownRuleIds);
    final YamlNode document;
    try {
      document = loadYamlNode(text, sourceUrl: Uri.file(absoluteConfigPath));
    } on YamlException catch (e) {
      throw ConfigException(absoluteConfigPath, [
        ConfigIssue(
          'Invalid YAML: ${e.message}',
          line: e.span == null ? null : e.span!.start.line + 1,
        ),
      ]);
    }
    final config = reader.read(document, projectRootOverride);
    if (reader.issues.isNotEmpty || config == null) {
      throw ConfigException(absoluteConfigPath, reader.issues);
    }
    return config;
  }
}

final _brandIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]*$');
final _androidIdPattern = RegExp(
  r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$',
);
final _iosIdPattern = RegExp(r'^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$');

class _Reader {
  _Reader(this.configPath, this.knownRuleIds);

  final String configPath;
  final Set<String> knownRuleIds;
  final List<ConfigIssue> issues = [];

  void _issue(String message, String field, YamlNode? node) {
    issues.add(
      ConfigIssue(
        message,
        field: field,
        line: node == null ? null : node.span.start.line + 1,
      ),
    );
  }

  BrandGuardConfig? read(YamlNode document, String? projectRootOverride) {
    if (document is! YamlMap) {
      _issue(
        'The configuration must be a YAML map with `version` and `brands`.',
        '(root)',
        document,
      );
      return null;
    }
    final root = _checkedMap(document, '', const {
      'version',
      'project',
      'scan',
      'defaults',
      'requirements',
      'policy',
      'assets',
      'localization',
      'environments',
      'platforms',
      'rules',
      'brands',
    });

    final versionNode = root['version'];
    final version = _int(versionNode, 'version');
    if (versionNode == null) {
      _issue(
        'Missing required field `version` (use `version: 1`).',
        'version',
        document,
      );
    } else if (version != null && version != supportedConfigVersion) {
      _issue(
        'Unsupported configuration version $version; this release supports '
            'version $supportedConfigVersion.',
        'version',
        versionNode,
      );
    }

    final project = _optionalMap(root['project'], 'project', const {
      'name',
      'root',
    });
    final projectName = _string(project?['name'], 'project.name');
    final configuredRoot = _string(project?['root'], 'project.root') ?? '.';
    final projectRoot = p.normalize(
      p.absolute(
        projectRootOverride ?? p.join(p.dirname(configPath), configuredRoot),
      ),
    );

    final scan = _optionalMap(root['scan'], 'scan', const {'exclude'});
    final excludes = _stringList(scan?['exclude'], 'scan.exclude') ?? [];

    final defaults = _optionalMap(root['defaults'], 'defaults', const {
      'environment',
    });
    final defaultEnvironment = _string(
      defaults?['environment'],
      'defaults.environment',
    );

    final requirements = _optionalMap(
      root['requirements'],
      'requirements',
      const {'brand_fields'},
    );
    final requiredFields =
        _stringList(
          requirements?['brand_fields'],
          'requirements.brand_fields',
        ) ??
        defaultRequiredBrandFields;
    for (final field in requiredFields) {
      if (!knownBrandRequirementFields.contains(field) &&
          !field.startsWith('assets.')) {
        _issue(
          'Unknown brand field `$field`. Use one of '
              '${knownBrandRequirementFields.join(', ')} or `assets.<kind>`.',
          'requirements.brand_fields',
          requirements?['brand_fields'],
        );
      }
    }

    final policy = _optionalMap(root['policy'], 'policy', const {
      'allow_duplicate_application_ids',
      'strict',
    });
    final allowDuplicates =
        _bool(
          policy?['allow_duplicate_application_ids'],
          'policy.allow_duplicate_application_ids',
        ) ??
        false;
    final strict = _bool(policy?['strict'], 'policy.strict') ?? false;

    final assets = _readAssets(root['assets']);
    final localization = _readLocalization(root['localization'], projectRoot);
    final environments = _readEnvironments(root['environments']);
    final platforms = _readPlatforms(root['platforms']);
    final rules = _readRules(root['rules'], 'rules');
    final brands = _readBrands(root['brands'], document);

    final knownEnvironments = environments.keys.toSet();
    if (defaultEnvironment != null &&
        knownEnvironments.isNotEmpty &&
        !knownEnvironments.contains(defaultEnvironment)) {
      _issue(
        '`defaults.environment` is `$defaultEnvironment`, which is not '
            'declared under `environments` (${knownEnvironments.join(', ')}).',
        'defaults.environment',
        defaults?['environment'],
      );
    }

    return BrandGuardConfig(
      version: version ?? supportedConfigVersion,
      configPath: configPath,
      projectRoot: projectRoot,
      projectName: projectName,
      excludes: excludes,
      defaultEnvironment: defaultEnvironment,
      requiredBrandFields: requiredFields,
      allowDuplicateApplicationIds: allowDuplicates,
      strict: strict,
      assets: assets,
      localization: localization,
      environments: environments,
      platforms: platforms,
      rules: rules,
      brands: brands,
    );
  }

  AssetsConfig _readAssets(YamlNode? node) {
    final map = _optionalMap(node, 'assets', const {
      'require_declaration',
      'declaration_exempt',
      'brands_root',
      'isolation',
    });
    if (map == null) return const AssetsConfig();
    final isolation = _optionalMap(map['isolation'], 'assets.isolation', const {
      'shared_paths',
      'compare_content',
      'path_heuristics',
    });
    final brandsRootNode = map['brands_root'];
    String? brandsRoot = 'assets/brands';
    if (brandsRootNode != null) {
      brandsRoot = brandsRootNode.value == null
          ? null
          : _relativePath(brandsRootNode, 'assets.brands_root');
    }
    return AssetsConfig(
      requireDeclaration:
          _bool(map['require_declaration'], 'assets.require_declaration') ??
          true,
      declarationExempt:
          _stringList(map['declaration_exempt'], 'assets.declaration_exempt') ??
          const ['launcher_icon'],
      brandsRoot: brandsRoot,
      brandsRootExplicit: brandsRootNode != null,
      sharedPaths:
          _stringList(
            isolation?['shared_paths'],
            'assets.isolation.shared_paths',
          ) ??
          const [],
      compareContent:
          _bool(
            isolation?['compare_content'],
            'assets.isolation.compare_content',
          ) ??
          true,
      pathHeuristics:
          _bool(
            isolation?['path_heuristics'],
            'assets.isolation.path_heuristics',
          ) ??
          true,
    );
  }

  LocalizationConfig _readLocalization(YamlNode? node, String projectRoot) {
    final map = _optionalMap(node, 'localization', const {
      'enabled',
      'arb_directory',
      'file_pattern',
      'base_locale',
      'required_locales',
      'allow_empty_translations',
    });
    final enabled = _bool(map?['enabled'], 'localization.enabled') ?? true;
    var arbDirectory = map?['arb_directory'] == null
        ? null
        : _relativePath(map!['arb_directory']!, 'localization.arb_directory');
    final explicitDir = arbDirectory != null;
    final filePattern =
        _string(map?['file_pattern'], 'localization.file_pattern') ??
        'app_{locale}.arb';
    if (!filePattern.contains('{locale}')) {
      _issue(
        '`localization.file_pattern` must contain `{locale}`, '
            'e.g. `app_{locale}.arb`.',
        'localization.file_pattern',
        map?['file_pattern'],
      );
    }
    var baseLocale = _string(map?['base_locale'], 'localization.base_locale');

    // Fall back to Flutter's own l10n.yaml, then to the gen-l10n default.
    if (arbDirectory == null || baseLocale == null) {
      final discovered = _discoverL10nYaml(projectRoot, filePattern);
      arbDirectory ??= discovered.$1;
      baseLocale ??= discovered.$2;
    }

    final required =
        _stringList(
          map?['required_locales'],
          'localization.required_locales',
        ) ??
        const <String>[];
    return LocalizationConfig(
      enabled: enabled,
      arbDirectory: arbDirectory,
      arbDirectoryExplicit: explicitDir,
      filePattern: filePattern,
      baseLocale: baseLocale,
      requiredLocales: required,
      allowEmptyTranslations:
          _bool(
            map?['allow_empty_translations'],
            'localization.allow_empty_translations',
          ) ??
          false,
    );
  }

  (String?, String?) _discoverL10nYaml(String projectRoot, String pattern) {
    final l10n = File(p.join(projectRoot, 'l10n.yaml'));
    String? dir;
    String? base;
    if (l10n.existsSync()) {
      try {
        final yaml = loadYaml(l10n.readAsStringSync());
        if (yaml is YamlMap) {
          final arbDir = yaml['arb-dir'];
          if (arbDir is String) dir = normalizeRelative(arbDir);
          final template = yaml['template-arb-file'];
          if (template is String) {
            final regex = RegExp(
              '^${RegExp.escape(pattern).replaceAll(RegExp.escape('{locale}'), '(.+)')}\$',
            );
            final match = regex.firstMatch(template);
            if (match != null) base = match[1];
          }
          dir ??= 'lib/l10n';
        }
      } on YamlException {
        // A broken l10n.yaml is Flutter's problem to report; fall through.
      } on FileSystemException {
        // Unreadable: fall through to the conventional directory.
      }
    }
    if (dir == null &&
        Directory(p.join(projectRoot, 'lib', 'l10n')).existsSync()) {
      dir = 'lib/l10n';
    }
    return (dir, base);
  }

  Map<String, EnvironmentConfig> _readEnvironments(YamlNode? node) {
    if (node == null) return const {};
    if (node is! YamlMap) {
      _issue(
        '`environments` must be a map of environment names.',
        'environments',
        node,
      );
      return const {};
    }
    final result = <String, EnvironmentConfig>{};
    for (final entry in node.nodes.entries) {
      final keyNode = entry.key as YamlNode;
      final name = keyNode.value;
      if (name is! String) {
        _issue('Environment names must be strings.', 'environments', keyNode);
        continue;
      }
      final field = 'environments.$name';
      final valueNode = entry.value;
      final map = valueNode.value == null
          ? <String, YamlNode>{}
          : _optionalMap(valueNode, field, const {
              'forbidden_url_patterns',
              'forbidden_hosts',
              'allowed_hosts',
              'files',
              'block_loopback',
              'heuristics',
              'heuristic_markers',
            });
      if (map == null) continue;
      final isProduction =
          name.toLowerCase() == 'production' || name.toLowerCase() == 'prod';
      result[name] = EnvironmentConfig(
        name: name,
        forbiddenUrlPatterns:
            _stringList(
              map['forbidden_url_patterns'],
              '$field.forbidden_url_patterns',
            ) ??
            const [],
        forbiddenHosts:
            _stringList(
              map['forbidden_hosts'],
              '$field.forbidden_hosts',
            )?.map((h) => h.toLowerCase()).toList() ??
            const [],
        allowedHosts:
            _stringList(
              map['allowed_hosts'],
              '$field.allowed_hosts',
            )?.map((h) => h.toLowerCase()).toList() ??
            const [],
        files: _stringList(map['files'], '$field.files') ?? const [],
        blockLoopback:
            _bool(map['block_loopback'], '$field.block_loopback') ??
            isProduction,
        heuristics:
            _bool(map['heuristics'], '$field.heuristics') ?? isProduction,
        heuristicMarkers:
            _stringList(
              map['heuristic_markers'],
              '$field.heuristic_markers',
            )?.map((m) => m.toLowerCase()).toList() ??
            EnvironmentConfig.defaultHeuristicMarkers,
      );
    }
    return result;
  }

  PlatformsConfig _readPlatforms(YamlNode? node) {
    final map = _optionalMap(node, 'platforms', const {'android', 'ios'});
    final android = _optionalMap(map?['android'], 'platforms.android', const {
      'enabled',
      'gradle_files',
      'manifest',
    });
    final ios = _optionalMap(map?['ios'], 'platforms.ios', const {
      'enabled',
      'project_file',
      'target',
      'info_plist',
    });
    const androidDefaults = AndroidPlatformConfig();
    const iosDefaults = IosPlatformConfig();
    return PlatformsConfig(
      android: AndroidPlatformConfig(
        enabled:
            _bool(android?['enabled'], 'platforms.android.enabled') ?? true,
        gradleFiles:
            _stringList(
              android?['gradle_files'],
              'platforms.android.gradle_files',
            ) ??
            const [],
        manifest: android?['manifest'] == null
            ? androidDefaults.manifest
            : _relativePath(
                    android!['manifest']!,
                    'platforms.android.manifest',
                  ) ??
                  androidDefaults.manifest,
      ),
      ios: IosPlatformConfig(
        enabled: _bool(ios?['enabled'], 'platforms.ios.enabled') ?? true,
        projectFile: ios?['project_file'] == null
            ? iosDefaults.projectFile
            : _relativePath(
                    ios!['project_file']!,
                    'platforms.ios.project_file',
                  ) ??
                  iosDefaults.projectFile,
        target:
            _string(ios?['target'], 'platforms.ios.target') ??
            iosDefaults.target,
        infoPlist: ios?['info_plist'] == null
            ? iosDefaults.infoPlist
            : _relativePath(ios!['info_plist']!, 'platforms.ios.info_plist') ??
                  iosDefaults.infoPlist,
      ),
    );
  }

  Map<String, RuleSettings> _readRules(YamlNode? node, String field) {
    if (node == null || node.value == null) return const {};
    if (node is! YamlMap) {
      _issue('`$field` must be a map of rule IDs.', field, node);
      return const {};
    }
    final result = <String, RuleSettings>{};
    for (final entry in node.nodes.entries) {
      final keyNode = entry.key as YamlNode;
      final id = keyNode.value;
      if (id is! String || !knownRuleIds.contains(id)) {
        _issue(
          'Unknown rule `$id`. Known rules: '
          '${(knownRuleIds.toList()..sort()).join(', ')}.',
          field,
          keyNode,
        );
        continue;
      }
      final ruleField = '$field.$id';
      final valueNode = entry.value;
      // Shorthand: `rule_id: false` disables, `rule_id: warning` sets severity.
      if (valueNode.value is bool) {
        result[id] = RuleSettings(enabled: valueNode.value as bool);
        continue;
      }
      if (valueNode.value is String) {
        final severity = _severity(valueNode, ruleField);
        if (severity != null) result[id] = RuleSettings(severity: severity);
        continue;
      }
      final map = _optionalMap(valueNode, ruleField, const {
        'enabled',
        'severity',
      });
      if (map == null) continue;
      result[id] = RuleSettings(
        enabled: _bool(map['enabled'], '$ruleField.enabled'),
        severity: map['severity'] == null
            ? null
            : _severity(map['severity']!, '$ruleField.severity'),
      );
    }
    return result;
  }

  List<BrandConfig> _readBrands(YamlNode? node, YamlNode document) {
    if (node == null) {
      _issue(
        'Missing required field `brands` (a list of brands).',
        'brands',
        document,
      );
      return const [];
    }
    if (node is! YamlList) {
      _issue('`brands` must be a list.', 'brands', node);
      return const [];
    }
    if (node.nodes.isEmpty) {
      _issue('`brands` must contain at least one brand.', 'brands', node);
    }
    final brands = <BrandConfig>[];
    final seenIds = <String, int>{};
    for (var i = 0; i < node.nodes.length; i++) {
      final brandNode = node.nodes[i];
      final field = 'brands[$i]';
      final map = _checkedMap(brandNode, field, const {
        'id',
        'name',
        'app_name',
        'application_id',
        'ios_bundle_id',
        'flavor',
        'ios_configuration',
        'environment',
        'assets',
        'asset_roots',
        'required_locales',
        'arb_directory',
        'environment_files',
        'rules',
      });
      if (brandNode is! YamlMap) continue;
      final idNode = map['id'];
      final id = _string(idNode, '$field.id');
      if (idNode == null) {
        _issue('Brand is missing required field `id`.', '$field.id', brandNode);
        continue;
      }
      if (id == null) continue;
      if (!_brandIdPattern.hasMatch(id)) {
        _issue(
          'Brand ID `$id` may only contain letters, digits, `_` and `-`.',
          '$field.id',
          idNode,
        );
      }
      final line = brandNode.span.start.line + 1;
      if (seenIds.containsKey(id)) {
        _issue(
          'Duplicate brand ID `$id` (first defined on line ${seenIds[id]}).',
          '$field.id',
          idNode,
        );
      } else {
        seenIds[id] = line;
      }

      final applicationId = _string(
        map['application_id'],
        '$field.application_id',
      );
      if (applicationId != null && !_androidIdPattern.hasMatch(applicationId)) {
        _issue(
          'Application ID `$applicationId` is not a valid Android application '
              'ID (segments must start with a letter and contain only letters, '
              'digits and `_`).',
          '$field.application_id',
          map['application_id'],
        );
      }
      final iosBundleId = _string(map['ios_bundle_id'], '$field.ios_bundle_id');
      if (iosBundleId != null && !_iosIdPattern.hasMatch(iosBundleId)) {
        _issue(
          'iOS bundle ID `$iosBundleId` is not valid (use reverse-DNS form '
              'with letters, digits, `-` and `.`).',
          '$field.ios_bundle_id',
          map['ios_bundle_id'],
        );
      }

      brands.add(
        BrandConfig(
          id: id,
          name: _string(map['name'], '$field.name'),
          appName: _string(map['app_name'], '$field.app_name'),
          applicationId: applicationId,
          iosBundleId: iosBundleId,
          flavor: _string(map['flavor'], '$field.flavor'),
          iosConfiguration: _string(
            map['ios_configuration'],
            '$field.ios_configuration',
          ),
          environment: _string(map['environment'], '$field.environment'),
          assets: _readBrandAssets(map['assets'], '$field.assets'),
          assetRoots: _stringList(
            map['asset_roots'],
            '$field.asset_roots',
          )?.map(normalizeRelative).toList(),
          requiredLocales: _stringList(
            map['required_locales'],
            '$field.required_locales',
          ),
          arbDirectory: map['arb_directory'] == null
              ? null
              : _relativePath(map['arb_directory']!, '$field.arb_directory'),
          environmentFiles:
              _stringList(
                map['environment_files'],
                '$field.environment_files',
              ) ??
              const [],
          rules: _readRules(map['rules'], '$field.rules'),
          line: line,
        ),
      );
    }
    return brands;
  }

  Map<String, List<String>> _readBrandAssets(YamlNode? node, String field) {
    if (node == null || node.value == null) return const {};
    if (node is! YamlMap) {
      _issue(
        '`$field` must map asset kinds to a path or a list of paths.',
        field,
        node,
      );
      return const {};
    }
    final result = <String, List<String>>{};
    for (final entry in node.nodes.entries) {
      final keyNode = entry.key as YamlNode;
      final kind = keyNode.value;
      if (kind is! String) {
        _issue('Asset kinds must be strings.', field, keyNode);
        continue;
      }
      final value = entry.value;
      if (value.value is String) {
        result[kind] = [toPosix(value.value as String)];
      } else {
        final list = _stringList(value, '$field.$kind');
        if (list != null) result[kind] = list.map(toPosix).toList();
      }
    }
    return result;
  }

  // ---- Primitive readers ---------------------------------------------------

  Map<String, YamlNode> _checkedMap(
    YamlNode node,
    String field,
    Set<String> allowedKeys,
  ) {
    if (node is! YamlMap) {
      _issue(
        '`${field.isEmpty ? '(root)' : field}` must be a map.',
        field,
        node,
      );
      return const {};
    }
    final result = <String, YamlNode>{};
    for (final entry in node.nodes.entries) {
      final keyNode = entry.key as YamlNode;
      final key = keyNode.value;
      final keyField = field.isEmpty ? '$key' : '$field.$key';
      if (key is! String || !allowedKeys.contains(key)) {
        final suggestion = key is String ? _closest(key, allowedKeys) : null;
        _issue(
          'Unknown field `$keyField`.'
          '${suggestion == null ? '' : ' Did you mean `$suggestion`?'}',
          keyField,
          keyNode,
        );
        continue;
      }
      result[key] = entry.value;
    }
    return result;
  }

  Map<String, YamlNode>? _optionalMap(
    YamlNode? node,
    String field,
    Set<String> allowedKeys,
  ) {
    if (node == null || node.value == null) return null;
    if (node is! YamlMap) {
      _issue('`$field` must be a map.', field, node);
      return null;
    }
    return _checkedMap(node, field, allowedKeys);
  }

  String? _string(YamlNode? node, String field) {
    if (node == null || node.value == null) return null;
    final value = node.value;
    if (value is String) {
      if (value.trim().isEmpty) {
        _issue('`$field` must not be empty.', field, node);
        return null;
      }
      return value.trim();
    }
    if (value is num || value is bool) {
      _issue('`$field` must be a string; quote the value.', field, node);
      return null;
    }
    _issue('`$field` must be a string.', field, node);
    return null;
  }

  String? _relativePath(YamlNode node, String field) {
    final value = _string(node, field);
    if (value == null) return null;
    if (p.isAbsolute(value) || value.startsWith('/')) {
      _issue('`$field` must be relative to the project root.', field, node);
      return null;
    }
    return normalizeRelative(value);
  }

  int? _int(YamlNode? node, String field) {
    if (node == null) return null;
    if (node.value is int) return node.value as int;
    _issue('`$field` must be an integer.', field, node);
    return null;
  }

  bool? _bool(YamlNode? node, String field) {
    if (node == null || node.value == null) return null;
    if (node.value is bool) return node.value as bool;
    _issue('`$field` must be `true` or `false`.', field, node);
    return null;
  }

  Severity? _severity(YamlNode node, String field) {
    final value = node.value;
    final parsed = value is String ? Severity.tryParse(value) : null;
    if (parsed == null) {
      _issue(
        'Invalid severity `$value` for `$field`; use error, warning or info.',
        field,
        node,
      );
    }
    return parsed;
  }

  List<String>? _stringList(YamlNode? node, String field) {
    if (node == null || node.value == null) return null;
    if (node is! YamlList) {
      _issue('`$field` must be a list of strings.', field, node);
      return null;
    }
    final result = <String>[];
    for (final item in node.nodes) {
      final value = item.value;
      if (value is String && value.trim().isNotEmpty) {
        result.add(value.trim());
      } else {
        _issue('`$field` must contain only non-empty strings.', field, item);
      }
    }
    return result;
  }

  static String? _closest(String key, Set<String> candidates) {
    String? best;
    var bestDistance = 3;
    for (final candidate in candidates) {
      final distance = _levenshtein(key, candidate);
      if (distance < bestDistance) {
        best = candidate;
        bestDistance = distance;
      }
    }
    return best;
  }

  static int _levenshtein(String a, String b) {
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        current[j] = [
          previous[j] + 1,
          current[j - 1] + 1,
          previous[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
      previous = current;
    }
    return previous[b.length];
  }
}
