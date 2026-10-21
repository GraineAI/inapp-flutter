/// THE GRAINE IN-APP AGENT, FOR FLUTTER — the runtime half: the app's
/// agents ([GraineInApp], one per publishable key — usually one), the call
/// each carries ([GraineVoice]) and the components each draws
/// ([GraineComponents]).
///
/// Every rule here is the Android SDK's (sdk/android, verified on a device
/// against production) and the React Native SDK's before it; the pure parts
/// live in `core/` and are proven by plain tests. What is left is wiring:
/// timers, listeners, the session request, and the page bridge.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, WebSocket;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:flutter/services.dart' show EventChannel, MethodChannel, MissingPluginException, PlatformException;
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'core/core.dart';
import 'fonts.dart';

part 'voice.dart';
part 'components.dart';
part 'calls.dart';
part 'chat_session.dart';
part 'device.dart';

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

  /// In the chat, the agent spoke without being asked — its welcome, or
  /// something it noticed on the screen. Open the chat if it is closed.
  void onAgentVolunteered(String text) {}

  /// Loud for you, invisible to the customer: a misconfigured agent is never
  /// the customer's problem.
  void onError(String message) {}
}

/// A failure with a sentence written for whoever has to fix it — WIRE.md's
/// `GraineError`: a typed [code], the [message], and with a rate limit how
/// long to wait ([retryAfterSeconds]).
class GraineException implements Exception {
  const GraineException(this.message,
      {this.code = GraineErrorCode.unknown, this.codeName, this.statusCode, this.retryAfterSeconds});

  /// The sentence Graine (or the SDK) gave — client-facing, never internal.
  final String message;

  /// Why: the wire's code ([GraineErrorCode.network] when Graine could not be
  /// reached; [GraineErrorCode.unknown] for anything else, see [codeName]).
  final GraineErrorCode code;

  /// The code as Graine said it — a newer one this build does not know
  /// included. Null when it said none.
  final String? codeName;

  /// The HTTP status of a refusal, when there was one.
  final int? statusCode;

  /// With [GraineErrorCode.rateLimited]: how long Graine asked to be left alone.
  final int? retryAfterSeconds;

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
/// SEVERAL AGENTS IN ONE APP — each with its own publishable key, chosen per
/// screen or use case (a support agent in Help, a sales agent on Plans):
///
///     GraineInApp.init(mainConfig);                       // the default agent
///     GraineInApp.init(supportConfig, name: 'support');
///     GraineChat(app: GraineInApp.named('support'));      // a view takes its agent
///
/// Each agent has its own session and design, its chat, its call, its
/// actions, and its own scheduling and memory requests (made with its own
/// key). What one app, one user and one device have once, every agent
/// shares: the install id, who is signed in ([identify] on any agent
/// identifies the user for all of them; `identify(null)` signs out
/// everywhere), their memory choice, and the screen ([setScreen], [track],
/// [tap] — each agent tells it to its own conversation while one is live).
/// One conversation at a time across all of them: starting a call or a chat
/// on one ends a live one on another.
///
/// Every method is main-isolate only.
class GraineInApp with WidgetsBindingObserver {
  GraineInApp._(this.config,
      {required _Agents group,
      required this.name,
      http.Client? httpClient,
      int Function()? clock,
      Directory? fontCacheDir,
      FontRegistrar? fontRegistrar,
      GraineChatConnector? chatConnector})
      : _group = group,
        _http = httpClient ?? http.Client(),
        _clock = clock ?? _wallClock,
        _chatConnector = chatConnector,
        _variables = VariableStore(config.variables),
        _appFriction = config.friction,
        _friction = FrictionDetector(
            rules: Friction.resolve(<FrictionConfig?>[config.friction]), gateOnCall: true) {
    _screenSince = _clock();
    // One loader for the app: a face is fetched once, whichever agent's design draws with it.
    _fonts = group.fonts ??=
        DesignFontLoader(client: _http, cacheDir: fontCacheDir, register: fontRegistrar, debug: config.debug);
    // Read now, so the first ticket and the engine page never wait on them.
    unawaited(_device.installId());
    unawaited(_device.prefs());
    unawaited(_device.timezone());
  }

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;

  /// The name of the agent [init] configures when it is given none — the
  /// one [instance] returns, and every view draws unless handed another.
  static const String defaultName = 'default';

  /// The agents [init] configured, and what they share.
  static _Agents _process = _Agents();

  /// A name as it is kept: trimmed; empty is the default agent's.
  static String _normaliseName(String name) {
    final t = name.trim();
    return t.isEmpty ? defaultName : t;
  }

  /// CONFIGURE AN AGENT — call before `runApp` or in your first widget.
  /// Starts fetching the agent's configuration straight away.
  ///
  /// Without a [name] it is the default agent: [instance], and the one every
  /// view draws unless handed another. An app with several agents configures
  /// each under its own name with its own publishable key, and hands the
  /// views the one each screen talks to (`GraineChat(app: GraineInApp.named('support'))`).
  /// A later call with a name already configured returns that agent unchanged.
  static GraineInApp init(GraineConfig config, {String name = defaultName}) {
    final key = _normaliseName(name);
    final existing = _process.byName[key];
    if (existing != null) return existing;
    WidgetsFlutterBinding.ensureInitialized();
    final g = GraineInApp._(config, group: _process, name: key, fontCacheDir: defaultFontCacheDir());
    _process.join(g);
    WidgetsBinding.instance.addObserver(g);
    g._observing = true;
    g._adoptShared();
    g.loadSession();
    GraineCalls._agentsChanged();
    return g;
  }

