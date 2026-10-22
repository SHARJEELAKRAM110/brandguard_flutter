/// Precomputed line starts for repeated offset-to-line lookups.
class LineIndex {
  /// Indexes [text].
  LineIndex(String text) {
    _starts.add(0);
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) _starts.add(i + 1);
    }
  }

  final List<int> _starts = [];

  /// Returns the 1-based line containing [offset].
  int lineOf(int offset) {
    var low = 0;
    var high = _starts.length - 1;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (_starts[mid] <= offset) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low + 1;
  }
}

/// Returns the index of the `}` matching the `{` at [openIndex], honouring
/// double- and single-quoted strings, or `-1` when unbalanced.
int matchingBrace(String text, int openIndex, {bool singleQuotes = true}) {
  var depth = 0;
  String? quote;
  for (var i = openIndex; i < text.length; i++) {
    final char = text[i];
    if (quote != null) {
      if (char == r'\') {
        i++;
      } else if (char == quote) {
        quote = null;
      }
      continue;
    }
    if (char == '"' || (singleQuotes && char == "'")) {
      quote = char;
    } else if (char == '{') {
      depth++;
    } else if (char == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// Replaces `//` and `/* */` comments with spaces, keeping newlines and
/// string literals intact so offsets still map to the original text.
String blankComments(String text) {
  final out = StringBuffer();
  String? quote;
  var i = 0;
  while (i < text.length) {
    final char = text[i];
    if (quote != null) {
      out.write(char);
      if (char == r'\' && i + 1 < text.length) {
        out.write(text[i + 1]);
        i += 2;
        continue;
      }
      if (char == quote || char == '\n') quote = null;
      i++;
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      out.write(char);
      i++;
      continue;
    }
    if (char == '/' && i + 1 < text.length && text[i + 1] == '/') {
      while (i < text.length && text[i] != '\n') {
        out.write(' ');
        i++;
      }
      continue;
    }
    if (char == '/' && i + 1 < text.length && text[i + 1] == '*') {
      final end = text.indexOf('*/', i + 2);
      final stop = end == -1 ? text.length : end + 2;
      for (var j = i; j < stop; j++) {
        out.write(text[j] == '\n' ? '\n' : ' ');
      }
      i = stop;
      continue;
    }
    out.write(char);
    i++;
  }
  return out.toString();
}

/// Replaces the contents of every nested `{ ... }` block in [text] with
/// spaces (keeping newlines), leaving only top-level statements visible.
String blankNestedBlocks(String text) {
  final out = StringBuffer();
  var depth = 0;
  String? quote;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (quote != null) {
      out.write(depth > 0 && char != '\n' ? ' ' : char);
      if (char == r'\' && i + 1 < text.length) {
        i++;
        out.write(depth > 0 && text[i] != '\n' ? ' ' : text[i]);
      } else if (char == quote || char == '\n') {
        quote = null;
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      out.write(depth > 0 ? ' ' : char);
    } else if (char == '{') {
      depth++;
      out.write(' ');
    } else if (char == '}') {
      if (depth > 0) depth--;
      out.write(' ');
    } else {
      out.write(depth > 0 && char != '\n' ? ' ' : char);
    }
  }
  return out.toString();
}

/// Decodes the predefined XML entities and numeric character references.
String decodeXmlText(String value) => value
    .replaceAllMapped(
      RegExp(r'&#x([0-9a-fA-F]+);'),
      (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)),
    )
    .replaceAllMapped(
      RegExp(r'&#([0-9]+);'),
      (m) => String.fromCharCode(int.parse(m[1]!)),
    )
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');
