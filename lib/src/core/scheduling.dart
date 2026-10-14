/// CALLS A USER BOOKS FROM THE APP — the agent rings them at the time they
/// chose (sdk/contract/inapp-platform-contract.md, §3.3 and §4; the shapes are
/// WIRE.md's "SDK types", the same in every SDK).
///
/// The device asks; Graine books, rings and keeps the record. What comes back
/// is read leniently — a newer server may say more than this build knows,
/// and a status it does not know is [GraineCallStatus.unknown] with its word
/// kept, not an error.
library;

import 'config.dart';
import 'js.dart';

/// Where a booked call stands (wire: `no_device` is [noDevice]).
enum GraineCallStatus {
  /// Booked, waiting for its time.
  scheduled('scheduled'),

  /// The device is ringing now.
  ringing('ringing'),
  answered('answered'),
  completed('completed'),
  declined('declined'),

  /// Rang out with no answer.
  missed('missed'),
  failed('failed'),
  cancelled('cancelled'),

  /// Its time passed while it could not ring (outside the calling hours, or
  /// held too long).
  expired('expired'),

  /// No device of the user's could be rung.
  noDevice('no_device'),

  /// A status this build does not know — the call's `statusName` says it.
  unknown('unknown');

  const GraineCallStatus(this.wire);

  /// The word on the wire.
  final String wire;

  static GraineCallStatus fromWire(Object? s) {
    final w = Js.strOrEmpty(s).trim().toLowerCase();
    for (final v in values) {
      if (v.wire == w) return v;
    }
    return unknown;
  }

  /// Still to come: it will ring, or is ringing.
  bool get upcoming => this == scheduled || this == ringing;
}

/// Who booked a call (wire: `sdk` is [app] — this app).
enum GraineCallSource {
  /// The agent, in a conversation.
  agent('agent'),

  /// The app, through this SDK.
  app('sdk'),
  dashboard('dashboard'),
  api('api'),

  /// A source this build does not know — the call's `sourceName` says it.
  unknown('unknown');

  const GraineCallSource(this.wire);

  /// The word on the wire.
  final String wire;

  /// Null for no source at all.
  static GraineCallSource? fromWire(Object? s) {
    final w = Js.strOrEmpty(s).trim().toLowerCase();
    if (w.isEmpty) return null;
    for (final v in values) {
      if (v.wire == w) return v;
    }
    return unknown;
  }
}

/// ONE CALL THE USER BOOKED — WIRE.md's `GraineScheduledCall`.
class GraineScheduledCall {
  const GraineScheduledCall({
    required this.id,
    this.at,
    this.status = GraineCallStatus.scheduled,
    String? statusName,
    this.source,
    this.sourceName,
    this.reason,
  }) : statusName = statusName ?? '';

  /// Graine's id for the booking — what [GraineScheduledCall]s are cancelled by.
  final String id;

  /// When it rings, in UTC (`.toLocal()` for the user's clock); null only
  /// when the server's time was unreadable.
  final DateTime? at;
  final GraineCallStatus status;

  /// The status as the server said it — with [GraineCallStatus.unknown], the
  /// word this build does not know. Empty when the server said none.
  final String statusName;

  /// Who booked it; null when the server does not say.
  final GraineCallSource? source;

  /// The source as the server said it (`sdk`, `agent`, …), or null.
  final String? sourceName;

  /// What it is about, as booked.
  final String? reason;

  /// Still to come: scheduled or ringing.
  bool get isUpcoming => status.upcoming;

  /// It can still be called off: scheduled.
  bool get canCancel => status == GraineCallStatus.scheduled;

  /// The status word: [statusName] when the server gave one, else [status]'s.
  String get statusWire => statusName.isNotEmpty ? statusName : status.wire;

