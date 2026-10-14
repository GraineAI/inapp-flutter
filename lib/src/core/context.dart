import 'dart:async';

import 'masking.dart';
import 'protocol.dart';

/// What an action handler's answer means to the agent.
enum ActionStatus {
  ok('ok'),
  refused('refused'),
  error('error');

  const ActionStatus(this.wire);
  final String wire;
}

/// What an action handler answers. The agent speaks about exactly this, so
/// tell the truth: "ok" makes the agent say the thing is done, and a refusal
/// with a reason is often the most useful thing it can pass on.
class ActionResult {
  const ActionResult(this.status,
      {this.message = '', this.data = const <String, Object?>{}});

  const ActionResult.ok(
      [this.message = '', this.data = const <String, Object?>{}])
      : status = ActionStatus.ok;

  const ActionResult.refused(this.message)
      : status = ActionStatus.refused,
        data = const <String, Object?>{};

  const ActionResult.error(this.message)
      : status = ActionStatus.error,
        data = const <String, Object?>{};

  final ActionStatus status;
  final String message;
  final Map<String, Object?> data;

  @override
  bool operator ==(Object other) =>
      other is ActionResult &&
      other.status == status &&
      other.message == message &&
      deepEquals(other.data, data);

  @override
  int get hashCode => Object.hash(status, message, deepHash(data));

  @override
  String toString() => 'ActionResult(${status.wire}, "$message")';
}

/// A handler for one thing the agent may do in the app. It may answer
/// synchronously or with a Future; returning null means "ok".
typedef GraineActionHandler = FutureOr<ActionResult?> Function(
    Map<String, Object?> args);

/// How an input on a screen is doing.
enum FieldStatus {
  empty('empty'),
  filled('filled'),
  invalid('invalid'),
  pending('pending'),
  locked('locked');

  const FieldStatus(this.wire);
  final String wire;

  static FieldStatus? fromWire(String? s) {
    for (final v in values) {
      if (v.wire == s) return v;
    }
    return null;
  }
}

/// One input on a screen, as the agent should understand it.
class GraineField {
  const GraineField(this.name,
      {this.label, this.value, this.status, this.error, this.optional = false});

  final String name;
  final String? label;

  /// The real value. Masking runs on the way out.
  final String? value;
  final FieldStatus? status;

  /// The validation message actually shown — what the agent can offer to fix.
  final String? error;

  /// Leaving this one blank is fine: kept in the frame, out of the count.
  final bool optional;

  @override
  bool operator ==(Object other) =>
      other is GraineField &&
      other.name == name &&
      other.label == label &&
      other.value == value &&
      other.status == status &&
      other.error == error &&
      other.optional == optional;

  @override
  int get hashCode => Object.hash(name, label, value, status, error, optional);
}

/// Where a screen sits in a flow, and where the flow goes next.
class GraineJourney {
  const GraineJourney(this.name, {this.step, this.of, this.next});

  final String name;
  final int? step;
  final int? of;

  /// What happens after this step — asked, the agent repeats it rather than
  /// inventing one.
  final String? next;

  @override
  bool operator ==(Object other) =>
      other is GraineJourney &&
      other.name == name &&
      other.step == step &&
      other.of == of &&
      other.next == next;

  @override
  int get hashCode => Object.hash(name, step, of, next);
}

/// What the customer is looking at. `status` on each field is what makes the
/// agent proactive: after a pause it names the field that is `invalid` or
/// `empty` instead of asking "need a hand?".
///
/// Report real values. Masking runs on the way out; a screen that pre-redacts
/// only blinds the agent.
class GraineScreen {
  const GraineScreen(
    this.screen, {
    this.title,
    this.journey,
    this.fields = const <GraineField>[],
    this.error,
    this.data = const <String, Object?>{},
    this.availableActions,
  });

  /// Stable id for the screen — used for analytics, so keep it constant.
  final String screen;
  final String? title;
  final GraineJourney? journey;
  final List<GraineField> fields;

