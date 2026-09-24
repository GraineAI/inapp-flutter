import 'context.dart';
import 'js.dart';

/// Per-screen friction overrides, keyed by the screen id the app reports.
class FrictionScreenRule {
  const FrictionScreenRule({this.ignore, this.idleAfterMs, this.message});

  /// No friction detection at all on this screen — someone reading terms is not stuck.
  final bool? ignore;
  final int? idleAfterMs;
  final String? message;
}

/// The app's layer of friction rules, over the dashboard's (Embed & Widgets →
/// friction, served with the session) over the built-in defaults. Every field
/// is optional; null means "inherit the layer below". Only the idle rule
/// (stalled_on_step) is ported; `idleAfterMs` of 0 or less switches it off.
class FrictionConfig {
  const FrictionConfig({
    this.enabled,
    this.idleAfterMs,
    this.cooldownMs,
    this.cooldownSeconds,
    this.maxPerSession,
    this.openLauncher,
    this.message,
    this.requireOutstandingField,
    this.screens = const <String, FrictionScreenRule>{},
  });

  final bool? enabled;

  /// On the same screen this long → stalled_on_step. Default 45s; 0 or less is off.
  final int? idleAfterMs;

  /// Minimum gap between two signals on the same screen. Default 60s.
  final int? cooldownMs;

  /// Runtime pacing for the agent's unsolicited interventions. Defaults 20s / 3.
  final int? cooldownSeconds;
  final int? maxPerSession;

  /// Carried to GraineListener.onFriction for a host that opens its own launcher.
  final bool? openLauncher;

  /// What the agent is told instead of the built-in sentence:
  /// {title} {screen} {seconds} {field} {error}.
  final String? message;

  /// Fire only while a field is outstanding (invalid, or empty and not
  /// optional), with the clock running from when it became so. Default true.
  /// False is the React Native SDK's rule: idle on the screen at all.
  final bool? requireOutstandingField;
  final Map<String, FrictionScreenRule> screens;

  static final RegExp _numeric =
      RegExp(r'^[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?$');

  /// A positive number, or a string holding one — a hand-edited JSON
  /// document says both.
  static double? _num(Object? v) {
    double? d;
    if (v is num) {
      d = v.toDouble();
    } else if (v is String) {
      final t = v.trim();
      if (_numeric.hasMatch(t)) d = double.parse(t);
    }
    return (d != null && d.isFinite && d > 0) ? d : null;
  }

  /// `false` is off (0); an object's `afterMs` is the time; anything else inherits.
  static int? _idle(Object? v) {
    if (v == false) return 0;
    if (v is Map) return _num(v['afterMs'])?.toInt();
    return null;
  }

  static String? _text(Object? v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  /// The dashboard's layer, from the session's `friction` object. Unknown
  /// keys are dropped.
  static FrictionConfig? fromJson(Map<String, Object?>? o) {
    if (o == null) return null;
    final nudge = Js.asMap(o['nudge']);
    final screens = <String, FrictionScreenRule>{};
    final s = Js.asMap(o['screens']);
    if (s != null) {
      s.forEach((String id, Object? raw) {
        final r = Js.asMap(raw);
        if (id.isEmpty || r == null) return;
        screens[id] = FrictionScreenRule(
          ignore: r['ignore'] == true ? true : null,
          idleAfterMs: _idle(r['idle']),
          message: _text(r['message']),
        );
      });
    }
    return FrictionConfig(
      enabled: o['enabled'] is bool ? o['enabled'] as bool : null,
      idleAfterMs: _idle(o['idle']),
      cooldownMs: _num(o['cooldownMs'])?.toInt(),
      cooldownSeconds: _num(nudge?['cooldownSeconds'])?.toInt(),
      maxPerSession: _num(nudge?['maxPerSession'])?.toInt(),
      openLauncher: nudge?['openLauncher'] is bool ? nudge!['openLauncher'] as bool : null,
      message: _text(o['message']),
      requireOutstandingField: o['requireOutstandingField'] is bool
          ? o['requireOutstandingField'] as bool
          : null,
      screens: screens,
    );
  }
}

/// The rules on one screen.
class FrictionForScreen {
  const FrictionForScreen(
      {required this.ignore, required this.idleAfterMs, required this.message});
  final bool ignore;
  final int? idleAfterMs;
  final String message;
}

/// Every layer applied: what is actually in force.
class FrictionRules {
  const FrictionRules({
    this.enabled = true,
    this.idleAfterMs = 45000,
    this.cooldownMs = 60000,
    this.cooldownSeconds = 20,
    this.maxPerSession = 3,
    this.openLauncher = false,
    this.message = '',
    this.requireOutstandingField = true,
    this.screens = const <String, FrictionScreenRule>{},
  });

