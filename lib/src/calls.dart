part of 'graine.dart';

/// Where a native call is. (Until 0.6.3 this was `GraineCallStatus`; that
/// name is now a booked call's status, as in every Graine SDK.)
enum GraineNativeCallStatus {
  idle('idle'),
  ringing('ringing'),
  connecting('connecting'),
  active('active'),
  ended('ended');

  const GraineNativeCallStatus(this.wire);
  final String wire;

  /// Ringing, connecting or connected.
  bool get isLive => this == ringing || this == connecting || this == active;

  static GraineNativeCallStatus fromWire(Object? s) {
    for (final v in values) {
      if (v.wire == s) return v;
    }
    return idle;
  }
}

/// Who placed the call: the agent (a push rang the phone) or the customer.
enum GraineCallDirection { incoming, outgoing }

/// Who draws the call while the app is open: the SDK's call screen, or yours.
enum GraineCallScreen { sdk, app }

/// How native calls carry their audio (README → Calls like WhatsApp → WebRTC
/// calls). Whatever is chosen, a call WebRTC cannot carry continues on the
/// WebSocket inside the same call, and the dashboard can turn WebRTC off for
/// an agent without an app release.
enum GraineCallTransport {
  /// WebRTC when the app was built with it, else the WebSocket. The default.
  auto('auto'),

  /// Always the WebSocket.
  websocket('websocket'),

  /// WebRTC whenever it can carry the call; the WebSocket when it cannot.
  webrtc('webrtc');

  const GraineCallTransport(this.wire);

  /// The word the native engine reads and reports.
  final String wire;

  /// `webrtc` or `websocket` from the engine; null for anything else.
  static GraineCallTransport? fromWire(Object? s) => switch (s) {
        'webrtc' => webrtc,
        'websocket' => websocket,
        _ => null,
      };
}

/// The line being said on a native call.
class GraineCallCaption {
  const GraineCallCaption(this.role, this.text, {this.live = false});

  final Role role;
  final String text;

  /// Still being said.
  final bool live;

  @override
  bool operator ==(Object other) =>
      other is GraineCallCaption && other.role == role && other.text == text && other.live == live;

  @override
  int get hashCode => Object.hash(role, text, live);
}

/// A native call, as a call screen draws it. Every field has its idle value
/// when no call is live.
class GraineCallSnapshot {
  const GraineCallSnapshot({
    this.status = GraineNativeCallStatus.idle,
    this.callId,
    this.direction,
    this.reason,
    this.callerName,
    this.muted = false,
    this.speakerOn = false,
    this.agentSpeaking = false,
    this.caption,
    this.connectedAt,
    this.error,
    this.agent,
    this.transport,
    this.transportFallbackReason,
    this.reconnecting = false,
  });

  /// No call.
  static const GraineCallSnapshot idle = GraineCallSnapshot();

  /// From the engine's snapshot. Anything missing reads as its idle value.
  factory GraineCallSnapshot.fromMap(Map<Object?, Object?>? m) {
    if (m == null) return idle;
    final caption = m['caption'];
    final connectedAt = m['connectedAt'];
    final direction = m['direction'];
    return GraineCallSnapshot(
      status: GraineNativeCallStatus.fromWire(m['state']),
      callId: _string(m['callId']),
      direction: direction == 'incoming'
          ? GraineCallDirection.incoming
          : direction == 'outgoing'
              ? GraineCallDirection.outgoing
              : null,
      reason: _string(m['reason']),
      callerName: _string(m['callerName']),
      muted: m['muted'] == true,
      speakerOn: m['speakerOn'] == true,
      agentSpeaking: m['agentSpeaking'] == true,
      caption: caption is Map && _string(caption['text']) != null
          ? GraineCallCaption(
              caption['role'] == 'customer' ? Role.customer : Role.agent,
              _string(caption['text'])!,
              live: caption['live'] == true,
            )
          : null,
      connectedAt:
          connectedAt is num ? DateTime.fromMillisecondsSinceEpoch(connectedAt.toInt()) : null,
      error: _string(m['error']),
      agent: _string(m['agent']),
      transport: GraineCallTransport.fromWire(m['transport']),
      transportFallbackReason: _string(m['transportFallbackReason']),
      // Only a true is a recovering call: an engine that predates it says nothing.
      reconnecting: m['reconnecting'] == true,
    );
  }

  final GraineNativeCallStatus status;

  /// Your server's id for a call it rang; a generated one for a call the
  /// customer placed. Every outcome carries it.
  final String? callId;
  final GraineCallDirection? direction;

  /// The push's reason, or the one `startCall` was given.
  final String? reason;

  /// The name the call shows.
  final String? callerName;
  final bool muted;

  /// Audio out of the loudspeaker rather than the earpiece or a headset.
  final bool speakerOn;

  /// The agent's voice is playing right now.
  final bool agentSpeaking;

  /// The latest line: the agent's words as they are said, or the customer's
  /// as they are heard.
  final GraineCallCaption? caption;

  /// When the conversation opened — for a call timer.
  final DateTime? connectedAt;

  /// Why the last call could not connect. Cleared when the next call starts.
  final String? error;

  /// The agent the call is with, by the name the app configured it under
  /// ([GraineInApp.init]; `'default'` for the default agent) — the one
  /// [GraineCalls.startCall] named, or the one a ring was routed to by its
  /// push. Null with no call, and from an engine that does not say.
  final String? agent;

  /// What the call's audio runs on: [GraineCallTransport.webrtc] or
  /// [GraineCallTransport.websocket]. Null with no call, and from an engine
  /// that predates WebRTC.
  final GraineCallTransport? transport;

  /// Why a call that tried WebRTC runs on the WebSocket instead —
  /// `mint_failed`, `register_failed`, `no_response`, `no_answer`,
  /// `ice_timeout`, `error`, or the dashboard's choice. Null when it did not
  /// fall back.
  final String? transportFallbackReason;

