/// BOOKING A CALL FROM THE APP — the rules the SDK's own booking sheet draws
/// from (BOOKING-SHEET.md), the same on every platform: when booking is
/// offered at all, which days and times the sheet offers, and the one line
/// each refusal shows under its button. Pure: the Flutter half passes the
/// platform, the clock and whether the user is identified.
library;

import 'config.dart';
import 'scheduling.dart';

/// The interval every option of the sheet is clamped to, both ends on the
/// 5-minute grid.
final class BookingBounds {
  const BookingBounds(this.earliest, this.latest);

  /// now + minLeadMinutes, rounded up to 5 minutes.
  final DateTime earliest;

  /// now + maxDaysAhead days, rounded down to 5 minutes.
  final DateTime latest;
}

/// One day the sheet offers.
final class BookingDay {
  const BookingDay({required this.key, required this.label, required this.first, required this.last});

  /// The day on the device, `YYYY-MM-DD`.
  final String key;

  /// Its chip: "Today", "Tomorrow", then the weekday and date ("Thu 16 Oct").
  final String label;

  /// The first and the last time it offers — on the 5-minute grid, inside the bounds.
  final DateTime first;
  final DateTime last;
}

/// WHY BOOKING IS NOT OFFERED HERE (contract/PUBLIC-STATE.md, "Booking and
/// scheduled calls") — `GraineInApp.bookingUnavailableReason`, null while
/// booking is available. [Booking.unavailableReason] decides it, in this
/// order — the same words, in the same order, on every Graine SDK.
enum GraineBookingUnavailableReason {
  /// The agent's settings have not arrived yet.
  notLoaded('not_loaded'),

  /// Graine cannot ring this phone: the workspace has not set up in-app
  /// calling, or not for this platform.
  ringsNotSetUp('rings_not_set_up'),

  /// The agent takes no bookings from the app (its Calls & scheduling
  /// setting), or the server says nothing about booking.
  schedulingOff('scheduling_off'),

  /// Nobody is identified with the agent's identity trait — a booking needs
  /// to know whose phones to ring.
  notIdentified('not_identified');

  const GraineBookingUnavailableReason(this.wire);

  /// The word every Graine SDK uses.
  final String wire;

  /// The refusal the booking sheet words it with ([Booking.errorLine]):
  /// [GraineErrorCode.identityRequired] for [notIdentified], else
  /// [GraineErrorCode.schedulingOff].
  GraineErrorCode get code => this == notIdentified ? GraineErrorCode.identityRequired : GraineErrorCode.schedulingOff;
}

abstract final class Booking {
  /// The sheet's words — the same on every platform.
  static const String title = 'Book a call';
  static const String about = "What's it about? (optional)";
  static const String book = 'Book call';
  static const String done = 'Done';

  /// On a website: the booking rings the user's app, not the browser.
  static const String web = "We'll ring you in the app";

  /// The longest reason a booking carries (the server's limit).
  static const int reasonMax = ScheduledCalls.maxReasonLength;

  /// Times are offered on this grid: the earliest rounded up to it, the latest down.
  static const int roundMinutes = 5;

  /// Under the title: "{call name} will call you".
  static String subtitle(String callName) => '$callName will call you';

  /// Who "will call you": the agent's call name (`calls.callName`), else the
  /// chat's title, else the heading, else "Assistant".
  static String callName(List<String?> names) {
    for (final n in names) {
      final s = n?.trim() ?? '';
      if (s.isNotEmpty) return s;
    }
    return 'Assistant';
  }

  /// WHY BOOKING IS NOT OFFERED HERE, or null when it is — one rule for
  /// every SDK. Booking needs all of: the agent lets users book
  /// (`calls.scheduling.usersCanBook`); Graine can ring this phone
  /// (`calls.hosted`, and `calls.platforms` empty or naming [platform]) — a
  /// web page cannot be rung, so it books for the user's app and needs only
  /// the rest; and the user is identified with the agent's identity trait.
  /// The agent's settings are said first: signing in would not help with
  /// booking off.
  static GraineErrorCode? blocker(CallsSetting? calls, {required String? platform, required bool identified}) {
    if (calls?.scheduling?.usersCanBook != true) return GraineErrorCode.schedulingOff;
    if (platform != 'web') {
      if (platform != 'ios' && platform != 'android') return GraineErrorCode.schedulingOff;
      if (calls?.hosted != true) return GraineErrorCode.schedulingOff;
      final named = calls!.platforms;
      if (named.isNotEmpty && !named.contains(platform)) return GraineErrorCode.schedulingOff;
    }
    return identified ? null : GraineErrorCode.identityRequired;
  }

