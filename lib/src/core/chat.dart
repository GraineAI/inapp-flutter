/// THE TEXT CHAT — what goes on its socket, what comes off it, and how the
/// agent's streamed words become one message per turn.
///
/// The wire is the React Native SDK's text path, byte for byte: a `text`
/// ticket (`mode: "text"`) on the gateway's `graine.embed.v1` subprotocol, or
/// the direct `/chat/v1/{agent}?text_chat=1` with `context_token`; `init`, a
/// `ping` every 25 s, `stop` on the way out. What it fixes is the turn: the
/// runtime ends each reply with `<end_of_stream>`, and a reply ends THERE —
/// one bubble per agent turn, never two replies merged into one.
library;

import 'bar.dart';
import 'context.dart';
import 'js.dart';
import 'protocol.dart';
import 'widget_flow.dart';

/// The constants and outgoing frames of the chat socket.
abstract final class ChatWire {
  /// The gateway subprotocol; the ticket rides beside it, never in the URL.
  static const String subprotocol = 'graine.embed.v1';
  static const int pingMs = 25000;

  /// A socket that has not opened by then is given up on.
  static const int openTimeoutMs = 15000;

  /// How long `stop` is given to leave before the socket closes.
  static const int stopGraceMs = 200;

  /// Who this client is, in the init frame (the runtime logs it).
  static const String client = 'graine-flutter-sdk';
  static const String defaultWsHost = 'wss://ws.graine.ai';

  /// The `call_type` a text conversation is filed under.
  static const String callType = 'text_chat';

  /// Without a ticket (no gateway on this deployment): the runtime directly.
  static String directUrl(String? wsHost, String agentId) {
    var host = (wsHost == null || wsHost.trim().isEmpty) ? defaultWsHost : wsHost.trim();
    while (host.endsWith('/')) {
      host = host.substring(0, host.length - 1);
    }
    return '$host/chat/v1/${Uri.encodeComponent(agentId)}?text_chat=1';
  }

  /// [url] with the variables' `context_token`, when there is one.
  static String withContextToken(String url, String? token) {
    if (token == null || token.isEmpty) return url;
    return '$url${url.contains('?') ? '&' : '?'}context_token=${Uri.encodeComponent(token)}';
  }

  /// The first frame: a start, carrying the variables for the record.
  static Map<String, Object?> init(Map<String, String> variables) => <String, Object?>{
        'type': 'init',
        'event': 'start',
        'meta_data': <String, Object?>{'client': client, 'context_data': Map<String, Object?>.of(variables)},
      };

  static const Map<String, Object?> ping = <String, Object?>{'type': 'ping'};

  /// A clean hang-up, so the conversation is filed as ended, not abandoned.
  static const Map<String, Object?> stop = <String, Object?>{'type': 'stop', 'event': 'stop', 'data': 'client_hangup'};

  /// One customer turn.
  static Map<String, Object?> text(String data) => <String, Object?>{'type': 'text', 'data': data};

  /// The structured answer to a component. The summary goes as a [text] turn
  /// after it: without the sentence, the conversation does not move.
  static Map<String, Object?> widgetResult(String widgetId, Map<String, Object?> data) =>
      <String, Object?>{'type': 'widget_result', 'widget_id': widgetId, 'data': Protocol.toJson(data)};

  /// The answer to an `app_action`, always given.
  static Map<String, Object?> actionResult(String actionId, ActionResult r) => <String, Object?>{
        'type': 'app_action_result',
        'action_id': actionId,
        'status': r.status.wire,
        if (r.message.isNotEmpty) 'message': r.message,
        if (r.data.isNotEmpty) 'data': Protocol.toJson(r.data),
      };

  /// A context frame — `{context, availableActions?, seq}` as the SDK builds
  /// it — in the socket's own spelling (`available_actions`).
  static Map<String, Object?> appContext(Map<String, Object?> frame) => <String, Object?>{
        'type': 'app_context',
        'context': frame['context'],
        if (frame.containsKey('availableActions')) 'available_actions': frame['availableActions'],
        if (frame['seq'] != null) 'seq': frame['seq'],
      };

