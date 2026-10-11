part of 'graine.dart';

/// Where a native call is.
enum GraineCallStatus {
  idle('idle'),
  ringing('ringing'),
  connecting('connecting'),
  active('active'),
  ended('ended');

  const GraineCallStatus(this.wire);
  final String wire;

  /// Ringing, connecting or connected.
  bool get isLive => this == ringing || this == connecting || this == active;

  static GraineCallStatus fromWire(Object? s) {
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
    this.status = GraineCallStatus.idle,
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
      status: GraineCallStatus.fromWire(m['state']),
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
    );
  }

  final GraineCallStatus status;

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
      other.error == error;

  @override
  int get hashCode => Object.hash(status, callId, direction, reason, callerName, muted, speakerOn,
      agentSpeaking, caption, connectedAt, error);
}

/// What became of a call.
enum GraineCallOutcomeKind { answered, declined, missed, ended, failed }

/// What became of a call — tell your server, with [callId].
class GraineCallOutcome {
  const GraineCallOutcome(this.callId, this.kind, {this.endReason, this.error});

  factory GraineCallOutcome.fromMap(Map<Object?, Object?> m) {
    final word = m['outcome'];
    final kind = GraineCallOutcomeKind.values.firstWhere((GraineCallOutcomeKind k) => k.name == word,
        orElse: () => GraineCallOutcomeKind.failed);
    return GraineCallOutcome(
      _string(m['callId']) ?? '',
      kind,
      endReason: kind == GraineCallOutcomeKind.ended ? _string(m['reason']) : null,
      error: kind == GraineCallOutcomeKind.failed ? _string(m['error']) : null,
    );
  }

  final String callId;
  final GraineCallOutcomeKind kind;

  /// With [GraineCallOutcomeKind.ended]: `local` (this app hung up), `remote`
  /// (the agent did) or `failed` (the connection broke mid-call).
  final String? endReason;

  /// With [GraineCallOutcomeKind.failed]: why the call never connected.
  final String? error;

  /// One word for your server: answered · declined · missed · ended · failed.
  String get wire => kind.name;

  @override
  String toString() => 'GraineCallOutcome($callId, $wire${endReason != null ? ', $endReason' : ''})';
}

/// An agent's call ringing on this device.
class GraineIncomingCall {
  const GraineIncomingCall(this.callId, {this.reason, this.callerName});

  final String callId;
  final String? reason;
  final String? callerName;
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
    this.debug = false,
    this.androidSmallIcon,
    this.iosIconTemplate,
    this.iosIncludesCallsInRecents = false,
  });

  /// Agent → Embed & Widgets. Public by design.
  final String publishableKey;

  /// The name on the ring and the call screen — your agent's or your brand's.
  /// A push's `caller_name` wins for its own call.
  final String displayName;
  final String baseUrl;

  /// iOS: a sound file of 30 seconds or less in the app bundle. Android: a
  /// `res/raw` resource name. Null: the phone's own ringtone.
  final String? ringtoneSound;

  /// How long an agent's call rings before it is missed.
  final Duration ringTimeout;

  /// Which build placed the call; it lands on the call record.
  final String? appVersion;

  /// Who draws the call while the app is open. [GraineCallScreen.sdk] (the
  /// default): the SDK's call screen — on Android its full-screen call
  /// activity, on iOS a full-screen view over your app. [GraineCallScreen.app]:
  /// your own screen, drawn from [GraineCalls.instance]. A locked iPhone
  /// always shows the system's call screen.
  final GraineCallScreen callScreen;

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
  Future<void> configure(GraineCallsOptions options) async {
    if (options.publishableKey.trim().isEmpty) {
      throw ArgumentError.value(options.publishableKey, 'publishableKey', 'is required');
    }
    if (options.displayName.trim().isEmpty) {
      throw ArgumentError.value(options.displayName, 'displayName', 'is required');
    }
    if (!isSupported) return;
    _listen();
    await _channel.invokeMethod<void>('configure', options.toMap());
    _apply(await _channel.invokeMapMethod<Object?, Object?>('snapshot'));
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

  /// Android: a push's data, from your Firebase message handlers — foreground
  /// and background. A Graine call rings with a call notification, even when
  /// the app was not running. True when the push was a call (ringing, busy or
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

  /// The customer calls the agent. The agent hears `who_called = "customer"`
  /// and `call_reason`, with [variables] over the app's own. Returns the
  /// call's id — every outcome carries it — or null when a call is already
  /// live (one at a time).
  Future<String?> startCall({String? reason, Map<String, Object?> variables = const <String, Object?>{}}) async {
    if (!isSupported) return null;
    _listen();
    try {
      return await _channel.invokeMethod<String>('startCall', <String, Object?>{
        if (reason != null) 'reason': reason,
        'variables': Protocol.toJson(variables),
      });
    } on MissingPluginException {
      debugPrint('[Graine] native calls are not available in this build (rebuild the app).');
      return null;
    }
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
  void Function() attach([GraineInApp? graine]) {
    final g = graine ?? GraineInApp.instance;
    _attached = g;
    if (!isSupported) return () {};
    _listen();
    void pushVariables() {
      _invoke('setIdentity', g._variables.identity());
      _invoke('setVariables', g.currentVariables());
    }

    void pushScreen() {
      _invoke('setScreen', _screenMap(g._screen));
      _invoke('setActions', g._actions.names);
    }

    pushVariables();
    pushScreen();
    final offVariables = g._onVariables((Map<String, String> _) => pushVariables());
    final offContext = g._onContext((Map<String, Object?> _) => pushScreen());
    return () {
      offVariables();
      offContext();
      if (identical(_attached, g)) {
        _attached = null;
        _invoke('setActions', const <String>[]);
      }
    };
  }

  void _listen() {
    if (_subscription != null || !isSupported) return;
    _subscription = _events.receiveBroadcastStream().listen(_onEvent,
        onError: (Object e) => debugPrint('[Graine] calls: $e'));
  }

  void _onEvent(Object? raw) {
    if (raw is! Map) return;
    final data = raw['data'];
    final payload = data is Map ? data : const <Object?, Object?>{};
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
                reason: _string(payload['reason']), callerName: _string(payload['callerName'])));
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
    final next = GraineCallSnapshot.fromMap(m);
    if (next == _snapshot) return;
    final wasLive = _snapshot.status.isLive;
    _snapshot = next;
    _nativeLive = next.status.isLive;
    if (!wasLive && next.status.isLive) {
      // One call at a time: the native call takes the line from the WebView engine.
      final voice = (_attached ?? GraineInApp.maybeInstance)?.voice;
      if (voice != null && (voice.connected || voice.connecting)) voice.end();
    }
    notifyListeners();
  }

  Future<void> _answerAction(Map<Object?, Object?> request) async {
    final requestId = _string(request['requestId']);
    final name = _string(request['name']) ?? '';
    if (requestId == null) return;
    final arguments = request['arguments'];
    final g = _attached;
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
  }
}

String? _string(Object? v) => v is String ? v : null;

String _encode(Object? v) => v is Map || v is List ? jsonEncode(v) : '$v';
