part of 'graine.dart';

/// THE CALL, AS A UI SEES IT. [GraineVoice] is the real one; a host with its
/// own design system draws from this, and a test hands a fake to the widgets.
abstract class GraineCallState implements Listenable {
  bool get connected;
  bool get connecting;
  bool get muted;

  /// The engine page said `graine:ready`: a start is an INVITE away.
  bool get ready;

  /// The network interrupted the call and it is being re-established.
  bool get reconnecting;

  /// From the engine page's own view of the network; null before it said.
  bool? get online;
  ConnectionQuality get quality;
  GraineConnectivity get connectivity;

  /// What has been said so far, oldest first, folded (see [Captions]).
  List<Caption> get captions;

  /// The turn being said now, or the last one. Null before any.
  Caption? get caption;

  /// The agent is mid-sentence (its caption is live).
  bool get agentSpeaking;

  /// The last start was refused the microphone.
  bool get micDenied;

  /// The dashboard's Appearance for this agent, empty until the session loads.
  Map<String, Object?> get appearance;

  Future<void> start();
  void end();
  void setMuted(bool muted);
  void retry();
}

/// A CALL THAT CAN SAY IT IS MISCONFIGURED — beside [GraineCallState] rather
/// than in it, so a host's own call state keeps compiling. [GraineVoice]
/// implements it; so may a fake.
abstract interface class GraineCallFault {
  /// What the page reported as permanently wrong with this agent's setup
  /// (a transport that is not configured), or null. The bar says
  /// "Unavailable" while it is set; a new call clears it.
  String? get error;
}

/// A CALL THAT SAYS WHERE A CONNECT IS — beside [GraineCallState], as
/// [GraineCallFault] is, so a host's own call state keeps compiling.
/// [GraineVoice] implements it; so may a fake. The bar draws from it
/// (contract/DESIGN.md, "Connecting").
abstract interface class GraineConnectProgress {
  /// Where the call being placed is, as the engine reports it
  /// (`graine:progress`); null outside a connect. A bar that says
  /// "Reconnecting…" across a retry is one the customer waits for; one that
  /// says "Connecting…" for eight seconds is one they close.
  ConnectStage? get connectStage;

  /// A connect the customer is waiting on — a bar on screen while the page
  /// loads, or a call being placed — has run past `timing.slowConnectMs`.
  /// Say so honestly ("Still connecting…"), not with a faster spinner.
  bool get slowConnect;

  /// The last start could not be connected at all — not on WebRTC, not on
  /// the fallback. Distinct from an error (a setting someone must change):
  /// the network may well be better in a moment, so a start simply tries
  /// again. Cleared by a start, a connected call, and the bar closing.
  bool get callFailed;
}

/// A CHAT WITH THE AGENT, as the bar sees it.
///
/// The dashboard can offer an agent as a call, a chat, or both (Embed &
/// Widgets → mode). This SDK carries the call; an app that runs the chat
/// conversation itself hands it to `GraineAgentBar.chat`, and the bar draws
/// the switch between them and the chat window in the brand's design.
abstract class GraineChatState implements Listenable {
  /// The conversation so far, oldest first; `live` while a line is still arriving.
  List<Caption> get messages;

  /// The chat is connected: its header says "Online".
  bool get connected;

  /// The customer typed [text] and sent it.
  void send(String text);
}

/// What [GraineVoice] needs from the page that carries the call. The real
/// one is a WebView ([GraineEngine] builds it); a test hands in a fake.
abstract class GraineEnginePage {
  /// Called once, by [GraineVoice.attach], before anything else: the page
  /// reports everything that happens to it through [sink].
  void bind(GraineEngineSink sink);

  /// Load the engine page.
  void load(String url);
  void reload();

  /// Evaluate JavaScript in the page.
  void run(String javaScript);

  /// Tear the page down: nothing it does afterwards reaches the call.
  void dispose();
}

/// How a page reports to the call. Created by [GraineVoice]; a page receives
/// one in [GraineEnginePage.bind].
class GraineEngineSink {
  GraineEngineSink._(this._voice, this._page);
  final GraineVoice _voice;
  final GraineEnginePage _page;

  bool get _live => identical(_voice._page, _page);

