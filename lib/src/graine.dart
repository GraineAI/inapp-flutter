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
import 'dart:math' as math;

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
part 'verification.dart';

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
      {this.code = GraineErrorCode.unknown, this.codeName, this.statusCode, this.retryAfterSeconds, this.reason});

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

  /// The finer reason some refusals carry, when Graine gave one: with
  /// [GraineErrorCode.appNotVerified] `missing`, `expired`, `invalid`,
  /// `debug_token_unknown` (development mode: the debug token is not
  /// registered on the agent) or `debug_token_expired`; which part of a server
  /// token failed — `scope`, `user` or `agent` with [GraineErrorCode.tokenScope];
  /// `malformed`, `signature`, `unknown_key`, `issuer` or `not_yet_valid` with
  /// [GraineErrorCode.tokenInvalid]. Null otherwise.
  final String? reason;

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
    // Which app this is, for the declaration every request carries — and, in
    // development mode only, this install's debug token (logged once).
    unawaited(_group.platform.declaration());
    if (_verifier.usesDebugToken) unawaited(_group.platform.debugToken(_device));
    // Server tokens: nothing is asked while the app is in the background; back in front, one close to its expiry is.
    _foregroundWatchers.add(_clientTokens.setForeground);
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
    // The first server token is asked for now, before the session — a new connection, which waits for it.
    g._clientTokens.start();
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

  /// The native call engine's verification for one publishable key (the calls
  /// plugin's `verification` event): every client of that key folds it in —
  /// what proves more than it knows, never less ([_Verifier.noteNative]).
  static void _nativeVerification(Map<Object?, Object?> event) {
    final key = event['publishableKey'];
    if (key is! String || key.isEmpty) return;
    for (final g in _process.byName.values) {
      if (g.config.publishableKey == key) g._verifier.noteNative(event);
    }
  }

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
  /// (default: Flutter's FontLoader). [debugBuild] stands in for `kDebugMode`
  /// — what development mode's automatic setting goes by — for this agent and
  /// what it shares.
  @visibleForTesting
  static GraineInApp forTesting(GraineConfig config,
      {http.Client? httpClient,
      int Function()? clock,
      bool install = false,
      String name = defaultName,
      Directory? fontCacheDir,
      Future<void> Function(String name, Uint8List bytes)? fontRegistrar,
      GraineChatConnector? chatConnector,
      bool? debugBuild}) {
    final group = install ? _process : _Agents();
    if (debugBuild != null) group.debugBuild = debugBuild;
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
    g._clientTokens.start();
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
  /// for [GraineConfig.chatCloseDelaySeconds] (15 s by default) more; a host
  /// drawing its own calls
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
  ///
  /// [identityToken] (0.14.4) PROVES the identity, for an agent with "Require
  /// verified users" on: an HMAC of the identity value your server computes
  /// with the agent's user secret, or the ID token (JWT) of your own sign-in.
  /// It travels only inside the request's identity — never in variables,
  /// metadata, logs or a URL — and only with the value it was given for; it
  /// is held in memory only. Without one, the token already held is kept
  /// while the identity is the same user, and dropped — with the pass Graine
  /// issued for it — when another user signs in or nobody does
  /// (`identify(null)`). [setIdentityToken] replaces it for the same user;
  /// [identityTokenRefresher] renews it. A token over 4096 characters is not
  /// kept.
  void identify(Map<String, Object?>? traits, {bool? memory, String? identityToken}) {
    final group = _group;
    final next = traits == null ? null : Map<String, Object?>.of(traits);
    // The token changes in the same step as the identity: never sent with another value.
    _takeIdentityToken(next, identityToken);
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
    // The server token of whoever was identified: their sign-out carries it, before it is let go of (below).
    final tokenBefore = _clientTokens.newest;
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
    // device is no longer the last user's. Before the session names the trait
    // that identifies users, whether other traits are someone else is not
    // known: that is decided once it does — against who the user is THEN.
    if (before != null && session == null) {
      if (!deepEquals(before, _traits)) {
        // Kept until a session arrives, however many loads that takes: one that fails must not lose it.
        _leftBeforeSession.add((previous: before, to: _traits, token: tokenBefore));
        unawaited(loadSession());
      }
    } else if (before != null && (traits == null || _anotherUser(beforeValue, afterValue))) {
      unawaited(_signOut(before, tokenBefore));
    }
    // A chat belongs to whoever was identified when it connected — nobody to a
    // user included: their conversation is not the next identity's.
    if (_identityKey(beforeValue) != _identityKey(afterValue)) {
      // The server token held was minted for the identity before: let go of, and a fresh one asked for — before a
      // chat connects again for whoever is identified now, so its ticket waits for that one (ClientTokens.renew).
      _clientTokens.renew();
      _chat?._identityChanged();
    }
    // The user pass was issued for the last identity, not this one.
    if (!deepEquals(before, _traits) && (session == null || beforeValue != afterValue)) _verifier.dropUserPass();
    _verifier.resetUser();
    _announceVariables();
    _scheduleContext();
    _announceIdentity();
    if (!deepEquals(before, _traits)) _warnIfTraitsLackIdentity();
  }

  /// The traits as prompt variables and `context.user` — masked, and without
  /// the trait that identifies the user, which travels only in the identity
  /// channel. Before the session names that trait, all of them; again when it
  /// arrives.
  void _applyTraits() =>
      _variables.setIdentity(Identity.withoutIdentity(_traits, session?.identitySetting.field));

  // ── your app and your users (0.14.4) ───────────────────────────────────

  /// The verdicts for this app and user, and what goes with them.
  late final _Verifier _verifier = _Verifier(this);

  /// REPLACE THE IDENTITY TOKEN for the user [identify] named, without
  /// changing who they are: no sign-out, and an open chat stays open. Null
  /// (or empty) clears it. The new token rides with the next request — and
  /// reaches the voice page at once. For every agent the app configured.
  void setIdentityToken(String? token) {
    final group = _group;
    final kept = AppIdentity.identityToken(token);
    if (token != null && token.isNotEmpty && kept == null) _warnTokenTooLong();
    group.identityToken = kept;
    group.tokenTraits = kept == null || group.traits == null ? null : Map<String, Object?>.of(group.traits!);
    for (final g in _peers) {
      g._identityTokenChanged();
    }
  }

  /// HOW THE SDK GETS A FRESH IDENTITY TOKEN — your function, asked (at most
  /// once every 30 seconds, never twice at once) when Graine says the token
  /// expired or refuses an unverified user (the request is then sent once
  /// more with the new token), and before a conversation starts when the
  /// token is a JWT with less than a minute left. Return the new token, or
  /// null to keep the one held; a function that throws keeps it too. One for
  /// the app: set on any agent, every agent uses it.
  ///
  ///     graine.identityTokenRefresher = () => myBackend.graineIdentityToken();
  Future<String?> Function()? get identityTokenRefresher => _group.refresher;
  set identityTokenRefresher(Future<String?> Function()? refresher) => _group.refresher = refresher;

  /// THE VERDICTS ON THIS APP AND THIS USER, for this agent — `off` for each
  /// check until its session says the agent makes it; then whether this app
  /// is proven (App Attest / Play Integrity, a debug token in development
  /// mode) and this user verified, as Graine last said, with why not.
  ValueListenable<GraineVerification> get verification => _verifier.state;

  /// PROVE THIS APP NOW — App Attest on iOS, Play Integrity on Android —
  /// rather than as the first conversation starts: call it once the app has
  /// launched, so a conversation under "Require a verified app" never waits
  /// for a proof. Completes with the app's verdict ([verification]'s `app`):
  /// at once with the pass already held when it has six hours or more left;
  /// `off` when the agent does not check apps; in development mode, the
  /// verdict as it stands (a debug token is not proven, it is registered).
  Future<GraineAppVerdict> prepareAppVerification() async {
    final s = await loadSession();
    if (s == null) return _verifier.state.value.app;
    return _verifier.prove(ignoreBackoff: true);
  }

  /// THIS INSTALL'S DEBUG TOKEN while development mode is on for this agent
  /// ([GraineConfig.debugTokenMode]: a debug build by default) — the token
  /// its requests carry instead of a proof, and the one the SDK logs once
  /// per install for you to register under Agent → Embed & Widgets → Install
  /// → Development → Debug tokens. Null in a release build that did not opt
  /// in, and until it has been read from the device.
  String? get debugToken => _verifier.debugToken;

  /// The token changes in the same step as the identity (APP-IDENTITY.md
  /// §1.3): a new one is taken with [next]; without one, the token held is
  /// kept only while [next] is the same user, and dropped otherwise.
  void _takeIdentityToken(Map<String, Object?>? next, String? given) {
    final group = _group;
    if (given != null) {
      final kept = AppIdentity.identityToken(given);
      if (given.isNotEmpty && kept == null) _warnTokenTooLong();
      group.identityToken = next == null ? null : kept;
      group.tokenTraits = next == null || kept == null ? null : next;
    } else if (group.identityToken != null && (next == null || !_sameUser(group.tokenTraits, next))) {
      group.identityToken = null;
      group.tokenTraits = null;
    }
  }

  /// Whether [a] and [b] name the same user for every agent: the same value of
  /// each agent's identity trait — or, before every session has said which
  /// trait that is, exactly the same traits.
  bool _sameUser(Map<String, Object?>? a, Map<String, Object?>? b) {
    if (deepEquals(a, b)) return true;
    final peers = _peers;
    if (peers.any((GraineInApp g) => g.session == null)) return false;
    return peers.every((GraineInApp g) {
      final field = g.session!.identitySetting.field;
      final value = Identity.pick(a, field);
      return value != null && value == Identity.pick(b, field);
    });
  }

  void _warnTokenTooLong() => debugPrint('[Graine] The identity token was not kept: an identity token is at most '
      '${AppIdentity.maxIdentityTokenLength} characters.');

  /// The token changed for the same user: nothing is proven about it yet, and
  /// the voice page hears it for the tickets it mints.
  void _identityTokenChanged() {
    _verifier.resetUser();
    for (final w in List<void Function()>.of(_identityWatchers)) {
      w();
    }
    // The native call engine, for the calls it places and answers.
    GraineCalls._identityTokenChanged(this);
  }

  /// ASK THE APP FOR A FRESH IDENTITY TOKEN ([identityTokenRefresher]) — at
  /// most once every 30 seconds, never twice at once (a caller meanwhile shares
  /// the one asked). Completes true when a NEW token was taken. One that
  /// throws, returns null or empty, or arrives after another user signed in
  /// changes nothing.
  Future<bool> _refreshIdentityToken() {
    final group = _group;
    final pending = group.refreshing;
    if (pending != null) return pending;
    final refresher = group.refresher;
    if (refresher == null) return Future<bool>.value(false);
    final now = _clock();
    final last = group.refreshStartedAt;
    if (last != null && now - last < AppIdentity.refresherIntervalMs) return Future<bool>.value(false);
    group.refreshStartedAt = now;
    final asked = group.traits;
    final before = group.identityToken;
    Future<bool> run() async {
      String? fresh;
      try {
        fresh = await refresher();
      } catch (e) {
        debugPrint('[Graine] identityTokenRefresher failed (${e.runtimeType}); the identity token is kept as it was.');
        return false;
      }
      final token = AppIdentity.identityToken(fresh);
      final traits = group.traits;
      if (token == null || traits == null || !deepEquals(traits, asked)) return false;
      if (token == before) return false;
      group.identityToken = token;
      group.tokenTraits = Map<String, Object?>.of(traits);
      for (final g in _peers) {
        g._identityTokenChanged();
      }
      return true;
    }

    final running = run();
    group.refreshing = running;
    unawaited(running.whenComplete(() {
      if (identical(group.refreshing, running)) group.refreshing = null;
    }));
    return running;
  }

  /// A RING ARRIVED for the agent the app calls [agentName] (APP-IDENTITY.md
  /// §6): before the person answers, its proof is refreshed and the app is
  /// asked for a fresh token, in the background.
  static void _ringArrived(String? agentName) {
    final g = _agentNamed(agentName) ?? maybeInstance;
    g?._verifier.ring();
  }

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
  /// `identityRequired` when nobody is identified by the trait this agent
  /// identifies users by (the message names it), `deviceLimit` from a device
  /// that is not theirs, and the agent's settings' own refusal when they
  /// could not load — `unavailable`, `network`, `invalidKey`… with Graine's
  /// sentence (the next call asks for them again).
  ///
  /// Asked before the agent's settings have arrived (a screen opened at
  /// launch), it waits for them — bounded by their request's timeout — and
  /// only then decides: never `identityRequired` for settings on their way.
  /// It is for the user identified when it was asked: when someone else was
  /// identified while the settings loaded, nothing is forgotten for anyone
  /// (`identityRequired`).
  Future<int> forgetMemory() async {
    final who = await _userAfterSession();
    final value = who.value;
    if (value == null) throw _identityRequired(who.session);
    final deleted =
        (await _embed(_Routes.forget, const <String, Object?>{}, identity: value, overrideIdentity: true))['deleted'];
    // The conversation is part of what was forgotten: off the screen too — only once it is gone.
    _chat?.clear();
    return deleted is num && deleted.isFinite && deleted >= 0 ? deleted.round() : 0;
  }

  /// Graine lets go of the conversation it kept for this agent and the current
  /// user, so the next chat starts fresh ([GraineChatSession.newConversation]).
  /// Nobody identified: nothing was kept, nothing to ask. For the user
  /// identified when it was asked, as [forgetMemory].
  Future<void> _letGoOfConversation() async {
    final value = (await _userAfterSession()).value;
    if (value == null) return;
    await _embed(_Routes.newConversation, const <String, Object?>{}, identity: value, overrideIdentity: true);
  }

  /// WHAT THE AGENT REMEMBERS about the current user, newest first (at most
  /// 100), already redacted — for a "what you remember about me" screen.
  /// Only from a device that is theirs. Throws a [GraineException]:
  /// `identityRequired` when nobody is identified by the trait this agent
  /// identifies users by (the message names it), `deviceLimit` from a device
  /// that is not theirs, and the agent's settings' own refusal when they
  /// could not load — `unavailable`, `network`, `invalidKey`… with Graine's
  /// sentence (the next call asks for them again). Whether the agent
  /// remembers anyone at all is no error: `session?.memory?.enabled`.
  ///
  /// Asked before the agent's settings have arrived (a screen opened at
  /// launch), it waits for them — bounded by their request's timeout — and
  /// only then decides: never `identityRequired` for settings on their way.
  /// It answers only about the user identified when it was asked: when
  /// someone else was identified while the settings loaded, it refuses
  /// (`identityRequired`) — never another user's memories.
  Future<List<GraineMemory>> memories() async {
    final who = await _userAfterSession();
    final value = who.value;
    if (value == null) throw _identityRequired(who.session);
    return GraineMemory.listFrom(
        await _embed(_Routes.memories, const <String, Object?>{}, identity: value, overrideIdentity: true));
  }

  /// One page of the current user's past sessions with this agent, as Graine
  /// answers it ([GraineChatSession.pastSessions] keeps them): the first, or
  /// the one after [cursor]. Waits for the session first. Throws a
  /// [GraineException] — `identityRequired` when nobody is identified
  /// (nothing is asked), `deviceLimit` from a device that is not theirs, the
  /// session's own refusal when it could not load.
  Future<Map<String, Object?>> _pastSessionsPage(String? cursor) async {
    final s = await _sessionOrThrow();
    if (_identityValueFor(_traits) == null) throw _identityRequired(s);
    return _embed(_Routes.pastSessions, <String, Object?>{if (cursor != null) 'cursor': cursor});
  }

  /// One past session's transcript, as Graine answers it
  /// ([GraineChatSession.sessionTranscript]). Throws as [_pastSessionsPage]
  /// does, and `notFound` for a session that is not the user's. For the user
  /// identified when it was asked, as [memories].
  Future<Map<String, Object?>> _sessionTranscript(String id) async {
    final who = await _userAfterSession();
    final value = who.value;
    if (value == null) throw _identityRequired(who.session);
    return _embed(_Routes.sessionTranscript, <String, Object?>{'id': id}, identity: value, overrideIdentity: true);
  }

  /// `identityRequired`'s sentence for a request whose user was replaced while
  /// the session loaded — the same words on every Graine SDK.
  static const String _someoneElseIdentified = "Someone else was identified while the agent's settings were loading, "
      'so nothing was asked for the customer identified before. Ask again for the customer identified now.';

  /// WHO A ONE-SHOT REQUEST IS FOR, once the session is here (it names the
  /// trait that identifies users): the identity value of the user identified
  /// when the request was made, read once — what the request then sends. A
  /// request belongs to whoever was identified when it was made: when the app
  /// identified someone else, or nobody, while the session was on its way,
  /// nothing is asked — `identityRequired`, never an answer about the next
  /// user, a booking in their name, or their memories forgotten. The same
  /// user identified again (other traits, another spelling) is still them,
  /// compared as Graine keys users; a request made with nobody identified is
  /// for whoever is identified when it arrives. Throws the session's own
  /// refusal when it could not load. Not for what follows whoever is
  /// identified (the past sessions list, the upcoming calls).
  Future<({SessionConfig session, String? value})> _userAfterSession() async {
    final asked = _traits;
    final s = await _sessionOrThrow();
    final field = s.identitySetting.field;
    final now = Identity.pick(_traits, field);
    final wanted = Identity.pick(asked, field);
    if (wanted != null && _userKey(field, wanted) != _userKey(field, now)) {
      throw now == null
          ? _identityRequired(s)
          : const GraineException(_someoneElseIdentified, code: GraineErrorCode.identityRequired);
    }
    return (session: s, value: now);
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

  /// WHY A REQUEST THAT NEEDS THE USER HAS NONE, naming the trait this agent
  /// identifies users by — the session's Who is the user? setting, so only
  /// once [s] has arrived: nobody identified, or traits without a usable
  /// value of it (the usual wiring mistake: `user_id` sent to an agent that
  /// identifies people by `customer_id`).
  String _missingIdentity(SessionConfig s) {
    final field = s.identitySetting.field;
    if (_traits == null) return 'Nobody is identified. Call identify() with the customer\'s "$field" first.';
    return 'identify() was given no usable "$field" — the trait this agent identifies customers by '
        "(Who is the user? in the agent's memory settings). Until it is, conversations are anonymous and nothing is "
        'remembered.';
  }

  /// `identityRequired`, in [_missingIdentity]'s words.
  GraineException _identityRequired(SessionConfig s) =>
      GraineException(_missingIdentity(s), code: GraineErrorCode.identityRequired);

  /// ONE LINE FOR THE DEVELOPER when identify() was given traits without a
  /// usable value of the trait this agent identifies users by — as the
  /// session lands (only it names the trait), and as identify() does with
  /// other traits. A sign-out is no mistake.
  void _warnIfTraitsLackIdentity() {
    final s = session;
    if (s == null || _traits == null || _identityValueFor(_traits) != null) return;
    debugPrint('[Graine] ${name == defaultName ? '' : '$name: '}${_missingIdentity(s)}');
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
  Future<void> _signOut(Map<String, Object?> previous, [String? token]) async {
    try {
      final s = await loadSession();
      if (s == null) return;
      final value = Identity.pick(previous, s.identitySetting.field);
      if (value != null) await _sendSignOut(value, token: token);
    } catch (e) {
      debugPrint('[Graine] Sign-out could not reach Graine ($e); the device is released after 30 days unused.');
    }
  }

  /// The users who left before the session named the trait that identifies
  /// users — each with the traits they left for (null: a sign-out) — until a
  /// session arrives ([_signOutWhoLeft]).
  final List<_Left> _leftBeforeSession = <_Left>[];

  /// THE USERS WHO LEFT BEFORE THE SESSION NAMED THE TRAIT that identifies
  /// users, signed out now that [s] has — as a switch after it is: other
  /// traits of the same user are no switch. Never the user the app has
  /// identified by now (away and back, out and in again): the device is still
  /// theirs, and a sign-out would stop it ringing for them. Each user once;
  /// users compared as Graine keys them (an address in any case, a phone
  /// number however it is written, is one user).
  void _signOutWhoLeft(SessionConfig s) {
    if (_leftBeforeSession.isEmpty) return;
    final left = List<_Left>.of(_leftBeforeSession);
    _leftBeforeSession.clear();
    final field = s.identitySetting.field;
    final now = _userKey(field, Identity.pick(_traits, field));
    final signedOut = <String>{};
    for (final l in left) {
      final value = Identity.pick(l.previous, field);
      final was = _userKey(field, value);
      if (value == null || was == null || was == now) continue;
      final to = l.to;
      if (to != null) {
        final next = _userKey(field, Identity.pick(to, field));
        if (next == null || next == was) continue;
      }
      if (signedOut.add(was)) unawaited(_sendSignOut(value, token: l.token));
    }
  }

  /// A raw identity value as Graine keys the user — normalised for [field]
  /// (the value itself when it cannot be); null for none.
  static String? _userKey(String field, String? value) =>
      value == null ? null : (Identity.normaliseValue(field, value) ?? value);

  /// Both values name a user, and not the same one as Graine keys them: an
  /// address in any case, a phone number however it is written, is one user
  /// — signing them out would unlink the device from the user still on it.
  bool _anotherUser(String? a, String? b) {
    final s = session;
    if (s == null || a == null || b == null) return false;
    final field = s.identitySetting.field;
    return _userKey(field, a) != _userKey(field, b);
  }

  /// Graine releases this device from the user [value] names. Best effort.
  Future<void> _sendSignOut(String value, {String? token}) async {
    try {
      await _embed(_Routes.signout, const <String, Object?>{},
          identity: value, overrideIdentity: true, leaving: true, leaverToken: token);
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

  /// The page's ticket requests carry the identity token too (APP-IDENTITY.md
  /// §1.3): only in this message, only with the value it was given for.
  Map<String, Object?> _identityMessageOf(_IdentityState id) {
    final token = _verifier.tokenFor(id.value);
    return <String, Object?>{
      'type': ProtocolOut.identity,
      'value': id.value,
      'installId': id.installId,
      'memory': id.memory,
      if (id.timezone != null) 'timezone': id.timezone,
      if (token != null) 'token': token,
    };
  }

  // ── requests to Graine ──────────────────────────────────────────────────

  static const Map<String, String> _json = <String, String>{'Content-Type': 'application/json'};

  Uri _embedUrl(String route) => Uri.parse('${Protocol.trimTrailingSlashes(config.baseUrl)}$route');

  /// THIS AGENT'S SERVER TOKENS (CLIENT-TOKENS.md §2.3): from
  /// [GraineConfig.tokenProvider], on this agent's clock. Without a provider
  /// none are in play and no request carries one. Every request the Dart side
  /// makes to Graine asks it for the token it carries; the engine page and the
  /// native call engine are handed each new one.
  late final ClientTokens _clientTokens = ClientTokens(config.tokenProvider, clock: _clock);

  /// ONE POST TO AN SDK ROUTE, as JSON — with the server token when tokens are
  /// in play (CLIENT-TOKENS.md §2.2): a new connection (the session, a
  /// ticket) waits for a usable token first, and a refusal a fresh token can
  /// lift goes once more with a different one. Without a provider the body
  /// goes exactly as it is. A network error or a timeout is thrown as it is.
  Future<http.Response> _postEmbed(String route, Map<String, Object?> payload,
          {required bool newConnection, required Duration timeout, bool pinned = false, String? pinnedToken}) =>
      ClientTokenWire.post<http.Response>(
        _clientTokens,
        payload,
        newConnection: newConnection,
        pinned: pinned,
        pinnedToken: pinnedToken,
        send: (Map<String, Object?> body) =>
            _http.post(_embedUrl(route), headers: _json, body: jsonEncode(body)).timeout(timeout),
        refreshable: (http.Response res) =>
            (res.statusCode < 200 || res.statusCode > 299) && ClientTokenRules.isRefreshable(res.statusCode, _bodyOf(res)),
      );

  /// An answer's body as JSON — UTF-8 whatever the header says (a Devanagari
  /// variable must survive); empty when it is not a JSON object.
  static Map<String, Object?> _bodyOf(http.Response res) {
    try {
      return Js.asMap(jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true))) ?? <String, Object?>{};
    } catch (_) {
      return <String, Object?>{};
    }
  }

  /// ONE REQUEST TO AN SDK ROUTE ([_Routes]): the key, [body], and the identity fields
  /// (contract §1.3) — the current user's, or [identity] with [overrideIdentity]: the user a
  /// request was asked for (memories, forget, a booking, a transcript — still the current user,
  /// [_userAfterSession] checked) or, with [leaving], the user a sign-out names: the user who
  /// left, so nothing of theirs rides with it — no token, no user pass, no refresh. A token and a
  /// pass only ever ride with the value they were issued for (_Verifier.tokenFor, userPassFor). Throws a
  /// [GraineException] with the contract's code on a refusal.
  ///
  /// Every request also carries the app's declaration (APP-IDENTITY.md §1.1)
  /// and, inside the identity, its token and user pass. Refused for want of a
  /// proof (`app_not_verified`), the app proves itself and the request is
  /// sent once more; refused for an unverified user (`identity_unverified`),
  /// [identityTokenRefresher] is asked for a new token and the request is
  /// sent once more with it.
  ///
  /// Inside that door, the server token, with tokens in play
  /// (CLIENT-TOKENS.md §2.2; [_postEmbed]).
  Future<Map<String, Object?>> _embed(String path, Map<String, Object?> body,
      {String? identity, bool overrideIdentity = false, bool leaving = false, String? leaverToken}) async {
    await _sessionOrThrow();
    var proved = false;
    var refreshed = false;
    while (true) {
      final id = await _identityState(waitForSession: false);
      final value = overrideIdentity ? identity : id.value;
      final payload = <String, Object?>{
        'publishableKey': config.publishableKey,
        ...body,
        ...Identity.requestFields(
          value: value,
          // A sign-out names the user who left: nothing of theirs rides with it.
          token: leaving ? null : _verifier.tokenFor(value),
          pass: leaving ? null : _verifier.userPassFor(value),
          installId: id.installId,
          memory: id.memory,
          timezone: id.timezone,
        ),
        ...await _verifier.appEntry(),
      };
      final http.Response res;
      try {
        // Inside the door: the server token, with tokens in play (refused for it, once more with a fresh one).
        // A sign-out carries the server token of the user who left ([leaverToken]), never the next one's.
        res = await _postEmbed(path, payload,
            newConnection: false, timeout: const Duration(seconds: 20), pinned: leaving, pinnedToken: leaverToken);
      } catch (e) {
        throw GraineException('Could not reach Graine: $e', code: GraineErrorCode.network);
      }
      final data = _bodyOf(res);
      final refusal = EmbedRefusal.of(res.statusCode, data, retryAfter: res.headers['retry-after']);
      if (refusal == null) return data;
      if (await _answerRefusal(refusal, proved: proved, refreshed: refreshed, mayRefresh: !leaving)) {
        if (refusal.code == GraineErrorCode.appNotVerified) proved = true;
        if (refusal.code == GraineErrorCode.identityUnverified) refreshed = true;
        continue;
      }
      throw _refused(refusal);
    }
  }

  /// WHETHER A REFUSED REQUEST IS SENT ONCE MORE (APP-IDENTITY.md §2.3):
  /// `app_not_verified` — after the app proved itself, when that earned a new
  /// pass (never in development mode, which has no proof to make);
  /// `identity_unverified` — when [identityTokenRefresher] gave a new token
  /// (waited for at most 10 s). `app_not_allowed` and everything else: no.
  Future<bool> _answerRefusal(EmbedRefusal r,
      {required bool proved, required bool refreshed, required bool mayRefresh}) async {
    _verifier.noteRefusal(r);
    if (r.code == GraineErrorCode.appNotVerified && !proved && await _verifier.canProve()) {
      final before = _verifier.livePass;
      await _verifier.prove(ignorePass: true, ignoreBackoff: true);
      final after = _verifier.livePass;
      return after != null && after != before;
    }
    if (r.code == GraineErrorCode.identityUnverified && !refreshed && mayRefresh) {
      return _refreshIdentityToken()
          .timeout(const Duration(milliseconds: AppIdentity.waitMs), onTimeout: () => false);
    }
    return false;
  }

  static GraineException _refused(EmbedRefusal r) => GraineException(r.message,
      code: r.code,
      codeName: r.codeName,
      statusCode: r.statusCode,
      retryAfterSeconds: r.retryAfterSeconds,
      reason: r.reason);

  /// The session, or the reason there is none: the session's own refusal
  /// (a key Graine rejected, say), else Graine out of reach. Waits for one on
  /// its way (its request's timeout bounds the wait); after one that failed,
  /// asks again.
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
  ///
  /// A conversation starts here (APP-IDENTITY.md): a JWT identity token about
  /// to expire is renewed first, and under "Require a verified app" a proof on
  /// its way is waited for (each at most 10 s). The answer's `verification`
  /// updates [verification] and keeps the passes it carries. A refusal for the
  /// app or the user is answered as [_embed] answers it — and when it stands,
  /// it is thrown: the direct socket never goes round the agent's own rule.
  /// A new connection: with tokens in play it carries a usable server token,
  /// waiting for one first; refused for the token or the publishable key
  /// ([ClientTokenRules.refusals]) it throws that refusal — final for the
  /// conversation, like a refusal for the app or the user.
  Future<({String ticket, String wsUrl})?> _ticket(String mode, Map<String, String> variables, _IdentityState id,
      {String? callId}) async {
    await _verifier.beforeConversation();
    var proved = false;
    var refreshed = false;
    var who = id;
    while (true) {
      final http.Response res;
      try {
        final metadata = Protocol.ticketMetadata(variables);
        // Inside the door: a new connection's server token (a usable one, waited for first).
        res = await _postEmbed(
            _Routes.ticket,
            <String, Object?>{
              'publishableKey': config.publishableKey,
              'mode': mode,
              if (metadata != null) 'metadata': metadata,
              ...Identity.requestFields(
                value: who.value,
                token: _verifier.tokenFor(who.value),
                pass: _verifier.userPassFor(who.value),
                installId: who.installId,
                memory: who.memory,
                timezone: who.timezone,
                callId: callId,
              ),
              ...await _verifier.appEntry(),
            },
            newConnection: true,
            timeout: const Duration(seconds: 15));
      } catch (_) {
        // No ticket is not an error: the direct socket carries the chat.
        return null;
      }
      final data = _bodyOf(res);
      if (res.statusCode >= 200 && res.statusCode <= 299) {
        _verifier.noteVerification(data['verification'], value: who.value);
        final ticket = data['ticket'];
        final url = data['wsUrl'];
        if (ticket is String && ticket.isNotEmpty && url is String && url.isNotEmpty) {
          return (ticket: ticket, wsUrl: url);
        }
        return null;
      }
      final refusal = EmbedRefusal.of(res.statusCode, data, retryAfter: res.headers['retry-after']);
      // Refused for the server token or the key: final for the conversation — the direct socket is no other way past it.
      if (refusal != null && ClientTokenRules.refusals.contains(refusal.code.wire)) throw _refused(refusal);
      final code = refusal?.code;
      if (refusal == null ||
          (code != GraineErrorCode.appNotAllowed &&
              code != GraineErrorCode.appNotVerified &&
              code != GraineErrorCode.identityUnverified)) {
        return null;
      }
      if (await _answerRefusal(refusal, proved: proved, refreshed: refreshed, mayRefresh: true)) {
        if (code == GraineErrorCode.appNotVerified) proved = true;
        if (code == GraineErrorCode.identityUnverified) refreshed = true;
        who = await _identityState(waitForSession: false);
        continue;
      }
      throw _refused(refusal);
    }
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
  /// identity trait). False until the session has arrived — read it where
  /// [bookingListenable] redraws, not once at launch: it fires when the
  /// session arrives and when the user changes. `GraineBooking.show` opens
  /// the SDK's own booking sheet.
  bool get bookingAvailable => bookingBlocker == null;

  /// Why [bookingAvailable] is false, as the booking sheet says it:
  /// [GraineErrorCode.schedulingOff] (the agent takes no bookings, or Graine
  /// cannot ring this phone) or [GraineErrorCode.identityRequired] (nobody
  /// identified); null when it is true. Never `identityRequired` before the
  /// session has arrived: until then it is `schedulingOff`, meaning only
  /// "not yet" — [bookingUnavailableReason] tells the two apart (`notLoaded`).
  GraineErrorCode? get bookingBlocker =>
      Booking.blocker(session?.calls, platform: _bookingPlatform, identified: _identityValueFor(_traits) != null);

  /// WHY [bookingAvailable] IS FALSE, in words an app can act on (the same
  /// rule as [bookingBlocker], finer), checked in this order: `not_loaded`
  /// (the session has not arrived — nothing to tell the customer yet; after
  /// one that could not load, [loadSession] asks again, as the next request
  /// does), `rings_not_set_up` (Graine cannot ring this phone),
  /// `scheduling_off` (the agent takes no bookings) and `not_identified`
  /// (nobody is identified); null when booking is available.
  /// [bookingListenable] fires whenever it may have changed — the session
  /// arriving included, even while booking stays unavailable — so read it
  /// again there.
  GraineBookingUnavailableReason? get bookingUnavailableReason => Booking.unavailableReason(session?.calls,
      platform: _bookingPlatform, identified: _identityValueFor(_traits) != null, loaded: session != null);

  /// THE TIMES THE SDK'S OWN BOOKING SHEET OFFERS on [day] — the device's day
  /// holding it — for a picker of your own: the sheet's 5-minute steps, from
  /// the earliest the rules allow ([GraineSchedulingRules.minLeadMinutes]
  /// from now, rounded up) to the latest ([GraineSchedulingRules.maxDaysAhead]),
  /// in the device's time zone — and, when the agent has a calling window
  /// ([GraineSchedulingRules.callingWindow]), only the times inside it: its
  /// days, from its start up to, not including, its end, on the device's
  /// clock. Empty for a day outside them — and empty until the session has
  /// arrived, since only it says what the agent allows (no time is offered
  /// on a guess; read it again when [bookingListenable] fires). Whether the
  /// customer can book at all is [bookingAvailable] ([bookingUnavailableReason]
  /// says why not); Graine checks the window again when the call is booked
  /// ([scheduleCall] — `outsideWindow`).
  List<DateTime> bookingSlots(DateTime day, {DateTime? now}) => session == null
      ? const <DateTime>[]
      : BookingClock.device.slotsOn(schedulingRules, day, now ?? DateTime.fromMillisecondsSinceEpoch(_clock()));

  /// The device's time zone (IANA, "Asia/Kolkata"), once the SDK has read it —
  /// the booking sheet names it beside the time chosen. Null before then.
  String? get deviceTimezone => _device.timezoneNow;

  /// [bookingAvailable], for a widget that redraws when it changes — and
  /// whenever [bookingUnavailableReason] changes while it stays false: the
  /// session arriving (`notLoaded` gives way to the real reason), the user
  /// signing in or out. A widget that shows the reason, or offers
  /// [bookingSlots], reads them again in its builder.
  ValueListenable<bool> get bookingListenable => _bookable;
  final _BookingNotifier _bookable = _BookingNotifier();

  /// The session arrived, or the user changed: whether they can book, and why not, again.
  void _bookingChanged() => _bookable.update(bookingAvailable, bookingUnavailableReason);

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
  /// `identityRequired`, `rateLimited`… — all a [GraineException]. It waits
  /// for the agent's settings first; `identityRequired` too when someone else
  /// (or nobody) was identified while they loaded — a call is never booked
  /// for a user who did not ask for it.
  Future<GraineScheduledCall> scheduleCall({required DateTime at, String? reason}) async {
    final why = reason?.trim();
    if (why != null && why.length > ScheduledCalls.maxReasonLength) {
      throw const GraineException('A booking\'s reason is at most ${ScheduledCalls.maxReasonLength} characters.',
          code: GraineErrorCode.invalidRequest);
    }
    final who = await _userAfterSession();
    final rules = schedulingRules;
    // Refused in the booking sheet's words (Booking.errorLine), the same on every SDK.
    GraineException refused(GraineErrorCode code) => GraineException(Booking.errorLine(code, rules), code: code);
    if (!rules.usersCanBook) throw refused(GraineErrorCode.schedulingOff);
    final now = DateTime.fromMillisecondsSinceEpoch(_clock());
    if (at.isBefore(rules.earliest(now))) throw refused(GraineErrorCode.tooSoon);
    if (at.isAfter(rules.latest(now))) throw refused(GraineErrorCode.tooFar);
    final data = await _embed(
        _Routes.schedule,
        <String, Object?>{
          'at': ScheduledCalls.atWire(at),
          if (why != null && why.isNotEmpty) 'reason': why,
        },
        identity: who.value,
        overrideIdentity: true);
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

  // ── workflows the app starts (0.14.4) ───────────────────────────────────

  /// START ONE OF YOUR OUTREACH WORKFLOWS FOR THE USER THIS APP SIGNED IN — a
  /// welcome call after sign-up, a follow-up after an order — with no server
  /// of your own. The workflow must have "Your app can start this" on (its
  /// Connect tab); [workflow] is its exact name or its id (`owf_…`).
  ///
  /// The run is for the identified user — [identify] with the agent's
  /// identity trait first — never for anyone [data] names. [data]: the
  /// contact fields the workflow allows — text (200 characters), numbers,
  /// yes/no; at most 12, the first 12 in the map's order. Anything else is
  /// left out, never refused.
  ///
  /// [idempotencyKey]: two calls with the same key start one run. Without
  /// one the SDK makes one for the call, and asks once more with it when a
  /// request got no answer.
  ///
  /// Completes with the run — [GraineWorkflowRun.alreadyRunning] when the
  /// user already had one of this workflow under way (that run, never a
  /// second). Throws a [GraineException]: `invalidRequest` (no workflow, a
  /// key that is not one) and `identityRequired` (nobody identified, or
  /// someone else identified while the agent's settings loaded: nothing is
  /// asked) on the device; from Graine `notAllowed`, `notVerified`,
  /// `rateLimited` ([GraineException.retryAfterSeconds]), `unavailable`,
  /// `invalidRequest` (a field the workflow needs that your app may not
  /// send); `network` when no answer came twice; the session's own refusal
  /// when it could not be loaded.
  Future<GraineWorkflowRun> startWorkflow(String workflow,
      {Map<String, Object?> data = const <String, Object?>{}, String? idempotencyKey}) async {
    final name = Workflows.name(workflow);
    if (name == null) throw const GraineException(Workflows.nameMessage, code: GraineErrorCode.invalidRequest);
    if (idempotencyKey != null && !Workflows.isIdempotencyKey(idempotencyKey)) {
      throw const GraineException(Workflows.keyMessage, code: GraineErrorCode.invalidRequest);
    }
    final key = idempotencyKey ?? Workflows.newKey();
    // Read once, now: a map the app changes afterwards changes nothing that is sent.
    final fields = Workflows.data(data);
    // For the user identified when it was asked: one replaced while the session loaded never has a run started for
    // them (_userAfterSession refuses with identityRequired), and both tries name that same user — with their proof.
    final who = await _userAfterSession();
    if (who.value == null) throw _identityRequired(who.session);
    final body = <String, Object?>{'workflow': name, 'data': fields, 'idempotencyKey': key};
    Map<String, Object?> answer;
    try {
      answer = await _embed(_Routes.startWorkflow, body, identity: who.value, overrideIdentity: true);
    } on GraineException catch (e) {
      // No answer: the start may have been made or not. The same key again is answered with the run
      // it made, or makes it now — never two. A refusal is Graine's answer: never asked again.
      if (e.code != GraineErrorCode.network) rethrow;
      await Future<void>.delayed(Workflows.retryDelay);
      answer = await _embed(_Routes.startWorkflow, body, identity: who.value, overrideIdentity: true);
    }
    final run = Workflows.runFrom(answer);
    if (run == null) {
      throw const GraineException('The workflow was started, but its run id did not come back.',
          code: GraineErrorCode.unknown, codeName: 'bad_response');
    }
    return run;
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

  /// SOMETHING WORTH SPEAKING UP ABOUT: the agent may speak first — the
  /// customer tapped a reminder, the app opened the chat, and the agent opens
  /// with its check-in question. Told to this agent's live call or chat; with
  /// neither live it is dropped, so open the chat and wait for it to connect
  /// first. Paced by the agent: 20 s apart and 3 per conversation by default;
  /// [data] may carry `cooldown_seconds`, `max_per_session`, or `quiet: true`
  /// to record it without speaking (they travel at the event's own level);
  /// anything else travels under the event's `data` — a `name` or `detail`
  /// there never replaces [name] or [detail] ([ChatWire.appEvent], the same
  /// event on the call and in the chat). [track] informs without speaking.
  /// New in 0.14.4.
  void reportEvent(String name, {String? detail, Map<String, Object?> data = const <String, Object?>{}}) {
    final n = name.trim();
    if (n.isEmpty) return;
    final d = detail?.trim();
    _reportEvent(n, detail: d == null || d.isEmpty ? null : d, data: data);
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

  /// Which registered actions the agent can call, and which it cannot — by
  /// what the session declares. Log this once the session has arrived
  /// ([GraineListener.onSessionReady], [sessionListenable]): before it,
  /// nothing is declared yet and every registered action reads `undeclared`.
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
      // What the agent checks: the verdicts start from it, and the app proves itself if asked.
      unawaited(_verifier.sessionArrived(s));
      // The setting names the trait that identifies the user: only now is
      // the identity known — it leaves the variables, and the native engine
      // and the page hear it.
      if (_traits != null) {
        _applyTraits();
        _announceVariables();
        _announceIdentity();
        _warnIfTraitsLackIdentity();
      }
      // Whoever left before the trait was known — this load's wait or an earlier one that failed — signed out now.
      _signOutWhoLeft(s);
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
    // Which app is asking (APP-IDENTITY.md §1.1), on this request too — and inside the door the server token: a new
    // connection, so it goes with a usable one or waits at most 10 s; refused for it, a fresh one and once more.
    final app = await _verifier.appEntry();
    final res = await _postEmbed(_Routes.session, <String, Object?>{'publishableKey': config.publishableKey, ...app},
        newConnection: true, timeout: const Duration(seconds: 25));
    // UTF-8 whatever the header says: a Devanagari variable must survive.
    final data = _bodyOf(res);
    final err = SessionConfig.errorFor(res.statusCode, data);
    if (err != null) {
      final r = EmbedRefusal.of(res.statusCode, data, retryAfter: res.headers['retry-after']);
      throw GraineException(err,
          code: r?.code ?? GraineErrorCode.unknown,
          codeName: r?.codeName,
          statusCode: res.statusCode,
          retryAfterSeconds: r?.retryAfterSeconds,
          reason: r?.reason);
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
    // An app pass running low is refreshed as the app comes back (APP-IDENTITY.md §3.3).
    if (foreground) _verifier.foreground();
  }

  /// Stop every timer and detach the engine (tests; an app keeps its
  /// agents). The agent leaves the app's agents.
  @visibleForTesting
  void dispose() {
    if (identical(_group.byName[name], this)) _group.byName.remove(name);
    _contextTimer?.cancel();
    _stallTimer?.cancel();
    _clientTokens.dispose();
    voice.detach();
    _chat?._dispose();
    components._cancel();
    _verifier.dispose();
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }
}

/// The identity fields of one request (contract §1.3).
typedef _IdentityState = ({String? value, String installId, bool memory, String? timezone});

/// A user who left before the session named the trait that identifies users: their traits, and the
/// traits identify() was given instead (null: a sign-out).
typedef _Left = ({Map<String, Object?> previous, Map<String, Object?>? to, String? token});

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

  /// The identity token (APP-IDENTITY.md §1.3) — memory only — and the traits
  /// it was given with: it is sent only with the identity value they carry.
  String? identityToken;
  Map<String, Object?>? tokenTraits;

  /// The app's way to a fresh token, and the one refresh at a time it runs.
  Future<String?> Function()? refresher;
  Future<bool>? refreshing;
  int? refreshStartedAt;

  /// A debug build (`kDebugMode`): development mode's automatic setting sends a debug token.
  bool debugBuild = kDebugMode;

  /// What the plugin reads and proves for the app declaration.
  final _AppPlatform platform = _AppPlatform(const MethodChannel('ai.graine.inapp/app'));

  int tapWindowAt = 0;
  int tapsInWindow = 0;

  /// The default agent, else the first one configured.
  GraineInApp? get primary => byName[GraineInApp.defaultName] ?? (byName.isEmpty ? null : byName.values.first);

  /// [g] is the agent under its name (a test installing a name again replaces it).
  void join(GraineInApp g) => byName[g.name] = g;
}

/// [GraineInApp.bookingListenable]: whether booking is available — and a
/// notification, too, when only the reason it is not changed (the session
/// arriving while nobody is identified, say), so a widget showing
/// [GraineInApp.bookingUnavailableReason] never keeps `notLoaded`.
class _BookingNotifier extends ValueNotifier<bool> {
  _BookingNotifier() : super(false);

  /// The reason last said: before the session, none has arrived.
  GraineBookingUnavailableReason? _reason = GraineBookingUnavailableReason.notLoaded;

  void update(bool available, GraineBookingUnavailableReason? reason) {
    final reasonChanged = reason != _reason;
    _reason = reason;
    if (available != value) {
      value = available; // notifies
    } else if (reasonChanged) {
      notifyListeners();
    }
  }
}

/// The SDK's routes (contract §5.1), whole — what the requests go to.
abstract final class _Routes {
  static const String session = '/api/embed/session';
  static const String ticket = '/api/embed/ticket';
  static const String signout = '/api/embed/identity/signout';
  static const String forget = '/api/embed/memory/forget';
  static const String memories = '/api/embed/memory/list';
  static const String newConversation = '/api/embed/conversation/new';
  static const String schedule = '/api/embed/calls/schedule';
  static const String list = '/api/embed/calls/list';
  static const String cancel = '/api/embed/calls/cancel';
  static const String pastSessions = '/api/embed/sessions/list';
  static const String sessionTranscript = '/api/embed/sessions/transcript';
  static const String startWorkflow = '/api/embed/workflows/start';
  static const String appVerifyChallenge = '/api/embed/app-verify/challenge';
  static const String appVerify = '/api/embed/app-verify';
}