  /// The agent configured under [name], or null.
  static GraineInApp? named(String name) => _process.byName[_normaliseName(name)];

  /// Every configured agent, by name, in the order they were configured.
  static Map<String, GraineInApp> get all => Map<String, GraineInApp>.unmodifiable(_process.byName);

  /// The default agent — the one [init] configured without a name (in an
  /// app that only named its agents, the first one configured). Throws if
  /// [init] was never called.
  static GraineInApp get instance {
    final g = _process.primary;
    if (g == null) throw StateError('GraineInApp.init(config) has not been called.');
    return g;
  }

  /// The default agent, or null before [init].
  static GraineInApp? get maybeInstance => _process.primary;

  /// The agent [name] names, or null — for a name the native engine sent.
  static GraineInApp? _agentNamed(String? name) => name == null ? null : named(name);

  /// Every configured agent, and [extra] if it is not one of them.
  static List<GraineInApp> _everyAgent([GraineInApp? extra]) {
    final every = _process.byName.values.toList();
    if (extra != null && !every.any((GraineInApp g) => identical(g, extra))) every.add(extra);
    return every;
  }

  /// An instance for tests: an injected HTTP client and clock, no lifecycle
  /// observer. With [install] it joins the app's agents under [name] (the
  /// default agent unless named) — [instance], [named], and everything the
  /// agents share; without, it shares nothing and is no agent of the app's.
  /// Design faces go through [httpClient] too, are kept on disk only in
  /// [fontCacheDir] (none by default), and are registered by [fontRegistrar]
  /// (default: Flutter's FontLoader).
  @visibleForTesting
  static GraineInApp forTesting(GraineConfig config,
      {http.Client? httpClient,
      int Function()? clock,
      bool install = false,
      String name = defaultName,
      Directory? fontCacheDir,
      Future<void> Function(String name, Uint8List bytes)? fontRegistrar,
      GraineChatConnector? chatConnector}) {
    final group = install ? _process : _Agents();
    final g = GraineInApp._(config,
        group: group,
        name: _normaliseName(name),
        httpClient: httpClient,
        clock: clock,
        fontCacheDir: fontCacheDir,
        fontRegistrar: fontRegistrar,
        chatConnector: chatConnector);
    group.join(g);
    if (install) {
      g._adoptShared();
      GraineCalls._agentsChanged();
    }
    return g;
  }

  /// Forget every agent and what they shared (tests only).
  @visibleForTesting
  static void resetForTesting() {
    final agents = _process.byName.values.toList();
    _process = _Agents();
    for (final g in agents) {
      g.dispose();
    }
  }

  final GraineConfig config;

  /// The name this agent was configured under ([init]); [defaultName] for the default agent.
  final String name;

  final _Agents _group;
  final http.Client _http;
  final int Function() _clock;
  final GraineChatConnector? _chatConnector;
  _Device get _device => _group.device;
  bool _observing = false;

  /// This agent and every other configured beside it — what the user, the
  /// device and the screen are shared with.
  List<GraineInApp> get _peers {
    final peers = _group.byName.values.toList();
    if (!peers.any((GraineInApp g) => identical(g, this))) peers.add(this);
    return peers;
  }

  /// An agent configured after the user was identified, or a screen set,
  /// takes them on.
  void _adoptShared() {
    final group = _group;
    if (group.identified) {
      _applyIdentify(group.traits, memory: group.memory);
    } else if (group.memory != null) {
      _applyMemory(group.memory!);
    }
    final screen = group.screen;
    if (screen != null) _applyScreen(screen, since: group.screenSince);
  }

  /// ONE CONVERSATION AT A TIME, across every agent: this agent's call or
  /// chat is starting — every other agent's call ends and its chat closes.
  /// (Between an agent's own call and chat, its bar switches, as before.)
  void _takeConversation() {
    for (final g in _peers) {
      if (identical(g, this)) continue;
      final voice = g.voice;
      if (voice.connected || voice.connecting) voice.end();
      final chat = g._chat;
      if (chat != null && chat.isOpen) chat.close();
    }
  }

  /// The voice call. [GraineEngine] attaches it; `start()` places a call.
  late final GraineVoice voice = GraineVoice._(this);

  /// The components the agent draws, as state a [GraineWidgetView] renders.
  late final GraineComponents components = GraineComponents._forApp(this);

  GraineChatSession? _chat;

  /// THE TEXT CHAT — the conversation in writing, on its own connection.
  /// [GraineAgentBar] and [GraineChat] draw it and open it when the customer
  /// is in the chat — and when their window closes, keep the conversation
  /// until it has been idle for 5 minutes; a host drawing its own calls
  /// [GraineChatSession.open] and [GraineChatSession.close] itself. One
  /// conversation at a time: the bar ends the call before it opens the chat
  /// (and the chat when it goes back to the call), and opening it ends any
  /// other agent's call and closes its chat.
  GraineChatSession get chat => _chat ??= GraineChatSession._(this, connector: _chatConnector);

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

