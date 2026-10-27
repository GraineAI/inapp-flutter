// YOUR APP AND YOUR USERS (0.14.4, sdk/contract/APP-IDENTITY.md): the app's
// declaration on every request, the identity token and the user pass it
// earns, the refresher, the app's proofs and passes, development mode's debug
// tokens, the outage grace and a ring's refresh — held to
// sdk/contract/app-identity.json, which these tests read and FAIL without.
// HTTP, the device and the plugin's app and calls channels are mocks; nothing
// reaches a real host.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graine_inapp/graine_inapp.dart';
import 'package:graine_inapp/src/core/app_identity.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'contract_files.dart';
import 'device_mock.dart';

const String base = 'https://www.graine.ai';
const String gateway = 'wss://gateway.test/v1/embed';
const String key = 'pk_test_1';

const MethodChannel appChannel = MethodChannel('ai.graine.inapp/app');
// The calls channels, for a ring (app_identity_ring_test.dart).
const MethodChannel callsChannel = MethodChannel('ai.graine.inapp/calls');
const EventChannel callsEvents = EventChannel('ai.graine.inapp/calls/events');

/// Every route a request of the SDK's own can reach (contract §1.1).
const List<String> everyRoute = <String>[
  '/api/embed/session',
  '/api/embed/ticket',
  '/api/embed/identity/signout',
  '/api/embed/memory/list',
  '/api/embed/memory/forget',
  '/api/embed/conversation/new',
  '/api/embed/calls/schedule',
  '/api/embed/calls/list',
  '/api/embed/calls/cancel',
  '/api/embed/sessions/list',
  '/api/embed/sessions/transcript',
  '/api/embed/app-verify/challenge',
  '/api/embed/app-verify',
];

Map<String, Object?> security({String app = 'off', String user = 'off', String? method}) => <String, Object?>{
      'app': <String, Object?>{'verify': app},
      'user': <String, Object?>{'verify': user, if (method != null) 'method': method},
    };

Map<String, Object?> sessionBody({Map<String, Object?>? security}) => <String, Object?>{
      'agentId': 'agent-1',
      'webcallAgentId': 'webcall-1',
      'pageVersion': 'dpl_42',
      'appearance': <String, Object?>{'mode': 'both', 'title': 'Asha'},
      'variables': <String, Object?>{'brand': 'Graine'},
      'identity': <String, Object?>{'field': 'user_id', 'devicesPerUser': 2},
      'memory': <String, Object?>{'enabled': true},
      'calls': <String, Object?>{
        'hosted': true,
        'platforms': <Object?>['android', 'ios'],
        'scheduling': <String, Object?>{'usersCanBook': true, 'maxDaysAhead': 14, 'minLeadMinutes': 5},
      },
      if (security != null) 'security': security,
    };

http.Response json(Object? body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: const <String, String>{'content-type': 'application/json'},
    );

http.Response refusal(String code, {String? reason, int status = 403}) =>
    json(<String, Object?>{'error': 'refused', 'code': code, if (reason != null) 'reason': reason}, status);

/// Graine, as far as the SDK can tell. Every request is kept; a route may be
/// given answers to use first ([queued]) or one that waits ([slow]).
class Server {
  Server({Map<String, Object?>? security}) : session = sessionBody(security: security);

  Map<String, Object?> session;
  final List<http.Request> requests = <http.Request>[];
  final Map<String, List<http.Response>> queued = <String, List<http.Response>>{};
  final Map<String, Future<http.Response> Function()> slow = <String, Future<http.Response> Function()>{};
  Map<String, Object?>? ticketVerification;
  int challenges = 0;
  int passes = 0;

  void queue(String path, http.Response answer) => (queued[path] ??= <http.Response>[]).add(answer);

  late final http.Client client = MockClient((http.Request req) async {
    requests.add(req);
    final path = req.url.path;
    final waiting = queued[path];
    if (waiting != null && waiting.isNotEmpty) return waiting.removeAt(0);
    final wait = slow[path];
    if (wait != null) return wait();
    switch (path) {
      case '/api/embed/session':
        return json(session);
      case '/api/embed/ticket':
        return json(<String, Object?>{
          'ticket': 'tkt_1',
          'wsUrl': gateway,
          if (ticketVerification != null) 'verification': ticketVerification,
        });
      case '/api/embed/app-verify/challenge':
        challenges++;
        return json(<String, Object?>{'challenge': 'chal${'$challenges'.padLeft(44, '0')}', 'expiresIn': 300});
      case '/api/embed/app-verify':
        passes++;
        return json(<String, Object?>{
          'verification': <String, Object?>{'app': 'verified', 'appPass': 'ap1.pass$passes', 'appPassExpiresIn': 86400},
        });
      case '/api/embed/memory/list':
        return json(<String, Object?>{'memories': <Object?>[]});
      case '/api/embed/memory/forget':
        return json(<String, Object?>{'deleted': 0});
      case '/api/embed/calls/schedule':
        return json(<String, Object?>{
          'call': <String, Object?>{'id': 'c1', 'at': '2030-01-01T10:00:00Z', 'status': 'scheduled'},
        });
      case '/api/embed/calls/list':
        return json(<String, Object?>{'calls': <Object?>[]});
      case '/api/embed/sessions/list':
        return json(<String, Object?>{'sessions': <Object?>[]});
    }
    return json(<String, Object?>{'ok': true});
  });

  List<http.Request> at(String path) => <http.Request>[for (final r in requests) if (r.url.path == path) r];

  List<Map<String, Object?>> bodies(String path) =>
      <Map<String, Object?>>[for (final r in at(path)) jsonDecode(r.body) as Map<String, Object?>];
}

/// The plugin's app channel: what the platform reads and proves.
class AppMock {
  Map<String, Object?>? declaration = <String, Object?>{
    'platform': 'ios',
    'id': 'com.acme.app',
    'accessGroup': 'ABCDE12345.com.acme.app',
  };

  /// The debug token kept with the install id.
  String? kept;
  final List<MethodCall> calls = <MethodCall>[];
  Map<String, Object?> Function(String challenge) proof =
      (String _) => <String, Object?>{'kind': 'attest', 'keyId': 'a2V5', 'attestation': 'YXR0'};

  List<String> get methods => <String>[for (final c in calls) c.method];

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(appChannel,
        (MethodCall call) async {
      calls.add(call);
      switch (call.method) {
        case 'declaration':
          return declaration;
        case 'readDebugToken':
          return kept;
        case 'writeDebugToken':
          kept = call.arguments as String?;
          return null;
        case 'prove':
          return proof((call.arguments! as Map<Object?, Object?>)['challenge']! as String);
      }
      return null;
    });
  }

  /// Back to a platform without the plugin (flutter_test_config.dart).
  static void uninstall() => noAppPlatform();
}

