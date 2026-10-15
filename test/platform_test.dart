// The in-app platform, wired: who the user is reaching the engine page and
// every request (contract §1.2–1.3), the memory choice kept for them, sign-out
// and forget, the calls they book (§4.2), the SDK's own text chat end to end
// against a fake socket — ticket, frames, turns, typing, offline sends,
// reconnects, components and actions — the bar and the full-screen chat
// drawing it, and the screen context's timing, actions and taps. HTTP is a
// mock; the device channel is a mock; nothing reaches a real host.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graine_inapp/graine_inapp.dart';
import 'package:graine_inapp/src/chat_window.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'device_mock.dart';

const String base = 'https://www.graine.ai';
const String gateway = 'wss://gateway.test/v1/embed';

Map<String, Object?> sessionBody({
  String field = 'email',
  bool usersCanBook = true,
  Map<String, Object?> appearance = const <String, Object?>{'mode': 'both', 'title': 'Asha'},
}) =>
    <String, Object?>{
      'agentId': 'agent-1',
      'webcallAgentId': 'webcall-1',
      'pageVersion': 'dpl_42',
      'appearance': appearance,
      'variables': <String, Object?>{'brand': 'Graine'},
      'identity': <String, Object?>{'field': field, 'devicesPerUser': 2},
      'memory': <String, Object?>{'enabled': true},
      'calls': <String, Object?>{
        'hosted': true,
        'platforms': <Object?>['android', 'ios'],
        'ringTimeoutSeconds': 45,
        'scheduling': <String, Object?>{
          'usersCanBook': usersCanBook,
          'maxDaysAhead': 14,
          'minLeadMinutes': 5,
          'maxPendingPerUser': 3,
        },
      },
    };

http.Response jsonResponse(Object? body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: const <String, String>{'content-type': 'application/json'},
    );

/// Graine, as far as the SDK can tell: the session, a ticket, and whatever a
/// test routes. Every request is kept.
class Server {
  Server({Map<String, Object?>? session}) : session = session ?? sessionBody();

  Map<String, Object?> session;
  final List<http.Request> requests = <http.Request>[];
  final Map<String, http.Response Function(Map<String, Object?> body)> routes =
      <String, http.Response Function(Map<String, Object?> body)>{};

  late final http.Client client = MockClient((http.Request req) async {
    requests.add(req);
    final path = req.url.path;
    final body = req.body.isEmpty ? <String, Object?>{} : jsonDecode(req.body) as Map<String, Object?>;
    if (path == '/api/embed/session') return jsonResponse(session);
    final route = routes[path];
    if (route != null) return route(body);
    if (path == '/api/embed/ticket') return jsonResponse(<String, Object?>{'ticket': 'tkt_1', 'wsUrl': gateway});
    return jsonResponse(<String, Object?>{'ok': true});
  });

  List<Map<String, Object?>> bodies(String path) => <Map<String, Object?>>[
        for (final r in requests)
          if (r.url.path == path) jsonDecode(r.body) as Map<String, Object?>,
      ];
}

/// One chat socket, as the chat session sees it.
class FakeSocket implements GraineChatSocket {
  FakeSocket(this.url, this.protocols);

  final Uri url;
  final List<String>? protocols;
  final StreamController<Object?> _in = StreamController<Object?>();
  final List<Map<String, Object?>> sent = <Map<String, Object?>>[];
  bool closed = false;

  @override
  Stream<Object?> get frames => _in.stream;

  @override
  void send(String data) => sent.add(jsonDecode(data) as Map<String, Object?>);

  @override
  Future<void> close() async {
    closed = true;
    if (!_in.isClosed) unawaited(_in.close());
  }

  void say(Map<String, Object?> frame) => _in.add(jsonEncode(frame));

  /// The server went away.
  void drop() => unawaited(_in.close());

  List<String> get types => <String>[for (final m in sent) m['type']! as String];
}

class Connector {
  final List<FakeSocket> sockets = <FakeSocket>[];
  bool fail = false;

  Future<GraineChatSocket> call(Uri url, List<String>? protocols) async {
    if (fail) throw StateError('offline');
    final s = FakeSocket(url, protocols);
    sockets.add(s);
    return s;
  }

  FakeSocket get last => sockets.last;
}

/// What a page receives.
class FakePage implements GraineEnginePage {
  late GraineEngineSink sink;
  final List<String> scripts = <String>[];

  @override
  void bind(GraineEngineSink s) => sink = s;
  @override
  void load(String url) {}
  @override
  void reload() {}
  @override
  void run(String javaScript) => scripts.add(javaScript);
  @override
  void dispose() {}

  List<Map<String, Object?>> get posted => <Map<String, Object?>>[
        for (final js in scripts)
          if (js.startsWith('window.postMessage('))
            jsonDecode(js.substring('window.postMessage('.length, js.lastIndexOf(', "*")'))) as Map<String, Object?>,
      ];

  List<Map<String, Object?>> ofType(String type) =>
      <Map<String, Object?>>[for (final m in posted) if (m['type'] == type) m];

  void say(Map<String, Object?> message) => sink.message(jsonEncode(message));
}

class Heard with GraineListener {
  final List<String> volunteered = <String>[];
  final List<String> errors = <String>[];

  @override
  void onAgentVolunteered(String text) => volunteered.add(text);

  @override
  void onError(String message) => errors.add(message);
}

GraineInApp makeApp(WidgetTester tester, Server server,
        {Connector? connector, bool install = false, GraineConfig? config}) =>
    GraineInApp.forTesting(
      config ?? const GraineConfig(baseUrl: base, publishableKey: 'pk_test_1', appVersion: '2.4.0'),
      httpClient: server.client,
      clock: () => tester.binding.clock.now().millisecondsSinceEpoch,
      chatConnector: connector?.call,
      install: install,
    );

/// Stop everything and let a hang-up's last timer run.
Future<void> finish(WidgetTester tester, GraineInApp g) async {
  if (identical(GraineInApp.maybeInstance, g)) {
    GraineInApp.resetForTesting();
  } else {
    g.dispose();
  }
  await tester.pump(const Duration(milliseconds: 300));
}

/// A chat, connected.
Future<FakeSocket> connected(WidgetTester tester, GraineInApp g, Connector c) async {
  g.chat.open();
  await tester.pump();
  await tester.pump();
  expect(g.chat.connected, isTrue, reason: 'the chat did not connect');
  return c.last;
}