  /// A screen-level error banner, distinct from a per-field one.
  final String? error;

  /// Anything else the agent should know.
  final Map<String, Object?> data;

  /// Which actions work HERE. Null allows everything registered.
  final List<String>? availableActions;

  /// This screen with [fields] in place of its own.
  GraineScreen copyWith({List<GraineField>? fields}) => GraineScreen(
        screen,
        title: title,
        journey: journey,
        fields: fields ?? this.fields,
        error: error,
        data: data,
        availableActions: availableActions,
      );

  /// This screen with [field] in place of the field of the same name — or
  /// added, after the others, when it has none.
  GraineScreen withField(GraineField field) {
    final i = fields.indexWhere((GraineField f) => f.name == field.name);
    final next = List<GraineField>.of(fields);
    if (i >= 0) {
      next[i] = field;
    } else {
      next.add(field);
    }
    return copyWith(fields: next);
  }

  /// This screen without the field named [name] (itself when it has none).
  GraineScreen withoutField(String name) {
    if (!fields.any((GraineField f) => f.name == name)) return this;
    return copyWith(fields: <GraineField>[for (final f in fields) if (f.name != name) f]);
  }

  @override
  bool operator ==(Object other) =>
      other is GraineScreen &&
      other.screen == screen &&
      other.title == title &&
      other.journey == journey &&
      deepEquals(other.fields, fields) &&
      other.error == error &&
      deepEquals(other.data, data) &&
      deepEquals(other.availableActions, availableActions);

  @override
  int get hashCode => Object.hash(screen, title, journey, deepHash(fields),
      error, deepHash(data), deepHash(availableActions));
}

/// The context frame the runtime reads — the same keys as the React Native
/// SDK's buildContextFrame() and the Android SDK's ContextFrame, masked on
/// the way out.
abstract final class ContextFrame {
  /// `{context, availableActions?}`, or null when there is nothing to say.
  ///
  /// With [registeredActions] (what this build can actually do), the actions
  /// are the React Native SDK's intersection: the screen's stated list — or,
  /// when it states none, everything registered — narrowed to what is
  /// registered. A screen that states its actions is honoured exactly, `[]`
  /// included; a list empty only because nothing is registered is left out,
  /// so the dashboard's catalogue stands (an absent key is "everything
  /// declared"; `[]` is "nothing here" — opposite instructions). Without it,
  /// the screen's list goes as stated.
  static Map<String, Object?>? build({
    required GraineScreen? screen,
    required int screenSinceMs,
    required int nowMs,
    Map<String, String> identity = const <String, String>{},
    String? appVersion,
    List<Map<String, Object?>> recentEvents = const <Map<String, Object?>>[],
    List<String>? registeredActions,
  }) {
    if (screen == null && identity.isEmpty && recentEvents.isEmpty) return null;
    final ctx = <String, Object?>{};
    if (screen != null) {
      ctx['screen'] = screen.screen;
      if (screen.title != null) ctx['title'] = screen.title;
      final j = screen.journey;
      if (j != null) {
        ctx['journey'] = <String, Object?>{
          'name': j.name,
          if (j.step != null) 'step': j.step,
          if (j.of != null) 'of': j.of,
          if (j.next != null) 'next': j.next,
        };
      }
      if (screen.fields.isNotEmpty) {
        ctx['fields'] = <Object?>[
          for (final f in screen.fields)
            <String, Object?>{
              'name': f.name,
              if (f.label != null) 'label': f.label,
              if (f.value != null) 'value': f.value,
              if (f.status != null) 'status': f.status!.wire,
              if (f.error != null) 'error': f.error,
              if (f.optional) 'optional': true,
            },
        ];
      }
      if (screen.error != null) ctx['error'] = screen.error;
      if (screen.data.isNotEmpty) ctx['data'] = Protocol.toJson(screen.data);
      final idle = nowMs - screenSinceMs;
      ctx['idle_ms'] = idle < 0 ? 0 : idle;
    }
    if (identity.isNotEmpty) ctx['user'] = Map<String, Object?>.of(identity);
    if (appVersion != null) ctx['app_version'] = appVersion;
    if (recentEvents.isNotEmpty) {
      ctx['recent_events'] = <Object?>[
        for (final e in recentEvents) Protocol.toJson(e),
      ];
    }
    final available = availableActions(screen?.availableActions, registeredActions);
    return <String, Object?>{
      'context': Masking.deep(ctx),
      if (available != null) 'availableActions': available,
    };
  }

