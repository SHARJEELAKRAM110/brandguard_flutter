import '../config/config_model.dart';
import '../discovery/project_files.dart';
import '../utils/text.dart';
import 'resolved_value.dart';

/// A value assigned in a Gradle file.
class GradleValue {
  /// Creates a Gradle value.
  const GradleValue({
    required this.raw,
    required this.file,
    required this.line,
    this.literal,
  });

  /// The source expression.
  final String raw;

  /// The string value when [raw] is a plain string literal.
  final String? literal;

  /// File containing the assignment.
  final String file;

  /// 1-based line.
  final int line;
}

/// The statements BrandGuard reads from a `defaultConfig`, product flavor or
/// build type block.
class GradleBlock {
  /// Creates an empty block description.
  GradleBlock(this.name, this.file, this.line);

  /// Block name (`defaultConfig`, a flavor name, or a build type name).
  final String name;

  /// File containing the block.
  final String file;

  /// Line of the block header.
  final int line;

  /// `applicationId` and `applicationIdSuffix` assignments.
  final Map<String, GradleValue> properties = {};

  /// `resValue("string", name, value)` declarations.
  final Map<String, GradleValue> stringResources = {};

  /// `manifestPlaceholders` entries.
  final Map<String, GradleValue> placeholders = {};
}

/// What BrandGuard understands of an Android app module's Gradle files.
class AndroidGradleModel {
  /// Creates an empty model.
  AndroidGradleModel(this.files);

  /// Inspected Gradle files.
  final List<String> files;

  /// Merged `defaultConfig` statements.
  GradleBlock? defaultConfig;

  /// Product flavors by name.
  final Map<String, GradleBlock> flavors = {};

  /// Build types by name.
  final Map<String, GradleBlock> buildTypes = {};

  /// Parses Gradle (Groovy or Kotlin DSL) [sources] keyed by relative path.
  static AndroidGradleModel parse(Map<String, String> sources) {
    final model = AndroidGradleModel(sources.keys.toList());
    for (final entry in sources.entries) {
      _GradleFileParser(entry.key, entry.value, model).parse();
    }
    return model;
  }
}

final _sectionHeader = RegExp(
  r'\b(defaultConfig|productFlavors|buildTypes)\s*\{',
);
final _namedCall = RegExp(
  r'''(?:create|register|maybeCreate|getByName|named)\s*\(\s*["']([^"']+)["']\s*\)\s*$''',
);
final _bareName = RegExp(r'''(?:^|[\s;])["']?([A-Za-z_][\w-]*)["']?\s*$''');
const _notBlockNames = {
  'all',
  'apply',
  'also',
  'android',
  'configureEach',
  'defaultConfig',
  'each',
  'else',
  'forEach',
  'if',
  'let',
  'run',
  'with',
};
final _property = RegExp(
  r'^[ \t]*(applicationId|applicationIdSuffix)\b[ \t]*=?[ \t]*(.+?)[ \t]*;?[ \t]*$',
  multiLine: true,
);
final _resValue = RegExp(
  r'''^[ \t]*resValue[ \t]*\(?[ \t]*["']string["'][ \t]*,[ \t]*["'](\w+)["'][ \t]*,[ \t]*(.+?)[ \t]*\)?[ \t]*;?[ \t]*$''',
  multiLine: true,
);
final _groovyPlaceholders = RegExp(
  r'manifestPlaceholders\s*(?:\+=|=)?\s*\[([^\]]*)\]',
);
final _groovyEntry = RegExp(
  r'''(?:^|,)\s*["']?(\w+)["']?\s*:\s*("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|[^,]+)''',
);
final _kotlinIndexedPlaceholder = RegExp(
  r'''manifestPlaceholders\s*\[\s*["'](\w+)["']\s*\]\s*=\s*(.+?)\s*;?\s*$''',
  multiLine: true,
);
final _kotlinPutPlaceholder = RegExp(
  r'''manifestPlaceholders\s*\.\s*put\s*\(\s*["'](\w+)["']\s*,\s*(.+?)\s*\)\s*;?\s*$''',
  multiLine: true,
);
final _kotlinMapOf = RegExp(
  r'manifestPlaceholders\s*(?:\+=|=|\.\s*putAll\s*\()\s*mapOf\s*\(([^)]*)\)',
);
final _kotlinPair = RegExp(
  r'''["'](\w+)["']\s+to\s+("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|[^,)]+)''',
);

class _GradleFileParser {
  _GradleFileParser(this.path, this.original, this.model)
    : text = blankComments(original),
      lines = LineIndex(original);

