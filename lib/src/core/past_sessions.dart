/// PAST SESSIONS (0.14.3) — the signed-in user's earlier sessions with this
/// agent, newest first, a page at a time, and each one's transcript, for the
/// user themselves. Per user, per agent, and only from a device that is one
/// of theirs.
///
/// Read leniently, like every answer (sdk/contract/past-sessions.json, run by
/// every SDK): what cannot be read is skipped or falls back, never thrown.
library;

import 'chat.dart' show ChatHistoryReader;
import 'config.dart' show EmbedRefusal;
import 'js.dart';

/// How a past session was held.
enum GrainePastSessionChannel {
  /// Typed in the chat.
  chat,

  /// A voice conversation in the app or on the website.
  voice,

  /// A call — on the phone, or in the app.
  call,
}

/// Who called whom, for a call.
enum GrainePastSessionDirection {
  /// The user called.
  inbound,

  /// Graine called the user.
  outbound,
}

/// Who said a line of a past session.
enum GrainePastSessionRole {
  /// The user.
  customer,

  /// The agent.
  agent,
}

/// ONE OF THE USER'S EARLIER SESSIONS with this agent — a row of a "past
/// conversations" list. From `GraineChatSession.pastSessions`.
class GrainePastSession {
  const GrainePastSession({
    required this.id,
    required this.startedAt,
    this.endedAt,
    this.durationSeconds,
    this.channel = GrainePastSessionChannel.chat,
    this.direction,
    this.status = '',
    this.turns = 0,
    this.preview = '',
  });

  /// The session's id — the one your dashboard's Execution Logs show for it.
  /// Pass it to `GraineChatSession.sessionTranscript`.
  final String id;

  /// When it began, in UTC.
  final DateTime startedAt;

  /// When it ended, in UTC; null when Graine did not say.
  final DateTime? endedAt;

  /// How long it lasted, in seconds; null when Graine did not say.
  final num? durationSeconds;

  /// Typed, a voice conversation, or a call.
  final GrainePastSessionChannel channel;

  /// For a call, who called whom; null when it does not apply.
  final GrainePastSessionDirection? direction;

  /// How it ended, in plain words — "completed", "missed", "failed", … —
  /// as Graine said it; "" when it said none.
  final String status;

  /// How many turns it holds.
  final int turns;

  /// The user's first line, at most 120 characters; "" when there is none.
  final String preview;

  @override
  bool operator ==(Object other) =>
      other is GrainePastSession &&
      other.id == id &&
      other.startedAt == startedAt &&
      other.endedAt == endedAt &&
      other.durationSeconds == durationSeconds &&
      other.channel == channel &&
      other.direction == direction &&
      other.status == status &&
      other.turns == turns &&
      other.preview == preview;

  @override
  int get hashCode => Object.hash(id, startedAt, endedAt, durationSeconds, channel, direction, status, turns, preview);

  @override
  String toString() => 'GrainePastSession($id, ${channel.name}, $status)';
}

/// THE USER'S PAST SESSIONS AS THE SDK KEEPS THEM — `GraineChatSession.pastSessions`.
/// Empty until `refreshPastSessions()`; empty again when the identity changes.
class GrainePastSessions {
  const GrainePastSessions({
    this.sessions = const <GrainePastSession>[],
    this.loading = false,
    this.hasMore = false,
    this.error,
  });

  /// Nothing loaded: before `refreshPastSessions()`, and after the identity changed.
  static const GrainePastSessions empty = GrainePastSessions();

  /// Loaded so far, newest first.
  final List<GrainePastSession> sessions;

  /// A page is being read.
  final bool loading;

  /// There are older sessions: `loadMorePastSessions()` reads the next page.
  final bool hasMore;

  /// Why the last read failed, as Graine's code — `identity_required`,
  /// `device_limit`, `rate_limited`, `unavailable`, `network`, … — else null.
  final String? error;

  @override
  bool operator ==(Object other) =>
      other is GrainePastSessions &&
      other.loading == loading &&
      other.hasMore == hasMore &&
      other.error == error &&
      _sameList(other.sessions, sessions);

