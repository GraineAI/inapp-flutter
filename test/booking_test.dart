// BOOKING A CALL FROM THE APP — the SDK's own booking sheet (BOOKING-SHEET.md):
// bookingAvailable for each rule; every option clamped to [now + lead rounded
// up to 5 minutes, now + days ahead rounded down to 5]; each refusal its one
// line, in the spec's words; a booking returned to the app; and "Book a
// call" in the chat window only where booking is available. HTTP and the
// device channel are mocks; nothing reaches a real host.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graine_inapp/graine_inapp.dart';
import 'package:graine_inapp/src/chat_window.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'device_mock.dart';

const String base = 'https://www.graine.ai';

Map<String, Object?> calls({
  bool hosted = true,
  List<Object?> platforms = const <Object?>[],
  bool usersCanBook = true,
  String? callName = 'Ring',
}) =>
    <String, Object?>{
      'hosted': hosted,
      'platforms': platforms,
      if (callName != null) 'callName': callName,
      'ringTimeoutSeconds': 45,
      'scheduling': <String, Object?>{
        'usersCanBook': usersCanBook,
        'maxDaysAhead': 2,
        'minLeadMinutes': 5,
        'maxPendingPerUser': 3,
      },
    };

Map<String, Object?> session({Map<String, Object?>? callsBody}) => <String, Object?>{
      'agentId': 'agent-1',
      'appearance': <String, Object?>{'mode': 'both', 'title': 'Asha'},
      'identity': <String, Object?>{'field': 'email', 'devicesPerUser': 2},
      'calls': callsBody ?? calls(),
    };

http.Response jsonResponse(Object? body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: const <String, String>{'content-type': 'application/json'},
    );

class Server {
  Server({Map<String, Object?>? session}) : session = session ?? _default();
  static Map<String, Object?> _default() => <String, Object?>{
        'agentId': 'agent-1',
        'appearance': <String, Object?>{'mode': 'both', 'title': 'Asha'},
        'identity': <String, Object?>{'field': 'email', 'devicesPerUser': 2},
        'calls': calls(),
      };

  Map<String, Object?> session;
  final List<Map<String, Object?>> booked = <Map<String, Object?>>[];

  /// A refusal for the next bookings: `{code, status}`.
  ({String code, int status})? refuse;

  late final http.Client client = MockClient((http.Request req) async {
    final body = req.body.isEmpty ? <String, Object?>{} : jsonDecode(req.body) as Map<String, Object?>;
    switch (req.url.path) {
      case '/api/embed/session':
        return jsonResponse(session);
      case '/api/embed/calls/schedule':
        final no = refuse;
        if (no != null) return jsonResponse(<String, Object?>{'error': 'Refused.', 'code': no.code}, no.status);
        final call = <String, Object?>{
          'id': 'sc_${booked.length + 1}', 'at': body['at'], 'status': 'scheduled', 'source': 'sdk', 'reason': body['reason'],
        };
        booked.add(<String, Object?>{...call, 'body': body});
        return jsonResponse(<String, Object?>{'call': call}, 201);
      case '/api/embed/calls/list':
        return jsonResponse(<String, Object?>{'calls': <Object?>[]});
    }
    return jsonResponse(<String, Object?>{'ok': true});
  });
}

/// An agent with the session read and the user signed in. On the test's
/// clock, which a sheet is handed too — or, with [wallClock], the device's,
/// which GraineBooking.show's sheet reads.
Future<GraineInApp> ready(WidgetTester tester, Server server, {bool identified = true, bool wallClock = false}) async {
  final g = GraineInApp.forTesting(
    const GraineConfig(baseUrl: base, publishableKey: 'pk_test_1'),
    httpClient: server.client,
    clock: wallClock ? null : () => tester.binding.clock.now().millisecondsSinceEpoch,
  );
  await g.loadSession();
  await g.installId;
  // The zone, read: the sheet names it.
  await g.memoryEnabled();
  if (identified) g.identify(<String, Object?>{'email': 'asha@example.com'});
  await tester.pump();
  return g;
}

/// Let a request to the mocked routes finish and the sheet redraw.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// A phone: 390 × 844 points.
void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Widget host(Widget child) => MaterialApp(home: Align(alignment: Alignment.bottomCenter, child: child));

/// Everything off screen, so no timer or ticker outlives the test.
Future<void> done(WidgetTester tester, GraineInApp g) async {
  await tester.pumpWidget(const SizedBox());
  g.dispose();
  await tester.pump(const Duration(milliseconds: 50));
}

