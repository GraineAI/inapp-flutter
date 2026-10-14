/// WHAT A CHAT WINDOW DRAWS, in order (contract/DESIGN.md, "Chat window";
/// contract §2.6, the `rows` of sdk/contract/history.json): a bubble per chat
/// turn; ONE "Voice call · 6:05 PM" row for a run of voice turns on one day —
/// that a call happened and when, never its transcript; and a day separator —
/// Today, Yesterday, a date — before the first row when it is not from today,
/// and wherever the device's day changes between rows. A conversation all from
/// today draws exactly what it always did. The React Native SDK's chatRows
/// (protocol.ts), ported. Pure: no Flutter, so `test/` runs every row.
library;

import 'chat.dart';
import 'design.dart';

/// Which day a separator names.
enum ChatDay { today, yesterday, date }

/// One row of the thread.
sealed class ChatRow {
  const ChatRow();

  /// Stable while the conversation grows: a separator by its date, a call by
  /// its first turn, a bubble by its turn.
  String get key;
}

/// A day separator: which day, the local date (YYYY-MM-DD), and the first
/// message's time on it.
final class ChatDayRow extends ChatRow {
  const ChatDayRow(this.day, this.date, this.at);
  final ChatDay day;
  final String date;
  final DateTime at;

  /// The contract's word for it: "today", "yesterday" or the local date.
  String get contractKey => switch (day) { ChatDay.today => 'today', ChatDay.yesterday => 'yesterday', ChatDay.date => date };

  @override
  String get key => 'day-$date';
}

/// An earlier call: when its first turn was said, and which turns (indices
/// into the conversation) it stands for.
final class ChatVoiceRow extends ChatRow {
  const ChatVoiceRow(this.id, this.at, this.first, this.last);
  final String id;
  final DateTime at;
  final int first;
  final int last;

  @override
  String get key => id;
}

/// A bubble.
final class ChatTurnRow extends ChatRow {
  const ChatTurnRow(this.turn, this.index);
  final GraineChatTurn turn;
  final int index;

  @override
  String get key => turn.id;
}

abstract final class ChatRows {
  static const List<String> _weekdays = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const List<String> _months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static DateTime _deviceTime(DateTime t) => t.toLocal();

  /// The rows for [turns] (oldest first). [local] reads an instant as the
  /// device's wall clock — the device's own zone unless a test says otherwise.
  static List<ChatRow> build(List<GraineChatTurn> turns, {required DateTime now, DateTime Function(DateTime)? local}) {
    final wall = local ?? _deviceTime;
    final n = wall(now);
    final today = _date(n.year, n.month, n.day);
    final y = DateTime.utc(n.year, n.month, n.day - 1);
    final yesterday = _date(y.year, y.month, y.day);
    final rows = <ChatRow>[];
    String? lastDay;
    var openCall = -1;
    String? callDay;
    for (var index = 0; index < turns.length; index++) {
      final turn = turns[index];
      final l = wall(turn.at);
      final day = _date(l.year, l.month, l.day);
      final voice = turn.channel == GraineChatChannel.voice;
      // One call, one row — until the day turns: a separator never sits inside a row.
      final call = openCall >= 0 ? rows[openCall] : null;
      if (voice && call is ChatVoiceRow && callDay == day) {
        rows[openCall] = ChatVoiceRow(call.id, call.at, call.first, index);
        continue;
      }
      if (lastDay == null ? day != today : day != lastDay) {
        final kind = day == today ? ChatDay.today : (day == yesterday ? ChatDay.yesterday : ChatDay.date);
        rows.add(ChatDayRow(kind, day, turn.at));
      }
      lastDay = day;
      if (voice) {
        rows.add(ChatVoiceRow('voice-${turn.id}', turn.at, index, index));
        openCall = rows.length - 1;
        callDay = day;
      } else {
        rows.add(ChatTurnRow(turn, index));
        openCall = -1;
        callDay = null;
      }
    }
    return rows;
  }