  /// A navigation began (a load, or a reload).
  void pageStarted() {
    if (_live) _voice._onPageStarted();
  }

  /// Download progress, 0–100.
  void progress(int percent) {
    if (_live) _voice._watchdog.progress(percent, _voice._graine._clock());
  }

  /// The document finished downloading.
  void pageFinished() {
    if (_live) _voice._onPageFinished();
  }

  /// The main frame failed to load (a network error, an HTTP error, a
  /// renderer that died). The page will be reloaded on the retry ladder.
  void mainFrameError(String reason) {
    if (_live) _voice._scheduleRetry(reason);
  }

  /// One message the page posted to `window.ReactNativeWebView`.
  void message(String? raw) {
    if (_live) _voice._onBridge(raw);
  }

  /// The page asks for capture devices. Returns whether to grant. Only the
  /// microphone is ever granted, and only when the app holds it (or has not
  /// said it does not).
  bool microphoneRequested({required bool onlyMicrophone}) =>
      _live && _voice._onMicrophoneRequested(onlyMicrophone: onlyMicrophone);
}

/// THE CALL — a hosted page in a WebView this SDK owns, one invisible pixel
/// big ([GraineEngine]).
///
/// Every fix to the audio path — the TURN relay, the dead-media watchdog,
/// connection quality, the WebSocket fallback — lives in that page and
/// reaches the installed app the day it ships, with no release. The trade is
/// a page load, which is done idle at attach and cached per deployment, so a
/// tap costs one registration and an INVITE.
///
/// A [ChangeNotifier]: a widget that listens redraws on every change.
class GraineVoice extends ChangeNotifier implements GraineCallState, GraineCallFault, GraineConnectProgress {
  GraineVoice._(this._graine)
      : _watchdog = LoadWatchdog(
          stallMs: _graine.config.timing.stallMs,
          bootMs: _graine.config.timing.bootMs,
          hardCapMs: _graine.config.timing.hardCapMs,
        ),
        _ladder = RetryLadder(delaysMs: _graine.config.timing.retryDelaysMs),
        _cacheKey = DateTime.now().millisecondsSinceEpoch.toString();

  final GraineInApp _graine;
  final LoadWatchdog _watchdog;
  final RetryLadder _ladder;

  /// The configuration this call was set up with.
  GraineConfig get config => _graine.config;

  // ── state ────────────────────────────────────────────────────────────────

  bool _connected = false;
  bool _connecting = false;
  bool _muted = false;
  bool _ready = false;
  bool _reconnecting = false;
  bool? _online;
  ConnectionQuality _quality = ConnectionQuality.unknown;
  GraineConnectivity _connectivity = GraineConnectivity.loading;
  List<Caption> _captions = const <Caption>[];
  bool _agentSpeaking = false;
  bool _micDenied = false;
  String? _error;
  Transport? _transport;
  ConnectStage? _connectStage;
  bool _slowConnect = false;
  bool _callFailed = false;

  @override
  bool get connected => _connected;
  @override
  bool get connecting => _connecting;
  @override
  bool get muted => _muted;
  @override
  bool get ready => _ready;
  @override
  bool get reconnecting => _reconnecting;
  @override
  bool? get online => _online;
  @override
  ConnectionQuality get quality => _quality;
  @override
  GraineConnectivity get connectivity => _connectivity;
  @override
  List<Caption> get captions => _captions;
  @override
  Caption? get caption => _captions.isEmpty ? null : _captions.last;
  @override
  bool get agentSpeaking => _agentSpeaking;
  @override
  bool get micDenied => _micDenied;
  @override
  String? get error => _error;
  @override
  ConnectStage? get connectStage => _connectStage;
  @override
  bool get slowConnect => _slowConnect;
  @override
  bool get callFailed => _callFailed;
  @override
  Map<String, Object?> get appearance => _graine.session?.appearance ?? const <String, Object?>{};

  /// Where the call stands in one word — idle, connecting, reconnecting,
  /// thinking, speaking, listening — as the React Native launcher's `phase`.
  CallPhase get phase => callPhase(
        reconnecting: _reconnecting,
        connectivity: _connectivity,
        connecting: _connecting,
        ready: _ready,
        connected: _connected,
        caption: caption,
        agentSpeaking: _agentSpeaking,
      );

