import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/config_model.dart';
import '../models/severity.dart';
import '../utils/glob.dart';
import '../utils/paths.dart';
import 'rule.dart';

/// Kinds treated as font files when checking pubspec declarations.
const _fontKinds = {'font', 'fonts'};

/// Rule B: configured brand assets exist inside the project.
class MissingAssetsRule extends Rule {
  /// Creates the rule.
  const MissingAssetsRule();

  @override
  String get id => 'missing_assets';

  @override
  String get description =>
      'Every asset configured for a brand exists inside the project root.';

  @override
  Severity get defaultSeverity => Severity.error;

  @override
  void run(RuleContext context, RuleReporter reporter) {
    final files = context.files;
    for (final brand in reporter.enabledBrands) {
      var checked = 0;
      var missing = 0;
      for (final MapEntry(key: kind, value: paths) in brand.assets.entries) {
        for (final path in paths) {
          checked++;
          final absolute = files.absolute(path);
          if (absolute == null) {
            missing++;
            reporter.fail(
              brand: brand,
              message:
                  'Asset `$kind` path `$path` is absolute or points outside '
                  'the project root.',
              explanation:
                  'BrandGuard only reads files inside the project, and builds '
                  'on other machines cannot rely on paths outside it.',
              recommendation:
                  'Use a path relative to the project root, e.g. '
                  '`assets/brands/${brand.id}/...`.',
            );
            continue;
          }
          final type = files.typeOf(path);
          if (type == FileSystemEntityType.link) {
            final target = _linkTarget(absolute);
            if (target == null ||
                !(target == files.root || p.isWithin(files.root, target))) {
              missing++;
              reporter.fail(
                brand: brand,
                message:
                    'Asset `$kind` `$path` is a symbolic link that is broken '
                    'or points outside the project root.',
                file: path,
                recommendation: 'Replace the link with the real file.',
              );
            }
            continue;
          }
          if (type == FileSystemEntityType.notFound) {
            missing++;
            reporter.fail(
              brand: brand,
              message: 'Missing asset `$kind`: $path',
              file: path,
              explanation:
                  'The configuration references a brand asset that does not '
                  'exist, so the build would ship without it or fail.',
              recommendation:
                  'Add the file at `$path` or fix the path in the brand '
                  'configuration.',
            );
          }
        }
      }
      if (checked > 0 && missing == 0) {
        reporter.pass(
          checked == 1
              ? 'Configured asset exists'
              : 'All $checked configured assets exist',
          brand: brand,
        );
      }
    }
  }

  static String? _linkTarget(String path) {
    try {
      return p.normalize(Link(path).resolveSymbolicLinksSync());
    } on FileSystemException {
      return null;
    }
  }
}

/// Rule B (registration): existing assets are declared in `pubspec.yaml`.
class UndeclaredAssetsRule extends Rule {
  /// Creates the rule.
  const UndeclaredAssetsRule();

  @override
  String get id => 'undeclared_assets';

  @override
  String get description =>
      'Existing brand assets are declared under flutter: assets (or fonts) '
      'in pubspec.yaml, including flavor-restricted declarations.';

  @override
  Severity get defaultSeverity => Severity.warning;