class FakeSocket implements GraineChatSocket {
  FakeSocket(this.url);

  final Uri url;
  final StreamController<Object?> _in = StreamController<Object?>();

  @override
  Stream<Object?> get frames => _in.stream;

  @override
  void send(String data) {}

  @override
  Future<void> close() async {
    if (!_in.isClosed) unawaited(_in.close());
  }
}

class Connector {
  final List<FakeSocket> sockets = <FakeSocket>[];

  Future<GraineChatSocket> call(Uri url, List<String>? protocols) async {
    final s = FakeSocket(url);
    sockets.add(s);
    return s;
  }
}

/// What a voice page receives.
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

  List<Map<String, Object?>> ofType(String type) => <Map<String, Object?>>[
        for (final js in scripts)
          if (js.startsWith('window.postMessage('))
            jsonDecode(js.substring('window.postMessage('.length, js.lastIndexOf(', "*")'))) as Map<String, Object?>,
      ].where((Map<String, Object?> m) => m['type'] == type).toList();

  void say(Map<String, Object?> message) => sink.message(jsonEncode(message));
}

/// Microtasks and channel replies, flushed.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump();
  }
}

Future<void> finish(WidgetTester tester, GraineInApp g) async {
  if (identical(GraineInApp.maybeInstance, g)) {
    GraineInApp.resetForTesting();
  } else {
    g.dispose();
  }
  await tester.pump(const Duration(milliseconds: 300));
}

/// What [body] printed — restored before the test ends, as flutter_test requires.
Future<List<String>> printed(Future<void> Function() body) async {
  final lines = <String>[];
  final saved = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) => lines.add(message ?? '');
  try {
    await body();
  } finally {
    debugPrint = saved;
  }
  return lines;
}

Map<String, Object?>? appOf(Map<String, Object?> body) => body['app'] as Map<String, Object?>?;
Map<String, Object?>? identityOf(Map<String, Object?> body) => body['identity'] as Map<String, Object?>?;