  /// Something the agent may want to speak up about (or, `quiet`, only know).
  static Map<String, Object?> appEvent(String name,
          {String? detail, Map<String, Object?> data = const <String, Object?>{}}) =>
      <String, Object?>{
        'type': 'app_event',
        'event': <String, Object?>{
          'name': name,
          if (detail != null) 'detail': detail,
          for (final e in data.entries)
            if (e.key != 'name' && e.key != 'detail') e.key: Protocol.toJson(e.value),
        },
      };
}

/// ONE `text` FRAME: the words to show, and what it says about the turn.
///
/// The runtime brackets an agent turn with `<beginning_of_stream>` and
/// `<end_of_stream>`, sent as ordinary text. They are boundaries, not words:
/// removed (in any case), with nothing else touched — chunks are joined into
/// a sentence and the spaces between them are load-bearing.
class AgentChunk {
  const AgentChunk(this.text, {this.startsTurn = false, this.endsTurn = false});

  static const String streamStart = '<beginning_of_stream>';
  static const String streamEnd = '<end_of_stream>';
  static final RegExp _start = RegExp(streamStart, caseSensitive: false);
  static final RegExp _end = RegExp(streamEnd, caseSensitive: false);

  /// What the customer should see. Often empty: a marker is a whole frame.
  final String text;
  final bool startsTurn;
  final bool endsTurn;

  static AgentChunk read(Object? raw) {
    final text = raw == null ? '' : Js.str(raw);
    if (text.isEmpty || !text.contains('<')) return AgentChunk(text);
    final lower = text.toLowerCase();
    final starts = lower.contains(streamStart);
    final ends = lower.contains(streamEnd);
    if (!starts && !ends) return AgentChunk(text);
    return AgentChunk(text.replaceAll(_start, '').replaceAll(_end, ''), startsTurn: starts, endsTurn: ends);
  }

  @override
  bool operator ==(Object other) =>
      other is AgentChunk && other.text == text && other.startsTurn == startsTurn && other.endsTurn == endsTurn;

  @override
  int get hashCode => Object.hash(text, startsTurn, endsTurn);
}

/// Everything the chat socket can say, typed. Anything else is ignored.
sealed class ChatFrame {
  const ChatFrame();

  /// One frame off the socket, or null for anything that is not ours.
  static ChatFrame? parse(Object? raw) {
    final Object? decoded;
    try {
      decoded = Protocol.decodeJson(raw);
    } catch (_) {
      return null;
    }
    final o = Js.asMap(decoded);
    if (o == null) return null;
    switch (o['type']) {
      case 'text':
        return ChatText(AgentChunk.read(o['data']));
      case 'widget':
        final w = Js.asMap(o['widget']);
        return w == null ? null : ChatWidget(w);
      case 'widget_pending':
        return ChatWidgetPending(Js.asMap(o['widget']) ?? <String, Object?>{});
      case 'app_action':
        final a = Js.asMap(o['action']);
        if (a == null) return null;
        return ChatAction(
          actionId: Js.strOrEmpty(a['action_id']),
          name: Js.strOrEmpty(a['name']),
          arguments: Js.asMap(a['arguments']) ?? <String, Object?>{},
        );
      case 'beginning_of_stream':
        return const ChatStream(start: true);
      case 'end_of_stream':
        return const ChatStream(start: false);
      case 'clear':
      case 'interruption':
        return const ChatClear();
      case 'history':
        // A history whose turns are not a list is not one: ignored, never an error.
        final turns = ChatHistoryReader.read(o);
        return turns == null ? null : ChatHistory(turns);
      default:
        return null; // pong, ack, and whatever a newer runtime adds
    }
  }
}

/// The earlier conversation, restored (contract §2.6): the turns, oldest first — possibly none.
final class ChatHistory extends ChatFrame {
  const ChatHistory(this.turns);
  final List<GraineChatTurn> turns;
}