  /// `bookingAvailable`: [blocker] says nothing.
  static bool available(CallsSetting? calls, {required String? platform, required bool identified}) =>
      blocker(calls, platform: platform, identified: identified) == null;

  /// WHY BOOKING IS NOT OFFERED HERE, in finer words than [blocker], checked
  /// in this order: the agent's settings not [loaded] yet (`not_loaded`);
  /// Graine cannot ring this phone (`rings_not_set_up` — a web page books
  /// for the user's app, so it is never this); the agent takes no bookings,
  /// or a server says nothing about them (`scheduling_off`); nobody
  /// identified (`not_identified`). Null exactly when [blocker] is.
  static GraineBookingUnavailableReason? unavailableReason(CallsSetting? calls,
      {required String? platform, required bool identified, bool loaded = true}) {
    if (!loaded) return GraineBookingUnavailableReason.notLoaded;
    if (platform != 'web') {
      if (platform != 'ios' && platform != 'android') return GraineBookingUnavailableReason.ringsNotSetUp;
      if (calls?.hosted != true) return GraineBookingUnavailableReason.ringsNotSetUp;
      final named = calls!.platforms;
      if (named.isNotEmpty && !named.contains(platform)) return GraineBookingUnavailableReason.ringsNotSetUp;
    }
    if (calls?.scheduling?.usersCanBook != true) return GraineBookingUnavailableReason.schedulingOff;
    return identified ? null : GraineBookingUnavailableReason.notIdentified;
  }

  static const int _step = roundMinutes * 60 * 1000;

  /// [rules]' bounds at [now]: the earliest rounded up to 5 minutes, the latest down.
  static BookingBounds bounds(GraineSchedulingRules rules, DateTime now) {
    final lead = now.millisecondsSinceEpoch + rules.minLeadMinutes * 60 * 1000;
    final far = now.millisecondsSinceEpoch + rules.maxDaysAhead * Duration.millisecondsPerDay;
    return BookingBounds(
      DateTime.fromMillisecondsSinceEpoch(((lead + _step - 1) ~/ _step) * _step),
      DateTime.fromMillisecondsSinceEpoch((far ~/ _step) * _step),
    );
  }

  /// [at] inside [bounds], on the 5-minute grid (to the nearest mark).
  static DateTime clamp(DateTime at, BookingBounds bounds) {
    final snapped = ((at.millisecondsSinceEpoch + _step ~/ 2) ~/ _step) * _step;
    final lo = bounds.earliest.millisecondsSinceEpoch;
    final hi = bounds.latest.millisecondsSinceEpoch;
    return DateTime.fromMillisecondsSinceEpoch(snapped < lo ? lo : (snapped > hi ? (hi < lo ? lo : hi) : snapped));
  }

  /// A day's chip: "Today", "Tomorrow", else the weekday and date ("Thu 16 Oct").
  static String dayLabel(DateTime at, DateTime now) => BookingClock.device.dayLabel(at, now);

  /// THE DAYS THE SHEET OFFERS: from the day of the earliest time to the day
  /// of the latest, each with its first and last time on the 5-minute grid.
  /// A day with no time left in it is not offered. With the agent's calling
  /// [window] (`GraineSchedulingRules.callingWindow`), only the times inside
  /// it count: a day it leaves out is not offered, and each day's first and
  /// last time are its first and last inside the window.
  static List<BookingDay> days(BookingBounds bounds, DateTime now, {GraineCallingWindow? window}) =>
      BookingClock.device.days(bounds, now, window: window);

  /// THE TIMES [day] OFFERS, every [stepMinutes] on the clock's grid — the
  /// sheet's 5 by default — from its first time to its last, in the device's
  /// time zone, and with the agent's calling [window] only the times inside
  /// it: a picker of your own offers exactly what the sheet does.
  static List<DateTime> slots(BookingDay day, {int stepMinutes = roundMinutes, GraineCallingWindow? window}) =>
      BookingClock.device.slots(day, stepMinutes: stepMinutes, window: window);

