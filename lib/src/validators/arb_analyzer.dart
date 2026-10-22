import 'dart:convert';

import '../config/config_model.dart';
import '../discovery/project_files.dart';
import '../models/severity.dart';
import '../utils/paths.dart';
import '../utils/text.dart';
import 'icu_message.dart';

/// Categories of ARB problems, mapped onto rules by the localization rules.
enum ArbIssueKind {
  /// A required locale has no ARB file.
  missingFile,

  /// The file is not valid JSON or not a JSON object.
  invalidJson,

  /// A message value is not a string, or metadata is malformed.
  invalidStructure,

  /// `@@locale` disagrees with the file name.
  localeMismatch,

  /// A key from the base locale is absent.
  missingKey,

  /// A translation is an empty string.
  emptyValue,

  /// A key exists in the translation but not in the base locale.
  extraKey,

  /// Placeholder names, kinds, types or cases disagree with the base locale,
  /// or the ICU syntax is invalid.
  placeholderMismatch,
}

/// A problem found in an ARB file.
class ArbIssue {
  /// Creates an issue.
  const ArbIssue({
    required this.kind,
    required this.locale,
    required this.file,
    required this.message,
    this.key,
    this.line,
    this.maxSeverity,
  });

  /// Issue category.
  final ArbIssueKind kind;

  /// Locale of the affected file.
  final String locale;

  /// Affected file, relative to the project root.
  final String file;

  /// Human-readable description.
  final String message;

  /// Affected message key.
  final String? key;

  /// 1-based line, when known.
  final int? line;

  /// Upper bound on severity for issues that are only suspicious.
  final Severity? maxSeverity;
}

/// A parsed ARB file.
class ArbDocument {
  ArbDocument._({
    required this.file,
    required this.locale,
    required this.messages,
    required this.metadata,
    required this.keyLines,
    required this.issues,
  });

  /// Relative file path.
  final String file;

  /// Locale derived from the file name.
  final String locale;

  /// Translatable messages (keys without a leading `@`).
  final Map<String, Object?> messages;

  /// `@key` metadata objects keyed by message key.
  final Map<String, Map<String, Object?>> metadata;

  /// Line of each top-level key.
  final Map<String, int> keyLines;

  /// Parse and structure problems.
  final List<ArbIssue> issues;

  /// Whether the file parsed into a JSON object.
  bool get isValid => !issues.any((i) => i.kind == ArbIssueKind.invalidJson);

  /// Declared placeholder types for [key] (`name -> type or null`).
  Map<String, String?> placeholderTypes(String key) {
    final placeholders = metadata[key]?['placeholders'];
    if (placeholders is! Map) return const {};
    return {
      for (final entry in placeholders.entries)
        '${entry.key}': entry.value is Map
            ? ((entry.value as Map)['type'] as Object?)?.toString()
            : null,
    };
  }
}

/// Loads ARB files and compares locales against the base locale.
///
/// Results are cached per file so each file is parsed once per run.
class ArbAnalyzer {
  /// Creates an analyzer.
  ArbAnalyzer(this.files, this.config);

  /// Project files.
  final ProjectFiles files;

  /// Localization options.
  final LocalizationConfig config;

  final Map<String, ArbDocument?> _documents = {};
  final Map<String, List<ArbIssue>> _results = {};

  /// Relative path of the ARB file for [locale] in [directory].
  String pathFor(String directory, String locale) =>
      normalizeRelative('$directory/${config.fileNameFor(locale)}');

  /// Loads the ARB file for [locale], or `null` when it does not exist.
  ArbDocument? load(String directory, String locale) {
    final path = pathFor(directory, locale);
    return _documents.putIfAbsent(path, () {
      if (!files.fileExists(path)) return null;
      final text = files.readText(path);
      if (text == null) {
        return ArbDocument._(
          file: path,
          locale: locale,
          messages: const {},
          metadata: const {},
          keyLines: const {},
          issues: [
            ArbIssue(
              kind: ArbIssueKind.invalidJson,
              locale: locale,
              file: path,
              message: 'ARB file could not be read as UTF-8 text.',
            ),
          ],
        );
      }
      return _parse(path, locale, text);
    });
  }

  /// Returns all issues for [locale] in [directory] compared to
  /// [baseLocale]. Base-file problems are only reported when
  /// `locale == baseLocale`.
  List<ArbIssue> analyze(String directory, String baseLocale, String locale) {
    final cacheKey = '$directory|$baseLocale|$locale';
    return _results.putIfAbsent(cacheKey, () {
      final document = load(directory, locale);
      if (document == null) {
        return [
          ArbIssue(
            kind: ArbIssueKind.missingFile,
            locale: locale,
            file: pathFor(directory, locale),
            message:
                'ARB file for locale `$locale` not found: '
                '${pathFor(directory, locale)}',
          ),
        ];
      }
      final issues = [...document.issues];
      if (!document.isValid) return issues;
      if (locale == baseLocale) {
        issues.addAll(_checkBase(document));
        return issues;
      }
      final base = load(directory, baseLocale);
      if (base == null || !base.isValid) return issues;
      issues.addAll(_compare(base, document));
      return issues;
    });
  }