  @override
  int get hashCode => Object.hash(Object.hashAll(sessions), loading, hasMore, error);

  @override
  String toString() =>
      'GrainePastSessions(${sessions.length} sessions${loading ? ', loading' : ''}${hasMore ? ', more' : ''}'
      '${error == null ? '' : ', $error'})';
}

/// ONE LINE OF A PAST SESSION'S TRANSCRIPT.
class GrainePastSessionTurn {
  const GrainePastSessionTurn({required this.role, required this.text, required this.at});

  /// Who said it.
  final GrainePastSessionRole role;

  /// What was said.
  final String text;

  /// When, in UTC.
  final DateTime at;

  @override
  bool operator ==(Object other) =>
      other is GrainePastSessionTurn && other.role == role && other.text == text && other.at == at;

  @override
  int get hashCode => Object.hash(role, text, at);

  @override
  String toString() => 'GrainePastSessionTurn(${role.name}, "$text")';
}

/// ONE PAST SESSION'S FULL TRANSCRIPT — `GraineChatSession.sessionTranscript`.
class GrainePastSessionTranscript {
  const GrainePastSessionTranscript({
    required this.id,
    this.startedAt,
    this.endedAt,
    this.durationSeconds,
    this.channel = GrainePastSessionChannel.chat,
    this.direction,
    this.status = '',
    this.turns = const <GrainePastSessionTurn>[],
  });

  /// The session's id.
  final String id;

  /// When it began, in UTC; null when Graine did not say.
  final DateTime? startedAt;

  /// When it ended, in UTC; null when Graine did not say.
  final DateTime? endedAt;

  /// How long it lasted, in seconds; null when Graine did not say.
  final num? durationSeconds;

  /// Typed, a voice conversation, or a call.
  final GrainePastSessionChannel channel;

  /// For a call, who called whom; null when it does not apply.
  final GrainePastSessionDirection? direction;

  /// How it ended, in plain words; "" when Graine said none.
  final String status;

  /// What was said, oldest first.
  final List<GrainePastSessionTurn> turns;

  @override
  bool operator ==(Object other) =>
      other is GrainePastSessionTranscript &&
      other.id == id &&
      other.startedAt == startedAt &&
      other.endedAt == endedAt &&
      other.durationSeconds == durationSeconds &&
      other.channel == channel &&
      other.direction == direction &&
      other.status == status &&
      _sameList(other.turns, turns);

  @override
  int get hashCode => Object.hash(id, startedAt, endedAt, durationSeconds, channel, direction, status, Object.hashAll(turns));

  @override
  String toString() => 'GrainePastSessionTranscript($id, ${turns.length} turns)';
}

bool _sameList<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// One page of a `sessions/list` answer: the sessions it carries, and the
/// next page's cursor (null at the end).
typedef PastSessionsPage = ({List<GrainePastSession> sessions, String? next});

/// THE WIRE, READ — as every SDK reads it (the React Native SDK's
/// parsePastSessions, parsePastSessionTranscript and pastSessionsAfter).
/// Not exported: `GraineChatSession` keeps the state.
abstract final class PastSessionsWire {
  /// One session, or null: without an id or a readable `startedAt` it is
  /// skipped. An unreadable `endedAt` or `durationSeconds` is null, a channel
  /// other than voice/call is the chat, a direction other than
  /// inbound/outbound is null, `turns` that are not a whole number ≥ 0 are 0,
  /// and a `preview` that is not text is "".
  static GrainePastSession? session(Object? raw) {
    final r = Js.asMap(raw);
    if (r == null) return null;
    final id = r['id'];
    final startedAt = _time(r['startedAt']);
    if (id is! String || id.trim().isEmpty || startedAt == null) return null;
    final preview = r['preview'];
    return GrainePastSession(
      id: id,
      startedAt: startedAt,
      endedAt: _time(r['endedAt']),
      durationSeconds: _duration(r['durationSeconds']),
      channel: _channel(r['channel']),
      direction: _direction(r['direction']),
      status: _status(r['status']),
      turns: _count(r['turns']),
      preview: preview is String ? preview : '',
    );
  }

