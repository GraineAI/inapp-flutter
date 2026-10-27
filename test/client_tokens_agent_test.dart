// SERVER TOKENS ON A REAL AGENT (CLIENT-TOKENS.md §2.2–2.5) — GraineInApp with
// the network, the chat's socket, the engine page and the native call engine's
// channel faked: with a provider every request the Dart side makes to Graine
// carries the token (the session, the chat's ticket, sign-out, booking,
// memory, a new conversation, past sessions); without one none does. A token
// that expires while a chat or a call is live ends and reconnects nothing. A
// refusal a fresh token lifts asks once and goes once more, only with a new
// token; token_scope and key_revoked are final — a request throws them, a chat
// fails with them and tries no other way in. The engine page is handed every
// token and answered when it asks; the native call engine is pushed every
// token (`setClientToken`) and answered when it asks (`needClientToken`).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graine_inapp/graine_inapp.dart';
import 'package:graine_inapp/src/core/core.dart' show ClientTokenRules;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'client_tokens_support.dart' show jtiOf, mintToken;
import 'device_mock.dart';

const String base = 'https://www.graine.ai';
const String gateway = 'wss://gateway.test/v1/embed';
const String sessionRoute = '/api/embed/session';
const String ticketRoute = '/api/embed/ticket';
const String listRoute = '/api/embed/calls/list';

http.Response jsonResponse(Object? body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: const <String, String>{'content-type': 'application/json'},
    );

http.Response refusal(String code, int status, {String? reason}) => jsonResponse(
    <String, Object?>{'error': 'Refused for its $code.', 'code': code, if (reason != null) 'reason': reason}, status);

/// Graine, as far as the SDK can tell. Every request is kept; [route] answers first when it answers at all.
class Server {
  final List<http.Request> requests = <http.Request>[];
  http.Response? Function(String path, Map<String, Object?> body)? route;

  late final http.Client client = MockClient((http.Request req) async {
    requests.add(req);
    final path = req.url.path;
    final body = req.body.isEmpty ? <String, Object?>{} : jsonDecode(req.body) as Map<String, Object?>;
    return route?.call(path, body) ?? _answer(path, body);
  });

  static http.Response _answer(String path, Map<String, Object?> body) => switch (path) {
        sessionRoute => jsonResponse(<String, Object?>{
            'agentId': 'agent-1',
            'webcallAgentId': 'webcall-1',
            'pageVersion': 'dpl_42',
            'appearance': <String, Object?>{'mode': 'both', 'title': 'Acme'},
            'identity': <String, Object?>{'field': 'user_id'},
            'memory': <String, Object?>{'enabled': true},
            'calls': <String, Object?>{
              'hosted': true,
              'platforms': <Object?>['android', 'ios'],
              'scheduling': <String, Object?>{'usersCanBook': true, 'maxDaysAhead': 14, 'minLeadMinutes': 5},
            },
          }),
        ticketRoute => jsonResponse(<String, Object?>{'ticket': 'tkt_1', 'wsUrl': gateway}),
        '/api/embed/calls/schedule' => jsonResponse(<String, Object?>{
            'call': <String, Object?>{'id': 'sc_1', 'at': body['at'], 'status': 'scheduled'},
          }),
        listRoute => jsonResponse(<String, Object?>{'calls': <Object?>[]}),
        '/api/embed/calls/cancel' => jsonResponse(<String, Object?>{'ok': true, 'status': 'cancelled'}),
        '/api/embed/memory/list' => jsonResponse(<String, Object?>{'memories': <Object?>[]}),
        '/api/embed/memory/forget' => jsonResponse(<String, Object?>{'deleted': 2}),
        '/api/embed/sessions/list' => jsonResponse(<String, Object?>{'sessions': <Object?>[], 'next': null}),
        '/api/embed/sessions/transcript' => jsonResponse(<String, Object?>{'id': body['id'], 'turns': <Object?>[]}),
        _ => jsonResponse(<String, Object?>{'ok': true}),
      };

