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

import 'dart:math' as math;

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
      case 'quick_replies':
        // Replies whose list is not a list are not replies: ignored. [] takes them away.
        final replies = QuickReplies.read(o);
        return replies == null ? null : ChatQuickReplies(replies);
      case 'conversation_end':
        return const ChatConversationEnd();
      default:
        return null; // pong, ack, and whatever a newer runtime adds
    }
  }
}

/// The replies the agent suggests for the turn it just sent (contract/DESIGN.md
/// "Chat window v2" → Wire), cleaned. An empty list takes them away.
final class ChatQuickReplies extends ChatFrame {
  const ChatQuickReplies(this.replies);
  final List<GraineQuickReply> replies;
}

/// The agent ended the conversation: the window may ask how it went.
final class ChatConversationEnd extends ChatFrame {
  const ChatConversationEnd();
}

/// ONE REPLY THE AGENT SUGGESTS: the words on the chip, and what a tap
/// sends as the user's own message — a real turn, exactly as if typed.
class GraineQuickReply {
  const GraineQuickReply({required this.label, required this.text});

  /// One line, at most 40 characters.
  final String label;

  /// At most 200 characters; the label when the agent gave none.
  final String text;

  Map<String, Object?> toJson() => <String, Object?>{'label': label, 'text': text};

  @override
  bool operator ==(Object other) => other is GraineQuickReply && other.label == label && other.text == text;

  @override
  int get hashCode => Object.hash(label, text);

  @override
  String toString() => 'GraineQuickReply("$label"${text == label ? '' : ' → "$text"'})';
}

/// HOW A `quick_replies` FRAME IS READ — the React Native SDK's
/// readQuickReplies (protocol.ts), pinned by sdk/contract/chat-window.json →
/// `quickReplies`: a reply is a string or `{label, text}`; a label is one line
/// of at most 40 characters, a text at most 200; blanks and repeats (the same
/// label, ignoring case) are left out; at most six.
abstract final class QuickReplies {
  static const int max = 6;
  static const int labelMax = 40;
  static const int textMax = 200;

  static final RegExp _controls = RegExp(r'[\u0000-\u001F\u007F-\u009F\u2028\u2029\u202A-\u202E\u2066-\u2069]');
  static final RegExp _spaces = RegExp(r'\s+');

  /// The replies [frame] suggests, in order — or null when it is not a
  /// replies frame (its `replies` is not a list), which is ignored. Never throws.
  static List<GraineQuickReply>? read(Object? frame) {
    final list = Js.asMap(frame)?['replies'];
    if (list is! List) return null;
    final out = <GraineQuickReply>[];
    final seen = <String>{};
    for (final raw in list) {
      final o = Js.asMap(raw);
      final label = line(raw is String ? raw : o?['label'], labelMax);
      if (label.isEmpty || seen.contains(label.toLowerCase())) continue;
      final given = o == null ? '' : line(o['text'], textMax);
      seen.add(label.toLowerCase());
      out.add(GraineQuickReply(label: label, text: given.isNotEmpty ? given : label));
      if (out.length == max) break;
    }
    return out;
  }

  /// One line of words as it may be drawn: no control or direction-override
  /// characters, spaces collapsed, at most [max] characters (whole characters,
  /// never half an emoji).
  static String line(Object? v, int max) {
    if (v is! String) return '';
    final s = v.replaceAll(_controls, ' ').replaceAll(_spaces, ' ').trim();
    final chars = s.runes.toList();
    return chars.length > max ? String.fromCharCodes(chars.take(max)).trim() : s;
  }
}

/// How the end-of-chat rating is asked: two thumbs, five stars or five faces.
enum GraineChatRatingStyle {
  thumbs,
  stars,
  emoji;

  /// The wire's word for it.
  String get wire => name;

