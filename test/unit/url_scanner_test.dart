import 'package:brandguard_flutter/src/validators/url_scanner.dart';
import 'package:test/test.dart';

void main() {
  test('finds URLs with hosts and line numbers', () {
    final urls = findUrls(
      '{\n  "api": "https://API.Example.com/v1",\n'
          '  "ws": "wss://push.example.com:8443/socket",\n'
          '  "text": "see https://docs.example.com."\n}',
      'config.json',
    );
    expect(urls.map((u) => (u.host, u.line)), [
      ('api.example.com', 2),
      ('push.example.com', 3),
      ('docs.example.com', 4),
    ]);
    expect(urls.last.url, 'https://docs.example.com');
  });

  test('skips commented-out lines', () {
    final urls = findUrls(
      '// const old = "https://staging.example.com";\n'
          '# url: https://dev.example.com\n'
          ' * https://qa.example.com\n'
          'const live = "https://api.example.com"; // https://x.example',
      'a.dart',
    );
    expect(urls.map((u) => u.host), ['api.example.com', 'x.example']);
  });

  test('ignores non-URL mentions of staging', () {
    expect(findUrls('"environment": "staging"', 'a.json'), isEmpty);
  });

  test('isLoopbackHost and hostTokens', () {
    expect(isLoopbackHost('localhost'), isTrue);
    expect(isLoopbackHost('127.0.0.5'), isTrue);
    expect(isLoopbackHost('10.0.2.2'), isTrue);
    expect(isLoopbackHost('[::1]'), isTrue);
    expect(isLoopbackHost('api.example.com'), isFalse);
    expect(hostTokens('api-staging.dev.example.com'), {
      'api',
      'staging',
      'dev',
      'example',
      'com',
    });
    expect(hostTokens('devices.example.com').contains('dev'), isFalse);
  });
}