  final String path;
  final String original;
  final String text;
  final LineIndex lines;
  final AndroidGradleModel model;

  void parse() {
    for (final match in _sectionHeader.allMatches(text)) {
      final open = match.end - 1;
      final close = matchingBrace(text, open);
      if (close == -1) continue;
      final bodyStart = open + 1;
      final body = text.substring(bodyStart, close);
      switch (match[1]) {
        case 'defaultConfig':
          final block = model.defaultConfig ??= GradleBlock(
            'defaultConfig',
            path,
            lines.lineOf(match.start),
          );
          _readStatements(block, body, bodyStart);
        case 'productFlavors':
          _readChildren(body, bodyStart, model.flavors);
        case 'buildTypes':
          _readChildren(body, bodyStart, model.buildTypes);
      }
    }
  }

  void _readChildren(
    String body,
    int bodyStart,
    Map<String, GradleBlock> target,
  ) {
    var segmentStart = 0;
    var i = 0;
    String? quote;
    while (i < body.length) {
      final char = body[i];
      if (quote != null) {
        if (char == r'\') {
          i++;
        } else if (char == quote) {
          quote = null;
        }
        i++;
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
      } else if (char == '{') {
        final close = matchingBrace(body, i);
        if (close == -1) return;
        final header = body.substring(segmentStart, i);
        final name = _blockName(header);
        if (name != null) {
          final block = target.putIfAbsent(
            name,
            () => GradleBlock(name, path, lines.lineOf(bodyStart + i)),
          );
          _readStatements(
            block,
            body.substring(i + 1, close),
            bodyStart + i + 1,
          );
        }
        segmentStart = close + 1;
        i = close;
      }
      i++;
    }
  }

  String? _blockName(String header) {
    final trimmed = header.trimRight();
    final named = _namedCall.firstMatch(trimmed);
    if (named != null) return named[1];
    final bare = _bareName.firstMatch(trimmed);
    if (bare == null) return null;
    final name = bare[1]!;
    return _notBlockNames.contains(name) ? null : name;
  }

  void _readStatements(GradleBlock block, String body, int bodyStart) {
    final topLevel = _splitStatements(blankNestedBlocks(body));
    for (final match in _property.allMatches(topLevel)) {
      block.properties[match[1]!] = _value(match[2]!, bodyStart + match.start);
    }
    for (final match in _resValue.allMatches(topLevel)) {
      block.stringResources[match[1]!] = _value(
        match[2]!,
        bodyStart + match.start,
      );
    }
    for (final match in _groovyPlaceholders.allMatches(topLevel)) {
      final entries = match[1]!;
      for (final entry in _groovyEntry.allMatches(entries)) {
        block.placeholders[entry[1]!] = _value(
          entry[2]!,
          bodyStart + match.start,
        );
      }
    }
    for (final match in _kotlinIndexedPlaceholder.allMatches(topLevel)) {
      block.placeholders[match[1]!] = _value(
        match[2]!,
        bodyStart + match.start,
      );
    }
    for (final match in _kotlinPutPlaceholder.allMatches(topLevel)) {
      block.placeholders[match[1]!] = _value(
        match[2]!,
        bodyStart + match.start,
      );
    }
    for (final match in _kotlinMapOf.allMatches(topLevel)) {
      for (final pair in _kotlinPair.allMatches(match[1]!)) {
        block.placeholders[pair[1]!] = _value(
          pair[2]!,
          bodyStart + match.start,
        );
      }
    }
  }

  /// Turns `;` statement separators outside strings into newlines (same
  /// length, so offsets are preserved) so one-line blocks parse like
  /// multi-line ones.
  static String _splitStatements(String text) {
    final out = StringBuffer();
    String? quote;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (quote != null) {
        if (char == r'\' && i + 1 < text.length) {
          out
            ..write(char)
            ..write(text[++i]);
          continue;
        }
        if (char == quote) quote = null;
        out.write(char);
      } else if (char == '"' || char == "'") {
        quote = char;
        out.write(char);
      } else {
        out.write(char == ';' ? '\n' : char);
      }
    }
    return out.toString();
  }

  GradleValue _value(String raw, int offset) {
    final trimmed = raw.trim();
    return GradleValue(
      raw: trimmed,
      literal: parseStringLiteral(trimmed),
      file: path,
      line: lines.lineOf(offset),
    );
  }
}

final _doubleQuoted = RegExp(r'^"((?:[^"\\]|\\.)*)"$');
final _singleQuoted = RegExp(r"^'((?:[^'\\]|\\.)*)'$");

