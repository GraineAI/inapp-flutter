/// THE GRAINE IN-APP AGENT, FOR FLUTTER — the runtime half: the one
/// [GraineInApp] instance, the call it carries ([GraineVoice]) and the
/// components the agent draws ([GraineComponents]).
///
/// Every rule here is the Android SDK's (sdk/android, verified on a device
/// against production) and the React Native SDK's before it; the pure parts
/// live in `core/` and are proven by plain tests. What is left is wiring:
/// timers, listeners, the session request, and the page bridge.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'core/core.dart';

part 'voice.dart';
part 'components.dart';

/// Everything the SDK reports. Every method is optional; override what you
/// draw. Use it with `extends` or `with`.
abstract mixin class GraineListener {
  void onSessionReady(SessionConfig session) {}
  void onCallState(bool connected, bool connecting) {}
  void onCaption(Role role, String text, bool live) {}

  /// The agent drew a component. [GraineComponents] already holds it for
  /// [GraineWidgetView]; a host drawing its own answers it with
  /// [GraineVoice.answerWidget].
  void onWidget(Map<String, Object?> widget) {}

  /// A component is on its way; its content is loading.
  void onWidgetPending(Map<String, Object?> hint) {}
  void onEnded() {}
  void onMicDenied(String reason) {}

  /// One word for the connection. Fires only when the word changes.
  void onQuality(ConnectionQuality quality) {}
  void onNetwork(bool online) {}

  /// The network interrupted the call and it is being re-established. Not an end.
  void onReconnecting(bool active) {}
  void onTransport(Transport transport, Transport requested, String? reason, String? message) {}
  void onConnectivity(GraineConnectivity state, int attempt, String? reason) {}
  void onActionRequested(String name) {}
  void onActionCompleted(String name, ActionResult result) {}

  /// The customer looks stuck (stalled_on_step): on one screen, with a field
  /// outstanding, through a stretch of a live call. The agent has already
  /// been told; this is for the app — badge a control, count it.
  void onFriction(FrictionSignal signal) {}

  /// Loud for you, invisible to the customer: a misconfigured agent is never
  /// the customer's problem.
  void onError(String message) {}
}

/// A failure with a sentence written for whoever has to fix it.
class GraineException implements Exception {
  const GraineException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// THE GRAINE IN-APP AGENT.
///
///     final graine = GraineInApp.init(const GraineConfig(
///       baseUrl: 'https://www.graine.ai',
///       publishableKey: 'pk_live_…',
///     ));
///     graine.identify({'name': user.name});
///     graine.setScreen(const GraineScreen('kyc_documents', fields: [...]));
///     graine.registerAction('set_tenure', (args) => const ActionResult.ok('Tenure set'));
///     // Place GraineEngine once near the root; it loads the engine, idle.
///     graine.voice.start();                       // places the call
///
/// One instance per app. Every method is main-isolate only.
class GraineInApp with WidgetsBindingObserver {
  GraineInApp._(this.config, {http.Client? httpClient, int Function()? clock})
      : _http = httpClient ?? http.Client(),
        _clock = clock ?? _wallClock,
        _variables = VariableStore(config.variables),
        _appFriction = config.friction,
        _friction = FrictionDetector(
            rules: Friction.resolve(<FrictionConfig?>[config.friction]), gateOnCall: true) {
    _screenSince = _clock();
  }

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;
  static GraineInApp? _instance;

  /// Create the one instance — call once, before `runApp` or in your first
  /// widget. Later calls return the same instance. Starts fetching the
  /// agent's configuration straight away.
  static GraineInApp init(GraineConfig config) {
    final existing = _instance;
    if (existing != null) return existing;
    WidgetsFlutterBinding.ensureInitialized();
    final g = GraineInApp._(config);
    _instance = g;
    WidgetsBinding.instance.addObserver(g);
    g._observing = true;
    g.loadSession();
    return g;
  }

  /// The instance [init] created. Throws if [init] was never called.
  static GraineInApp get instance {
    final g = _instance;
    if (g == null) throw StateError('GraineInApp.init(config) has not been called.');
    return g;
  }

  /// The instance, or null before [init].
  static GraineInApp? get maybeInstance => _instance;

  /// An instance for tests: an injected HTTP client and clock, no lifecycle
  /// observer, and installed as [instance] only when [install] is true.
  @visibleForTesting
  static GraineInApp forTesting(GraineConfig config,
      {http.Client? httpClient, int Function()? clock, bool install = false}) {
    final g = GraineInApp._(config, httpClient: httpClient, clock: clock);
    if (install) _instance = g;
    return g;
  }