  /// The actions a frame offers — see [build]. Null: leave the key out.
  static List<String>? availableActions(List<String>? stated, List<String>? registered) {
    if (registered == null) return stated == null ? null : List<String>.of(stated);
    final usable = (stated ?? registered).where(registered.contains).toList();
    if (usable.isNotEmpty) return usable;
    if (stated != null) return const <String>[]; // the screen said so
    return null;
  }
}

/// THE ACTIONS THE AGENT MAY TAKE IN THIS APP, and the one way they are run.
///
/// Always answers — a handler that throws is `error`, a slow one is `error`
/// with a timeout message, an unknown one is `refused`. The agent is blocked
/// waiting, so silence is the one answer never given.
class ActionRegistry {
  ActionRegistry(
      {this.deadline = const Duration(milliseconds: Protocol.actionDeadlineMs)});

  /// How long a handler may take before the agent is told it was not done.
  final Duration deadline;
  final Map<String, GraineActionHandler> _handlers =
      <String, GraineActionHandler>{};

  /// Register [handler] under [name]; the returned function unregisters it
  /// (only if it is still the one registered).
  void Function() register(String name, GraineActionHandler handler) {
    _handlers[name] = handler;
    return () {
      if (identical(_handlers[name], handler)) _handlers.remove(name);
    };
  }

  /// Registered names, in registration order.
  List<String> get names => List<String>.unmodifiable(_handlers.keys);

  bool has(String name) => _handlers.containsKey(name);

  /// Run one action. [onRequested] fires first, [onCompleted] once with the
  /// answer the agent is given.
  Future<ActionResult> execute(
    String name,
    Map<String, Object?> args, {
    void Function(String name)? onRequested,
    void Function(String name, ActionResult result)? onCompleted,
  }) {
    onRequested?.call(name);
    final completer = Completer<ActionResult>();
    Timer? timer;
    void once(ActionResult r) {
      if (completer.isCompleted) return;
      timer?.cancel();
      completer.complete(r);
      onCompleted?.call(name, r);
    }

    final handler = _handlers[name];
    if (handler == null) {
      once(ActionResult.refused('This app build does not implement "$name".'));
      return completer.future;
    }
    timer = Timer(deadline, () {
      once(ActionResult.error(
          'The app did not answer within ${deadline.inMilliseconds ~/ 1000} seconds.'));
    });
    try {
      final out = handler(args);
      if (out is Future<ActionResult?>) {
        out.then((ActionResult? r) => once(r ?? const ActionResult.ok()),
            onError: (Object e, StackTrace _) => once(ActionResult.error(describeError(e))));
      } else {
        once(out ?? const ActionResult.ok());
      }
    } catch (e) {
      once(ActionResult.error(describeError(e)));
    }
    return completer.future;
  }

  /// An exception as the sentence the agent is given.
  static String describeError(Object e) {
    final s = e.toString();
    const prefix = 'Exception: ';
    return s.startsWith(prefix) ? s.substring(prefix.length) : s;
  }
}

/// Structural equality for JSON-like values (maps, lists, scalars).
bool deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !deepEquals(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// A hash consistent with [deepEquals].
int deepHash(Object? v) {
  if (v is Map) {
    var h = 0;
    for (final e in v.entries) {
      h ^= Object.hash(e.key, deepHash(e.value));
    }
    return h;
  }
  if (v is List) return Object.hashAll(v.map(deepHash));
  return v.hashCode;
}