  /// WHO IS SIGNED IN. Traits become prompt variables and land on the call
  /// record, masked on the device as before.
  ///
  /// The agent's Who is the user? setting (Agent → Memory, in the dashboard) names
  /// the trait that identifies the user — `user_id` unless it says `email`,
  /// `phone` or a custom trait. That one trait is kept raw and sent only
  /// where Graine needs it to recognise the user — never as a prompt variable
  /// or in what the agent is told about the screen. A placeholder ("guest",
  /// "null", a masked "[EMAIL]"), null, a boolean or a fraction identifies
  /// nobody, and that conversation is anonymous — with no memory.
  ///
  /// [memory]: false — this user's conversations are neither remembered nor
  /// recalled. Kept on the device for this user, so it need not be repeated;
  /// left out, their last choice stands (on until they make one).
  ///
  /// A call already open keeps the identity it opened with: a change reaches
  /// the next one. A chat belongs to whoever was identified when it
  /// connected (contract/DESIGN.md "Who a chat belongs to"): when the identity
  /// changes — signing in after it opened, another user, or a sign-out — a
  /// chat connected or connecting closes quietly, its turns go (a line typed
  /// and not yet sent stays, and goes next), and it connects again at once as
  /// the new identity; one not connected forgets the same way and connects at
  /// the next open or message. The same identity with other traits, or
  /// another memory choice, changes nothing on the open chat. Null signs out:
  /// this device stops being the user's (Graine is told), and later
  /// conversations are anonymous. Someone else signing in without a sign-out
  /// first signs the last user out the same way.
  ///
  /// One user for the whole app: every agent the app configured hears it —
  /// each keeps the trait its own Identity setting names, and a sign-out
  /// releases the device from every agent's workspace.
  void identify(Map<String, Object?>? traits, {bool? memory}) {
    final group = _group;
    final next = traits == null ? null : Map<String, Object?>.of(traits);
    if (memory != null) {
      group.memory = memory;
    } else if (!deepEquals(group.traits, next)) {
      group.memory = null; // this user's own last choice applies
    }
    group.identified = true;
    group.traits = next;
    for (final g in _peers) {
      g._applyIdentify(next, memory: memory);
    }
  }

  /// [identify], for this agent alone.
  void _applyIdentify(Map<String, Object?>? traits, {bool? memory}) {
    final before = _traits;
    final beforeValue = _identityValueFor(before);
    _traits = traits == null ? null : Map<String, Object?>.of(traits);
    _applyTraits();
    final afterValue = _identityValueFor(_traits);
    if (memory != null) {
      _memoryNow = memory;
      unawaited(_rememberMemory(_traits, memory));
    } else if (!deepEquals(before, _traits)) {
      _memoryNow = null; // this user's own last choice applies
    }
    // Signed out — or someone else signed in without a sign-out first: the
    // device is no longer the last user's.
    if (before != null && (traits == null || (beforeValue != null && afterValue != null && beforeValue != afterValue))) {
      unawaited(_signOut(before));
    }
    // A chat belongs to whoever was identified when it connected — nobody to a
    // user included: their conversation is not the next identity's.
    if (_identityKey(beforeValue) != _identityKey(afterValue)) _chat?._identityChanged();
    _announceVariables();
    _scheduleContext();
    _announceIdentity();
  }

  /// The traits as prompt variables and `context.user` — masked, and without
  /// the trait that identifies the user, which travels only in the identity
  /// channel. Before the session names that trait, all of them; again when it
  /// arrives.
  void _applyTraits() =>
      _variables.setIdentity(Identity.withoutIdentity(_traits, session?.identitySetting.field));

  /// Whether the current user's conversations are remembered — the same as
  /// `identify(currentTraits, memory: enabled)`. Kept on the device for them.
  /// Their choice for every agent the app configured.
  void setMemory(bool enabled) {
    _group.memory = enabled;
    for (final g in _peers) {
      g._applyMemory(enabled);
    }
  }

  /// [setMemory], for this agent alone.
  void _applyMemory(bool enabled) {
    _memoryNow = enabled;
    unawaited(_rememberMemory(_traits, enabled));
    _announceIdentity();
  }

  /// The current user's memory choice: on until they turn it off.
  Future<bool> memoryEnabled() async => (await _identityState()).memory;

  /// FORGET EVERYTHING THE AGENT REMEMBERS about the current user, for this
  /// agent's memory. Allowed only from a device that is theirs. Completes
  /// with how many memories were deleted; throws a [GraineException] —
  /// `identityRequired` when nobody is identified, `deviceLimit` from a
  /// device that is not theirs.
  Future<int> forgetMemory() async {
    await _sessionOrThrow();
    if (_identityValueFor(_traits) == null) {
      throw const GraineException(
          'Nobody is identified. Call identify() with the trait that identifies the user before forgetMemory().',
          code: GraineErrorCode.identityRequired);
    }
    final deleted = (await _embed(_Routes.forget, const <String, Object?>{}))['deleted'];
    // The conversation is part of what was forgotten: off the screen too — only once it is gone.
    _chat?.clear();
    return deleted is num && deleted.isFinite && deleted >= 0 ? deleted.round() : 0;
  }

  /// Graine lets go of the conversation it kept for this agent and the current
  /// user, so the next chat starts fresh ([GraineChatSession.newConversation]).
  /// Nobody identified: nothing was kept, nothing to ask.
  Future<void> _letGoOfConversation() async {
    await _sessionOrThrow();
    if (_identityValueFor(_traits) == null) return;
    await _embed(_Routes.newConversation, const <String, Object?>{});
  }

  /// WHAT THE AGENT REMEMBERS about the current user, newest first (at most
  /// 100), already redacted — for a "what you remember about me" screen.
  /// Only from a device that is theirs. Throws a [GraineException]:
  /// `identityRequired` when nobody is identified, `deviceLimit` from a
  /// device that is not theirs.
  Future<List<GraineMemory>> memories() async {
    await _sessionOrThrow();
    if (_identityValueFor(_traits) == null) {
      throw const GraineException(
          'Nobody is identified. Call identify() with the trait that identifies the user before memories().',
          code: GraineErrorCode.identityRequired);
    }
    return GraineMemory.listFrom(await _embed(_Routes.memories, const <String, Object?>{}));
  }