/// THE CONVERSATION CONTINUES (contract §2.6, vectors sdk/contract/history.json).
///
/// An identified user who comes back finds the chat where they left it: a
/// chat that passes the memory gate opens with ONE frame, in place of the
/// welcome (the user types next) —
///
///     {"type":"history","turns":[{id, role: "user"|"assistant", text,
///       at: ISO-8601 UTC, channel: "chat"|"voice"}, …oldest first],"continued":true}
///
/// read here as the React Native SDK reads it (protocol.ts readHistoryFrame).
abstract final class ChatHistoryReader {
  static final RegExp _iso =
      RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false);

  /// The turns a history frame restores, oldest first, or null when its
  /// `turns` is not a list. A turn that cannot be read is skipped: not an
  /// object, a role other than user/assistant, text that is not a string or is
  /// blank, no ISO-8601 `at` string. A channel other than "voice" is the chat;
  /// a missing or repeated id becomes "h<index>".
  static List<GraineChatTurn>? read(Map<String, Object?> frame) {
    final list = frame['turns'];
    if (list is! List) return null;
    final out = <GraineChatTurn>[];
    final used = <String>{};
    for (var index = 0; index < list.length; index++) {
      final o = Js.asMap(list[index]);
      if (o == null) continue;
      final GraineChatRole role;
      switch (o['role']) {
        case 'user':
          role = GraineChatRole.user;
        case 'assistant':
          role = GraineChatRole.agent;
        default:
          continue;
      }
      final text = o['text'];
      if (text is! String || text.trim().isEmpty) continue;
      final rawAt = o['at'];
      final at = rawAt is String ? time(rawAt) : null;
      if (at == null) continue;
      final wire = o['id'];
      final id = wire is String && wire.isNotEmpty && !used.contains(wire) ? wire : 'h$index';
      used.add(id);
      out.add(GraineChatTurn(
        id: id,
        role: role,
        text: text,
        at: at,
        delivery: role == GraineChatRole.user ? GraineChatDelivery.sent : null,
        restored: true,
        channel: o['channel'] == 'voice' ? GraineChatChannel.voice : GraineChatChannel.chat,
      ));
    }
    return out;
  }

  /// ISO-8601 with a zone, fractions or not, as UTC — the server writes UTC
  /// with a Z. A time with no zone is not one.
  static DateTime? time(String raw) {
    var s = raw.trim();
    if (!_iso.hasMatch(s)) return null;
    // "+0530" is ISO too; DateTime.tryParse wants the colon.
    s = s.replaceFirstMapped(RegExp(r'([+-]\d{2})(\d{2})$'), (Match m) => '${m[1]}:${m[2]}');
    return DateTime.tryParse(s)?.toUtc();
  }
}

/// The agent's words (and turn markers).
final class ChatText extends ChatFrame {
  const ChatText(this.chunk);
  final AgentChunk chunk;
}

/// A component the agent drew.
final class ChatWidget extends ChatFrame {
  const ChatWidget(this.widget);
  final Map<String, Object?> widget;
}

/// A component on its way.
final class ChatWidgetPending extends ChatFrame {
  const ChatWidgetPending(this.hint);
  final Map<String, Object?> hint;
}

/// Something the agent asks the app to do; answered with [ChatWire.actionResult].
final class ChatAction extends ChatFrame {
  const ChatAction({required this.actionId, required this.name, required this.arguments});
  final String actionId;
  final String name;
  final Map<String, Object?> arguments;
}

/// An explicit start or end of the agent's turn.
final class ChatStream extends ChatFrame {
  const ChatStream({required this.start});
  final bool start;
}

/// The turn was cut off.
final class ChatClear extends ChatFrame {
  const ChatClear();
}

/// Who said a turn of the chat.
enum GraineChatRole { user, agent }

/// Where a user's turn is: typed and waiting to go out, on the wire, or not
/// sent (the chat could not connect; it goes when the chat does).
enum GraineChatDelivery { sending, sent, failed }

/// Where a turn was said: typed in the chat, or spoken on a call (only an
/// earlier conversation's turn is).
enum GraineChatChannel { chat, voice }

/// ONE TURN OF THE CHAT — WIRE.md's `GraineChatTurn`, the same in every SDK.
class GraineChatTurn {
  const GraineChatTurn({
    required this.id,
    required this.role,
    required this.text,
    required this.at,
    this.delivery,
    this.proactive = false,
    this.component,
    this.live = false,
    this.restored = false,
    this.channel = GraineChatChannel.chat,
  });

  /// This chat's id for the turn: `t1`, `t2`, … (a restored turn: Graine's)
  final String id;
  final GraineChatRole role;

  /// What was said. An agent's turn may be only a [component].
  final String text;

  /// When it was said (an agent turn: its first words).
  final DateTime at;

  /// A user's turn only: sending, sent or failed. Null on the agent's.
  final GraineChatDelivery? delivery;

  /// An agent's turn nobody asked for: its welcome, or something it noticed.
  final bool proactive;

  /// The component the agent drew with this turn, if any.
  final GraineComponent? component;