  ArbDocument _parse(String path, String locale, String text) {
    final issues = <ArbIssue>[];
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      final offset = e.offset;
      issues.add(
        ArbIssue(
          kind: ArbIssueKind.invalidJson,
          locale: locale,
          file: path,
          line: offset == null ? null : LineIndex(text).lineOf(offset),
          message: 'Invalid JSON: ${e.message}',
        ),
      );
    }
    if (decoded != null && decoded is! Map) {
      issues.add(
        ArbIssue(
          kind: ArbIssueKind.invalidJson,
          locale: locale,
          file: path,
          line: 1,
          message: 'ARB files must contain a JSON object.',
        ),
      );
    }
    if (issues.isNotEmpty) {
      return ArbDocument._(
        file: path,
        locale: locale,
        messages: const {},
        metadata: const {},
        keyLines: const {},
        issues: issues,
      );
    }

    final json = (decoded as Map).cast<String, Object?>();
    final keyLines = _topLevelKeyLines(text);
    final messages = <String, Object?>{};
    final metadata = <String, Map<String, Object?>>{};
    for (final entry in json.entries) {
      final key = entry.key;
      if (key.startsWith('@@')) continue;
      if (key.startsWith('@')) {
        final value = entry.value;
        if (value is Map) {
          metadata[key.substring(1)] = value.cast<String, Object?>();
        } else {
          issues.add(
            ArbIssue(
              kind: ArbIssueKind.invalidStructure,
              locale: locale,
              file: path,
              key: key,
              line: keyLines[key],
              message: 'Metadata entry `$key` must be a JSON object.',
            ),
          );
        }
        continue;
      }
      if (entry.value is! String) {
        issues.add(
          ArbIssue(
            kind: ArbIssueKind.invalidStructure,
            locale: locale,
            file: path,
            key: key,
            line: keyLines[key],
            message: 'Message `$key` must be a string.',
          ),
        );
      }
      messages[key] = entry.value;
    }

    final declaredLocale = json['@@locale'];
    if (declaredLocale is String &&
        _normalizeLocale(declaredLocale) != _normalizeLocale(locale)) {
      issues.add(
        ArbIssue(
          kind: ArbIssueKind.localeMismatch,
          locale: locale,
          file: path,
          line: keyLines['@@locale'],
          message:
              '`@@locale` is `$declaredLocale` but the file name implies '
              '`$locale`.',
        ),
      );
    }