  /// Forget the instance (tests only).
  @visibleForTesting
  static void resetForTesting() {
    final g = _instance;
    _instance = null;
    g?.dispose();
  }

  final GraineConfig config;
  final http.Client _http;
  final int Function() _clock;
  bool _observing = false;

  /// The voice call. [GraineEngine] attaches it; `start()` places a call.
  late final GraineVoice voice = GraineVoice._(this);

  /// The components the agent draws, as state a [GraineWidgetView] renders.
  late final GraineComponents components = GraineComponents._forApp(this);

  final Set<GraineListener> _listeners = <GraineListener>{};

  void addListener(GraineListener l) => _listeners.add(l);
  void removeListener(GraineListener l) => _listeners.remove(l);

  void _report(void Function(GraineListener l) f) {
    for (final l in List<GraineListener>.of(_listeners)) {
      try {
        f(l);
      } catch (e) {
        debugPrint('[Graine] a GraineListener threw: $e');
      }
    }
  }

  // ── who, and what they are called ───────────────────────────────────────

  final VariableStore _variables;
  final List<void Function(Map<String, String>)> _variableWatchers = <void Function(Map<String, String>)>[];

  /// Who is signed in. Traits become prompt variables and land on the call
  /// record. Null on sign-out.
  void identify(Map<String, Object?>? traits) {
    _variables.setIdentity(traits);
    _announceVariables();
    _scheduleContext();
  }

  /// Prompt variables from the app's own data, while it runs. Merged, not
  /// replaced; null under a key removes it; null clears them all. Reaches the
  /// next call, and a live engine page re-mints with it.
  void setVariables(Map<String, Object?>? values) {
    _variables.setRuntime(values);
    _announceVariables();
  }

  /// Every variable the agent will receive, in precedence order.
  Map<String, String> currentVariables() => _variables.merged();

  void Function() _onVariables(void Function(Map<String, String>) watch) {
    _variableWatchers.add(watch);
    return () => _variableWatchers.remove(watch);
  }

  void _announceVariables() {
    final merged = _variables.merged();
    for (final w in List<void Function(Map<String, String>)>.of(_variableWatchers)) {
      w(merged);
    }
  }

  // ── what is on the screen ───────────────────────────────────────────────

  GraineScreen? _screen;
  late int _screenSince;
  final List<Map<String, Object?>> _recentEvents = <Map<String, Object?>>[];
  int _contextSeq = 0;
  final List<void Function(Map<String, Object?>)> _contextWatchers = <void Function(Map<String, Object?>)>[];
  Timer? _contextTimer;

  /// What the customer is looking at. Call on every meaningful change; an
  /// unchanged screen is not resent, and bursts are coalesced to one frame
  /// per 400ms.
  void setScreen(GraineScreen? next) {
    if (next == _screen) return;
    final now = _clock();
    if (next?.screen != _screen?.screen) _screenSince = now;
    _screen = next;
    _scheduleContext();
    _friction.onScreen(next, now);
    _armStall();
  }

  /// A product event that informs without interrupting. Rides the next
  /// context frame; the last ten are kept.
  void track(String name, [Map<String, Object?> data = const <String, Object?>{}]) {
    if (name.isEmpty) return;
    _recentEvents.add(<String, Object?>{
      'name': name,
      'at': _clock(),
      if (data.isNotEmpty) 'data': Protocol.toJson(data),
    });
    while (_recentEvents.length > 10) {
      _recentEvents.removeAt(0);
    }
    _scheduleContext();
  }

  void Function() _onContext(void Function(Map<String, Object?>) watch) {
    _contextWatchers.add(watch);
    return () => _contextWatchers.remove(watch);
  }

  /// The current frame — `{context, availableActions?, seq}` — for a
  /// transport that has just come up. Null when there is nothing to say.
  Map<String, Object?>? _currentContextFrame() {
    final frame = ContextFrame.build(
      screen: _screen,
      screenSinceMs: _screenSince,
      nowMs: _clock(),
      identity: _variables.identity(),
      appVersion: config.appVersion,
      recentEvents: List<Map<String, Object?>>.of(_recentEvents),
    );
    if (frame == null) return null;
    final available = _screen?.availableActions ?? _actions.names;
    if (!frame.containsKey('availableActions') && available.isNotEmpty) {
      frame['availableActions'] = List<String>.of(available);
    }
    frame['seq'] = ++_contextSeq;
    return frame;
  }

