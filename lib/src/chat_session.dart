part of 'graine.dart';

/// A CHAT THAT IS OPENED AND CLOSED with the customer — beside
/// [GraineChatState], as [GraineCallFault] is beside the call state, so a
/// host's own chat keeps compiling. [GraineChatSession] implements it; the
/// bar opens a chat that does when the customer is in the chat, and closes it
/// when they leave (the SDK's own [GraineConfig.chatCloseDelaySeconds] after
/// no window shows it).
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

/// A CHAT SOCKET THAT SAYS HOW IT CLOSED — beside [GraineChatSocket], so a
/// socket written before it keeps compiling. The real one does; a test's
/// fake may. Not exported.
abstract interface class ChatSocketCloseCode {
  /// The code the server closed with, once [GraineChatSocket.frames] is done;
  /// null before that, or when it gave none.
  int? get closeCode;
}

/// Opens a [GraineChatSocket] to [url], offering [protocols].
typedef GraineChatConnector = Future<GraineChatSocket> Function(Uri url, List<String>? protocols);

/// WHAT THE SDK'S OWN CHAT WINDOWS ASK OF A CHAT — [GraineAgentBar] and
/// [GraineChat] — beyond what a host's own chat offers: when one comes on
/// screen and when it leaves, where the new-conversation markers go, and
/// whether Graine ended the conversation. Not exported: a chat screen of the
/// app's own reaches the same through [GraineChatSession.shown],
/// [GraineChatSession.newConversationBefore] and [GraineChatSession.status].
abstract final class ChatWindows {
  /// A window came on screen with [chat]: the customer is in it.
  static void shown(GraineChatConnection chat) {
    if (chat is GraineChatSession) {
      chat._windowShown();
    } else {
      chat.open();
    }
  }

  /// A window with [chat] left the screen. The SDK's own chat is kept for
  /// [GraineConfig.chatCloseDelaySeconds] more once no window shows it
  /// (0.14.3; it was 5 idle minutes in 0.14.0–0.14.1); a host's own closes,
  /// as it always did.
  static void left(GraineChatConnection chat) {
    if (chat is GraineChatSession) {
      chat._windowLeft();
    } else {
      chat.close();
    }
  }

  /// The ids of [chat]'s turns a "Disconnected · new conversation" row is drawn before.
  static Set<String> marks(GraineChatSession chat) => ChatMarks.of(chat._transcript);