/// A JWT whose payload is [claims] — header and signature are never read on the device.
String jwt(Map<String, Object?> claims) {
  String part(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${part(<String, Object?>{'alg': 'RS256', 'kid': 'k1'})}.${part(claims)}.c2ln';
}

void main() {
  late Map<String, Object?> contract;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    contract = await contractJson('contract/app-identity.json');
  });

  // ── the contract's vectors, on the pure rules ─────────────────────────────

  group('the contract', () {
    test("each error code: its wire word, its Dart name, read from a refusal", () {
      final codes = contract['errorCodes']! as List<Object?>;
      expect(codes, hasLength(3));
      for (final raw in codes) {
        final e = raw! as Map<String, Object?>;
        final code = GraineErrorCode.fromWire(e['wire']! as String);
        expect(code.name, e['dart'], reason: '${e['wire']}');
        expect(code.wire, e['wire']);
        final refused = EmbedRefusal.of(e['status']! as int, <String, Object?>{'code': e['wire'], 'reason': 'expired'})!;
        expect(refused.code, code);
        expect(refused.reason, 'expired');
        expect(refused.message, isNotEmpty, reason: 'a sentence even when Graine gives none');
      }
    });

    test('the verdicts, by name and by wire word', () {
      expect(GraineAppVerdict.values.map((GraineAppVerdict v) => v.name), contract['appVerdicts']);
      expect(GraineUserVerdict.values.map((GraineUserVerdict v) => v.name), contract['userVerdicts']);
      (contract['wireAppVerdicts']! as Map<String, Object?>).forEach((String wire, Object? name) {
        expect(GraineAppVerdict.fromWire(wire)!.name, name, reason: wire);
      });
      (contract['wireUserVerdicts']! as Map<String, Object?>).forEach((String wire, Object? name) {
        expect(GraineUserVerdict.fromWire(wire)!.name, name, reason: wire);
      });
      expect(GraineAppVerdict.fromWire('checking'), isNull, reason: "the SDK's own word is never Graine's");
    });

    test('an answer: verdicts and reasons, an unknown word read as unverified, nothing said changes nothing', () {
      const start = GraineVerification(app: GraineAppVerdict.verified, user: GraineUserVerdict.verified);
      expect(start.merge(<String, Object?>{}), start);
      expect(start.merge(null), start);
      final next = start.merge(<String, Object?>{'app': 'debug_token', 'user': 'invalid', 'userReason': 'signature'});
      expect(next, const GraineVerification(
          app: GraineAppVerdict.debugToken, user: GraineUserVerdict.invalid, userReason: 'signature'));
      expect(next.merge(<String, Object?>{'user': 'test_user', 'userReason': 'missing'}).userReason, isNull,
          reason: 'a reason only beside unverified or invalid');
      expect(start.merge(<String, Object?>{'app': 'quantum'}).app, GraineAppVerdict.unverified,
          reason: 'a verdict this build does not know is never a stale "verified"');
      for (final r in contract['userReasons']! as List<Object?>) {
        expect(start.merge(<String, Object?>{'user': 'unverified', 'userReason': r}).userReason, r);
      }
    });

    test('the Team ID from a Keychain access group', () {
      for (final raw in contract['teamIdFromAccessGroup']! as List<Object?>) {
        final v = raw! as Map<String, Object?>;
        expect(AppIdentity.teamFromAccessGroup(v['accessGroup']), v['team'], reason: '${v['accessGroup']}');
        final declared = AppIdentity.declaration(
            <String, Object?>{'platform': 'ios', 'id': 'com.acme.app', 'accessGroup': v['accessGroup']})!;
        expect(declared['team'], v['team']);
        expect(declared.containsKey('team'), v['team'] != null, reason: 'unknown is left out, never guessed');
      }
    });

    test('signing certificates: SHA-256 of the DER, lower-case hex, de-duplicated, at most five', () {
      final digest = contract['certificateDigest']! as Map<String, Object?>;
      final hex = digest['derHex']! as String;
      final der = <int>[for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
      expect(AppIdentity.certificateDigest(der), digest['sha256']);
      final shapes = contract['shapes']! as Map<String, Object?>;
      final many = <List<int>>[der, der, for (var i = 0; i < 6; i++) <int>[...der, i]];
      final declared = AppIdentity.declaration(
          <String, Object?>{'platform': 'android', 'id': 'com.acme.app', 'certificates': many})!;
      final certs = declared['certs']! as List<String>;
      expect(certs, hasLength(shapes['maxCerts']));
      expect(certs.first, digest['sha256']);
      expect(certs.toSet(), hasLength(certs.length));
      for (final c in certs) {
        expect(RegExp(shapes['certSha256']! as String).hasMatch(c), isTrue);
      }
      expect(AppIdentity.declaration(<String, Object?>{'platform': 'android', 'id': 'com.acme.app'}),
          <String, Object?>{'platform': 'android', 'id': 'com.acme.app'},
          reason: 'certificates that cannot be read are left out');
      expect(AppIdentity.declaration(<String, Object?>{'platform': 'android', 'id': ''}), isNull,
          reason: 'no id: the whole object is left out');
      expect(AppIdentity.declaration(<String, Object?>{'platform': 'web', 'id': 'x'}), isNull);
    });

    test('the shapes: debug tokens, challenges, Team IDs, the longest identity token', () {
      final shapes = contract['shapes']! as Map<String, Object?>;
      final debug = RegExp(shapes['debugToken']! as String);
      for (var i = 0; i < 200; i++) {
        final t = AppIdentity.newDebugToken();
        expect(debug.hasMatch(t), isTrue, reason: t);
        expect(AppIdentity.isDebugToken(t), isTrue);
      }
      expect(AppIdentity.isDebugToken('gdt_short'), isFalse);
      final challenge = RegExp(shapes['challenge']! as String);
      for (final c in <String>['a' * 48, 'A_-9' * 12, 'a' * 47, '${'a' * 47}=', '${'a' * 47}+']) {
        expect(AppIdentity.isChallenge(c), challenge.hasMatch(c), reason: c);
      }
      expect(AppIdentity.maxCerts, shapes['maxCerts']);
      expect(AppIdentity.maxIdentityTokenLength, shapes['maxIdentityTokenLength']);
      expect(AppIdentity.identityToken('x' * AppIdentity.maxIdentityTokenLength), isNotNull);
      expect(AppIdentity.identityToken('x' * (AppIdentity.maxIdentityTokenLength + 1)), isNull);
      expect(AppIdentity.identityToken(''), isNull);
    });

    test('development mode: the modes, the default, the line logged once per install', () {
      final dev = contract['debugTokens']! as Map<String, Object?>;
      expect(GraineDebugTokenMode.values.map((GraineDebugTokenMode m) => m.name), dev['modes']);
      expect(const GraineConfig(baseUrl: base, publishableKey: key).debugTokenMode.name, dev['defaultMode']);
      final token = AppIdentity.newDebugToken();
      expect(AppIdentity.debugTokenLine(token), (dev['logLine']! as String).replaceAll('{token}', token));
      expect(AppIdentity.usesDebugToken(GraineDebugTokenMode.automatic, debugBuild: true), isTrue);
      expect(AppIdentity.usesDebugToken(GraineDebugTokenMode.automatic, debugBuild: false), isFalse);
      expect(AppIdentity.usesDebugToken(GraineDebugTokenMode.always, debugBuild: false), isTrue);
      expect(AppIdentity.usesDebugToken(GraineDebugTokenMode.never, debugBuild: true), isFalse);
    });

    test("a JWT's exp, read without verifying it, and when a token is refreshed", () {
      final expiry = contract['jwtExpiry']! as Map<String, Object?>;
      final example = expiry['example']! as Map<String, Object?>;
      final exp = example['exp']! as int;
      expect(AppIdentity.jwtExpiry(example['token']! as String), exp);
      expect(AppIdentity.jwtRefreshBelowSeconds, expiry['refreshWhenSecondsLeftBelow']);
      final left = (expiry['refreshWhenSecondsLeftBelow']! as int) * 1000;
      expect(AppIdentity.jwtNeedsRefresh(example['token']! as String, exp * 1000 - left - 1000), isFalse);
      expect(AppIdentity.jwtNeedsRefresh(example['token']! as String, exp * 1000 - left + 1000), isTrue);
      final hmac = ((contract['hmacVectors']! as List<Object?>).first! as Map<String, Object?>)['hex']! as String;
      expect(AppIdentity.jwtExpiry(hmac), isNull, reason: 'an HMAC is no JWT, and is never refreshed for its age');
      expect(AppIdentity.jwtExpiry('a.b'), isNull);
      expect(AppIdentity.jwtExpiry(jwt(<String, Object?>{'sub': 'u'})), isNull, reason: 'no exp');
    });

    test("the session's security: when the app proves itself, and when a ticket waits for it", () {
      for (final raw in contract['sessionSecurityExamples']! as List<Object?>) {
        final e = raw! as Map<String, Object?>;
        final s = SecuritySetting.fromJson(e['security'])!;
        expect(s.appVerify != GraineVerifyMode.off, e['prove'], reason: '${e['security']}');
        expect(s.appVerify == GraineVerifyMode.enforce, e['waitForProofBeforeTicket'] ?? false);
      }
      final full = SecuritySetting.fromJson(security(app: 'report', user: 'enforce', method: 'jwt')
        ..['app'] = <String, Object?>{'verify': 'report', 'cloudProjectNumber': '123456789012'})!;
      expect(full.cloudProjectNumber, '123456789012');
      expect(full.userMethod, 'jwt');
      expect(SecuritySetting.fromJson(<String, Object?>{'app': <String, Object?>{'verify': 'sometimes'}})!.appVerify,
          GraineVerifyMode.off);
    });

    test('the identity on the wire: the token and the pass ride inside it, and only with a value', () {
      final wire = (contract['identityWire']! as Map<String, Object?>)['identity']! as Map<String, Object?>;
      final fields = Identity.requestFields(
          value: wire['value']! as String,
          token: wire['token']! as String,
          pass: wire['pass']! as String,
          installId: testInstallId);
      expect(fields['identity'], wire);
      expect(Identity.requestFields(token: 'tok', pass: 'up1.x', installId: testInstallId).containsKey('identity'),
          isFalse);
      // The HMAC vectors are the server's to check; the device sends a token exactly as given.
      for (final raw in contract['hmacVectors']! as List<Object?>) {
        final v = raw! as Map<String, Object?>;
        for (final form in <String>['hex', 'base64url', 'base64']) {
          expect(AppIdentity.identityToken(v[form]), v[form]);
        }
      }
    });

    test("the passes' lifetimes and the refresh, the ring and the outage windows", () {
      final passes = contract['passes']! as Map<String, Object?>;
      expect(AppIdentity.appPassSeconds, passes['appTtlSeconds']);
      expect(AppIdentity.userPassSeconds, passes['userTtlSeconds']);
      expect(AppIdentity.appPassRefreshBelowMs, (passes['appRefreshWhenSecondsLeftBelow']! as int) * 1000);
      expect(AppIdentity.outageGraceMs, (passes['outageGraceSeconds']! as int) * 1000);
      final user = IssuedPass.fromVerification(<String, Object?>{'userPass': 'up1.x'}, app: false, nowMs: 0, value: 'u')!;
      expect(user.expiresAtMs, AppIdentity.userPassSeconds * 1000, reason: 'no lifetime said: the contract\'s');
      final app = IssuedPass.fromVerification(
          <String, Object?>{'app': 'test_build', 'appPass': 'ap1.x', 'appPassExpiresIn': 60}, app: true, nowMs: 0)!;
      expect(app.expiresAtMs, 60000);
      expect(app.appVerdict, GraineAppVerdict.testBuild);
      expect(IssuedPass.fromJson(app.toJson())!.pass, 'ap1.x');
    });
  });

  // ── the SDK on a device ───────────────────────────────────────────────────

  late DeviceMock device;
  late AppMock app;
  setUp(() {
    device = DeviceMock()..install();
    app = AppMock()..install();
  });
  tearDown(() {
    DeviceMock.uninstall();
    AppMock.uninstall();
  });

  var skewMs = 0;
  GraineInApp makeApp(WidgetTester tester, Server server,
      {Connector? connector,
      bool install = false,
      bool debugBuild = false,
      GraineConfig config = const GraineConfig(baseUrl: base, publishableKey: key)}) {
    skewMs = 0;
    return GraineInApp.forTesting(config,
        httpClient: server.client,
        clock: () => tester.binding.clock.now().millisecondsSinceEpoch + skewMs,
        chatConnector: connector?.call,
        install: install,
        debugBuild: debugBuild);
  }

  Future<void> openChat(WidgetTester tester, GraineInApp g) async {
    g.chat.open();
    await settle(tester);
  }

  group('which app is asking', () {
    testWidgets('every request says it: the declaration, the Team ID, and the app pass once one is held',
        (WidgetTester tester) async {
      final server = Server(security: security(app: 'report'));
      final connector = Connector();
      final g = makeApp(tester, server, connector: connector);
      g.identify(<String, Object?>{'user_id': 'user-123'});
      await g.loadSession();
      await settle(tester); // the proof, in the background: challenge, then app-verify
      expect(g.verification.value.app, GraineAppVerdict.verified);

      await openChat(tester, g);
      await g.memories();
      await g.forgetMemory();
      await g.chat.refreshPastSessions();
      try {
        await g.chat.sessionTranscript('s1');
      } on Object {
        // Only the request matters here.
      }
      final now = DateTime.fromMillisecondsSinceEpoch(tester.binding.clock.now().millisecondsSinceEpoch);
      await g.scheduleCall(at: now.add(const Duration(days: 1)));
      await g.scheduledCalls();
      await g.cancelScheduledCall('c1');
      await g.chat.newConversation();
      g.identify(null); // a sign-out
      await settle(tester);

      const declared = <String, Object?>{'platform': 'ios', 'id': 'com.acme.app', 'team': 'ABCDE12345'};
      for (final route in everyRoute) {
        final sent = server.bodies(route);
        expect(sent, isNotEmpty, reason: '$route was never asked');
        for (final body in sent) {
          final a = appOf(body);
          expect(a, isNotNull, reason: '$route carried no app');
          expect(<String, Object?>{for (final k in declared.keys) k: a![k]}, declared, reason: route);
          expect(a!.containsKey('debugToken'), isFalse, reason: 'a release build never sends one');
        }
      }
      expect(appOf(server.bodies('/api/embed/session').single)!.containsKey('pass'), isFalse,
          reason: 'a fresh install holds no pass');
      for (final route in everyRoute.where((String r) => !r.startsWith('/api/embed/app-verify') && r != '/api/embed/session')) {
        for (final body in server.bodies(route)) {
          expect(appOf(body)!['pass'], 'ap1.pass1', reason: '$route: the pass held, while unexpired');
        }
      }
      await finish(tester, g);
    });

    testWidgets('a platform that cannot say which app this is sends no app at all', (WidgetTester tester) async {
      AppMock.uninstall();
      final server = Server(security: security(app: 'report'));
      final g = makeApp(tester, server, debugBuild: true);
      g.identify(<String, Object?>{'user_id': 'user-123'});
      await g.loadSession();
      await settle(tester);
      await g.memories();
      for (final r in server.requests) {
        expect(r.body, isNot(contains('"app"')), reason: r.url.path);
        expect(r.body, isNot(contains('gdt_')));
      }
      expect(server.at('/api/embed/app-verify/challenge'), isEmpty, reason: 'nothing to prove with');
      expect(g.verification.value, const GraineVerification(app: GraineAppVerdict.unverified, appReason: 'unsupported'));
      await finish(tester, g);
    });
  });

  group('the identity token', () {
    testWidgets('rides only inside the identity: never in metadata, variables, a URL, the page or a log',
        (WidgetTester tester) async {
      final vector = (contract['hmacVectors']! as List<Object?>).first! as Map<String, Object?>;
      final token = vector['hex']! as String;
      final server = Server(security: security(user: 'enforce', method: 'hmac'));
      final connector = Connector();
      final g = makeApp(tester, server,
          connector: connector, config: const GraineConfig(baseUrl: base, publishableKey: key, debug: true));
      final lines = await printed(() async {
        g.identify(<String, Object?>{'user_id': vector['identityValue'], 'name': 'Asha'}, identityToken: token);
        g.setVariables(<String, Object?>{'plan': 'gold'});
        await g.loadSession();
        await openChat(tester, g);
        final page = FakePage();
        g.voice.attach(page);
        await tester.pump();
        page.say(<String, Object?>{'type': 'graine:ready'});
        await settle(tester);
        final message = page.ofType('graine:identity').last;
        expect(message['token'], token, reason: "the page's own tickets carry it");
        expect(message.containsKey('pass'), isFalse);
      });
      final ticket = server.bodies('/api/embed/ticket').single;
      expect(identityOf(ticket), <String, Object?>{'value': vector['identityValue'], 'token': token});
      final rest = Map<String, Object?>.of(ticket)..remove('identity');
      expect(jsonEncode(rest), isNot(contains(token)), reason: 'not in the metadata, nor anywhere else');
      for (final r in server.requests) {
        expect(r.url.toString(), isNot(contains(token)));
      }
      expect(connector.sockets.single.url.toString(), isNot(contains(token)));
      expect(jsonEncode(g.currentVariables()), isNot(contains(token)));
      expect(lines.join('\n'), isNot(contains(token)), reason: 'never in a log, the debug log included');
      expect(lines.join('\n'), contains('graine:identity'), reason: 'the debug log did name the message');
      await finish(tester, g);
    });

    testWidgets('another user, or nobody, drops the token and the pass in the same step',
        (WidgetTester tester) async {
      final server = Server(security: security(user: 'enforce', method: 'hmac'))
        ..ticketVerification = <String, Object?>{'user': 'verified', 'userPass': 'up1.asha', 'userPassExpiresIn': 3600};
      final g = makeApp(tester, server, connector: Connector());
      g.identify(<String, Object?>{'user_id': 'asha'}, identityToken: 'tok-asha');
      await g.loadSession();
      await openChat(tester, g);
      await g.memories();
      expect(identityOf(server.bodies('/api/embed/memory/list').last),
          <String, Object?>{'value': 'asha', 'token': 'tok-asha', 'pass': 'up1.asha'});
      expect(g.verification.value.user, GraineUserVerdict.verified);
      server.ticketVerification = null; // the next user's chat earns nothing

      g.identify(<String, Object?>{'user_id': 'ravi'});
      await settle(tester);
      expect(g.verification.value, const GraineVerification(user: GraineUserVerdict.unverified, userReason: 'missing'));
      await g.memories();
      expect(identityOf(server.bodies('/api/embed/memory/list').last), <String, Object?>{'value': 'ravi'});
      expect(identityOf(server.bodies('/api/embed/identity/signout').single), <String, Object?>{'value': 'asha'},
          reason: "a sign-out names who left — and carries nothing of theirs");

      g.identify(<String, Object?>{'user_id': 'asha'});
      await settle(tester);
      await g.memories();
      expect(identityOf(server.bodies('/api/embed/memory/list').last), <String, Object?>{'value': 'asha'},
          reason: 'dropped is dropped: coming back is not getting it back');

      g.identify(<String, Object?>{'user_id': 'asha'}, identityToken: 'tok-asha-2');
      g.identify(null);
      await settle(tester);
      g.identify(<String, Object?>{'user_id': 'asha'});
      await settle(tester);
      await g.memories();
      expect(identityOf(server.bodies('/api/embed/memory/list').last), <String, Object?>{'value': 'asha'});
      await finish(tester, g);
    });

    testWidgets('the same user without a token keeps it; setIdentityToken replaces it without a sign-out',
        (WidgetTester tester) async {
      final server = Server(security: security(user: 'report'));
      final g = makeApp(tester, server);
      g.identify(<String, Object?>{'user_id': 'asha'}, identityToken: 'tok-1');
      await g.loadSession();
      g.identify(<String, Object?>{'user_id': 'asha', 'plan': 'gold'});
      await g.memories();
      expect(identityOf(server.bodies('/api/embed/memory/list').last)!['token'], 'tok-1');

      g.setIdentityToken('tok-2');
      await g.memories();
      expect(identityOf(server.bodies('/api/embed/memory/list').last)!['token'], 'tok-2');
      expect(server.at('/api/embed/identity/signout'), isEmpty);

      g.setIdentityToken(null);
      expect(g.verification.value, const GraineVerification(user: GraineUserVerdict.unverified, userReason: 'missing'));
      await g.memories();
      expect(identityOf(server.bodies('/api/embed/memory/list').last), <String, Object?>{'value': 'asha'});

      final lines = await printed(() async => g.setIdentityToken('x' * (AppIdentity.maxIdentityTokenLength + 1)));
      await g.memories();
      expect(identityOf(server.bodies('/api/embed/memory/list').last), <String, Object?>{'value': 'asha'},
          reason: 'over 4096 characters: not kept');
      expect(lines.single, contains('4096'));
      expect(lines.single, isNot(contains('xxxx')));
      await finish(tester, g);
    });
  });

  group('the refresher', () {
    testWidgets('identity_unverified: asked once, the request sent once more — at most once per 30 s, never twice at once',
        (WidgetTester tester) async {
      final server = Server(security: security(user: 'enforce', method: 'jwt'));
      final g = makeApp(tester, server);
      var asked = 0;
      Completer<String?>? hold;
      g.identityTokenRefresher = () async {
        asked++;
        final h = hold;
        if (h == null) return 'tok-$asked';
        return h.future;
      };
      g.identify(<String, Object?>{'user_id': 'asha'}, identityToken: 'tok-0');
      server.queue('/api/embed/memory/list', refusal('identity_unverified'));
      await g.memories();
      expect(asked, 1);
      final sent = server.bodies('/api/embed/memory/list');
      expect(sent, hasLength(2));
      expect(identityOf(sent.first)!['token'], 'tok-0');
      expect(identityOf(sent.last)!['token'], 'tok-1', reason: 'sent once more, with the new token');

      // Within 30 s: not asked again — the refusal stands.
      server.queue('/api/embed/memory/list', refusal('identity_unverified'));
      await expectLater(g.memories(),
          throwsA(isA<GraineException>().having((GraineException e) => e.code, 'code', GraineErrorCode.identityUnverified)));
      expect(asked, 1);
      expect(server.bodies('/api/embed/memory/list'), hasLength(3), reason: 'no second retry');

      // Later, two refused at once: one question, both answered by it.
      skewMs += 31000;
      hold = Completer<String?>();
      server.queue('/api/embed/memory/list', refusal('identity_unverified'));
      server.queue('/api/embed/memory/list', refusal('identity_unverified'));
      final a = g.memories();
      final b = g.memories();
      await settle(tester);
      expect(asked, 2, reason: 'never twice at once');
      hold.complete('tok-late');
      await a;
      await b;
      expect(identityOf(server.bodies('/api/embed/memory/list').last)!['token'], 'tok-late');
      await finish(tester, g);
    });

    testWidgets('a refresher that throws, or returns nothing, keeps the token', (WidgetTester tester) async {
      final server = Server(security: security(user: 'enforce', method: 'jwt'));
      final g = makeApp(tester, server);
      g.identityTokenRefresher = () async => throw StateError('signed out of the backend');
      g.identify(<String, Object?>{'user_id': 'asha'}, identityToken: 'tok-0');
      server.queue('/api/embed/memory/list', refusal('identity_unverified'));
      final lines = await printed(() async {
        await expectLater(g.memories(), throwsA(isA<GraineException>()));
      });
      expect(lines.join(), isNot(contains('tok-0')));
      skewMs += 31000;
      g.identityTokenRefresher = () async => null;
      await g.memories();
      expect(identityOf(server.bodies('/api/embed/memory/list').last)!['token'], 'tok-0');
      await finish(tester, g);
    });

    testWidgets('a JWT with less than a minute left is renewed before the ticket; an HMAC is not',
        (WidgetTester tester) async {
      final server = Server(security: security(user: 'enforce', method: 'jwt'));
      final g = makeApp(tester, server, connector: Connector());
      final nowS = tester.binding.clock.now().millisecondsSinceEpoch ~/ 1000;
      final fresh = jwt(<String, Object?>{'sub': 'asha', 'exp': nowS + 3600});
      var asked = 0;
      g.identityTokenRefresher = () async {
        asked++;
        return fresh;
      };
      g.identify(<String, Object?>{'user_id': 'asha'}, identityToken: jwt(<String, Object?>{'sub': 'asha', 'exp': nowS + 30}));
      await g.loadSession();
      await openChat(tester, g);
      expect(asked, 1);
      expect(identityOf(server.bodies('/api/embed/ticket').single)!['token'], fresh);
      await finish(tester, g);

      final hmacServer = Server(security: security(user: 'enforce', method: 'hmac'));
      final h = makeApp(tester, hmacServer, connector: Connector());
      var hmacAsked = 0;
      h.identityTokenRefresher = () async {
        hmacAsked++;
        return 'never';
      };
      h.identify(<String, Object?>{'user_id': 'asha'}, identityToken: 'a' * 64);
      await h.loadSession();
      await openChat(tester, h);
      expect(hmacAsked, 0);
      expect(identityOf(hmacServer.bodies('/api/embed/ticket').single)!['token'], 'a' * 64);
      await finish(tester, h);
    });

    testWidgets('an answer saying the token expired asks for a new one in the background',
        (WidgetTester tester) async {
      final server = Server(security: security(user: 'enforce', method: 'jwt'))
        ..ticketVerification = <String, Object?>{'user': 'invalid', 'userReason': 'expired'};
      final g = makeApp(tester, server, connector: Connector());
      var asked = 0;
      g.identityTokenRefresher = () async {
        asked++;
        return 'tok-new';
      };
      g.identify(<String, Object?>{'user_id': 'asha'}, identityToken: 'tok-old');
      await g.loadSession();
      await openChat(tester, g);
      expect(asked, 1);
      expect(server.at('/api/embed/ticket'), hasLength(1), reason: 'the conversation goes on; nothing is asked again');
      await g.memories();
      expect(identityOf(server.bodies('/api/embed/memory/list').last)!['token'], 'tok-new');
      await finish(tester, g);
    });
  });

  group('passes', () {
    testWidgets('the user pass rides with the value it was issued for, until it expires', (WidgetTester tester) async {
      final server = Server(security: security(user: 'enforce', method: 'hmac'))
        ..ticketVerification = <String, Object?>{'user': 'verified', 'userPass': 'up1.asha', 'userPassExpiresIn': 3600};
      final g = makeApp(tester, server, connector: Connector());
      g.identify(<String, Object?>{'user_id': 'asha'}, identityToken: 'tok');
      await g.loadSession();
      await openChat(tester, g);
      await g.memories();
      expect(identityOf(server.bodies('/api/embed/memory/list').last)!['pass'], 'up1.asha');
      skewMs += 3600 * 1000;
      await g.memories();
      expect(identityOf(server.bodies('/api/embed/memory/list').last)!.containsKey('pass'), isFalse);
      expect(jsonEncode(device.prefs), isNot(contains('up1.')), reason: 'a user pass is held in memory only');
      await finish(tester, g);
    });

    testWidgets("the app pass is kept for its publishable key, sent until it expires, and refreshed below six hours",
        (WidgetTester tester) async {
      final server = Server(security: security(app: 'report'));
      final g = makeApp(tester, server);
      await g.loadSession();
      await settle(tester);
      final kept = device.prefs['appPasses']! as Map<String, Object?>;
      expect(kept.keys.single, AppIdentity.passKey(key));
      expect(jsonEncode(device.prefs), isNot(contains(key)), reason: 'kept under a fingerprint, never the key');
      await finish(tester, g);

      // The next launch: the pass is sent from the first request, and not proven again.
      final again = makeApp(tester, server);
      await again.loadSession();
      await settle(tester);
      expect(appOf(server.bodies('/api/embed/session').last)!['pass'], 'ap1.pass1');
      expect(server.challenges, 1);
      expect(again.verification.value.app, GraineAppVerdict.verified);
      // Five hours left: back in the foreground, it is renewed.
      skewMs += 19 * 3600 * 1000;
      again.setForegroundForTesting(false);
      again.setForegroundForTesting(true);
      await settle(tester);
      expect(server.challenges, 2);
      again.identify(<String, Object?>{'user_id': 'asha'});
      await again.memories();
      expect(appOf(server.bodies('/api/embed/memory/list').last)!['pass'], 'ap1.pass2');
      await finish(tester, again);

      // Another key's agent never sends it; and an expired pass is not sent.
      final other = GraineInApp.forTesting(const GraineConfig(baseUrl: base, publishableKey: 'pk_test_2'),
          httpClient: server.client, debugBuild: false);
      await other.loadSession();
      expect(appOf(server.bodies('/api/embed/session').last)!.containsKey('pass'), isFalse);
      other.dispose();
      final laterServer = Server();
      final later = makeApp(tester, laterServer);
      skewMs = 48 * 3600 * 1000;
      await later.loadSession();
      expect(appOf(laterServer.bodies('/api/embed/session').single)!.containsKey('pass'), isFalse,
          reason: 'expired: no longer sent');
      await finish(tester, later);
    });
  });

  group('proving the app', () {
    testWidgets('enforce: a ticket waits for the proof on its way — at most ten seconds', (WidgetTester tester) async {
      final server = Server(security: security(app: 'enforce'));
      final gate = Completer<http.Response>();
      server.slow['/api/embed/app-verify'] = () => gate.future;
      final g = makeApp(tester, server, connector: Connector());
      await g.loadSession();
      await settle(tester);
      g.chat.open();
      await settle(tester);
      expect(server.at('/api/embed/ticket'), isEmpty, reason: 'waiting for the proof');
      gate.complete(json(<String, Object?>{
        'verification': <String, Object?>{'app': 'verified', 'appPass': 'ap1.slow', 'appPassExpiresIn': 86400},
      }));
      await settle(tester);
      expect(appOf(server.bodies('/api/embed/ticket').single)!['pass'], 'ap1.slow');
      await finish(tester, g);

      device.prefs.remove('appPasses'); // a fresh install: no pass to send
      final stuck = Server(security: security(app: 'enforce'));
      final never = Completer<http.Response>();
      stuck.slow['/api/embed/app-verify'] = () => never.future;
      final h = makeApp(tester, stuck, connector: Connector());
      await h.loadSession();
      await settle(tester);
      h.chat.open();
      await settle(tester);
      expect(stuck.at('/api/embed/ticket'), isEmpty);
      await tester.pump(const Duration(seconds: 10));
      await settle(tester);
      expect(stuck.at('/api/embed/ticket'), hasLength(1), reason: 'after ten seconds it goes anyway');
      expect(appOf(stuck.bodies('/api/embed/ticket').single)!.containsKey('pass'), isFalse);
      never.complete(json(<String, Object?>{}, 503));
      await tester.pump(const Duration(seconds: 30));
      await finish(tester, h);
    });

    testWidgets('app_not_verified: the app proves itself and the request is sent once more', (WidgetTester tester) async {
      final server = Server(security: security(app: 'enforce'));
      final g = makeApp(tester, server);
      g.identify(<String, Object?>{'user_id': 'asha'});
      await g.loadSession();
      await settle(tester);
      server.queue('/api/embed/memory/list', refusal('app_not_verified', reason: 'expired'));
      await g.memories();
      final sent = server.bodies('/api/embed/memory/list');
      expect(sent, hasLength(2));
      expect(appOf(sent.first)!['pass'], 'ap1.pass1');
      expect(appOf(sent.last)!['pass'], 'ap1.pass2', reason: 'proven again, then sent once more');
      expect(server.challenges, 2);

      // A proof that cannot be made: no second request.
      app.proof = (String _) => <String, Object?>{'error': 'unsupported'};
      server.queue('/api/embed/memory/list', refusal('app_not_verified', reason: 'invalid'));
      await expectLater(
          g.memories(),
          throwsA(isA<GraineException>()
              .having((GraineException e) => e.code, 'code', GraineErrorCode.appNotVerified)
              .having((GraineException e) => e.reason, 'reason', 'invalid')));
      expect(server.bodies('/api/embed/memory/list'), hasLength(3));
      await finish(tester, g);
    });

    testWidgets('app_not_allowed is final: never sent again, and the chat stops trying', (WidgetTester tester) async {
      final server = Server(security: security(app: 'report'));
      final g = makeApp(tester, server, connector: Connector());
      g.identify(<String, Object?>{'user_id': 'asha'});
      server.queue('/api/embed/memory/list', refusal('app_not_allowed'));
      await expectLater(g.memories(),
          throwsA(isA<GraineException>().having((GraineException e) => e.code, 'code', GraineErrorCode.appNotAllowed)));
      expect(server.at('/api/embed/memory/list'), hasLength(1));
      for (var i = 0; i < 3; i++) {
        server.queue('/api/embed/ticket', refusal('app_not_allowed'));
      }
      await openChat(tester, g);
      await tester.pump(const Duration(minutes: 2));
      await settle(tester);
      expect(server.at('/api/embed/ticket'), hasLength(1), reason: 'refused for this app: asking again changes nothing');
      expect(g.chat.connected, isFalse, reason: 'never round the rule on the direct socket');
      await finish(tester, g);
    });

    testWidgets('a stale challenge is fetched once more; a key Graine no longer knows is replaced once',
        (WidgetTester tester) async {
      final server = Server(security: security(app: 'report'));
      server.queue('/api/embed/app-verify', refusal('app_not_verified', reason: 'challenge'));
      server.queue('/api/embed/app-verify', refusal('app_not_verified', reason: 'unknown_key'));
      final g = makeApp(tester, server);
      await g.loadSession();
      await settle(tester);
      expect(server.challenges, 3);
      expect(app.methods.where((String m) => m == 'forgetProofKey'), hasLength(1));
      expect(g.verification.value.app, GraineAppVerdict.verified);
      final proofs = server.bodies('/api/embed/app-verify');
      expect(proofs.map((Map<String, Object?> b) => b['challenge']).toSet(), hasLength(3),
          reason: 'each proof answers its own challenge');
      expect(proofs.last['proof'], <String, Object?>{'kind': 'attest', 'keyId': 'a2V5', 'attestation': 'YXR0'});
      await finish(tester, g);
    });

    testWidgets('outage: with a pass held — even an expired one — Graine is asked for a grace pass, without a challenge',
        (WidgetTester tester) async {
      final nowMs = tester.binding.clock.now().millisecondsSinceEpoch;
      device.prefs['appPasses'] = <String, Object?>{
        AppIdentity.passKey(key): <String, Object?>{'pass': 'ap1.old', 'exp': nowMs - 3600 * 1000, 'verdict': 'verified'},
      };
      app.proof = (String _) => <String, Object?>{'error': 'backoff'};
      final server = Server(security: security(app: 'enforce'));
      server.queue(
          '/api/embed/app-verify',
          json(<String, Object?>{
            'verification': <String, Object?>{'app': 'verified', 'appPass': 'ap1.grace', 'appPassExpiresIn': 3600},
          }));
      final g = makeApp(tester, server);
      g.identify(<String, Object?>{'user_id': 'asha'});
      await g.loadSession();
      await settle(tester);
      expect(appOf(server.bodies('/api/embed/session').single)!.containsKey('pass'), isFalse,
          reason: 'an expired pass is not sent on an ordinary request');
      final grace = server.bodies('/api/embed/app-verify').single;
      expect(grace['proof'], <String, Object?>{'kind': 'unavailable'});
      expect(grace.containsKey('challenge'), isFalse);
      expect(appOf(grace)!['pass'], 'ap1.old', reason: 'the pass it held, expired');
      expect(g.verification.value.app, GraineAppVerdict.verified);
      await g.memories();
      expect(appOf(server.bodies('/api/embed/memory/list').last)!['pass'], 'ap1.grace');
      // The real proof is tried again later: 30 s on.
      await tester.pump(const Duration(seconds: 30));
      await settle(tester);
      expect(server.challenges, 2);
      await finish(tester, g);

      // Never proven: no pass, no grace — unverified until a proof gets through.
      device.prefs.remove('appPasses');
      final fresh = Server(security: security(app: 'enforce'));
      final h = makeApp(tester, fresh);
      await h.loadSession();
      await settle(tester);
      expect(fresh.at('/api/embed/app-verify'), isEmpty);
      expect(h.verification.value, const GraineVerification(app: GraineAppVerdict.unverified, appReason: 'unavailable'));
      await finish(tester, h);
    });

    testWidgets('prepareAppVerification proves now, and says off when the agent does not check',
        (WidgetTester tester) async {
      final server = Server(security: security(app: 'report'));
      final g = makeApp(tester, server);
      expect(await g.prepareAppVerification(), GraineAppVerdict.verified);
      expect(await g.prepareAppVerification(), GraineAppVerdict.verified);
      expect(server.challenges, 1, reason: 'a fresh pass: nothing to prove again');
      await finish(tester, g);
      final off = makeApp(tester, Server());
      expect(await off.prepareAppVerification(), GraineAppVerdict.off);
      expect(off.verification.value, GraineVerification.off);
      await finish(tester, off);
    });

  });

  group('development mode', () {
    testWidgets('a debug build sends its debug token instead of a proof — the session included — and logs it once',
        (WidgetTester tester) async {
      final server = Server(security: security(app: 'enforce'))
        ..ticketVerification = <String, Object?>{'app': 'debug_token'};
      late GraineInApp g;
      final lines = await printed(() async {
        g = makeApp(tester, server, debugBuild: true, connector: Connector());
        g.identify(<String, Object?>{'user_id': 'asha'});
        await g.loadSession();
        await settle(tester);
      });
      final token = app.kept!;
      expect(AppIdentity.isDebugToken(token), isTrue);
      expect(g.debugToken, token);
      expect(lines.where((String l) => l.contains('gdt_')), <String>[AppIdentity.debugTokenLine(token)]);
      expect(appOf(server.bodies('/api/embed/session').single)!['debugToken'], token);
      expect(g.verification.value.app, GraineAppVerdict.checking, reason: 'no proof: the first answer says');
      await openChat(tester, g);
      await g.memories();
      expect(appOf(server.bodies('/api/embed/ticket').single)!['debugToken'], token);
      expect(appOf(server.bodies('/api/embed/memory/list').single)!['debugToken'], token);
      expect(g.verification.value.app, GraineAppVerdict.debugToken);
      expect(app.methods, isNot(contains('prove')));
      expect(server.challenges, 0);
      await finish(tester, g);

      // The next launch of this install: the same token, not logged again.
      final again = await printed(() async {
        final h = makeApp(tester, server, debugBuild: true);
        await h.loadSession();
        await settle(tester);
        expect(appOf(server.bodies('/api/embed/session').last)!['debugToken'], token);
        await finish(tester, h);
      });
      expect(again.where((String l) => l.contains('gdt_')), isEmpty);
      expect(app.methods.where((String m) => m == 'writeDebugToken'), hasLength(1));
    });

    testWidgets('a release build never creates, logs or sends one', (WidgetTester tester) async {
      final server = Server(security: security(app: 'enforce'));
      final lines = await printed(() async {
        final g = makeApp(tester, server, debugBuild: false);
        g.identify(<String, Object?>{'user_id': 'asha'});
        await g.loadSession();
        await settle(tester);
        await g.memories();
        expect(g.debugToken, isNull);
        await finish(tester, g);
      });
      expect(app.methods, isNot(contains('readDebugToken')));
      expect(app.methods, isNot(contains('writeDebugToken')));
      expect(app.methods, contains('prove'), reason: 'it proves itself');
      for (final r in server.requests) {
        expect(r.body, isNot(contains('debugToken')), reason: r.url.path);
      }
      expect(lines.join(), isNot(contains('gdt_')));
    });

    testWidgets('`always` sends it from a release build; `never` makes a debug build prove itself',
        (WidgetTester tester) async {
      final server = Server(security: security(app: 'enforce'));
      final always = makeApp(tester, server,
          config: const GraineConfig(baseUrl: base, publishableKey: key, debugTokenMode: GraineDebugTokenMode.always));
      await always.loadSession();
      await settle(tester);
      expect(appOf(server.bodies('/api/embed/session').single)!['debugToken'], app.kept);
      expect(always.debugToken, app.kept);
      expect(app.methods, isNot(contains('prove')));
      await finish(tester, always);

      final proving = Server(security: security(app: 'enforce'));
      final never = makeApp(tester, proving,
          debugBuild: true,
          config: const GraineConfig(baseUrl: base, publishableKey: key, debugTokenMode: GraineDebugTokenMode.never));
      await never.loadSession();
      await settle(tester);
      expect(never.debugToken, isNull);
      for (final r in proving.requests) {
        expect(r.body, isNot(contains('debugToken')));
      }
      expect(app.methods, contains('prove'));
      expect(never.verification.value.app, GraineAppVerdict.verified);
      await finish(tester, never);
    });

    testWidgets('a debug token Graine refuses is final: development mode has nothing to prove',
        (WidgetTester tester) async {
      final server = Server(security: security(app: 'enforce'));
      final g = makeApp(tester, server, debugBuild: true);
      g.identify(<String, Object?>{'user_id': 'asha'});
      server.queue('/api/embed/memory/list', refusal('app_not_verified', reason: 'debug_token_unknown'));
      await expectLater(
          g.memories(),
          throwsA(isA<GraineException>()
              .having((GraineException e) => e.code, 'code', GraineErrorCode.appNotVerified)
              .having((GraineException e) => e.reason, 'reason', 'debug_token_unknown')));
      expect(server.at('/api/embed/memory/list'), hasLength(1));
      expect(app.methods, isNot(contains('prove')));
      expect(g.verification.value,
          const GraineVerification(app: GraineAppVerdict.unverified, appReason: 'debug_token_unknown'));
      await finish(tester, g);
    });
  });

  group('the verdicts', () {
    testWidgets('off until the session says, then every answer — test users and debug tokens included',
        (WidgetTester tester) async {
      final server = Server(security: security(app: 'report', user: 'report', method: 'hmac'));
      final g = makeApp(tester, server, connector: Connector());
      final seen = <GraineVerification>[];
      g.verification.addListener(() => seen.add(g.verification.value));
      expect(g.verification.value, GraineVerification.off);
      g.identify(<String, Object?>{'user_id': 'asha'});
      await g.loadSession();
      await settle(tester);
      expect(seen.first.app, GraineAppVerdict.checking);
      expect(g.verification.value, const GraineVerification(
          app: GraineAppVerdict.verified, user: GraineUserVerdict.unverified, userReason: 'missing'));
      g.setIdentityToken('tok');
      expect(g.verification.value.user, GraineUserVerdict.unverified);
      expect(g.verification.value.userReason, isNull, reason: 'a token is held: not yet checked');
      server.ticketVerification = <String, Object?>{'app': 'debug_token', 'user': 'test_user'};
      await openChat(tester, g);
      expect(g.verification.value, const GraineVerification(app: GraineAppVerdict.debugToken, user: GraineUserVerdict.testUser));
      await finish(tester, g);
    });
  });
}