  /// A `sessions/list` answer: its sessions (what cannot be read skipped, an
  /// id twice kept once) and the next page's cursor — a non-empty string, else
  /// null.
  static PastSessionsPage page(Object? body) {
    final m = Js.asMap(body);
    final raw = m == null ? null : m['sessions'];
    final read = <GrainePastSession>[
      for (final x in raw is List ? raw : const <Object?>[])
        if (session(x) case final GrainePastSession s) s,
    ];
    final next = m == null ? null : m['next'];
    return (sessions: append(const <GrainePastSession>[], read), next: next is String && next.isNotEmpty ? next : null);
  }

  /// [kept], then each of [more] whose id is not already kept.
  static List<GrainePastSession> append(List<GrainePastSession> kept, Iterable<GrainePastSession> more) {
    final seen = <String>{for (final s in kept) s.id};
    return List<GrainePastSession>.unmodifiable(<GrainePastSession>[
      ...kept,
      for (final s in more)
        if (seen.add(s.id)) s,
    ]);
  }

  /// The state after [page] arrived: a refresh's replaces what was loaded, a
  /// load-more's ([more]) is appended — an id already kept is not added
  /// twice. More to read while the page names a next one.
  static GrainePastSessions after(GrainePastSessions state, PastSessionsPage page, {required bool more}) =>
      GrainePastSessions(
        sessions: append(more ? state.sessions : const <GrainePastSession>[], page.sessions),
        hasMore: page.next != null,
      );

  /// A `sessions/transcript` answer: the session's details and its turns,
  /// oldest first, in the SDK's words — user → customer, assistant → agent. A
  /// turn without one of those roles, text that is a string, or a readable
  /// `at` is skipped. [id] is the session asked for, when the answer names none.
  static GrainePastSessionTranscript transcript(Object? body, {String id = ''}) {
    final r = Js.asMap(body) ?? const <String, Object?>{};
    final raw = r['turns'];
    final turns = <GrainePastSessionTurn>[];
    for (final x in raw is List ? raw : const <Object?>[]) {
      final t = Js.asMap(x);
      if (t == null) continue;
      final role = switch (t['role']) {
        'user' => GrainePastSessionRole.customer,
        'assistant' => GrainePastSessionRole.agent,
        _ => null,
      };
      final text = t['text'];
      final at = _time(t['at']);
      if (role == null || text is! String || at == null) continue;
      turns.add(GrainePastSessionTurn(role: role, text: text, at: at));
    }
    final named = r['id'];
    return GrainePastSessionTranscript(
      id: named is String && named.trim().isNotEmpty ? named : id,
      startedAt: _time(r['startedAt']),
      endedAt: _time(r['endedAt']),
      durationSeconds: _duration(r['durationSeconds']),
      channel: _channel(r['channel']),
      direction: _direction(r['direction']),
      status: _status(r['status']),
      turns: List<GrainePastSessionTurn>.unmodifiable(turns),
    );
  }

  /// The state's error word for a refusal: Graine's own code — a newer one
  /// as it came — else what its status means.
  static String errorWord(EmbedRefusal refusal) => refusal.codeName ?? refusal.code.wire;

  /// ISO-8601 with a zone, as UTC — the history reader's rule; null otherwise.
  static DateTime? _time(Object? v) => v is String ? ChatHistoryReader.time(v) : null;

  static num? _duration(Object? v) => v is num && v.isFinite && v >= 0 ? v : null;

  static int _count(Object? v) {
    if (v is int) return v >= 0 ? v : 0;
    if (v is double && v.isFinite && v >= 0 && v == v.truncateToDouble()) return v.toInt();
    return 0;
  }

  static GrainePastSessionChannel _channel(Object? v) => switch (v) {
        'voice' => GrainePastSessionChannel.voice,
        'call' => GrainePastSessionChannel.call,
        _ => GrainePastSessionChannel.chat,
      };

  static GrainePastSessionDirection? _direction(Object? v) => switch (v) {
        'inbound' => GrainePastSessionDirection.inbound,
        'outbound' => GrainePastSessionDirection.outbound,
        _ => null,
      };

  static String _status(Object? v) => v is String ? v : '';
}
