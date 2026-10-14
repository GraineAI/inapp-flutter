part of 'graine.dart';

/// A CHAT THAT IS OPENED AND CLOSED with the customer — beside
/// [GraineChatState], as [GraineCallFault] is beside the call state, so a
/// host's own chat keeps compiling. [GraineChatSession] implements it; the
/// bar opens a chat that does when the customer is in the chat, and closes it
/// when they leave.
abstract interface class GraineChatConnection {
  /// A connection is being made, or remade after a drop.
  bool get connecting;

  /// The customer is in the chat: connect, and stay connected.
  void open();

  /// The customer left the chat: hang up.
  void close();
}

/// A CHAT THAT SAYS THE AGENT IS COMPOSING — beside [GraineChatState]. The
/// chat window draws a typing bubble while it is true.
abstract interface class GraineChatTyping {
  /// The agent owes an answer and has not said a word of it yet.
  bool get agentTyping;
}

/// One open chat socket, as the chat sees it. The real one is `dart:io`'s
/// WebSocket; a test hands in a fake through [GraineInApp.forTesting].
abstract class GraineChatSocket {
  /// The frames as they arrive; done when the socket closes.
  Stream<Object?> get frames;

  /// Put one text frame on the wire.
  void send(String data);

  Future<void> close();
}

/// Opens a [GraineChatSocket] to [url], offering [protocols].
typedef GraineChatConnector = Future<GraineChatSocket> Function(Uri url, List<String>? protocols);

/// THE TEXT CHAT — a conversation in writing with the agent, on its own
/// socket, the same agent and the same context as the call.
///
/// The React Native SDK's text path, with what it lacked: one bubble per agent
/// turn (a reply ends on its end marker), a typing indicator from the
/// customer's message to the agent's first words, a reconnect with backoff
/// after a drop while the customer is in the chat, and messages typed while
/// offline kept on screen and sent the moment it connects. Components the
/// agent draws in the chat land in [GraineInApp.components] and are answered
/// on this socket; its in-app actions run through [GraineInApp.registerAction];
/// the screen reaches it as it changes.
///
/// [GraineInApp.chat] is the one instance. A [ChangeNotifier]: a widget that
/// listens redraws on every change.
class GraineChatSession extends ChangeNotifier implements GraineChatState, GraineChatConnection, GraineChatTyping {
  GraineChatSession._(this._graine, {GraineChatConnector? connector})
      : _connector = connector ?? _ioConnect,
        _ladder = RetryLadder(delaysMs: _graine.config.timing.retryDelaysMs) {
    _unwatch = <void Function()>[
      _graine._onContext((Map<String, Object?> frame) {
        if (_connected) _send(ChatWire.appContext(frame));
      }),
      () => _graine._foregroundWatchers.remove(_foregroundChanged),
    ];
    _graine._foregroundWatchers.add(_foregroundChanged);
  }

  final GraineInApp _graine;
  final GraineChatConnector _connector;
  final RetryLadder _ladder;
  final ChatTranscript _transcript = ChatTranscript();

  /// The agent this chat is with.
  GraineInApp get app => _graine;

  bool _notifyQueued = false;

  /// Every change reaches the listeners at once — except while the widget
  /// tree is locked: a chat screen leaving closes the chat from its dispose
  /// while another view of the same chat (the bar beneath it) listens. They
  /// hear it straight after that frame.
  @override
  void notifyListeners() {
    if (!_treeLocked()) {
      super.notifyListeners();
      return;
    }
    if (_notifyQueued) return;
    _notifyQueued = true;
    scheduleMicrotask(() {
      _notifyQueued = false;
      if (!_disposed) super.notifyListeners();
    });
  }

  static bool _treeLocked() {
    try {
      return SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks;
    } catch (_) {
      return false; // no binding, no widget tree
    }
  }
  late final List<void Function()> _unwatch;

  GraineChatSocket? _socket;
  StreamSubscription<Object?>? _subscription;
  Future<void>? _opening;
  bool _wanted = false;
  bool _connected = false;
  bool _failed = false;
  String? _error;
  Timer? _ping;
  Timer? _retry;
  Timer? _backgroundConfirm;

  /// Bumped whenever the chat is hung up on purpose: a connect still in
  /// flight from before is nobody's, and closes itself when it lands.
  int _generation = 0;
  bool _disposed = false;

  List<GraineScheduledCall> _upcoming = const <GraineScheduledCall>[];
  final Map<String, GraineUpcomingCancel> _cancels = <String, GraineUpcomingCancel>{};
  Future<void>? _upcomingLoad;
  int? _upcomingAt;