  /// The transport that actually carries the call, once the page has said.
  Transport? get transport => _transport;

  /// Whether an engine page is attached ([GraineEngine] is mounted).
  bool get attached => _page != null;

  // ── internals ────────────────────────────────────────────────────────────

  GraineEnginePage? _page;
  bool _pendingStart = false;
  bool _startedCall = false;
  bool _endNotified = true;
  bool _askingMic = false;
  bool? _micGranted;
  bool _urlLoaded = false;
  int _loadToken = 0;
  String _cacheKey;
  List<void Function()> _unwatch = const <void Function()>[];
  Timer? _checkTimer;
  Timer? _retryTimer;
  Timer? _endWatchdog;
  Timer? _backgroundConfirm;
  Timer? _slowTimer;

  /// UIs showing this call on screen ([viewOpened]).
  int _views = 0;

  /// Mount the engine: [GraineEngine] calls this with its WebView page; a
  /// test calls it with a fake. Loads the page idle — nothing registered,
  /// nothing dialled, no microphone. Attaching another page ends any call on
  /// the last one.
  void attach(GraineEnginePage page) {
    if (identical(_page, page)) return;
    detach();
    _page = page;
    page.bind(GraineEngineSink._(this, page));
    _unwatch = <void Function()>[
      _graine._onVariables((Map<String, String> vars) {
        if (_ready) _post(Protocol.out(ProtocolOut.variables, <String, Object?>{'variables': vars}));
      }),
      _graine._onContext((Map<String, Object?> frame) {
        if (_connected) _postContext(frame);
      }),
      () => _graine._foregroundWatchers.remove(_foregroundChanged),
    ];
    _graine._foregroundWatchers.add(_foregroundChanged);
    _load(idle: true);
    notifyListeners();
  }

  /// Detach [page] if it is the one attached — what [GraineEngine] does on unmount.
  void detachPage(GraineEnginePage page) {
    if (identical(_page, page)) detach();
  }

  /// Remove the engine. Hangs up first — a call must never outlive its UI.
  void detach() {
    final page = _page;
    if (page == null) return;
    _post(Protocol.out(ProtocolOut.endCall));
    for (final u in _unwatch) {
      u();
    }
    _unwatch = const <void Function()>[];
    _cancelTimers();
    _page = null;
    _urlLoaded = false;
    _loadToken++;
    page.dispose();
    _ready = false;
    _startedCall = false;
    _pendingStart = false;
    _error = null;
    _clearProgress();
    _setCall(false, false);
    notifyListeners();
  }

  void _cancelTimers() {
    _checkTimer?.cancel();
    _retryTimer?.cancel();
    _endWatchdog?.cancel();
    _backgroundConfirm?.cancel();
    _slowTimer?.cancel();
    _checkTimer = _retryTimer = _endWatchdog = _backgroundConfirm = _slowTimer = null;
  }

  /// A UI showing this call came on screen — [GraineAgentBar] says so
  /// itself; a host drawing its own bar may too, paired with [viewClosed].
  /// While one is, a page still loading is a customer waiting, and after
  /// `timing.slowConnectMs` the call says so ([slowConnect]). An idle page
  /// loading behind no bar at all is nobody's slow connect.
  void viewOpened() {
    _views++;
    // No notification: nothing a listener draws has changed yet, and this
    // runs while the bar is being built.
    _syncSlowConnect();
  }

  /// A UI from [viewOpened] left the screen. When the last one goes, the
  /// customer has closed the agent: a failed connect and its stage are no
  /// longer news.
  void viewClosed() {
    if (_views == 0) return;
    _views--;
    final before = (_callFailed, _connectStage, _slowConnect);
    if (_views == 0) _clearProgress();
    _syncSlowConnect();
    if (before != (_callFailed, _connectStage, _slowConnect)) {
      // Not synchronously: this runs while the bar is being unmounted.
      scheduleMicrotask(notifyListeners);
    }
  }

  void _clearProgress() {
    _callFailed = false;
    _connectStage = null;
  }