  /// A style by its word (or itself); anything this build does not know is thumbs.
  static GraineChatRatingStyle of(Object? style) {
    if (style is GraineChatRatingStyle) return style;
    final word = style is String ? style.trim().toLowerCase() : '';
    for (final s in values) {
      if (s.name == word) return s;
    }
    return thumbs;
  }
}

/// THE USER'S ANSWER TO "HOW WAS THIS CHAT?" — thumbs: 1 up, 0 down, out of
/// 1; stars and emoji: 1–5 out of 5. One per conversation, only after the
/// agent ended it.
class GraineChatRating {
  const GraineChatRating({required this.value, required this.scale, required this.style});

  final int value;
  final int scale;
  final GraineChatRatingStyle style;

  Map<String, Object?> toJson() => <String, Object?>{'value': value, 'scale': scale, 'style': style.wire};

  @override
  bool operator ==(Object other) =>
      other is GraineChatRating && other.value == value && other.scale == scale && other.style == style;

  @override
  int get hashCode => Object.hash(value, scale, style);

  @override
  String toString() => 'GraineChatRating(${style.wire} $value/$scale)';
}

/// How the rating card is laid out in a thread of a given width ([ChatRatings.layout]).
class ChatRatingLayout {
  const ChatRatingLayout({required this.width, required this.count, required this.size, required this.glyph, required this.gap});

  /// The card's width.
  final double width;

  /// How many choices: 2 thumbs, or 5 stars or faces.
  final int count;

  /// Each choice's square target.
  final double size;

  /// The icon or face inside a target, scaled with it.
  final double glyph;

  /// Between two choices.
  final double gap;

  @override
  bool operator ==(Object other) =>
      other is ChatRatingLayout &&
      other.width == width &&
      other.count == count &&
      other.size == size &&
      other.glyph == glyph &&
      other.gap == gap;

  @override
  int get hashCode => Object.hash(width, count, size, glyph, gap);

  @override
  String toString() => 'ChatRatingLayout(width: $width, count: $count, size: $size, glyph: $glyph, gap: $gap)';
}

/// THE RATING ON THE WIRE — protocol.ts chatRating / chatRatingFrame, pinned
/// by sdk/contract/chat-window.json → `rating`: sent as a quiet app event,
/// recorded on the conversation, never a nudge. And the card it is asked on,
/// sized to the thread it sits in ([layout]).
abstract final class ChatRatings {
  /// The app event a rating is recorded as.
  static const String event = 'chat_rating';

  /// The question when the brand wrote none.
  static const String defaultPrompt = 'How was this chat?';

  /// The line under a rating once it is given.
  static const String thanks = 'Thanks for your feedback';

  /// The faces of the emoji rating, 1–5 — drawn as text: every platform has them.
  static const List<String> emoji = <String>['😞', '🙁', '😐', '🙂', '😄'];

  /// What each choice says to a screen reader: thumbs down then up; stars and emoji 1–5.
  static const Map<GraineChatRatingStyle, List<String>> labels = <GraineChatRatingStyle, List<String>>{
    GraineChatRatingStyle.thumbs: <String>['Thumbs down', 'Thumbs up'],
    GraineChatRatingStyle.stars: <String>['1 star', '2 stars', '3 stars', '4 stars', '5 stars'],
    GraineChatRatingStyle.emoji: <String>['Very unhappy', 'Unhappy', 'Neutral', 'Happy', 'Very happy'],
  };

  /// A rating as it may be sent: thumbs 0 or 1 of 1, stars and emoji 1–5 of
  /// 5 (rounded, clamped). A value that is not a number is 0; a style this
  /// build does not know is thumbs.
  static GraineChatRating of(Object? style, Object? value) {
    final s = GraineChatRatingStyle.of(style);
    final n = Js.finite(value) ?? 0;
    if (s == GraineChatRatingStyle.thumbs) return GraineChatRating(value: n >= 1 ? 1 : 0, scale: 1, style: s);
    return GraineChatRating(value: Js.round(n).clamp(1, 5).toInt(), scale: 5, style: s);
  }

