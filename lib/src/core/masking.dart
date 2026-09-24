/// WHAT NEVER LEAVES THE DEVICE UNMASKED.
///
/// The same five rules, in the same order, with the same tokens, as the React
/// Native SDK (sdk/inapp/mask.ts) and the Android SDK. Order is load-bearing:
/// a card number must be caught as a card before a twelve-digit run inside it
/// can be caught as an Aadhaar, and an Indian mobile in +91 form must be a
/// phone before the Aadhaar rule can claim it. Pinned to the RN SDK's own
/// answers by sdk/contract/fixtures.json.
///
/// No lookbehind — the leading boundary is captured as group 1 and put back,
/// exactly as the RN rules do it. Dart's RegExp has JavaScript semantics, so
/// `\w`, `\d`, `\s` and `\b` mean what they mean in the RN SDK.
abstract final class Masking {
  static final List<_Rule> _builtIn = <_Rule>[
    _Rule(RegExp(r'\b[A-Z]{5}[0-9]{4}[A-Z]\b'), (Match m) => '[PAN]'),
    _Rule(RegExp(r'[\w.+-]+@[\w-]+\.[\w.]{2,}'), (Match m) => '[EMAIL]'),
    _Rule(RegExp(r'(^|[^\d-])((?:\d[ -]?){13,19})(?![\d-])'),
        (Match m) => '${m[1] ?? ''}[CARD]'),
    // The trailing (?!\d) matters: without it this eats the first ten digits
    // of a twelve-digit Aadhaar and leaves the last two in the payload.
    _Rule(RegExp(r'(^|[^\d+])((?:\+91[-\s]?)?[6-9]\d{9})(?!\d)'),
        (Match m) => '${m[1] ?? ''}[PHONE]'),
    _Rule(RegExp(r'(^|[^\d+])(\d{4}\s?\d{4}\s?\d{4})(?!\d)'),
        (Match m) => '${m[1] ?? ''}[AADHAAR]'),
  ];

  static final List<_Rule> _custom = <_Rule>[];

  /// Replace identifiers in one string: the five built-in rules, then the
  /// app's own ([addRule]).
  static String mask(String input) {
    var out = input;
    for (final rule in _builtIn) {
      out = out.replaceAllMapped(rule.pattern, rule.replace);
    }
    for (final rule in _custom) {
      out = out.replaceAllMapped(rule.pattern, rule.replace);
    }
    return out;
  }

  /// A rule for a field shape only your app knows — an account number, a
  /// policy id. Every match is replaced (Dart's replaceAll is always global,
  /// which is what the RN SDK forces). `token` may use JavaScript's
  /// replacement patterns — `$1`, `$&`, `$$`, `$<name>` — as it would there.
  static void addRule(RegExp pattern, [String token = '[REDACTED]']) {
    _custom.add(_Rule(pattern, (Match m) => expandReplacement(token, m)));
  }

  /// Only for tests — production code registers rules once, at startup.
  static void clearCustomRules() => _custom.clear();

  /// Masks every string anywhere inside a JSON value. Keys are not masked;
  /// values are. Numbers and booleans are left as they are — the agent
  /// reasons about amounts and timestamps.
  static Object? deep(Object? value) {
    if (value is String) return mask(value);
    if (value is Map) {
      return <String, Object?>{
        for (final e in value.entries) e.key.toString(): deep(e.value),
      };
    }
    if (value is Iterable) return <Object?>[for (final v in value) deep(v)];
    return value;
  }

  /// JavaScript's `GetSubstitution`: what `String.prototype.replace` does
  /// with `$` in a replacement string, so a custom rule written for the RN
  /// SDK means the same thing here.
  static String expandReplacement(String token, Match m) {
    if (!token.contains(r'$')) return token;
    final names = m is RegExpMatch ? m.groupNames.toSet() : const <String>{};
    final out = StringBuffer();
    var i = 0;
    while (i < token.length) {
      final c = token[i];
      if (c != r'$' || i + 1 >= token.length) {
        out.write(c);
        i++;
        continue;
      }
      final n = token[i + 1];
      if (n == r'$') {
        out.write(r'$');
        i += 2;
      } else if (n == '&') {
        out.write(m[0]);
        i += 2;
      } else if (n == '`') {
        out.write(m.input.substring(0, m.start));
        i += 2;
      } else if (n == "'") {
        out.write(m.input.substring(m.end));
        i += 2;
      } else if (_isDigit(n)) {
        if (i + 2 < token.length && _isDigit(token[i + 2])) {
          final nn = int.parse(token.substring(i + 1, i + 3));
          if (nn >= 1 && nn <= m.groupCount) {
            out.write(m.group(nn) ?? '');
            i += 3;
            continue;
          }
        }
        final d = int.parse(n);
        if (d >= 1 && d <= m.groupCount) {
          out.write(m.group(d) ?? '');
        } else {
          out.write(r'$');
          out.write(n);
        }
        i += 2;
      } else if (n == '<' && names.isNotEmpty) {
        final close = token.indexOf('>', i + 2);
        if (close < 0) {
          out.write(r'$<');
          i += 2;
        } else {
          final name = token.substring(i + 2, close);
          if (names.contains(name)) {
            out.write((m as RegExpMatch).namedGroup(name) ?? '');
          }
          i = close + 1;
        }
      } else {
        out.write(r'$');
        i++;
      }
    }
    return out.toString();
  }

  static bool _isDigit(String c) =>
      c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;
}

class _Rule {
  _Rule(this.pattern, this.replace);
  final RegExp pattern;
  final String Function(Match) replace;
}
