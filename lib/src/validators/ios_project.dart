import 'package:path/path.dart' as p;

import '../config/config_model.dart';
import '../discovery/project_files.dart';
import '../utils/text.dart';
import 'resolved_value.dart';

/// One `XCBuildConfiguration` object from a `project.pbxproj` file.
class XcodeBuildConfiguration {
  /// Creates a build configuration.
  const XcodeBuildConfiguration({
    required this.id,
    required this.name,
    required this.settings,
    required this.settingLines,
    required this.line,
    this.baseConfigurationReference,
  });

  /// Object ID.
  final String id;

  /// Configuration name, e.g. `Release-acme`.
  final String name;

  /// Build settings with unquoted values.
  final Map<String, String> settings;

  /// Line of each setting.
  final Map<String, int> settingLines;

  /// Line of the object header.
  final int line;

  /// ID of the `.xcconfig` file reference, if any.
  final String? baseConfigurationReference;
}

/// The parts of a `project.pbxproj` BrandGuard understands.
class XcodeProjectModel {
  XcodeProjectModel._(
    this.configurations,
    this.targets,
    this.projectConfigurationIds,
    this.fileReferences,
  );

  /// Build configurations by object ID.
  final Map<String, XcodeBuildConfiguration> configurations;

  /// Native targets: name -> configuration IDs.
  final Map<String, List<String>> targets;

  /// Configuration IDs of the project (not target) level.
  final List<String> projectConfigurationIds;

  /// File references: object ID -> `path`.
  final Map<String, String> fileReferences;

  /// Configurations of [target], in file order.
  List<XcodeBuildConfiguration>? configurationsFor(String target) =>
      targets[target]
          ?.map((id) => configurations[id])
          .whereType<XcodeBuildConfiguration>()
          .toList();

  /// Project-level configuration with [name].
  XcodeBuildConfiguration? projectConfiguration(String name) {
    for (final id in projectConfigurationIds) {
      final configuration = configurations[id];
      if (configuration?.name == name) return configuration;
    }
    return null;
  }

  /// Parses a `project.pbxproj` file.
  static XcodeProjectModel parse(String text) {
    final lines = LineIndex(text);
    final objects = <String, (String isa, String body, int offset)>{};
    final header = RegExp(
      r'\b([0-9A-Za-z]{24})\b(?:\s*/\*(?:(?!\*/)[\s\S])*\*/)?\s*=\s*\{',
    );
    var consumedUntil = 0;
    for (final match in header.allMatches(text)) {
      if (match.start < consumedUntil) continue;
      final open = match.end - 1;
      final close = matchingBrace(text, open, singleQuotes: false);
      if (close == -1) continue;
      final body = text.substring(open + 1, close);
      final isa = RegExp(r'\bisa\s*=\s*(\w+)\s*;').firstMatch(body)?[1];
      if (isa != null) {
        objects[match[1]!] = (isa, body, open + 1);
        consumedUntil = close;
      }
    }

    final configurations = <String, XcodeBuildConfiguration>{};
    final configurationLists = <String, List<String>>{};
    final fileReferences = <String, String>{};
    final targetLists = <String, String>{};
    String? projectList;

    for (final entry in objects.entries) {
      final (isa, body, offset) = entry.value;
      final topLevel = blankNestedBlocks(body);
      switch (isa) {
        case 'XCBuildConfiguration':
          final settingsMatch = RegExp(
            r'buildSettings\s*=\s*\{',
          ).firstMatch(body);
          final settings = <String, String>{};
          final settingLines = <String, int>{};
          if (settingsMatch != null) {
            final open = settingsMatch.end - 1;
            final close = matchingBrace(body, open, singleQuotes: false);
            if (close != -1) {
              _parseSettings(
                body.substring(open + 1, close),
                offset + open + 1,
                lines,
                settings,
                settingLines,
              );
            }
          }
          configurations[entry.key] = XcodeBuildConfiguration(
            id: entry.key,
            name: _value(topLevel, 'name') ?? entry.key,
            settings: settings,
            settingLines: settingLines,
            line: lines.lineOf(offset),
            baseConfigurationReference: RegExp(
              r'baseConfigurationReference\s*=\s*([0-9A-Za-z]{24})',
            ).firstMatch(topLevel)?[1],
          );
        case 'XCConfigurationList':
          final list = RegExp(
            r'buildConfigurations\s*=\s*\(([^)]*)\)',
          ).firstMatch(body);
          configurationLists[entry.key] = list == null
              ? const []
              : _stripComments(list[1]!)
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList();
        case 'PBXNativeTarget':
          final name = _value(topLevel, 'name');
          final list = RegExp(
            r'buildConfigurationList\s*=\s*([0-9A-Za-z]{24})',
          ).firstMatch(topLevel)?[1];
          if (name != null && list != null) targetLists[name] = list;
        case 'PBXProject':
          projectList = RegExp(
            r'buildConfigurationList\s*=\s*([0-9A-Za-z]{24})',
          ).firstMatch(topLevel)?[1];
        case 'PBXFileReference':
          final path = _value(topLevel, 'path');
          if (path != null) fileReferences[entry.key] = path;
      }
    }

    return XcodeProjectModel._(
      configurations,
      {
        for (final entry in targetLists.entries)
          entry.key: configurationLists[entry.value] ?? const [],
      },
      configurationLists[projectList] ?? const [],
      fileReferences,
    );
  }

