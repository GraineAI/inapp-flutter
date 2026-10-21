// BOOKING SLOTS AND THE AGENT'S CALLING WINDOW (sdk/contract/booking-slots.json,
// generated from the rule by generate-booking-slots.mjs): what the session's
// `calls.scheduling.callingWindow` reads as, and the times bookingSlots(day) and
// the booking sheet offer — in each case's own time zone, through the same code
// the device runs (BookingClock, handed the zone's offsets from UTC: Dart has no
// time zone database). A missing file FAILS: this contract is never skipped.
import 'package:graine_inapp/src/core/core.dart';
import 'package:test/test.dart';

import 'contract_files.dart';

GraineCallingWindow? expectedWindow(Object? raw) {
  if (raw == null) return null;
  final m = raw as Map<String, Object?>;
  return GraineCallingWindow(
    start: m['start']! as String,
    end: m['end']! as String,
    days: <int>[for (final d in m['days']! as List<Object?>) (d! as num).toInt()],
  );
}

CallsSetting callsWith(Map<String, Object?> scheduling) =>
    CallsSetting.fromJson(<String, Object?>{'hosted': true, 'scheduling': <String, Object?>{'usersCanBook': true, ...scheduling}})!;

void main() {
  late Map<String, Object?> contract;
  setUpAll(() async => contract = await contractJson('contract/booking-slots.json'));

  test('the file is the one the contract describes', () {
    expect(contract['stepMinutes'], 5);
    expect((contract['window']! as List<Object?>), isNotEmpty);
    expect((contract['slots']! as List<Object?>), isNotEmpty);
  });

  test('window: the session\'s callingWindow reads as every SDK reads it', () {
    for (final raw in contract['window']! as List<Object?>) {
      final c = raw! as Map<String, Object?>;
      final want = expectedWindow(c['window']);
      final calls = callsWith(<String, Object?>{'callingWindow': c['wire']});
      expect(calls.scheduling!.callingWindow, want, reason: c['name'] as String);
      expect(GraineSchedulingRules.of(calls).callingWindow, want, reason: '${c['name']} (the rules)');
    }
    expect(callsWith(<String, Object?>{}).scheduling!.callingWindow, isNull, reason: 'none in the session: no window');
  });

  test('slots: the times offered on the day, in the device\'s zone, inside the window', () {
    final cases = contract['slots']! as List<Object?>;
    for (final raw in cases) {
      final c = raw! as Map<String, Object?>;
      final name = c['name']! as String;
      final clock = BookingClock.offsets(<(DateTime, Duration)>[
        for (final o in (c['utcOffsets']! as List<Object?>).cast<Map<String, Object?>>())
          (DateTime.parse(o['from']! as String), Duration(minutes: (o['minutes']! as num).toInt())),
      ]);
      final rules = GraineSchedulingRules.of(callsWith(<String, Object?>{
        'minLeadMinutes': c['minLeadMinutes'],
        'maxDaysAhead': c['maxDaysAhead'],
        'callingWindow': c['callingWindow'],
      }));
      expect(rules.minLeadMinutes, c['minLeadMinutes'], reason: name);
      expect(rules.maxDaysAhead, c['maxDaysAhead'], reason: name);
      final ymd = (c['day']! as String).split('-').map(int.parse).toList();
      // Noon of that day on the zone's clock names the day.
      final day = clock.midnight(ymd[0], ymd[1], ymd[2]).add(const Duration(hours: 12));
      expect(clock.wall(day).day, ymd[2], reason: name);
      final now = DateTime.parse(c['now']! as String);
      final got = clock.slotsOn(rules, day, now).map((DateTime t) => t.millisecondsSinceEpoch).toList();
      final want = <int>[for (final s in c['slots']! as List<Object?>) DateTime.parse(s! as String).millisecondsSinceEpoch];
      expect(got, want, reason: name);

      // The sheet offers the same: that day's chip spans exactly these times.
      final offered = clock
          .days(Booking.bounds(rules, now), now, window: rules.callingWindow)
          .where((BookingDay d) => d.key == c['day'])
          .toList();
      if (want.isEmpty) {
        expect(offered, isEmpty, reason: '$name: no chip for a day with nothing to offer');
      } else {
        expect(offered, hasLength(1), reason: name);
        expect(offered.single.first.millisecondsSinceEpoch, want.first, reason: '$name: the chip\'s first time');
        expect(offered.single.last.millisecondsSinceEpoch, want.last, reason: '$name: the chip\'s last time');
      }
    }
    expect(cases.length, greaterThanOrEqualTo(15));
  });
}