  /// An agent turn still arriving.
  final bool live;

  /// From an earlier conversation, restored when the chat opened (the user
  /// came back): delivered, with the time it was said, not said just now.
  final bool restored;

  /// Where it was said. A chat window draws a run of [GraineChatChannel.voice]
  /// turns as one "Voice call" row, never their words.
  final GraineChatChannel channel;

  /// The turn as a caption — what a [Caption]-drawing window shows.
  Caption get caption => Caption(role == GraineChatRole.agent ? Role.agent : Role.customer, text, live: live);

  GraineChatTurn copyWith({String? text, bool? live, GraineChatDelivery? delivery, GraineComponent? component}) =>
      GraineChatTurn(
        id: id,
        role: role,
        text: text ?? this.text,
        at: at,
        delivery: delivery ?? this.delivery,
        proactive: proactive,
        component: component ?? this.component,
        live: live ?? this.live,
        restored: restored,
        channel: channel,
      );

  @override
  bool operator ==(Object other) =>
      other is GraineChatTurn &&
      other.id == id &&
      other.role == role &&
      other.text == text &&
      other.at == at &&
      other.delivery == delivery &&
      other.proactive == proactive &&
      identical(other.component, component) &&
      other.live == live &&
      other.restored == restored &&
      other.channel == channel;

  @override
  int get hashCode => Object.hash(id, role, text, at, delivery, proactive, component, live, restored, channel);

  @override
  String toString() => 'GraineChatTurn($id ${role.name}, "$text"${live ? ', live' : ''}'
      '${delivery != null ? ', ${delivery!.name}' : ''}${proactive ? ', proactive' : ''}'
      '${restored ? ', restored' : ''}${channel == GraineChatChannel.voice ? ', voice' : ''})';
}

/// HOW A CHAT'S FRAMES BECOME ITS TURNS.
///
/// The agent's words stream into ONE live turn; the turn ends on its end
/// marker, an explicit end, an interruption, the user speaking, or the
/// socket closing — and the next words open a new turn. "Typing" is the time
/// the agent owes an answer: from the user's message (or the agent's start
/// marker) until its first words.
class ChatTranscript {
  ChatTranscript({this.max = 200});

  /// How many turns are kept; the oldest go first.
  final int max;

  final List<GraineChatTurn> _turns = <GraineChatTurn>[];
  int _seq = 0;
  bool _awaitingReply = false;
  bool _turnOpen = false;

  /// The ids that were settled when the connection last opened — what a
  /// history replaces. Null before any open.
  Set<String>? _settledAtOpen;

  List<GraineChatTurn> get turns => List<GraineChatTurn>.unmodifiable(_turns);

  /// The turns as captions, for a window that draws captions.
  List<Caption> get messages => <Caption>[for (final t in _turns) t.caption];

  /// The agent is composing an answer and has not said a word of it yet.
  bool get agentTyping => _awaitingReply || (_turnOpen && !_liveAgentHasWords);

  bool get _liveAgentHasWords {
    final last = _turns.isEmpty ? null : _turns.last;
    return last != null && last.role == GraineChatRole.agent && last.live && last.text.isNotEmpty;
  }

  /// User turns still to be sent (sending or failed), oldest first.
  List<GraineChatTurn> get pending => <GraineChatTurn>[
        for (final t in _turns)
          if (t.delivery == GraineChatDelivery.sending || t.delivery == GraineChatDelivery.failed) t,
      ];

  /// The user said [text]. Whatever the agent was saying is over. [pending]:
  /// not on the wire yet ([sent] marks it when it is).
  GraineChatTurn customer(String text, DateTime at, {bool pending = false}) {
    _settleLive();
    _turnOpen = false;
    final t = GraineChatTurn(
      id: 't${++_seq}',
      role: GraineChatRole.user,
      text: text,
      at: at,
      delivery: pending ? GraineChatDelivery.sending : GraineChatDelivery.sent,
    );
    _add(t);
    if (!pending) _awaitingReply = true;
    return t;
  }

  /// The queued turn [id] went out: the agent now owes it an answer.
  void sent(String id) {
    final i = _turns.indexWhere((GraineChatTurn t) => t.id == id);
    if (i < 0) return;
    _turns[i] = _turns[i].copyWith(delivery: GraineChatDelivery.sent);
    _awaitingReply = true;
  }