  final bool enabled;

  /// Null: the idle rule is off.
  final int? idleAfterMs;
  final int cooldownMs;
  final int cooldownSeconds;
  final int maxPerSession;
  final bool openLauncher;
  final String message;
  final bool requireOutstandingField;
  final Map<String, FrictionScreenRule> screens;

  /// The rules on one screen: the top level with that screen's overrides on it.
  FrictionForScreen forScreen(String? id) {
    final over = id == null ? null : screens[id];
    final o = over?.idleAfterMs;
    final idle = o == null ? idleAfterMs : (o > 0 ? o : null);
    return FrictionForScreen(
      ignore: over?.ignore ?? false,
      idleAfterMs: idle,
      message: over?.message ?? message,
    );
  }
}

abstract final class Friction {
  /// Defaults ← each layer in order, each changing only what it names.
  static FrictionRules resolve(List<FrictionConfig?> layers) {
    var r = const FrictionRules();
    for (final l in layers) {
      if (l == null) continue;
      final screens = Map<String, FrictionScreenRule>.of(r.screens);
      l.screens.forEach((String id, FrictionScreenRule s) {
        final cur = screens[id];
        screens[id] = FrictionScreenRule(
          ignore: s.ignore ?? cur?.ignore,
          idleAfterMs: s.idleAfterMs ?? cur?.idleAfterMs,
          message: s.message ?? cur?.message,
        );
      });
      final i = l.idleAfterMs;
      r = FrictionRules(
        enabled: l.enabled ?? r.enabled,
        idleAfterMs: i == null ? r.idleAfterMs : (i > 0 ? i : null),
        cooldownMs: _positive(l.cooldownMs) ?? r.cooldownMs,
        cooldownSeconds: _positive(l.cooldownSeconds) ?? r.cooldownSeconds,
        maxPerSession: _positive(l.maxPerSession) ?? r.maxPerSession,
        openLauncher: l.openLauncher ?? r.openLauncher,
        message: l.message ?? r.message,
        requireOutstandingField:
            l.requireOutstandingField ?? r.requireOutstandingField,
        screens: screens,
      );
    }
    return r;
  }

  static int? _positive(int? v) => (v != null && v > 0) ? v : null;
}

/// The customer looks stuck. [detail] is plain English, given to the agent verbatim.
class FrictionSignal {
  const FrictionSignal({
    required this.name,
    required this.screen,
    required this.detail,
    required this.data,
    required this.cooldownSeconds,
    required this.maxPerSession,
    required this.openLauncher,
  });

  final String name;
  final String screen;
  final String detail;
  final Map<String, Object?> data;
  final int cooldownSeconds;
  final int maxPerSession;
  final bool openLauncher;
}

/// STALLED ON A STEP — the idle half of the React Native SDK's friction
/// detector, with time as an argument so every rule is a plain test.
///
/// The clock is per screen VISIT: a field edit on the same screen does not
/// restart it (a customer typing one character every forty seconds is
/// exactly who is stuck); a different screen, or [onInteraction], does. It
/// fires at most once per visit, and never twice on one screen inside the
/// cooldown.
///
/// Two gates the React Native rule does not have, each on by default in the
/// SDK and off here so the RN rule itself stays provable:
///  - [FrictionRules.requireOutstandingField]: the clock runs only while a
///    field is outstanding, from the moment it became so.
///  - `gateOnCall`: the clock runs only while a call is live, from when it
///    connected — so the one signal per visit is spent on a conversation
///    that can hear it.
class FrictionDetector {
  FrictionDetector({FrictionRules rules = const FrictionRules(), bool gateOnCall = false})
      : _rules = rules,
        _gateOnCall = gateOnCall;

  FrictionRules _rules;
  final bool _gateOnCall;
  GraineScreen? _screen;
  int _screenSince = 0;
  int? _stuckSince;
  int? _callSince;
  String? _idleFiredFor;
  final Map<String, int> _lastSignalAt = <String, int>{};

  FrictionRules get rules => _rules;

  void configure(FrictionRules next) => _rules = next;

