/// A minimal glob matcher for `/`-separated relative paths.
///
/// Supports `*` (any characters except `/`), `?` (one character except `/`)
/// and `**` (any number of path segments, including none).
class Glob {
  /// Compiles [pattern].
  Glob(this.pattern) : _regex = _compile(pattern);

  /// The source pattern.
  final String pattern;
  final RegExp _regex;

  /// Whether [pattern] contains wildcard characters.
  bool get hasWildcards => pattern.contains('*') || pattern.contains('?');

  /// Whether [path] matches this glob.
  bool matches(String path) => _regex.hasMatch(path);

  static RegExp _compile(String pattern) {
    final buffer = StringBuffer('^');
    for (var i = 0; i < pattern.length; i++) {
      final char = pattern[i];
      if (char == '*') {
        final isDouble = i + 1 < pattern.length && pattern[i + 1] == '*';
        if (isDouble) {
          final followedBySlash =
              i + 2 < pattern.length && pattern[i + 2] == '/';
          if (followedBySlash) {
            buffer.write('(?:.*/)?');
            i += 2;
          } else {
            buffer.write('.*');
            i += 1;
          }
        } else {
          buffer.write('[^/]*');
        }
      } else if (char == '?') {
        buffer.write('[^/]');
      } else {
        buffer.write(RegExp.escape(char));
      }
    }
    buffer.write(r'$');
    return RegExp(buffer.toString());
  }

  @override
  String toString() => pattern;
}