  @override
  void run(RuleContext context, RuleReporter reporter) {
    final options = context.config.assets;
    if (!options.requireDeclaration) return;
    final pubspec = context.pubspecAssets;
    if (pubspec == null) {
      reporter.report(
        Severity.info,
        message:
            'pubspec.yaml could not be parsed; asset declarations were not '
            'checked.',
        file: 'pubspec.yaml',
        certainty: Certainty.unresolved,
      );
      return;
    }
    final files = context.files;
    for (final brand in reporter.enabledBrands) {
      var checked = 0;
      var problems = 0;
      for (final MapEntry(key: kind, value: paths) in brand.assets.entries) {
        if (options.declarationExempt.contains(kind)) continue;
        for (final rawPath in paths) {
          final path = normalizeRelative(rawPath);
          final type = files.typeOf(path);
          if (type == FileSystemEntityType.notFound ||
              files.absolute(path) == null) {
            continue; // reported by missing_assets
          }
          checked++;
          if (_fontKinds.contains(kind)) {
            if (!pubspec.fonts.containsKey(path)) {
              problems++;
              reporter.fail(
                brand: brand,
                message:
                    'Font `$path` exists but is not declared under '
                    '`flutter: fonts:` in pubspec.yaml.',
                file: 'pubspec.yaml',
                explanation:
                    'Undeclared fonts are not bundled, so the brand would '
                    'fall back to the default font.',
                recommendation:
                    'Add `- asset: $path` to the matching font family in '
                    'pubspec.yaml.',
              );
            }
            continue;
          }
          final isDirectory = type == FileSystemEntityType.directory;
          final declarations = pubspec.declarationsFor(
            isDirectory ? path : path,
          );
          if (declarations.isEmpty) {
            problems++;
            final suggestion = isDirectory
                ? '$path/'
                : '${p.posix.dirname(path)}/';
            reporter.fail(
              brand: brand,
              message:
                  'Asset `$kind` exists but is not declared in pubspec.yaml: '
                  '$path',
              file: 'pubspec.yaml',
              explanation:
                  'The file exists on disk, but Flutter only bundles assets '
                  'listed under `flutter: assets:`. Directory entries cover '
                  'only files directly inside the directory.',
              recommendation:
                  'Add `- $suggestion` (or `- $path`) under `flutter: assets:`, '
                  'or list `$kind` in `assets.declaration_exempt` if it is '
                  'only used at build time.',
            );
            continue;
          }
          final flavor = brand.effectiveFlavor;
          final available = declarations.any(
            (d) => d.flavors == null || d.flavors!.contains(flavor),
          );
          if (!available) {
            problems++;
            final flavors = declarations
                .expand((d) => d.flavors ?? const <String>[])
                .toSet()
                .join(', ');
            reporter.fail(
              brand: brand,
              message:
                  'Asset `$kind` is declared only for flavor(s) $flavors, not '
                  '`$flavor`: $path',
              file: 'pubspec.yaml',
              line: declarations.first.line,
              explanation:
                  'Flavor-restricted assets are excluded from other flavors\' '
                  'builds.',
              recommendation:
                  'Add `$flavor` to the `flavors:` list of that asset entry.',
            );
          }
        }
      }
      if (checked > 0 && problems == 0) {
        reporter.pass('Assets are declared in pubspec.yaml', brand: brand);
      }
    }
  }
}

/// Rule C: brands do not use each other's assets.
class BrandAssetLeakageRule extends Rule {
  /// Creates the rule.
  const BrandAssetLeakageRule();

  @override
  String get id => 'brand_asset_leakage';

  @override
  String get description =>
      'A brand does not reference assets owned by another brand, the same '
      'file as another brand, or a byte-identical copy of another brand\'s '
      'asset.';

  @override
  Severity get defaultSeverity => Severity.warning;