  /// "Today", "Yesterday", else the date — "Sat 10 Oct", and the year when it
  /// is not this one ("Wed 31 Dec 2025") — as `ChatTime.booked` writes a day.
  static String dayLabel(ChatDayRow row, {required DateTime now, DateTime Function(DateTime)? local}) {
    switch (row.day) {
      case ChatDay.today:
        return 'Today';
      case ChatDay.yesterday:
        return 'Yesterday';
      case ChatDay.date:
        final wall = local ?? _deviceTime;
        final a = wall(row.at);
        final sameYear = a.year == wall(now).year;
        return '${_weekdays[a.weekday - 1]} ${a.day} ${_months[a.month - 1]}${sameYear ? '' : ' ${a.year}'}';
    }
  }

  /// "Voice call · 6:05 PM" — the call's first turn, in the device's short time ([clock]).
  static String callLabel(String clock) => 'Voice call · $clock';

  /// What a screen reader says for the row: "Voice call at 6:05 PM".
  static String callSpoken(String clock) => 'Voice call at $clock';

  /// The header's "New conversation" belongs to a conversation that
  /// continues: offered while restored turns are on screen.
  static bool offersNewConversation(List<GraineChatTurn> turns) => turns.any((GraineChatTurn t) => t.restored);

  /// The brand's starters belong to a new chat: not once the user has said
  /// something, nor on a conversation that continues.
  static bool offersStarters(List<GraineChatTurn> turns) =>
      !turns.any((GraineChatTurn t) => t.role == GraineChatRole.user || t.restored);

  static String _date(int y, int m, int d) =>
      '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
}

/// THE PIECES A CHAT WINDOW DRAWS of those the design can leave out
/// (contract/DESIGN.md, "Chat window" → Booked calls, Earlier messages, New
/// conversation) — the React Native SDK's chatPieces, ported, and pinned for
/// every SDK by sdk/contract/history.json → `display`. With earlier messages
/// hidden the window opens like a new chat: the restored turns are not drawn
/// (the agent still has them), the starters may show, and the compose
/// control, which belongs to earlier messages on screen, does not.
final class ChatPieces {
  const ChatPieces._(this.turns, this.starters, this.newConversation, this.upcoming, this.upcomingTitle, this.book);

  /// The turns to draw, oldest first.
  final List<GraineChatTurn> turns;

  /// The brand's starters may show: nothing restored on screen, nothing said by the user.
  final bool starters;

  /// The header's compose control: kept by the design, and earlier messages on screen.
  final bool newConversation;

  /// The booked-calls card: kept by the design, and at least one booked call.
  final bool upcoming;

  /// The card's title: the brand's words, else "Upcoming call" / "Upcoming calls".
  final String upcomingTitle;

  /// "Book a call" in the card's place — in the card, or a compact row while
  /// nothing is booked: kept by the design (it belongs to the booked-calls
  /// piece), and booking available here (`Booking.available`).
  final bool book;

  /// For [turns] and [upcomingCount] booked calls, as the design sets the pieces.
  static ChatPieces of(
    List<GraineChatTurn> turns, {
    bool showHistory = true,
    bool newConversation = true,
    bool showUpcomingCalls = true,
    String upcomingTitle = '',
    int upcomingCount = 0,
    bool bookingAvailable = false,
  }) {
    final shown = showHistory ? List<GraineChatTurn>.unmodifiable(turns) : List<GraineChatTurn>.unmodifiable(turns.where((GraineChatTurn t) => !t.restored));
    final words = upcomingTitle.trim();
    return ChatPieces._(
      shown,
      ChatRows.offersStarters(shown),
      newConversation && ChatRows.offersNewConversation(shown),
      showUpcomingCalls && upcomingCount > 0,
      words.isNotEmpty ? words : (upcomingCount == 1 ? 'Upcoming call' : 'Upcoming calls'),
      showUpcomingCalls && bookingAvailable,
    );
  }

  /// The same under a session's chat tokens (null, an older server: everything on).
  static ChatPieces ofChat(List<GraineChatTurn> turns, ThemeChat? chat, {int upcomingCount = 0, bool bookingAvailable = false}) => of(
        turns,
        showHistory: chat?.showHistory ?? true,
        newConversation: chat?.newConversation ?? true,
        showUpcomingCalls: chat?.showUpcomingCalls ?? true,
        upcomingTitle: chat?.upcomingTitle ?? '',
        upcomingCount: upcomingCount,
        bookingAvailable: bookingAvailable,
      );
}