  /// The app reported a screen. A different id is a new visit; the same id is an update.
  void onScreen(GraineScreen? next, int now) {
    final prev = _screen;
    _screen = next;
    if (next == null) {
      _stuckSince = null;
      return;
    }
    if (prev == null || prev.screen != next.screen) {
      _screenSince = now;
      _idleFiredFor = null;
      _stuckSince = null;
    }
    _stuckSince = outstanding(next.fields).isEmpty ? null : (_stuckSince ?? now);
  }

  /// The customer did something — the idle clock restarts.
  void onInteraction(int now) => _screenSince = now;

  /// A call connected or ended. Only read when the detector is gated on a call.
  void onCall(bool live, int now) {
    if (live && _callSince == null) {
      _callSince = now;
      _idleFiredFor = null;
    }
    if (!live) _callSince = null;
  }

  FrictionForScreen? _active() {
    final s = _screen;
    if (s == null || !_rules.enabled) return null;
    final r = _rules.forScreen(s.screen);
    return r.ignore ? null : r;
  }

  int? _startedAt() {
    var start = _screenSince;
    if (_rules.requireOutstandingField) {
      final stuck = _stuckSince;
      if (stuck == null) return null;
      if (stuck > start) start = stuck;
    }
    if (_gateOnCall) {
      final call = _callSince;
      if (call == null) return null;
      if (call > start) start = call;
    }
    return start;
  }

  /// How long until the idle rule should fire, or null if it should not.
  int? idleDueIn(int now) {
    final r = _active();
    if (r == null) return null;
    final after = r.idleAfterMs;
    if (after == null) return null;
    if (_idleFiredFor == _screen?.screen) return null;
    final start = _startedAt();
    if (start == null) return null;
    final due = after - (now - start);
    return due < 0 ? 0 : due;
  }

  /// The idle timer went off. At most once per visit.
  FrictionSignal? onIdle(int now) {
    final r = _active();
    if (r == null) return null;
    final after = r.idleAfterMs;
    if (after == null) return null;
    final s = _screen;
    if (s == null) return null;
    if (_idleFiredFor == s.screen) return null;
    final start = _startedAt();
    if (start == null) return null;
    if (now - start < after) return null;
    _idleFiredFor = s.screen;

    final last = _lastSignalAt[s.screen];
    if (last != null && now - last < _rules.cooldownMs) return null;
    _lastSignalAt[s.screen] = now;

    final pool = _rules.requireOutstandingField ? outstanding(s.fields) : s.fields;
    GraineField? stuck;
    for (final f in pool) {
      if (f.status == FieldStatus.invalid || Js.truthy(f.error)) {
        stuck = f;
        break;
      }
    }
    if (stuck == null) {
      for (final f in pool) {
        if (f.status == FieldStatus.empty) {
          stuck = f;
          break;
        }
      }
    }
    final seconds = Js.round(after / 1000.0).toInt();
    final vars = <String, Object?>{
      'seconds': seconds,
      'field': stuck == null ? '' : (stuck.label ?? stuck.name),
      'error': stuck == null ? '' : (stuck.error ?? stuck.status?.wire ?? ''),
    };
    final all = <String, Object?>{
      'title': s.title ?? s.screen,
      'screen': s.screen,
      ...vars,
    };
    final fallback = stuck != null
        ? 'The customer has not touched the "{title}" screen for {seconds}s. The "{field}" field is ' +
            (Js.truthy(stuck.error) ? 'showing: {error}' : '{error}') +
            '.'
        : 'The customer has not touched the "{title}" screen for {seconds}s.';
    return FrictionSignal(
      name: 'stalled_on_step',
      screen: s.screen,
      detail: fill(r.message.isNotEmpty ? r.message : fallback, all),
      data: vars,
      cooldownSeconds: _rules.cooldownSeconds,
      maxPerSession: _rules.maxPerSession,
      openLauncher: _rules.openLauncher,
    );
  }

  /// What the customer still has to deal with. `locked` is not theirs to fix
  /// and `optional` not theirs to have to; an explicit error outranks `optional`.
  static List<GraineField> outstanding(List<GraineField> fields) => fields
      .where((GraineField f) =>
          Js.truthy(f.error) ||
          (!f.optional &&
              (f.status == FieldStatus.invalid || f.status == FieldStatus.empty)))
      .toList();

  static final RegExp _var = RegExp(r'\{(\w+)\}');

  /// Fill {name} placeholders; an unknown one is empty.
  static String fill(String template, Map<String, Object?> vars) =>
      template.replaceAllMapped(_var, (Match m) {
        final v = vars[m[1]];
        return v == null ? '' : Js.str(v);
      });
}