  /// The customer is actually waiting on a connect: a call being placed, or
  /// a bar on screen while the page is not ready — and neither connected nor
  /// given up on. A clock on the wait, not on the network: the network is
  /// the engine's to report.
  bool get _waitingOnConnect =>
      _page != null && !_connected && !_callFailed && (_connecting || (!_ready && _views > 0));

  /// Arm "Still connecting…" when a wait begins; disarm (and clear it) the
  /// moment the wait ends. A wait that continues keeps its clock.
  void _syncSlowConnect() {
    if (!_waitingOnConnect) {
      _slowTimer?.cancel();
      _slowTimer = null;
      _slowConnect = false;
      return;
    }
    if (_slowConnect || _slowTimer != null) return;
    _slowTimer = Timer(Duration(milliseconds: _graine.config.timing.slowConnectMs), () {
      _slowTimer = null;
      if (!_waitingOnConnect) return;
      _slowConnect = true;
      notifyListeners();
    });
  }

  /// Every change a listener hears about is also a chance for the wait to
  /// have begun or ended.
  @override
  void notifyListeners() {
    _syncSlowConnect();
    super.notifyListeners();
  }

  /// Place the call. With [GraineConfig.requestMicrophone] set, the app is
  /// asked for the microphone first and a refusal places nothing. Before the
  /// page is ready the start is held and fired on ready — which is what the
  /// customer meant.
  @override
  Future<void> start() async {
    if (_page == null) {
      _graine._report((GraineListener l) =>
          l.onError('Place GraineEngine near the root of the app before starting a call.'));
      return;
    }
    _micDenied = false;
    _error = null;
    // A new attempt: the last one's failure and stage are not news.
    _clearProgress();
    // A new call, not a continuation: the last one's words do not open this one.
    _captions = const <Caption>[];
    _agentSpeaking = false;
    _setCall(_connected, true);
    final ask = _graine.config.requestMicrophone;
    if (ask != null) {
      _pendingStart = true;
      _askingMic = true;
      notifyListeners();
      bool granted;
      try {
        granted = await ask();
      } catch (e) {
        // A permission API that throws on some OEM build must not stop a
        // call being attempted; the page reports mic-denied if it really was.
        debugPrint('[Graine] requestMicrophone threw ($e); trying the call anyway.');
        granted = true;
      }
      _askingMic = false;
      _micGranted = granted;
      if (!_pendingStart) {
        notifyListeners();
        return; // ended while the dialog was up
      }
      if (!granted) {
        _pendingStart = false;
        _setCall(false, false);
        _micDenied = true;
        _graine._report((GraineListener l) => l.onMicDenied('NotAllowedError'));
        notifyListeners();
        return;
      }
    }
    if (!_ready) {
      _pendingStart = true;
      notifyListeners();
      return;
    }
    _pendingStart = false;
    _beginCall();
    notifyListeners();
  }

  /// Hang up. Guaranteed: if the page never confirms a call it placed, the
  /// call is torn down locally after `timing.endWatchdogMs`.
  @override
  void end() {
    _pendingStart = false;
    _post(Protocol.out(ProtocolOut.endCall));
    _endWatchdog?.cancel();
    _endWatchdog = null;
    if (_connected || _startedCall) {
      _endWatchdog = Timer(Duration(milliseconds: _graine.config.timing.endWatchdogMs), _forceEnd);
    } else {
      // Nothing was placed — a held start, or idle: nothing to tear down.
      _setCall(false, false);
    }
    notifyListeners();
  }

  /// Stop sending the customer's voice without ending the call.
  @override
  void setMuted(bool muted) {
    _muted = muted;
    _post(Protocol.out(ProtocolOut.setMuted, <String, Object?>{'muted': muted}));
    notifyListeners();
  }

  /// The customer answered a component. [summary] is the sentence the agent
  /// hears ("Let's compare Creta and Seltos.") — without it the tap lands and
  /// the conversation does not move.
  void answerWidget(String widgetId, Map<String, Object?> data, String summary) {
    _graine.clearPendingWidget();
    _post(Protocol.out(ProtocolOut.widgetResult,
        <String, Object?>{'widgetId': widgetId, 'data': data, 'summary': summary}));
  }