  /// Coalesced: the first change opens a 400ms window and everything inside
  /// it goes out as one frame at its end — a field that updates on every
  /// keystroke is sent at most every 400ms, and never starved.
  void _scheduleContext() {
    if (_contextTimer != null) return;
    _contextTimer = Timer(const Duration(milliseconds: 400), () {
      _contextTimer = null;
      final frame = _currentContextFrame();
      if (frame == null) return;
      for (final w in List<void Function(Map<String, Object?>)>.of(_contextWatchers)) {
        w(frame);
      }
    });
  }

  // ── friction: noticing the customer is stuck ────────────────────────────

  final FrictionDetector _friction;
  FrictionConfig? _appFriction;
  Timer? _stallTimer;

  /// Replace the app's layer of friction rules. Safe at any time.
  void configureFriction(FrictionConfig? override) {
    _appFriction = override;
    _friction.configure(
        Friction.resolve(<FrictionConfig?>[FrictionConfig.fromJson(session?.friction), override]));
    _armStall();
  }

  /// The rules in force right now — defaults, the dashboard's, the app's.
  FrictionRules get frictionRules => _friction.rules;

  /// The customer did something that is not a field edit — scrolled a list,
  /// opened a picker. The idle clock restarts. Field edits do NOT count.
  void noteInteraction() {
    _friction.onInteraction(_clock());
    _armStall();
  }

  void _callStateChanged(bool live) {
    _friction.onCall(live, _clock());
    _armStall();
  }

  void _armStall() {
    _stallTimer?.cancel();
    _stallTimer = null;
    final due = _friction.idleDueIn(_clock());
    if (due == null) return;
    _stallTimer = Timer(Duration(milliseconds: due), _onStall);
  }

  void _onStall() {
    _stallTimer = null;
    final signal = _friction.onIdle(_clock());
    if (signal == null) {
      _armStall();
      return;
    }
    _report((GraineListener l) => l.onFriction(signal));
    voice.reportEvent(signal.name, detail: signal.detail, data: <String, Object?>{
      'cooldown_seconds': signal.cooldownSeconds,
      'max_per_session': signal.maxPerSession,
    });
  }

  // ── what the agent may do ───────────────────────────────────────────────

  final ActionRegistry _actions = ActionRegistry();

  /// Something the agent can do in your app. Declare it on the agent in the
  /// dashboard too — a handler with no declaration is never offered, and a
  /// declaration with no handler is refused mid-sentence.
  ///
  /// The handler may answer synchronously or with a Future, and must answer
  /// within six seconds or the agent is told it was not done. Returning null
  /// means ok. Returns a function that unregisters it.
  void Function() registerAction(String name, GraineActionHandler handler) {
    final off = _actions.register(name, handler);
    _scheduleContext();
    return () {
      off();
      _scheduleContext();
    };
  }

  /// Which registered actions the agent can call, and which it cannot. Log
  /// this once at startup.
  Map<String, List<String>> checkActions() {
    final registered = _actions.names;
    final declared = session?.declaredActions ?? const <String>{};
    return <String, List<String>>{
      'usable': registered.where(declared.contains).toList(),
      'undeclared': registered.where((String a) => !declared.contains(a)).toList(),
      'unhandled': declared.where((String a) => !registered.contains(a)).toList(),
    };
  }

  /// Run one action as the agent would, against the deadline. Always
  /// answers: unknown is `refused`, a throw or a timeout is `error`.
  Future<ActionResult> executeAction(String name, Map<String, Object?> args) => _actions.execute(
        name,
        args,
        onRequested: (String n) => _report((GraineListener l) => l.onActionRequested(n)),
        onCompleted: (String n, ActionResult r) => _report((GraineListener l) => l.onActionCompleted(n, r)),
      );

  // ── the component the agent drew, retained ──────────────────────────────

  Map<String, Object?>? _pendingWidget;

  /// The component the agent drew that is still waiting to be answered, as
  /// the page sent it. Cleared when it is answered or dismissed, and when a
  /// new call starts.
  Map<String, Object?>? get pendingWidget => _pendingWidget;

  /// Forget the retained component.
  void clearPendingWidget() => _pendingWidget = null;

  // ── the session ─────────────────────────────────────────────────────────

  final ValueNotifier<SessionConfig?> _session = ValueNotifier<SessionConfig?>(null);
  Future<SessionConfig?>? _sessionLoad;

  /// What the dashboard says about this agent. Null until it has loaded.
  SessionConfig? get session => _session.value;