  /// This server has no booked calls to list (an older one): stop asking.
  bool _upcomingOff = false;

  /// After an agent's turn, the booked calls are read again at most this
  /// often: the agent may have just booked one.
  static const int _upcomingEveryMs = 30000;

  // ── state ────────────────────────────────────────────────────────────────

  /// The conversation so far as captions, oldest first: one per turn, the
  /// agent's `live` while it is still arriving. [turns] says more.
  @override
  List<Caption> get messages => _transcript.messages;

  /// THE CONVERSATION SO FAR, oldest first — WIRE.md's `GraineChatTurn`: one
  /// per turn, with who, what, when, a user turn's delivery (sending, sent,
  /// failed), whether an agent turn was volunteered, and the component it drew.
  List<GraineChatTurn> get turns => _transcript.turns;

  /// The socket is open: the window says "Online".
  @override
  bool get connected => _connected;

  @override
  bool get connecting => _opening != null || (_wanted && !_connected && _retry != null);

  @override
  bool get agentTyping => _connected && _transcript.agentTyping;

  /// Every reconnect was spent: the chat stays offline until the customer
  /// sends something, or [open] is called again.
  bool get failed => _failed;

  /// Why the last connect failed, for a log; null once connected.
  String? get error => _error;

  /// The customer is in the chat ([open] was called and [close] was not).
  bool get isOpen => _wanted;

  /// THE USER'S BOOKED CALLS still to ring, soonest first — what the chat
  /// window's Upcoming calls card shows (it draws the first three). Read when
  /// the chat connects, after a booking or a cancel through this SDK, back in
  /// the foreground, and after the agent speaks (at most every 30 s: it may
  /// have just booked one).
  List<GraineScheduledCall> get upcomingCalls => _upcoming;

  /// Where a booked call's Cancel is.
  GraineUpcomingCancel cancelStateOf(String id) => _cancels[id] ?? GraineUpcomingCancel.none;

  /// Read the booked calls again now.
  Future<void> refreshUpcoming() => _upcomingLoad ??= _loadUpcoming().whenComplete(() => _upcomingLoad = null);

  /// The card's Cancel: "Cancelling…" until Graine answers, then the row
  /// goes; on a failure the row says so, and a tap tries again.
  Future<void> cancelUpcoming(String id) async {
    if (_cancels[id] == GraineUpcomingCancel.cancelling) return;
    _cancels[id] = GraineUpcomingCancel.cancelling;
    notifyListeners();
    try {
      await _graine.cancelScheduledCall(id); // takes the row away (_cancelled)
    } catch (e) {
      if (_disposed) return;
      _cancels[id] = GraineUpcomingCancel.failed;
      if (_graine.config.debug) debugPrint('[Graine] chat: could not cancel the booked call: $e');
      notifyListeners();
    }
  }

  Future<void> _loadUpcoming() async {
    final session = await _graine.loadSession();
    // An older server says nothing about calls: it has no booked calls to list.
    if (session?.calls == null || _upcomingOff || _disposed) return;
    final generation = _generation;
    _upcomingAt = _graine._clock();
    try {
      final calls = await _graine.scheduledCalls();
      if (_disposed || generation != _generation) return;
      _setUpcoming(calls);
    } on GraineException catch (e) {
      if (e.code == GraineErrorCode.notFound) _upcomingOff = true;
    } catch (e) {
      // Fire and forget: the card is a courtesy, never an error the customer sees.
      if (_graine.config.debug) debugPrint('[Graine] chat: could not read the booked calls: $e');
    }
  }

  void _setUpcoming(List<GraineScheduledCall> calls) {
    final booked = <GraineScheduledCall>[
      for (final c in calls)
        if (c.status == GraineCallStatus.scheduled) c,
    ];
    // Soonest first; a call with no time last.
    booked.sort((GraineScheduledCall a, GraineScheduledCall b) =>
        a.at == null ? (b.at == null ? 0 : 1) : (b.at == null ? -1 : a.at!.compareTo(b.at!)));
    _upcoming = List<GraineScheduledCall>.unmodifiable(booked);
    _cancels.removeWhere((String id, GraineUpcomingCancel _) => !booked.any((GraineScheduledCall c) => c.id == id));
    notifyListeners();
  }

  /// A call booked through this SDK: on the card at once.
  void _booked(GraineScheduledCall call) {
    if (_disposed) return;
    _setUpcoming(<GraineScheduledCall>[..._upcoming.where((GraineScheduledCall c) => c.id != call.id), call]);
  }