  static String _stripComments(String text) =>
      text.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');

  static String? _value(String body, String key) {
    final match = RegExp(
      '(?:^|[\\s;{])${RegExp.escape(key)}\\s*=\\s*("(?:[^"\\\\]|\\\\.)*"|[^;\\s]+)\\s*;',
    ).firstMatch(body);
    if (match == null) return null;
    return _unquote(match[1]!);
  }

  static String _unquote(String value) {
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      return value
          .substring(1, value.length - 1)
          .replaceAllMapped(RegExp(r'\\(.)'), (m) => m[1]!);
    }
    return value;
  }

  static void _parseSettings(
    String text,
    int baseOffset,
    LineIndex lines,
    Map<String, String> settings,
    Map<String, int> settingLines,
  ) {
    final cleaned = _blankPbxComments(text);
    final key = RegExp(r'\s*("(?:[^"\\]|\\.)*"|[^\s=;]+)\s*=\s*');
    var i = 0;
    while (i < cleaned.length) {
      final match = key.matchAsPrefix(cleaned, i);
      if (match == null) break;
      final name = _unquote(match[1]!);
      var j = match.end;
      String? value;
      if (j < cleaned.length && cleaned[j] == '"') {
        var k = j + 1;
        while (k < cleaned.length && cleaned[k] != '"') {
          if (cleaned[k] == r'\') k++;
          k++;
        }
        value = _unquote(cleaned.substring(j, k + 1));
        j = k + 1;
      } else if (j < cleaned.length && cleaned[j] == '(') {
        final close = cleaned.indexOf(')', j);
        j = close == -1 ? cleaned.length : close + 1;
      } else {
        final end = cleaned.indexOf(';', j);
        value = cleaned.substring(j, end == -1 ? cleaned.length : end).trim();
        j = end == -1 ? cleaned.length : end;
      }
      final semicolon = cleaned.indexOf(';', j);
      if (value != null) {
        settings[name] = value;
        settingLines[name] = lines.lineOf(baseOffset + match.start);
      }
      if (semicolon == -1) break;
      i = semicolon + 1;
    }
  }

  static String _blankPbxComments(String text) => text.replaceAllMapped(
    RegExp(r'/\*[\s\S]*?\*/'),
    (m) => m[0]!.replaceAll(RegExp(r'[^\n]'), ' '),
  );
}

final _variable = RegExp(
  r'\$\(([A-Za-z0-9_]+)(:[^)]*)?\)|\$\{([A-Za-z0-9_]+)(:[^}]*)?\}',
);

/// Static view of the iOS Runner project.
class IosProject {
  IosProject._(this.files, this.config, this.model);

  /// Loads the iOS project, or returns `null` when the project file is
  /// absent.
  static IosProject? load(ProjectFiles files, IosPlatformConfig config) {
    final text = files.readText(config.projectFile);
    if (text == null) return null;
    return IosProject._(files, config, XcodeProjectModel.parse(text));
  }

  /// Project files.
  final ProjectFiles files;

  /// iOS options.
  final IosPlatformConfig config;

  /// Parsed project.
  final XcodeProjectModel model;

  final Map<String, Map<String, String>> _xcconfigCache = {};

  /// Whether the configured target exists.
  bool get hasTarget => model.targets.containsKey(config.target);

