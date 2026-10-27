// The in-app platform, wired: who the user is reaching the engine page and
// every request (contract §1.2–1.3), the memory choice kept for them, sign-out
// and forget, the calls they book (§4.2), the SDK's own text chat end to end
// against a fake socket — ticket, frames, turns, typing, offline sends,
// reconnects, how long a conversation lasts once its window closes, a new
// conversation under earlier lines, components and actions — the bar and the
// full-screen chat drawing it, and the screen context's timing, actions and
// taps. HTTP is a mock; the device channel is a mock; nothing reaches a real
// host.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graine_inapp/graine_inapp.dart';
import 'package:graine_inapp/src/chat_window.dart';
import 'package:graine_inapp/src/graine.dart' show ChatSocketCloseCode;
import 'package:graine_inapp/src/core/workflows.dart' show Workflows;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'contract_files.dart';
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

  /// Routes that answer when the test says (an answer still on its way).
  final Map<String, Future<http.Response> Function(Map<String, Object?> body)> slowRoutes =
      <String, Future<http.Response> Function(Map<String, Object?> body)>{};

  /// The session's answer when a test says — one still on its way, a
  /// refusal; null: [session], at once.
  Future<http.Response> Function()? sessionAnswer;

  /// How many times the session was asked for.
  int get sessionRequests => requests.where((http.Request r) => r.url.path == '/api/embed/session').length;

  late final http.Client client = MockClient((http.Request req) async {
    requests.add(req);
    final path = req.url.path;
    final body = req.body.isEmpty ? <String, Object?>{} : jsonDecode(req.body) as Map<String, Object?>;
    if (path == '/api/embed/session') {
      final answer = sessionAnswer;
      return answer == null ? jsonResponse(session) : await answer();
    }
    final slow = slowRoutes[path];
    if (slow != null) return slow(body);
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
class FakeSocket implements GraineChatSocket, ChatSocketCloseCode {
  FakeSocket(this.url, this.protocols);

  final Uri url;
  final List<String>? protocols;
  final StreamController<Object?> _in = StreamController<Object?>();
  final List<Map<String, Object?>> sent = <Map<String, Object?>>[];
  bool closed = false;

  @override
  int? closeCode;

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

  /// The server went away — with [code], when it closed with one.
  void drop({int? code}) {
    closeCode = code;
    unawaited(_in.close());
  }

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

/// A connector whose first connection waits until [gate] completes — a chat still being made.
class _GatedConnector extends Connector {
  final Completer<void> gate = Completer<void>();
  int calls = 0;

  @override
  Future<GraineChatSocket> call(Uri url, List<String>? protocols) async {
    calls++;
    if (calls == 1) await gate.future;
    return super.call(url, protocols);
  }
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

/// [g]'s chat on screen — the SDK's full-screen chat — and connected: its socket.
Future<FakeSocket> onScreen(WidgetTester tester, GraineInApp g, Connector c) async {
  await tester.pumpWidget(MediaQuery(
    data: const MediaQueryData(size: Size(400, 800)),
    child: Directionality(textDirection: TextDirection.ltr, child: GraineChat(app: g)),
  ));
  await tester.pump();
  await tester.pump();
  expect(g.chat.connected, isTrue, reason: 'the chat did not connect');
  return c.last;
}

/// One whole agent turn, as the runtime sends it.
Map<String, Object?> said(String words) => <String, Object?>{'type': 'text', 'data': '<beginning_of_stream>$words<end_of_stream>'};

/// An app's own screen that closes the chat as it goes.
class _ClosesOnDispose extends StatefulWidget {
  const _ClosesOnDispose(this.chat);

  final GraineChatSession chat;

  @override
  State<_ClosesOnDispose> createState() => _ClosesOnDisposeState();
}

class _ClosesOnDisposeState extends State<_ClosesOnDispose> {
  @override
  void dispose() {
    widget.chat.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
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

    testWidgets('the same user written another way is no switch: nobody is signed out, and the chat stays theirs',
        (WidgetTester tester) async {
      final server = Server(session: sessionBody(field: 'phone'));
      final c = Connector();
      final g = makeApp(tester, server, connector: c);
      g.identify(<String, Object?>{'phone': '+91 98765 43210'});
      final socket = await connected(tester, g, c);
      // The profile API spells the number its own way: Graine keys both as one user (the last ten digits).
      g.identify(<String, Object?>{'phone': '9876543210'});
      await tester.pump();
      await tester.pump();
      expect(server.bodies('/api/embed/identity/signout'), isEmpty,
          reason: "a sign-out would unlink this phone from the user who is still on it — and stop it ringing for them");
      expect(socket.closed, isFalse, reason: 'the chat already reads them as one user');
      await finish(tester, g);
    });

    // 0.14.0 — contract/DESIGN.md "Who a chat belongs to": the reverse of what this used to pin.
    testWidgets('anonymous to identified: the open chat was nobody\'s — it closes and connects again at once as the user',
        (WidgetTester tester) async {
      final server = Server();
      final c = Connector();
      final g = makeApp(tester, server, connector: c);
      final first = await connected(tester, g, c);
      first.say(said('Hi, I am Asha.'));
      await tester.pump();
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      await tester.pump();
      await tester.pump();
      expect(first.types.last, 'stop', reason: 'closed normally');
      expect(g.chat.turns, isEmpty, reason: "the anonymous chat's turns are not the user's");
      expect(c.sockets, hasLength(2), reason: 'connected again at once');
      expect(server.bodies('/api/embed/ticket').last['identity'], <String, Object?>{'value': 'asha@example.com'});
      expect(g.chat.status, GraineChatStatus.connected);
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

  // 0.14.4 — what a request answers is the true reason: identity_required
  // names the trait this agent identifies users by; a session still on its
  // way is waited for; one that failed is its own refusal, never "nobody is
  // identified"; and a getter read before the session is told when it lands.
  group('identity_required, and the session it depends on (0.14.4)', () {
    const String memoryList = '/api/embed/memory/list';
    const String memoryForget = '/api/embed/memory/forget';
    const String usableMemberId = 'identify() was given no usable "member_id" — the trait this agent identifies customers '
        "by (Who is the user? in the agent's memory settings). Until it is, conversations are anonymous and nothing is "
        'remembered.';

    Matcher identityRequired(String message) => throwsA(isA<GraineException>()
        .having((GraineException e) => e.code, 'code', GraineErrorCode.identityRequired)
        .having((GraineException e) => e.message, 'message', message));

    testWidgets("traits without the agent's trait: identity_required names it, and nothing is asked", (WidgetTester tester) async {
      final server = Server(session: sessionBody(field: 'member_id'));
      server.routes[memoryList] = (Map<String, Object?> _) => jsonResponse(<String, Object?>{'memories': <Object?>[]});
      final g = makeApp(tester, server);
      g.identify(<String, Object?>{'user_id': 'P-1', 'name': 'Asha'});
      await expectLater(g.memories(), identityRequired(usableMemberId));
      await expectLater(g.forgetMemory(), identityRequired(usableMemberId));
      await expectLater(g.chat.sessionTranscript('ex-1'), identityRequired(usableMemberId));
      g.identify(<String, Object?>{'member_id': 'guest'});
      await expectLater(g.memories(), identityRequired(usableMemberId), reason: 'a placeholder is no usable value either');
      expect(server.bodies(memoryList), isEmpty, reason: 'nothing asked that would be refused');
      expect(server.bodies(memoryForget), isEmpty);
      g.identify(<String, Object?>{'member_id': 'M-000981'});
      expect(await g.memories(), isEmpty);
      expect(server.bodies(memoryList).single['identity'], <String, Object?>{'value': 'M-000981'});
      await finish(tester, g);
    });

    testWidgets("nobody identified: identity_required asks for the agent's trait by name — after a sign-out too",
        (WidgetTester tester) async {
      final g = makeApp(tester, Server(session: sessionBody(field: 'customer_id')));
      final nobody = identityRequired('Nobody is identified. Call identify() with the customer\'s "customer_id" first.');
      await expectLater(g.forgetMemory(), nobody);
      await expectLater(g.memories(), nobody);
      await expectLater(g.chat.sessionTranscript('ex-1'), nobody);
      g.identify(<String, Object?>{'customer_id': 'C-42'});
      g.identify(null);
      await tester.pump();
      await expectLater(g.memories(), nobody, reason: 'signed out: nobody again');
      await g.chat.refreshPastSessions();
      expect(g.chat.pastSessions.value.error, 'identity_required');
      await finish(tester, g);
    });

    testWidgets("one log line says so when the traits lack the agent's trait — as the session lands, and as identify() does",
        (WidgetTester tester) async {
      final g = makeApp(tester, Server(session: sessionBody(field: 'member_id')));
      final printed = <String>[];
      final before = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => printed.add(m ?? '');
      try {
        List<String> said() => <String>[
              for (final m in printed)
                if (m.contains('given no usable')) m,
            ];
        g.identify(<String, Object?>{'user_id': 'P-1', 'name': 'Asha'});
        expect(said(), isEmpty, reason: 'which trait the agent wants is not known before the session');
        await g.loadSession();
        expect(said(), <String>['[Graine] $usableMemberId']);
        g.identify(<String, Object?>{'user_id': 'P-1', 'name': 'Asha'});
        expect(said(), hasLength(1), reason: 'the same traits again: said once');
        g.identify(<String, Object?>{'member_id': 'M-000981'});
        expect(said(), hasLength(1), reason: 'the trait is there');
        g.identify(<String, Object?>{'userId': 'P-2'});
        expect(said(), hasLength(2), reason: 'identify() landed without it');
        g.identify(null);
        expect(said(), hasLength(2), reason: 'a sign-out is no mistake');
        await tester.pump();
      } finally {
        debugPrint = before;
      }
      await finish(tester, g);
    });

    testWidgets("a session that could not load is the refusal — its code, the server's sentence — never \"nobody is "
        'identified"; 502 and 504 are unavailable; the next call asks again', (WidgetTester tester) async {
      final server = Server();
      server.routes[memoryList] = (Map<String, Object?> _) => jsonResponse(<String, Object?>{
            'memories': <Object?>[
              <String, Object?>{'id': 'm1', 'text': 'Prefers mornings'},
            ],
          });
      final answers = <Future<http.Response> Function()>[
        () async => jsonResponse(<String, Object?>{'error': 'Graine is busy right now.', 'code': 'unavailable'}, 503),
        () async => http.Response('<html><body>502 Bad Gateway</body></html>', 502,
            headers: const <String, String>{'content-type': 'text/html'}),
        () async => http.Response('', 504),
        () async => throw http.ClientException('no route to host'),
        () async => jsonResponse(<String, Object?>{'error': 'Unknown key', 'code': 'invalid_key'}, 401),
      ];
      server.sessionAnswer = () => answers.isEmpty ? Future<http.Response>.value(jsonResponse(server.session)) : answers.removeAt(0)();
      final g = makeApp(tester, server);
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      Matcher refused(GraineErrorCode code, {Object? message, int? status}) => throwsA(isA<GraineException>()
          .having((GraineException e) => e.code, 'code', code)
          .having((GraineException e) => e.message, 'message', message ?? anything)
          .having((GraineException e) => e.statusCode, 'statusCode', status));
      await expectLater(g.memories(), refused(GraineErrorCode.unavailable, message: 'Graine is busy right now.', status: 503));
      await expectLater(g.forgetMemory(), refused(GraineErrorCode.unavailable, status: 502),
          reason: 'a gateway that failed, no code: an outage, as the docs say');
      await expectLater(g.memories(), refused(GraineErrorCode.unavailable, status: 504), reason: 'and one that timed out');
      await expectLater(g.forgetMemory(), refused(GraineErrorCode.network, message: contains('no route to host')));
      await expectLater(g.memories(), refused(GraineErrorCode.invalidKey, status: 401));
      expect(server.sessionRequests, 5, reason: 'each call asked for the session again');
      expect(server.bodies(memoryList), isEmpty);
      expect(server.bodies(memoryForget), isEmpty);
      expect((await g.memories()).single.id, 'm1');
      expect(server.sessionRequests, 6);
      await finish(tester, g);
    });

    // A one-shot request belongs to whoever was identified when it was made — the native SDKs' rule
    // (iOS customerAfterSession, Android afterSession(forWhoAsked)), in the same words.
    group('a request made while the settings load is carried out only for the customer who asked', () {
      const String someoneElse = "Someone else was identified while the agent's settings were loading, so nothing was "
          'asked for the customer identified before. Ask again for the customer identified now.';
      const List<String> routes = <String>[
        '/api/embed/memory/list',
        '/api/embed/memory/forget',
        '/api/embed/sessions/transcript',
        '/api/embed/calls/schedule',
        '/api/embed/conversation/new',
        '/api/embed/workflows/start',
      ];

      /// A server whose session waits for [gate], answering every route the requests below use.
      Server gated(Completer<void> gate) {
        final server = Server(session: sessionBody(field: 'customer_id'));
        server.sessionAnswer = () async {
          await gate.future;
          return jsonResponse(server.session);
        };
        server.routes['/api/embed/memory/list'] = (Map<String, Object?> _) => jsonResponse(<String, Object?>{
              'memories': <Object?>[
                <String, Object?>{'id': 'm1', 'text': 'Prefers mornings'},
              ],
            });
        server.routes['/api/embed/memory/forget'] = (Map<String, Object?> _) => jsonResponse(<String, Object?>{'deleted': 3});
        server.routes['/api/embed/sessions/transcript'] = (Map<String, Object?> body) => jsonResponse(<String, Object?>{
              'id': body['id'],
              'turns': <Object?>[
                <String, Object?>{'role': 'user', 'text': 'Hi', 'at': '2026-10-21T10:00:05Z'},
              ],
            });
        server.routes['/api/embed/calls/schedule'] = (Map<String, Object?> body) => jsonResponse(<String, Object?>{
              'call': <String, Object?>{'id': 'sc_1', 'at': body['at'], 'status': 'scheduled', 'source': 'sdk'},
            }, 201);
        server.routes['/api/embed/workflows/start'] = (Map<String, Object?> _) => jsonResponse(<String, Object?>{
              'runId': 'oex_2c9e8f1a7b3d4c5e6f7a8b9c',
              'workflowId': 'owf_8a1d4e7c2b90f1a2b3c4d5e6',
              'alreadyRunning': false,
            }, 201);
        return server;
      }

      /// Every one-shot request, asked now: what each came to — its value, or what it threw.
      Future<Map<String, Object?>> ask(WidgetTester tester, GraineInApp g, void Function() meanwhile, Completer<void> gate) async {
        final later = tester.binding.clock.now().toUtc().add(const Duration(hours: 3));
        final at = DateTime.utc(later.year, later.month, later.day, later.hour, later.minute, later.second);
        final asked = <String, Future<Object?>>{
          'memories': g.memories(),
          'forgetMemory': g.forgetMemory(),
          'sessionTranscript': g.chat.sessionTranscript('ex-1'),
          'scheduleCall': g.scheduleCall(at: at, reason: 'Renewal'),
          'newConversation': g.chat.newConversation().then((void _) => 'done'),
          'startWorkflow': g.startWorkflow('Welcome call', data: <String, Object?>{'plan': 'gold'}),
        };
        meanwhile();
        gate.complete();
        return <String, Object?>{
          for (final e in asked.entries) e.key: await e.value.then((Object? v) => v, onError: (Object e) => e),
        };
      }

      Matcher refused(String message) => isA<GraineException>()
          .having((GraineException e) => e.code, 'code', GraineErrorCode.identityRequired)
          .having((GraineException e) => e.message, 'message', message);

      testWidgets('someone else identified before the settings land: nothing is asked for either of them',
          (WidgetTester tester) async {
        final gate = Completer<void>();
        final server = gated(gate);
        final g = makeApp(tester, server);
        g.identify(<String, Object?>{'customer_id': 'C-42', 'name': 'Asha'});
        final came = await ask(tester, g, () => g.identify(<String, Object?>{'customer_id': 'C-77', 'name': 'Ravi'}), gate);
        for (final e in came.entries) {
          expect(e.value, refused(someoneElse), reason: "${e.key}: Asha's request is never Ravi's");
        }
        for (final route in routes) {
          expect(server.bodies(route), isEmpty, reason: '$route: nothing asked');
        }
        await finish(tester, g);
      });

      testWidgets('signed out before the settings land: refused, in the words that name the trait', (WidgetTester tester) async {
        final gate = Completer<void>();
        final server = gated(gate);
        final g = makeApp(tester, server);
        g.identify(<String, Object?>{'customer_id': 'C-42'});
        final came = await ask(tester, g, () => g.identify(null), gate);
        for (final e in came.entries) {
          expect(e.value, refused('Nobody is identified. Call identify() with the customer\'s "customer_id" first.'),
              reason: e.key);
        }
        for (final route in routes) {
          expect(server.bodies(route), isEmpty, reason: route);
        }
        await finish(tester, g);
      });

      testWidgets('the same customer again — other traits, another spelling — is still them; one asked for by nobody is '
          'for whoever is identified when the settings land', (WidgetTester tester) async {
        final gate = Completer<void>();
        final server = gated(gate);
        final g = makeApp(tester, server);
        g.identify(<String, Object?>{'customer_id': 'C-42'});
        final came = await ask(tester, g, () => g.identify(<String, Object?>{'customer_id': ' C-42 ', 'plan': 'gold'}), gate);
        expect(came['memories'], isA<List<GraineMemory>>());
        expect(came['forgetMemory'], 3);
        expect(came['sessionTranscript'], isA<GrainePastSessionTranscript>());
        expect(came['scheduleCall'], isA<GraineScheduledCall>());
        expect(came['newConversation'], 'done');
        expect(came['startWorkflow'], isA<GraineWorkflowRun>());
        for (final route in routes) {
          expect(server.bodies(route).single['identity'], <String, Object?>{'value': ' C-42 '}, reason: route);
        }
        await finish(tester, g);

        final gate2 = Completer<void>();
        final server2 = gated(gate2);
        final h = makeApp(tester, server2);
        final booked = await ask(tester, h, () => h.identify(<String, Object?>{'customer_id': 'C-77'}), gate2);
        expect(booked['scheduleCall'], isA<GraineScheduledCall>(), reason: 'asked for nobody in particular: no one was replaced');
        expect(server2.bodies('/api/embed/calls/schedule').single['identity'], <String, Object?>{'value': 'C-77'});
        await finish(tester, h);
      });
    });

    testWidgets('a session that never answers: memories() gives up at its timeout, as network — and the next call asks again',
        (WidgetTester tester) async {
      final server = Server();
      final never = Completer<http.Response>();
      server.sessionAnswer = () => never.future;
      server.routes[memoryList] = (Map<String, Object?> _) => jsonResponse(<String, Object?>{'memories': <Object?>[]});
      final g = makeApp(tester, server);
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      Object? failure;
      unawaited(g.memories().then((List<GraineMemory> _) {}, onError: (Object e) {
        failure = e;
      }));
      await tester.pump(const Duration(seconds: 24));
      expect(failure, isNull, reason: 'still waiting for the session');
      await tester.pump(const Duration(seconds: 2));
      expect(failure, isA<GraineException>().having((GraineException e) => e.code, 'code', GraineErrorCode.network));
      server.sessionAnswer = null;
      expect(await g.memories(), isEmpty);
      expect(server.sessionRequests, 2);
      await finish(tester, g);
    });

    testWidgets('asked as the app starts — memories, forget, past sessions, a transcript, bookings — everything waits for the '
        'session, then decides: nothing is "not identified" for a session on its way', (WidgetTester tester) async {
      final server = Server(session: sessionBody(field: 'customer_id'));
      final gate = Completer<void>();
      server.sessionAnswer = () async {
        await gate.future;
        return jsonResponse(server.session);
      };
      server.routes[memoryList] = (Map<String, Object?> _) => jsonResponse(<String, Object?>{
            'memories': <Object?>[
              <String, Object?>{'id': 'm1', 'text': 'Prefers mornings'},
            ],
          });
      server.routes[memoryForget] = (Map<String, Object?> _) => jsonResponse(<String, Object?>{'deleted': 1});
      server.routes['/api/embed/sessions/list'] = (Map<String, Object?> _) => jsonResponse(<String, Object?>{
            'sessions': <Object?>[
              <String, Object?>{'id': 'ex-1', 'startedAt': '2026-10-21T10:00:00Z', 'channel': 'chat', 'turns': 2, 'preview': 'Hi'},
            ],
            'next': null,
          });
      server.routes['/api/embed/sessions/transcript'] = (Map<String, Object?> body) => jsonResponse(<String, Object?>{
            'id': body['id'],
            'turns': <Object?>[
              <String, Object?>{'role': 'user', 'text': 'Hi', 'at': '2026-10-21T10:00:05Z'},
            ],
          });
      server.routes['/api/embed/calls/list'] = (Map<String, Object?> _) => jsonResponse(<String, Object?>{'calls': <Object?>[]});
      server.routes['/api/embed/calls/schedule'] = (Map<String, Object?> body) => jsonResponse(<String, Object?>{
            'call': <String, Object?>{'id': 'sc_1', 'at': body['at'], 'status': 'scheduled', 'source': 'sdk'},
          }, 201);
      final g = makeApp(tester, server);
      g.identify(<String, Object?>{'customer_id': 'C-42', 'name': 'Asha'});
      final later = tester.binding.clock.now().toUtc().add(const Duration(hours: 3));
      final at = DateTime.utc(later.year, later.month, later.day, later.hour, later.minute, later.second);
      final asked = <String, Future<Object?>>{
        'memories': g.memories(),
        'forgetMemory': g.forgetMemory(),
        'sessionTranscript': g.chat.sessionTranscript('ex-1'),
        'pastSessions': g.chat.refreshPastSessions().then((void _) => null),
        'scheduledCalls': g.scheduledCalls(),
        'scheduleCall': g.scheduleCall(at: at, reason: 'Renewal'),
        'memoryEnabled': g.memoryEnabled(),
      };
      final answered = <String>{};
      final failed = <String, Object>{};
      asked.forEach((String name, Future<Object?> f) => unawaited(f.then((Object? _) {
            answered.add(name);
          }, onError: (Object e) {
            failed[name] = e;
          })));
      // While it loads the getters say "not yet" — never a reason that is wrong a moment later.
      expect(g.bookingUnavailableReason, GraineBookingUnavailableReason.notLoaded);
      expect(g.bookingAvailable, isFalse);
      expect(g.bookingBlocker, isNot(GraineErrorCode.identityRequired));
      await tester.pump(const Duration(seconds: 5));
      expect(answered, isEmpty, reason: 'nothing decides before the session says who the user is');
      expect(failed, isEmpty);
      expect(g.chat.pastSessions.value.loading, isTrue);
      expect(g.chat.pastSessions.value.error, isNull);
      gate.complete();
      await Future.wait<Object?>(<Future<Object?>>[for (final f in asked.values) f.catchError((Object _) => null)]);
      expect(failed, isEmpty);
      expect(answered, asked.keys.toSet());
      expect(await asked['forgetMemory'], 1);
      expect(g.chat.pastSessions.value.sessions.single.id, 'ex-1');
      expect(server.sessionRequests, 1, reason: 'all of them shared the one request');
      for (final route in <String>[
        memoryList, memoryForget, '/api/embed/sessions/list', '/api/embed/sessions/transcript', '/api/embed/calls/list',
        '/api/embed/calls/schedule',
      ]) {
        expect(server.bodies(route).single['identity'], <String, Object?>{'value': 'C-42'}, reason: route);
      }
      expect(g.bookingUnavailableReason, isNull);
      await finish(tester, g);
    });

    testWidgets('someone else signing in before the session arrives: once it names the trait, the last user is signed out',
        (WidgetTester tester) async {
      const String signout = '/api/embed/identity/signout';
      final server = Server();
      final gate = Completer<void>();
      server.sessionAnswer = () async {
        await gate.future;
        return jsonResponse(server.session);
      };
      final g = makeApp(tester, server);
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      g.identify(<String, Object?>{'email': 'asha@example.com', 'name': 'Asha'});
      g.identify(<String, Object?>{'email': 'ravi@example.com', 'name': 'Ravi'});
      await tester.pump(const Duration(seconds: 1));
      expect(server.bodies(signout), isEmpty, reason: 'whether that was someone else is not known before the session');
      gate.complete();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(server.bodies(signout).single['identity'], <String, Object?>{'value': 'asha@example.com'},
          reason: 'Asha, once — her other traits were no switch');
      await finish(tester, g);
    });

    testWidgets('a user who is the user again by the time the session arrives is not signed out — away and back, or out '
        'and in again', (WidgetTester tester) async {
      const String signout = '/api/embed/identity/signout';
      final server = Server();
      final gate = Completer<void>();
      server.sessionAnswer = () async {
        await gate.future;
        return jsonResponse(server.session);
      };
      final g = makeApp(tester, server);
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      g.identify(<String, Object?>{'email': 'ravi@example.com'});
      g.identify(<String, Object?>{'email': 'Asha@Example.com'}); // Asha again — spelt as her profile spells it
      g.identify(null);
      g.identify(<String, Object?>{'email': 'asha@example.com', 'name': 'Asha'});
      gate.complete();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      // A sign-out unlinks the device from that user: signing Asha out now would stop her phone ringing for her —
      // under any spelling of her address, which Graine reads as one user.
      expect(<Object?>[for (final b in server.bodies(signout)) b['identity']], <Object?>[
        <String, Object?>{'value': 'ravi@example.com'},
      ], reason: 'Ravi left; Asha is the user again');
      await finish(tester, g);
    });

    testWidgets('whoever left before the session is signed out once one arrives — after a load that failed, too',
        (WidgetTester tester) async {
      const String signout = '/api/embed/identity/signout';
      final server = Server();
      final answers = <Future<http.Response> Function()>[
        () async => jsonResponse(<String, Object?>{'error': 'Graine is busy right now.', 'code': 'unavailable'}, 503),
      ];
      server.sessionAnswer =
          () => answers.isEmpty ? Future<http.Response>.value(jsonResponse(server.session)) : answers.removeAt(0)();
      final g = makeApp(tester, server);
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      g.identify(<String, Object?>{'email': 'ravi@example.com'}); // someone else, before the session
      g.identify(null); // and a sign-out
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(server.sessionRequests, 1);
      expect(g.session, isNull, reason: 'the first load failed');
      expect(server.bodies(signout), isEmpty);
      expect(await g.loadSession(), isNotNull);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(<Object?>[for (final b in server.bodies(signout)) (b['identity']! as Map<String, Object?>)['value']],
          unorderedEquals(<String>['asha@example.com', 'ravi@example.com']),
          reason: 'neither device binding may outlive a session load that failed: their calls would ring here');
      await finish(tester, g);
    });

    testWidgets('bookingListenable tells the app when the session arrives — even when booking stays unavailable — so the '
        'reason is read again', (WidgetTester tester) async {
      final g = makeApp(tester, Server());
      final reasons = <GraineBookingUnavailableReason?>[];
      g.bookingListenable.addListener(() => reasons.add(g.bookingUnavailableReason));
      expect(g.bookingUnavailableReason, GraineBookingUnavailableReason.notLoaded);
      await g.loadSession();
      expect(reasons, <GraineBookingUnavailableReason?>[GraineBookingUnavailableReason.notIdentified],
          reason: 'bookingAvailable stayed false, but the reason a widget shows changed: it is told, once');
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      expect(reasons.last, isNull);
      expect(g.bookingListenable.value, isTrue);
      g.identify(<String, Object?>{'email': 'asha@example.com', 'name': 'Asha'});
      expect(reasons, hasLength(2), reason: 'nothing changed: nothing said');
      g.identify(null);
      expect(reasons.last, GraineBookingUnavailableReason.notIdentified);
      expect(g.bookingListenable.value, isFalse);
      await tester.pump();
      await finish(tester, g);

      final h = makeApp(tester, Server(session: sessionBody(usersCanBook: false)));
      final heard = <GraineBookingUnavailableReason?>[];
      h.bookingListenable.addListener(() => heard.add(h.bookingUnavailableReason));
      h.identify(<String, Object?>{'email': 'asha@example.com'});
      expect(heard, isEmpty, reason: 'still loading: nothing to read again yet');
      await h.loadSession();
      expect(heard, <GraineBookingUnavailableReason?>[GraineBookingUnavailableReason.schedulingOff]);
      await finish(tester, h);
    });

    testWidgets("bookingSlots offers no time on a guess: empty until the session brings the agent's rules",
        (WidgetTester tester) async {
      final g = makeApp(tester, Server());
      final now = DateTime(2026, 10, 14, 17, 58, 37);
      expect(g.bookingSlots(DateTime(2026, 10, 15, 9), now: now), isEmpty);
      await g.loadSession();
      expect(g.bookingSlots(DateTime(2026, 10, 15, 9), now: now), hasLength(288));
      await finish(tester, g);
    });

    testWidgets("a chat that cannot connect for want of the session says the session's own reason", (WidgetTester tester) async {
      final server = Server();
      server.sessionAnswer = () async => jsonResponse(<String, Object?>{'error': 'Unknown key', 'code': 'invalid_key'}, 401);
      final c = Connector();
      final g = makeApp(tester, server, connector: c);
      g.chat.open();
      await tester.pump();
      await tester.pump();
      expect(g.chat.connected, isFalse);
      expect(g.chat.error, 'Publishable key was rejected. Check it against Embed & Widgets in the dashboard.');
      expect(c.sockets, isEmpty);
      g.chat.close();
      await finish(tester, g);
    });
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

  group('workflows the app starts (0.14.4)', () {
    const route = '/api/embed/workflows/start';
    final run = <String, Object?>{
      'runId': 'oex_2c9e8f1a7b3d4c5e6f7a8b9c',
      'workflowId': 'owf_8a1d4e7c2b90f1a2b3c4d5e6',
      'alreadyRunning': false,
    };
    Matcher refused(GraineErrorCode code) =>
        throwsA(isA<GraineException>().having((GraineException e) => e.code, 'code', code));

    testWidgets('the run is started for the identified user — nobody identified is refused, nothing asked',
        (WidgetTester tester) async {
      final server = Server();
      server.routes[route] = (Map<String, Object?> _) => jsonResponse(run, 201);
      final g = makeApp(tester, server);
      await expectLater(g.startWorkflow('Welcome call'), refused(GraineErrorCode.identityRequired));
      g.identify(<String, Object?>{'user_id': 'P-1'});
      await expectLater(g.startWorkflow('Welcome call'), refused(GraineErrorCode.identityRequired),
          reason: 'another trait is nobody for this agent');
      expect(server.bodies(route), isEmpty);
      g.identify(<String, Object?>{'email': 'asha@example.com', 'name': 'Asha'});
      final started = await g.startWorkflow('  Welcome call ', data: <String, Object?>{'plan': 'gold', 'seats': 3, 'trial': true});
      expect(started, const GraineWorkflowRun(runId: 'oex_2c9e8f1a7b3d4c5e6f7a8b9c', workflowId: 'owf_8a1d4e7c2b90f1a2b3c4d5e6'));
      final body = server.bodies(route).single;
      expect(body['identity'], <String, Object?>{'value': 'asha@example.com'});
      expect(body['installId'], testInstallId);
      expect(body['publishableKey'], 'pk_test_1');
      expect(body['workflow'], 'Welcome call');
      expect(body['data'], <String, Object?>{'plan': 'gold', 'seats': 3, 'trial': true});
      expect(Workflows.isIdempotencyKey(body['idempotencyKey']! as String), isTrue, reason: 'every call carries a key');
      await finish(tester, g);
    });

    testWidgets('a forged id never leaves the device; what could never be kept is left out; twelve at most',
        (WidgetTester tester) async {
      final server = Server();
      server.routes[route] = (Map<String, Object?> _) => jsonResponse(run, 201);
      final g = makeApp(tester, server);
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      await g.startWorkflow('Welcome call', data: <String, Object?>{
        'user_id': 'someone-else', 'user_field': 'email', 'reference_id': 'ref-forged', 'graine_user_key': 'u1_x',
        'mobile_number': '+15550000002', 'email': 'x@evil.example', 'fields': 'x',
        'plan': 'gold', 'long': 'x' * 201, 'emoji': '🙂' * 200, 'list': <int>[1], 'nested': <String, int>{'a': 1},
        'nothing': null, 'nan': double.nan, 'bad name': 'x',
      });
      final body = server.bodies(route).single;
      expect(body['identity'], <String, Object?>{'value': 'asha@example.com'}, reason: 'the identity, untouched by data');
      expect((body['data']! as Map<String, Object?>).keys.toSet(), <String>{'plan', 'emoji'},
          reason: 'an emoji is one character, as Graine counts');
      final many = <String, Object?>{'list': <int>[1], for (var i = 0; i < 15; i++) 'f$i': i};
      expect(Workflows.data(many).keys.toList(), <String>[for (var i = 0; i < 12; i++) 'f$i']);
      await finish(tester, g);
    });

    testWidgets('a workflow name is needed and a key must be one — refused before anything is asked',
        (WidgetTester tester) async {
      final server = Server();
      final g = makeApp(tester, server);
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      for (final bad in <String>['', '   ', 'w' * 121]) {
        await expectLater(g.startWorkflow(bad), refused(GraineErrorCode.invalidRequest));
      }
      for (final bad in <String>['short', 'has a space', 'k' * 129]) {
        await expectLater(g.startWorkflow('Welcome call', idempotencyKey: bad), refused(GraineErrorCode.invalidRequest));
      }
      expect(server.bodies(route), isEmpty);
      expect(Workflows.name('w' * 120), isNotNull);
      await finish(tester, g);
    });

    testWidgets('no answer is asked once more with the same key; a refusal never', (WidgetTester tester) async {
      final server = Server();
      var asked = 0;
      server.routes[route] = (Map<String, Object?> _) {
        asked++;
        if (asked == 1) throw http.ClientException('connection reset');
        return jsonResponse(run);
      };
      final g = makeApp(tester, server);
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      final starting = g.startWorkflow('Welcome call');
      await tester.pump();
      expect(server.bodies(route), hasLength(1), reason: 'the first ask went, and got no answer');
      await tester.pump(const Duration(seconds: 1));
      final started = await starting;
      expect(started.runId, 'oex_2c9e8f1a7b3d4c5e6f7a8b9c');
      final keys = server.bodies(route).map((Map<String, Object?> b) => b['idempotencyKey']).toList();
      expect(keys, hasLength(2));
      expect(keys.first, keys.last, reason: 'the same key: Graine answers the start it made');

      server.routes[route] = (Map<String, Object?> _) => throw http.ClientException('connection reset');
      final before = server.bodies(route).length;
      final failing = expectLater(g.startWorkflow('Welcome call', idempotencyKey: 'order-1042:welcome'),
          refused(GraineErrorCode.network));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await failing;
      expect(server.bodies(route).skip(before).map((Map<String, Object?> b) => b['idempotencyKey']),
          <String>['order-1042:welcome', 'order-1042:welcome'], reason: 'once more, and no more');

      server.routes[route] = (Map<String, Object?> _) =>
          jsonResponse(<String, Object?>{'error': "This workspace can't start workflows right now.", 'code': 'unavailable'}, 503);
      final beforeRefusal = server.bodies(route).length;
      await expectLater(g.startWorkflow('Welcome call'), refused(GraineErrorCode.unavailable));
      expect(server.bodies(route).length - beforeRefusal, 1, reason: 'Graine answered: not asked again');
      await finish(tester, g);
    });

    testWidgets("Graine's refusals arrive as their codes, with the sentence and Retry-After", (WidgetTester tester) async {
      final server = Server();
      final g = makeApp(tester, server);
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      for (final (status, word, code) in <(int, String, GraineErrorCode)>[
        (403, 'not_allowed', GraineErrorCode.notAllowed),
        (403, 'not_verified', GraineErrorCode.notVerified),
        (400, 'invalid_request', GraineErrorCode.invalidRequest),
        (503, 'unavailable', GraineErrorCode.unavailable),
      ]) {
        server.routes[route] = (Map<String, Object?> _) => jsonResponse(<String, Object?>{'error': 'said $word', 'code': word}, status);
        await expectLater(
            g.startWorkflow('Welcome call'),
            throwsA(isA<GraineException>()
                .having((GraineException e) => e.code, 'code', code)
                .having((GraineException e) => e.message, 'message', 'said $word')));
      }
      server.routes[route] = (Map<String, Object?> _) => http.Response(
          jsonEncode(<String, Object?>{'error': 'Too many workflows started from this device in the last hour.', 'code': 'rate_limited'}),
          429,
          headers: const <String, String>{'retry-after': '600'});
      await expectLater(
          g.startWorkflow('Welcome call'),
          throwsA(isA<GraineException>()
              .having((GraineException e) => e.code, 'code', GraineErrorCode.rateLimited)
              .having((GraineException e) => e.retryAfterSeconds, 'retryAfterSeconds', 600)));
      server.routes[route] = (Map<String, Object?> _) => jsonResponse(<String, Object?>{'workflowId': 'owf_1'}, 201);
      await expectLater(g.startWorkflow('Welcome call'), refused(GraineErrorCode.unknown));
      expect(Workflows.runFrom(<String, Object?>{'run_id': 'oex_1', 'workflow_id': 'owf_1', 'already_running': true}),
          const GraineWorkflowRun(runId: 'oex_1', workflowId: 'owf_1', alreadyRunning: true));
      expect(GraineErrorCode.fromWire('not_verified'), GraineErrorCode.notVerified);
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

    testWidgets('reportEvent reaches the live chat, its pacing keys at the event\'s own level (0.14.4)',
        (WidgetTester tester) async {
      final c = Connector();
      final g = makeApp(tester, Server(), connector: c);
      final s = await connected(tester, g, c);
      g.reportEvent('  ');
      expect(s.sent.where((Map<String, Object?> m) => m['type'] == 'app_event'), isEmpty, reason: 'an empty name is ignored');
      g.reportEvent(' reminder_opened ',
          detail: 'The customer came from the breakfast reminder',
          data: const <String, Object?>{'cooldown_seconds': 0, 'max_per_session': 5, 'quiet': false});
      final event = s.sent.last['event']! as Map<String, Object?>;
      expect(s.sent.last['type'], 'app_event');
      expect(event['name'], 'reminder_opened');
      expect(event['detail'], 'The customer came from the breakfast reminder');
      expect(event['cooldown_seconds'], 0);
      expect(event['max_per_session'], 5);
      expect(event['quiet'], isFalse);
      expect(event.containsKey('data'), isFalse, reason: 'nothing else was said');
      // A data key is data: it never renames the event, nor replaces its detail.
      g.reportEvent('medication_due',
          detail: 'The 8 pm dose is due.', data: const <String, Object?>{'name': 'Metformin', 'detail': 'x', 'dose_mg': 500});
      expect(s.sent.last['event'], <String, Object?>{
        'name': 'medication_due',
        'detail': 'The 8 pm dose is due.',
        'data': <String, Object?>{'name': 'Metformin', 'detail': 'x', 'dose_mg': 500},
      });
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

  // 0.14.3 — sdk/contract/past-sessions.json through the chat: what GraineChatSession.pastSessions keeps.
  group('past sessions', () {
    const String list = '/api/embed/sessions/list';
    const String transcript = '/api/embed/sessions/transcript';
    late Map<String, Object?> contract;
    setUpAll(() async => contract = await contractJson('contract/past-sessions.json'));
    List<Map<String, Object?>> section(String name) => (contract[name]! as List<Object?>).cast<Map<String, Object?>>();
    List<String> ids(GraineInApp g) => <String>[for (final s in g.chat.pastSessions.value.sessions) s.id];

    Map<String, Object?> page(List<String> ids, {String? next}) => <String, Object?>{
          'sessions': <Object?>[
            for (final id in ids)
              <String, Object?>{'id': id, 'startedAt': '2026-10-21T10:00:00Z', 'channel': 'chat', 'turns': 2, 'preview': 'Hi'},
          ],
          'next': next,
        };

    testWidgets('empty until refreshed; the first page for this user from this install, then the next with its cursor, then the end',
        (WidgetTester tester) async {
      final server = Server();
      server.routes[list] = (Map<String, Object?> body) =>
          jsonResponse(body['cursor'] == 'c2' ? page(<String>['a2', 'a1'], next: null) : page(<String>['a1'], next: 'c2'));
      final g = makeApp(tester, server);
      expect(g.chat.pastSessions.value, GrainePastSessions.empty);
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      final seen = <GrainePastSessions>[];
      g.chat.pastSessions.addListener(() => seen.add(g.chat.pastSessions.value));
      await g.chat.refreshPastSessions();
      expect(seen.first.loading, isTrue, reason: 'loading while the page is read');
      expect(ids(g), <String>['a1']);
      expect(g.chat.pastSessions.value.hasMore, isTrue);
      expect(g.chat.pastSessions.value.loading, isFalse);
      final first = server.bodies(list).single;
      expect(first['publishableKey'], 'pk_test_1');
      expect(first['identity'], <String, Object?>{'value': 'asha@example.com'});
      expect(first['installId'], testInstallId);
      expect(first.containsKey('cursor'), isFalse);
      expect(first.containsKey('limit'), isFalse);

      await g.chat.loadMorePastSessions();
      expect(server.bodies(list).last['cursor'], 'c2');
      expect(ids(g), <String>['a1', 'a2'], reason: 'appended, an id already kept not added twice');
      expect(g.chat.pastSessions.value.hasMore, isFalse);
      await g.chat.loadMorePastSessions();
      expect(server.bodies(list), hasLength(2), reason: 'no next page: nothing asked');

      await g.chat.refreshPastSessions();
      expect(server.bodies(list).last.containsKey('cursor'), isFalse, reason: 'a refresh reads the first page again');
      expect(ids(g), <String>['a1'], reason: 'and replaces what was loaded');
      await finish(tester, g);
    });

    testWidgets('the contract through the chat: every page, every append, every refusal', (WidgetTester tester) async {
      final server = Server();
      final g = makeApp(tester, server);
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      for (final c in section('pages')) {
        server.routes[list] = (Map<String, Object?> _) => jsonResponse(c['response']);
        await g.chat.refreshPastSessions();
        expect(ids(g), <Object?>[for (final s in (c['sessions']! as List<Object?>)) (s! as Map<String, Object?>)['id']],
            reason: c['name']! as String);
        expect(g.chat.pastSessions.value.hasMore, c['next'] != null, reason: c['name']! as String);
      }
      for (final c in section('append')) {
        final steps = (c['steps']! as List<Object?>).cast<Map<String, Object?>>();
        final states = (c['states']! as List<Object?>).cast<Map<String, Object?>>();
        for (var i = 0; i < steps.length; i++) {
          final more = steps[i].containsKey('more');
          server.routes[list] = (Map<String, Object?> _) => jsonResponse(steps[i][more ? 'more' : 'refresh']);
          await (more ? g.chat.loadMorePastSessions() : g.chat.refreshPastSessions());
          expect(ids(g), states[i]['ids'], reason: '${c['name']} #$i');
          expect(g.chat.pastSessions.value.hasMore, states[i]['hasMore'], reason: '${c['name']} #$i');
        }
      }
      server.routes[list] = (Map<String, Object?> _) => jsonResponse(page(<String>['kept'], next: 'c9'));
      await g.chat.refreshPastSessions();
      for (final c in section('refusals')) {
        server.routes[list] = (Map<String, Object?> _) => jsonResponse(c['body'], c['status']! as int);
        await g.chat.refreshPastSessions();
        final state = g.chat.pastSessions.value;
        expect(state.error, c['error'], reason: c['name']! as String);
        expect(state.loading, isFalse);
        expect(<String>[for (final s in state.sessions) s.id], <String>['kept'], reason: 'a failed read keeps what was loaded');
        expect(state.hasMore, isTrue, reason: 'and can be asked again');
      }
      await finish(tester, g);
    });

    testWidgets("nobody identified: identity_required, nothing asked — and Graine out of reach is network; never thrown",
        (WidgetTester tester) async {
      final server = Server();
      final g = makeApp(tester, server);
      await g.chat.refreshPastSessions();
      expect(g.chat.pastSessions.value.error, 'identity_required');
      expect(g.chat.pastSessions.value.sessions, isEmpty);
      expect(server.bodies(list), isEmpty, reason: 'nobody identified: nothing asked');
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      server.slowRoutes[list] = (Map<String, Object?> _) async => throw http.ClientException('offline');
      await g.chat.refreshPastSessions();
      expect(g.chat.pastSessions.value.error, 'network');
      server.slowRoutes.remove(list);
      server.routes[list] = (Map<String, Object?> _) => jsonResponse(page(<String>['a1']));
      await g.chat.refreshPastSessions();
      expect(g.chat.pastSessions.value.error, isNull, reason: 'a read that works clears the error');
      expect(ids(g), <String>['a1']);
      await finish(tester, g);
    });

    testWidgets("an identity change empties them, and a page still on its way lands nobody's", (WidgetTester tester) async {
      final server = Server();
      server.routes[list] = (Map<String, Object?> _) => jsonResponse(page(<String>['asha-1'], next: 'c2'));
      final g = makeApp(tester, server);
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      await g.chat.refreshPastSessions();
      expect(ids(g), <String>['asha-1']);

      final gate = Completer<void>();
      server.slowRoutes[list] = (Map<String, Object?> _) async {
        await gate.future;
        return jsonResponse(page(<String>['asha-2']));
      };
      final reading = g.chat.refreshPastSessions();
      await tester.pump();
      expect(g.chat.pastSessions.value.loading, isTrue);
      g.identify(<String, Object?>{'email': 'ravi@example.com'});
      expect(g.chat.pastSessions.value, GrainePastSessions.empty, reason: "Ravi must not see Asha's sessions");
      gate.complete();
      await reading;
      expect(g.chat.pastSessions.value, GrainePastSessions.empty, reason: "the answer for Asha is nobody's now");

      g.identify(<String, Object?>{'email': 'ravi@example.com', 'name': 'Ravi'});
      server.slowRoutes.remove(list);
      await g.chat.refreshPastSessions();
      expect(ids(g), <String>['asha-1'], reason: 'the route answers what it answers');
      g.identify(<String, Object?>{'email': 'ravi@example.com', 'name': 'Ravi Kumar'});
      expect(ids(g), <String>['asha-1'], reason: 'the same identity, other traits: nothing changes');
      g.identify(null);
      expect(g.chat.pastSessions.value, GrainePastSessions.empty, reason: 'signed out: nobody');
      await finish(tester, g);
    });

    testWidgets("sessionTranscript: the session asked for, in the SDK's words — the errors typed", (WidgetTester tester) async {
      final server = Server();
      final answer = (section('transcripts').first['response']! as Map<String, Object?>);
      server.routes[transcript] = (Map<String, Object?> body) => body['id'] == answer['id']
          ? jsonResponse(answer)
          : jsonResponse(<String, Object?>{'error': 'Session not found.', 'code': 'not_found'}, 404);
      final g = makeApp(tester, server);
      await expectLater(g.chat.sessionTranscript('   '),
          throwsA(isA<GraineException>().having((GraineException e) => e.code, 'code', GraineErrorCode.invalidRequest)));
      await expectLater(g.chat.sessionTranscript('ex-7a1c0001'),
          throwsA(isA<GraineException>().having((GraineException e) => e.code, 'code', GraineErrorCode.identityRequired)));
      expect(server.bodies(transcript), isEmpty, reason: 'neither asks Graine');
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      final t = await g.chat.sessionTranscript(' ex-7a1c0001 ');
      expect(t.id, 'ex-7a1c0001');
      expect(t.turns.map((GrainePastSessionTurn x) => x.role), <GrainePastSessionRole>[
        GrainePastSessionRole.agent,
        GrainePastSessionRole.customer,
        GrainePastSessionRole.agent,
      ]);
      expect(t.turns.first.at, DateTime.utc(2026, 10, 21, 12, 0, 5));
      expect(t.channel, GrainePastSessionChannel.chat);
      expect(t.durationSeconds, 276);
      final body = server.bodies(transcript).single;
      expect(body['id'], 'ex-7a1c0001');
      expect(body['identity'], <String, Object?>{'value': 'asha@example.com'});
      expect(body['installId'], testInstallId);
      expect(body['publishableKey'], 'pk_test_1');
      await expectLater(
        g.chat.sessionTranscript('someone-elses'),
        throwsA(isA<GraineException>()
            .having((GraineException e) => e.code, 'code', GraineErrorCode.notFound)
            .having((GraineException e) => e.message, 'message', 'Session not found.')),
      );
      expect(g.chat.pastSessions.value, GrainePastSessions.empty, reason: 'a transcript is not the list');
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
      expect(c.last.types, isNot(contains('stop')), reason: 'gone from the screen: the conversation is kept until it goes idle');
      expect(g.chat.connected, isTrue);
      await finish(tester, g);
    });

    testWidgets('a chat screen leaving over the bar keeps the conversation; a close from a dispose reaches the bar after that frame',
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
      expect(tester.takeException(), isNull, reason: 'told from a dispose, while the tree is locked');
      expect(c.last.types, isNot(contains('stop')), reason: 'no window shows it, and it is not idle yet');
      expect(g.chat.isOpen, isTrue);

      // An app's own screen that closes the chat as it goes.
      await tester.pumpWidget(screen(<Widget>[const GraineAgentBar(showComponents: false), _ClosesOnDispose(g.chat)]));
      await tester.pumpWidget(screen(const <Widget>[GraineAgentBar(showComponents: false)]));
      expect(tester.takeException(), isNull, reason: 'closed from a dispose, while the tree is locked');
      expect(c.last.types.last, 'stop');
      await tester.pump();
      expect(g.chat.isOpen, isFalse);
      await tester.pumpWidget(const SizedBox());
      await finish(tester, g);
    });
  });

  // 0.14.3: closed chatCloseDelaySeconds (15 by default) after it leaves every screen — 5 idle minutes in 0.14.0–0.14.1.
  group('how long a conversation lasts', () {
    testWidgets('the chat window closed, the conversation is kept 15 seconds — counted from when it left — then closed cleanly',
        (WidgetTester tester) async {
      final c = Connector();
      final g = makeApp(tester, Server(), connector: c, install: true);
      await g.loadSession();
      final s = await onScreen(tester, g, c);
      s.say(said('Hi, I am Asha.'));
      await tester.pump();
      // The last message long before the window goes: the wait counts from the window.
      await tester.pump(const Duration(minutes: 2));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 14, milliseconds: 999));
      expect(g.chat.connected, isTrue, reason: 'kept for 15 seconds once no window shows it');
      expect(s.types, isNot(contains('stop')));
      await tester.pump(const Duration(milliseconds: 1));
      expect(s.types.last, 'stop', reason: '15 seconds with no window: it ends cleanly');
      expect(g.chat.isOpen, isFalse);
      expect(g.chat.status, GraineChatStatus.idle, reason: 'the SDK closed it: not "Disconnected", nothing failed');
      await tester.pump(const Duration(milliseconds: 200));
      expect(s.closed, isTrue);
      await tester.pump(const Duration(minutes: 1));
      expect(c.sockets, hasLength(1), reason: 'a conversation closed with no window does not reconnect by itself');
      await finish(tester, g);
    });

    testWidgets("a message while no window shows the chat starts its wait again — the agent's or the customer's",
        (WidgetTester tester) async {
      final c = Connector();
      final g = makeApp(tester, Server(), connector: c, install: true);
      await g.loadSession();
      final s = await onScreen(tester, g, c);
      s.say(said('Hi, I am Asha.'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
      s.say(said('Your order left the warehouse.'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      expect(g.chat.connected, isTrue, reason: "20 seconds since the window closed, 10 since the agent's message");
      g.chat.send('Thanks!');
      await tester.pump(const Duration(seconds: 14, milliseconds: 999));
      expect(g.chat.connected, isTrue, reason: "the customer's message started the wait again");
      await tester.pump(const Duration(milliseconds: 1));
      expect(s.types.last, 'stop');
      await finish(tester, g);
    });

    testWidgets('chatCloseDelaySeconds: a delay of your own, 0 at once, and held to 0–300',
        (WidgetTester tester) async {
      Future<void> closesAfter(num seconds, Duration expected) async {
        final c = Connector();
        final g = makeApp(tester, Server(), connector: c, install: true,
            config: GraineConfig(baseUrl: base, publishableKey: 'pk_test_1', chatCloseDelaySeconds: seconds));
        await g.loadSession();
        final s = await onScreen(tester, g, c);
        await tester.pumpWidget(const SizedBox());
        if (expected > Duration.zero) {
          await tester.pump(expected - const Duration(milliseconds: 1));
          expect(s.types, isNot(contains('stop')), reason: '$seconds: still kept');
          await tester.pump(const Duration(milliseconds: 1));
        }
        expect(s.types.last, 'stop', reason: '$seconds: closed after $expected');
        expect(g.chat.isOpen, isFalse);
        await finish(tester, g);
      }

      await closesAfter(42, const Duration(seconds: 42));
      await closesAfter(0, Duration.zero);
      await closesAfter(-5, Duration.zero);
      await closesAfter(1000, const Duration(seconds: 300));
      await closesAfter(double.nan, const Duration(seconds: 15));
      await closesAfter(2.5, const Duration(milliseconds: 2500));
    });

    testWidgets('closed with no window, opened again: it connects again — the history continues the conversation, nothing twice',
        (WidgetTester tester) async {
      final c = Connector();
      final g = makeApp(tester, Server(), connector: c, install: true);
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      await g.loadSession();
      final s = await onScreen(tester, g, c);
      s.say(said('Hi, I am Asha.'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 15));
      expect(s.types.last, 'stop');
      await tester.pump(const Duration(milliseconds: 300));
      final again = await onScreen(tester, g, c);
      expect(c.sockets, hasLength(2), reason: 'opening the chat connects it again');
      again.say(<String, Object?>{
        'type': 'history',
        'continued': true,
        'turns': <Object?>[
          <String, Object?>{'id': 'h1', 'role': 'assistant', 'text': 'Hi, I am Asha.', 'at': '2026-10-21T10:00:00Z', 'channel': 'chat'},
        ],
      });
      await tester.pump();
      expect(g.chat.turns.map((GraineChatTurn t) => t.text), <String>['Hi, I am Asha.'], reason: 'the history holds the lines on screen');
      expect(g.chat.newConversationBefore, isEmpty, reason: 'it continued: no new conversation');
      await tester.pumpWidget(const SizedBox());
      await finish(tester, g);
    });

    testWidgets('opening the chat again within the wait goes on with the same conversation: no new connection or welcome',
        (WidgetTester tester) async {
      final c = Connector();
      final g = makeApp(tester, Server(), connector: c, install: true);
      await g.loadSession();
      final s = await onScreen(tester, g, c);
      s.say(said('Hi, I am Asha.'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 14));
      await onScreen(tester, g, c);
      expect(c.sockets, hasLength(1), reason: 'the same connection, so the agent does not welcome the customer again');
      expect(find.text('Hi, I am Asha.'), findsOneWidget);
      await tester.pump(const Duration(minutes: 6));
      expect(g.chat.connected, isTrue, reason: 'on screen again: it is not closed');
      expect(s.types, isNot(contains('stop')));
      await tester.pumpWidget(const SizedBox());
      await finish(tester, g);
    });

    testWidgets('idle (4408): Graine ended it — no reconnect, the lines stay, "Disconnected"; the next message connects again',
        (WidgetTester tester) async {
      final c = Connector();
      final g = makeApp(tester, Server(), connector: c, install: true);
      await g.loadSession();
      final s = await onScreen(tester, g, c);
      s.say(said('Hi, I am Asha.'));
      await tester.pump();
      s.drop(code: 4408);
      await tester.pump();
      expect(g.chat.connected || g.chat.connecting || g.chat.reconnecting, isFalse, reason: 'nothing reconnects by itself');
      expect(find.text('Disconnected'), findsOneWidget, reason: "the header's status line");
      expect(find.text('Hi, I am Asha.'), findsOneWidget, reason: 'the lines stay');
      await tester.pump(const Duration(minutes: 1));
      g.setForegroundForTesting(false);
      await tester.pump(const Duration(seconds: 3));
      g.setForegroundForTesting(true);
      await tester.pump();
      await tester.pump();
      expect(c.sockets, hasLength(1), reason: 'not even back in the foreground');

      g.chat.send('Still there?');
      await tester.pump();
      await tester.pump();
      expect(c.sockets, hasLength(2), reason: "the customer's message connects again");
      expect(c.last.sent.where((Map<String, Object?> m) => m['type'] == 'text').single['data'], 'Still there?');
      expect(find.text('Disconnected'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await finish(tester, g);
    });

    testWidgets("the session's time limit (4410): the same — and opening the chat again connects again",
        (WidgetTester tester) async {
      final c = Connector();
      final g = makeApp(tester, Server(), connector: c, install: true);
      await g.loadSession();
      final s = await onScreen(tester, g, c);
      s.say(said('Hi, I am Asha.'));
      await tester.pump();
      s.drop(code: 4410);
      await tester.pump();
      expect(find.text('Disconnected'), findsOneWidget);
      await tester.pump(const Duration(minutes: 1));
      expect(c.sockets, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      await onScreen(tester, g, c);
      expect(c.sockets, hasLength(2), reason: 'opened again: a new connection');
      expect(find.text('Disconnected'), findsNothing);
      expect(find.text('Hi, I am Asha.'), findsOneWidget, reason: 'the earlier lines are still there');
      await tester.pumpWidget(const SizedBox());
      await finish(tester, g);
    });

    testWidgets('in the bar, its status line says "Disconnected" too', (WidgetTester tester) async {
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
      await tester.tap(find.byKey(GraineAgentBar.switchButtonKey));
      await tester.pump();
      await tester.pump();
      expect(g.chat.connected, isTrue);
      c.last.drop(code: 4408);
      await tester.pump();
      expect(find.text('Disconnected'), findsNWidgets(2), reason: "the chat window's header and the bar's status line");
      await tester.pumpWidget(const SizedBox());
      await finish(tester, g);
    });

    testWidgets('any other close is a dropped connection: it reconnects, as before', (WidgetTester tester) async {
      final c = Connector();
      final g = makeApp(tester, Server(), connector: c, install: true);
      await g.loadSession();
      final s = await onScreen(tester, g, c);
      s.drop(code: 1011);
      await tester.pump();
      expect(g.chat.reconnecting, isTrue);
      expect(find.text('Disconnected'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pump();
      expect(c.sockets, hasLength(2));
      expect(g.chat.connected, isTrue);
      await tester.pumpWidget(const SizedBox());
      await finish(tester, g);
    });

    testWidgets('a call with the same agent ends a conversation no window shows: one conversation with an agent at a time',
        (WidgetTester tester) async {
      final c = Connector();
      final g = makeApp(tester, Server(), connector: c, install: true);
      await g.loadSession();
      final s = await onScreen(tester, g, c);
      await tester.pumpWidget(const SizedBox());
      final page = FakePage();
      g.voice.attach(page);
      await tester.pump();
      page.say(<String, Object?>{'type': 'graine:ready'});
      await tester.pump();
      await g.voice.start();
      expect(s.types.last, 'stop');
      expect(g.chat.isOpen, isFalse);
      await finish(tester, g);
    });

    testWidgets('the background ends a conversation no window shows, and so does close() — at once',
        (WidgetTester tester) async {
      final c = Connector();
      final g = makeApp(tester, Server(), connector: c, install: true);
      await g.loadSession();
      final s = await onScreen(tester, g, c);
      await tester.pumpWidget(const SizedBox());
      g.setForegroundForTesting(false);
      await tester.pump(const Duration(seconds: 2));
      expect(s.types.last, 'stop');
      g.setForegroundForTesting(true);
      await tester.pump();
      await tester.pump();
      expect(c.sockets, hasLength(1), reason: 'nobody is in the chat to reconnect it for');
      expect(g.chat.isOpen, isFalse);

      final again = await onScreen(tester, g, c);
      await tester.pumpWidget(const SizedBox());
      g.chat.close();
      expect(again.types.last, 'stop');
      await tester.pump(const Duration(minutes: 6));
      expect(c.sockets, hasLength(2));
      await finish(tester, g);
    });
  });

  group('a new conversation under earlier lines', () {
    testWidgets('a reconnect that starts over: a marker over the new welcome — an opening nobody answered is replaced',
        (WidgetTester tester) async {
      final c = Connector();
      final g = makeApp(tester, Server(), connector: c, install: true);
      await g.loadSession();
      final first = await onScreen(tester, g, c);
      first.say(said('Hi, I am Asha.'));
      await tester.pump();
      g.chat.send('Is my dose due?');
      first.say(said('Yes, at 8 pm.'));
      await tester.pump();
      first.drop();
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pump();
      expect(c.sockets, hasLength(2));
      c.last.say(said('Hi, I am Asha.'));
      await tester.pump();
      await tester.pump();
      expect(g.chat.turns.map((GraineChatTurn t) => t.text), <String>['Hi, I am Asha.', 'Is my dose due?', 'Yes, at 8 pm.', 'Hi, I am Asha.'],
          reason: 'turns are what they always were: the marker is not one');
      final welcome = g.chat.turns.last.id;
      expect(find.byKey(ChatWindow.markKey(welcome)), findsOneWidget);
      expect(find.text('Disconnected · new conversation'), findsOneWidget);

      // Dropped again before the customer said anything: the new opening replaces that one.
      c.last.drop();
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pump();
      c.last.say(said('Hi, I am Asha.'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Hi, I am Asha.'), findsNWidgets(2), reason: 'never a third welcome');
      expect(find.text('Disconnected · new conversation'), findsOneWidget);
      expect(find.byKey(ChatWindow.markKey(g.chat.turns.last.id)), findsOneWidget);

      await g.chat.newConversation();
      await tester.pump();
      expect(find.text('Disconnected · new conversation'), findsNothing, reason: 'New conversation takes it away with the lines');
      await tester.pumpWidget(const SizedBox());
      await finish(tester, g);
    });
  });

  // 0.14.0 — contract/PUBLIC-STATE.md §1: everything the SDK's chat windows
  // read, for a chat screen of the app's own.
  group('public state for a chat of your own', () {
    testWidgets('status: idle, connecting, connected; reconnecting after a drop; failed once every try is spent; idle once closed',
        (WidgetTester tester) async {
      final c = Connector();
      final g = makeApp(tester, Server(), connector: c, install: true);
      await g.loadSession();
      expect(g.chat.status, GraineChatStatus.idle);
      g.chat.open();
      expect(g.chat.status, GraineChatStatus.connecting);
      await tester.pump();
      await tester.pump();
      expect(g.chat.status, GraineChatStatus.connected);
      expect(g.chat.status.wire, 'connected');
      c.fail = true;
      c.last.drop();
      await tester.pump();
      expect(g.chat.status, GraineChatStatus.reconnecting, reason: 'a drop, retrying');
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(seconds: 20));
        await tester.pump();
      }
      expect(g.chat.status, GraineChatStatus.failed);
      c.fail = false;
      g.chat.retry();
      expect(g.chat.status, GraineChatStatus.connecting, reason: 'a tap tries again, from the start');
      await tester.pump();
      await tester.pump();
      expect(g.chat.status, GraineChatStatus.connected);
      g.chat.close();
      expect(g.chat.status, GraineChatStatus.idle);
      await finish(tester, g);
    });

    testWidgets('status disconnected: Graine ended it (4408) and it waits for the customer; their message connects again',
        (WidgetTester tester) async {
      final c = Connector();
      final g = makeApp(tester, Server(), connector: c, install: true);
      await g.loadSession();
      final s = await connected(tester, g, c);
      s.say(said('Hi, I am Asha.'));
      await tester.pump();
      s.drop(code: 4408);
      await tester.pump();
      expect(g.chat.status, GraineChatStatus.disconnected);
      expect(g.chat.status.wire, 'disconnected');
      await tester.pump(const Duration(minutes: 1));
      expect(g.chat.status, GraineChatStatus.disconnected, reason: 'nothing reconnects by itself');
      g.chat.send('Still there?');
      expect(g.chat.status, GraineChatStatus.connecting);
      await tester.pump();
      await tester.pump();
      expect(g.chat.status, GraineChatStatus.connected);
      await finish(tester, g);
    });

    testWidgets("status after the agent's goodbye: idle, not failed — the customer's next message starts over",
        (WidgetTester tester) async {
      final c = Connector();
      final g = makeApp(tester, Server(), connector: c, install: true);
      await g.loadSession();
      final s = await connected(tester, g, c);
      s.say(said('Glad I could help. Goodbye!'));
      s.say(<String, Object?>{'type': 'conversation_end'});
      await tester.pump();
      s.drop(code: 1000);
      await tester.pump();
      expect(g.chat.ended, isTrue);
      expect(g.chat.status, GraineChatStatus.idle);
      await tester.pump(const Duration(seconds: 30));
      expect(c.sockets, hasLength(1), reason: 'a goodbye is not reconnected');
      g.chat.send('One more thing');
      expect(g.chat.status, GraineChatStatus.connecting);
      await tester.pump();
      await tester.pump();
      expect(g.chat.status, GraineChatStatus.connected);
      await finish(tester, g);
    });

    testWidgets('status offline: in the chat, a message waiting, nothing connecting it — until something does',
        (WidgetTester tester) async {
      final c = Connector();
      final g = makeApp(tester, Server(), connector: c, install: true);
      await g.loadSession();
      g.setForegroundForTesting(false);
      g.chat.send('Hello?');
      await tester.pump();
      expect(g.chat.status, GraineChatStatus.offline, reason: 'in the background nothing connects; the message waits');
      expect(g.chat.turns.single.delivery, GraineChatDelivery.sending);
      g.setForegroundForTesting(true);
      await tester.pump();
      await tester.pump();
      expect(g.chat.status, GraineChatStatus.connected);
      expect(g.chat.turns.single.delivery, GraineChatDelivery.sent);
      await finish(tester, g);
    });

    testWidgets('newConversationBefore: where a new conversation began under earlier lines — ChatRows.build lays it out',
        (WidgetTester tester) async {
      final c = Connector();
      final g = makeApp(tester, Server(), connector: c, install: true);
      await g.loadSession();
      final first = await connected(tester, g, c);
      first.say(said('Hi, I am Asha.'));
      await tester.pump();
      g.chat.send('Is my dose due?');
      first.say(said('Yes, at 8 pm.'));
      await tester.pump();
      expect(g.chat.newConversationBefore, isEmpty);
      first.drop();
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pump();
      c.last.say(said('Hi, I am Asha.'));
      await tester.pump();
      final welcome = g.chat.turns.last;
      expect(g.chat.newConversationBefore, <String>{welcome.id});
      expect(g.chat.turns, hasLength(4), reason: 'turns are what they always were');

      final rows = ChatRows.build(g.chat.turns, now: DateTime.now(), newConversationBefore: g.chat.newConversationBefore);
      final marker = rows.whereType<ChatNewConversationRow>().single;
      expect(marker.before, welcome.id);
      expect(marker.key, 'fresh-${welcome.id}');
      expect(marker.label, 'Disconnected · new conversation');
      expect(marker.spoken, 'Disconnected. A new conversation started.');
      expect(rows.indexOf(marker), rows.length - 2, reason: 'just before the turn it marks');
      expect((rows.last as ChatTurnRow).turn.id, welcome.id);
      expect(ChatRows.build(g.chat.turns, now: DateTime.now()).whereType<ChatNewConversationRow>(), isEmpty,
          reason: 'only when asked for: a chat that never asks sees the rows it always did');

      await g.chat.newConversation();
      expect(g.chat.newConversationBefore, isEmpty, reason: 'New conversation takes the markers away with the lines');
      await finish(tester, g);
    });

    testWidgets("shown(): a screen of the app's own keeps the conversation as the SDK's windows do — 15 seconds, then closed",
        (WidgetTester tester) async {
      final c = Connector();
      final g = makeApp(tester, Server(), connector: c, install: true);
      await g.loadSession();
      g.chat.shown(true);
      await tester.pump();
      await tester.pump();
      expect(g.chat.status, GraineChatStatus.connected, reason: 'shown, the chat opens');
      final s = c.last;
      s.say(said('Hi, I am Asha.'));
      await tester.pump();
      g.chat.shown(false);
      await tester.pump(const Duration(seconds: 14, milliseconds: 999));
      expect(g.chat.connected, isTrue, reason: 'gone from the screen: kept for 15 seconds');
      g.chat.shown(true);
      await tester.pump();
      expect(c.sockets, hasLength(1), reason: 'shown again in time: the same conversation, no new welcome');
      expect(g.chat.connected, isTrue);
      g.chat.shown(false);
      await tester.pump(const Duration(seconds: 15));
      expect(s.types.last, 'stop', reason: '15 seconds with no screen: it closes cleanly');
      expect(g.chat.isOpen, isFalse);
      expect(g.chat.status, GraineChatStatus.idle);
      await tester.pump(const Duration(milliseconds: 300));

      // A chat nobody reports is kept until Graine's own idle limit.
      g.chat.open();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(minutes: 10));
      expect(g.chat.connected, isTrue);
      await finish(tester, g);
    });
  });

  // 0.14.0 — contract/DESIGN.md "Who a chat belongs to": every case.
  group('who a chat belongs to', () {
    testWidgets('a user to another, and a user to nobody: closed quietly, a fresh ticket for whoever is identified now — never a banner',
        (WidgetTester tester) async {
      final server = Server();
      final c = Connector();
      final g = makeApp(tester, server, connector: c);
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      final heard = <GraineChatStatus>[];
      g.chat.addListener(() => heard.add(g.chat.status));
      final first = await connected(tester, g, c);
      first.say(said('Hello Asha.'));
      await tester.pump();
      g.identify(<String, Object?>{'email': 'ravi@example.com'});
      await tester.pump();
      await tester.pump();
      expect(first.types.last, 'stop');
      expect(g.chat.turns, isEmpty);
      expect(c.sockets, hasLength(2));
      expect(server.bodies('/api/embed/ticket').last['identity'], <String, Object?>{'value': 'ravi@example.com'});
      c.last.say(said('Hello Ravi.'));
      await tester.pump();
      g.identify(null);
      await tester.pump();
      await tester.pump();
      expect(g.chat.turns, isEmpty);
      expect(c.sockets, hasLength(3));
      expect(server.bodies('/api/embed/ticket').last.containsKey('identity'), isFalse, reason: 'signed out: anonymous');
      expect(heard, isNot(contains(GraineChatStatus.disconnected)));
      expect(heard, isNot(contains(GraineChatStatus.reconnecting)), reason: 'no reconnect banner');
      await finish(tester, g);
    });

    testWidgets('the same identity — other traits, another memory choice, another spelling — changes nothing on the open chat',
        (WidgetTester tester) async {
      final c = Connector();
      final g = makeApp(tester, Server(), connector: c);
      g.identify(<String, Object?>{'email': 'asha@example.com', 'name': 'Asha'});
      final first = await connected(tester, g, c);
      first.say(said('Hello Asha.'));
      await tester.pump();
      g.identify(<String, Object?>{'email': 'Asha@Example.com ', 'name': 'Asha K', 'plan': 'Gold'});
      g.identify(<String, Object?>{'email': 'asha@example.com'}, memory: false);
      g.setMemory(true);
      await tester.pump();
      await tester.pump();
      expect(c.sockets, hasLength(1));
      expect(first.types, isNot(contains('stop')));
      expect(g.chat.turns.map((GraineChatTurn t) => t.text), <String>['Hello Asha.']);
      await finish(tester, g);
    });

    testWidgets('a line typed and not yet sent stays, and goes on the next connection — as the new identity',
        (WidgetTester tester) async {
      final server = Server();
      final c = Connector();
      final g = makeApp(tester, server, connector: c);
      final first = await connected(tester, g, c);
      first.say(said('Hi there.'));
      await tester.pump();
      c.fail = true;
      first.drop();
      await tester.pump();
      g.chat.send('Typed in the tunnel');
      await tester.pump();
      expect(g.chat.turns.last.delivery, GraineChatDelivery.sending);
      c.fail = false;
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      expect(g.chat.turns.map((GraineChatTurn t) => t.text), <String>['Typed in the tunnel'],
          reason: 'only the line not yet sent stays');
      await tester.pump();
      await tester.pump();
      expect(server.bodies('/api/embed/ticket').last['identity'], <String, Object?>{'value': 'asha@example.com'});
      expect(c.last.sent.where((Map<String, Object?> m) => m['type'] == 'text').map((Map<String, Object?> m) => m['data']),
          <Object?>['Typed in the tunnel']);
      expect(g.chat.turns.single.delivery, GraineChatDelivery.sent);
      await finish(tester, g);
    });

    testWidgets('identified while the chat is being made: that connection lands nobody\'s; the line waiting goes on the user\'s',
        (WidgetTester tester) async {
      final server = Server();
      final c = _GatedConnector();
      final g = makeApp(tester, server, connector: c);
      await g.loadSession();
      g.chat.send('Hello?');
      await tester.pump();
      expect(c.calls, 1, reason: 'a connection is being made, for nobody');
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      await tester.pump();
      await tester.pump();
      c.gate.complete();
      await tester.pump();
      await tester.pump();
      final open = c.sockets.where((FakeSocket s) => !s.closed).toList();
      expect(open, hasLength(1), reason: 'the one made for nobody closed itself as it landed');
      expect(server.bodies('/api/embed/ticket').last['identity'], <String, Object?>{'value': 'asha@example.com'});
      expect(open.single.sent.where((Map<String, Object?> m) => m['type'] == 'text').map((Map<String, Object?> m) => m['data']),
          <Object?>['Hello?']);
      expect(c.sockets.where((FakeSocket s) => s.closed).single.sent, isEmpty, reason: 'nothing was said on it');
      await finish(tester, g);
    });

    testWidgets("not connected — Graine ended it: the turns go, Disconnected goes, nothing connects until the next message",
        (WidgetTester tester) async {
      final server = Server();
      final c = Connector();
      final g = makeApp(tester, server, connector: c, install: true);
      await g.loadSession();
      final s = await onScreen(tester, g, c);
      s.say(said('Hi, I am Asha.'));
      await tester.pump();
      s.drop(code: 4408);
      await tester.pump();
      expect(g.chat.status, GraineChatStatus.disconnected);
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      await tester.pump();
      await tester.pump();
      expect(g.chat.turns, isEmpty);
      expect(g.chat.status, isNot(GraineChatStatus.disconnected), reason: 'the Disconnected was the identity before\'s');
      expect(find.text('Disconnected'), findsNothing);
      expect(c.sockets, hasLength(1), reason: 'nothing connects by itself');
      g.chat.send('Still there?');
      await tester.pump();
      await tester.pump();
      expect(c.sockets, hasLength(2), reason: 'the next message connects');
      expect(server.bodies('/api/embed/ticket').last['identity'], <String, Object?>{'value': 'asha@example.com'});
      await tester.pumpWidget(const SizedBox());
      await finish(tester, g);
    });

    testWidgets('not connected — every retry spent: a failed line stays, still failed; it goes on the next connection',
        (WidgetTester tester) async {
      final server = Server();
      final c = Connector();
      final g = makeApp(tester, server, connector: c);
      final first = await connected(tester, g, c);
      c.fail = true;
      first.drop();
      await tester.pump();
      g.chat.send('Lost line');
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(seconds: 20));
        await tester.pump();
      }
      expect(g.chat.failed, isTrue);
      expect(g.chat.turns.last.delivery, GraineChatDelivery.failed);
      final made = c.sockets.length;
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      await tester.pump();
      expect(g.chat.turns.map((GraineChatTurn t) => '${t.text}:${t.delivery?.name}'), <String>['Lost line:failed']);
      expect(g.chat.failed, isTrue, reason: 'giving up is not the identity before\'s to take away');
      await tester.pump(const Duration(seconds: 30));
      expect(c.sockets.length, made, reason: 'nothing connects by itself');
      c.fail = false;
      g.chat.retry();
      await tester.pump();
      await tester.pump();
      expect(server.bodies('/api/embed/ticket').last['identity'], <String, Object?>{'value': 'asha@example.com'});
      expect(c.last.sent.where((Map<String, Object?> m) => m['type'] == 'text').map((Map<String, Object?> m) => m['data']),
          <Object?>['Lost line']);
      await finish(tester, g);
    });

    testWidgets('the markers and the booked calls go with the turns; the calls are read again for the new identity',
        (WidgetTester tester) async {
      final server = Server();
      server.routes['/api/embed/calls/list'] = (Map<String, Object?> body) {
        final who = (body['identity'] as Map<String, Object?>?)?['value'];
        return jsonResponse(<String, Object?>{
          'calls': <Object?>[
            if (who == 'asha@example.com')
              <String, Object?>{'id': 'sc_1', 'at': '2030-01-01T10:00:00Z', 'status': 'scheduled', 'source': 'sdk'},
          ],
        });
      };
      final c = Connector();
      final g = makeApp(tester, server, connector: c, install: true);
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      final first = await connected(tester, g, c);
      await tester.pump();
      await tester.pump();
      expect(g.chat.upcomingCalls.map((GraineScheduledCall x) => x.id), <String>['sc_1']);
      first.say(said('Hi, I am Asha.'));
      g.chat.send('Is my dose due?');
      first.say(said('Yes, at 8 pm.'));
      await tester.pump();
      first.drop();
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pump();
      c.last.say(said('Hi, I am Asha.'));
      await tester.pump();
      expect(g.chat.newConversationBefore, isNotEmpty, reason: 'a marker, before the new welcome');
      final lists = server.bodies('/api/embed/calls/list').length;
      g.identify(<String, Object?>{'email': 'ravi@example.com'});
      expect(g.chat.newConversationBefore, isEmpty, reason: 'the markers go with the turns');
      expect(g.chat.upcomingCalls, isEmpty, reason: "Asha's booked calls are not Ravi's");
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(server.bodies('/api/embed/calls/list').length, greaterThan(lists), reason: 'read again for the new identity');
      expect(server.bodies('/api/embed/calls/list').last['identity'], <String, Object?>{'value': 'ravi@example.com'});
      expect(g.chat.upcomingCalls, isEmpty);
      await finish(tester, g);
    });

    testWidgets('a chat no window shows, still connected, is wanted: it connects again at once — and still closes with no window',
        (WidgetTester tester) async {
      final server = Server();
      final c = Connector();
      final g = makeApp(tester, server, connector: c, install: true);
      await g.loadSession();
      final s = await onScreen(tester, g, c);
      s.say(said('Hi.'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      g.identify(<String, Object?>{'email': 'asha@example.com'});
      await tester.pump();
      await tester.pump();
      expect(c.sockets, hasLength(2));
      expect(server.bodies('/api/embed/ticket').last['identity'], <String, Object?>{'value': 'asha@example.com'});
      await tester.pump(const Duration(seconds: 15));
      expect(c.last.types.last, 'stop', reason: 'no window for 15 seconds: it closes as before');
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