  /// Null for anything that is not a call with an id.
  static GraineScheduledCall? fromJson(Object? raw) {
    final r = Js.asMap(raw);
    if (r == null) return null;
    final id = _firstString(<Object?>[r['id'], r['callId'], r['call_id'], r['_id']]);
    if (id == null) return null;
    final said = Js.strOrEmpty(r['status']).trim();
    final from = _firstString(<Object?>[r['source']]);
    return GraineScheduledCall(
      id: id,
      at: ScheduledCalls.parseTime(Js.firstDefined(<Object?>[r['at'], r['scheduledAt'], r['scheduled_at']])),
      status: said.isEmpty ? GraineCallStatus.scheduled : GraineCallStatus.fromWire(said),
      statusName: said,
      source: GraineCallSource.fromWire(from),
      sourceName: from,
      reason: _firstString(<Object?>[r['reason']]),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'at': at?.toUtc().toIso8601String(),
        'status': statusWire,
        'source': sourceName ?? source?.wire,
        'reason': reason,
      };

  @override
  bool operator ==(Object other) =>
      other is GraineScheduledCall &&
      other.id == id &&
      other.at == at &&
      other.statusWire == statusWire &&
      other.reason == reason &&
      other.source == source;

  @override
  int get hashCode => Object.hash(id, at, statusWire, reason, source);

  @override
  String toString() => 'GraineScheduledCall($id, ${at?.toIso8601String()}, $statusWire)';
}

/// WHAT THE AGENT ALLOWS USERS TO BOOK, and how Graine rings — WIRE.md's
/// `GraineSchedulingRules`, from the session's `calls`. A session that says
/// nothing (an older server) allows no booking.
class GraineSchedulingRules {
  const GraineSchedulingRules({
    this.usersCanBook = false,
    this.minLeadMinutes = 5,
    this.maxDaysAhead = 14,
    this.maxPendingPerUser = 3,
    this.ringTimeoutSeconds = 45,
    this.callName,
    this.hostedRinging = false,
    this.platforms = const <String>[],
  });

  /// The rules of [calls] (the session's `calls`; null: an older server).
  factory GraineSchedulingRules.of(CallsSetting? calls) {
    final s = calls?.scheduling;
    return GraineSchedulingRules(
      usersCanBook: s?.usersCanBook ?? false,
      minLeadMinutes: s?.minLeadMinutes ?? 5,
      maxDaysAhead: s?.maxDaysAhead ?? 14,
      maxPendingPerUser: s?.maxPendingPerUser ?? 3,
      ringTimeoutSeconds: calls?.ringTimeoutSeconds ?? 45,
      callName: calls?.callName,
      hostedRinging: calls?.hosted ?? false,
      platforms: calls?.platforms ?? const <String>[],
    );
  }

  /// `scheduleCall` is allowed at all.
  final bool usersCanBook;
  final int minLeadMinutes;
  final int maxDaysAhead;
  final int maxPendingPerUser;

  /// How long a ring lasts before it is missed.
  final int ringTimeoutSeconds;

  /// What the phone shows for the agent's calls; null — the agent's name.
  final String? callName;

  /// The workspace has Graine ring its users' devices.
  final bool hostedRinging;

  /// Where it rings: `ios`, `android`.
  final List<String> platforms;

  /// The soonest a call can be booked for: [now] + [minLeadMinutes].
  DateTime earliest(DateTime now) => now.add(Duration(minutes: minLeadMinutes));

  /// The latest a call can be booked for: [now] + [maxDaysAhead] days.
  DateTime latest(DateTime now) => now.add(Duration(days: maxDaysAhead));
}

/// The rules for what goes out and what comes back.
abstract final class ScheduledCalls {
  /// The longest reason a booking carries.
  static const int maxReasonLength = 120;

  /// A time on the wire: ISO-8601 with the device's own offset, to the second
  /// — `2026-10-14T18:00:00+05:30` (`Z` where the offset is zero), as the iOS
  /// SDK writes it.
  static String atWire(DateTime at, {Duration? offset}) {
    final zone = offset ?? at.toLocal().timeZoneOffset;
    final t = at.toUtc().add(zone);
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}'
        'T${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
    if (zone == Duration.zero) return '${date}Z';
    final minutes = zone.inMinutes.abs();
    return '$date${zone.isNegative ? '-' : '+'}${two(minutes ~/ 60)}:${two(minutes % 60)}';
  }

