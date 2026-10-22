/// An argument referenced by an ICU message, e.g. `{name}` or
/// `{count, plural, one{...} other{...}}`.
class IcuArgument {
  /// Creates an argument description.
  const IcuArgument(this.name, this.kind, {this.cases = const {}});

  /// Argument name.
  final String name;

  /// `simple`, `plural`, `select`, `selectordinal`, or a format type such as
  /// `number` or `date`.
  final String kind;

  /// Case selectors for `plural`, `select` and `selectordinal` arguments.
  final Set<String> cases;

  /// Whether this argument chooses between sub-messages.
  bool get isChoice =>
      kind == 'plural' || kind == 'select' || kind == 'selectordinal';
}

/// The arguments of a parsed ICU message.
class IcuMessage {
  IcuMessage._(this.arguments, this.error);

  /// Parses [message] the way Flutter's `gen-l10n` does by default (without
  /// `use-escaping`).
  factory IcuMessage.parse(String message) {
    final parser = _Parser();
    parser.parse(message);
    return IcuMessage._(Map.unmodifiable(parser.arguments), parser.error);
  }

  /// Arguments keyed by name. Repeated arguments keep their first kind.
  final Map<String, IcuArgument> arguments;

  /// A syntax error, or `null` when the message is well-formed.
  final String? error;
}

final _simpleArg = RegExp(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*$');
final _choiceArg = RegExp(
  r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*,\s*(plural|select|selectordinal)\s*,(.*)$',
  dotAll: true,
);
final _formattedArg = RegExp(
  r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*,\s*([A-Za-z]+)\s*(,.*)?$',
  dotAll: true,
);
final _caseSelector = RegExp(r'\s*(offset:\s*\d+\s*)?(=?[A-Za-z0-9_-]+)\s*\{');

class _Parser {
  final Map<String, IcuArgument> arguments = {};
  String? error;

  void parse(String text) {
    var i = 0;
    while (i < text.length && error == null) {
      final char = text[i];
      if (char == '{') {
        final end = _match(text, i);
        if (end == -1) {
          error = 'Unbalanced `{` in message.';
          return;
        }
        _argument(text.substring(i + 1, end));
        i = end + 1;
      } else if (char == '}') {
        error = 'Unbalanced `}` in message.';
        return;
      } else {
        i++;
      }
    }
  }

  void _argument(String inner) {
    final simple = _simpleArg.firstMatch(inner);
    if (simple != null) {
      _add(IcuArgument(simple[1]!, 'simple'));
      return;
    }
    final choice = _choiceArg.firstMatch(inner);
    if (choice != null) {
      final cases = <String>{};
      final body = choice[3]!;
      var position = 0;
      while (position < body.length && error == null) {
        if (body.substring(position).trim().isEmpty) break;
        final selector = _caseSelector.matchAsPrefix(body, position);
        if (selector == null) {
          error = 'Malformed `${choice[2]}` cases for argument `${choice[1]}`.';
          return;
        }
        final open = selector.end - 1;
        final close = _match(body, open);
        if (close == -1) {
          error = 'Unbalanced `{` in `${choice[1]}` case `${selector[2]}`.';
          return;
        }
        cases.add(selector[2]!);
        parse(body.substring(open + 1, close));
        position = close + 1;
      }
      _add(IcuArgument(choice[1]!, choice[2]!, cases: cases));
      return;
    }
    final formatted = _formattedArg.firstMatch(inner);
    if (formatted != null) {
      _add(IcuArgument(formatted[1]!, formatted[2]!));
      return;
    }
    error = 'Unrecognized placeholder syntax `{${inner.trim()}}`.';
  }

  void _add(IcuArgument argument) {
    final existing = arguments[argument.name];
    // A plural/select argument usually repeats as `{count}` inside its own
    // cases, which are parsed first; the choice kind must win.
    if (existing == null || (!existing.isChoice && argument.isChoice)) {
      arguments[argument.name] = argument;
    }
  }

  static int _match(String text, int open) {
    var depth = 0;
    for (var i = open; i < text.length; i++) {
      if (text[i] == '{') depth++;
      if (text[i] == '}') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }
}