  /// A call cancelled through this SDK: off the card.
  void _cancelled(String id) {
    if (_disposed) return;
    _cancels.remove(id);
    _setUpcoming(<GraineScheduledCall>[..._upcoming.where((GraineScheduledCall c) => c.id != id)]);
  }

  /// After the agent's turn: the booked calls again, unless read lately.
  void _maybeRefreshUpcoming() {
    final at = _upcomingAt;
    if (at != null && _graine._clock() - at < _upcomingEveryMs) return;
    unawaited(refreshUpcoming());
  }

  // ── what the customer does ───────────────────────────────────────────────

  @override
  void open() {
    if (_disposed) return;
    // One conversation at a time, across the app's agents.
    if (!_wanted) _graine._takeConversation();
    _wanted = true;
    _retryNow();
    notifyListeners();
  }

  @override
  void close() {
    if (_disposed) return;
    _wanted = false;
    _generation++;
    _cancelRetry();
    _backgroundConfirm?.cancel();
    _backgroundConfirm = null;
    _hangUp();
    _ladder.reset();
    _failed = false;
    notifyListeners();
  }

  /// The customer typed [text] and sent it. Shown at once; sent now when
  /// connected, else kept and sent the moment the chat connects (and the
  /// chat connects for it).
  @override
  void send(String text) {
    if (_disposed) return;
    final t = text.trim();
    if (t.isEmpty) return;
    _graine.noteInteraction();
    final live = _connected && _socket != null;
    _transcript.customer(t, _now(), pending: !live);
    if (live) {
      _send(ChatWire.text(t));
    } else {
      if (!_wanted) _graine._takeConversation();
      _wanted = true;
      _retryNow();
    }
    notifyListeners();
  }

  /// Answer a component the agent drew in the chat: the structured answer,
  /// then [summary] as the customer's turn — without it the conversation
  /// does not move.
  void answerWidget(String widgetId, Map<String, Object?> data, String summary) {
    _graine.clearPendingWidget();
    if (!_connected) return;
    _send(ChatWire.widgetResult(widgetId, data));
    if (summary.isNotEmpty) {
      _send(ChatWire.text(summary));
      _transcript.expectReply();
    }
    notifyListeners();
  }

  /// Forget the conversation on screen (a "new chat"). The socket, if open,
  /// stays: the agent keeps its own memory of this conversation.
  void clear() {
    _transcript.clear();
    notifyListeners();
  }

  /// START A NEW CONVERSATION — a fresh thread, as a support chat offers one.
  ///
  /// The chat hangs up, Graine lets go of the conversation it kept for this
  /// agent and user (so the next chat does not continue it), the chat on
  /// screen clears — messages still waiting too — and, when the user was in
  /// the chat, a fresh chat opens, with the welcome and the starters. What the
  /// agent remembers about the user (memories) is untouched. Nobody
  /// identified: nothing was kept, so only the screen clears. The chat
  /// window's header offers it while it shows an earlier conversation.
  ///
  /// Throws a [GraineException] when Graine refused (`deviceLimit`,
  /// `network`, …); the chat is then as it was, connected again.
  Future<void> newConversation() async {
    if (_disposed) return;
    final wanted = _wanted;
    // Hung up first: the conversation being let go of must not write another turn after it.
    if (wanted) {
      _generation++;
      _cancelRetry();
      _hangUp();
      notifyListeners();
    }
    try {
      await _graine._letGoOfConversation();
    } catch (_) {
      // Nothing was let go of: back to the conversation as it was.
      if (wanted && _wanted && !_disposed) {
        _ensureConnected();
        notifyListeners();
      }
      rethrow;
    }
    if (_disposed) return;
    _transcript.clear();
    if (wanted && _wanted) _ensureConnected();
    notifyListeners();
  }

  // ── the socket ───────────────────────────────────────────────────────────

  /// Connect now: an explicit open or a message beats the backoff.
  void _retryNow() {
    if (_failed) {
      _failed = false;
      _ladder.reset();
      _transcript.retryFailed();
    }
    _cancelRetry();
    _ensureConnected();
  }