  /// A connected call recovering its connection — its audio dropped and is
  /// being restored; the SDK's call screen says "Reconnecting…". False again
  /// once the audio is back, and from an engine that predates it.
  final bool reconnecting;

  @override
  bool operator ==(Object other) =>
      other is GraineCallSnapshot &&
      other.status == status &&
      other.callId == callId &&
      other.direction == direction &&
      other.reason == reason &&
      other.callerName == callerName &&
      other.muted == muted &&
      other.speakerOn == speakerOn &&
      other.agentSpeaking == agentSpeaking &&
      other.caption == caption &&
      other.connectedAt == connectedAt &&
      other.error == error &&
      other.agent == agent &&
      other.transport == transport &&
      other.transportFallbackReason == transportFallbackReason &&
      other.reconnecting == reconnecting;

  @override
  int get hashCode => Object.hash(status, callId, direction, reason, callerName, muted, speakerOn,
      agentSpeaking, caption, connectedAt, error, agent, transport, transportFallbackReason, reconnecting);
}

/// What became of a call (WIRE.md: ringing · answered · declined · missed ·
/// failed · ended).
enum GraineCallOutcomeKind { ringing, answered, declined, missed, ended, failed }

/// WHAT BECAME OF A CALL — WIRE.md's `GraineCallOutcome`. A call Graine rang
/// ([hosted]) is reported to Graine by the SDK itself; tell your own server
/// about the others, with [callId].
class GraineCallOutcome {
  const GraineCallOutcome(this.callId, this.outcome,
      {this.reason, this.durationSeconds, this.hosted = false, this.agent});

  factory GraineCallOutcome.fromMap(Map<Object?, Object?> m) {
    final word = m['outcome'];
    final outcome = GraineCallOutcomeKind.values.firstWhere((GraineCallOutcomeKind k) => k.name == word,
        orElse: () => GraineCallOutcomeKind.failed);
    final seconds = m['durationSeconds'];
    final reason = switch (outcome) {
      GraineCallOutcomeKind.failed => _string(m['error']) ?? _string(m['reason']),
      _ => _string(m['reason']),
    };
    return GraineCallOutcome(
      _string(m['callId']) ?? '',
      outcome,
      reason: reason,
      durationSeconds: seconds is num && seconds.isFinite && seconds >= 0 ? seconds.round() : null,
      hosted: m['hosted'] == true || m['hosted'] == '1',
      agent: _string(m['agent']),
    );
  }

  final String callId;
  final GraineCallOutcomeKind outcome;

  /// With `ended`: `local` (this app hung up), `remote` (the agent did) or
  /// `failed` (the connection broke mid-call). With `failed`: why the call
  /// never connected.
  final String? reason;

  /// How long the conversation lasted, when the engine says.
  final int? durationSeconds;

  /// Graine rang this call (hosted ringing); the SDK has already told Graine
  /// what became of it.
  final bool hosted;

  /// The agent the call was with, by the name the app configured it under
  /// (`'default'` for the default agent); null when the engine does not know.
  final String? agent;

  /// One word for your server: ringing · answered · declined · missed · ended · failed.
  String get wire => outcome.name;

  /// [outcome], by its 0.6 name.
  @Deprecated('Use outcome.')
  GraineCallOutcomeKind get kind => outcome;

  /// [reason] of an `ended` call, by its 0.6 name.
  @Deprecated('Use reason.')
  String? get endReason => outcome == GraineCallOutcomeKind.ended ? reason : null;

  /// [reason] of a `failed` call, by its 0.6 name.
  @Deprecated('Use reason.')
  String? get error => outcome == GraineCallOutcomeKind.failed ? reason : null;

  @override
  String toString() => 'GraineCallOutcome($callId, $wire${reason != null ? ', $reason' : ''})';
}

/// An agent's call ringing on this device.
class GraineIncomingCall {
  const GraineIncomingCall(this.callId, {this.reason, this.callerName, this.hosted = false, this.agent});

  final String callId;
  final String? reason;
  final String? callerName;

  /// Graine rang it (hosted ringing) rather than your own server's push.
  final bool hosted;

  /// The agent ringing, by the name the app configured it under (`'default'`
  /// for the default agent): the native engine matches the push's `agent_id`
  /// to a configured agent's — the default agent when none matches. Null from
  /// an engine that does not say.
  final String? agent;
}

/// A permission a native call needs.
enum GraineCallPermission {
  /// The customer's voice. Asked by the SDK when a call starts without it, or
  /// by [GraineCalls.requestCallPermissions].
  microphone('microphone'),

  /// A call that rings while the app is closed or in the background — Android
  /// (13+ asks). iOS rings through CallKit, which needs none.
  notifications('notifications'),

  /// A ring that fills a locked screen — Android 14+, allowed in Settings.
  /// iOS: CallKit's own screen, nothing to allow.
  fullScreen('fullScreen');

  const GraineCallPermission(this.wire);

  /// The word every Graine SDK uses.
  final String wire;
}

/// Where a call permission stands.
enum GraineCallPermissionStatus {
  /// Allowed.
  granted('granted'),

  /// Not allowed yet: [GraineCalls.requestCallPermissions] can ask for it.
  denied('denied'),

  /// Refused for good, or only allowed in Settings: only the Settings app can
  /// change it ([GraineCalls.openCallSettings]).
  blocked('blocked'),

  /// This phone needs no such permission.
  notNeeded('notNeeded');

  const GraineCallPermissionStatus(this.wire);

  /// The word every Graine SDK uses.
  final String wire;

  /// Granted, or nothing to grant.
  bool get isSatisfied => this == granted || this == notNeeded;

  /// From the engine's word; anything it does not know is [denied], never granted.
  static GraineCallPermissionStatus fromWire(Object? s) {
    for (final v in values) {
      if (v.wire == s) return v;
    }
    return denied;
  }
}