  /// The session, for a widget that redraws when it arrives.
  ValueListenable<SessionConfig?> get sessionListenable => _session;

  /// Fetch the agent's configuration once; concurrent callers share the one
  /// request, and a failure is retried by the next caller. Null on failure,
  /// which is reported through [GraineListener.onError].
  Future<SessionConfig?> loadSession() {
    final s = _session.value;
    if (s != null) return Future<SessionConfig?>.value(s);
    return _sessionLoad ??= _fetchSession().then<SessionConfig?>((SessionConfig s) {
      _session.value = s;
      _pickTokens();
      _variables.setDashboardDefaults(s.variables);
      _friction.configure(
          Friction.resolve(<FrictionConfig?>[FrictionConfig.fromJson(s.friction), _appFriction]));
      _armStall();
      _report((GraineListener l) => l.onSessionReady(s));
      voice._sessionChanged();
      final unhandled = checkActions()['unhandled']!;
      if (unhandled.isNotEmpty) {
        debugPrint('[Graine] The agent declares actions this build does not implement: $unhandled. '
            'They will be refused mid-sentence.');
      }
      return s;
    }, onError: (Object e) {
      final msg = e is GraineException
          ? e.message
          : e is TimeoutException
              ? 'Could not reach the agent — the request timed out. Check the connection and baseUrl.'
              : 'Could not load the agent: $e';
      debugPrint('[Graine] $msg');
      _report((GraineListener l) => l.onError(msg));
      return null;
    }).whenComplete(() => _sessionLoad = null);
  }

  Future<SessionConfig> _fetchSession() async {
    final url = Uri.parse('${Protocol.trimTrailingSlashes(config.baseUrl)}/api/embed/session');
    final res = await _http
        .post(url,
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(<String, Object?>{'publishableKey': config.publishableKey}))
        .timeout(const Duration(seconds: 25));
    Map<String, Object?> data;
    try {
      // UTF-8 whatever the header says: a Devanagari variable must survive.
      data = Js.asMap(jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true))) ?? <String, Object?>{};
    } catch (_) {
      data = <String, Object?>{};
    }
    final err = SessionConfig.errorFor(res.statusCode, data);
    if (err != null) throw GraineException(err);
    return SessionConfig.fromJson(data);
  }

  // ── how it looks ────────────────────────────────────────────────────────

  final ValueNotifier<ThemeTokens?> _tokens = ValueNotifier<ThemeTokens?>(null);

  /// The design the brand chose in the dashboard — both token sets. Null
  /// until the session loads, and from a server that predates designs.
  ResolvedDesign? get design => _session.value?.design;

  /// The tokens to draw with right now: the brand's fixed scheme, else the
  /// device's light or dark, re-picked when the device switches. Null without
  /// a [design]. For a host drawing its own UI; the SDK's widgets pick for
  /// themselves from their `MediaQuery`.
  ThemeTokens? get tokens => _tokens.value;

  /// [tokens], for a widget that redraws when they change.
  ValueListenable<ThemeTokens?> get tokensListenable => _tokens;

  /// The device switched between light and dark.
  @override
  void didChangePlatformBrightness() => _pickTokens();

  void _pickTokens() {
    final d = design;
    if (d == null) {
      _tokens.value = null;
      return;
    }
    bool? dark;
    try {
      dark = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    } catch (_) {
      dark = null; // no binding yet: the device has not said, which is light
    }
    _tokens.value = d.pick(deviceDark: dark);
  }

  // ── the app's lifecycle ─────────────────────────────────────────────────

  bool _foreground = true;
  final List<void Function(bool)> _foregroundWatchers = <void Function(bool)>[];

  /// Whether the app is in the foreground, as the lifecycle last reported.
  bool get foreground => _foreground;

  /// `inactive` is not the background: iOS reports it for the app switcher,
  /// a pulled-down notification — and the microphone permission dialog.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setForegroundForTesting(true);
    } else if (state != AppLifecycleState.inactive) {
      setForegroundForTesting(false);
    }
  }

  /// What the lifecycle observer calls. Public so a test can drive it.
  @visibleForTesting
  void setForegroundForTesting(bool foreground) {
    if (foreground == _foreground) return;
    _foreground = foreground;
    for (final w in List<void Function(bool)>.of(_foregroundWatchers)) {
      w(foreground);
    }
  }

  /// Stop every timer and detach the engine (tests; an app keeps its instance).
  @visibleForTesting
  void dispose() {
    _contextTimer?.cancel();
    _stallTimer?.cancel();
    voice.detach();
    components._cancel();
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }
}