  /// The time on [day] a picker answered with ([hour]:[minute] on the
  /// device's clock), on the 5-minute grid, clamped into what the day offers.
  static DateTime onDay(BookingDay day, int hour, int minute) {
    final d = day.first.toLocal();
    final raw = DateTime(d.year, d.month, d.day, hour, minute);
    final snapped = DateTime.fromMillisecondsSinceEpoch(((raw.millisecondsSinceEpoch + _step ~/ 2) ~/ _step) * _step);
    if (snapped.isBefore(day.first)) return day.first;
    if (snapped.isAfter(day.last)) return day.last;
    return snapped;
  }

  /// The time zone line: "Asia/Kolkata · Wed 14 Oct, 6:00 PM" — the zone, then the time chosen.
  static String zoneLine(DateTime at, String? zone, {required bool h24}) {
    final when = '${ChatTime.day(at)}, ${ChatTime.clock(at, h24: h24)}';
    final z = zone?.trim() ?? '';
    return z.isEmpty ? when : '$z · $when';
  }

  /// After a booking: "Booked — {call name} will call you on {day}, {time}" —
  /// always the date ("on Wed 14 Oct, 6:00 PM"), never "on Today".
  static String doneLine(String callName, DateTime? at, {required bool h24}) => at == null
      ? 'Booked — $callName will call you'
      : 'Booked — $callName will call you on ${ChatTime.day(at)}, ${ChatTime.clock(at, h24: h24)}';

  /// THE ONE LINE UNDER "Book call" for a refusal, in plain words; the rules
  /// give the numbers. Anything else — a limit, no answer, a code this build
  /// does not know — is "try again".
  static String errorLine(GraineErrorCode? code, GraineSchedulingRules rules) => switch (code) {
        GraineErrorCode.tooSoon => 'Pick a time at least ${_counted(rules.minLeadMinutes, 'minute')} from now',
        GraineErrorCode.tooFar => 'Pick a time within ${_counted(rules.maxDaysAhead, 'day')}',
        GraineErrorCode.outsideWindow => 'That time is outside the hours we can call — pick another',
        GraineErrorCode.tooManyPending =>
          'You already have ${_counted(rules.maxPendingPerUser, 'call')} booked — cancel one first',
        GraineErrorCode.schedulingOff => "Booking a call isn't available right now",
        GraineErrorCode.identityRequired => 'Sign in to book a call',
        _ => "Couldn't book just now — try again",
      };

  static String _counted(int n, String one) => '$n ${n == 1 ? one : '${one}s'}';
}

bool _sameDay(DateTime x, DateTime y) => x.year == y.year && x.month == y.month && x.day == y.day;