void main() {
  late DeviceMock device;
  setUp(() {
    device = DeviceMock()..install();
  });
  tearDown(DeviceMock.uninstall);

  group('who the user is', () {
    testWidgets("the configured trait reaches the page raw — the variables keep it masked; a placeholder is anonymous",
        (WidgetTester tester) async {
      final g = makeApp(tester, Server());
      g.identify(<String, Object?>{'name': 'Asha', 'email': 'asha@example.com'});
      final page = FakePage();
      g.voice.attach(page);
      await tester.pump();
      page.say(<String, Object?>{'type': 'graine:ready'});
      expect(page.ofType('graine:identity').single, <String, Object?>{
        'type': 'graine:identity',
        'value': 'asha@example.com',
        'installId': testInstallId,
        'memory': true,
        'timezone': 'Asia/Kolkata',
      });
      final vars = page.ofType('graine:variables').single['variables']! as Map<String, Object?>;
      expect(vars.containsKey('email'), isFalse, reason: 'the identifying trait is never a variable, masked or not');
      expect(vars['name'], 'Asha');

      g.identify(<String, Object?>{'email': '[EMAIL]'});
      await tester.pump();
      expect(page.ofType('graine:identity').last['value'], isNull, reason: 'a masked value identifies nobody');
      await finish(tester, g);
    });

    testWidgets('identify before the session: the trait is resolved when the setting arrives', (WidgetTester tester) async {
      final g = makeApp(tester, Server(session: sessionBody(field: 'patient_id')));
      g.identify(<String, Object?>{'Patient_ID': 'MRN-000981', 'email': 'asha@example.com'});
      await tester.pump();
      expect(await g.memoryEnabled(), isTrue);
      final page = FakePage();
      g.voice.attach(page);
      await tester.pump();
      page.say(<String, Object?>{'type': 'graine:ready'});
      expect(page.ofType('graine:identity').single['value'], 'MRN-000981');
      await finish(tester, g);
    });

    testWidgets('memory off is kept for that user: the next launch need not say it again', (WidgetTester tester) async {
      final server = Server();
      final g = makeApp(tester, server);
      g.identify(<String, Object?>{'email': 'Asha@Example.com'}, memory: false);
      await tester.pump();
      expect(await g.memoryEnabled(), isFalse);
      final kept = device.prefs['memory']! as Map<String, Object?>;
      expect(kept, <String, Object?>{Identity.memoryKey('email', 'asha@example.com'): false},
          reason: "under the iOS SDK's fingerprint of the normalised value");
      expect(jsonEncode(device.prefs), isNot(contains('asha')), reason: 'the identifier is never written down');
      await finish(tester, g);

      // The next launch, the same device — the address typed another way.
      final again = makeApp(tester, server);
      again.identify(<String, Object?>{'email': 'asha@example.com'});
      await tester.pump();
      expect(await again.memoryEnabled(), isFalse, reason: "the user's own last choice");
      again.identify(<String, Object?>{'email': 'ravi@example.com'});
      expect(await again.memoryEnabled(), isTrue, reason: 'someone else: on until they choose');
      again.setMemory(false);
      expect(await again.memoryEnabled(), isFalse);
      await finish(tester, again);
    });

    testWidgets('setMemory reaches the page at once', (WidgetTester tester) async {
      final g = makeApp(tester, Server());
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      final page = FakePage();
      g.voice.attach(page);
      await tester.pump();
      page.say(<String, Object?>{'type': 'graine:ready'});
      g.setMemory(false);
      expect(page.ofType('graine:identity').last['memory'], isFalse);
      await finish(tester, g);
    });

    testWidgets('sign-out: Graine is told who left, and their chat ends with its transcript', (WidgetTester tester) async {
      final server = Server();
      final c = Connector();
      final g = makeApp(tester, server, connector: c);
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      final first = await connected(tester, g, c);
      g.chat.send('Hi');
      expect(g.chat.messages, isNotEmpty);

      g.identify(null);
      await tester.pump();
      await tester.pump();
      final out = server.bodies('/api/embed/identity/signout').single;
      expect(out['identity'], <String, Object?>{'value': 'asha@example.com'});
      expect(out['installId'], testInstallId);
      expect(out['publishableKey'], 'pk_test_1');
      expect(first.types.last, 'stop', reason: 'the open conversation was theirs');
      expect(g.chat.messages, isEmpty, reason: "the next person must not read the last one's chat");
      expect(c.sockets, hasLength(2), reason: 'still in the chat: a new conversation, anonymous');
      expect(server.bodies('/api/embed/ticket').last.containsKey('identity'), isFalse);
      await finish(tester, g);
    });

    testWidgets('someone else signing in without a sign-out first signs the last user out', (WidgetTester tester) async {
      final server = Server();
      final c = Connector();
      final g = makeApp(tester, server, connector: c);
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      await connected(tester, g, c);
      g.chat.send('Hi');
      g.identify(<String, Object?>{'email': 'ravi@example.com'});
      await tester.pump();
      await tester.pump();
      expect(server.bodies('/api/embed/identity/signout').single['identity'], <String, Object?>{'value': 'asha@example.com'});
      expect(g.chat.messages, isEmpty, reason: "Ravi must not read Asha's chat");
      expect(server.bodies('/api/embed/ticket').last['identity'], <String, Object?>{'value': 'ravi@example.com'});
      g.identify(<String, Object?>{'email': 'ravi@example.com', 'name': 'Ravi'});
      await tester.pump();
      expect(server.bodies('/api/embed/identity/signout'), hasLength(1), reason: 'the same user with another trait is not a switch');
      await finish(tester, g);
    });

    testWidgets('anonymous to identified keeps the open conversation (the change reaches the next one)',
        (WidgetTester tester) async {
      final c = Connector();
      final g = makeApp(tester, Server(), connector: c);
      await connected(tester, g, c);
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      await tester.pump();
      expect(c.sockets, hasLength(1));
      expect(c.last.types, isNot(contains('stop')));
      await finish(tester, g);
    });

    testWidgets('forgetMemory: the user, from this install, and how many went — nobody identified is refused',
        (WidgetTester tester) async {
      final server = Server();
      server.routes['/api/embed/memory/forget'] = (Map<String, Object?> _) => jsonResponse(<String, Object?>{'deleted': 3});
      final g = makeApp(tester, server);
      await expectLater(g.forgetMemory(),
          throwsA(isA<GraineException>().having((GraineException e) => e.code, 'code', GraineErrorCode.identityRequired)));
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      expect(await g.forgetMemory(), 3);
      final body = server.bodies('/api/embed/memory/forget').single;
      expect(body['identity'], <String, Object?>{'value': 'asha@example.com'});
      expect(body['installId'], testInstallId);
      expect(body['memory'], isTrue);
      expect(body['timezone'], 'Asia/Kolkata');
      await finish(tester, g);
    });

    testWidgets('memories: what the agent remembers about this user, newest first — refusals typed',
        (WidgetTester tester) async {
      final server = Server();
      server.routes['/api/embed/memory/list'] = (Map<String, Object?> _) => jsonResponse(<String, Object?>{
            'memories': <Object?>[
              <String, Object?>{'id': 'm2', 'text': 'Prefers calls after 6 pm', 'createdAt': '2026-10-12T10:00:00Z', 'updatedAt': null},
              <String, Object?>{'id': 'm1', 'text': 'Drives a Creta', 'createdAt': null, 'updatedAt': '2026-10-01T08:00:00Z'},
              <String, Object?>{'text': 'no id: not a memory'},
            ],
          });
      final g = makeApp(tester, server);
      await expectLater(
          g.memories(), throwsA(isA<GraineException>().having((GraineException e) => e.code, 'code', GraineErrorCode.identityRequired)));
      expect(server.bodies('/api/embed/memory/list'), isEmpty, reason: 'nobody identified: nothing asked');
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      final memories = await g.memories();
      expect(memories.map((GraineMemory m) => m.id), <String>['m2', 'm1'], reason: "the server's order: newest first");
      expect(memories.first.text, 'Prefers calls after 6 pm');
      expect(memories.first.createdAt, DateTime.utc(2026, 10, 12, 10));
      expect(memories.last.updatedAt, DateTime.utc(2026, 10, 1, 8));
      final body = server.bodies('/api/embed/memory/list').single;
      expect(body['publishableKey'], 'pk_test_1');
      expect(body['identity'], <String, Object?>{'value': 'asha@example.com'});
      expect(body['installId'], testInstallId);

      server.routes['/api/embed/memory/list'] = (Map<String, Object?> _) =>
          jsonResponse(<String, Object?>{'error': 'This device is not one of theirs.', 'code': 'device_limit'}, 403);
      await expectLater(
        g.memories(),
        throwsA(isA<GraineException>()
            .having((GraineException e) => e.code, 'code', GraineErrorCode.deviceLimit)
            .having((GraineException e) => e.message, 'message', 'This device is not one of theirs.')),
      );
      await finish(tester, g);
    });

    testWidgets("installId is the platform's", (WidgetTester tester) async {
      final g = makeApp(tester, Server());
      expect(await g.installId, testInstallId);
      await finish(tester, g);
    });
  });

  test('with no platform side, the install id is a UUID kept for this run', () async {
    DeviceMock.uninstall();
    final g = GraineInApp.forTesting(const GraineConfig(baseUrl: base, publishableKey: 'pk_test_1'),
        httpClient: MockClient((http.Request _) async => http.Response('{}', 404)));
    final id = await g.installId;
    expect(Identity.normaliseInstallId(id), id);
    expect(await g.installId, id, reason: 'one per run');
    g.dispose();
  });

  group('the calls a user books', () {
    /// [hours] from the test's clock, to the second (the wire's precision).
    DateTime fromNow(WidgetTester tester, {int hours = 0, int minutes = 0, int days = 0}) {
      final now = tester.binding.clock.now().toUtc();
      final t = now.add(Duration(days: days, hours: hours, minutes: minutes));
      return DateTime.utc(t.year, t.month, t.day, t.hour, t.minute, t.second);
    }

    testWidgets('scheduleCall: the time with its offset, the reason, who and where — and the booking back',
        (WidgetTester tester) async {
      final server = Server();
      server.routes['/api/embed/calls/schedule'] = (Map<String, Object?> body) => jsonResponse(<String, Object?>{
            'call': <String, Object?>{'id': 'sc_1', 'at': body['at'], 'status': 'scheduled', 'source': 'sdk', 'reason': body['reason']},
          }, 201);
      final g = makeApp(tester, server);
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      final at = fromNow(tester, hours: 3);
      final call = await g.scheduleCall(at: at, reason: '  KYC follow-up  ');
      expect(call.id, 'sc_1');
      expect(call.at, at);
      expect(call.status, GraineCallStatus.scheduled);
      expect(call.source, GraineCallSource.app);
      expect(call.reason, 'KYC follow-up');
      expect(call.canCancel, isTrue);
      final wire = server.bodies('/api/embed/calls/schedule').single['at']! as String;
      expect(wire, matches(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(Z|[+-]\d\d:\d\d)$')), reason: 'with an offset');
      expect(ScheduledCalls.parseTime(wire), at);
      expect(server.bodies('/api/embed/calls/schedule').single, <String, Object?>{
        'publishableKey': 'pk_test_1',
        'at': wire,
        'reason': 'KYC follow-up',
        'identity': <String, Object?>{'value': 'asha@example.com'},
        'installId': testInstallId,
        'memory': true,
        'timezone': 'Asia/Kolkata',
      });
      await finish(tester, g);
    });

    testWidgets('checked here first — off, too soon, too far, a long reason — and nothing asked', (WidgetTester tester) async {
      final server = Server();
      final g = makeApp(tester, server);
      Matcher refused(GraineErrorCode code) =>
          throwsA(isA<GraineException>().having((GraineException e) => e.code, 'code', code));
      // In the booking sheet's words, as every SDK says them.
      Matcher says(GraineErrorCode code, String line) => throwsA(isA<GraineException>()
          .having((GraineException e) => e.code, 'code', code)
          .having((GraineException e) => e.message, 'message', line));
      await expectLater(
          g.scheduleCall(at: fromNow(tester, minutes: 4)), says(GraineErrorCode.tooSoon, 'Pick a time at least 5 minutes from now'));
      await expectLater(g.scheduleCall(at: fromNow(tester, days: 14, minutes: 1)),
          says(GraineErrorCode.tooFar, 'Pick a time within 14 days'));
      await expectLater(g.scheduleCall(at: fromNow(tester, hours: 1), reason: 'x' * 121), refused(GraineErrorCode.invalidRequest));
      expect(g.schedulingRules.earliest(DateTime.utc(2026, 10, 13, 9)), DateTime.utc(2026, 10, 13, 9, 5));
      expect(server.bodies('/api/embed/calls/schedule'), isEmpty, reason: 'nothing asked that would be refused');
      await finish(tester, g);

      final off = Server(session: sessionBody(usersCanBook: false));
      final h = makeApp(tester, off);
      await expectLater(h.scheduleCall(at: fromNow(tester, hours: 3)),
          says(GraineErrorCode.schedulingOff, "Booking a call isn't available right now"));
      expect(off.bodies('/api/embed/calls/schedule'), isEmpty);
      await finish(tester, h);

      final older = Server(session: <String, Object?>{...sessionBody()}..remove('calls'));
      final o = makeApp(tester, older);
      await expectLater(o.scheduleCall(at: fromNow(tester, hours: 3)), refused(GraineErrorCode.schedulingOff),
          reason: 'a server that says nothing allows no booking');
      expect(o.schedulingRules.usersCanBook, isFalse);
      await finish(tester, o);
    });

    testWidgets("Graine's refusal is its typed code and sentence; a rate limit says how long to wait",
        (WidgetTester tester) async {
      final server = Server();
      server.routes['/api/embed/calls/schedule'] = (Map<String, Object?> _) =>
          jsonResponse(<String, Object?>{'error': 'That time is outside the calling hours.', 'code': 'outside_window'}, 409);
      final g = makeApp(tester, server);
      await expectLater(
        g.scheduleCall(at: fromNow(tester, hours: 3)),
        throwsA(isA<GraineException>()
            .having((GraineException e) => e.code, 'code', GraineErrorCode.outsideWindow)
            .having((GraineException e) => e.codeName, 'codeName', 'outside_window')
            .having((GraineException e) => e.statusCode, 'status', 409)
            .having((GraineException e) => e.message, 'message', 'That time is outside the calling hours.')),
      );
      server.routes['/api/embed/calls/schedule'] = (Map<String, Object?> _) => http.Response.bytes(
          utf8.encode(jsonEncode(<String, Object?>{'error': 'Slow down.', 'code': 'rate_limited'})), 429,
          headers: const <String, String>{'content-type': 'application/json', 'retry-after': '20'});
      await expectLater(
        g.scheduleCall(at: fromNow(tester, hours: 3)),
        throwsA(isA<GraineException>()
            .having((GraineException e) => e.code, 'code', GraineErrorCode.rateLimited)
            .having((GraineException e) => e.retryAfterSeconds, 'retryAfterSeconds', 20)),
      );
      await finish(tester, g);
    });

    testWidgets("scheduledCalls lists in Graine's order; cancelScheduledCall names the call and says where it is now",
        (WidgetTester tester) async {
      final server = Server();
      server.routes['/api/embed/calls/list'] = (Map<String, Object?> _) => jsonResponse(<String, Object?>{
            'calls': <Object?>[
              <String, Object?>{'id': 'b', 'at': '2026-10-15T09:00:00Z', 'status': 'scheduled'},
              <String, Object?>{'id': 'a', 'at': '2026-10-14T09:00:00Z', 'status': 'ringing'},
            ],
          });
      server.routes['/api/embed/calls/cancel'] = (Map<String, Object?> _) =>
          jsonResponse(<String, Object?>{'ok': true, 'status': 'cancelled'});
      final g = makeApp(tester, server);
      final calls = await g.scheduledCalls();
      expect(calls.map((GraineScheduledCall c) => c.id), <String>['b', 'a'], reason: "the server's order");
      expect(calls.last.isUpcoming, isTrue);
      expect(calls.last.canCancel, isFalse, reason: 'ringing');
      expect(server.bodies('/api/embed/calls/list').single['installId'], testInstallId);
      expect(server.bodies('/api/embed/calls/list').single.containsKey('identity'), isFalse, reason: 'nobody identified');
      expect(await g.cancelScheduledCall('b'), GraineCallStatus.cancelled);
      expect(server.bodies('/api/embed/calls/cancel').single['callId'], 'b');
      server.routes['/api/embed/calls/cancel'] = (Map<String, Object?> _) =>
          jsonResponse(<String, Object?>{'error': 'No such call.', 'code': 'not_found'}, 404);
      await expectLater(g.cancelScheduledCall('zz'),
          throwsA(isA<GraineException>().having((GraineException e) => e.code, 'code', GraineErrorCode.notFound)));
      await finish(tester, g);
    });

    testWidgets('Graine out of reach is the code network', (WidgetTester tester) async {
      final server = Server();
      server.routes['/api/embed/calls/list'] = (Map<String, Object?> _) => throw http.ClientException('no route to host');
      final g = makeApp(tester, server);
      await expectLater(g.scheduledCalls(),
          throwsA(isA<GraineException>().having((GraineException e) => e.code, 'code', GraineErrorCode.network)));
      await finish(tester, g);
    });

    testWidgets("a key Graine rejects is the session's own refusal on every request", (WidgetTester tester) async {
      final server = Server();
      final rejecting = MockClient((http.Request req) async {
        if (req.url.path == '/api/embed/session') {
          return jsonResponse(<String, Object?>{'error': 'Unknown key', 'code': 'invalid_key'}, 401);
        }
        return server.client.post(req.url, body: req.body);
      });
      final g = GraineInApp.forTesting(const GraineConfig(baseUrl: base, publishableKey: 'pk_test_1'),
          httpClient: rejecting, clock: () => tester.binding.clock.now().millisecondsSinceEpoch);
      await expectLater(g.scheduledCalls(),
          throwsA(isA<GraineException>().having((GraineException e) => e.code, 'code', GraineErrorCode.invalidKey)));
      expect(server.bodies('/api/embed/calls/list'), isEmpty);
      await finish(tester, g);
    });
  });

  group('the chat', () {
    testWidgets('a text ticket with who the user is; the gateway with the subprotocol; init, the screen, a ping every 25 s',
        (WidgetTester tester) async {
      final server = Server();
      final c = Connector();
      final g = makeApp(tester, server, connector: c);
      g.identify(<String, Object?>{'name': 'Asha', 'email': 'asha@example.com'}, memory: false);
      g.setScreen(const GraineScreen('kyc_pan', fields: <GraineField>[GraineField('pan', value: 'ABCDE1234F')]));
      final s = await connected(tester, g, c);

      final ticket = server.bodies('/api/embed/ticket').single;
      expect(ticket['publishableKey'], 'pk_test_1');
      expect(ticket['mode'], 'text', reason: 'a voice ticket opens a call pipeline; the chat would be deaf');
      expect(ticket['identity'], <String, Object?>{'value': 'asha@example.com'});
      expect(ticket['installId'], testInstallId);
      expect(ticket['memory'], isFalse);
      expect(ticket['timezone'], 'Asia/Kolkata');
      expect((ticket['metadata']! as Map<String, Object?>).containsKey('email'), isFalse,
          reason: 'the identifying trait rides only as identity');
      expect((ticket['metadata']! as Map<String, Object?>)['name'], 'Asha');
      expect(ticket.containsKey('callId'), isFalse);

      expect(s.protocols, <String>['graine.embed.v1', 'tkt_1'], reason: 'the ticket in the subprotocol, never the URL');
      expect(s.url.toString(), gateway,
          reason: 'the variables ride the ticket: the gateway reads nothing off its URL, and a query reaches the access logs');
      expect(s.types, <String>['init', 'app_context']);
      expect((s.sent.first['meta_data']! as Map<String, Object?>)['client'], 'graine-flutter-sdk');
      final context = s.sent[1]['context']! as Map<String, Object?>;
      expect(context['screen'], 'kyc_pan');
      expect(((context['fields']! as List<Object?>).single! as Map<String, Object?>)['value'], '[PAN]');

      await tester.pump(const Duration(seconds: 25));
      expect(s.types.last, 'ping');
      await finish(tester, g);
    });

    testWidgets('no gateway: the runtime directly, as a text chat, with the variables on the URL',
        (WidgetTester tester) async {
      final server = Server();
      server.routes['/api/embed/ticket'] = (Map<String, Object?> _) => jsonResponse(<String, Object?>{'error': 'no gateway'}, 503);
      final c = Connector();
      final g = makeApp(tester, server, connector: c);
      final s = await connected(tester, g, c);
      expect(s.protocols, isNull);
      expect(s.url.toString(), startsWith('wss://ws.graine.ai/chat/v1/webcall-1?text_chat=1&context_token='));
      final token = Uri.decodeComponent(s.url.queryParameters['context_token']!);
      expect((jsonDecode(utf8.decode(base64.decode(token))) as Map<String, Object?>)['call_type'], 'text_chat');
      await finish(tester, g);
    });

    testWidgets('one bubble per agent turn, typing until its first word, ended on its marker', (WidgetTester tester) async {
      final c = Connector();
      final heard = Heard();
      final g = makeApp(tester, Server(), connector: c)..addListener(heard);
      final s = await connected(tester, g, c);
      s.say(<String, Object?>{'type': 'text', 'data': '<beginning_of_stream>Hello! '});
      s.say(<String, Object?>{'type': 'text', 'data': 'How can I help?'});
      s.say(<String, Object?>{'type': 'text', 'data': '<end_of_stream>'});
      await tester.pump();
      expect(heard.volunteered, <String>['Hello! '], reason: 'the welcome: the agent spoke first');
      expect(g.chat.agentTyping, isFalse);

      g.chat.send('Where is my card?');
      expect(s.sent.last, <String, Object?>{'type': 'text', 'data': 'Where is my card?'});
      expect(g.chat.agentTyping, isTrue);
      s.say(<String, Object?>{'type': 'text', 'data': 'It shipped '});
      await tester.pump();
      expect(g.chat.agentTyping, isFalse);
      s.say(<String, Object?>{'type': 'text', 'data': 'yesterday.<end_of_stream>'});
      s.say(<String, Object?>{'type': 'text', 'data': 'Anything else?'});
      s.say(<String, Object?>{'type': 'end_of_stream'});
      await tester.pump();
      expect(
        g.chat.messages.map((Caption m) => '${m.role.name}: ${m.text}'),
        <String>['agent: Hello! How can I help?', 'customer: Where is my card?', 'agent: It shipped yesterday.', 'agent: Anything else?'],
      );
      expect(g.chat.messages.any((Caption m) => m.live), isFalse);
      expect(heard.volunteered, hasLength(2), reason: '"Anything else?" was not asked for');
      await finish(tester, g);
    });

    testWidgets('typed while offline: shown at once, sent the moment it connects', (WidgetTester tester) async {
      final c = Connector()..fail = true;
      final g = makeApp(tester, Server(), connector: c);
      g.chat.send('Hello?');
      expect(g.chat.turns.single.delivery, GraineChatDelivery.sending);
      expect(g.chat.isOpen, isTrue, reason: 'a message opens the chat');
      await tester.pump();
      expect(g.chat.connected, isFalse);
      c.fail = false;
      await tester.pump(const Duration(milliseconds: 1300)); // the first rung of the backoff
      await tester.pump();
      expect(g.chat.connected, isTrue);
      expect(c.last.sent.where((Map<String, Object?> m) => m['type'] == 'text').single['data'], 'Hello?');
      expect(g.chat.turns.single.delivery, GraineChatDelivery.sent);
      expect(g.chat.agentTyping, isTrue);
      await finish(tester, g);
    });

    testWidgets('a drop while in the chat reconnects with backoff; leaving hangs up cleanly', (WidgetTester tester) async {
      final c = Connector();
      final g = makeApp(tester, Server(), connector: c);
      final first = await connected(tester, g, c);
      first.say(<String, Object?>{'type': 'text', 'data': 'Hello'});
      expect(g.chat.reconnecting, isFalse);
      first.drop();
      await tester.pump();
      expect(g.chat.connected, isFalse);
      expect(g.chat.connecting, isTrue, reason: 'a reconnect is on its way');
      expect(g.chat.reconnecting, isTrue, reason: '"Reconnecting…", not "Offline"');
      expect(g.chat.failed, isFalse);
      expect(g.chat.messages.single.live, isFalse, reason: 'nothing more of that turn is coming');
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pump();
      expect(c.sockets, hasLength(2));
      expect(g.chat.connected, isTrue);
      expect(g.chat.reconnecting, isFalse, reason: 'back');

      g.chat.close();
      expect(c.last.types.last, 'stop');
      expect(c.last.closed, isFalse, reason: 'the stop frame is given time to leave');
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.last.closed, isTrue);
      expect(g.chat.connected, isFalse);
      await tester.pump(const Duration(seconds: 30));
      expect(c.sockets, hasLength(2), reason: 'a chat the customer left never reconnects');
      await finish(tester, g);
    });

    testWidgets('every retry spent: failed, no longer reconnecting; a message asks again as a fresh connect',
        (WidgetTester tester) async {
      final c = Connector();
      final g = makeApp(tester, Server(), connector: c);
      final first = await connected(tester, g, c);
      c.fail = true;
      first.drop();
      await tester.pump();
      expect(g.chat.reconnecting, isTrue);
      // The whole ladder (1, 2, 4, 8, 15, 15 s, jittered), every try refused.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(seconds: 20));
        await tester.pump();
      }
      expect(g.chat.failed, isTrue);
      expect(g.chat.reconnecting, isFalse, reason: 'given up is not reconnecting');
      expect(g.chat.connecting, isFalse);

      c.fail = false;
      g.chat.send('Still there?');
      expect(g.chat.connecting, isTrue);
      expect(g.chat.reconnecting, isFalse, reason: 'asked again after giving up: a fresh connect');
      await tester.pump();
      await tester.pump();
      expect(g.chat.connected, isTrue);
      await finish(tester, g);
    });

    testWidgets('a first connect that fails is retried as a reconnect; leaving ends it', (WidgetTester tester) async {
      final c = Connector()..fail = true;
      final g = makeApp(tester, Server(), connector: c);
      g.chat.open();
      expect(g.chat.reconnecting, isFalse, reason: 'the first try is connecting');
      await tester.pump();
      await tester.pump();
      expect(g.chat.reconnecting, isTrue);
      g.chat.close();
      expect(g.chat.reconnecting, isFalse);
      expect(g.chat.connecting, isFalse);
      await finish(tester, g);
    });

    testWidgets('components drawn in the chat are answered in the chat', (WidgetTester tester) async {
      final c = Connector();
      final g = makeApp(tester, Server(), connector: c);
      final page = FakePage();
      g.voice.attach(page);
      await tester.pump();
      final s = await connected(tester, g, c);
      s.say(<String, Object?>{'type': 'widget_pending', 'widget': <String, Object?>{'widget_id': 'w1', 'kind': 'choices'}});
      await tester.pump();
      expect(g.components.loading?.kind, 'choices');
      s.say(<String, Object?>{
        'type': 'widget',
        'widget': <String, Object?>{
          'widget_id': 'w1',
          'kind': 'choices',
          'data': <String, Object?>{'options': <Object?>['Yes', 'No']},
        },
      });
      await tester.pump(const Duration(milliseconds: Widgets.minLoaderMs));
      expect(g.components.widget?.id, 'w1');
      g.components.answer(g.components.content!.pickChip(g.components.content!.chips.first));
      expect(s.sent[s.sent.length - 2], <String, Object?>{
        'type': 'widget_result',
        'widget_id': 'w1',
        'data': <String, Object?>{'chosen': 'Yes', 'label': 'Yes'},
      });
      expect(s.sent.last['type'], 'text', reason: 'the sentence, or the conversation does not move');
      expect(page.ofType('graine:widget-result'), isEmpty, reason: 'not the call: it did not draw it');
      expect(g.chat.agentTyping, isTrue);
      await finish(tester, g);
    });

    testWidgets("the agent's action runs in the app and is answered on the socket", (WidgetTester tester) async {
      final c = Connector();
      final g = makeApp(tester, Server(), connector: c);
      g.registerAction('open_screen', (Map<String, Object?> args) async => ActionResult.ok('Opened ${args['path']}.'));
      final s = await connected(tester, g, c);
      s.say(<String, Object?>{
        'type': 'app_action',
        'action': <String, Object?>{'action_id': 'a1', 'name': 'open_screen', 'arguments': <String, Object?>{'path': '/billing'}},
      });
      s.say(<String, Object?>{
        'type': 'app_action',
        'action': <String, Object?>{'action_id': 'a2', 'name': 'not_built', 'arguments': <String, Object?>{}},
      });
      await tester.pump();
      final results = <Map<String, Object?>>[for (final m in s.sent) if (m['type'] == 'app_action_result') m];
      expect(results.first, <String, Object?>{
        'type': 'app_action_result',
        'action_id': 'a1',
        'status': 'ok',
        'message': 'Opened /billing.',
      });
      expect(results.last['status'], 'refused');
      await finish(tester, g);
    });

    testWidgets('the screen reaches the chat as it changes; a dismissal reaches it as a quiet event',
        (WidgetTester tester) async {
      final c = Connector();
      final g = makeApp(tester, Server(), connector: c);
      final s = await connected(tester, g, c);
      g.setScreen(const GraineScreen('billing'));
      expect((s.sent.last['context']! as Map<String, Object?>)['screen'], 'billing', reason: 'at once');
      s.say(<String, Object?>{
        'type': 'widget',
        'widget': <String, Object?>{'widget_id': 'w2', 'kind': 'choices', 'data': <String, Object?>{'options': <Object?>['A']}},
      });
      await tester.pump(const Duration(milliseconds: Widgets.minLoaderMs));
      g.components.dismiss();
      final event = s.sent.last;
      expect(event['type'], 'app_event');
      expect((event['event']! as Map<String, Object?>)['name'], 'component_dismissed');
      expect((event['event']! as Map<String, Object?>)['quiet'], isTrue);
      expect(s.sent[s.sent.length - 2]['type'], 'app_context', reason: 'the screen goes first: the event is about it');
      await finish(tester, g);
    });

    testWidgets('two seconds in the background hang up the chat; back in front, it reconnects', (WidgetTester tester) async {
      final c = Connector();
      final g = makeApp(tester, Server(), connector: c);
      await connected(tester, g, c);
      g.setForegroundForTesting(false);
      await tester.pump(const Duration(seconds: 1));
      expect(g.chat.connected, isTrue, reason: 'a permission dialog backgrounds the app for a moment');
      await tester.pump(const Duration(seconds: 1));
      expect(c.last.types.last, 'stop');
      expect(g.chat.connected, isFalse);
      g.setForegroundForTesting(true);
      await tester.pump();
      await tester.pump();
      expect(c.sockets, hasLength(2));
      expect(g.chat.connected, isTrue);
      await finish(tester, g);
    });
  });

  group('a conversation that continues', () {
    Map<String, Object?> history() => <String, Object?>{
          'type': 'history',
          'continued': true,
          'turns': <Object?>[
            <String, Object?>{'id': 'f1', 'role': 'user', 'text': 'Is my order shipped?', 'at': '2026-10-13T09:30:00Z', 'channel': 'chat'},
            <String, Object?>{'id': 'f2', 'role': 'assistant', 'text': 'Yes, it left this morning.', 'at': '2026-10-13T09:30:04Z', 'channel': 'chat'},
            <String, Object?>{'id': 'f3', 'role': 'assistant', 'text': 'Hi, this is Asha.', 'at': '2026-10-13T11:00:00Z', 'channel': 'fax'},
          ],
        };

    testWidgets('the history becomes the chat before any agent message, and is never announced as new',
        (WidgetTester tester) async {
      final c = Connector();
      final heard = Heard();
      final g = makeApp(tester, Server(), connector: c)..addListener(heard);
      final s = await connected(tester, g, c);
      s.say(history());
      await tester.pump();
      expect(g.chat.turns.map((GraineChatTurn t) => t.text), <String>['Is my order shipped?', 'Yes, it left this morning.', 'Hi, this is Asha.']);
      expect(g.chat.turns.every((GraineChatTurn t) => t.restored), isTrue);
      expect(g.chat.turns.last.channel, GraineChatChannel.chat, reason: 'a channel this build does not know is the chat');
      expect(heard.volunteered, isEmpty, reason: 'restored turns are not the agent speaking now');
      g.chat.send('Where is it now?');
      s.say(<String, Object?>{'type': 'text', 'data': '<beginning_of_stream>In Pune.<end_of_stream>'});
      await tester.pump();
      expect(g.chat.turns.skip(3).map((GraineChatTurn t) => t.text), <String>['Where is it now?', 'In Pune.']);
      expect(g.chat.turns.last.proactive, isFalse);
      await finish(tester, g);
    });

    testWidgets('what went out as the chat opened stays after the history', (WidgetTester tester) async {
      final c = Connector()..fail = true;
      final g = makeApp(tester, Server(), connector: c);
      g.chat.send('Typed in the tunnel');
      await tester.pump();
      c.fail = false;
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pump();
      expect(c.last.types, contains('text'), reason: 'the waiting message went out on open');
      c.last.say(<String, Object?>{
        'type': 'history',
        'turns': <Object?>[<String, Object?>{'id': 'g1', 'role': 'assistant', 'text': 'Hello!', 'at': '2026-10-14T05:00:00Z'}],
      });
      await tester.pump();
      expect(g.chat.turns.map((GraineChatTurn t) => '${t.restored}:${t.text}'), <String>['true:Hello!', 'false:Typed in the tunnel']);
      await finish(tester, g);
    });

    testWidgets('a malformed history is no news', (WidgetTester tester) async {
      final c = Connector();
      final g = makeApp(tester, Server(), connector: c);
      final s = await connected(tester, g, c);
      s.say(<String, Object?>{'type': 'text', 'data': '<beginning_of_stream>Hi!<end_of_stream>'});
      s.say(<String, Object?>{'type': 'history', 'turns': 'none'});
      s.say(<String, Object?>{
        'type': 'history',
        'turns': <Object?>[<String, Object?>{'role': 'robot', 'text': 'x', 'at': '2026-10-13T09:30:00Z'}],
      });
      await tester.pump();
      expect(g.chat.turns.map((GraineChatTurn t) => t.text), <String>['Hi!']);
      await finish(tester, g);
    });

    testWidgets('a forget clears the chat on screen — only once it went through', (WidgetTester tester) async {
      final server = Server();
      final c = Connector();
      final g = makeApp(tester, server, connector: c);
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      final s = await connected(tester, g, c);
      s.say(history());
      await tester.pump();
      server.routes['/api/embed/memory/forget'] =
          (Map<String, Object?> _) => jsonResponse(<String, Object?>{'error': 'Try again soon.', 'code': 'unavailable'}, 503);
      await expectLater(g.forgetMemory(), throwsA(isA<GraineException>()));
      expect(g.chat.turns, hasLength(3), reason: 'a forget that did not complete took the conversation off the screen');
      server.routes['/api/embed/memory/forget'] = (Map<String, Object?> _) => jsonResponse(<String, Object?>{'deleted': 2});
      expect(await g.forgetMemory(), 2);
      expect(g.chat.turns, isEmpty, reason: 'the forgotten conversation is still on screen');
      await finish(tester, g);
    });

    testWidgets('newConversation: hang up, let go, clear, and a fresh chat — memories untouched', (WidgetTester tester) async {
      final server = Server();
      final c = Connector();
      final g = makeApp(tester, server, connector: c);
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      final first = await connected(tester, g, c);
      first.say(history());
      await tester.pump();
      final done = g.chat.newConversation();
      await tester.pump();
      await done;
      await tester.pump();
      expect(first.types.last, 'stop', reason: 'the conversation let go of was not hung up');
      final body = server.bodies('/api/embed/conversation/new').single;
      expect(body['identity'], <String, Object?>{'value': 'asha@example.com'});
      expect(body['installId'], testInstallId);
      expect(server.bodies('/api/embed/memory/forget'), isEmpty, reason: 'memories are untouched');
      expect(g.chat.turns, isEmpty);
      expect(c.sockets, hasLength(2), reason: 'no fresh chat was opened');
      c.last.say(<String, Object?>{'type': 'text', 'data': '<beginning_of_stream>Hi! How can I help?<end_of_stream>'});
      await tester.pump();
      expect(g.chat.turns.map((GraineChatTurn t) => t.text), <String>['Hi! How can I help?']);
      await finish(tester, g);
    });

    testWidgets('newConversation refused: it throws, and the chat is as it was, connected again', (WidgetTester tester) async {
      final server = Server();
      server.routes['/api/embed/conversation/new'] =
          (Map<String, Object?> _) => jsonResponse(<String, Object?>{'error': 'Not one of your devices.', 'code': 'device_limit'}, 403);
      final c = Connector();
      final g = makeApp(tester, server, connector: c);
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      final first = await connected(tester, g, c);
      first.say(history());
      await tester.pump();
      final done = g.chat.newConversation();
      await expectLater(done,
          throwsA(isA<GraineException>().having((GraineException e) => e.code, 'code', GraineErrorCode.deviceLimit)));
      await tester.pump();
      await tester.pump();
      expect(g.chat.turns, hasLength(3), reason: 'a refused new conversation took the old one off the screen');
      expect(c.sockets, hasLength(2), reason: 'the chat was left hung up');
      await finish(tester, g);
    });

    testWidgets('newConversation, nobody identified: only the screen starts over', (WidgetTester tester) async {
      final server = Server();
      final c = Connector();
      final g = makeApp(tester, server, connector: c);
      final s = await connected(tester, g, c);
      s.say(<String, Object?>{'type': 'text', 'data': '<beginning_of_stream>Hello!<end_of_stream>'});
      await tester.pump();
      await g.chat.newConversation();
      await tester.pump();
      expect(server.bodies('/api/embed/conversation/new'), isEmpty, reason: 'nothing was kept for an anonymous user');
      expect(g.chat.turns, isEmpty);
      expect(c.sockets, hasLength(2));
      await finish(tester, g);
    });
  });

  group('the booked calls in the chat', () {
    Map<String, Object?> call(String id, String at, [String status = 'scheduled']) =>
        <String, Object?>{'id': id, 'at': at, 'status': status, 'source': 'sdk', 'reason': null};

    testWidgets('read when the chat connects — booked ones, soonest first; a booking and a cancel show at once',
        (WidgetTester tester) async {
      final server = Server();
      server.routes['/api/embed/calls/list'] = (Map<String, Object?> _) => jsonResponse(<String, Object?>{
            'calls': <Object?>[
              call('b', '2026-10-15T09:00:00Z'),
              call('x', '2026-10-14T08:00:00Z', 'cancelled'),
              call('a', '2026-10-14T09:00:00Z'),
            ],
          });
      server.routes['/api/embed/calls/schedule'] = (Map<String, Object?> _) =>
          jsonResponse(<String, Object?>{'call': call('c', '2026-10-14T12:00:00Z')}, 201);
      final c = Connector();
      final g = makeApp(tester, server, connector: c);
      await connected(tester, g, c);
      await tester.pump();
      expect(g.chat.upcomingCalls.map((GraineScheduledCall x) => x.id), <String>['a', 'b']);

      await g.scheduleCall(at: tester.binding.clock.now().toUtc().add(const Duration(hours: 3)));
      expect(g.chat.upcomingCalls.map((GraineScheduledCall x) => x.id), <String>['a', 'c', 'b']);

      final done = g.chat.cancelUpcoming('a');
      expect(g.chat.cancelStateOf('a'), GraineUpcomingCancel.cancelling);
      await done;
      expect(g.chat.upcomingCalls.map((GraineScheduledCall x) => x.id), <String>['c', 'b']);
      expect(server.bodies('/api/embed/calls/cancel').single['callId'], 'a');

      server.routes['/api/embed/calls/cancel'] = (Map<String, Object?> _) =>
          jsonResponse(<String, Object?>{'error': 'Try again.', 'code': 'unavailable'}, 503);
      await g.chat.cancelUpcoming('b');
      expect(g.chat.cancelStateOf('b'), GraineUpcomingCancel.failed);
      expect(g.chat.upcomingCalls.map((GraineScheduledCall x) => x.id), <String>['c', 'b'], reason: 'it stays, and says so');
      await finish(tester, g);
    });

    testWidgets("after the agent speaks they are read again (it may have just booked one), at most every 30 s",
        (WidgetTester tester) async {
      final server = Server();
      final c = Connector();
      final g = makeApp(tester, server, connector: c);
      final s = await connected(tester, g, c);
      await tester.pump();
      expect(server.bodies('/api/embed/calls/list'), hasLength(1));
      s.say(<String, Object?>{'type': 'text', 'data': 'Booked for 6 pm.<end_of_stream>'});
      await tester.pump();
      expect(server.bodies('/api/embed/calls/list'), hasLength(1), reason: 'read a moment ago');
      await tester.pump(const Duration(seconds: 31));
      s.say(<String, Object?>{'type': 'text', 'data': 'Anything else?<end_of_stream>'});
      await tester.pump();
      expect(server.bodies('/api/embed/calls/list'), hasLength(2));
      await finish(tester, g);
    });

    testWidgets('an older server, which says nothing about calls, is never asked', (WidgetTester tester) async {
      final server = Server(session: <String, Object?>{...sessionBody()}..remove('calls'));
      final c = Connector();
      final g = makeApp(tester, server, connector: c);
      await connected(tester, g, c);
      await tester.pump();
      expect(server.bodies('/api/embed/calls/list'), isEmpty);
      expect(g.chat.upcomingCalls, isEmpty);
      await finish(tester, g);
    });
  });

  group('the bar and the windows', () {
    testWidgets("the bar opens the SDK's own chat when the customer switches to it, and closes it when they switch back",
        (WidgetTester tester) async {
      final c = Connector();
      final g = makeApp(tester, Server(), connector: c, install: true);
      await g.loadSession();
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(800, 600)),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(children: <Widget>[GraineAgentBar(showComponents: false)]),
        ),
      ));
      expect(find.byKey(GraineAgentBar.switchButtonKey), findsOneWidget,
          reason: 'the dashboard offers both, and the SDK runs the chat');
      expect(c.sockets, isEmpty, reason: 'no chat until the customer is in it');
      await tester.tap(find.byKey(GraineAgentBar.switchButtonKey));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(GraineAgentBar.chatKey), findsOneWidget);
      expect(g.chat.connected, isTrue);
      c.last.say(<String, Object?>{'type': 'text', 'data': '<beginning_of_stream>Hi there!<end_of_stream>'});
      await tester.pump();
      expect(find.text('Hi there!'), findsOneWidget);

      await tester.enterText(find.byType(EditableText), 'Show me the Creta');
      await tester.pump();
      await tester.tap(find.byKey(ChatWindow.sendKey));
      await tester.pump();
      expect(c.last.sent.last, <String, Object?>{'type': 'text', 'data': 'Show me the Creta'});
      expect(find.byKey(ChatWindow.typingKey), findsOneWidget, reason: 'the agent owes an answer');
      c.last.say(<String, Object?>{'type': 'text', 'data': 'Here it is.<end_of_stream>'});
      await tester.pump();
      expect(find.byKey(ChatWindow.typingKey), findsNothing);
      expect(find.text('Here it is.'), findsOneWidget);

      await tester.tap(find.byKey(ChatWindow.collapseKey));
      await tester.pump();
      await tester.pump();
      expect(c.last.types.last, 'stop', reason: 'back to the call: the chat hangs up');
      await tester.pumpWidget(const SizedBox());
      await finish(tester, g);
    });

    testWidgets("the chat's tokens draw its header, starters and composer; a starter is sent", (WidgetTester tester) async {
      final tokens = ThemeTokens.fromJson(<String, Object?>{
        'scheme': 'light',
        'colors': <String, Object?>{'accent': '#3B5BDB'},
        'icons': <String, Object?>{'launcher': null},
        'chat': <String, Object?>{
          'title': 'Ask Asha',
          'subtitle': 'Replies in seconds',
          'avatar': 'none',
          'placeholder': 'Type here…',
          'showTimestamps': true,
          'suggestions': <Object?>['Track my order', 'Refunds'],
          'background': '#F4F6FF',
          'pattern': 'dots',
          'patternColor': '#DDE2F0',
          'headerBackground': '#3B5BDB',
          'headerText': '#FFFFFF',
          'headerSubtext': '#D7DEFA',
          'composerBackground': '#FFFFFF',
          'composerText': '#101318',
          'composerPlaceholder': '#5F6672',
          'composerBorder': '#E5E4E0',
        },
      })!;
      final sent = <String>[];
      final at = DateTime(2026, 10, 13, 9, 5);
      Widget window(List<GraineChatTurn> turns, {bool typing = false}) => MediaQuery(
            data: const MediaQueryData(size: Size(400, 800)),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ChatWindow(
                  look: ChatLook.design(tokens),
                  heading: 'Assistant',
                  messages: <Caption>[for (final t in turns) t.caption],
                  turns: turns,
                  online: true,
                  typing: typing,
                  onSend: sent.add,
                  onCollapse: () {},
                ),
              ),
            ),
          );
      await tester.pumpWidget(window(<GraineChatTurn>[
        GraineChatTurn(id: 't1', role: GraineChatRole.agent, text: 'Hi!', at: at),
      ]));
      expect(find.text('Ask Asha'), findsOneWidget);
      expect(find.text('Replies in seconds'), findsOneWidget);
      expect(find.text('Type here…'), findsOneWidget);
      expect(find.text('9:05 AM'), findsOneWidget, reason: "timestamps on, in the device's short time");
      expect(find.byKey(ChatWindow.suggestionsKey), findsOneWidget);
      final title = tester.widget<Text>(find.text('Ask Asha'));
      expect(title.style?.color, const Color(0xFFFFFFFF), reason: 'headerText');
      await tester.tap(find.byKey(ChatWindow.suggestionKey(1)));
      expect(sent, <String>['Refunds']);

      await tester.pumpWidget(window(<GraineChatTurn>[
        GraineChatTurn(id: 't1', role: GraineChatRole.agent, text: 'Hi!', at: at),
        GraineChatTurn(id: 't2', role: GraineChatRole.user, text: 'Refunds', at: at, delivery: GraineChatDelivery.sent),
      ], typing: true));
      expect(find.byKey(ChatWindow.suggestionsKey), findsNothing, reason: 'starters are for a chat not yet begun');
      expect(find.byKey(ChatWindow.typingKey), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('GraineChat fills the screen, opens the chat while it shows, and its chevron closes',
        (WidgetTester tester) async {
      final c = Connector();
      final g = makeApp(tester, Server(), connector: c, install: true);
      await g.loadSession();
      var closed = 0;
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(400, 800), padding: EdgeInsets.only(top: 44, bottom: 34)),
        child: Directionality(textDirection: TextDirection.ltr, child: GraineChat(onClose: () => closed++)),
      ));
      await tester.pump();
      await tester.pump();
      expect(g.chat.connected, isTrue);
      expect(tester.getSize(find.byKey(GraineChat.screenKey)), const Size(800, 600), reason: 'the whole surface');
      expect(find.text('Asha'), findsOneWidget, reason: "the dashboard's heading");
      await tester.tap(find.byKey(ChatWindow.collapseKey));
      expect(closed, 1);
      await tester.pumpWidget(const SizedBox());
      expect(c.last.types.last, 'stop', reason: 'gone from the screen: the chat it opened hangs up');
      await finish(tester, g);
    });

    testWidgets('a chat screen leaving over the bar: the bar hears the chat close after that frame, not during it',
        (WidgetTester tester) async {
      final c = Connector();
      final g = makeApp(tester, Server(), connector: c, install: true);
      await g.loadSession();
      Widget screen(List<Widget> children) => MediaQuery(
            data: const MediaQueryData(size: Size(400, 800)),
            child: Directionality(textDirection: TextDirection.ltr, child: Stack(children: children)),
          );
      await tester.pumpWidget(screen(const <Widget>[GraineAgentBar(showComponents: false), GraineChat()]));
      await tester.pump();
      await tester.pump();
      expect(g.chat.connected, isTrue);
      await tester.pumpWidget(screen(const <Widget>[GraineAgentBar(showComponents: false)]));
      expect(tester.takeException(), isNull, reason: 'closed from a dispose, while the tree is locked');
      expect(c.last.types.last, 'stop', reason: 'the chat screen that opened it closed it');
      await tester.pump();
      expect(g.chat.isOpen, isFalse);
      await tester.pumpWidget(const SizedBox());
      await finish(tester, g);
    });
  });

  group('the screen', () {
    testWidgets("updateField, removeField and clearScreen; a screen's actions narrowed to this build's",
        (WidgetTester tester) async {
      final c = Connector();
      final g = makeApp(tester, Server(), connector: c);
      g.registerAction('fill_pan', (Map<String, Object?> _) => null);
      final s = await connected(tester, g, c);
      Map<String, Object?> lastContext() =>
          (s.sent.lastWhere((Map<String, Object?> m) => m['type'] == 'app_context')['context']! as Map<String, Object?>);
      g.setScreen(const GraineScreen('kyc', availableActions: <String>['fill_pan', 'not_built']));
      expect(s.sent.last['available_actions'], <String>['fill_pan']);
      g.updateField(const GraineField('pan', value: 'ABCDE1234F', status: FieldStatus.invalid));
      await tester.pump(const Duration(milliseconds: 400));
      expect(((lastContext()['fields']! as List<Object?>).single! as Map<String, Object?>)['status'], 'invalid');
      g.removeField('pan');
      await tester.pump(const Duration(milliseconds: 400));
      expect(lastContext().containsKey('fields'), isFalse);
      g.clearScreen('somewhere_else');
      await tester.pump(const Duration(milliseconds: 400));
      expect(lastContext()['screen'], 'kyc', reason: 'not the screen being described');
      g.clearScreen('kyc');
      await tester.pump(const Duration(milliseconds: 400));
      // Nothing left to say is no frame (as the React Native SDK); the screen
      // is gone, so the same screen again is news, sent at once.
      final frames = s.types.where((String t) => t == 'app_context').length;
      g.setScreen(const GraineScreen('kyc', availableActions: <String>['fill_pan', 'not_built']));
      expect(s.types.where((String t) => t == 'app_context').length, frames + 1);
      await finish(tester, g);
    });

    testWidgets('taps: a labelled control by its label, elsewhere where — only with a screen, two a second',
        (WidgetTester tester) async {
      final c = Connector();
      final g = makeApp(tester, Server(), connector: c, install: true);
      final s = await connected(tester, g, c);
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: GraineEngine(
          child: Stack(children: <Widget>[
            Positioned(
              left: 0,
              top: 0,
              width: 100,
              height: 50,
              child: Semantics(
                label: 'Continue',
                button: true,
                child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () {}, child: const SizedBox.expand()),
              ),
            ),
          ]),
        ),
      ));
      List<String> taps() => <String>[
            for (final m in s.sent)
              if (m['type'] == 'app_context')
                for (final e in (((m['context']! as Map<String, Object?>)['recent_events'] as List<Object?>?) ?? const <Object?>[]))
                  (e! as Map<String, Object?>)['name']! as String,
          ];
      await tester.tapAt(const Offset(50, 25));
      await tester.pump(const Duration(milliseconds: 500));
      expect(taps(), isEmpty, reason: 'no screen: a tap is about a screen');

      g.setScreen(const GraineScreen('checkout'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tapAt(const Offset(50, 25));
      await tester.tapAt(const Offset(300, 300));
      await tester.tapAt(const Offset(310, 300));
      await tester.pump(const Duration(milliseconds: 450));
      final last = s.sent.lastWhere((Map<String, Object?> m) => m['type'] == 'app_context');
      final events = ((last['context']! as Map<String, Object?>)['recent_events']! as List<Object?>).cast<Map<String, Object?>>();
      expect(events.map((Map<String, Object?> e) => e['name']), <String>['tap:Continue', 'tap:screen'],
          reason: 'two a second; the third is dropped');
      expect(events.last['data'], <String, Object?>{'x': 300, 'y': 300});
      await tester.pumpWidget(const SizedBox());
      await finish(tester, g);
    });
  });
}