  List<Map<String, Object?>> bodies(String path) => <Map<String, Object?>>[
        for (final r in requests)
          if (r.url.path == path) jsonDecode(r.body) as Map<String, Object?>,
      ];
}

/// One chat socket, as the chat session sees it.
class FakeSocket implements GraineChatSocket {
  FakeSocket(this.protocols);

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

  List<Object?> get types => <Object?>[for (final m in sent) m['type']];
}

class Connector {
  final List<FakeSocket> sockets = <FakeSocket>[];

  Future<GraineChatSocket> call(Uri url, List<String>? protocols) async {
    final s = FakeSocket(protocols);
    sockets.add(s);
    return s;
  }
}

/// What a page receives.
class FakePage implements GraineEnginePage {
  late GraineEngineSink sink;
  final List<String> scripts = <String>[];
  int reloads = 0;

  @override
  void bind(GraineEngineSink s) => sink = s;
  @override
  void load(String url) {}
  @override
  void reload() => reloads++;
  @override
  void run(String javaScript) => scripts.add(javaScript);
  @override
  void dispose() {}

  List<Map<String, Object?>> get posted => <Map<String, Object?>>[
        for (final js in scripts)
          if (js.startsWith('window.postMessage('))
            jsonDecode(js.substring('window.postMessage('.length, js.lastIndexOf(', "*")'))) as Map<String, Object?>,
      ];

  List<Map<String, Object?>> ofType(String type) => <Map<String, Object?>>[for (final m in posted) if (m['type'] == type) m];

  void say(Map<String, Object?> message) => sink.message(jsonEncode(message));
}

class Heard with GraineListener {
  final List<String> errors = <String>[];

  @override
  void onError(String message) => errors.add(message);
}

/// One whole agent turn, as the runtime sends it.
Map<String, Object?> said(String words) => <String, Object?>{'type': 'text', 'data': '<beginning_of_stream>$words<end_of_stream>'};

int nowSec(WidgetTester tester) => tester.binding.clock.now().millisecondsSinceEpoch ~/ 1000;

GraineInApp makeApp(WidgetTester tester, Server server, {Connector? connector, Future<String?> Function()? tokens}) =>
    GraineInApp.forTesting(
      GraineConfig(baseUrl: base, publishableKey: 'pk_test_1', tokenProvider: tokens),
      httpClient: server.client,
      clock: () => tester.binding.clock.now().millisecondsSinceEpoch,
      chatConnector: connector?.call,
    );

