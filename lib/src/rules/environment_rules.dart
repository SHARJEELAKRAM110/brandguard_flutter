import '../config/config_model.dart';
import '../models/severity.dart';
import '../utils/redaction.dart';
import '../validators/url_scanner.dart';
import 'rule.dart';

/// A URL that violates an environment's configuration.
class _UrlMatch {
  const _UrlMatch(this.occurrence, this.reason, {required this.heuristic});

  final UrlOccurrence occurrence;
  final String reason;
  final bool heuristic;
}

/// Files scanned for [brand], and globs that matched nothing.
(List<String>, List<String>) _filesFor(
  RuleContext context,
  BrandConfig brand,
  EnvironmentConfig environment,
) {
  final globs = [...environment.files, ...brand.environmentFiles].map(
    (g) => g
        .replaceAll('{brand}', brand.id)
        .replaceAll('{flavor}', brand.effectiveFlavor),
  );
  final files = <String>{};
  final empty = <String>[];
  for (final glob in globs) {
    final matched = context.files.matching(glob);
    if (matched.isEmpty) empty.add(glob);
    files.addAll(matched);
  }
  return (files.toList()..sort(), empty);
}

List<_UrlMatch> _scan(
  RuleContext context,
  BrandConfig brand,
  EnvironmentConfig environment,
) => context.cached(('urlScan', brand.id), () {
  final (files, _) = _filesFor(context, brand, environment);
  final matches = <_UrlMatch>[];
  for (final file in files) {
    final text = context.files.readText(file);
    if (text == null) continue;
    for (final url in context.cached((
      'urls',
      file,
    ), () => findUrls(text, file))) {
      if (environment.allowedHosts.contains(url.host)) continue;
      final reason = _definiteReason(url, environment);
      if (reason != null) {
        matches.add(_UrlMatch(url, reason, heuristic: false));
        continue;
      }
      if (environment.heuristics) {
        final markers = hostTokens(
          url.host,
        ).intersection(environment.heuristicMarkers.toSet());
        if (markers.isNotEmpty) {
          matches.add(
            _UrlMatch(url, 'host contains `${markers.first}`', heuristic: true),
          );
        }
      }
    }
  }
  return matches;
});

String? _definiteReason(UrlOccurrence url, EnvironmentConfig environment) {
  if (environment.forbiddenHosts.contains(url.host)) {
    return 'host is listed in forbidden_hosts';
  }
  final lowerUrl = url.url.toLowerCase();
  for (final pattern in environment.forbiddenUrlPatterns) {
    final lower = pattern.toLowerCase();
    final target = lower.contains('/') || lower.contains(':')
        ? lowerUrl
        : url.host;
    if (target.contains(lower)) return 'matches forbidden pattern `$pattern`';
  }
  if (environment.blockLoopback && isLoopbackHost(url.host)) {
    return 'points to a local/loopback host';
  }
  return null;
}

/// Rule F: a brand's environment files contain no forbidden URLs.
class ForbiddenEnvironmentUrlRule extends Rule {
  /// Creates the rule.
  const ForbiddenEnvironmentUrlRule();

  @override
  String get id => 'forbidden_environment_url';

  @override
  String get description =>
      'Files scanned for a brand contain no URL matching its environment\'s '
      'forbidden_hosts, forbidden_url_patterns or (for production) loopback '
      'hosts.';

  @override
  Severity get defaultSeverity => Severity.error;

  @override
  void run(RuleContext context, RuleReporter reporter) {
    final config = context.config;
    for (final brand in reporter.enabledBrands) {
      final name = config.environmentOf(brand);
      final environment = name == null ? null : config.environments[name];
      if (environment == null) continue; // missing_brand_configuration
      final (files, empty) = _filesFor(context, brand, environment);
      if (environment.files.isEmpty && brand.environmentFiles.isEmpty) {
        reporter.report(
          Severity.info,
          brand: brand,
          message:
              'No environment files configured for `${brand.id}`; URL checks '
              'skipped.',
          certainty: Certainty.unresolved,
          recommendation:
              'List the brand\'s configuration files under '
              '`environments.$name.files` (use `{brand}` for the brand ID) or '
              '`environment_files`.',
        );
        continue;
      }
      for (final glob in empty) {
        reporter.report(
          Severity.warning,
          brand: brand,
          message:
              'Environment file pattern `$glob` matched no files for '
              '`${brand.id}`.',
          explanation:
              'A missing environment file can mean the brand has no '
              '$name configuration at all.',
          recommendation: 'Create the file or fix the pattern.',
        );
      }
      var problems = 0;
      for (final match in _scan(context, brand, environment)) {
        if (match.heuristic) continue;
        problems++;
        reporter.fail(
          brand: brand,
          message:
              '${_title(name!)} brand uses URL '
              '${redactUrl(match.occurrence.url)} (${match.reason}).',
          file: match.occurrence.file,
          line: match.occurrence.line,
          explanation:
              'Shipping a $name build that talks to a non-$name backend '
              'leaks test data to real users or breaks the app.',
          recommendation:
              'Replace it with the $name endpoint, or add the host to '
              '`environments.$name.allowed_hosts` if it is correct.',
        );
      }
      if (problems == 0 && files.isNotEmpty) {
        reporter.pass(
          'No forbidden URLs in ${files.length} $name file'
          '${files.length == 1 ? '' : 's'}',
          brand: brand,
        );
      }
    }
  }
}

/// Rule F (heuristic): production URLs whose host suggests a test backend.
class SuspiciousEnvironmentUrlRule extends Rule {
  /// Creates the rule.
  const SuspiciousEnvironmentUrlRule();

  @override
  String get id => 'suspicious_environment_url';

  @override
  String get description =>
      'Heuristic: URLs whose host labels look non-production (staging, dev, '
      'qa, ...) in environments with heuristics enabled.';

  @override
  Severity get defaultSeverity => Severity.warning;

  @override
  void run(RuleContext context, RuleReporter reporter) {
    final config = context.config;
    for (final brand in reporter.enabledBrands) {
      final name = config.environmentOf(brand);
      final environment = name == null ? null : config.environments[name];
      if (environment == null || !environment.heuristics) continue;
      for (final match in _scan(context, brand, environment)) {
        if (!match.heuristic) continue;
        reporter.fail(
          brand: brand,
          message:
              '${_title(name!)} brand uses URL '
              '${redactUrl(match.occurrence.url)}, whose ${match.reason}.',
          file: match.occurrence.file,
          line: match.occurrence.line,
          certainty: Certainty.heuristic,
          explanation:
              'Inferred from the host name only; it may be a legitimate '
              '$name host.',
          recommendation:
              'If the host is correct, add it to '
              '`environments.$name.allowed_hosts`; otherwise replace it.',
        );
      }
    }
  }
}

String _title(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
