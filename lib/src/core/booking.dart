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
  static String dayLabel(DateTime at, DateTime now) {
    final a = at.toLocal();
    final n = now.toLocal();
    if (_sameDay(a, n)) return 'Today';
    if (_sameDay(a, DateTime(n.year, n.month, n.day + 1))) return 'Tomorrow';
    return ChatTime.day(a);
  }

  /// THE DAYS THE SHEET OFFERS: from the day of the earliest time to the day
  /// of the latest, each with its first and last time on the 5-minute grid.
  /// A day with no time left in it is not offered.
  static List<BookingDay> days(BookingBounds bounds, DateTime now) {
    final lo = bounds.earliest.toLocal();
    final hi = bounds.latest.toLocal();
    final out = <BookingDay>[];
    if (hi.isBefore(lo)) return out;
    var start = DateTime(lo.year, lo.month, lo.day);
    // Bounded: the server allows 30 days ahead, and this never loops past a year.
    for (var i = 0; i < 400 && !start.isAfter(hi); i++) {
      final next = DateTime(start.year, start.month, start.day + 1);
      final first = start.isBefore(lo) ? lo : start;
      final lastOfDay = DateTime.fromMillisecondsSinceEpoch(((next.millisecondsSinceEpoch - 1) ~/ _step) * _step);
      final last = lastOfDay.isAfter(hi) ? hi : lastOfDay;
      if (!first.isAfter(last)) {
        out.add(BookingDay(key: _key(first), label: dayLabel(first, now), first: first, last: last));
      }
      start = next;
    }
    return out;
  }

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

  static bool _sameDay(DateTime x, DateTime y) => x.year == y.year && x.month == y.month && x.day == y.day;

  static String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