  /// The chat gave up connecting: every turn still to go is not sent (yet).
  void failPending() {
    for (var i = 0; i < _turns.length; i++) {
      if (_turns[i].delivery == GraineChatDelivery.sending) {
        _turns[i] = _turns[i].copyWith(delivery: GraineChatDelivery.failed);
      }
    }
  }

  /// Trying again: the turns that were not sent are on their way.
  void retryFailed() {
    for (var i = 0; i < _turns.length; i++) {
      if (_turns[i].delivery == GraineChatDelivery.failed) {
        _turns[i] = _turns[i].copyWith(delivery: GraineChatDelivery.sending);
      }
    }
  }

  /// The user answered a component (the answer's sentence went out as their
  /// turn): the agent owes a reply, and is no longer mid-turn.
  void expectReply() {
    _settleLive();
    _turnOpen = false;
    _awaitingReply = true;
  }

  /// The agent's start marker: its turn has begun, words to follow.
  void turnStarted() => _turnOpen = true;

  /// Words of the agent's turn. True when they open a turn nobody asked for
  /// — the agent volunteering, as opposed to answering.
  bool agent(String words, DateTime at) {
    if (words.isEmpty) return false;
    _awaitingReply = false;
    _turnOpen = true;
    final last = _turns.isEmpty ? null : _turns.last;
    if (last != null && last.role == GraineChatRole.agent && last.live) {
      _turns[_turns.length - 1] = last.copyWith(text: last.text + words);
      return false;
    }
    final proactive = last == null || last.role != GraineChatRole.user;
    _add(GraineChatTurn(id: 't${++_seq}', role: GraineChatRole.agent, text: words, at: at, live: true, proactive: proactive));
    return proactive;
  }

  /// A component the agent drew: it belongs to the agent's turn in progress
  /// (or the last turn, when that is the agent's); else it is a turn of its own.
  void component(GraineComponent c, DateTime at) {
    final last = _turns.isEmpty ? null : _turns.last;
    if (last != null && last.role == GraineChatRole.agent) {
      _turns[_turns.length - 1] = last.copyWith(component: c);
      return;
    }
    _add(GraineChatTurn(id: 't${++_seq}', role: GraineChatRole.agent, text: '', at: at, component: c));
  }

  /// The agent's turn is over — its end marker, an explicit end, or an interruption.
  void turnEnded() {
    _settleLive();
    _turnOpen = false;
    _awaitingReply = false;
  }

  /// The socket closed: nothing is arriving any more, and nothing is owed.
  void closed() => turnEnded();

  /// Forget everything (a different user, or a new conversation on purpose).
  void clear() {
    _turns.clear();
    _awaitingReply = false;
    _turnOpen = false;
    _settledAtOpen = null;
  }

  /// The connection opened, before what was waiting goes out: what is settled
  /// now is what the next history replaces. A turn still waiting goes out
  /// right after this, and stays.
  void opened() {
    _settledAtOpen = <String>{
      for (final t in _turns)
        if (!t.live && t.delivery != GraineChatDelivery.sending && t.delivery != GraineChatDelivery.failed) t.id,
    };
  }

  /// An earlier conversation, restored: its turns, then every turn the history
  /// cannot hold yet — still sending or failed, or said since the connection
  /// opened — in order. A reconnect's history holds what the last one did and
  /// what was said since, so it replaces both, and nothing shows twice. With
  /// no open yet, only the turns still to go are kept. False when there was
  /// nothing to restore.
  bool restore(List<GraineChatTurn> restored) {
    if (restored.isEmpty) return false;
    final settled = _settledAtOpen;
    final kept = <GraineChatTurn>[
      for (final t in _turns)
        if (!t.restored &&
            (settled != null
                ? !settled.contains(t.id)
                : t.delivery == GraineChatDelivery.sending || t.delivery == GraineChatDelivery.failed))
          t,
    ];
    _turns
      ..clear()
      ..addAll(restored)
      ..addAll(kept);
    while (_turns.length > max) {
      _turns.removeAt(0);
    }
    return true;
  }

  void _settleLive() {
    if (_turns.isEmpty) return;
    final last = _turns.last;
    if (last.live) _turns[_turns.length - 1] = last.copyWith(live: false);
  }

  void _add(GraineChatTurn t) {
    _turns.add(t);
    while (_turns.length > max) {
      _turns.removeAt(0);
    }
  }
}
