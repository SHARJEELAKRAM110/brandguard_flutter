import 'package:yaml/yaml.dart';

import '../utils/paths.dart';

/// An entry under `flutter: assets:` in `pubspec.yaml`.
class AssetDeclaration {
  /// Creates a declaration.
  const AssetDeclaration({
    required this.path,
    required this.line,
    this.flavors,
  });

  /// Declared path. Directories end with `/`.
  final String path;

  /// 1-based line in `pubspec.yaml`.
  final int line;

  /// Flavors this asset is restricted to, or `null` for all flavors.
  final List<String>? flavors;

  /// Whether this declaration is a directory.
  bool get isDirectory => path.endsWith('/');

  /// Whether this declaration bundles [assetPath]. Directory declarations
  /// cover only files directly inside the directory, as in Flutter.
  bool covers(String assetPath) {
    final asset = normalizeRelative(assetPath);
    if (!isDirectory) return normalizeRelative(path) == asset;
    final directory = normalizeRelative(path);
    if (asset == directory) return true;
    if (!asset.startsWith('$directory/')) return false;
    return !asset.substring(directory.length + 1).contains('/');
  }
}

/// Parsed `flutter:` asset and font declarations.
class PubspecAssets {
  const PubspecAssets._(this.assets, this.fonts);

  /// Asset declarations.
  final List<AssetDeclaration> assets;

  /// Font asset paths keyed by normalized path, with their line.
  final Map<String, int> fonts;

  /// Parses `pubspec.yaml` [text]. Returns `null` when it is not valid YAML.
  static PubspecAssets? parse(String text) {
    final YamlNode root;
    try {
      root = loadYamlNode(text);
    } on YamlException {
      return null;
    }
    final assets = <AssetDeclaration>[];
    final fonts = <String, int>{};
    if (root is! YamlMap) return PubspecAssets._(assets, fonts);
    final flutter = root.nodes['flutter'];
    if (flutter is! YamlMap) return PubspecAssets._(assets, fonts);

    final assetList = flutter.nodes['assets'];
    if (assetList is YamlList) {
      for (final node in assetList.nodes) {
        final line = node.span.start.line + 1;
        if (node.value is String) {
          assets.add(
            AssetDeclaration(path: _clean(node.value as String), line: line),
          );
        } else if (node is YamlMap && node['path'] is String) {
          final flavors = node['flavors'];
          assets.add(
            AssetDeclaration(
              path: _clean(node['path'] as String),
              line: line,
              flavors: flavors is YamlList
                  ? flavors.map((f) => '$f').toList()
                  : null,
            ),
          );
        }
      }
    }

    final fontList = flutter.nodes['fonts'];
    if (fontList is YamlList) {
      for (final family in fontList.nodes) {
        if (family is! YamlMap) continue;
        final entries = family.nodes['fonts'];
        if (entries is! YamlList) continue;
        for (final entry in entries.nodes) {
          if (entry is YamlMap && entry['asset'] is String) {
            fonts[normalizeRelative(entry['asset'] as String)] =
                entry.span.start.line + 1;
          }
        }
      }
    }
    return PubspecAssets._(assets, fonts);
  }

  static String _clean(String path) {
    final posix = toPosix(path.trim());
    return posix.endsWith('/')
        ? '${normalizeRelative(posix)}/'
        : normalizeRelative(posix);
  }

  /// Declarations that bundle [assetPath].
  List<AssetDeclaration> declarationsFor(String assetPath) =>
      assets.where((d) => d.covers(assetPath)).toList();
}