  /// An ISO-8601 string with a zone (or an epoch in milliseconds), as UTC;
  /// null for anything else. A time with no zone is read as UTC — a server
  /// never sends a local time.
  static DateTime? parseTime(Object? v) {
    if (v is num && v.isFinite) return DateTime.fromMillisecondsSinceEpoch(v.round(), isUtc: true);
    if (v is! String || v.trim().isEmpty) return null;
    final s = v.trim();
    final zoned = RegExp(r'(Z|[+-]\d\d:?\d\d)$', caseSensitive: false).hasMatch(s);
    final t = DateTime.tryParse(zoned ? s : '${s}Z');
    return t?.toUtc();
  }

  /// The booking a schedule request answered with: `{call: {...}}`, or the
  /// call itself.
  static GraineScheduledCall? oneFrom(Object? body) {
    final m = Js.asMap(body);
    if (m == null) return null;
    return GraineScheduledCall.fromJson(m['call']) ??
        GraineScheduledCall.fromJson(m['scheduledCall']) ??
        GraineScheduledCall.fromJson(m);
  }

  /// The bookings a list request answered with — `{calls: [...]}` or a bare
  /// list — in the server's order (upcoming first). Entries that are not
  /// calls are skipped.
  static List<GraineScheduledCall> listFrom(Object? body) {
    final m = Js.asMap(body);
    final raw = m == null ? body : Js.firstDefined(<Object?>[m['calls'], m['scheduledCalls'], m['items']]);
    return <GraineScheduledCall>[
      for (final x in Js.asList(raw))
        if (GraineScheduledCall.fromJson(x) case final GraineScheduledCall c) c,
    ];
  }

  /// A cancel's answer: `{ok, status?}` — the call's status afterwards,
  /// [GraineCallStatus.cancelled] when the server does not say.
  static GraineCallStatus statusAfterCancel(Object? body) {
    final said = Js.strOrEmpty(Js.asMap(body)?['status']).trim();
    return said.isEmpty ? GraineCallStatus.cancelled : GraineCallStatus.fromWire(said);
  }
}

String? _firstString(List<Object?> values) {
  for (final v in values) {
    if (v is String && v.trim().isNotEmpty) return v.trim();
    if (v is int) return v.toString();
  }
  return null;
}

/// Where one booked call's Cancel is, on the chat's Upcoming calls card.
enum GraineUpcomingCancel {
  /// Not asked.
  none,

  /// Asked; the row says "Cancelling…" until Graine answers.
  cancelling,

  /// Graine could not cancel it: "Couldn’t cancel · tap to retry".
  failed,
}

/// THE TIMES A CHAT SHOWS, in the device's own zone (contract/DESIGN.md,
/// "Chat window"): the short clock under a message, and a booked call's day.
abstract final class ChatTime {
  static const List<String> _weekdays = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const List<String> _months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// The device's short time: "9:41 PM", or "21:41" on a 24-hour device.
  static String clock(DateTime time, {required bool h24}) {
    final t = time.toLocal();
    final m = t.minute.toString().padLeft(2, '0');
    if (h24) return '${t.hour.toString().padLeft(2, '0')}:$m';
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  /// A booked call's time: "Today, 5:30 PM", "Tomorrow, 9:00 AM", else the
  /// weekday and the date — "Wed 14 Oct, 10:00 AM".
  static String booked(DateTime at, DateTime now, {required bool h24}) {
    final a = at.toLocal();
    final n = now.toLocal();
    bool sameDay(DateTime x, DateTime y) => x.year == y.year && x.month == y.month && x.day == y.day;
    final time = clock(a, h24: h24);
    if (sameDay(a, n)) return 'Today, $time';
    if (sameDay(a, DateTime(n.year, n.month, n.day + 1))) return 'Tomorrow, $time';
    return '${day(a)}, $time';
  }

  /// A day in short words: the weekday and the date — "Wed 14 Oct".
  static String day(DateTime at) {
    final a = at.toLocal();
    return '${_weekdays[a.weekday - 1]} ${a.day} ${_months[a.month - 1]}';
  }
}