  @override
  void run(RuleContext context, RuleReporter reporter) {
    final config = context.config;
    final options = config.assets;
    final files = context.files;
    final shared = options.sharedPaths
        .map((g) => Glob(normalizeRelative(g)))
        .toList();
    bool isShared(String path) => shared.any((g) => g.matches(path));

    final brandsRootExists =
        options.brandsRoot != null &&
        files.directoryExists(options.brandsRoot!);
    // (roots, explicitlyConfigured)
    (List<String>, bool) ownedRoots(BrandConfig brand) {
      if (brand.assetRoots != null) return (brand.assetRoots!, true);
      if (options.brandsRoot != null &&
          (options.brandsRootExplicit || brandsRootExists)) {
        return (
          ['${options.brandsRoot}/${brand.id}'],
          options.brandsRootExplicit,
        );
      }
      return (const [], false);
    }

    for (final brand in reporter.enabledBrands) {
      var problems = 0;
      final reported = <String>{};
      final own = ownedRoots(brand).$1;
      for (final MapEntry(key: kind, value: paths) in brand.assets.entries) {
        for (final rawPath in paths) {
          final path = normalizeRelative(rawPath);
          if (isShared(path) || !reported.add('$kind|$path')) continue;
          if (own.any((root) => isSameOrWithin(root, path))) continue;

          // 1. Path inside another brand's owned directory.
          var flagged = false;
          for (final other in config.brands) {
            if (other.id == brand.id) continue;
            final (roots, explicit) = ownedRoots(other);
            final root = roots.where((r) => isSameOrWithin(r, path));
            if (root.isEmpty) continue;
            flagged = true;
            problems++;
            reporter.fail(
              brand: brand,
              message:
                  'Brand `${brand.id}` uses `$kind` from brand '
                  '`${other.id}`: $path',
              file: path,
              certainty: explicit ? Certainty.definite : Certainty.heuristic,
              explanation: explicit
                  ? '`${root.first}` is configured as owned by `${other.id}`.'
                  : '`${root.first}` follows the `<brands_root>/<brand id>` '
                        'convention for `${other.id}`.',
              recommendation:
                  'Point `${brand.id}` at its own asset, or add the path to '
                  '`assets.isolation.shared_paths` if it is meant to be shared.',
            );
            break;
          }
          if (flagged) continue;

          // 2. Same file referenced by another brand.
          final sameFile = config.brands
              .where(
                (o) =>
                    o.id != brand.id &&
                    o.assets.values.any(
                      (list) => list.map(normalizeRelative).contains(path),
                    ),
              )
              .map((o) => o.id)
              .toList();
          if (sameFile.isNotEmpty) {
            problems++;
            reporter.fail(
              brand: brand,
              message:
                  'Brand `${brand.id}` uses the same `$kind` file as '
                  '${sameFile.map((o) => '`$o`').join(', ')}: $path',
              file: path,
              explanation:
                  'Brand-specific assets referenced by more than one brand '
                  'usually indicate a copy-paste mistake in the configuration.',
              recommendation:
                  'Give each brand its own file, or add the path to '
                  '`assets.isolation.shared_paths`.',
            );
            continue;
          }

          // 3. Directory segment naming another brand (weak evidence).
          if (options.pathHeuristics) {
            final segments = p.posix
                .split(p.posix.dirname(path))
                .map((s) => s.toLowerCase())
                .toSet();
            if (!segments.contains(brand.id.toLowerCase())) {
              final match = config.brands
                  .where(
                    (o) =>
                        o.id != brand.id &&
                        segments.contains(o.id.toLowerCase()),
                  )
                  .map((o) => o.id)
                  .firstOrNull;
              if (match != null) {
                problems++;
                reporter.report(
                  Severity.warning,
                  brand: brand,
                  message:
                      'Brand `${brand.id}` uses `$kind` from a directory '
                      'named after brand `$match`: $path',
                  file: path,
                  certainty: Certainty.heuristic,
                  explanation:
                      'A directory in the path matches another brand ID. '
                      'This is inferred from naming only.',
                  recommendation:
                      'Verify the asset belongs to `${brand.id}`, or disable '
                      '`assets.isolation.path_heuristics`.',
                );
              }
            }
          }
        }
      }

      if (options.compareContent) {
        problems += _compareContent(context, reporter, brand, isShared);
      }
      if (problems == 0 && brand.assets.isNotEmpty) {
        reporter.pass('No assets shared with other brands', brand: brand);
      }
    }
  }

  int _compareContent(
    RuleContext context,
    RuleReporter reporter,
    BrandConfig brand,
    bool Function(String) isShared,
  ) {
    final files = context.files;
    var problems = 0;
    for (final MapEntry(key: kind, value: paths) in brand.assets.entries) {
      for (final rawPath in paths) {
        final path = normalizeRelative(rawPath);
        if (isShared(path)) continue;
        final size = files.sizeOf(path);
        if (size == null || size == 0) continue;
        for (final other in context.config.brands) {
          if (other.id == brand.id) continue;
          final duplicate = other.assets.values
              .expand((list) => list)
              .map(normalizeRelative)
              .where((o) => o != path && !isShared(o))
              .where((o) => files.sizeOf(o) == size)
              .where((o) => _sameBytes(context, path, o))
              .firstOrNull;
          if (duplicate == null) continue;
          problems++;
          reporter.fail(
            brand: brand,
            message:
                'Brand `${brand.id}` `$kind` is byte-identical to '
                '`${other.id}`\'s asset $duplicate',
            file: path,
            explanation:
                'The files have identical contents, which usually means one '
                'brand\'s asset was copied into another brand\'s folder '
                'without being replaced.',
            recommendation:
                'Replace $path with `${brand.id}`\'s real asset, or add it '
                'to `assets.isolation.shared_paths` if sharing is intended.',
          );
          break;
        }
      }
    }
    return problems;
  }

  static bool _sameBytes(RuleContext context, String a, String b) {
    final key = a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';
    return context.cached(('sameBytes', key), () {
      final first = context.files.readBytes(a);
      final second = context.files.readBytes(b);
      if (first == null || second == null) return false;
      if (first.length != second.length) return false;
      for (var i = 0; i < first.length; i++) {
        if (first[i] != second[i]) return false;
      }
      return true;
    });
  }
}