  /// The words the conversation's record carries — plain, so a person reading it understands.
  static String detail(GraineChatRating rating) {
    final r = of(rating.style, rating.value);
    if (r.style == GraineChatRatingStyle.thumbs) {
      return r.value == 1 ? 'The customer gave this chat a thumbs up.' : 'The customer gave this chat a thumbs down.';
    }
    return 'The customer rated this chat ${r.value} out of ${r.scale}.';
  }

  /// The frame a rating is sent as.
  static Map<String, Object?> frame(GraineChatRating rating) {
    final r = of(rating.style, rating.value);
    return <String, Object?>{
      'type': 'app_event',
      'event': <String, Object?>{
        'name': event,
        'quiet': true,
        'detail': detail(r),
        'data': <String, Object?>{'value': r.value, 'scale': r.scale, 'style': r.style.wire},
      },
    };
  }

  /// The rating card's width: `min(maxWidth, share × the thread)`, wider where its choices need it.
  static const double maxWidth = 300;
  static const double share = 0.84;

  /// Between two of the rating's choices.
  static const double gap = 8;

  /// Each style's choices at full size: how many, the target, the icon or face inside it.
  static const Map<GraineChatRatingStyle, ({int count, double size, double glyph})> choices =
      <GraineChatRatingStyle, ({int count, double size, double glyph})>{
    GraineChatRatingStyle.thumbs: (count: 2, size: 44, glyph: 22),
    GraineChatRatingStyle.stars: (count: 5, size: 36, glyph: 28),
    GraineChatRatingStyle.emoji: (count: 5, size: 44, glyph: 24),
  };

  /// THE RATING CARD in a thread [thread] wide (its rows' width, inside the
  /// thread's own padding), with [padding] inside the card — protocol.ts
  /// chatRatingLayout, pinned by sdk/contract/chat-window.json →
  /// `ratingLayout`, the SAME numbers on every renderer:
  /// `min(300, 84% of the thread)` wide, wider — up to the thread's own width
  /// — where the choices would not fit inside its padding; the choices at
  /// full size (thumbs and faces 44, stars 36), 8 apart, made smaller
  /// together only where even the whole thread is too narrow for them. A
  /// narrow phone or a large display setting never pushes a choice out of its
  /// card. A width that is not a finite number is 0; a style this build does
  /// not know is thumbs.
  static ChatRatingLayout layout(Object? style, num thread, num padding) {
    final c = choices[GraineChatRatingStyle.of(style)]!;
    final room = thread.isFinite ? math.max(0.0, thread.toDouble()) : 0.0;
    final pad = padding.isFinite ? math.max(0.0, padding.toDouble()) : 0.0;
    final row = c.count * c.size + (c.count - 1) * gap;
    final width = math.min(maxWidth, math.max(room * share, math.min(room, row + 2 * pad)));
    final inner = math.max(0.0, width - 2 * pad);
    final size = math.max(0.0, math.min(c.size, (inner - (c.count - 1) * gap) / c.count));
    return ChatRatingLayout(width: width, count: c.count, size: size, glyph: c.glyph * size / c.size, gap: gap);
  }
}

/// WHAT THE CONVERSATION IS ABOUT — an item, a booking, a case — pinned by
/// the app (`chat.pin(pin)`) and drawn as a bar under the header or a card
/// atop the thread, as the design says. Never sent to the agent: describe the
/// screen to it with the screen context, as always.
class GraineChatPin {
  const GraineChatPin({required this.title, this.subtitle, this.imageUrl, this.badge});

  /// One line, at most 60 characters.
  final String title;

  /// One line, at most 80 characters.
  final String? subtitle;

  /// An http(s) picture, filled and cropped into the thumbnail.
  final String? imageUrl;

  /// A short word or two at the trailing end, at most 24 characters.
  final String? badge;

