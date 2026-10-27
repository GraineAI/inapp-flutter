// WHAT THE NATIVE CALL ENGINE WAS TOLD (APP-IDENTITY.md §4): the calls plugin
// forwards every hosted agent's verification — Graine's verdicts on the
// engine's own requests (a call's ticket, its credential) — as the
// `verification` event, with the agent's key and the traits the engine was
// speaking for. The client of that key folds in what proves MORE than it
// knows, never less, and a user verdict only for the user identified now.
// The calls channels and HTTP are mocks; nothing reaches a real host.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graine_inapp/graine_inapp.dart';

import 'app_identity_test.dart' show AppMock, Server, base, callsChannel, callsEvents, key, security;
import 'contract_files.dart';
import 'device_mock.dart';

/// One agent with [checks] on, identified as asha (no token), its calls engine
/// configured; [body] sends the engine's `verification` events through [native].
Future<void> withEngine(
  Map<String, Object?>? checks,
  Future<void> Function(GraineInApp g, void Function(Map<String, Object?> data) native) body, {
  bool platformCanProve = false,
}) async {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  MockStreamHandlerEventSink? sink;
  messenger.setMockMethodCallHandler(
      callsChannel, (MethodCall call) async => call.method == 'snapshot' ? <String, Object?>{'state': 'idle'} : null);
  messenger.setMockStreamHandler(callsEvents, MockStreamHandler.inline(onListen: (Object? _, MockStreamHandlerEventSink s) {
    sink = s;
  }));
  final app = AppMock();
  // Without the plugin's app side this client cannot prove the app itself: only the engine can.
  if (!platformCanProve) app.declaration = null;
  app.install();
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  try {
    GraineCalls.instance.resetForTesting();
    final server = Server(security: checks);
    final g = GraineInApp.forTesting(const GraineConfig(baseUrl: base, publishableKey: key),
        httpClient: server.client, install: true, debugBuild: false);
    g.identify(<String, Object?>{'user_id': 'asha'});
    await g.loadSession();
    await pumpEventQueue(times: 50);
    await GraineCalls.instance.configure(const GraineCallsOptions(publishableKey: key, displayName: 'Acme'));
    await pumpEventQueue(times: 50);
    await body(g, (Map<String, Object?> data) => sink!.success(<String, Object?>{'event': 'verification', 'data': data}));
  } finally {
    GraineInApp.resetForTesting();
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(callsChannel, null);
    messenger.setMockStreamHandler(callsEvents, null);
    GraineCalls.instance.resetForTesting();
    AppMock.uninstall();
  }
}

Map<String, Object?> told({
  String app = 'off',
  String? appReason,
  String user = 'off',
  String? userReason,
  Object? traits = const <String, Object?>{'user_id': 'asha'},
  String publishableKey = key,
}) =>
    <String, Object?>{
      'publishableKey': publishableKey,
      'app': app,
      'appReason': appReason,
      'user': user,
      'userReason': userReason,
      'traits': traits,
    };

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await contractJson('contract/app-identity.json');
  });
  setUp(() => DeviceMock().install());
  tearDown(DeviceMock.uninstall);

  test('a native verdict that proves the app is adopted while this client has not proved it', () async {
    await withEngine(security(app: 'report'), (GraineInApp g, void Function(Map<String, Object?>) native) async {
      expect(g.verification.value.app, GraineAppVerdict.unverified, reason: 'this client cannot prove the app itself');
      native(told(app: 'testBuild'));
      await pumpEventQueue(times: 20);
      expect(g.verification.value.app, GraineAppVerdict.testBuild);
      expect(g.verification.value.appReason, isNull);
    });
  });

  test('a native verdict that proves the user is adopted for the user identified now', () async {
    await withEngine(security(user: 'enforce', method: 'jwt'), (GraineInApp g, void Function(Map<String, Object?>) native) async {
      expect(g.verification.value.user, GraineUserVerdict.unverified);
      native(told(user: 'verified'));
      await pumpEventQueue(times: 20);
      expect(g.verification.value.user, GraineUserVerdict.verified);
      expect(g.verification.value.userReason, isNull);
    });
  });

  test('an unproven native verdict never takes away what this client knows', () async {
    await withEngine(security(app: 'report', user: 'enforce', method: 'jwt'),
        (GraineInApp g, void Function(Map<String, Object?>) native) async {
      expect(g.verification.value.app, GraineAppVerdict.verified, reason: 'this client proved the app itself');
      native(told(user: 'testUser'));
      await pumpEventQueue(times: 20);
      expect(g.verification.value.user, GraineUserVerdict.testUser);
      native(told(app: 'unverified', appReason: 'missing', user: 'invalid', userReason: 'expired'));
      native(told(app: 'checking', user: 'unverified', userReason: 'missing'));
      await pumpEventQueue(times: 20);
      expect(g.verification.value.app, GraineAppVerdict.verified);
      expect(g.verification.value.user, GraineUserVerdict.testUser);
    }, platformCanProve: true);
  });

  test('a word about other traits — a late one about the user before — is not this user\'s', () async {
    await withEngine(security(user: 'enforce', method: 'jwt'), (GraineInApp g, void Function(Map<String, Object?>) native) async {
      native(told(user: 'verified', traits: const <String, Object?>{'user_id': 'ravi'}));
      native(told(user: 'verified', traits: null));
      await pumpEventQueue(times: 20);
      expect(g.verification.value.user, GraineUserVerdict.unverified);
    });
  });

  test('another key\'s verdict is not this agent\'s', () async {
    await withEngine(security(app: 'report', user: 'enforce', method: 'jwt'),
        (GraineInApp g, void Function(Map<String, Object?>) native) async {
      native(told(app: 'verified', user: 'verified', publishableKey: 'pk_test_other'));
      await pumpEventQueue(times: 20);
      expect(g.verification.value.app, GraineAppVerdict.unverified);
      expect(g.verification.value.user, GraineUserVerdict.unverified);
    });
  });

  test('an agent that checks nothing stays off', () async {
    await withEngine(null, (GraineInApp g, void Function(Map<String, Object?>) native) async {
      native(told(app: 'verified', user: 'verified'));
      await pumpEventQueue(times: 20);
      expect(g.verification.value.app, GraineAppVerdict.off);
      expect(g.verification.value.user, GraineUserVerdict.off);
    });
  });
}
