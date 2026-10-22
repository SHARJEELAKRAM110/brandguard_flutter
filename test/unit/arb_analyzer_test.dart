import 'package:brandguard_flutter/brandguard_flutter.dart';
import 'package:test/test.dart';

import '../support/project_builder.dart';

const _base = '''
{
  "@@locale": "en",
  "title": "Shop",
  "@title": {"description": "Title"},
  "greeting": "Hello {name}",
  "@greeting": {"placeholders": {"name": {"type": "String"}}},
  "items": "{count, plural, =0{none} other{{count} items}}",
  "@items": {"placeholders": {"count": {"type": "int"}}},
  "gender": "{sex, select, male{he} female{she} other{they}}"
}
''';

List<ArbIssue> _analyze(
  String locale,
  String content, {
  bool allowEmpty = false,
}) {
  final project = ProjectBuilder()
    ..file('lib/l10n/app_en.arb', _base)
    ..file('lib/l10n/app_$locale.arb', content);
  final analyzer = ArbAnalyzer(
    ProjectFiles(project.root),
    LocalizationConfig(allowEmptyTranslations: allowEmpty),
  );
  return analyzer.analyze('lib/l10n', 'en', locale);
}

void main() {
  group('IcuMessage', () {
    test('extracts simple, plural and nested arguments', () {
      final message = IcuMessage.parse(
        '{count, plural, =0{none} other{{name} has {count}}}',
      );
      expect(message.error, isNull);
      expect(message.arguments['count']!.kind, 'plural');
      expect(message.arguments['count']!.cases, {'=0', 'other'});
      expect(message.arguments['name']!.kind, 'simple');
    });

    test('reports unbalanced braces', () {
      expect(IcuMessage.parse('Hello {name').error, contains('Unbalanced'));
      expect(IcuMessage.parse('Hello name}').error, contains('Unbalanced'));
    });
  });

  group('ArbAnalyzer', () {
    test('a complete translation has no issues', () {
      final issues = _analyze('es', '''
{
  "@@locale": "es",
  "title": "Tienda",
  "greeting": "Hola {name}",
  "items": "{count, plural, =0{nada} one{1} other{{count} artículos}}",
  "gender": "{sex, select, male{él} female{ella} other{elle}}"
}
''');
      expect(issues, isEmpty);
    });

    test('metadata keys are not treated as messages', () {
      final issues = _analyze('es', '''
{"title": "T", "greeting": "Hola {name}",
 "items": "{count, plural, other{x}}",
 "gender": "{sex, select, male{a} female{b} other{c}}"}
''');
      // @title, @greeting, @items and @@locale in the base are not "missing".
      expect(issues, isEmpty);
    });

    test('reports a missing locale file', () {
      final project = ProjectBuilder()..file('lib/l10n/app_en.arb', _base);
      final issues = ArbAnalyzer(
        ProjectFiles(project.root),
        const LocalizationConfig(),
      ).analyze('lib/l10n', 'en', 'fr');
      expect(issues.single.kind, ArbIssueKind.missingFile);
      expect(issues.single.file, 'lib/l10n/app_fr.arb');
    });

    test('reports missing keys and empty translations', () {
      final issues = _analyze('fr', '''
{
  "title": "  ",
  "greeting": "Bonjour {name}",
  "gender": "{sex, select, male{il} female{elle} other{iel}}"
}
''');
      expect(
        issues.map((i) => (i.kind, i.key)),
        containsAll([
          (ArbIssueKind.emptyValue, 'title'),
          (ArbIssueKind.missingKey, 'items'),
        ]),
      );
      expect(issues.firstWhere((i) => i.key == 'title').line, 2);
    });

    test('empty translations can be allowed', () {
      final issues = _analyze('fr', '''
{"title": "", "greeting": "{name}", "items": "{count, plural, other{x}}",
 "gender": "{sex, select, male{a} female{b} other{c}}"}
''', allowEmpty: true);
      expect(issues, isEmpty);
    });

    test('reports invalid JSON with a line number', () {
      final issues = _analyze(
        'de',
        '{\n  "title": "Laden",\n  "greeting": \n}',
      );
      expect(issues.single.kind, ArbIssueKind.invalidJson);
      expect(issues.single.line, 4);
    });

    test('reports non-string messages and @@locale mismatches', () {
      final issues = _analyze('de', '''
{"@@locale": "fr", "title": 3, "greeting": "{name}",
 "items": "{count, plural, other{x}}",
 "gender": "{sex, select, male{a} female{b} other{c}}"}
''');
      expect(
        issues.map((i) => i.kind),
        containsAll([
          ArbIssueKind.invalidStructure,
          ArbIssueKind.localeMismatch,
        ]),
      );
    });

    test('reports placeholder name, kind and case mismatches', () {
      final issues = _analyze('fr', '''
{
  "title": "Boutique",
  "greeting": "Bonjour {nom}",
  "items": "{count, select, a{x} other{y}}",
  "gender": "{sex, select, male{il} other{iel}}"
}
''');
      final messages = issues.map((i) => i.message).join('\n');
      expect(messages, contains('uses placeholder `{nom}`'));
      expect(messages, contains('does not use placeholder `{name}`'));
      expect(messages, contains('as select, but the base locale uses plural'));
      expect(messages, contains('missing case(s) female'));
      expect(
        issues.every((i) => i.kind == ArbIssueKind.placeholderMismatch),
        isTrue,
      );
      // Omitted placeholders and select cases are only warnings.
      expect(
        issues.where((i) => i.maxSeverity == Severity.warning),
        hasLength(2),
      );
    });

    test('requires an `other` case in plurals', () {
      final issues = _analyze('fr', '''
{"title": "x", "greeting": "{name}", "items": "{count, plural, =0{rien} one{un}}",
 "gender": "{sex, select, male{a} female{b} other{c}}"}
''');
      expect(issues.single.message, contains('has no `other` case'));
    });

    test('reports placeholder type mismatches in translated metadata', () {
      final issues = _analyze('fr', '''
{"title": "x", "greeting": "{name}",
 "items": "{count, plural, other{{count}}}",
 "@items": {"placeholders": {"count": {"type": "String"}}},
 "gender": "{sex, select, male{a} female{b} other{c}}"}
''');
      expect(issues.single.message, contains('has type `String`'));
    });

    test('extra keys are informational', () {
      final issues = _analyze('fr', '''
{"title": "x", "greeting": "{name}", "items": "{count, plural, other{x}}",
 "gender": "{sex, select, male{a} female{b} other{c}}", "legacy": "old"}
''');
      expect(issues.single.kind, ArbIssueKind.extraKey);
      expect(issues.single.maxSeverity, Severity.info);
    });

    test('ignores generated Dart localization files', () {
      final project = ProjectBuilder()
        ..file('lib/l10n/app_en.arb', _base)
        ..file('lib/l10n/app_localizations_en.dart', '// generated')
        ..file('lib/l10n/app_localizations.dart', '// generated');
      final analyzer = ArbAnalyzer(
        ProjectFiles(project.root),
        const LocalizationConfig(),
      );
      expect(analyzer.analyze('lib/l10n', 'en', 'en'), isEmpty);
    });
  });
}