/// Returns the value of a Groovy/Kotlin string literal, or `null` when [raw]
/// is not a plain literal (variables, interpolation, concatenation).
String? parseStringLiteral(String raw) {
  final trimmed = raw.trim();
  final double = _doubleQuoted.firstMatch(trimmed);
  if (double != null) {
    final body = double[1]!;
    if (body.contains(r'$')) return null;
    return _unescape(body);
  }
  final single = _singleQuoted.firstMatch(trimmed);
  if (single != null) return _unescape(single[1]!);
  return null;
}

String _unescape(String body) => body.replaceAllMapped(
  RegExp(r'\\(.)'),
  (m) => switch (m[1]) {
    'n' => '\n',
    't' => '\t',
    _ => m[1]!,
  },
);

/// Static view of an Android app module.
class AndroidProject {
  AndroidProject._(this.files, this.config, this.gradle);

  /// Loads the Android module, or returns `null` when no Gradle files exist.
  static AndroidProject? load(
    ProjectFiles files,
    AndroidPlatformConfig config,
  ) {
    final paths = config.gradleFiles.isNotEmpty
        ? config.gradleFiles.expand(files.matching).toList()
        : files.all
              .where(
                (f) =>
                    RegExp(r'^android/app/[^/]+\.gradle(\.kts)?$').hasMatch(f),
              )
              .toList();
    final sources = <String, String>{};
    for (final path in paths) {
      final text = files.readText(path);
      if (text != null) sources[path] = text;
    }
    if (sources.isEmpty) return null;
    return AndroidProject._(files, config, AndroidGradleModel.parse(sources));
  }

  /// Project files.
  final ProjectFiles files;

  /// Android options.
  final AndroidPlatformConfig config;

  /// Parsed Gradle model.
  final AndroidGradleModel gradle;

  /// Resolves the application ID of the release build for [flavor].
  ResolvedValue applicationIdFor(String flavor) {
    final block = gradle.flavors[flavor];
    if (gradle.flavors.isNotEmpty && block == null) {
      return ResolvedValue.flavorMissing(
        origin: 'productFlavors',
        available: gradle.flavors.keys.toList()..sort(),
        file: gradle.files.first,
      );
    }
    final scope = block != null ? ValueScope.flavor : ValueScope.shared;
    final fromFlavor = block?.properties['applicationId'];
    final base =
        fromFlavor ?? gradle.defaultConfig?.properties['applicationId'];
    final origin = fromFlavor != null
        ? 'productFlavors.$flavor.applicationId'
        : 'defaultConfig.applicationId';
    if (base == null) {
      return ResolvedValue(
        scope: scope,
        origin: origin,
        file: gradle.files.first,
        unresolvedReason:
            'No applicationId found in defaultConfig'
            '${block == null ? '' : ' or productFlavors.$flavor'}.',
      );
    }
    if (base.literal == null) {
      return ResolvedValue(
        scope: scope,
        origin: origin,
        file: base.file,
        line: base.line,
        unresolvedReason:
            'applicationId is set from `${base.raw}`, which cannot be '
            'resolved statically.',
      );
    }
    final suffixes = [
      (
        gradle.defaultConfig?.properties['applicationIdSuffix'],
        'defaultConfig',
      ),
      (block?.properties['applicationIdSuffix'], 'productFlavors.$flavor'),
      (
        gradle.buildTypes['release']?.properties['applicationIdSuffix'],
        'buildTypes.release',
      ),
    ];
    final buffer = StringBuffer(base.literal!);
    final parts = [origin];
    for (final (suffix, where) in suffixes) {
      if (suffix == null) continue;
      if (suffix.literal == null) {
        return ResolvedValue(
          scope: scope,
          origin: '$where.applicationIdSuffix',
          file: suffix.file,
          line: suffix.line,
          unresolvedReason:
              'applicationIdSuffix is set from `${suffix.raw}`, which cannot '
              'be resolved statically.',
        );
      }
      buffer.write(suffix.literal);
      parts.add('$where.applicationIdSuffix');
    }
    return ResolvedValue(
      scope: scope,
      origin: parts.join(' + '),
      value: buffer.toString(),
      file: base.file,
      line: base.line,
    );
  }