  /// Graine ended [chat]'s conversation itself — idle, or at the session's
  /// time limit — and nothing is connecting: the header says "Disconnected".
  static bool disconnected(GraineChatSession chat) => chat._disconnected;
}

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
/// How long it lasts (0.14.3): once no window shows the chat, the
/// conversation stays connected for [GraineConfig.chatCloseDelaySeconds] (15
/// by default; a message either way meanwhile starts the wait again), so
/// opening the chat again within it goes on with it; then it closes, and the
/// next open connects again — an identified user's conversation continuing
/// from Graine's history, with no new welcome. (0.14.0–0.14.1 kept it for 5
/// idle minutes.) [close] ends it at once, and the app going to the
/// background (`endOnBackground`) ends it as before. When Graine ends it
/// itself — idle, or at the session's time limit — nothing reconnects until
/// the customer opens the chat or sends something; the window says
/// "Disconnected".
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

  /// A drop's retries are under way: set when one is scheduled, cleared when
  /// the chat connects, gives up or is hung up.
  bool _remaking = false;
  String? _error;
  GraineException? _refusal;
  Timer? _ping;
  Timer? _retry;
  Timer? _backgroundConfirm;

  /// The SDK's chat windows showing this chat now ([ChatWindows]).
  int _windows = 0;

  /// When a message last went either way, or the chat last connected.
  int? _lastActivity;

  /// Set while no window shows the chat: closes it
  /// [GraineConfig.chatCloseDelaySeconds] after it left the last one, or
  /// after the last message either way since.
  Timer? _idleClose;

  /// When the last window stopped showing the chat; null while one shows it.
  int? _leftAt;

  /// Graine ended the conversation itself: nothing reconnects until the
  /// customer opens the chat or sends something.
  bool _endedByGraine = false;

  /// The embed gateway's close codes for a conversation it ended: idle
  /// (`idle_timeout`) and the session's time limit.
  static const Set<int> _endedCodes = <int>{4408, 4410};

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

  /// THE CHAT'S CURRENT SESSION — this connection's run, the id Execution
  /// Logs shows for it — from the server's `session` frame (sdk/contract/
  /// history.json `sessionFrame`). Null until it arrives, with a server that
  /// sends none, once the connection closes, and after the identity changed.
  /// Each turn carries the [GraineChatTurn.session] it was said in.
  String? get sessionId => _transcript.sessionId;

  /// THE SESSIONS THE THREAD HOLDS, oldest first (history.json `sessions`):
  /// consecutive turns with the same session make one; turns kept before
  /// sessions were recorded make one with no id — for a "past conversations"
  /// list or session dividers of your own.
  List<GraineChatSessionInfo> get sessions => ChatSessions.of(_transcript.turns, _transcript.sessionId);

  /// The socket is open: the window says "Online".
  @override
  bool get connected => _connected;

  @override
  bool get connecting => _opening != null || (_wanted && !_connected && _retry != null);

  @override
  bool get agentTyping => _connected && _transcript.agentTyping;

  /// The chat dropped — or a try to open it failed — while the user is in
  /// it, and it is being made again: from then until it connects, gives up
  /// ([failed]) or is closed. [connecting] is true too. Say "Reconnecting…",
  /// not "Offline", while it is.
  bool get reconnecting => _remaking && connecting;

  /// Every reconnect was spent: the chat stays offline until the customer
  /// sends something, or [open] is called again.
  bool get failed => _failed;

  /// Why the last connect failed, for a log; null once connected.
  String? get error => _error;

  /// WHY GRAINE REFUSED THE CHAT, when it refused it for the server token or
  /// the publishable key — [GraineErrorCode.tokenRequired], `tokenInvalid`,
  /// `tokenExpired` (the SDK already asked [GraineConfig.tokenProvider] again
  /// and tried once more), `tokenScope` or `keyRevoked`, with
  /// [GraineException.reason] saying which part failed; null otherwise. Such a
  /// refusal is final for that try: [failed] is true, nothing reconnects by
  /// itself, and what the customer typed waits, marked not sent — [open],
  /// [send] or [retry] tries again. [GraineListener.onError] hears its
  /// sentence too. New in 0.14.4.
  GraineException? get refusal => _refusal;

  /// The customer is in the chat ([open] was called and [close] was not).
  bool get isOpen => _wanted;

  // ── public state for a chat of your own (contract/PUBLIC-STATE.md) ──────

  /// WHERE THE CHAT IS, in one word — what the SDK's own windows draw their
  /// header and banner from. First match wins: connected; reconnecting (a
  /// drop, retrying); connecting; disconnected (Graine ended the
  /// conversation — idle, or its time limit — and it waits for the
  /// customer); failed (every reconnect spent); offline (in the chat, a
  /// message waiting, nothing connecting it); else idle.
  GraineChatStatus get status {
    if (_connected) return GraineChatStatus.connected;
    if (reconnecting) return GraineChatStatus.reconnecting;
    if (connecting) return GraineChatStatus.connecting;
    if (_disconnected) return GraineChatStatus.disconnected;
    if (_failed) return GraineChatStatus.failed;
    if (_wanted && _transcript.pending.isNotEmpty) return GraineChatStatus.offline;
    return GraineChatStatus.idle;
  }

  /// THE TURNS A "Disconnected · new conversation" ROW GOES BEFORE, by id
  /// (contract/DESIGN.md "A new conversation under earlier lines";
  /// sdk/contract/history.json → `fresh`): where the chat connected again and
  /// Graine began a new conversation under the earlier lines. Empty when there
  /// are none. The window's own rows, never turns — [turns] is as it always
  /// was; [ChatRows.build] lays them out (`ChatNewConversationRow`).
  Set<String> get newConversationBefore => ChatMarks.of(_transcript);

  /// A CHAT SCREEN OF YOUR OWN CAME ON SCREEN (`true`) OR LEFT IT (`false`),
  /// so the conversation lives as the SDK's own windows' does
  /// (contract/DESIGN.md "How long a conversation lasts"). Shown, the chat
  /// opens ([open]): a conversation kept since a screen left goes on as it
  /// was, with no new welcome. Gone from every screen, it stays connected for
  /// [GraineConfig.chatCloseDelaySeconds] (15 s by default; a message either
  /// way meanwhile starts the wait again) and then closes (0.14.3; it was 5
  /// idle minutes in 0.14.0–0.14.1). Each `true` is paired with one `false`.
  /// A chat nobody reports stays connected until Graine's own idle limit;
  /// [close] ends it at once.
  void shown(bool visible) {
    if (_disposed) return;
    if (visible) {
      _windowShown();
    } else {
      _windowLeft();
    }
  }

  // ── chat window v2 (contract/DESIGN.md "Chat window v2" → SDK API) ───────

  /// THE REPLIES THE AGENT SUGGESTS for its latest turn, for an app that
  /// draws its own chat (the SDK's chat window draws them as chips). Gone
  /// once the user sends anything, the agent starts another turn, an earlier
  /// conversation is restored, or the conversation ends.
  List<GraineQuickReply> get quickReplies => _transcript.quickReplies;

  /// Send [reply] as the user's own message — a real turn, exactly as if
  /// they had typed its words.
  void sendQuickReply(GraineQuickReply reply) => send(reply.text);

  /// The agent ended the conversation. The chat window asks for a rating
  /// where the design does; a message from the user starts over.
  bool get ended => _transcript.ended;

  /// The user's answer to "How was this chat?", once given — one per conversation.
  GraineChatRating? get rating => _transcript.rating;

  /// Called with the user's rating the moment they give it — from the chat
  /// window's rating card, or [rate].
  void Function(GraineChatRating rating)? onRated;

  /// RATE THE CONVERSATION, for an app that draws its own rating: thumbs 1
  /// (up) or 0 (down), stars and emoji 1–5. Taken only after the agent ended
  /// the conversation, once; recorded on the conversation as a quiet event
  /// (it never makes the agent speak) while the chat is connected, and
  /// announced through [onRated] either way. Null when it was not taken.
  GraineChatRating? rate(GraineChatRatingStyle style, num value) {
    if (_disposed) return null;
    final rating = ChatRatings.of(style, value);
    if (!_transcript.rated(rating)) return null;
    if (_connected) _send(ChatRatings.frame(rating));
    notifyListeners();
    onRated?.call(rating);
    return rating;
  }

  GraineChatPin? _pin;

  /// What the app pinned ([pin]), as it is drawn; null when nothing is.
  GraineChatPin? get pinned => _pin;

  /// PIN WHAT THE CONVERSATION IS ABOUT — an item, a booking, a case — as a
  /// bar under the chat window's header or a card atop its thread, as the
  /// design says (nowhere when it says none). `pin(null)` takes it away. Never
  /// sent to the agent: tell it about the screen with the screen context.
  void pin(GraineChatPin? pin) {
    final next = pin?.cleaned;
    if (next == _pin) return;
    _pin = next;
    if (!_disposed) notifyListeners();
  }

  VoidCallback? _onAttach;

  /// The paperclip's tap. The chat window draws the paperclip only where
  /// the design asks for one AND this is set; the SDK sends nothing itself —
  /// pick and send the file your own way.
  VoidCallback? get onAttach => _onAttach;
  set onAttach(VoidCallback? handler) {
    if (identical(handler, _onAttach)) return;
    _onAttach = handler;
    if (!_disposed) notifyListeners();
  }

  /// A link the user tapped in one of the agent's messages (http, https,
  /// mailto or tel). The SDK opens nothing itself: hand it to your own
  /// launcher here. Unset, a tap does nothing.
  void Function(Uri uri)? onOpenLink;

  /// TRY AGAIN NOW to send what is waiting or could not be sent — what the
  /// chat window's "Not sent · Tap to retry" does: the chat connects at once,
  /// its reconnects start over, and every message still to go goes out.
  void retry() {
    if (_disposed) return;
    if (!_wanted) _graine._takeConversation();
    _wanted = true;
    _retryNow();
    notifyListeners();
  }

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

  // ── past sessions (0.14.3; contract/PUBLIC-STATE.md "Past sessions") ─────

  final ValueNotifier<GrainePastSessions> _past = ValueNotifier<GrainePastSessions>(GrainePastSessions.empty);

  /// Where the next page starts; null before the first and after the last.
  String? _pastCursor;

  /// Bumped by every refresh and identity change: an answer from before is nobody's.
  int _pastGeneration = 0;

  /// THE USER'S PAST SESSIONS WITH THIS AGENT, newest first — chats, voice
  /// conversations and calls, for the signed-in user themselves, read only
  /// from a device that is one of theirs: for a "past conversations" screen
  /// of your own. The conversation open now is never among them. Empty until [refreshPastSessions];
  /// `loading` while a page is read, `hasMore` while there are older ones
  /// ([loadMorePastSessions]), and `error` — Graine's code — when the last
  /// read failed. Emptied when the identity changes.
  ValueListenable<GrainePastSessions> get pastSessions => _past;

  /// Read the first page of the user's past sessions again: it replaces what
  /// was loaded (kept on screen while it is read). Never throws — a failure
  /// is the state's `error`: `identity_required` with nobody identified
  /// (nothing is asked), `device_limit` from a device that is not theirs,
  /// `rate_limited`, `unavailable`, `network`. A refresh supersedes any read
  /// still on its way.
  Future<void> refreshPastSessions() => _readPastSessions(more: false);

  /// Read the next page and add it after the sessions loaded — an id already
  /// there is not added twice. Nothing happens while a page is being read or
  /// when there is no next page ([GrainePastSessions.hasMore]). Never throws;
  /// after a failure `hasMore` stays true, so it can be asked again.
  Future<void> loadMorePastSessions() {
    final now = _past.value;
    if (_disposed || now.loading || !now.hasMore || _pastCursor == null) return Future<void>.value();
    return _readPastSessions(more: true);
  }

  /// ONE PAST SESSION'S FULL TRANSCRIPT — [id] from [pastSessions] — oldest
  /// first. Throws a [GraineException]: `invalidRequest` for an empty id and
  /// `identityRequired` with nobody identified (neither asks Graine),
  /// `notFound` for a session that is not the user's, `deviceLimit` from a
  /// device that is not theirs, `network` when Graine cannot be reached.
  Future<GrainePastSessionTranscript> sessionTranscript(String id) async {
    final wanted = id.trim();
    if (wanted.isEmpty) {
      throw const GraineException("Pass the id of one of the user's past sessions.", code: GraineErrorCode.invalidRequest);
    }
    return PastSessionsWire.transcript(await _graine._sessionTranscript(wanted), id: wanted);
  }

  Future<void> _readPastSessions({required bool more}) async {
    if (_disposed) return;
    final generation = ++_pastGeneration;
    final cursor = more ? _pastCursor : null;
    final before = _past.value;
    _setPast(GrainePastSessions(sessions: before.sessions, loading: true, hasMore: before.hasMore));
    String? error;
    try {
      final page = PastSessionsWire.page(await _graine._pastSessionsPage(cursor));
      if (_disposed || generation != _pastGeneration) return;
      _pastCursor = page.next;
      _setPast(PastSessionsWire.after(_past.value, page, more: more));
      return;
    } on GraineException catch (e) {
      error = e.codeName ?? e.code.wire;
    } catch (e) {
      error = GraineErrorCode.network.wire;
      if (_graine.config.debug) debugPrint('[Graine] chat: could not read the past sessions: $e');
    }
    if (_disposed || generation != _pastGeneration) return;
    // What was loaded stays (nobody identified, nothing was: an identity change empties it), and can be asked again.
    final now = _past.value;
    _setPast(GrainePastSessions(sessions: now.sessions, hasMore: now.hasMore, error: error));
  }

  void _setPast(GrainePastSessions next) {
    if (_disposed || next == _past.value) return;
    _past.value = next;
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
    _cancelIdleClose();
    _backgroundConfirm?.cancel();
    _backgroundConfirm = null;
    _hangUp();
    _ladder.reset();
    _failed = false;
    _refusal = null;
    _remaking = false;
    _endedByGraine = false;
    notifyListeners();
  }

  /// A chat window came on screen: the customer is in the chat. A
  /// conversation kept since a window left goes on as it was — the same
  /// connection, nothing on screen changing.
  void _windowShown() {
    _windows++;
    _leftAt = null;
    _cancelIdleClose();
    open();
  }

  /// A chat window left the screen. When no window shows the chat any more
  /// the conversation is kept for [GraineConfig.chatCloseDelaySeconds], and
  /// then closes: opening the chat within it goes on with it.
  void _windowLeft() {
    if (_windows > 0) _windows--;
    if (_windows == 0) {
      _leftAt = _graine._clock();
      _scheduleIdleClose();
    }
  }

  /// The close of a chat no window shows: [GraineConfig.chatCloseDelaySeconds]
  /// after it left the last window, or after the last message either way when
  /// that came later — at once for 0.
  void _scheduleIdleClose() {
    _cancelIdleClose();
    if (!_wanted || _windows > 0 || _disposed) return;
    final now = _graine._clock();
    final left = _leftAt ?? now;
    final last = _lastActivity ?? now;
    final due = (left > last ? left : last) + ChatCloseDelay.ms(_graine.config.chatCloseDelaySeconds) - now;
    // 0: at once, as the last window goes.
    if (due <= 0) {
      close();
      return;
    }
    _idleClose = Timer(Duration(milliseconds: due), () {
      _idleClose = null;
      close();
    });
  }

  void _cancelIdleClose() {
    _idleClose?.cancel();
    _idleClose = null;
  }

  /// This agent's call is starting: a conversation kept only until it goes
  /// idle, with no window showing it, ends — one conversation with an agent
  /// at a time.
  void _callStarting() {
    if (_idleClose != null) close();
  }

  /// A message went either way: the conversation is not idle. While no
  /// window shows the chat, its wait to close starts again.
  void _activity() {
    _lastActivity = _graine._clock();
    if (_idleClose != null) _scheduleIdleClose();
  }

  bool get _disconnected => _endedByGraine && !_connected && _opening == null;

  /// The customer typed [text] and sent it. Shown at once; sent now when
  /// connected, else kept and sent the moment the chat connects (and the
  /// chat connects for it).
  @override
  void send(String text) {
    if (_disposed) return;
    final t = text.trim();
    if (t.isEmpty) return;
    _graine.noteInteraction();
    _activity();
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
    _activity();
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
      _remaking = false;
      // Asked for on purpose: whatever Graine had ended, the chat connects again.
      _endedByGraine = false;
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

  /// Connect now: an explicit open or a message beats the backoff — and
  /// connects again a conversation Graine ended.
  void _retryNow() {
    if (_failed) {
      _failed = false;
      _refusal = null;
      _ladder.reset();
      _transcript.retryFailed();
    }
    _endedByGraine = false;
    _cancelRetry();
    _ensureConnected();
  }

  void _ensureConnected() {
    if (_disposed || !_wanted || _connected || _opening != null || _retry != null) return;
    // Graine ended the conversation: only the customer's next open or message connects again.
    if (_endedByGraine) return;
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
      // No session: its own refusal is why ([error]) — a key Graine rejected, an outage — not a generic one.
      final session = await _graine._sessionOrThrow();
      if (!current()) return;
      final variables = _graine.currentVariables();
      final identity = await _graine._identityState(waitForSession: false);
      final ticket = await _graine._ticket('text', variables, identity);
      if (!current()) return;
      // The direct socket reads the variables off its URL. The gateway builds the conversation's context
      // from the ticket's signed claims and reads nothing else, so a token there would only reach the access logs.
      final url = ticket?.wsUrl ??
          ChatWire.withContextToken(ChatWire.directUrl(session.wsHost, session.webcallAgentId),
              Protocol.contextToken(variables, callType: ChatWire.callType));
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
      _refusal = null;
      _remaking = false;
      _ladder.reset();
      // A connection is where the idle time of a conversation starts.
      _activity();
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
      // Refused for the server token or the publishable key — its ticket, or the agent's settings: final for this
      // try. The direct socket would only be another way past that answer, and a reconnect would meet it again.
      if (e is GraineException && ClientTokenRules.refusals.contains(e.code.wire)) {
        _refused(e);
        return;
      }
      _error = e is GraineException ? e.message : 'The chat could not connect: $e';
      if (_graine.config.debug) debugPrint('[Graine] chat: $_error');
      if (e is GraineException && e.code == GraineErrorCode.appNotAllowed) {
        // Not one of the agent's apps: asking again cannot change that (APP-IDENTITY.md §2.3).
        _cancelRetry();
        _failed = true;
        _remaking = false;
        _transcript.failPending();
        return;
      }
      _scheduleReconnect();
    }
  }

  /// GRAINE REFUSED THE CONVERSATION for the server token or the publishable
  /// key (CLIENT-TOKENS.md §2.5): the chat fails with that refusal —
  /// [refusal] — and nothing reconnects by itself. What was waiting to go is
  /// marked not sent; the customer's next open or message tries again.
  void _refused(GraineException e) {
    _cancelRetry();
    _refusal = e;
    _error = e.message;
    _failed = true;
    _remaking = false;
    _transcript.failPending();
    if (_graine.config.debug) {
      debugPrint('[Graine] chat: refused (${e.code.wire}${e.reason == null ? '' : ', ${e.reason}'})');
    }
    _graine._report((GraineListener l) => l.onError(e.message));
  }

  void _onFrame(Object? raw) {
    if (_graine.config.debug) {
      final s = raw is String ? raw : '';
      debugPrint('[Graine] ← chat ${s.length > 600 ? s.substring(0, 600) : s}');
    }
    final frame = ChatFrame.parse(raw);
    if (frame == null) return;
    _activity();
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
      case ChatQuickReplies(replies: final replies):
        _transcript.offerReplies(replies);
      case ChatConversationEnd():
        _transcript.conversationEnded();
      case ChatSessionStart(id: final id):
        _transcript.sessionStarted(id);
    }
    notifyListeners();
  }

  void _onClosed(GraineChatSocket socket) {
    if (!identical(socket, _socket)) return;
    final code = switch (socket) { ChatSocketCloseCode(:final closeCode) => closeCode, _ => null };
    _teardown();
    _transcript.closed();
    _graine._conversationStateChanged();
    // Graine ended the conversation itself — idle, or at the session's time
    // limit: the lines stay, the header says "Disconnected", and the
    // customer's next open or message connects again.
    if (_endedCodes.contains(code)) _endedByGraine = true;
    // After the agent ended the conversation the server closes the socket
    // itself: reconnecting would open a new conversation under the old one's
    // goodbye. The next message the user sends connects again. Any other
    // close is a drop, and reconnects.
    if (_wanted && !_transcript.ended && !_endedByGraine) _scheduleReconnect();
    if (!_disposed) notifyListeners();
  }

  void _scheduleReconnect() {
    if (!_wanted || _retry != null || _disposed) return;
    final delay = _ladder.next();
    if (delay == null) {
      _failed = true;
      _remaking = false;
      _error ??= 'The chat could not connect.';
      // What the user typed is kept, marked not sent; the next try sends it.
      _transcript.failPending();
      return;
    }
    _remaking = true;
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

  /// WHO A CHAT BELONGS TO (contract/DESIGN.md): the identity changed —
  /// nobody to a user (the app identified after the chat opened), a user to
  /// another, or a user to nobody. A connection is whoever was identified when
  /// its ticket was made, so:
  ///  1. the one connected, connecting or coming back after a drop closes
  ///     normally — no "Disconnected", no reconnect banner — and one still
  ///     being made is nobody's when it lands;
  ///  2. the turns it carried go, with their history and marker rows, the
  ///     booked calls shown for the identity before (read again for the new
  ///     one as the chat connects) and the past sessions loaded for them
  ///     ([pastSessions] is empty until the next refresh);
  ///  3. a line typed that has not gone out — still sending, or failed —
  ///     stays, and goes on the next connection;
  ///  4. a chat that was connected or connecting connects again at once, with
  ///     a ticket for the new identity, when it is wanted; otherwise — and for
  ///     a chat neither connected nor connecting, whose "Disconnected" goes
  ///     too — the next open or message connects.
  /// Called only when the identity's value changed: other traits, or the
  /// memory choice, change nothing on an open chat.
  void _identityChanged() {
    if (_disposed) return;
    final live = _connected || _opening != null || _retry != null;
    _generation++;
    _cancelRetry();
    _hangUp();
    _transcript.forgetAllButUnsent();
    // Their booked calls are not the next identity's.
    _upcoming = const <GraineScheduledCall>[];
    _cancels.clear();
    _upcomingAt = null;
    // Nor their past sessions — and a read still on its way lands nobody's.
    _pastGeneration++;
    _pastCursor = null;
    _setPast(GrainePastSessions.empty);
    _endedByGraine = false;
    _remaking = false;
    _ladder.reset();
    if (live && _wanted) {
      _failed = false;
      _refusal = null;
      _transcript.retryFailed();
      _ensureConnected();
    }
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
      // Kept only until it went idle, with no window showing it: the background ends it, as close() does.
      if (_idleClose != null) {
        close();
        return;
      }
      _generation++;
      _cancelRetry();
      _hangUp();
      _ladder.reset();
      _remaking = false;
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

class _IoChatSocket implements GraineChatSocket, ChatSocketCloseCode {
  _IoChatSocket(this._ws);

  final WebSocket _ws;

  @override
  Stream<Object?> get frames => _ws;

  @override
  int? get closeCode => _ws.closeCode;

  @override
  void send(String data) {
    if (_ws.readyState == WebSocket.open) _ws.add(data);
  }

  @override
  Future<void> close() => _ws.close(1000);
}