  /// Something happened that the agent may want to speak up about. Only
  /// during a call; the screen goes first, since the event is about it.
  void reportEvent(String name,
      {String? detail, Map<String, Object?> data = const <String, Object?>{}}) {
    if (!_connected) return;
    final frame = _graine._currentContextFrame();
    if (frame != null) _postContext(frame);
    final payload = <String, Object?>{...data, if (detail != null) 'detail': detail};
    _post(Protocol.out(ProtocolOut.appEvent, <String, Object?>{'name': name, 'data': payload}));
  }

  /// Reload the page and start the retry ladder over. For a "Try again" button.
  @override
  void retry() {
    _ladder.reset();
    _retryTimer?.cancel();
    _retryTimer = null;
    _setConnectivity(GraineConnectivity.loading, null);
    if (_urlLoaded) {
      _page?.reload();
    } else {
      _load(idle: true);
    }
    notifyListeners();
  }

  void _sessionChanged() => notifyListeners();

  void _load({required bool idle}) {
    final token = ++_loadToken;
    _graine.loadSession().then((SessionConfig? session) {
      final page = _page;
      if (page == null || token != _loadToken) return;
      if (session == null) {
        _setConnectivity(GraineConnectivity.failed, 'session');
        notifyListeners();
        return;
      }
      final version = session.pageVersion;
      if (version != null) _cacheKey = version;
      final url = Protocol.engineUrl(
        baseUrl: _graine.config.baseUrl,
        voiceAgentId: session.webcallAgentId,
        transport: _graine.config.transport ?? session.preferredTransport,
        cacheKey: _cacheKey,
        idle: idle,
        publishableKey: _graine.config.publishableKey,
        accent: session.accent,
      );
      _urlLoaded = true;
      page.load(url);
    });
  }

  void _beginCall() {
    _startedCall = true;
    _endNotified = true;
    // A new call: the last one's unanswered component must not come back over it.
    _graine.clearPendingWidget();
    _post(Protocol.out(ProtocolOut.startCall));
  }

  /// Deliver one message into the page.
  void _post(Map<String, Object?> message) {
    final page = _page;
    if (page == null) return;
    if (_graine.config.debug) {
      debugPrint('[Graine] → page ${message['type']} ${_redactForLog(message)}');
    }
    page.run(Protocol.deliver(message));
  }

  /// Debug logs name what was sent without dumping a customer's variables or fields.
  static String _redactForLog(Map<String, Object?> m) {
    switch (m['type']) {
      case ProtocolOut.variables:
        final v = m['variables'];
        return '{${v is Map ? v.keys.join(', ') : ''}}';
      case ProtocolOut.appContext:
        final c = m['context'];
        return 'screen=${c is Map ? c['screen'] : null}';
      default:
        final s = jsonEncode(m);
        return s.length > 300 ? s.substring(0, 300) : s;
    }
  }

  void _postContext(Map<String, Object?> frame) {
    _post(<String, Object?>{...frame, 'type': ProtocolOut.appContext});
  }

  void _setCall(bool connected, bool connecting) {
    final changed = connected != _connected || connecting != _connecting;
    final liveChanged = connected != _connected;
    _connected = connected;
    _connecting = connecting;
    if (liveChanged) _graine._callStateChanged(connected);
    if (changed) {
      _graine.components._onCall(connected || connecting);
      _graine._report((GraineListener l) => l.onCallState(connected, connecting));
    }
  }

  void _setConnectivity(GraineConnectivity state, String? reason) {
    _connectivity = state;
    _graine._report((GraineListener l) => l.onConnectivity(state, _ladder.attempt, reason));
  }

  void _setQuality(ConnectionQuality q) {
    if (q == _quality) return;
    _quality = q;
    _graine._report((GraineListener l) => l.onQuality(q));
  }

  // ── what the page says ───────────────────────────────────────────────────

  void _onPageStarted() {
    _ready = false;
    _watchdog.start(_graine._clock());
    _checkTimer?.cancel();
    final first = _graine.config.timing.stallMs < 1000 ? _graine.config.timing.stallMs : 1000;
    _checkTimer = Timer(Duration(milliseconds: first), _onWatchdogTick);
    notifyListeners();
  }

  void _onPageFinished() {
    _watchdog.loaded(_graine._clock());
    if (_graine.config.debug) _page?.run(SocketTrace.js);
  }

