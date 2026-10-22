import 'package:path/path.dart' as p;

/// Converts [path] to `/` separators for stable, cross-platform output.
String toPosix(String path) => path.replaceAll(r'\', '/');

/// Returns [absolute] relative to [root] using `/` separators.
String relativeTo(String root, String absolute) =>
    toPosix(p.relative(absolute, from: root));

/// Resolves [relative] against [root] and returns the normalized absolute
/// path, or `null` when [relative] is absolute or the result would escape
/// [root].
String? resolveWithin(String root, String relative) {
  if (relative.trim().isEmpty) return null;
  if (p.isAbsolute(relative) || p.posix.isAbsolute(relative)) return null;
  final normalizedRoot = p.normalize(p.absolute(root));
  final resolved = p.normalize(p.join(normalizedRoot, relative));
  if (resolved == normalizedRoot || p.isWithin(normalizedRoot, resolved)) {
    return resolved;
  }
  return null;
}

/// Whether [child] is [parent] or lies inside it. Both are `/`-separated
/// relative paths.
bool isSameOrWithin(String parent, String child) {
  final a = normalizeRelative(parent);
  final b = normalizeRelative(child);
  if (a == '.' || a.isEmpty) return true;
  return b == a || b.startsWith('$a/');
}

/// Normalizes a configured relative path to `/` form without `./` or a
/// trailing slash.
String normalizeRelative(String value) {
  var result = toPosix(value.trim());
  while (result.length > 1 && result.endsWith('/')) {
    result = result.substring(0, result.length - 1);
  }
  return p.posix.normalize(result);
}
