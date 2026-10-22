import 'package:brandguard_flutter/src/utils/glob.dart';
import 'package:brandguard_flutter/src/utils/paths.dart';
import 'package:brandguard_flutter/src/utils/redaction.dart';
import 'package:brandguard_flutter/src/utils/text.dart';
import 'package:test/test.dart';

void main() {
  group('Glob', () {
    test('matches *, ? and **', () {
      expect(
        Glob('config/*/prod.json').matches('config/acme/prod.json'),
        isTrue,
      );
      expect(
        Glob('config/*/prod.json').matches('config/a/b/prod.json'),
        isFalse,
      );
      expect(Glob('lib/**/*.dart').matches('lib/main.dart'), isTrue);
      expect(Glob('lib/**/*.dart').matches('lib/a/b/c.dart'), isTrue);
      expect(Glob('app_??.arb').matches('app_en.arb'), isTrue);
      expect(Glob('app_??.arb').matches('app_eng.arb'), isFalse);
      expect(Glob('a.b').matches('axb'), isFalse);
    });
  });

  group('paths', () {
    test('resolveWithin rejects escapes and absolute paths', () {
      expect(resolveWithin('/root', '../etc/passwd'), isNull);
      expect(resolveWithin('/root', '/etc/passwd'), isNull);
      expect(resolveWithin('/root', 'a/../../b'), isNull);
      expect(resolveWithin('/root', 'a/./b.png'), isNotNull);
    });

    test('isSameOrWithin and normalizeRelative', () {
      expect(
        isSameOrWithin('assets/brands/acme', 'assets/brands/acme/x.png'),
        isTrue,
      );
      expect(
        isSameOrWithin('assets/brands/acme', 'assets/brands/acme2/x.png'),
        isFalse,
      );
      expect(normalizeRelative('./assets//brands/'), 'assets/brands');
      expect(normalizeRelative(r'assets\brands\acme'), 'assets/brands/acme');
    });
  });

  group('redactUrl', () {
    test('removes credentials and sensitive query values', () {
      expect(
        redactUrl('https://user:p4ss@api.example.com/v1?token=abc&page=2#frag'),
        'https://***@api.example.com/v1?token=***&page=2',
      );
      expect(
        redactUrl('https://x.example/?api_key=SECRET&client_secret=s&q=ok'),
        'https://x.example/?api_key=***&client_secret=***&q=ok',
      );
      expect(redactUrl('https://x.example/${'a' * 300}').length, 160);
    });
  });

  group('text helpers', () {
    test('LineIndex maps offsets to lines', () {
      final index = LineIndex('a\nbb\nccc');
      expect(index.lineOf(0), 1);
      expect(index.lineOf(2), 2);
      expect(index.lineOf(6), 3);
    });

    test('blankComments keeps strings and offsets', () {
      const source = 'a = "http://x" // note\n/* b\n c */ d';
      final blanked = blankComments(source);
      expect(blanked.length, source.length);
      expect(blanked, contains('"http://x"'));
      expect(blanked, isNot(contains('note')));
      expect(blanked.split('\n'), hasLength(3));
    });

    test('blankNestedBlocks hides nested statements', () {
      final blanked = blankNestedBlocks('x = 1\ninner { y = 2 }\nz = 3');
      expect(blanked, contains('x = 1'));
      expect(blanked, contains('z = 3'));
      expect(blanked, isNot(contains('y = 2')));
    });

    test('decodeXmlText', () {
      expect(decodeXmlText('A &amp; B &#39;s &#x41;'), "A & B 's A");
    });
  });
}