  void _ensureConnected() {
    if (_disposed || !_wanted || _connected || _opening != null || _retry != null) return;
    if (!_graine._foreground) return; // back in the foreground, it connects
    final generation = _generation;
    _opening = _openSocket(generation).whenComplete(() {
      if (generation == _generation) _opening = null;
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> _openSocket(int generation) async {
    bool current() => generation == _generation && _wanted && !_disposed;
    try {
      final session = await _graine.loadSession();
      if (session == null) throw const GraineException('Could not load the agent.', code: GraineErrorCode.network);
      if (!current()) return;
      final variables = _graine.currentVariables();
      final identity = await _graine._identityState(waitForSession: false);
      final ticket = await _graine._ticket('text', variables, identity);
      if (!current()) return;
      var url = ticket?.wsUrl ?? ChatWire.directUrl(session.wsHost, session.webcallAgentId);
      url = ChatWire.withContextToken(url, Protocol.contextToken(variables, callType: ChatWire.callType));
      final protocols = ticket == null ? null : <String>[ChatWire.subprotocol, ticket.ticket];
      final socket =
          await _connector(Uri.parse(url), protocols).timeout(const Duration(milliseconds: ChatWire.openTimeoutMs));
      if (!current()) {
        unawaited(socket.close().catchError((Object _) {}));
        return;
      }
      _socket = socket;
      _subscription = socket.frames.listen(
        _onFrame,
        onDone: () => _onClosed(socket),
        onError: (Object _) => _onClosed(socket),
        cancelOnError: true,
      );
      _connected = true;
      _error = null;
      _failed = false;
      _ladder.reset();
      // A new conversation: the last one's unanswered component must not come back over it.
      if (_graine._componentsFromChat) _graine.components.reset();
      _send(ChatWire.init(variables));
      _ping = Timer.periodic(const Duration(milliseconds: ChatWire.pingMs), (_) => _send(ChatWire.ping));
      // A screen set before the socket opened — the usual case — is the whole
      // context for the agent's first words.
      final frame = _graine._currentContextFrame();
      if (frame != null) _send(ChatWire.appContext(frame));
      // What a history on this connection replaces: what is settled now, before the waiting turns go.
      _transcript.opened();
      for (final m in _transcript.pending) {
        _send(ChatWire.text(m.text));
        _transcript.sent(m.id);
      }
      _graine._conversationStateChanged();
      unawaited(refreshUpcoming());
    } catch (e) {
      if (generation != _generation || _disposed) return;
      _error = e is GraineException ? e.message : 'The chat could not connect: $e';
      if (_graine.config.debug) debugPrint('[Graine] chat: $_error');
      _scheduleReconnect();
    }
  }

  void _onFrame(Object? raw) {
    if (_graine.config.debug) {
      final s = raw is String ? raw : '';
      debugPrint('[Graine] ← chat ${s.length > 600 ? s.substring(0, 600) : s}');
    }
    final frame = ChatFrame.parse(raw);
    if (frame == null) return;
    switch (frame) {
      case ChatText(chunk: final chunk):
        if (chunk.startsTurn) _transcript.turnStarted();
        if (chunk.text.isNotEmpty) {
          final volunteered = _transcript.agent(chunk.text, _now());
          _graine.components._agentStarted();
          if (volunteered) _graine._report((GraineListener l) => l.onAgentVolunteered(chunk.text));
        }
        if (chunk.endsTurn) {
          _transcript.turnEnded();
          _maybeRefreshUpcoming();
        }
      case ChatStream(start: final start):
        if (start) {
          _transcript.turnStarted();
        } else {
          _transcript.turnEnded();
          _maybeRefreshUpcoming();
        }
      case ChatClear():
        _transcript.turnEnded();
      case ChatWidget(widget: final widget):
        _graine._widgetArrived(widget, fromChat: true);
        final component = GraineWidget.adopt(widget, _graine.config.baseUrl);
        if (component != null) _transcript.component(component, _now());
      case ChatWidgetPending(hint: final hint):
        _graine._widgetPending(hint, fromChat: true);
      case ChatAction(actionId: final actionId, name: final name, arguments: final args):
        _graine.executeAction(name, args).then((ActionResult r) => _send(ChatWire.actionResult(actionId, r)));
      case ChatHistory(turns: final turns):
        // The conversation continues: the earlier turns, before any agent message. Never announced as new ones.
        if (!_transcript.restore(turns)) return;
    }
    notifyListeners();
  }

  void _onClosed(GraineChatSocket socket) {
    if (!identical(socket, _socket)) return;
    _teardown();
    _transcript.closed();
    _graine._conversationStateChanged();
    if (_wanted) _scheduleReconnect();
    if (!_disposed) notifyListeners();
  }

  void _scheduleReconnect() {
    if (!_wanted || _retry != null || _disposed) return;
    final delay = _ladder.next();
    if (delay == null) {
      _failed = true;
      _error ??= 'The chat could not connect.';
      // What the user typed is kept, marked not sent; the next try sends it.
      _transcript.failPending();
      return;
    }
    _retry = Timer(Duration(milliseconds: delay), () {
      _retry = null;
      _ensureConnected();
      if (!_disposed) notifyListeners();
    });
  }

  void _cancelRetry() {
    _retry?.cancel();
    _retry = null;
  }

  /// Stop listening and forget the socket, without a word to it.
  void _teardown() {
    _ping?.cancel();
    _ping = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _socket = null;
    _connected = false;
  }

  /// A clean hang-up: `stop`, then the socket a moment later — closing at
  /// once races the frame, and usually wins.
  void _hangUp() {
    final socket = _socket;
    final wasConnected = _connected;
    _teardown();
    _transcript.closed();
    _opening = null;
    if (socket != null) {
      try {
        if (wasConnected) socket.send(jsonEncode(ChatWire.stop));
      } catch (_) {
        // Already gone.
      }
      Timer(const Duration(milliseconds: ChatWire.stopGraceMs), () {
        unawaited(socket.close().catchError((Object _) {}));
      });
    }
    _graine._conversationStateChanged();
  }

  void _send(Map<String, Object?> frame) {
    final socket = _socket;
    if (socket == null) return;
    if (_graine.config.debug) {
      final type = frame['type'];
      debugPrint('[Graine] → chat $type${type == 'text' ? '' : ' ${_redact(frame)}'}');
    }
    try {
      socket.send(jsonEncode(Protocol.toJson(frame)));
    } catch (e) {
      if (_graine.config.debug) debugPrint('[Graine] chat send failed: $e');
    }
  }

  /// A debug line names what was sent without dumping a customer's words.
  static String _redact(Map<String, Object?> frame) {
    if (frame['type'] == 'app_context') {
      final c = frame['context'];
      return 'screen=${c is Map ? c['screen'] : null}';
    }
    if (frame['type'] == 'init') return '';
    final s = jsonEncode(Protocol.toJson(frame));
    return s.length > 200 ? s.substring(0, 200) : s;
  }

  // ── what the rest of the SDK tells it ────────────────────────────────────

  void _reportEvent(String name, {String? detail, Map<String, Object?> data = const <String, Object?>{}}) {
    if (!_connected) return;
    // The screen goes first: the event is about it.
    final frame = _graine._currentContextFrame();
    if (frame != null) _send(ChatWire.appContext(frame));
    _send(ChatWire.appEvent(name, detail: detail, data: data));
  }

  /// Someone else is using the app now (a sign-out, another user): the open
  /// conversation is not theirs. It ends, the transcript goes, and — if the
  /// customer is still in the chat — a new conversation opens for whoever it is.
  void _newUser() {
    final wanted = _wanted;
    _generation++;
    _cancelRetry();
    _hangUp();
    _transcript.clear();
    // Their booked calls are not the next person's either.
    _upcoming = const <GraineScheduledCall>[];
    _cancels.clear();
    _upcomingAt = null;
    _ladder.reset();
    _failed = false;
    _wanted = wanted;
    _ensureConnected();
    notifyListeners();
  }

  /// Confirmed after two seconds, as the call is: a permission dialog or the
  /// app switcher backgrounds the app for a moment. A chat suspended in the
  /// background reconnects in the foreground — the customer is still in it.
  void _foregroundChanged(bool foreground) {
    _backgroundConfirm?.cancel();
    _backgroundConfirm = null;
    if (foreground) {
      _ensureConnected();
      if (_connected) unawaited(refreshUpcoming());
      return;
    }
    if (!_graine.config.endOnBackground || !(_connected || _opening != null)) return;
    _backgroundConfirm = Timer(const Duration(seconds: 2), () {
      _backgroundConfirm = null;
      if (_graine._foreground) return;
      _generation++;
      _cancelRetry();
      _hangUp();
      _ladder.reset();
      if (!_disposed) notifyListeners();
    });
  }

  DateTime _now() => DateTime.fromMillisecondsSinceEpoch(_graine._clock());

  void _dispose() {
    if (_disposed) return;
    close();
    _disposed = true;
    _backgroundConfirm?.cancel();
    for (final u in _unwatch) {
      u();
    }
  }
}

Future<GraineChatSocket> _ioConnect(Uri url, List<String>? protocols) async =>
    _IoChatSocket(await WebSocket.connect(url.toString(), protocols: protocols));

class _IoChatSocket implements GraineChatSocket {
  _IoChatSocket(this._ws);

  final WebSocket _ws;

  @override
  Stream<Object?> get frames => _ws;

  @override
  void send(String data) {
    if (_ws.readyState == WebSocket.open) _ws.add(data);
  }

  @override
  Future<void> close() => _ws.close(1000);
}