  static const int titleMax = 60;
  static const int subtitleMax = 80;
  static const int badgeMax = 24;

  /// The pin as it is drawn: each line one line, at most its characters, a
  /// picture only from http(s); null when nothing is left of the title.
  GraineChatPin? get cleaned {
    final t = QuickReplies.line(title, titleMax);
    if (t.isEmpty) return null;
    String? words(String? v, int max) {
      final s = QuickReplies.line(v, max);
      return s.isEmpty ? null : s;
    }

    final image = imageUrl?.trim() ?? '';
    final scheme = Uri.tryParse(image)?.scheme.toLowerCase();
    return GraineChatPin(
      title: t,
      subtitle: words(subtitle, subtitleMax),
      imageUrl: scheme == 'http' || scheme == 'https' ? image : null,
      badge: words(badge, badgeMax),
    );
  }

  /// What a screen reader says: "Pinned: {title}, {subtitle}, {badge}".
  String get spoken => <String>[
        'Pinned: $title',
        if (subtitle != null && subtitle!.isNotEmpty) subtitle!,
        if (badge != null && badge!.isNotEmpty) badge!,
      ].join(', ');

  @override
  bool operator ==(Object other) =>
      other is GraineChatPin &&
      other.title == title &&
      other.subtitle == subtitle &&
      other.imageUrl == imageUrl &&
      other.badge == badge;

  @override
  int get hashCode => Object.hash(title, subtitle, imageUrl, badge);

  @override
  String toString() => 'GraineChatPin("$title")';
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

  // Chat window v2 (protocol.ts foldChat; sdk/contract/chat-window.json → `fold`).
  List<GraineQuickReply> _replies = const <GraineQuickReply>[];
  bool _ended = false;
  GraineChatRating? _rating;

  List<GraineChatTurn> get turns => List<GraineChatTurn>.unmodifiable(_turns);

  /// The replies the agent suggests for its latest turn: gone once the user
  /// sends anything, the agent starts another turn, an earlier conversation
  /// is restored, or the conversation ends.
  List<GraineQuickReply> get quickReplies => _replies;

  /// The agent ended the conversation. A message from the user starts over.
  bool get ended => _ended;

  /// The user's answer to the rating, once given — one per conversation.
  GraineChatRating? get rating => _rating;

  /// The agent suggested [replies] for its turn; an empty list takes them
  /// away. Offered after the conversation ended, they are nobody's to tap.
  void offerReplies(List<GraineQuickReply> replies) {
    if (replies.isEmpty) {
      _replies = const <GraineQuickReply>[];
      return;
    }
    if (_ended) return;
    _replies = List<GraineQuickReply>.unmodifiable(replies);
  }

  /// The agent ended the conversation: the open turn closes, typing stops,
  /// the replies go, and the window may ask for a rating.
  void conversationEnded() {
    _settleLive();
    _turnOpen = false;
    _awaitingReply = false;
    _replies = const <GraineQuickReply>[];
    _ended = true;
  }

  /// The user answered the rating. Kept — true — only for a conversation
  /// that ended and was not rated yet.
  bool rated(GraineChatRating rating) {
    if (!_ended || _rating != null) return false;
    _rating = rating;
    return true;
  }

  /// The user moved on: past the agent's suggestions, and past a conversation that had ended.
  void _goingOn() {
    _replies = const <GraineQuickReply>[];
    _ended = false;
    _rating = null;
  }

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
    _goingOn();
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
    _goingOn();
  }

  /// The agent's start marker: its turn has begun, words to follow — and the
  /// replies it suggested for the turn before are spent.
  void turnStarted() {
    _turnOpen = true;
    _replies = const <GraineQuickReply>[];
  }

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
    // A new turn: the replies suggested for the one before it are spent.
    _replies = const <GraineQuickReply>[];
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
    _goingOn();
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
    // The replies belonged to the moment they were offered, not to the conversation restored.
    _replies = const <GraineQuickReply>[];
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