  /// Selects the release build configuration for [brand].
  (XcodeBuildConfiguration?, ResolvedValue?) _configurationFor(
    BrandConfig brand,
  ) {
    final configurations = model.configurationsFor(config.target) ?? const [];
    final names = configurations.map((c) => c.name).toList();
    if (brand.iosConfiguration != null) {
      for (final configuration in configurations) {
        if (configuration.name == brand.iosConfiguration) {
          return (configuration, null);
        }
      }
      return (
        null,
        ResolvedValue.flavorMissing(
          origin: 'configuration `${brand.iosConfiguration}`',
          available: names,
          file: config.projectFile,
        ),
      );
    }
    String normalize(String value) =>
        value.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
    final flavor = normalize(brand.effectiveFlavor);
    for (final configuration in configurations) {
      final name = normalize(configuration.name);
      if (name == 'release$flavor' || name == '${flavor}release') {
        return (configuration, null);
      }
    }
    const standard = {'Debug', 'Release', 'Profile'};
    if (names.any((n) => !standard.contains(n))) {
      return (
        null,
        ResolvedValue.flavorMissing(
          origin: 'build configurations',
          available: names,
          file: config.projectFile,
        ),
      );
    }
    for (final configuration in configurations) {
      if (configuration.name == 'Release') return (configuration, null);
    }
    return (
      null,
      ResolvedValue.flavorMissing(
        origin: 'Release configuration',
        available: names,
        file: config.projectFile,
      ),
    );
  }

  ValueScope _scopeOf(XcodeBuildConfiguration configuration) =>
      configuration.name == 'Release' ? ValueScope.shared : ValueScope.flavor;

  /// Resolves `PRODUCT_BUNDLE_IDENTIFIER` for [brand]'s release
  /// configuration.
  ResolvedValue bundleIdFor(BrandConfig brand) {
    final (configuration, missing) = _configurationFor(brand);
    if (configuration == null) return missing!;
    return _resolveSetting(configuration, 'PRODUCT_BUNDLE_IDENTIFIER');
  }

  /// Resolves the display name (`CFBundleDisplayName`, falling back to
  /// `CFBundleName`) for [brand]'s release configuration.
  ResolvedValue displayNameFor(BrandConfig brand) {
    final (configuration, missing) = _configurationFor(brand);
    if (configuration == null) return missing!;
    final scope = _scopeOf(configuration);
    final settings = _effectiveSettings(configuration);

    var plistPath = config.infoPlist;
    final plistSetting = settings['INFOPLIST_FILE'];
    if (plistSetting != null) {
      final expanded = _expand(plistSetting, settings);
      if (expanded.$1 != null) {
        plistPath = p.posix.normalize(
          expanded.$1!.startsWith('ios/') ? expanded.$1! : 'ios/${expanded.$1}',
        );
      }
    }
    final plist = files.readText(plistPath);
    if (plist != null) {
      for (final key in ['CFBundleDisplayName', 'CFBundleName']) {
        final match = RegExp(
          '<key>$key</key>\\s*<string>([^<]*)</string>',
        ).firstMatch(plist);
        if (match == null) continue;
        final raw = decodeXmlText(match[1]!);
        final (value, reason) = _expand(raw, settings);
        return ResolvedValue(
          scope: scope,
          origin:
              '$key in ${p.posix.basename(plistPath)} '
              '(${configuration.name})',
          value: value,
          file: plistPath,
          line: LineIndex(plist).lineOf(match.start),
          unresolvedReason: reason,
        );
      }
    }
    if (settings.containsKey('INFOPLIST_KEY_CFBundleDisplayName')) {
      return _resolveSetting(
        configuration,
        'INFOPLIST_KEY_CFBundleDisplayName',
      );
    }
    return ResolvedValue(
      scope: scope,
      origin: 'Info.plist',
      file: plistPath,
      unresolvedReason: plist == null
          ? 'Info.plist not found at $plistPath.'
          : 'Info.plist defines neither CFBundleDisplayName nor CFBundleName.',
    );
  }