/// Every call permission's status, as the phone holds it when read.
class GraineCallPermissions {
  const GraineCallPermissions({required this.microphone, required this.notifications, required this.fullScreen});

  /// From the engine's map, `{microphone, notifications, fullScreen}`.
  factory GraineCallPermissions.fromMap(Map<Object?, Object?>? m) => GraineCallPermissions(
        microphone: GraineCallPermissionStatus.fromWire(m?['microphone']),
        notifications: GraineCallPermissionStatus.fromWire(m?['notifications']),
        fullScreen: GraineCallPermissionStatus.fromWire(m?['fullScreen']),
      );

  final GraineCallPermissionStatus microphone;
  final GraineCallPermissionStatus notifications;
  final GraineCallPermissionStatus fullScreen;

  /// One permission's status.
  GraineCallPermissionStatus operator [](GraineCallPermission item) => switch (item) {
        GraineCallPermission.microphone => microphone,
        GraineCallPermission.notifications => notifications,
        GraineCallPermission.fullScreen => fullScreen,
      };

  /// Every permission is granted or not needed: calls can ring and connect.
  bool get allGranted => GraineCallPermission.values.every((GraineCallPermission p) => this[p].isSatisfied);

  @override
  bool operator ==(Object other) =>
      other is GraineCallPermissions &&
      other.microphone == microphone &&
      other.notifications == notifications &&
      other.fullScreen == fullScreen;

  @override
  int get hashCode => Object.hash(microphone, notifications, fullScreen);

  @override
  String toString() =>
      'GraineCallPermissions(microphone: ${microphone.wire}, notifications: ${notifications.wire}, fullScreen: ${fullScreen.wire})';
}

/// Something the app's setup still lacks for calls: a stable [code] and a
/// [message] with the exact fix. Calls still work where they can.
class GraineCallSetupProblem {
  const GraineCallSetupProblem(this.code, this.message);

  /// Stable, the same on every SDK: `microphone_usage_missing`,
  /// `background_audio_missing`, `background_voip_missing`,
  /// `push_entitlement_missing`, `voip_pushes_not_enabled`, `no_voip_token`
  /// (iOS); `manifest_entry_missing`, `no_push_token`,
  /// `notifications_not_allowed`, `full_screen_not_allowed` (Android);
  /// `microphone_blocked`, `hosted_ringing_off` (both).
  final String code;

  /// What is missing and how to fix it, for the developer.
  final String message;

  @override
  bool operator ==(Object other) => other is GraineCallSetupProblem && other.code == code && other.message == message;

  @override
  int get hashCode => Object.hash(code, message);

  @override
  String toString() => 'GraineCallSetupProblem($code: $message)';
}

/// How native calls ring and what they show. Passed to [GraineCalls.configure].
class GraineCallsOptions {
  const GraineCallsOptions({
    required this.publishableKey,
    required this.displayName,
    this.baseUrl = 'https://www.graine.ai',
    this.ringtoneSound,
    this.ringTimeout = const Duration(seconds: 30),
    this.appVersion,
    this.callScreen = GraineCallScreen.sdk,
    this.callTransport = GraineCallTransport.auto,
    this.debug = false,
    this.androidSmallIcon,
    this.iosIconTemplate,
    this.iosIncludesCallsInRecents = false,
  });

  /// Agent → Embed & Widgets. Public by design. The default agent's: the
  /// agents the app configured under a name of their own go with it, each
  /// with its own key ([GraineCalls.configure]).
  final String publishableKey;

  /// The name on the calls the customer places, and on a ring whose push
  /// names nobody. A push's `caller_name` wins for its own call — so a call
  /// Graine rings shows the agent's call name from the dashboard (Calls &
  /// scheduling).
  final String displayName;
  final String baseUrl;

  /// iOS: a sound file of 30 seconds or less in the app bundle. Android: a
  /// `res/raw` resource name. Null (the default): the ring the brand chose in
  /// the dashboard's call screen design — the phone's own ringtone unless it
  /// chose one. Set, it replaces the brand's ring.
  final String? ringtoneSound;

  /// How long an agent's call rings before it is missed.
  final Duration ringTimeout;

  /// Which build placed the call; it lands on the call record.
  final String? appVersion;

  /// Who draws the call while the app is open. [GraineCallScreen.sdk] (the
  /// default): the SDK's call screen, drawn from the brand's call screen
  /// design and its look — the backdrop, layout, avatar ring, buttons, the
  /// agent's voice, captions and a look per moment, all chosen in the
  /// dashboard and changed there without an app release — on Android its
  /// full-screen call activity, on iOS a full-screen view over your app.
  /// [GraineCallScreen.app]: your own screen, drawn from
  /// [GraineCalls.instance] (the design's call tokens are
  /// `GraineInApp.instance.tokens?.call` — with several agents, those of the
  /// agent the call is with, `GraineInApp.named(snapshot.agent ?? 'default')`
  /// — and [CallLook] has the rules for drawing them: the moment, its look,
  /// the status words, the backdrop's geometry, the buttons and the voice).
  /// A locked iPhone always shows the system's call screen.
  final GraineCallScreen callScreen;

  /// How calls carry their audio. [GraineCallTransport.auto] (the default):
  /// WebRTC when the app was built with it (README → Calls like WhatsApp →
  /// WebRTC calls), else the WebSocket. A call WebRTC cannot carry continues
  /// on the WebSocket inside the same call.
  final GraineCallTransport callTransport;

  /// The native SDK's debug log, in Xcode's console or logcat: how a call
  /// connected and what its audio did, for finding out why one did not. Off
  /// by default; turn it on in debug builds. Read once, when the app
  /// launches: a change takes effect at the next launch.
  final bool debug;

  /// Android: a monochrome drawable for the call notifications, by name.
  final String? androidSmallIcon;

  /// iOS: a template image in the app bundle, by name, for the system call screen.
  final String? iosIconTemplate;