Future<void> finish(WidgetTester tester, GraineInApp g) async {
  g.dispose();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> pumps(WidgetTester tester, [int n = 3]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => DeviceMock().install());
  tearDown(DeviceMock.uninstall);

  /// Every route the Dart side asks on its own, once each at least.
  Future<void> everyRoute(WidgetTester tester, GraineInApp g) async {
    g.identify(<String, Object?>{'user_id': 'u-1'});
    await pumps(tester);
    final later = tester.binding.clock.now().toUtc().add(const Duration(hours: 3));
    await g.scheduleCall(at: DateTime.utc(later.year, later.month, later.day, later.hour, later.minute), reason: 'billing');
    await g.scheduledCalls();
    await g.cancelScheduledCall('sc_1');
    await g.memories();
    await g.forgetMemory();
    await g.chat.refreshPastSessions();
    await g.chat.sessionTranscript('s_1');
    g.chat.open();
    await pumps(tester);
    expect(g.chat.connected, isTrue, reason: 'the chat did not connect');
    await g.chat.newConversation();
    await pumps(tester);
    g.identify(null);
    await pumps(tester);
  }

  const List<String> routes = <String>[
    sessionRoute, ticketRoute, '/api/embed/calls/schedule', listRoute, '/api/embed/calls/cancel', '/api/embed/memory/list',
    '/api/embed/memory/forget', '/api/embed/sessions/list', '/api/embed/sessions/transcript', '/api/embed/conversation/new',
    '/api/embed/identity/signout',
  ];

  group('the wire', () {
    testWidgets('with a provider every request carries the token — asked once, before the session',
        (WidgetTester tester) async {
      final server = Server();
      final token = mintToken(nowSec(tester), nowSec(tester) + 3600, id: 'ct_app');
      var asked = 0;
      final g = makeApp(tester, server, connector: Connector(), tokens: () async {
        asked++;
        return token;
      });
      expect(asked, 1, reason: 'asked at start');
      await everyRoute(tester, g);
      for (final route in routes) {
        expect(server.bodies(route), isNotEmpty, reason: '$route was asked');
      }
      for (final r in server.requests) {
        expect((jsonDecode(r.body) as Map<String, Object?>)[ClientTokenRules.field], token, reason: r.url.path);
      }
      expect(asked, 2, reason: 'one token, used everywhere — and asked anew once identify(null) let it go (another user)');
      await finish(tester, g);
    });

    testWidgets('without a provider no request carries one, and nothing about a request changes', (WidgetTester tester) async {
      final server = Server();
      final g = makeApp(tester, server, connector: Connector());
      await everyRoute(tester, g);
      for (final route in routes) {
        expect(server.bodies(route), isNotEmpty, reason: '$route was asked');
      }
      for (final r in server.requests) {
        expect((jsonDecode(r.body) as Map<String, Object?>).containsKey(ClientTokenRules.field), isFalse, reason: r.url.path);
      }
      expect(server.bodies(sessionRoute).first, <String, Object?>{'publishableKey': 'pk_test_1'});
      await finish(tester, g);
    });
  });

  group('refusals', () {
    testWidgets('token_expired: one more question, and the request goes once more with the new token',
        (WidgetTester tester) async {
      final server = Server();
      var asked = 0;
      final g = makeApp(tester, server, tokens: () async {
        asked++;
        return mintToken(nowSec(tester), nowSec(tester) + 3600, id: 'ct_$asked');
      });
      await g.loadSession();
      var lists = 0;
      server.route =
          (String path, Map<String, Object?> _) => path == listRoute && ++lists == 1 ? refusal('token_expired', 401) : null;
      expect(await g.scheduledCalls(), isEmpty);
      expect(asked, 2, reason: 'exactly one more question');
      expect(<String>[for (final b in server.bodies(listRoute)) jtiOf(b[ClientTokenRules.field]! as String)],
          <String>['ct_1', 'ct_2'],
          reason: 'exactly one retry, with the new token');
      await finish(tester, g);
    });

    testWidgets('the same token again: no second request — the refusal stands, with its reason', (WidgetTester tester) async {
      final server = Server();
      final same = mintToken(nowSec(tester), nowSec(tester) + 3600);
      var asked = 0;
      final g = makeApp(tester, server, tokens: () async {
        asked++;
        return same;
      });
      await g.loadSession();
      server.route = (String path, Map<String, Object?> _) =>
          path == listRoute ? refusal('token_invalid', 401, reason: 'signature') : null;
      await expectLater(
          g.scheduledCalls(),
          throwsA(isA<GraineException>()
              .having((GraineException e) => e.code, 'code', GraineErrorCode.tokenInvalid)
              .having((GraineException e) => e.reason, 'reason', 'signature')
              .having((GraineException e) => e.statusCode, 'statusCode', 401)));
      expect(server.bodies(listRoute), hasLength(1));
      expect(asked, 2, reason: 'a fresh token was asked for — and it was the same one');
      await finish(tester, g);
    });

    testWidgets('token_scope and key_revoked are surfaced with Graine\'s sentence and reason, never retried',
        (WidgetTester tester) async {
      final server = Server();
      var asked = 0;
      final g = makeApp(tester, server, tokens: () async {
        asked++;
        return mintToken(nowSec(tester), nowSec(tester) + 3600);
      });
      await g.loadSession();
      for (final (String code, int status, String? reason, GraineErrorCode typed) in <(String, int, String?, GraineErrorCode)>[
        ('token_scope', 403, 'scope', GraineErrorCode.tokenScope),
        ('key_revoked', 401, null, GraineErrorCode.keyRevoked),
      ]) {
        server.route =
            (String path, Map<String, Object?> _) => path == listRoute ? refusal(code, status, reason: reason) : null;
        final before = server.bodies(listRoute).length;
        await expectLater(
            g.scheduledCalls(),
            throwsA(isA<GraineException>()
                .having((GraineException e) => e.code, 'code', typed)
                .having((GraineException e) => e.codeName, 'codeName', code)
                .having((GraineException e) => e.reason, 'reason', reason)
                .having((GraineException e) => e.message, 'message', 'Refused for its $code.')));
        expect(server.bodies(listRoute).length, before + 1, reason: '$code: one request');
      }
      expect(asked, 1, reason: 'the provider is not asked for a final refusal');
      await finish(tester, g);
    });

    testWidgets('the session refused for an expired token asks once and loads', (WidgetTester tester) async {
      final server = Server();
      final first = mintToken(nowSec(tester), nowSec(tester) + 3600, id: 'ct_1');
      final second = mintToken(nowSec(tester), nowSec(tester) + 3600, id: 'ct_2');
      server.route = (String path, Map<String, Object?> body) =>
          path == sessionRoute && body[ClientTokenRules.field] == first ? refusal('token_expired', 401) : null;
      var asked = 0;
      final g = makeApp(tester, server, tokens: () async => ++asked == 1 ? first : second);
      expect(await g.loadSession(), isNotNull);
      expect(asked, 2);
      expect(<Object?>[for (final b in server.bodies(sessionRoute)) b[ClientTokenRules.field]], <Object?>[first, second]);
      await finish(tester, g);
    });

    testWidgets('a session refused for a revoked key: its own sentence — never the key or domains one — for every request',
        (WidgetTester tester) async {
      final server = Server();
      server.route = (String path, Map<String, Object?> _) => path == sessionRoute
          ? jsonResponse(<String, Object?>{'error': 'This key was revoked.', 'code': 'key_revoked'}, 401)
          : null;
      final g = makeApp(tester, server, tokens: () async => mintToken(nowSec(tester), nowSec(tester) + 3600));
      final heard = Heard();
      g.addListener(heard);
      expect(await g.loadSession(), isNull);
      expect(server.bodies(sessionRoute), hasLength(1), reason: 'final: not retried');
      expect(heard.errors, <String>['This key was revoked.']);
      g.identify(<String, Object?>{'user_id': 'u-1'});
      await expectLater(g.memories(),
          throwsA(isA<GraineException>().having((GraineException e) => e.code, 'code', GraineErrorCode.keyRevoked)));
      await finish(tester, g);
    });
  });

  group('the chat', () {
    testWidgets('a ticket refused for an expired token asks once, and the chat connects', (WidgetTester tester) async {
      final server = Server();
      final c = Connector();
      var asked = 0;
      final g = makeApp(tester, server, connector: c, tokens: () async {
        asked++;
        return mintToken(nowSec(tester), nowSec(tester) + 3600, id: 'ct_$asked');
      });
      var tickets = 0;
      server.route = (String path, Map<String, Object?> _) =>
          path == ticketRoute && ++tickets == 1 ? refusal('token_expired', 401) : null;
      g.chat.open();
      await pumps(tester);
      expect(asked, 2, reason: 'exactly one more question');
      expect(<String>[for (final b in server.bodies(ticketRoute)) jtiOf(b[ClientTokenRules.field]! as String)],
          <String>['ct_1', 'ct_2']);
      expect(c.sockets.single.protocols, <String>[ChatWire.subprotocol, 'tkt_1']);
      expect(g.chat.connected, isTrue);
      expect(g.chat.refusal, isNull);
      await finish(tester, g);
    });

    testWidgets('refused for a revoked key, the chat fails with it — no direct socket, no reconnect — until asked again',
        (WidgetTester tester) async {
      final server = Server();
      final c = Connector();
      final g = makeApp(tester, server, connector: c, tokens: () async => mintToken(nowSec(tester), nowSec(tester) + 3600));
      final heard = Heard();
      g.addListener(heard);
      server.route = (String path, Map<String, Object?> _) => path == ticketRoute
          ? jsonResponse(<String, Object?>{'error': 'This key was revoked.', 'code': 'key_revoked'}, 401)
          : null;
      g.chat.open();
      await pumps(tester);
      g.chat.send('Hello');
      await pumps(tester);
      expect(g.chat.failed, isTrue);
      expect(g.chat.connecting, isFalse);
      expect(g.chat.status, GraineChatStatus.failed);
      expect(g.chat.refusal?.code, GraineErrorCode.keyRevoked);
      expect(g.chat.error, 'This key was revoked.');
      expect(c.sockets, isEmpty, reason: 'no direct socket past the refusal');
      expect(heard.errors, contains('This key was revoked.'));
      expect(g.chat.turns.single.delivery, GraineChatDelivery.failed, reason: 'kept, marked not sent');
      final asked = server.bodies(ticketRoute).length;
      await tester.pump(const Duration(minutes: 2));
      expect(server.bodies(ticketRoute), hasLength(asked), reason: 'no reconnect: the next would meet the same answer');
      // The customer asks again: a new try — and the line they typed goes on it.
      server.route = null;
      g.chat.retry();
      await pumps(tester);
      expect(g.chat.refusal, isNull);
      expect(g.chat.connected, isTrue);
      expect(c.sockets.single.sent, contains(equals(<String, Object?>{'type': 'text', 'data': 'Hello'})));
      expect(g.chat.turns.single.delivery, GraineChatDelivery.sent);
      await finish(tester, g);
    });

    testWidgets("refused for the token's scope, the chat is never retried", (WidgetTester tester) async {
      final server = Server();
      final c = Connector();
      var asked = 0;
      final g = makeApp(tester, server, connector: c, tokens: () async {
        asked++;
        return mintToken(nowSec(tester), nowSec(tester) + 3600);
      });
      server.route =
          (String path, Map<String, Object?> _) => path == ticketRoute ? refusal('token_scope', 403, reason: 'scope') : null;
      g.chat.open();
      await pumps(tester);
      await tester.pump(const Duration(minutes: 1));
      expect(server.bodies(ticketRoute), hasLength(1));
      expect(asked, 1);
      expect(g.chat.refusal?.code, GraineErrorCode.tokenScope);
      expect(g.chat.refusal?.reason, 'scope');
      expect(c.sockets, isEmpty);
      await finish(tester, g);
    });

    testWidgets('a token that expires during a live chat ends, pauses and reconnects nothing', (WidgetTester tester) async {
      final server = Server();
      final c = Connector();
      String? answer = mintToken(nowSec(tester), nowSec(tester) + 60, id: 'ct_minute');
      var asked = 0;
      final g = makeApp(tester, server, connector: c, tokens: () async {
        asked++;
        return answer;
      });
      g.chat.open();
      await pumps(tester);
      final s = c.sockets.single;
      expect(g.chat.connected, isTrue);
      // The app's server goes down: the minute's token lapses, and every refresh fails, for ten minutes.
      answer = null;
      final tickets = server.bodies(ticketRoute).length;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(seconds: 30));
        s.say(said('Still here.'));
        await tester.pump();
      }
      expect(asked, greaterThan(2), reason: 'the refreshes were tried');
      g.chat.send('And now?');
      await tester.pump();
      expect(g.chat.connected, isTrue);
      expect(g.chat.connecting, isFalse);
      expect(g.chat.reconnecting, isFalse);
      expect(g.chat.failed, isFalse);
      expect(s.closed, isFalse);
      expect(s.types, isNot(contains('stop')));
      expect(s.sent, contains(equals(<String, Object?>{'type': 'text', 'data': 'And now?'})), reason: 'on the live socket');
      expect(server.bodies(ticketRoute), hasLength(tickets), reason: 'no new ticket');
      expect(c.sockets, hasLength(1));
      await finish(tester, g);
    });
  });

  group('the engine page', () {
    testWidgets('the token reaches the page after ready and on every change; its ask is answered, at most one anew in 5 s',
        (WidgetTester tester) async {
      final server = Server();
      var asked = 0;
      final g = makeApp(tester, server, tokens: () async {
        asked++;
        return mintToken(nowSec(tester), nowSec(tester) + 3600, id: 'ct_$asked');
      });
      final page = FakePage();
      g.voice.attach(page);
      await pumps(tester);
      page.say(<String, Object?>{'type': 'graine:ready'});
      await tester.pump();
      final first = page.ofType(ClientTokenRules.pageToken);
      expect(first, hasLength(1), reason: 'after ready');
      expect(jtiOf(first.single['token']! as String), 'ct_1');
      expect(page.posted.indexWhere((Map<String, Object?> m) => m['type'] == ClientTokenRules.pageToken),
          lessThan(page.posted.indexWhere((Map<String, Object?> m) => m['type'] == 'graine:warm')),
          reason: 'before the page warms up its call');
      // The page was refused for its token: a fresh one, posted.
      await tester.pump(const Duration(seconds: 10));
      page.say(<String, Object?>{'type': ClientTokenRules.pageNeedsToken});
      await pumps(tester);
      expect(asked, 2);
      expect(<String>[for (final m in page.ofType(ClientTokenRules.pageToken)) jtiOf(m['token']! as String)],
          <String>['ct_1', 'ct_2', 'ct_2'],
          reason: 'the change, then the answer to its ask');
      // Asked again at once: answered with the newest, asking nobody.
      page.say(<String, Object?>{'type': ClientTokenRules.pageNeedsToken});
      await pumps(tester);
      expect(asked, 2);
      expect(page.ofType(ClientTokenRules.pageToken), hasLength(4));
      await finish(tester, g);
    });

    testWidgets('without a provider the page is handed nothing — and its ask is answered with none', (WidgetTester tester) async {
      final g = makeApp(tester, Server());
      final page = FakePage();
      g.voice.attach(page);
      await pumps(tester);
      page.say(<String, Object?>{'type': 'graine:ready'});
      await tester.pump();
      expect(page.ofType(ClientTokenRules.pageToken), isEmpty);
      page.say(<String, Object?>{'type': ClientTokenRules.pageNeedsToken});
      await pumps(tester);
      expect(page.ofType(ClientTokenRules.pageToken), <Map<String, Object?>>[
        <String, Object?>{'type': ClientTokenRules.pageToken, 'token': null},
      ]);
      await finish(tester, g);
    });

    testWidgets('a token that expires during a live call ends and reconnects nothing', (WidgetTester tester) async {
      final server = Server();
      String? answer = mintToken(nowSec(tester), nowSec(tester) + 60, id: 'ct_minute');
      var asked = 0;
      final g = makeApp(tester, server, tokens: () async {
        asked++;
        return answer;
      });
      final page = FakePage();
      g.voice.attach(page);
      await pumps(tester);
      page.say(<String, Object?>{'type': 'graine:ready'});
      await tester.pump();
      await g.voice.start();
      await tester.pump();
      page.say(<String, Object?>{'type': 'graine:call', 'connected': true, 'connecting': false});
      await tester.pump();
      expect(g.voice.connected, isTrue);
      answer = null;
      final posted = page.posted.length;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(seconds: 30));
      }
      expect(asked, greaterThan(2), reason: 'the refreshes were tried');
      expect(g.voice.connected, isTrue);
      expect(page.posted.skip(posted).map((Map<String, Object?> m) => m['type']), isNot(contains('graine:end-call')));
      expect(page.reloads, 0);
      g.voice.end();
      page.say(<String, Object?>{'type': 'graine:ended'});
      await finish(tester, g);
    });
  });

  group('the native call engine', () {
    const MethodChannel channel = MethodChannel('ai.graine.inapp/calls');
    const EventChannel events = EventChannel('ai.graine.inapp/calls/events');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    MockStreamHandlerEventSink? sink;

    List<Object?> argsOf(String method) =>
        calls.where((MethodCall c) => c.method == method).map((MethodCall c) => c.arguments).toList();

    void emit(String event, [Map<String, Object?> data = const <String, Object?>{}]) =>
        sink!.success(<String, Object?>{'event': event, 'data': data});

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      calls.clear();
      sink = null;
      messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
        calls.add(call);
        if (call.method == 'snapshot') return <String, Object?>{'state': 'idle'};
        if (call.method == 'startCall') return 'call_1';
        return null;
      });
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(onListen: (Object? _, MockStreamHandlerEventSink s) => sink = s),
      );
      GraineCalls.instance.resetForTesting();
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockStreamHandler(events, null);
      GraineInApp.resetForTesting();
    });

    var now = 1793000000000;
    var asked = <String, int>{};

    GraineInApp agent(String name, String key, {bool provider = true}) => GraineInApp.forTesting(
          GraineConfig(
              baseUrl: base,
              publishableKey: key,
              tokenProvider: provider
                  ? () async {
                      final n = asked[name] = (asked[name] ?? 0) + 1;
                      return mintToken(now ~/ 1000, now ~/ 1000 + 3600, id: '${name}_$n');
                    }
                  : null),
          httpClient: MockClient((http.Request _) async => jsonResponse(<String, Object?>{'ok': true})),
          clock: () => now,
          install: true,
          name: name,
        );

    List<String?> pushed() => <String?>[for (final a in argsOf('setClientToken')) a == null ? null : jtiOf(a as String)];

    test('the token goes before configure, every new one follows, and its ask is answered — at most one anew in 5 s',
        () async {
      now = 1793000000000;
      asked = <String, int>{};
      agent(GraineInApp.defaultName, 'pk_test_1');
      await pumpEventQueue();
      await GraineCalls.instance.configure(const GraineCallsOptions(publishableKey: 'pk_test_1', displayName: 'Acme'));
      expect(pushed(), <String?>['default_1']);
      final methods = calls.map((MethodCall c) => c.method).toList();
      expect(methods.indexOf('setClientToken'), lessThan(methods.indexOf('configure')),
          reason: 'held by the engine until configured, so its first request carries it');
      // A request of the engine's was refused for its token: a fresh one, pushed.
      now += 10000;
      emit(ClientTokenRules.hostNeedsToken);
      await pumpEventQueue();
      expect(asked['default'], 2);
      expect(pushed(), <String?>['default_1', 'default_2']);
      // Asked again at once: answered with the newest — the engine waits for an answer — asking nobody.
      emit(ClientTokenRules.hostNeedsToken);
      await pumpEventQueue();
      expect(asked['default'], 2);
      expect(pushed(), <String?>['default_1', 'default_2', 'default_2']);
      // A ring: a fresh token in the background, before anyone answers — pushed as it lands.
      now += 31000;
      emit('incoming', <String, Object?>{'callId': 'ic_1', 'hosted': true, 'agent': 'default'});
      await pumpEventQueue();
      expect(asked['default'], 3);
      expect(pushed().last, 'default_3');
    });

    test("a call with another agent carries that agent's tokens; after it, the default agent's again", () async {
      now = 1793000000000;
      asked = <String, int>{};
      agent(GraineInApp.defaultName, 'pk_test_1');
      agent('support', 'pk_support');
      await pumpEventQueue();
      await GraineCalls.instance.configure(const GraineCallsOptions(publishableKey: 'pk_test_1', displayName: 'Acme'));
      GraineCalls.instance.attach();
      await GraineCalls.instance.startCall(reason: 'question', agent: 'support');
      final methods = calls.map((MethodCall c) => c.method).toList();
      expect(pushed(), <String?>['default_1', 'support_1']);
      expect(methods.lastIndexOf('setClientToken'), lessThan(methods.indexOf('startCall')),
          reason: "the agent's token reaches the engine before the call it places");
      emit('state', <String, Object?>{'state': 'active', 'callId': 'call_1', 'direction': 'outgoing', 'agent': 'support'});
      await pumpEventQueue();
      emit('state', <String, Object?>{'state': 'idle'});
      await pumpEventQueue();
      expect(pushed(), <String?>['default_1', 'support_1', 'default_1']);
    });

    test('without a provider the engine is pushed nothing — and its ask is answered with none', () async {
      agent(GraineInApp.defaultName, 'pk_test_1', provider: false);
      await GraineCalls.instance.configure(const GraineCallsOptions(publishableKey: 'pk_test_1', displayName: 'Acme'));
      GraineCalls.instance.attach();
      await pumpEventQueue();
      expect(argsOf('setClientToken'), isEmpty);
      emit(ClientTokenRules.hostNeedsToken);
      await pumpEventQueue();
      expect(argsOf('setClientToken'), <Object?>[null], reason: 'so it stops waiting');
    });
  });

  group('another user', () {
    // identify() naming another user, or nobody, lets go of the token held — it was minted for the user before
    // and would speak for them — and asks for a fresh one before anything else goes: the sign-out of the user who
    // left still carries theirs, every later request the new user's, and an answer still on its way for an
    // earlier user is never kept (CLIENT-TOKENS.md §2.3, as iOS, React Native and the website loader do).
    testWidgets('the token follows the user: dropped and asked for anew, the sign-out carries the leaver\'s, a late answer is not kept',
        (WidgetTester tester) async {
      final server = Server();
      var who = 'nobody';
      final asked = <String>[];
      final slow = <String, Completer<String?>>{};
      String tokenFor(String user) => mintToken(nowSec(tester), nowSec(tester) + 3600, id: 'ct_$user');
      final g = makeApp(tester, server, connector: Connector(), tokens: () {
        final user = who;
        asked.add(user);
        final late = slow[user];
        return late != null ? late.future : Future<String?>.value(tokenFor(user));
      });
      await pumps(tester);
      // The agent's settings first, as an app that signs its user in after launch: the SDK knows who the user is from then.
      await g.loadSession();
      await pumps(tester);
      String? lastToken(String route) {
        final b = server.bodies(route);
        final t = b.isEmpty ? null : b.last[ClientTokenRules.field];
        return t is String ? jtiOf(t) : null;
      }

      who = 'alice';
      g.identify(<String, Object?>{'user_id': 'alice'});
      await pumps(tester);
      await g.scheduledCalls();
      expect(lastToken(listRoute), 'ct_alice', reason: "after alice signs in, requests carry alice's token");

      who = 'bob';
      g.identify(<String, Object?>{'user_id': 'bob'});
      await pumps(tester);
      final signouts = server.bodies('/api/embed/identity/signout');
      expect(signouts, hasLength(1));
      expect((signouts.single['identity'] as Map<String, Object?>)['value'], 'alice');
      expect(jtiOf(signouts.single[ClientTokenRules.field]! as String), 'ct_alice',
          reason: "the sign-out of the user who left carries their token, never the next user's");
      await g.scheduledCalls();
      expect(lastToken(listRoute), 'ct_bob', reason: "bob's requests carry bob's token, never alice's");

      // An answer still on its way for carol when dave signs in is not kept.
      slow['carol'] = Completer<String?>();
      who = 'carol';
      g.identify(<String, Object?>{'user_id': 'carol'});
      await pumps(tester);
      who = 'dave';
      g.identify(<String, Object?>{'user_id': 'dave'});
      await pumps(tester);
      slow['carol']!.complete(tokenFor('carol'));
      await pumps(tester);
      await g.scheduledCalls();
      expect(lastToken(listRoute), 'ct_dave', reason: "carol's late answer never became dave's token");
      expect(asked, containsAllInOrder(<String>['alice', 'bob', 'carol', 'dave']), reason: 'asked anew for every user');

      // Nobody: the token goes, and the sign-out carries dave's.
      who = 'nobody';
      g.identify(null);
      await pumps(tester);
      final last = server.bodies('/api/embed/identity/signout').last;
      expect((last['identity'] as Map<String, Object?>)['value'], 'dave');
      expect(jtiOf(last[ClientTokenRules.field]! as String), 'ct_dave');
      await finish(tester, g);
    });
  });
}
