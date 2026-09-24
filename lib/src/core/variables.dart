import 'masking.dart';

/// THE PROMPT'S {variables}, from every place they can come from, in one view.
///
///   1. the agent's defaults from the dashboard (Embed & Widgets → Variables)
///   2. what the app knows at build time (GraineConfig.variables)
///   3. what the app learns while it runs (setVariables)
///   4. who is signed in (identify) — last, so a person beats a default
///
/// Every value is a string, because it is substituted into a sentence:
/// numbers and booleans are flattened (an integer never gains ".0"), nested
/// maps and lists are dropped (they would render as a repr inside the agent's
/// first line). Runtime values and identity are masked on the way in, like
/// everything else the app hands over.
class VariableStore {
  VariableStore([Map<String, Object?> buildTime = const <String, Object?>{}])
      : _buildTime = flatten(buildTime);

  final Map<String, String> _buildTime;
  Map<String, String> _dashboard = const <String, String>{};
  Map<String, String> _runtime = const <String, String>{};
  Map<String, String> _identity = const <String, String>{};

  void setDashboardDefaults(Map<String, Object?> values) {
    _dashboard = flatten(values);
  }

  /// Merged over what is there. `null` under a key removes it; `null` for the
  /// whole map clears.
  void setRuntime(Map<String, Object?>? values) {
    if (values == null) {
      _runtime = const <String, String>{};
      return;
    }
    final next = Map<String, String>.of(_runtime);
    values.forEach((String k, Object? v) {
      if (k.isEmpty) return;
      if (v == null) {
        next.remove(k);
        return;
      }
      final flat = flattenOne(v);
      if (flat != null) next[k] = Masking.mask(flat);
    });
    _runtime = next;
  }

  /// Who is signed in. `null` on sign-out clears it.
  void setIdentity(Map<String, Object?>? traits) {
    _identity = traits == null
        ? const <String, String>{}
        : flatten(traits).map(
            (String k, String v) => MapEntry<String, String>(k, Masking.mask(v)));
  }

  /// Who is signed in, masked.
  Map<String, String> identity() => Map<String, String>.unmodifiable(_identity);

  /// Every variable, in precedence order.
  Map<String, String> merged() => <String, String>{
        ..._dashboard,
        ..._buildTime,
        ..._runtime,
        ..._identity,
      };

  static Map<String, String> flatten(Map<String, Object?> values) {
    final out = <String, String>{};
    values.forEach((String k, Object? v) {
      if (k.isEmpty) return;
      final flat = flattenOne(v);
      if (flat != null) out[k] = flat;
    });
    return out;
  }

  /// One value as the string a prompt substitutes, or null to drop it.
  static String? flattenOne(Object? v) {
    if (v == null) return null;
    if (v is String) return v;
    if (v is bool) return v.toString();
    if (v is int) return v.toString();
    if (v is num) {
      final d = v.toDouble();
      if (d.isFinite && d == d.floorToDouble() && d.abs() < 1e15) {
        return d.toInt().toString();
      }
      return d.toString();
    }
    if (v is Map || v is Iterable) return null;
    return v.toString();
  }
}