  /// iOS: list the calls in the Phone app's Recents.
  final bool iosIncludesCallsInRecents;

  Map<String, Object?> toMap() => <String, Object?>{
        'publishableKey': publishableKey,
        'displayName': displayName,
        'baseUrl': baseUrl,
        if (ringtoneSound != null) 'ringtoneSound': ringtoneSound,
        'ringTimeoutMs': ringTimeout.inMilliseconds,
        if (appVersion != null) 'appVersion': appVersion,
        'callScreen': callScreen.name,
        if (callTransport != GraineCallTransport.auto) 'callTransport': callTransport.wire,
        'debug': debug,
        'android': <String, Object?>{if (androidSmallIcon != null) 'smallIcon': androidSmallIcon},
        'ios': <String, Object?>{
          if (iosIconTemplate != null) 'iconTemplate': iosIconTemplate,
          'includesCallsInRecents': iosIncludesCallsInRecents,
        },
      };
}

/// CALLS LIKE WHATSAPP — your agent rings the customer, or the customer calls
/// it, on the iOS and Android SDKs' native call engine: CallKit and VoIP
/// pushes on iOS, a ringing call notification and call screen on Android, the
/// call going on with the screen off. The audio runs natively, with the
/// platform's echo canceller; Dart configures it, draws from its state and
/// answers the agent's in-app actions.
///
///     await GraineCalls.instance.configure(const GraineCallsOptions(
///       publishableKey: 'pk_live_…', displayName: 'Acme Assistant'));
///     GraineCalls.instance.attach();                     // your screen, variables, actions
///     GraineCalls.instance.outcomes.listen(myServer.report);
///     await GraineCalls.instance.startCall(reason: 'card_blocked');
///
/// One call at a time. A native call ends any call the WebView engine holds,
/// and [GraineVoice.start] waits until it is over. Listen to it as a
/// [ValueListenable] of [GraineCallSnapshot] to draw your own call screen.
///
/// PERMISSIONS AND SETUP: [requestCallPermissions] asks when the app chooses
/// (never on its own at launch), [callPermissions] reads them,
/// [openCallSettings] opens Settings, and [callSetupProblems] says what the
/// app's setup still lacks, with the fix.
///
/// SEVERAL AGENTS: the engine is the app's, one for every agent. The agents
/// the app configured under a name of their own ([GraineInApp.init]) reach
/// it with [configure]; `startCall(agent: 'support')` calls one of them, and
/// a ring Graine sends for one of them (its push names the agent) rings as
/// that agent — the snapshot, the ring and the outcome say which
/// ([GraineCallSnapshot.agent]), and the agent's actions run in its own
/// handlers.
class GraineCalls extends ChangeNotifier implements ValueListenable<GraineCallSnapshot> {
  GraineCalls._(this._channel, this._events);

  /// The one instance.
  static final GraineCalls instance = GraineCalls._(
      const MethodChannel('ai.graine.inapp/calls'), const EventChannel('ai.graine.inapp/calls/events'));

  /// True while a native call rings, connects or is connected.
  static bool _nativeLive = false;

  final MethodChannel _channel;
  final EventChannel _events;

  GraineCallSnapshot _snapshot = GraineCallSnapshot.idle;
  StreamSubscription<Object?>? _subscription;
  // The engine keeps the outcomes and rings that happen while no Dart is
  // listening (a call rung, answered and ended before the app started) and
  // hands them over the moment the channel is listened to — usually by
  // configure(), before the app listens to [outcomes]. They wait here, the
  // last 20, for the first listener.
  static const int _heldCap = 20;
  final List<GraineCallOutcome> _heldOutcomes = <GraineCallOutcome>[];
  final List<GraineIncomingCall> _heldIncoming = <GraineIncomingCall>[];
  late final StreamController<GraineCallOutcome> _outcomes =
      StreamController<GraineCallOutcome>.broadcast(onListen: () => _drain(_heldOutcomes, _outcomes));
  late final StreamController<GraineIncomingCall> _incoming =
      StreamController<GraineIncomingCall>.broadcast(onListen: () => _drain(_heldIncoming, _incoming));
  final List<void Function(String?)> _tokenWatchers = <void Function(String?)>[];
  GraineInApp? _attached;

  /// [configure] reached the engine in this run.
  bool _configured = false;

  /// The options [configure] last sent — sent again, with the agents, when
  /// the app configures another agent.
  GraineCallsOptions? _options;

  /// The named agents the engine was last told about, as it reads them.
  Map<String, Object?> _agentsSent = const <String, Object?>{};

  /// The app's named agents whose key IS the options' own. To the engine
  /// they are its default agent: they are not listed again, a call with one
  /// of them is a call with the default agent, and — in an app that named
  /// every agent — the engine's "default" is the first of them.
  List<String> _sameAsDefault = const <String>[];

  /// Whose variables, screen and actions the engine holds — the agent its
  /// call is with, else the attached one — and how to stop following them.
  GraineInApp? _held;
  void Function()? _unhold;

  /// The agent the last [startCall] named, while its call lasts.
  GraineInApp? _calling;

  /// The call, as it is now.
  @override
  GraineCallSnapshot get value => _snapshot;

  /// Native calls run on Android and iOS.
  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// What became of every call — tell your server. Outcomes from before
  /// anyone listened (a call that rang and ended while the app was not
  /// running) reach the first listener, oldest first.
  Stream<GraineCallOutcome> get outcomes => _outcomes.stream;

  /// An agent's call started ringing — for your own ringing UI or analytics.
  /// Held like [outcomes].
  Stream<GraineIncomingCall> get incomingCalls => _incoming.stream;