  void _onBridge(String? raw) {
    if (_graine.config.debug) {
      final s = raw ?? '';
      debugPrint('[Graine] ← page ${s.length > 600 ? s.substring(0, 600) : s}');
    }
    final msg = Protocol.parse(raw);
    if (msg == null) return;
    _handle(msg);
    notifyListeners();
  }

  void _handle(PageMessage msg) {
    switch (msg) {
      case PageReady():
        _ready = true;
        _checkTimer?.cancel();
        _checkTimer = null;
        _retryTimer?.cancel();
        _retryTimer = null;
        _ladder.reset();
        _setConnectivity(GraineConnectivity.ready, null);
        // Who the customer is, before anything else: the greeting is composed
        // from these and nothing later can repair it.
        _post(Protocol.out(ProtocolOut.variables, <String, Object?>{'variables': _graine.currentVariables()}));
        final frame = _graine._currentContextFrame();
        if (frame != null) _postContext(frame);
        if (_pendingStart && !_askingMic && _micGranted != false) {
          _pendingStart = false;
          _beginCall();
        } else if (!_startedCall) {
          _post(Protocol.out(ProtocolOut.warm));
        }
      case PageCall(connected: final connected, connecting: final connecting):
        if (connected) {
          _endNotified = false;
          _reconnecting = false;
          _endWatchdog?.cancel();
          _endWatchdog = null;
          // Answered: no longer retrying, and no longer failed.
          _clearProgress();
        }
        // The page announces "not connected" as it loads. With a start queued
        // behind it that is not idle — the bar must keep saying "connecting".
        final held = _pendingStart && !connected;
        _setCall(connected, connecting || held);
        if (connected) {
          final frame = _graine._currentContextFrame();
          if (frame != null) _postContext(frame);
        }
        if (!connected && !connecting) _startedCall = false;
      case PageMuted(muted: final muted):
        _muted = muted;
      case PageCaption(role: final role, text: final text, live: final live):
        _captions = Captions.fold(_captions, Caption(role, text, live: live));
        _agentSpeaking = role == Role.agent && live;
        if (role == Role.agent) _graine.components._agentStarted();
        _graine._report((GraineListener l) => l.onCaption(role, text, live));
      case PageWidget(widget: final widget):
        // Retained before it is dispatched, so a view mounted later still finds it.
        _graine._pendingWidget = widget;
        _graine.components._onWidget(widget);
        _graine._report((GraineListener l) => l.onWidget(widget));
      case PageWidgetPending(widget: final hint):
        _graine.components._onPending(hint);
        _graine._report((GraineListener l) => l.onWidgetPending(hint));
      case PageAppAction(actionId: final actionId, name: final name, arguments: final args):
        _graine.executeAction(name, args).then((ActionResult r) {
          _post(Protocol.out(ProtocolOut.appActionResult, <String, Object?>{
            'actionId': actionId,
            'status': r.status.wire,
            'message': r.message,
            'data': r.data,
          }));
        });
      case PageEnded():
        _endWatchdog?.cancel();
        _endWatchdog = null;
        _reconnecting = false;
        _setCall(false, false);
        _startedCall = false;
        _agentSpeaking = false;
        _setQuality(ConnectionQuality.unknown);
        _graine.components._ended();
        if (!_endNotified) {
          _endNotified = true;
          _graine._report((GraineListener l) => l.onEnded());
        }
      case PageMicDenied(reason: final reason):
        _pendingStart = false;
        _setCall(false, false);
        _micDenied = true;
        _graine._report((GraineListener l) => l.onMicDenied(reason));
      case PageTransport(
          transport: final transport,
          requested: final requested,
          reason: final reason,
          message: final message
        ):
        _transport = transport;
        _graine._report((GraineListener l) => l.onTransport(transport, requested, reason, message));
        // A misconfiguration is an error even though the call survived it —
        // held, so a bar can say so, and reported to whoever has to fix it.
        if (reason == 'not_configured' && message != null) {
          _error = message;
          _graine._report((GraineListener l) => l.onError(message));
        }
      case PageQuality(rttMs: final rtt, jitterMs: final jitter, loss: final loss):
        _setQuality(ConnectionQuality.classify(rtt, jitter, loss));
      case PageNetwork(online: final online):
        _online = online;
        _graine._report((GraineListener l) => l.onNetwork(online));
        if (!online) _setQuality(ConnectionQuality.lost);
      case PageReconnecting(active: final active):
        _reconnecting = active;
        if (active) _setCall(_connected, true);
        _graine._report((GraineListener l) => l.onReconnecting(active));
      case PageProgress(failed: true):
        // Neither transport could carry the call. The bar must stop saying
        // "connecting" and offer another try; the host hears the attempt is over.
        _connectStage = null;
        _callFailed = true;
        _startedCall = false;
        _pendingStart = false;
        if (_connecting) {
          _setCall(_connected, false);
        } else {
          // Already not connecting (the page said so first): still the end of an attempt.
          _graine._report((GraineListener l) => l.onCallState(_connected, false));
        }
      case PageProgress(stage: final stage):
        // A stage this SDK does not know is ignored, not stored.
        final known = ConnectStage.from(stage);
        if (known != null) _connectStage = known;
    }
  }