  /// THIS INSTALL'S ID: a UUID made on the app's first launch and kept by the
  /// platform (the Keychain on iOS, through reinstalls; storage excluded from
  /// backups on Android) — the same id the native call engine sends, and the
  /// same for every agent the app configured. Graine counts a user's devices
  /// by it; the agent never sees it.
  Future<String> get installId => _device.installId();

  Map<String, Object?>? _traits;

  /// The memory choice made in this run for the current traits; null: the
  /// user's own last choice, kept on the device.
  bool? _memoryNow;
  final List<void Function()> _identityWatchers = <void Function()>[];

  /// An identity value as a chat compares them: normalised for the session's
  /// trait — the same user however the app spells it — and null for nobody.
  String? _identityKey(String? value) {
    final s = session;
    return s == null || value == null ? null : Identity.normaliseValue(s.identitySetting.field, value);
  }

  /// The identity in [traits] for the session's setting; null before the
  /// session arrives (no conversation can start before it does).
  String? _identityValueFor(Map<String, Object?>? traits) {
    final s = session;
    return s == null ? null : Identity.pick(traits, s.identitySetting.field);
  }

  /// THE IDENTITY FIELDS AS THEY STAND — for a ticket, a request, the engine
  /// page. Waits for the session (the setting names the trait), the install
  /// id and the kept choices, and reads the zone afresh.
  Future<_IdentityState> _identityState({bool waitForSession = true}) async {
    if (waitForSession) await loadSession();
    await _device.installId();
    await _device.prefs();
    await _device.timezone();
    return _identityStateNow()!;
  }

  /// The same, now — or null while the install id or the kept choices are
  /// still being read (they are read as the SDK starts).
  _IdentityState? _identityStateNow() {
    final install = _device.installIdNow;
    if (install == null || _device.prefsNow == null) return null;
    final value = _identityValueFor(_traits);
    final field = session?.identitySetting.field ?? Identity.defaultField;
    final memory = _memoryNow ?? (value == null ? null : _device.memoryChoiceNow(Identity.memoryKey(field, value)));
    return (value: value, installId: install, memory: memory ?? true, timezone: _device.timezoneNow);
  }

  Future<void> _rememberMemory(Map<String, Object?>? traits, bool enabled) async {
    final s = await loadSession();
    if (s == null) return;
    final field = s.identitySetting.field;
    final value = Identity.pick(traits, field);
    if (value == null) return; // an anonymous choice lasts this run only
    await _device.rememberMemory(Identity.memoryKey(field, value), enabled);
  }

  /// `identify(null)` after a user: the device is no longer theirs. Graine
  /// releases it and stops ringing it for them.
  Future<void> _signOut(Map<String, Object?> previous) async {
    try {
      final s = await loadSession();
      if (s == null) return;
      final value = Identity.pick(previous, s.identitySetting.field);
      if (value == null) return;
      await _embed(_Routes.signout, const <String, Object?>{}, identity: value, overrideIdentity: true);
    } catch (e) {
      debugPrint('[Graine] Sign-out could not reach Graine ($e); the device is released after 30 days unused.');
    }
  }

  void Function() _onIdentity(void Function() watch) {
    _identityWatchers.add(watch);
    return () => _identityWatchers.remove(watch);
  }

  void _announceIdentity() {
    _bookingChanged();
    for (final w in List<void Function()>.of(_identityWatchers)) {
      w();
    }
    GraineCalls._identityChanged(this);
  }

  /// `{type: "graine:identity", value, installId, memory, timezone}` for the
  /// engine page, which mints its own tickets.
  Future<Map<String, Object?>> _identityMessage() async => _identityMessageOf(await _identityState());

  /// The same, now, or null while it cannot be built without waiting.
  Map<String, Object?>? _identityMessageNow() {
    final id = _identityStateNow();
    return id == null ? null : _identityMessageOf(id);
  }

  static Map<String, Object?> _identityMessageOf(_IdentityState id) => <String, Object?>{
        'type': ProtocolOut.identity,
        'value': id.value,
        'installId': id.installId,
        'memory': id.memory,
        if (id.timezone != null) 'timezone': id.timezone,
      };

  // ── requests to Graine ──────────────────────────────────────────────────

  static const Map<String, String> _json = <String, String>{'Content-Type': 'application/json'};

  Uri _embedUrl(String route) => Uri.parse('${Protocol.trimTrailingSlashes(config.baseUrl)}$route');

  /// ONE REQUEST TO AN SDK ROUTE ([_Routes]): the key, [body], and the identity fields
  /// (contract §1.3) — the current user's, or [identity] with
  /// [overrideIdentity] (a sign-out names the user who left). Throws a
  /// [GraineException] with the contract's code on a refusal.
  Future<Map<String, Object?>> _embed(String path, Map<String, Object?> body,
      {String? identity, bool overrideIdentity = false}) async {
    await _sessionOrThrow();
    final id = await _identityState(waitForSession: false);
    final payload = <String, Object?>{
      'publishableKey': config.publishableKey,
      ...body,
      ...Identity.requestFields(
        value: overrideIdentity ? identity : id.value,
        installId: id.installId,
        memory: id.memory,
        timezone: id.timezone,
      ),
    };
    final http.Response res;
    try {
      res = await _http
          .post(_embedUrl(path), headers: _json, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      throw GraineException('Could not reach Graine: $e', code: GraineErrorCode.network);
    }
    Map<String, Object?> data;
    try {
      data = Js.asMap(jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true))) ?? <String, Object?>{};
    } catch (_) {
      data = <String, Object?>{};
    }
    final refusal = EmbedRefusal.of(res.statusCode, data, retryAfter: res.headers['retry-after']);
    if (refusal != null) throw _refused(refusal);
    return data;
  }