  /// Once, at launch, before a push can arrive. The options are kept by the
  /// native side, so a push that wakes the app before any Dart has run still
  /// rings. Throws [ArgumentError] for a missing key or name, and a
  /// `PlatformException` with the code `invalid_options` for anything else.
  ///
  /// [GraineCallsOptions.publishableKey] is the default agent's. Every agent
  /// the app configured under a name of its own goes with the options
  /// (`agents: {name: {publishableKey, baseUrl}}`), so [startCall] can call it
  /// and Graine's rings for it ring as it; one configured later reaches the
  /// engine then. A named agent with the options' own key is the engine's
  /// default agent, not listed again.
  Future<void> configure(GraineCallsOptions options) async {
    if (options.publishableKey.trim().isEmpty) {
      throw ArgumentError.value(options.publishableKey, 'publishableKey', 'is required');
    }
    if (options.displayName.trim().isEmpty) {
      throw ArgumentError.value(options.displayName, 'displayName', 'is required');
    }
    if (!isSupported) return;
    _listen();
    final engine = _engineAgents(options);
    await _channel.invokeMethod<void>('configure', _configureArgs(options, engine.agents));
    _options = options;
    _agentsSent = engine.agents;
    _sameAsDefault = engine.sameAsDefault;
    _configured = true;
    _apply(await _channel.invokeMapMethod<Object?, Object?>('snapshot'));
    // Who the user is — for the calls this engine places and answers, and the
    // device Graine rings for them.
    final g = _attached ?? GraineInApp.maybeInstance;
    if (g != null) unawaited(_sendIdentity(g));
    if (kDebugMode) _scheduleSetupWarnings();
  }

  // ── permissions and setup ───────────────────────────────────────────────

  /// The call permissions as the phone holds them now: the microphone, and on
  /// Android the ring's notifications (13+ asks) and the full-screen ring
  /// (14+, Settings only); on iOS those two are `notNeeded` — CallKit rings.
  /// Read again when the app returns to the foreground: the customer may have
  /// changed Settings. Readable before [configure].
  Future<GraineCallPermissions> callPermissions() async {
    if (!isSupported) return _nothingNeeded;
    return GraineCallPermissions.fromMap(await _invokeMap('callPermissions'));
  }

  /// Ask for the call permissions the system's dialog can still ask for — the
  /// microphone, and notifications on Android 13+ — at a moment the app
  /// chooses (onboarding, a "Call me" screen). The SDK never asks on its own
  /// at launch; a call that starts without the microphone still asks then.
  /// Returns the permissions as they stand after. The full-screen ring has
  /// no dialog: [openCallSettings] opens its page.
  Future<GraineCallPermissions> requestCallPermissions() async {
    if (!isSupported) return _nothingNeeded;
    return GraineCallPermissions.fromMap(await _invokeMap('requestCallPermissions'));
  }