  /// Resolves the launcher label (`android:label`) for [flavor].
  ResolvedValue appNameFor(String flavor) {
    final block = gradle.flavors[flavor];
    if (gradle.flavors.isNotEmpty && block == null) {
      return ResolvedValue.flavorMissing(
        origin: 'productFlavors',
        available: gradle.flavors.keys.toList()..sort(),
        file: gradle.files.first,
      );
    }
    final scope = block != null ? ValueScope.flavor : ValueScope.shared;
    final flavorManifest = 'android/app/src/$flavor/AndroidManifest.xml';
    final label =
        _manifestLabel(flavorManifest) ?? _manifestLabel(config.manifest);
    if (label == null) {
      return ResolvedValue(
        scope: scope,
        origin: 'AndroidManifest.xml',
        file: config.manifest,
        unresolvedReason: files.fileExists(config.manifest)
            ? 'No android:label on <application>.'
            : 'AndroidManifest.xml not found.',
      );
    }
    final (raw, file, line) = label;

    if (raw.startsWith('@string/')) {
      final name = raw.substring('@string/'.length);
      final candidates = <ResolvedValue? Function()>[
        () => _fromGradle(
          block?.stringResources[name],
          scope,
          'productFlavors.$flavor.resValue($name)',
        ),
        () => _fromStrings(
          'android/app/src/$flavor/res/values/strings.xml',
          name,
          scope,
        ),
        () => _fromGradle(
          gradle.defaultConfig?.stringResources[name],
          scope,
          'defaultConfig.resValue($name)',
        ),
        () => _fromStrings(
          'android/app/src/main/res/values/strings.xml',
          name,
          scope,
        ),
      ];
      for (final candidate in candidates) {
        final result = candidate();
        if (result != null) return result;
      }
      return ResolvedValue(
        scope: scope,
        origin: raw,
        file: file,
        line: line,
        unresolvedReason:
            'String resource `$name` was not found in Gradle resValue or '
            'res/values/strings.xml; it may be generated at build time.',
      );
    }

    final placeholder = RegExp(r'^\$\{(\w+)\}$').firstMatch(raw);
    if (placeholder != null) {
      final name = placeholder[1]!;
      final value =
          _fromGradle(
            block?.placeholders[name],
            scope,
            'productFlavors.$flavor.manifestPlaceholders[$name]',
          ) ??
          _fromGradle(
            gradle.buildTypes['release']?.placeholders[name],
            scope,
            'buildTypes.release.manifestPlaceholders[$name]',
          ) ??
          _fromGradle(
            gradle.defaultConfig?.placeholders[name],
            scope,
            'defaultConfig.manifestPlaceholders[$name]',
          );
      return value ??
          ResolvedValue(
            scope: scope,
            origin: raw,
            file: file,
            line: line,
            unresolvedReason:
                'Manifest placeholder `$name` is not assigned statically.',
          );
    }

    if (raw.startsWith('@') || raw.contains(r'${')) {
      return ResolvedValue(
        scope: scope,
        origin: 'android:label',
        file: file,
        line: line,
        unresolvedReason: 'android:label `$raw` cannot be resolved statically.',
      );
    }
    return ResolvedValue(
      scope: file == flavorManifest ? ValueScope.flavor : scope,
      origin: 'android:label',
      value: raw,
      file: file,
      line: line,
    );
  }

  ResolvedValue? _fromGradle(
    GradleValue? value,
    ValueScope scope,
    String origin,
  ) {
    if (value == null) return null;
    return ResolvedValue(
      scope: scope,
      origin: origin,
      value: value.literal,
      file: value.file,
      line: value.line,
      unresolvedReason: value.literal == null
          ? '`${value.raw}` cannot be resolved statically.'
          : null,
    );
  }

  ResolvedValue? _fromStrings(String path, String name, ValueScope scope) {
    final text = files.readText(path);
    if (text == null) return null;
    final match = RegExp(
      '<string\\s+name="${RegExp.escape(name)}"[^>]*>([\\s\\S]*?)</string>',
    ).firstMatch(text);
    if (match == null) return null;
    var value = decodeXmlText(match[1]!.trim());
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    }
    value = value.replaceAll(r"\'", "'").replaceAll(r'\"', '"');
    return ResolvedValue(
      scope: scope,
      origin: '$path @string/$name',
      value: value,
      file: path,
      line: LineIndex(text).lineOf(match.start),
    );
  }

  (String, String, int)? _manifestLabel(String path) {
    final text = files.readText(path);
    if (text == null) return null;
    final application = RegExp(r'<application\b[^>]*>').firstMatch(text);
    if (application == null) return null;
    final label = RegExp(
      r'''android:label\s*=\s*["']([^"']*)["']''',
    ).firstMatch(application[0]!);
    if (label == null) return null;
    return (
      decodeXmlText(label[1]!),
      path,
      LineIndex(text).lineOf(application.start + label.start),
    );
  }
}
