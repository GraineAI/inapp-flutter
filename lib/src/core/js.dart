/// JAVASCRIPT'S OWN COERCIONS, for values decoded from JSON.
///
/// Several of the React Native SDK's rules lean on `String(x)`, truthiness
/// and `x ?? y`. A port that used Dart's equivalents would agree on every
/// ordinary input and differ on the odd one — a numeric price, a `null`
/// title — which is exactly where nobody looks. So the port is literal.
///
/// Dart has one null. JSON `null` and an absent key both read as `null`
/// here; the few places where JavaScript tells them apart (`"undefined"` vs
/// `"null"` inside a template string) check `containsKey` themselves.
abstract final class Js {
  /// `v === null || v === undefined`.
  static bool nullish(Object? v) => v == null;

  /// JavaScript truthiness.
  static bool truthy(Object? v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is String) return v.isNotEmpty;
    if (v is num) return !(v == 0 || v.isNaN);
    return true;
  }

  /// `String(v)`, with JSON `null` as `"null"`.
  static String str(Object? v) {
    if (v == null) return 'null';
    if (v is String) return v;
    if (v is bool) return v.toString();
    if (v is int) return v.toString();
    if (v is num) return number(v.toDouble());
    if (v is Map) return '[object Object]';
    if (v is Iterable) {
      return v.map((Object? x) => x == null ? '' : str(x)).join(',');
    }
    return v.toString();
  }

  /// `String(v ?? "")` — the idiom every allowlist in the RN SDK reads through.
  static String strOrEmpty(Object? v) => v == null ? '' : str(v);

  /// `typeof v === "number" && Number.isFinite(v)`, as the number.
  static double? finite(Object? v) {
    if (v is! num) return null;
    final d = v.toDouble();
    return d.isFinite ? d : null;
  }

  /// `Math.round`: half rounds up, toward +∞, as JavaScript does.
  static double round(double d) => (d + 0.5).floorToDouble();

  /// `Number.prototype.toString()`: no ".0" on an integer, and the same
  /// exponent thresholds (1e-6 and 1e21) — which Dart's own `toString`
  /// already shares, apart from the ".0" it adds to integral values.
  static String number(double d) {
    if (d.isNaN) return 'NaN';
    if (d.isInfinite) return d > 0 ? 'Infinity' : '-Infinity';
    if (d == 0) return '0';
    final s = d.toString();
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  /// `a ?? b ?? …`: the first value that is neither undefined nor null.
  static Object? firstDefined(List<Object?> values) {
    for (final v in values) {
      if (v != null) return v;
    }
    return null;
  }

  /// `String(v || fallback)`.
  static String or(Object? v, String fallback) => truthy(v) ? str(v) : fallback;

  /// A JSON object as a `Map<String, Object?>`, or null when it is not one.
  static Map<String, Object?>? asMap(Object? v) {
    if (v is! Map) return null;
    return <String, Object?>{
      for (final e in v.entries) e.key.toString(): e.value,
    };
  }

  /// A JSON array as a list, or an empty list when it is not one.
  static List<Object?> asList(Object? v) =>
      v is List ? List<Object?>.of(v) : const <Object?>[];
}