  /// Open the Settings page that changes [item] — on Android the full-screen
  /// ring's own page (14+) or the app's notification settings; otherwise the
  /// app's page, where the microphone is. True when a page opened.
  Future<bool> openCallSettings(GraineCallPermission item) async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('openCallSettings', item.wire) ?? false;
    } on MissingPluginException {
      debugPrint('[Graine] call permissions are not available in this build (rebuild the app).');
      return false;
    }
  }

  /// What the app's setup still lacks for calls, read now — each a stable
  /// code and a sentence with the exact fix. iOS: an Info.plist entry
  /// (`NSMicrophoneUsageDescription`, the `audio` and `voip` background modes
  /// — a plugin cannot add them, so the check names them), the push
  /// entitlement, `enableVoIPPushes` never called or no VoIP token. Android: a
  /// manifest entry, no push token (Firebase missing or not set up in the app,
  /// or [registerPushToken] never called by an app whose own messaging service
  /// receives the pushes), notifications or the full-screen ring not allowed.
  /// Both: the microphone blocked, Graine
  /// not ringing this phone. Empty when nothing is missing, and before
  /// [configure]. In a debug build each one is also printed once.
  Future<List<GraineCallSetupProblem>> callSetupProblems() async {
    if (!isSupported) return const <GraineCallSetupProblem>[];
    final List<Object?>? raw;
    try {
      raw = await _channel.invokeListMethod<Object?>('callSetupProblems');
    } on MissingPluginException {
      return const <GraineCallSetupProblem>[];
    }
    final out = <GraineCallSetupProblem>[];
    for (final p in raw ?? const <Object?>[]) {
      if (p is! Map) continue;
      final code = _string(p['code']);
      if (code == null || code.isEmpty) continue;
      out.add(GraineCallSetupProblem(code, _string(p['message']) ?? ''));
    }
    return out;
  }

  static const GraineCallPermissions _nothingNeeded = GraineCallPermissions(
    microphone: GraineCallPermissionStatus.notNeeded,
    notifications: GraineCallPermissionStatus.notNeeded,
    fullScreen: GraineCallPermissionStatus.notNeeded,
  );

  /// A map from the engine; null — every permission then reads `denied` — from a build without the method.
  Future<Map<Object?, Object?>?> _invokeMap(String method) async {
    try {
      return await _channel.invokeMapMethod<Object?, Object?>(method);
    } on MissingPluginException {
      debugPrint('[Graine] call permissions are not available in this build (rebuild the app).');
      return null;
    }
  }

  // In a debug build, the setup problems in the console `flutter run` shows:
  // the native SDK logs them to Xcode's console and logcat, which a Flutter
  // developer rarely watches. Once each, now and once the push registration
  // has had its time.
  final Set<String> _warned = <String>{};
  Timer? _setupTimer;
  static const Duration _setupSettle = Duration(seconds: 16);

  void _scheduleSetupWarnings() {
    if (_setupTimer != null) return;
    unawaited(_warnSetupProblems());
    _setupTimer = Timer(_setupSettle, () => unawaited(_warnSetupProblems()));
  }

  Future<void> _warnSetupProblems() async {
    try {
      for (final p in await callSetupProblems()) {
        if (_warned.add(p.code)) debugPrint('[Graine] Calls setup (${p.code}): ${p.message}');
      }
    } catch (_) {
      // The check never stands in the way of a call.
    }
  }

  /// HOSTED RINGING ON ANDROID, for an app whose own Firebase messaging
  /// service receives the pushes (`firebase_messaging` brings one): the token
  /// it hands the app — from `onTokenRefresh`. With Firebase Cloud Messaging
  /// in the app the SDK reads the token itself at start, and without a
  /// messaging service of the app's own the SDK's receives every new one, so
  /// most apps never call this. The SDK registers this device with Graine
  /// (when the workspace has Graine ring its users) together with who is
  /// signed in, and again whenever they change. iOS needs nothing: its VoIP
  /// token is registered natively.
  Future<void> registerPushToken(String token) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final t = token.trim();
    if (t.isEmpty) return;
    await _invokeOptional('registerPushToken', <String, Object?>{'token': t, 'tokenKind': 'fcm'});
  }

  /// iOS: receive your agent's calls as VoIP pushes. [onToken] gets the token
  /// your server sends the push to (APNs, `apns-push-type: voip`) — now, if
  /// the device has one, and whenever it changes; null when it is
  /// invalidated. Every VoIP push rings, as iOS requires. Android has no VoIP
  /// pushes — use [handlePush]. Returns a function that stops listening.
  void Function() enableVoIPPushes(void Function(String? token) onToken) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return () {};
    _tokenWatchers.add(onToken);
    _listen();
    _channel.invokeMethod<void>('enableVoIPPushes');
    return () => _tokenWatchers.remove(onToken);
  }

  /// Android, for an app whose own Firebase messaging service receives the
  /// pushes (`firebase_messaging` brings one): a push's data, from its
  /// message handlers — foreground and background. Without one, the SDK's
  /// own messaging service receives Graine's calls natively and this is not
  /// needed. A Graine call rings with a call notification, even when the app
  /// was not running. True when the push was a call (ringing, busy or
  /// malformed) and the app should do nothing more with it. iOS: false — VoIP
  /// pushes arrive natively.
  Future<bool> handlePush(Map<String, Object?> data) async {
    if (!isSupported) return false;
    final strings = <String, String>{
      for (final MapEntry<String, Object?> e in data.entries)
        if (e.value != null) e.key: e.value is String ? e.value! as String : _encode(e.value),
    };
    try {
      return await _channel.invokeMethod<bool>('handlePush', strings) ?? false;
    } on MissingPluginException {
      debugPrint('[Graine] native calls are not available in this build (rebuild the app).');
      return false;
    }
  }

  /// The customer calls the agent — [agent], by the name the app configured
  /// it under ([GraineInApp.init]); the default agent without one. The agent
  /// hears `who_called = "customer"` and `call_reason`, with [variables] over
  /// the app's own. Returns the call's id — every outcome carries it — or
  /// null when a call is already live (one at a time).
  Future<String?> startCall(
      {String? reason, Map<String, Object?> variables = const <String, Object?>{}, String? agent}) async {
    if (!isSupported) return null;
    _listen();
    final name = agent == null ? null : GraineInApp._normaliseName(agent);
    // An agent with the options' own key is the engine's default agent.
    final engineName = name != null && _sameAsDefault.contains(name) ? null : name;
    if (!_snapshot.status.isLive) {
      // What the app tells the agent goes to the engine before it calls it.
      _calling = GraineInApp._agentNamed(name);
      _follow();
    }
    try {
      final id = await _channel.invokeMethod<String>('startCall', <String, Object?>{
        if (reason != null) 'reason': reason,
        'variables': Protocol.toJson(variables),
        if (engineName != null) 'agent': engineName,
      });
      if (id == null) _notCalling();
      return id;
    } on MissingPluginException {
      debugPrint('[Graine] native calls are not available in this build (rebuild the app).');
      _notCalling();
      return null;
    } catch (_) {
      _notCalling();
      rethrow;
    }
  }

  /// Get the customer's next call ready before they tap — to [agent], by the
  /// name the app configured it under ([GraineInApp.init]), the default agent
  /// without one — so that when they do, [startCall] connects almost at once.
  /// Call it when the screen with your call button appears; calling it again
  /// is cheap: while a call prepared for the same agent, customer, [reason] and
  /// [variables] is ready, nothing more happens. A [startCall] with the same
  /// reason and variables within four minutes uses it; any other call is
  /// prepared at the tap, as without this.
  ///
  /// Nothing is dialled and no conversation starts — nothing is billed — until
  /// [startCall], and the microphone is not touched. What was prepared is let
  /// go when the app goes to the background, the signed-in customer changes
  /// (or their memory choice, or the phone's time zone), after four minutes,
  /// or when a call rings in. For calls over WebRTC; otherwise, while a call
  /// rings or is live, or with a native build from before it, it does nothing.
  Future<void> prepareCall(
      {String? reason, Map<String, Object?> variables = const <String, Object?>{}, String? agent}) async {
    if (!isSupported) return;
    final name = agent == null ? null : GraineInApp._normaliseName(agent);
    // An agent with the options' own key is the engine's default agent, as startCall names it.
    final engineName = name != null && _sameAsDefault.contains(name) ? null : name;
    try {
      await _channel.invokeMethod<void>('prepareCall', <String, Object?>{
        if (reason != null) 'reason': reason,
        'variables': Protocol.toJson(variables),
        if (engineName != null) 'agent': engineName,
      });
    } on MissingPluginException {
      // A native build from before prepareCall: the tap prepares the call, as it always did.
    }
  }

  /// [startCall] placed nothing: the engine holds the attached agent's again.
  void _notCalling() {
    if (_snapshot.status.isLive) return;
    _calling = null;
    _follow();
  }

  /// Answer the ringing call from your own screen. The SDK's call screens and
  /// the system's answer by themselves.
  Future<void> answer() => _invoke('answer');

  /// Decline the ringing call.
  Future<void> decline() => _invoke('decline');

  /// Hang up — or decline, while it rings.
  Future<void> end() => _invoke('end');

  /// Stop sending the customer's voice without ending the call.
  Future<void> setMuted(bool muted) => _invoke('setMuted', muted);

  /// The loudspeaker (true) or the earpiece / headset (false). The earpiece by
  /// default, like a phone call.
  Future<void> setSpeaker(bool on) => _invoke('setSpeaker', on);

  /// Hand the call what the app already tells the agent through [graine] —
  /// who the customer is, the prompt variables, the screen and the actions
  /// the app registered — kept in step as they change, and answer the agent's
  /// actions through the app's own handlers. Returns a function that detaches.
  ///
  /// With several agents, attach the default one: while a call is with
  /// another agent of the app ([startCall]'s `agent`, or a ring for it), the
  /// engine holds THAT agent's variables and actions, and its actions run in
  /// that agent's handlers; after the call, the attached agent's again.
  void Function() attach([GraineInApp? graine]) {
    final g = graine ?? GraineInApp.instance;
    _attached = g;
    if (!isSupported) return () {};
    _listen();
    unawaited(_sendIdentity(g));
    // Handed over at once — again to an engine that held this agent already.
    _hold(null);
    _follow();
    return () {
      if (!identical(_attached, g)) return;
      _attached = null;
      _hold(null);
      _invoke('setActions', const <String>[]);
    };
  }

  /// The agent whose variables, screen and actions the engine should hold:
  /// the one its call is with, else the attached one — none while no app is
  /// attached.
  void _follow() {
    final attached = _attached;
    if (attached == null) {
      _hold(null);
      return;
    }
    final live = _snapshot.status.isLive ? GraineInApp._agentNamed(_snapshot.agent) : null;
    _hold(live ?? _calling ?? attached);
  }

  /// Hand the engine [g]'s variables, screen and actions now, and keep them
  /// in step until another agent's are held.
  void _hold(GraineInApp? g) {
    if (identical(g, _held)) return;
    _unhold?.call();
    _unhold = null;
    _held = g;
    if (g == null) return;
    void pushVariables() => _invoke('setVariables', g.currentVariables());

    void pushScreen() {
      _invoke('setScreen', _screenMap(g._screen));
      _invoke('setActions', g._actions.names);
    }

    pushVariables();
    pushScreen();
    final offVariables = g._onVariables((Map<String, String> _) => pushVariables());
    final offContext = g._onContext((Map<String, Object?> _) => pushScreen());
    _unhold = () {
      offVariables();
      offContext();
    };
  }

  /// The configure arguments: the options, and the named agents when there are any.
  static Map<String, Object?> _configureArgs(GraineCallsOptions options, Map<String, Object?> agents) =>
      <String, Object?>{
        ...options.toMap(),
        if (agents.isNotEmpty) 'agents': agents,
      };

  /// THE APP'S OTHER AGENTS, AS THE ENGINE READS THEM: every agent configured
  /// under a name of its own, `{name: {publishableKey, baseUrl}}` — except
  /// those whose key is the options' own, which to the engine are its
  /// default agent ([_sameAsDefault]).
  static ({Map<String, Object?> agents, List<String> sameAsDefault}) _engineAgents(GraineCallsOptions options) {
    final agents = <String, Object?>{};
    final same = <String>[];
    for (final g in GraineInApp.all.values) {
      if (g.name == GraineInApp.defaultName) continue;
      if (g.config.publishableKey == options.publishableKey) {
        same.add(g.name);
      } else {
        agents[g.name] = <String, Object?>{'publishableKey': g.config.publishableKey, 'baseUrl': g.config.baseUrl};
      }
    }
    return (agents: agents, sameAsDefault: same);
  }

  /// The app configured another agent: an engine configured in this run
  /// hears of it (the kept options, with every named agent).
  static void _agentsChanged() {
    final calls = instance;
    final options = calls._options;
    if (!calls._configured || options == null || !calls.isSupported) return;
    final engine = _engineAgents(options);
    calls._sameAsDefault = engine.sameAsDefault;
    if (deepEquals(engine.agents, calls._agentsSent)) return;
    calls._agentsSent = engine.agents;
    unawaited(calls._invokeOptional('configure', _configureArgs(options, engine.agents)));
  }

  /// The app's name for an agent the engine names: the engine's default
  /// agent is the app's default — or, in an app that named every agent, the
  /// one configured with the options' key.
  String? _appAgent(String? engine) {
    if (engine != GraineInApp.defaultName || _sameAsDefault.isEmpty) return engine;
    if (GraineInApp.all.containsKey(GraineInApp.defaultName)) return engine;
    return _sameAsDefault.first;
  }

  /// [payload] with its `agent` as the app names it.
  Map<Object?, Object?> _withAppAgent(Map<Object?, Object?> payload) {
    final engine = payload['agent'];
    if (engine is! String) return payload;
    final app = _appAgent(engine);
    return app == engine ? payload : <Object?, Object?>{...payload, 'agent': app};
  }

  /// [g]'s user changed: the engine hears it if it is [g]'s — configured in
  /// this run, or attached to [g]. One user for the app: with no app
  /// attached, the engine hears it from the default agent alone.
  static void _identityChanged(GraineInApp g) {
    final calls = instance;
    final attached = calls._attached;
    if (attached != null) {
      if (!identical(attached, g)) return;
    } else {
      if (!calls._configured) return;
      final primary = GraineInApp.maybeInstance;
      if (primary != null && !identical(primary, g) && GraineInApp._everyAgent().contains(g)) return;
    }
    unawaited(calls._sendIdentity(g));
  }

  /// WHO THE USER IS, FOR THE NATIVE ENGINE: the traits as the app passed
  /// them — the engine masks them for the agent and keeps the identity raw
  /// for Graine, exactly as the app's own `identify` would — and their memory
  /// choice.
  Future<void> _sendIdentity(GraineInApp g) async {
    if (!isSupported) return;
    final traits = g._traits;
    await _invoke('setIdentity', traits == null ? null : Protocol.toJson(traits));
    // Not waiting for the session: when it arrives, the identity is announced
    // again with the choice that user made.
    final id = await g._identityState(waitForSession: false);
    await _invokeOptional('setMemory', id.memory);
  }

  void _listen() {
    if (_subscription != null || !isSupported) return;
    _subscription = _events.receiveBroadcastStream().listen(_onEvent,
        onError: (Object e) => debugPrint('[Graine] calls: $e'));
  }

  void _onEvent(Object? raw) {
    if (raw is! Map) return;
    final data = raw['data'];
    final payload = _withAppAgent(data is Map ? data : const <Object?, Object?>{});
    switch (raw['event']) {
      case 'state':
        _apply(payload);
      case 'outcome':
        _deliver(_outcomes, _heldOutcomes, GraineCallOutcome.fromMap(payload));
      case 'incoming':
        _deliver(
            _incoming,
            _heldIncoming,
            GraineIncomingCall(_string(payload['callId']) ?? '',
                reason: _string(payload['reason']),
                callerName: _string(payload['callerName']),
                hosted: payload['hosted'] == true || payload['hosted'] == '1',
                agent: _string(payload['agent'])));
      case 'voipToken':
        final token = _string(payload['token']);
        for (final w in List<void Function(String?)>.of(_tokenWatchers)) {
          w(token);
        }
      case 'action':
        _answerAction(payload);
    }
  }

  static void _deliver<T>(StreamController<T> stream, List<T> held, T value) {
    if (stream.hasListener) {
      stream.add(value);
      return;
    }
    held.add(value);
    if (held.length > _heldCap) held.removeAt(0);
  }

  static void _drain<T>(List<T> held, StreamController<T> stream) {
    for (final value in held) {
      stream.add(value);
    }
    held.clear();
  }

  void _apply(Map<Object?, Object?>? m) {
    final next = GraineCallSnapshot.fromMap(m == null ? null : _withAppAgent(m));
    if (next == _snapshot) return;
    final wasLive = _snapshot.status.isLive;
    _snapshot = next;
    _nativeLive = next.status.isLive;
    if (!wasLive && next.status.isLive) {
      // One call at a time: the native call takes the line from every agent's WebView engine.
      for (final g in GraineInApp._everyAgent(_attached)) {
        final voice = g.voice;
        if (voice.connected || voice.connecting) voice.end();
      }
    }
    if (wasLive && !next.status.isLive) _calling = null;
    _follow();
    notifyListeners();
  }

  Future<void> _answerAction(Map<Object?, Object?> request) async {
    final requestId = _string(request['requestId']);
    final name = _string(request['name']) ?? '';
    if (requestId == null) return;
    final arguments = request['arguments'];
    // The agent the call is with answers in its own handlers.
    final g = _attached == null ? null : (GraineInApp._agentNamed(_string(request['agent'])) ?? _held ?? _attached);
    ActionResult result;
    if (g == null) {
      result = ActionResult.refused('This app build does not implement "$name".');
    } else {
      try {
        result = await g.executeAction(
            name, arguments is Map ? arguments.cast<String, Object?>() : const <String, Object?>{});
      } catch (e) {
        result = ActionResult.error('"$name" failed: $e');
      }
    }
    await _invoke('resolveAction', <String, Object?>{
      'requestId': requestId,
      'result': <String, Object?>{
        'status': result.status.wire,
        'message': result.message,
        'data': Protocol.toJson(result.data),
      },
    });
  }

  Future<void> _invoke(String method, [Object? arguments]) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      debugPrint('[Graine] native calls are not available in this build (rebuild the app).');
    }
  }

  /// A method an older engine may not have: its absence is not news.
  Future<void> _invokeOptional(String method, [Object? arguments]) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // An engine from before this method: nothing to tell it.
    } on PlatformException catch (e) {
      debugPrint('[Graine] calls: $method failed (${e.code}).');
    }
  }

  static Map<String, Object?>? _screenMap(GraineScreen? s) {
    if (s == null) return null;
    final j = s.journey;
    return <String, Object?>{
      'screen': s.screen,
      if (s.title != null) 'title': s.title,
      if (j != null)
        'journey': <String, Object?>{
          'name': j.name,
          if (j.step != null) 'step': j.step,
          if (j.of != null) 'of': j.of,
          if (j.next != null) 'next': j.next,
        },
      'fields': <Map<String, Object?>>[
        for (final f in s.fields)
          <String, Object?>{
            'name': f.name,
            if (f.label != null) 'label': f.label,
            if (f.value != null) 'value': f.value,
            if (f.status != null) 'status': f.status!.wire,
            if (f.error != null) 'error': f.error,
            if (f.optional) 'optional': true,
          },
      ],
      if (s.error != null) 'error': s.error,
      if (s.data.isNotEmpty) 'data': Protocol.toJson(s.data),
      if (s.availableActions != null) 'availableActions': List<String>.of(s.availableActions!),
    };
  }

  /// For tests: forget everything this instance holds.
  @visibleForTesting
  void resetForTesting() {
    _subscription?.cancel();
    _subscription = null;
    _snapshot = GraineCallSnapshot.idle;
    _nativeLive = false;
    _tokenWatchers.clear();
    _heldOutcomes.clear();
    _heldIncoming.clear();
    _attached = null;
    _configured = false;
    _options = null;
    _agentsSent = const <String, Object?>{};
    _sameAsDefault = const <String>[];
    _unhold?.call();
    _unhold = null;
    _held = null;
    _calling = null;
    _setupTimer?.cancel();
    _setupTimer = null;
    _warned.clear();
  }
}

String? _string(Object? v) => v is String ? v : null;

String _encode(Object? v) => v is Map || v is List ? jsonEncode(v) : '$v';