String? lineOf(WidgetTester tester) {
  final f = find.byKey(GraineBookingSheet.lineKey);
  return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
}

void main() {
  setUp(() => DeviceMock().install());
  tearDown(DeviceMock.uninstall);

  final rules = GraineSchedulingRules.of(CallsSetting.fromJson(calls()));

  // ── the rules ────────────────────────────────────────────────────────────

  group('bookingAvailable, one rule per line', () {
    CallsSetting c([Map<String, Object?>? over]) => CallsSetting.fromJson(<String, Object?>{...calls(), ...?over})!;

    test('users may book, Graine rings this platform, and the user is identified', () {
      expect(Booking.available(c(), platform: 'ios', identified: true), isTrue);
      expect(Booking.available(c(), platform: 'android', identified: true), isTrue);
    });

    test('users may not book: off — and that is said before sign-in', () {
      final off = c(<String, Object?>{'scheduling': <String, Object?>{'usersCanBook': false}});
      expect(Booking.available(off, platform: 'ios', identified: true), isFalse);
      expect(Booking.blocker(off, platform: 'ios', identified: false), GraineErrorCode.schedulingOff);
      expect(Booking.available(null, platform: 'ios', identified: true), isFalse, reason: 'an older server: off');
    });

    test('not hosted, or the platforms leave this phone out', () {
      expect(Booking.available(c(<String, Object?>{'hosted': false}), platform: 'ios', identified: true), isFalse);
      expect(Booking.available(c(<String, Object?>{'platforms': <Object?>['android']}), platform: 'ios', identified: true), isFalse);
      expect(Booking.available(c(<String, Object?>{'platforms': <Object?>['android']}), platform: 'android', identified: true), isTrue);
      expect(Booking.available(c(<String, Object?>{'platforms': <Object?>[' IOS ']}), platform: 'ios', identified: true), isTrue);
      expect(Booking.available(c(), platform: null, identified: true), isFalse, reason: 'a platform Graine cannot ring');
    });

    test('a web page books for the app: neither hosted nor its platform counts', () {
      expect(Booking.available(c(<String, Object?>{'hosted': false, 'platforms': <Object?>['android']}), platform: 'web', identified: true), isTrue);
    });

    test('nobody identified: identityRequired, and the line says sign in', () {
      expect(Booking.blocker(c(), platform: 'ios', identified: false), GraineErrorCode.identityRequired);
      expect(Booking.errorLine(GraineErrorCode.identityRequired, rules), 'Sign in to book a call');
    });
  });

  group('the offer', () {
    test('earliest = now + lead rounded up to 5 minutes; latest = now + days ahead rounded down to 5', () {
      final b = Booking.bounds(rules, DateTime(2026, 10, 14, 17, 58, 37));
      expect(b.earliest, DateTime(2026, 10, 14, 18, 5));
      expect(b.latest, DateTime(2026, 10, 16, 17, 55));
      expect(Booking.bounds(rules, DateTime(2026, 10, 14, 17, 55)).earliest, DateTime(2026, 10, 14, 18, 0),
          reason: 'a time already on the grid stays');
    });

    test('the days: Today, Tomorrow, then the weekday and date; each day its first and last time', () {
      final now = DateTime(2026, 10, 14, 17, 58, 37);
      final days = Booking.days(Booking.bounds(rules, now), now);
      expect(days.map((BookingDay d) => d.label), <String>['Today', 'Tomorrow', 'Fri 16 Oct']);
      expect(days.map((BookingDay d) => d.key), <String>['2026-10-14', '2026-10-15', '2026-10-16']);
      expect(days[0].first, DateTime(2026, 10, 14, 18, 5));
      expect(days[0].last, DateTime(2026, 10, 14, 23, 55));
      expect(days[1].first, DateTime(2026, 10, 15));
      expect(days[2].last, DateTime(2026, 10, 16, 17, 55), reason: 'never past the latest');
    });

    test('late at night today has nothing left: the first chip is Tomorrow; nothing bookable, no day', () {
      final night = DateTime(2026, 10, 14, 23, 58);
      final one = GraineSchedulingRules.of(CallsSetting.fromJson(<String, Object?>{
        ...calls(),
        'scheduling': <String, Object?>{'usersCanBook': true, 'minLeadMinutes': 5, 'maxDaysAhead': 1},
      }));
      final days = Booking.days(Booking.bounds(one, night), night);
      expect(days.first.label, 'Tomorrow');
      expect(days.first.first, DateTime(2026, 10, 15, 0, 5));
      final never = GraineSchedulingRules.of(CallsSetting.fromJson(<String, Object?>{
        ...calls(),
        'scheduling': <String, Object?>{'usersCanBook': true, 'minLeadMinutes': 1440, 'maxDaysAhead': 1},
      }));
      expect(Booking.days(Booking.bounds(never, night), night), isEmpty);
    });

    test("a picker's answer: on the day chosen, on the 5-minute grid, clamped into the day", () {
      final now = DateTime(2026, 10, 14, 17, 58, 37);
      final today = Booking.days(Booking.bounds(rules, now), now).first;
      expect(Booking.onDay(today, 19, 32), DateTime(2026, 10, 14, 19, 30));
      expect(Booking.onDay(today, 19, 33), DateTime(2026, 10, 14, 19, 35));
      expect(Booking.onDay(today, 9, 0), today.first, reason: 'before the first time: the first');
      expect(Booking.clamp(DateTime(2026, 10, 20), Booking.bounds(rules, now)), DateTime(2026, 10, 16, 17, 55));
    });
  });

  group('the words', () {
    test('each refusal is its one line, in the spec words — and one is one', () {
      expect(Booking.errorLine(GraineErrorCode.tooSoon, rules), 'Pick a time at least 5 minutes from now');
      expect(Booking.errorLine(GraineErrorCode.tooFar, rules), 'Pick a time within 2 days');
      expect(Booking.errorLine(GraineErrorCode.outsideWindow, rules), 'That time is outside the hours we can call — pick another');
      expect(Booking.errorLine(GraineErrorCode.tooManyPending, rules), 'You already have 3 calls booked — cancel one first');
      expect(Booking.errorLine(GraineErrorCode.schedulingOff, rules), "Booking a call isn't available right now");
      expect(Booking.errorLine(GraineErrorCode.identityRequired, rules), 'Sign in to book a call');
      for (final code in <GraineErrorCode?>[
        GraineErrorCode.rateLimited, GraineErrorCode.unavailable, GraineErrorCode.network,
        GraineErrorCode.invalidKey, GraineErrorCode.deviceLimit, GraineErrorCode.notFound, GraineErrorCode.unknown, null,
      ]) {
        expect(Booking.errorLine(code, rules), "Couldn't book just now — try again", reason: '$code');
      }
      const ones = GraineSchedulingRules(usersCanBook: true, minLeadMinutes: 1, maxDaysAhead: 1, maxPendingPerUser: 1);
      expect(Booking.errorLine(GraineErrorCode.tooSoon, ones), 'Pick a time at least 1 minute from now');
      expect(Booking.errorLine(GraineErrorCode.tooFar, ones), 'Pick a time within 1 day');
      expect(Booking.errorLine(GraineErrorCode.tooManyPending, ones), 'You already have 1 call booked — cancel one first');
    });

    test('the confirmation always names the date — 14 Oct 2026 is a Wednesday — and the zone line', () {
      final at = DateTime(2026, 10, 14, 18);
      expect(Booking.doneLine('Acme', at, h24: false), 'Booked — Acme will call you on Wed 14 Oct, 6:00 PM');
      expect(Booking.doneLine('Acme', at, h24: true), 'Booked — Acme will call you on Wed 14 Oct, 18:00');
      expect(Booking.zoneLine(at, 'Asia/Kolkata', h24: false), 'Asia/Kolkata · Wed 14 Oct, 6:00 PM');
      expect(Booking.zoneLine(at, null, h24: false), 'Wed 14 Oct, 6:00 PM');
      expect(Booking.title, 'Book a call');
      expect(Booking.subtitle('Ring'), 'Ring will call you');
      expect(Booking.about, "What's it about? (optional)");
      expect(Booking.book, 'Book call');
      expect(Booking.done, 'Done');
      expect(Booking.web, "We'll ring you in the app");
    });

    test("who will call: the call name, else the chat's title, else the heading, else Assistant", () {
      expect(Booking.callName(<String?>['Ring', 'Asha from Acme', 'Acme']), 'Ring');
      expect(Booking.callName(<String?>[null, 'Asha from Acme', 'Acme']), 'Asha from Acme');
      expect(Booking.callName(<String?>[' ', '', 'Acme']), 'Acme');
      expect(Booking.callName(<String?>[null, null, null]), 'Assistant');
    });

    test("the chat's Book a call: where booking is available, and the design keeps the booked-calls piece", () {
      expect(ChatPieces.of(const <GraineChatTurn>[], bookingAvailable: true).book, isTrue);
      expect(ChatPieces.of(const <GraineChatTurn>[], bookingAvailable: false).book, isFalse);
      expect(ChatPieces.of(const <GraineChatTurn>[], showUpcomingCalls: false, bookingAvailable: true).book, isFalse);
    });
  });

  // ── the agent ────────────────────────────────────────────────────────────

  testWidgets('GraineInApp.bookingAvailable follows the session, the user and this platform', (WidgetTester tester) async {
    final server = Server();
    final g = GraineInApp.forTesting(const GraineConfig(baseUrl: base, publishableKey: 'pk_test_1'), httpClient: server.client);
    expect(g.bookingAvailable, isFalse, reason: 'no session yet');
    await g.loadSession();
    expect(g.bookingAvailable, isFalse, reason: 'nobody identified');
    expect(g.bookingBlocker, GraineErrorCode.identityRequired);
    final heard = <bool>[];
    g.bookingListenable.addListener(() => heard.add(g.bookingListenable.value));
    g.identify(<String, Object?>{'email': 'asha@example.com'});
    expect(g.bookingAvailable, isTrue);
    expect(heard.last, isTrue, reason: 'a widget hears it');
    g.identify(null);
    expect(g.bookingAvailable, isFalse);
    expect(heard.last, isFalse);
    await tester.pump(); // the sign-out goes out
    g.dispose();

    final iosOnly = Server(session: session(callsBody: calls(platforms: <Object?>['ios'])));
    final h = GraineInApp.forTesting(const GraineConfig(baseUrl: base, publishableKey: 'pk_test_1'), httpClient: iosOnly.client);
    await h.loadSession();
    h.identify(<String, Object?>{'email': 'asha@example.com'});
    expect(h.bookingAvailable, isFalse, reason: 'a test runs as Android; the workspace rings iOS only');
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      expect(h.bookingAvailable, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
    h.dispose();
    await tester.pump(const Duration(seconds: 1));
  });

  // ── the sheet ────────────────────────────────────────────────────────────

  testWidgets('the sheet: its title, the call name, a chip per day, the time, the zone, what it is about',
      (WidgetTester tester) async {
    phone(tester);
    final server = Server();
    final g = await ready(tester, server);
    final now = tester.binding.clock.now();
    await tester.pumpWidget(host(GraineBookingSheet(app: g, reason: '  Renewal  ', now: () => tester.binding.clock.now())));
    expect(find.text('Book a call'), findsOneWidget);
    expect(find.text('Ring will call you'), findsOneWidget);
    final days = Booking.days(Booking.bounds(g.schedulingRules, now), now);
    for (final d in days) {
      expect(find.byKey(GraineBookingSheet.dayKey(d.key)), findsOneWidget, reason: d.label);
    }
    expect(find.text(ChatTime.clock(days.first.first, h24: false)), findsOneWidget, reason: 'the earliest time offered');
    expect(tester.widget<Text>(find.byKey(GraineBookingSheet.zoneKey)).data, startsWith('Asia/Kolkata · '));
    expect(find.text("What's it about? (optional)"), findsOneWidget);
    expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, 'Renewal');
    expect(find.text('Book call'), findsOneWidget);
    expect(lineOf(tester), isNull);
    await done(tester, g);
  });

  testWidgets('Book call books the day chosen and its first time, says so with the date, and Done closes',
      (WidgetTester tester) async {
    phone(tester);
    final server = Server();
    final g = await ready(tester, server);
    GraineScheduledCall? booked;
    var closed = 0;
    await tester.pumpWidget(host(GraineBookingSheet(
      app: g,
      now: () => tester.binding.clock.now(),
      onBooked: (GraineScheduledCall c) => booked = c,
      onClose: () => closed++,
    )));
    final now = tester.binding.clock.now();
    final days = Booking.days(Booking.bounds(g.schedulingRules, now), now);
    await tester.tap(find.byKey(GraineBookingSheet.dayKey(days[1].key)));
    await tester.pump();
    await tester.tap(find.byKey(GraineBookingSheet.bookKey));
    await settle(tester);
    expect(server.booked, hasLength(1));
    final sent = server.booked.single['body']! as Map<String, Object?>;
    expect(ScheduledCalls.parseTime(sent['at']), days[1].first.toUtc(), reason: 'the day chosen, its first time');
    expect(sent['identity'], <String, Object?>{'value': 'asha@example.com'});
    expect(booked?.id, 'sc_1');
    expect(find.text(Booking.doneLine('Ring', days[1].first, h24: false)), findsOneWidget);
    expect(find.textContaining('on Today'), findsNothing);
    expect(find.byKey(GraineBookingSheet.bookKey), findsNothing, reason: 'the form gave way to the confirmation');
    await tester.tap(find.byKey(GraineBookingSheet.doneKey));
    expect(closed, 1);
    await done(tester, g);
  });

  for (final r in <({String code, int status, String line})>[
    (code: 'outside_window', status: 422, line: 'That time is outside the hours we can call — pick another'),
    (code: 'too_many_pending', status: 409, line: 'You already have 3 calls booked — cancel one first'),
    (code: 'scheduling_off', status: 403, line: "Booking a call isn't available right now"),
    (code: 'identity_required', status: 400, line: 'Sign in to book a call'),
    (code: 'rate_limited', status: 429, line: "Couldn't book just now — try again"),
    (code: 'unavailable', status: 503, line: "Couldn't book just now — try again"),
    (code: 'device_limit', status: 403, line: "Couldn't book just now — try again"),
  ]) {
    testWidgets('refused with ${r.code}: "${r.line}" under the button, and the form stays', (WidgetTester tester) async {
      phone(tester);
      final server = Server()..refuse = (code: r.code, status: r.status);
      final g = await ready(tester, server);
      await tester.pumpWidget(host(GraineBookingSheet(app: g, now: () => tester.binding.clock.now())));
      await tester.tap(find.byKey(GraineBookingSheet.bookKey));
      await settle(tester);
      expect(lineOf(tester), r.line);
      expect(find.byKey(GraineBookingSheet.bookKey), findsOneWidget);
      await done(tester, g);
    });
  }

  testWidgets('a too_soon refusal moves the offer back to the new earliest', (WidgetTester tester) async {
    phone(tester);
    final server = Server()..refuse = (code: 'too_soon', status: 422);
    final g = await ready(tester, server);
    await tester.pumpWidget(host(GraineBookingSheet(app: g, now: () => tester.binding.clock.now())));
    final now = tester.binding.clock.now();
    final days = Booking.days(Booking.bounds(g.schedulingRules, now), now);
    await tester.tap(find.byKey(GraineBookingSheet.dayKey(days.last.key)));
    await tester.pump();
    expect(find.text(ChatTime.clock(days.last.first, h24: false)), findsOneWidget);
    await tester.tap(find.byKey(GraineBookingSheet.bookKey));
    await settle(tester);
    expect(lineOf(tester), 'Pick a time at least 5 minutes from now');
    // The new earliest: the clock has moved on since the sheet opened.
    final later = tester.binding.clock.now();
    final again = Booking.days(Booking.bounds(g.schedulingRules, later), later);
    expect(find.text(ChatTime.clock(again.first.first, h24: false)), findsOneWidget, reason: 'back on the earliest');
    await done(tester, g);
  });

  testWidgets('opened where the user cannot book: it says why, and Book call does nothing', (WidgetTester tester) async {
    phone(tester);
    for (final c in <({Map<String, Object?> calls, bool identified, String line})>[
      (calls: calls(), identified: false, line: 'Sign in to book a call'),
      (calls: calls(usersCanBook: false), identified: true, line: "Booking a call isn't available right now"),
      (calls: calls(hosted: false), identified: true, line: "Booking a call isn't available right now"),
      (calls: calls(platforms: <Object?>['ios']), identified: true, line: "Booking a call isn't available right now"),
    ]) {
      final server = Server(session: session(callsBody: c.calls));
      final g = await ready(tester, server, identified: c.identified);
      await tester.pumpWidget(host(GraineBookingSheet(app: g, now: () => tester.binding.clock.now())));
      expect(lineOf(tester), c.line);
      await tester.tap(find.byKey(GraineBookingSheet.bookKey));
      await tester.pump();
      expect(server.booked, isEmpty, reason: 'nothing was asked');
      await done(tester, g);
    }
  });

  testWidgets("the time is Flutter's own picker — even in an app with no MaterialApp", (WidgetTester tester) async {
    phone(tester);
    final g = await ready(tester, Server());
    await tester.pumpWidget(WidgetsApp(
      color: const Color(0xFF000000),
      pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
          PageRouteBuilder<T>(settings: settings, pageBuilder: (BuildContext c, Animation<double> _, Animation<double> __) => builder(c)),
      home: Align(alignment: Alignment.bottomCenter, child: GraineBookingSheet(app: g, now: () => tester.binding.clock.now())),
    ));
    await tester.tap(find.byKey(GraineBookingSheet.timeKey));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await done(tester, g);
  });

  testWidgets('GraineBooking.show: the call after Done, null when closed unbooked', (WidgetTester tester) async {
    phone(tester);
    final server = Server();
    final g = await ready(tester, server, wallClock: true);
    late BuildContext page;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (BuildContext c) {
      page = c;
      return const SizedBox.expand();
    })));
    final closed = GraineBooking.show(page, app: g, reason: 'Delivery');
    await tester.pumpAndSettle();
    expect(find.byKey(GraineBookingSheet.sheetKey), findsOneWidget);
    expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, 'Delivery');
    await tester.tap(find.byKey(GraineBookingSheet.closeKey));
    await tester.pumpAndSettle();
    expect(await closed, isNull);

    final booked = GraineBooking.show(page, app: g);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(GraineBookingSheet.bookKey));
    await settle(tester);
    await tester.tap(find.byKey(GraineBookingSheet.doneKey));
    await tester.pumpAndSettle();
    final call = await booked;
    expect(call?.id, 'sc_1');
    expect(call?.status, GraineCallStatus.scheduled);
    await done(tester, g);
  });

  // ── the chat window ──────────────────────────────────────────────────────

  group("the chat window's Book a call", () {
    final look = ChatLook.appearance(dark: false, accent: const Color(0xFF318CE7), radius: 18, shadows: const <BoxShadow>[]);
    Widget chat({List<GraineScheduledCall> upcoming = const <GraineScheduledCall>[], bool available = true, VoidCallback? onBook}) =>
        MediaQuery(
          data: const MediaQueryData(size: Size(400, 800)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ChatWindow(
                look: look,
                heading: 'Assistant',
                messages: const <Caption>[],
                turns: const <GraineChatTurn>[],
                online: true,
                onSend: (String _) {},
                upcoming: upcoming,
                onCancelUpcoming: (String _) {},
                callName: 'Ring',
                bookingAvailable: available,
                onBook: onBook ?? () {},
              ),
            ),
          ),
        );
    final soon = GraineScheduledCall(id: 'c1', at: DateTime.now().add(const Duration(hours: 3)).toUtc());

    testWidgets('nothing booked: one Book a call row in the card\'s place, which opens the sheet', (WidgetTester tester) async {
      var opened = 0;
      await tester.pumpWidget(chat(onBook: () => opened++));
      expect(find.byKey(ChatWindow.bookKey), findsOneWidget);
      expect(find.text('Book a call'), findsOneWidget);
      expect(find.text('Ring will call you'), findsOneWidget);
      expect(find.byKey(ChatWindow.upcomingKey), findsNothing);
      await tester.tap(find.byKey(ChatWindow.bookKey));
      expect(opened, 1);
    });

    testWidgets('a call booked: the card, its row and Cancel, and Book a call in it', (WidgetTester tester) async {
      await tester.pumpWidget(chat(upcoming: <GraineScheduledCall>[soon]));
      expect(find.byKey(ChatWindow.upcomingKey), findsOneWidget);
      expect(find.text('Upcoming call'), findsOneWidget);
      expect(find.byKey(ChatWindow.cancelKey('c1')), findsOneWidget);
      expect(find.descendant(of: find.byKey(ChatWindow.upcomingKey), matching: find.byKey(ChatWindow.bookKey)), findsOneWidget);
    });

    testWidgets('booking not available: the card alone, or nothing', (WidgetTester tester) async {
      await tester.pumpWidget(chat(available: false));
      expect(find.byKey(ChatWindow.bookKey), findsNothing);
      await tester.pumpWidget(chat(upcoming: <GraineScheduledCall>[soon], available: false));
      expect(find.byKey(ChatWindow.upcomingKey), findsOneWidget);
      expect(find.byKey(ChatWindow.bookKey), findsNothing);
    });
  });

  // A sheet left open a while must not leave its clock behind it.
  testWidgets('the sheet keeps no timer once it is gone', (WidgetTester tester) async {
    phone(tester);
    final g = await ready(tester, Server());
    await tester.pumpWidget(host(GraineBookingSheet(app: g, now: () => tester.binding.clock.now())));
    await tester.pump(const Duration(seconds: 31));
    expect(find.text('Book call'), findsOneWidget);
    await done(tester, g);
  });
}