  ResolvedValue _resolveSetting(
    XcodeBuildConfiguration configuration,
    String key,
  ) {
    final settings = _effectiveSettings(configuration);
    final scope = _scopeOf(configuration);
    final origin = '$key (${configuration.name})';
    final raw = settings[key];
    final line = configuration.settingLines[key];
    if (raw == null) {
      return ResolvedValue(
        scope: scope,
        origin: origin,
        file: config.projectFile,
        line: configuration.line,
        unresolvedReason:
            '$key is not set in configuration `${configuration.name}` or its '
            'xcconfig files.',
      );
    }
    final (value, reason) = _expand(raw, settings);
    final xcconfig = _xcconfigPath(configuration.baseConfigurationReference);
    return ResolvedValue(
      scope: scope,
      origin: raw.contains(r'$') && xcconfig != null
          ? '$key (${configuration.name}, from `$raw` via $xcconfig)'
          : origin,
      value: value,
      file: config.projectFile,
      line: line ?? configuration.line,
      unresolvedReason: reason,
    );
  }

  String? _xcconfigPath(String? referenceId) {
    final referencePath = model.fileReferences[referenceId];
    return referencePath == null ? null : _locate(referencePath);
  }

  /// Project-level settings < project xcconfig < target xcconfig < target
  /// settings, mirroring Xcode's precedence.
  Map<String, String> _effectiveSettings(XcodeBuildConfiguration target) {
    final project = model.projectConfiguration(target.name);
    return {
      'TARGET_NAME': config.target,
      'PROJECT_NAME': 'Runner',
      'SRCROOT': 'ios',
      'PROJECT_DIR': 'ios',
      if (project != null) ..._xcconfigFor(project.baseConfigurationReference),
      if (project != null) ...project.settings,
      ..._xcconfigFor(target.baseConfigurationReference),
      ...target.settings,
    };
  }

  Map<String, String> _xcconfigFor(String? referenceId) {
    final path = _xcconfigPath(referenceId);
    if (path == null) return const {};
    return _readXcconfig(path, {});
  }

  String? _locate(String referencePath) {
    final normalized = referencePath.replaceAll(r'\', '/');
    final candidates = files.all
        .where((f) => f.startsWith('ios/') && f.endsWith('/$normalized'))
        .toList();
    if (candidates.length == 1) return candidates.single;
    final base = p.posix.basename(normalized);
    final byName = files.all
        .where((f) => f.startsWith('ios/') && p.posix.basename(f) == base)
        .toList();
    return byName.length == 1 ? byName.single : null;
  }

  Map<String, String> _readXcconfig(String path, Set<String> visiting) {
    final cached = _xcconfigCache[path];
    if (cached != null) return cached;
    if (!visiting.add(path)) return const {};
    final text = files.readText(path);
    final result = <String, String>{};
    if (text != null) {
      for (var line in text.split('\n')) {
        final comment = line.indexOf('//');
        if (comment != -1) line = line.substring(0, comment);
        line = line.trim();
        if (line.isEmpty) continue;
        final include = RegExp(r'^#include\??\s+"([^"]+)"').firstMatch(line);
        if (include != null) {
          final included = p.posix.normalize(
            p.posix.join(p.posix.dirname(path), include[1]!),
          );
          result.addAll(_readXcconfig(included, visiting));
          continue;
        }
        final assignment = RegExp(
          r'^([A-Za-z0-9_]+)\s*=\s*(.*?);?$',
        ).firstMatch(line);
        if (assignment != null) result[assignment[1]!] = assignment[2]!.trim();
      }
    }
    visiting.remove(path);
    return _xcconfigCache[path] = result;
  }

  /// Expands `$(VAR)` references. Returns `(value, null)` or
  /// `(null, reason)`.
  (String?, String?) _expand(String raw, Map<String, String> settings) {
    var value = raw;
    for (var depth = 0; depth < 10; depth++) {
      final match = _variable.firstMatch(value);
      if (match == null) return (value, null);
      final name = match[1] ?? match[3]!;
      final modifier = match[2] ?? match[4];
      if (name == 'inherited') {
        return (
          null,
          '`$raw` uses \$(inherited), which BrandGuard does not resolve.',
        );
      }
      if (modifier != null) {
        return (
          null,
          '`$raw` uses the build setting modifier `$modifier`, which '
              'BrandGuard does not evaluate.',
        );
      }
      final replacement = settings[name];
      if (replacement == null) {
        return (
          null,
          '`$raw` references `$name`, which is not defined statically '
              '(it may come from a generated xcconfig or the build '
              'environment).',
        );
      }
      value = value.replaceRange(match.start, match.end, replacement);
    }
    return (null, '`$raw` has too many nested variable references.');
  }
}