  bool _onMicrophoneRequested({required bool onlyMicrophone}) {
    if (!onlyMicrophone) {
      debugPrint('[Graine] The page asked for more than the microphone; refused.');
      return false;
    }
    if (_micGranted == false) {
      _graine._report((GraineListener l) => l.onMicDenied('NotAllowedError'));
      return false;
    }
    return true;
  }

  /// The page never confirmed the hang-up. Force it: state, the callback, and
  /// a reload that tears the media down.
  void _forceEnd() {
    _endWatchdog = null;
    _setCall(false, false);
    _startedCall = false;
    _agentSpeaking = false;
    _graine.components._ended();
    if (!_endNotified) {
      _endNotified = true;
      _graine._report((GraineListener l) => l.onEnded());
    }
    _page?.reload();
    notifyListeners();
  }

  void _onWatchdogTick() {
    _checkTimer = null;
    if (_ready || _page == null || _retryTimer != null) return;
    final now = _graine._clock();
    final verdict = _watchdog.check(now);
    if (verdict == LoadVerdict.wait) {
      _checkTimer = Timer(Duration(milliseconds: _watchdog.nextCheckInMs(now)), _onWatchdogTick);
    } else {
      _scheduleRetry(verdict.reason);
    }
  }

  void _scheduleRetry(String reason) {
    _checkTimer?.cancel();
    _checkTimer = null;
    if (_connected) return; // never reload a page that is carrying a call
    final delay = _ladder.next();
    if (delay == null) {
      _setConnectivity(GraineConnectivity.failed, reason);
      _pendingStart = false;
      _setCall(false, false);
      _graine._report((GraineListener l) =>
          l.onError('The assistant could not load. Check your connection and try again.'));
      notifyListeners();
      return;
    }
    _ready = false;
    _setConnectivity(GraineConnectivity.retrying, reason);
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(milliseconds: delay), () {
      _retryTimer = null;
      _page?.reload();
    });
    notifyListeners();
  }

  void _foregroundChanged(bool foreground) {
    _backgroundConfirm?.cancel();
    _backgroundConfirm = null;
    if (foreground) {
      // Whatever screen the app is on now is the one the agent must see.
      if (_connected) {
        final frame = _graine._currentContextFrame();
        if (frame != null) _postContext(frame);
      }
      // And idle: the page keeps a SIP registration warm so a tap costs only
      // the INVITE, but a phone drops that idle socket while the app sleeps,
      // and the page's own visibilitychange is not reliably what wakes it in
      // a web view a pixel wide. The app knows it is back, so it says so —
      // only when the page can hear it, never during a call. The same rule as
      // the React Native launcher and the native SDKs' Warm.onForeground.
      if (_ready && !_startedCall && !_connected && !_connecting) {
        _post(Protocol.out(ProtocolOut.warm));
      }
      return;
    }
    // Confirmed after two seconds: a permission dialog or the app switcher
    // briefly backgrounds the app, and ending on that would hang up the call
    // that asked for the microphone.
    if (_graine.config.endOnBackground && (_connected || _connecting)) {
      _backgroundConfirm = Timer(const Duration(seconds: 2), () {
        _backgroundConfirm = null;
        if (!_graine._foreground) end();
      });
    }
  }
}