String _key(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

final RegExp _hhmm = RegExp(r'^\s*(\d{1,2}):(\d{2})\s*$');

/// "HH:MM" as minutes past midnight; null for anything else.
int? _minutesOf(String hhmm) {
  final m = _hhmm.firstMatch(hhmm);
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  return h < 24 && min < 60 ? h * 60 + min : null;
}

/// THE BOOKING RULES READ ON A CLOCK — the device's ([device], what the SDK
/// and its sheet use), or a zone given by its offsets from UTC
/// ([BookingClock.offsets]) so the shared contract's vectors
/// (sdk/contract/booking-slots.json) run through the very same code for any
/// time zone. Not part of the package's API.
final class BookingClock {
  const BookingClock._(this._offsets);

  /// A zone given as its offsets from UTC, each `(from, offset)` in force
  /// from `from` until the next one, in order (the contract's `utcOffsets`).
  factory BookingClock.offsets(List<(DateTime, Duration)> offsets) =>
      BookingClock._(<(int, int)>[for (final (at, off) in offsets) (at.millisecondsSinceEpoch, off.inMilliseconds)]);

  /// The device's own clock and zone.
  static const BookingClock device = BookingClock._(null);

  final List<(int, int)>? _offsets;

  static const int _step = Booking.roundMinutes * 60 * 1000;

  int _offsetAt(int ms) {
    final table = _offsets!;
    var off = table.first.$2;
    for (final (from, o) in table) {
      if (from > ms) break;
      off = o;
    }
    return off;
  }

  /// [t] on this clock: its year, month, day, weekday, hour and minute are the wall clock's.
  DateTime wall(DateTime t) => _offsets == null
      ? t.toLocal()
      : DateTime.fromMillisecondsSinceEpoch(t.millisecondsSinceEpoch + _offsetAt(t.millisecondsSinceEpoch), isUtc: true);

  /// The first instant of the day [year]-[month]-[day] (overflowing days roll on).
  DateTime midnight(int year, int month, int day) {
    if (_offsets == null) return DateTime(year, month, day);
    final base = DateTime.utc(year, month, day).millisecondsSinceEpoch;
    final guess = base - _offsetAt(base);
    return DateTime.fromMillisecondsSinceEpoch(base - _offsetAt(guess), isUtc: true);
  }

  DateTime _instant(int ms) =>
      _offsets == null ? DateTime.fromMillisecondsSinceEpoch(ms) : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

  /// [at] is inside [window] on this clock: its weekday (Monday 0) is one of
  /// the window's days, and start <= its time < end. No window: always.
  bool inWindow(GraineCallingWindow? window, DateTime at) {
    final open = window == null ? null : _minutesOf(window.start);
    final close = window == null ? null : _minutesOf(window.end);
    // No window, or one that cannot be read (built by hand with other words): every time.
    if (window == null || open == null || close == null) return true;
    final w = wall(at);
    if (!window.days.contains(w.weekday - 1)) return false;
    final minute = w.hour * 60 + w.minute;
    return open <= minute && minute < close;
  }

  /// [Booking.dayLabel] on this clock.
  String dayLabel(DateTime at, DateTime now) {
    final a = wall(at);
    final n = wall(now);
    if (_sameDay(a, n)) return 'Today';
    if (_sameDay(a, DateTime.utc(n.year, n.month, n.day + 1))) return 'Tomorrow';
    return ChatTime.day(DateTime(a.year, a.month, a.day));
  }

  /// [Booking.days] on this clock.
  List<BookingDay> days(BookingBounds bounds, DateTime now, {GraineCallingWindow? window}) {
    final lo = _offsets == null ? bounds.earliest.toLocal() : bounds.earliest;
    final hi = _offsets == null ? bounds.latest.toLocal() : bounds.latest;
    final out = <BookingDay>[];
    if (hi.isBefore(lo)) return out;
    final from = wall(lo);
    var start = midnight(from.year, from.month, from.day);
    // Bounded: the server allows 30 days ahead, and this never loops past a year.
    for (var i = 0; i < 400 && !start.isAfter(hi); i++) {
      final s = wall(start);
      final next = midnight(s.year, s.month, s.day + 1);
      var first = start.isBefore(lo) ? lo : start;
      final lastOfDay = _instant(((next.millisecondsSinceEpoch - 1) ~/ _step) * _step);
      var last = lastOfDay.isAfter(hi) ? hi : lastOfDay;
      if (window != null && !first.isAfter(last)) {
        // Only the times inside the window: the day's first and last of them, or none.
        final lowest = ((first.millisecondsSinceEpoch + _step - 1) ~/ _step) * _step;
        final highest = last.millisecondsSinceEpoch;
        int? a;
        for (var t = lowest; t <= highest; t += _step) {
          if (inWindow(window, _instant(t))) {
            a = t;
            break;
          }
        }
        int? b;
        if (a != null) {
          for (var t = (highest ~/ _step) * _step; t >= a; t -= _step) {
            if (inWindow(window, _instant(t))) {
              b = t;
              break;
            }
          }
        }
        if (a == null || b == null) {
          start = next;
          continue;
        }
        first = _instant(a);
        last = _instant(b);
      }
      if (!first.isAfter(last)) {
        out.add(BookingDay(key: _key(wall(first)), label: dayLabel(first, now), first: first, last: last));
      }
      start = next;
    }
    return out;
  }

  /// [Booking.slots] on this clock.
  List<DateTime> slots(BookingDay day, {int stepMinutes = Booking.roundMinutes, GraineCallingWindow? window}) {
    final step = (stepMinutes < 1 ? 1 : stepMinutes) * 60 * 1000;
    final last = day.last.millisecondsSinceEpoch;
    return <DateTime>[
      for (var t = ((day.first.millisecondsSinceEpoch + step - 1) ~/ step) * step; t <= last; t += step)
        if (window == null || inWindow(window, _instant(t))) _instant(t),
    ];
  }

  /// THE TIMES THE SHEET OFFERS ON THE DAY HOLDING [day] (`GraineInApp.bookingSlots`):
  /// [rules]' days from [now], that day's 5-minute steps, inside the rules' calling window.
  List<DateTime> slotsOn(GraineSchedulingRules rules, DateTime day, DateTime now) {
    final d = wall(day);
    final window = rules.callingWindow;
    for (final offered in days(Booking.bounds(rules, now), now, window: window)) {
      if (_sameDay(wall(offered.first), d)) return slots(offered, window: window);
    }
    return const <DateTime>[];
  }
}
