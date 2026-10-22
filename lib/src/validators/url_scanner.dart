import '../utils/text.dart';

/// A URL found in a scanned file.
class UrlOccurrence {
  /// Creates an occurrence.
  const UrlOccurrence({
    required this.url,
    required this.host,
    required this.file,
    required this.line,
  });

  /// The URL as written (not redacted; never print this directly).
  final String url;

  /// Lower-case host name.
  final String host;

  /// File containing the URL.
  final String file;

  /// 1-based line.
  final int line;
}

final _urlPattern = RegExp(
  r'''\b(?:https?|wss?)://[^\s"'<>`\\(){}\[\],;]+''',
  caseSensitive: false,
);

const _commentPrefixes = ['//', '#', '*', '/*', '<!--', '--'];

/// Finds `http(s)` and `ws(s)` URLs in [text].
///
/// Lines whose first non-blank characters start a comment (`//`, `#`, `*`,
/// `/*`, `<!--`, `--`) are skipped, so commented-out endpoints are not
/// reported.
List<UrlOccurrence> findUrls(String text, String file) {
  final result = <UrlOccurrence>[];
  final lines = LineIndex(text);
  for (final match in _urlPattern.allMatches(text)) {
    final lineStart = text.lastIndexOf('\n', match.start) + 1;
    final prefix = text.substring(lineStart, match.start).trimLeft();
    if (_commentPrefixes.any(prefix.startsWith)) continue;
    var url = match[0]!;
    while (url.endsWith('.') || url.endsWith(':')) {
      url = url.substring(0, url.length - 1);
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) continue;
    result.add(
      UrlOccurrence(
        url: url,
        host: uri.host.toLowerCase(),
        file: file,
        line: lines.lineOf(match.start),
      ),
    );
  }
  return result;
}

const _loopbackHosts = {'localhost', '127.0.0.1', '0.0.0.0', '10.0.2.2', '::1'};

/// Whether [host] is a loopback or Android-emulator host.
bool isLoopbackHost(String host) {
  final h = host.replaceAll('[', '').replaceAll(']', '');
  return _loopbackHosts.contains(h) ||
      h.endsWith('.localhost') ||
      RegExp(r'^127\.\d+\.\d+\.\d+$').hasMatch(h);
}

/// Splits [host] into labels and hyphen-separated tokens.
Set<String> hostTokens(String host) =>
    host.split(RegExp(r'[.\-_]')).where((t) => t.isNotEmpty).toSet();