  static GraineException _refused(EmbedRefusal r) => GraineException(r.message,
      code: r.code, codeName: r.codeName, statusCode: r.statusCode, retryAfterSeconds: r.retryAfterSeconds);

  /// The session, or the reason there is none: the session's own refusal
  /// (a key Graine rejected, say), else Graine out of reach.
  Future<SessionConfig> _sessionOrThrow() async {
    final s = await loadSession();
    if (s != null) return s;
    throw _sessionError ??
        const GraineException('Could not load the agent. Check the connection and the publishable key.',
            code: GraineErrorCode.network);
  }

  /// Why the last session request failed, for the requests that need it.
  GraineException? _sessionError;

  /// A ticket for a socket: `{ticket, wsUrl}`, or null — no gateway on this
  /// deployment (503), or no answer — and the socket goes direct.
  Future<({String ticket, String wsUrl})?> _ticket(String mode, Map<String, String> variables, _IdentityState id,
      {String? callId}) async {
    try {
      final metadata = Protocol.ticketMetadata(variables);
      final res = await _http
          .post(_embedUrl(_Routes.ticket),
              headers: _json,
              body: jsonEncode(<String, Object?>{
                'publishableKey': config.publishableKey,
                'mode': mode,
                if (metadata != null) 'metadata': metadata,
                ...Identity.requestFields(
                  value: id.value,
                  installId: id.installId,
                  memory: id.memory,
                  timezone: id.timezone,
                  callId: callId,
                ),
              }))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode < 200 || res.statusCode > 299) return null;
      final data = Js.asMap(jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true)));
      final ticket = data?['ticket'];
      final url = data?['wsUrl'];
      if (ticket is String && ticket.isNotEmpty && url is String && url.isNotEmpty) {
        return (ticket: ticket, wsUrl: url);
      }
    } catch (_) {
      // No ticket is not an error: the direct socket carries the chat.
    }
    return null;
  }

  // ── calls the user books ────────────────────────────────────────────────

  /// WHAT THE AGENT ALLOWS USERS TO BOOK, and how Graine rings — from the
  /// session (defaults until it arrives, and from a server that says nothing,
  /// which allows no booking). `earliest(now)` and `latest(now)` bound a
  /// booking.
  GraineSchedulingRules get schedulingRules => GraineSchedulingRules.of(session?.calls);

  /// WHETHER THIS USER CAN BOOK A CALL FROM HERE — for showing or hiding a
  /// "Call me" button of the app's own: the agent lets users book, Graine
  /// rings this phone (the workspace set up in-app calling for this
  /// platform), and the user is identified ([identify] with the agent's
  /// identity trait). False until the session has arrived.
  /// [bookingListenable] redraws a widget when it changes;
  /// `GraineBooking.show` opens the SDK's own booking sheet.
  bool get bookingAvailable => bookingBlocker == null;

  /// Why [bookingAvailable] is false, as the booking sheet says it:
  /// [GraineErrorCode.schedulingOff] (the agent takes no bookings, or Graine
  /// cannot ring this phone) or [GraineErrorCode.identityRequired] (nobody
  /// identified); null when it is true.
  GraineErrorCode? get bookingBlocker =>
      Booking.blocker(session?.calls, platform: _bookingPlatform, identified: _identityValueFor(_traits) != null);

  /// WHY [bookingAvailable] IS FALSE, in words an app can act on (the same
  /// rule as [bookingBlocker], finer), checked in this order: `not_loaded`
  /// (the session has not arrived), `rings_not_set_up` (Graine cannot ring
  /// this phone), `scheduling_off` (the agent takes no bookings) and
  /// `not_identified` (nobody is identified); null when booking is available.
  /// [bookingListenable] redraws a widget when it may have changed.
  GraineBookingUnavailableReason? get bookingUnavailableReason => Booking.unavailableReason(session?.calls,
      platform: _bookingPlatform, identified: _identityValueFor(_traits) != null, loaded: session != null);

  /// THE TIMES THE SDK'S OWN BOOKING SHEET OFFERS on [day] — the device's day
  /// holding it — for a picker of your own: the sheet's 5-minute steps, from
  /// the earliest the rules allow ([GraineSchedulingRules.minLeadMinutes]
  /// from now, rounded up) to the latest ([GraineSchedulingRules.maxDaysAhead]),
  /// in the device's time zone. Empty for a day outside them. Whether the
  /// customer can book at all is [bookingAvailable] ([bookingUnavailableReason]
  /// says why not); the agent's calling window is checked by Graine when the
  /// call is booked ([scheduleCall] — `outsideWindow`).
  List<DateTime> bookingSlots(DateTime day, {DateTime? now}) {
    final at = now ?? DateTime.fromMillisecondsSinceEpoch(_clock());
    final d = day.toLocal();
    for (final offered in Booking.days(Booking.bounds(schedulingRules, at), at)) {
      final first = offered.first.toLocal();
      if (first.year == d.year && first.month == d.month && first.day == d.day) return Booking.slots(offered);
    }
    return const <DateTime>[];
  }

  /// The device's time zone (IANA, "Asia/Kolkata"), once the SDK has read it —
  /// the booking sheet names it beside the time chosen. Null before then.
  String? get deviceTimezone => _device.timezoneNow;

  /// [bookingAvailable], for a widget that redraws when it changes.
  ValueListenable<bool> get bookingListenable => _bookable;
  final ValueNotifier<bool> _bookable = ValueNotifier<bool>(false);

  /// The session arrived, or the user changed: whether they can book, again.
  void _bookingChanged() => _bookable.value = bookingAvailable;

  /// Where Graine can ring this app: the plugin's platforms, iOS and Android.
  static String? get _bookingPlatform => switch (defaultTargetPlatform) {
        TargetPlatform.iOS => 'ios',
        TargetPlatform.android => 'android',
        _ => null,
      };

  /// BOOK A CALL FROM THE AGENT at [at] — "call me tomorrow at 6". The agent
  /// rings this user's devices (or, with nobody identified, this install)
  /// through the app; [reason] (at most 120 characters) is kept with the call
  /// for the agent and never put in the push that rings it. Completes with
  /// the booked call (status scheduled).
  ///
  /// Checked here first, before anything is asked: `schedulingOff` (the agent
  /// does not let users book), `tooSoon` (before [GraineSchedulingRules.earliest]),
  /// `tooFar` (after [GraineSchedulingRules.latest]), `invalidRequest` (a reason
  /// over 120 characters). Then Graine's own: `outsideWindow`, `tooManyPending`,
  /// `identityRequired`, `rateLimited`… — all a [GraineException].
  Future<GraineScheduledCall> scheduleCall({required DateTime at, String? reason}) async {
    final why = reason?.trim();
    if (why != null && why.length > ScheduledCalls.maxReasonLength) {
      throw const GraineException('A booking\'s reason is at most ${ScheduledCalls.maxReasonLength} characters.',
          code: GraineErrorCode.invalidRequest);
    }
    await _sessionOrThrow();
    final rules = schedulingRules;
    // Refused in the booking sheet's words (Booking.errorLine), the same on every SDK.
    GraineException refused(GraineErrorCode code) => GraineException(Booking.errorLine(code, rules), code: code);
    if (!rules.usersCanBook) throw refused(GraineErrorCode.schedulingOff);
    final now = DateTime.fromMillisecondsSinceEpoch(_clock());
    if (at.isBefore(rules.earliest(now))) throw refused(GraineErrorCode.tooSoon);
    if (at.isAfter(rules.latest(now))) throw refused(GraineErrorCode.tooFar);
    final data = await _embed(_Routes.schedule, <String, Object?>{
      'at': ScheduledCalls.atWire(at),
      if (why != null && why.isNotEmpty) 'reason': why,
    });
    final call = ScheduledCalls.oneFrom(data);
    if (call == null) {
      throw const GraineException('The booking was not confirmed. Read scheduledCalls() before booking again.',
          code: GraineErrorCode.unknown, codeName: 'bad_response');
    }
    _chat?._booked(call);
    return call;
  }

  /// This user's (or, with nobody identified, this install's) calls, in
  /// Graine's order — upcoming first.
  Future<List<GraineScheduledCall>> scheduledCalls() async =>
      ScheduledCalls.listFrom(await _embed(_Routes.list, const <String, Object?>{}));

  /// Cancel a booked call — one of this user's own. Completes with the call's
  /// status afterwards ([GraineCallStatus.cancelled]); throws a
  /// [GraineException] — `notFound` for a call that is not theirs.
  Future<GraineCallStatus> cancelScheduledCall(String id) async {
    final callId = id.trim();
    if (callId.isEmpty) throw const GraineException('Which call? The id is empty.', code: GraineErrorCode.invalidRequest);
    final status = ScheduledCalls.statusAfterCancel(await _embed(_Routes.cancel, <String, Object?>{'callId': callId}));
    _chat?._cancelled(callId);
    return status;
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
  /// unchanged screen is not resent. The first change goes out at once and
  /// a burst after it is coalesced to one more frame at the end of 400ms —
  /// the agent's opening line is never a screen behind.
  ///
  /// The screen is the app's: every agent the app configured hears it (and
  /// [updateField], [removeField], [clearScreen], [track], [tap]), and each
  /// tells it to its own conversation while one is live.
  void setScreen(GraineScreen? next) {
    final group = _group;
    if (next?.screen != group.screen?.screen) group.screenSince = _clock();
    group.screen = next;
    for (final g in _peers) {
      g._applyScreen(next, since: group.screenSince);
    }
  }

  /// [setScreen], for this agent alone. [since]: when this screen was first
  /// shown, if earlier than now.
  void _applyScreen(GraineScreen? next, {int? since}) {
    if (next == _screen) return;
    final now = _clock();
    if (next?.screen != _screen?.screen) _screenSince = since ?? now;
    _screen = next;
    _scheduleContext();
    _friction.onScreen(next, now);
    _armStall();
  }

  /// One field changed: [field] replaces the screen's field of the same name,
  /// or is added. Nothing happens before a screen is set — the next
  /// [setScreen] carries the field itself.
  void updateField(GraineField field) {
    final s = _screen;
    if (s == null || field.name.isEmpty) return;
    setScreen(s.withField(field));
  }

  /// A field left the screen. Nothing happens if it was never reported.
  void removeField(String name) {
    final s = _screen;
    if (s == null || name.isEmpty) return;
    setScreen(s.withoutField(name));
  }

  /// Forget the screen — but only if [screenId] (when given) is still the one
  /// being described. What a screen's cleanup should call: a navigator keeps
  /// the old screen through its exit transition, and an unconditional
  /// `setScreen(null)` there wipes the screen that has just replaced it.
  void clearScreen([String? screenId]) {
    final s = _screen;
    if (s == null) return;
    if (screenId != null && s.screen != screenId) return;
    setScreen(null);
  }

  /// A product event that informs without interrupting. Rides the next
  /// context frame; the last ten are kept.
  void track(String name, [Map<String, Object?> data = const <String, Object?>{}]) {
    for (final g in _peers) {
      g._record(name, data, coalesce: false);
    }
  }

  /// The customer tapped a control you name — "tap:<name>" in the recent
  /// events, so the agent knows what they just did. Context, not news: it
  /// rides the next frame at the end of the coalescing window.
  void tap(String name) {
    final n = _tapName(name);
    if (n.isEmpty) return;
    for (final g in _peers) {
      g._record('tap:$n', const <String, Object?>{}, coalesce: true);
    }
  }

  void _record(String name, Map<String, Object?> data, {required bool coalesce}) {
    if (name.isEmpty) return;
    _recentEvents.add(<String, Object?>{
      'name': name,
      'at': _clock(),
      if (data.isNotEmpty) 'data': Protocol.toJson(data),
    });
    while (_recentEvents.length > 10) {
      _recentEvents.removeAt(0);
    }
    _scheduleContext(trailing: coalesce);
  }

  /// A TAP ANYWHERE IN THE APP — [GraineEngine] reports every one it sees; a
  /// host with its own gesture layer may call it too. On a control with an
  /// accessibility [label]: "tap:<label>"; elsewhere "tap:screen" with where
  /// ([x], [y] in logical pixels). Only while a screen is set — a tap is about
  /// a screen — at most two a second, and only with
  /// [GraineConfig.captureTaps]. Context, not news: it rides the next frame.
  /// Every agent that captures taps hears it.
  void captureTap({required double x, required double y, String? label}) {
    final takers = <GraineInApp>[
      for (final g in _peers)
        if (g.config.captureTaps && g._screen != null) g,
    ];
    if (takers.isEmpty) return;
    final group = _group;
    final now = _clock();
    if (now - group.tapWindowAt >= 1000) {
      group.tapWindowAt = now;
      group.tapsInWindow = 0;
    }
    if (group.tapsInWindow >= 2) return;
    group.tapsInWindow++;
    final named = label == null ? '' : _tapName(label);
    for (final g in takers) {
      if (named.isNotEmpty) {
        g._record('tap:$named', const <String, Object?>{}, coalesce: true);
      } else {
        g._record('tap:screen', <String, Object?>{'x': x.round(), 'y': y.round()}, coalesce: true);
      }
    }
  }

  /// A label as an event name: one line, at most 40 characters.
  static String _tapName(String label) {
    final one = label.replaceAll(RegExp(r'\s+'), ' ').trim();
    return one.length > 40 ? one.substring(0, 40).trim() : one;
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
      registeredActions: _actions.names,
    );
    if (frame == null) return null;
    frame['seq'] = ++_contextSeq;
    return frame;
  }

  /// THE CONTEXT THROTTLE (the React Native SDK's): a change goes out at
  /// once and opens a 400ms window; changes inside it go out as one frame at
  /// its end, which opens the next window. A field that updates on every
  /// keystroke is sent at most every 400ms and never starved. [trailing]
  /// (taps) never goes out at once — only at the end of a window. A window
  /// opens only after a frame actually went out.
  void _scheduleContext({bool trailing = false}) {
    if (_contextTimer != null || trailing) {
      _contextPending = true;
      _contextTimer ??= _contextWindow();
      return;
    }
    if (!_flushContext()) return;
    _contextTimer = _contextWindow();
  }

  Timer _contextWindow() => Timer(const Duration(milliseconds: _contextThrottleMs), () {
        _contextTimer = null;
        if (_contextPending) {
          _contextPending = false;
          _scheduleContext();
        }
      });

  static const int _contextThrottleMs = 400;
  bool _contextPending = false;

  bool _flushContext() {
    final frame = _currentContextFrame();
    if (frame == null) return false;
    for (final w in List<void Function(Map<String, Object?>)>.of(_contextWatchers)) {
      w(frame);
    }
    return true;
  }

  /// Tell whichever conversation is live — the call, the chat, or both —
  /// something the agent may want to speak up about (or, `quiet`, only know).
  void _reportEvent(String name, {String? detail, Map<String, Object?> data = const <String, Object?>{}}) {
    voice.reportEvent(name, detail: detail, data: data);
    _chat?._reportEvent(name, detail: detail, data: data);
  }

  bool _conversationLive = false;

  /// The call or the chat came up or went down: friction watches a
  /// customer only while a conversation is live.
  void _conversationStateChanged() {
    final live = voice.connected || (_chat?.connected ?? false);
    if (live == _conversationLive) return;
    _conversationLive = live;
    _friction.onCall(live, _clock());
    _armStall();
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
  /// opened a picker. The idle clock restarts (every agent's). Field edits do
  /// NOT count.
  void noteInteraction() {
    for (final g in _peers) {
      g._friction.onInteraction(g._clock());
      g._armStall();
    }
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
    _reportEvent(signal.name, detail: signal.detail, data: <String, Object?>{
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

  /// The component on screen came from the chat (its answer goes back on the
  /// chat's socket), not the call's page.
  bool _componentsFromChat = false;

  void _widgetArrived(Map<String, Object?> widget, {required bool fromChat}) {
    _componentsFromChat = fromChat;
    // Retained before it is dispatched, so a view mounted later still finds it.
    _pendingWidget = widget;
    components._onWidget(widget);
    _report((GraineListener l) => l.onWidget(widget));
  }

  void _widgetPending(Map<String, Object?> hint, {required bool fromChat}) {
    _componentsFromChat = fromChat;
    components._onPending(hint);
    _report((GraineListener l) => l.onWidgetPending(hint));
  }

  /// The customer answered a component: to the conversation that drew it.
  void _answerWidget(String widgetId, Map<String, Object?> data, String summary) {
    final chat = _chat;
    if (_componentsFromChat && chat != null && chat.connected) {
      chat.answerWidget(widgetId, data, summary);
    } else {
      voice.answerWidget(widgetId, data, summary);
    }
  }

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
      _bookingChanged();
      _pickTokens();
      // The brand's typeface, fetched now — both schemes — so it is drawn
      // from the first frame it can be, and a switch to dark never waits.
      loadDesignFonts(s.design);
      _variables.setDashboardDefaults(s.variables);
      _friction.configure(
          Friction.resolve(<FrictionConfig?>[FrictionConfig.fromJson(s.friction), _appFriction]));
      _armStall();
      _report((GraineListener l) => l.onSessionReady(s));
      voice._sessionChanged();
      // The setting names the trait that identifies the user: only now is
      // the identity known — it leaves the variables, and the native engine
      // and the page hear it.
      if (_traits != null) {
        _applyTraits();
        _announceVariables();
        _announceIdentity();
      }
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
      _sessionError = e is GraineException ? e : GraineException(msg, code: GraineErrorCode.network);
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
    if (err != null) {
      final r = EmbedRefusal.of(res.statusCode, data, retryAfter: res.headers['retry-after']);
      throw GraineException(err,
          code: r?.code ?? GraineErrorCode.unknown,
          codeName: r?.codeName,
          statusCode: res.statusCode,
          retryAfterSeconds: r?.retryAfterSeconds);
    }
    _sessionError = null;
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

  late final DesignFontLoader _fonts;

  /// THE DESIGN'S TYPEFACES THE SDK HAS LOADED — `family|weight` (the
  /// design's family, the weight it really has) → the family name the face
  /// is registered under, such as `"DM Sans|700"` → `"Graine-DMSans-700"`.
  ///
  /// The SDK fetches the faces the session's design draws with by itself
  /// (contract/DESIGN.md, "Fonts") and redraws its own surfaces as each one
  /// lands. For a host drawing its own UI in the brand's typeface: a loaded
  /// face IS its weight, so set `fontFamily` to it with `FontWeight.normal`.
  /// Empty until one loads — and for "system", which is never fetched.
  ValueListenable<Map<String, String>> get fontFaces => _fonts.loaded;

  /// Fetch and register the faces [design] draws with. The SDK does this for
  /// the session's design itself; call it for a design you hand a widget
  /// directly. Families listed in [GraineConfig.fonts] are the app's own and
  /// are never fetched. Safe to call again: each face is fetched once.
  Future<void> loadDesignFonts(ResolvedDesign? design) =>
      _fonts.load(design, origin: config.baseUrl, bundled: config.fonts);

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

  /// Stop every timer and detach the engine (tests; an app keeps its
  /// agents). The agent leaves the app's agents.
  @visibleForTesting
  void dispose() {
    if (identical(_group.byName[name], this)) _group.byName.remove(name);
    _contextTimer?.cancel();
    _stallTimer?.cancel();
    voice.detach();
    _chat?._dispose();
    components._cancel();
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }
}

/// The identity fields of one request (contract §1.3).
typedef _IdentityState = ({String? value, String installId, bool memory, String? timezone});

/// WHAT EVERY AGENT IN THE APP SHARES (MULTI-AGENT.md) — one app, one user,
/// one device: the agents themselves, by name, in the order they were
/// configured; the device (the install id, the zone, the kept choices); who
/// is signed in and their memory choice, and the screen — kept here for an
/// agent configured after them; the design's typefaces; and the window that
/// lets at most two taps a second through, however many engines saw them.
///
/// The app's agents share one ([GraineInApp.init]); an instance built for a
/// test alone has its own.
class _Agents {
  /// Every agent, by name, in the order configured.
  final Map<String, GraineInApp> byName = <String, GraineInApp>{};

  final _Device device = _Device(const MethodChannel('ai.graine.inapp/device'));

  /// One loader for the app: every face fetched once, whichever agent asks.
  DesignFontLoader? fonts;

  /// [GraineInApp.identify] was called, with [traits] (null: signed out).
  bool identified = false;
  Map<String, Object?>? traits;

  /// The memory choice made in this run for [traits]; null: the user's own
  /// last choice, kept on the device.
  bool? memory;

  /// The screen, and since when it has been shown.
  GraineScreen? screen;
  int? screenSince;

  int tapWindowAt = 0;
  int tapsInWindow = 0;

  /// The default agent, else the first one configured.
  GraineInApp? get primary => byName[GraineInApp.defaultName] ?? (byName.isEmpty ? null : byName.values.first);

  /// [g] is the agent under its name (a test installing a name again replaces it).
  void join(GraineInApp g) => byName[g.name] = g;
}

/// The SDK's routes (contract §5.1), whole — what the requests go to.
abstract final class _Routes {
  static const String ticket = '/api/embed/ticket';
  static const String signout = '/api/embed/identity/signout';
  static const String forget = '/api/embed/memory/forget';
  static const String memories = '/api/embed/memory/list';
  static const String newConversation = '/api/embed/conversation/new';
  static const String schedule = '/api/embed/calls/schedule';
  static const String list = '/api/embed/calls/list';
  static const String cancel = '/api/embed/calls/cancel';
}