    return ArbDocument._(
      file: path,
      locale: locale,
      messages: messages,
      metadata: metadata,
      keyLines: keyLines,
      issues: issues,
    );
  }

  List<ArbIssue> _checkBase(ArbDocument base) {
    final issues = <ArbIssue>[];
    for (final entry in base.messages.entries) {
      final value = entry.value;
      if (value is! String) continue;
      if (value.trim().isEmpty && !config.allowEmptyTranslations) {
        issues.add(
          _issue(
            base,
            ArbIssueKind.emptyValue,
            entry.key,
            'Message `${entry.key}` is empty in the base locale.',
          ),
        );
      }
      final parsed = IcuMessage.parse(value);
      if (parsed.error != null) {
        issues.add(
          _issue(
            base,
            ArbIssueKind.placeholderMismatch,
            entry.key,
            'Message `${entry.key}`: ${parsed.error}',
          ),
        );
      }
    }
    return issues;
  }

  List<ArbIssue> _compare(ArbDocument base, ArbDocument target) {
    final issues = <ArbIssue>[];
    for (final key in base.messages.keys) {
      final baseValue = base.messages[key];
      if (!target.messages.containsKey(key)) {
        issues.add(
          ArbIssue(
            kind: ArbIssueKind.missingKey,
            locale: target.locale,
            file: target.file,
            key: key,
            message: 'Missing translation `$key` in locale `${target.locale}`.',
          ),
        );
        continue;
      }
      final value = target.messages[key];
      if (value is! String || baseValue is! String) continue;
      if (value.trim().isEmpty && !config.allowEmptyTranslations) {
        issues.add(
          _issue(
            target,
            ArbIssueKind.emptyValue,
            key,
            'Translation `$key` is empty in locale `${target.locale}`.',
          ),
        );
        continue;
      }
      issues.addAll(_comparePlaceholders(base, target, key, baseValue, value));
    }
    for (final key in target.messages.keys) {
      if (!base.messages.containsKey(key)) {
        issues.add(
          _issue(
            target,
            ArbIssueKind.extraKey,
            key,
            'Key `$key` exists in locale `${target.locale}` but not in the '
            'base locale `${base.locale}`.',
            maxSeverity: Severity.info,
          ),
        );
      }
    }
    return issues;
  }

  List<ArbIssue> _comparePlaceholders(
    ArbDocument base,
    ArbDocument target,
    String key,
    String baseValue,
    String value,
  ) {
    final issues = <ArbIssue>[];
    final baseMessage = IcuMessage.parse(baseValue);
    final message = IcuMessage.parse(value);
    if (baseMessage.error != null) return issues; // reported on the base file
    if (message.error != null) {
      return [
        _issue(
          target,
          ArbIssueKind.placeholderMismatch,
          key,
          'Translation `$key` (${target.locale}): ${message.error}',
        ),
      ];
    }

    final declared = base.placeholderTypes(key).keys.toSet();
    final baseArgs = baseMessage.arguments;
    final known = {...baseArgs.keys, ...declared};

    for (final argument in message.arguments.values) {
      if (!known.contains(argument.name)) {
        issues.add(
          _issue(
            target,
            ArbIssueKind.placeholderMismatch,
            key,
            'Translation `$key` (${target.locale}) uses placeholder '
            '`{${argument.name}}`, which the base locale does not define.',
          ),
        );
        continue;
      }
      final baseArg = baseArgs[argument.name];
      if (baseArg == null) continue;
      if (baseArg.isChoice != argument.isChoice ||
          (baseArg.isChoice && baseArg.kind != argument.kind)) {
        issues.add(
          _issue(
            target,
            ArbIssueKind.placeholderMismatch,
            key,
            'Translation `$key` (${target.locale}) uses `{${argument.name}}` '
            'as ${argument.kind}, but the base locale uses ${baseArg.kind}.',
          ),
        );
        continue;
      }
      if (argument.isChoice && !argument.cases.contains('other')) {
        issues.add(
          _issue(
            target,
            ArbIssueKind.placeholderMismatch,
            key,
            'Translation `$key` (${target.locale}): ${argument.kind} '
            '`{${argument.name}}` has no `other` case.',
          ),
        );
      }
      if (argument.kind == 'select') {
        final missing = baseArg.cases.difference(argument.cases);
        if (missing.isNotEmpty) {
          issues.add(
            _issue(
              target,
              ArbIssueKind.placeholderMismatch,
              key,
              'Translation `$key` (${target.locale}): select `{${argument.name}}` '
              'is missing case(s) ${missing.join(', ')}.',
              maxSeverity: Severity.warning,
            ),
          );
        }
      }
    }

    for (final name in baseArgs.keys) {
      if (!message.arguments.containsKey(name)) {
        issues.add(
          _issue(
            target,
            ArbIssueKind.placeholderMismatch,
            key,
            'Translation `$key` (${target.locale}) does not use placeholder '
            '`{$name}` from the base locale.',
            maxSeverity: Severity.warning,
          ),
        );
      }
    }

    final baseTypes = base.placeholderTypes(key);
    final targetTypes = target.placeholderTypes(key);
    for (final entry in targetTypes.entries) {
      if (!baseTypes.containsKey(entry.key)) {
        issues.add(
          _issue(
            target,
            ArbIssueKind.placeholderMismatch,
            key,
            'Metadata `@$key` (${target.locale}) declares placeholder '
            '`${entry.key}`, which the base locale does not declare.',
          ),
        );
        continue;
      }
      final baseType = baseTypes[entry.key];
      if (entry.value != null && baseType != null && entry.value != baseType) {
        issues.add(
          _issue(
            target,
            ArbIssueKind.placeholderMismatch,
            key,
            'Placeholder `${entry.key}` of `$key` has type `${entry.value}` '
            'in ${target.locale} but `$baseType` in the base locale.',
          ),
        );
      }
    }
    return issues;
  }

  ArbIssue _issue(
    ArbDocument document,
    ArbIssueKind kind,
    String key,
    String message, {
    Severity? maxSeverity,
  }) => ArbIssue(
    kind: kind,
    locale: document.locale,
    file: document.file,
    key: key,
    line: document.keyLines[key],
    message: message,
    maxSeverity: maxSeverity,
  );

  static String _normalizeLocale(String locale) =>
      locale.replaceAll('-', '_').toLowerCase();

  /// Finds the line of every key in the top-level JSON object.
  static Map<String, int> _topLevelKeyLines(String text) {
    final lines = <String, int>{};
    var depth = 0;
    var line = 1;
    var i = 0;
    while (i < text.length) {
      final char = text[i];
      if (char == '\n') {
        line++;
      } else if (char == '{' || char == '[') {
        depth++;
      } else if (char == '}' || char == ']') {
        depth--;
      } else if (char == '"') {
        final start = i;
        final startLine = line;
        i++;
        while (i < text.length && text[i] != '"') {
          if (text[i] == r'\') i++;
          if (i < text.length && text[i] == '\n') line++;
          i++;
        }
        if (depth == 1) {
          var j = i + 1;
          while (j < text.length && ' \t\r\n'.contains(text[j])) {
            j++;
          }
          if (j < text.length && text[j] == ':') {
            try {
              final key = jsonDecode(text.substring(start, i + 1)) as String;
              lines.putIfAbsent(key, () => startLine);
            } on FormatException {
              // Leave the key without a line number.
            }
          }
        }
      }
      i++;
    }
    return lines;
  }
}
