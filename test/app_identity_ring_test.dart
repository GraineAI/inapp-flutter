// YOUR APP AND YOUR USERS — a ring (APP-IDENTITY.md §6): before the person
// answers, the app's proof is refreshed and the app is asked for a fresh
// identity token, in the background. On its own: rings arrive on the calls
// event channel, which plain async delivers (as in calls_test.dart).
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graine_inapp/graine_inapp.dart';

import 'app_identity_test.dart' show AppMock, Server, base, callsChannel, callsEvents, key, security;
import 'contract_files.dart';
import 'device_mock.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await contractJson('contract/app-identity.json');
  });
  setUp(() {
    DeviceMock().install();
    AppMock().install();
  });
  tearDown(() {
    DeviceMock.uninstall();
    AppMock.uninstall();
  });

  test('a ring refreshes the proof and the token in the background, before anyone answers', () async {
    // Rings arrive on the calls event channel, which plain async delivers (as in calls_test.dart).
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MockStreamHandlerEventSink? sink;
    messenger.setMockMethodCallHandler(
        callsChannel, (MethodCall call) async => call.method == 'snapshot' ? <String, Object?>{'state': 'idle'} : null);
    messenger.setMockStreamHandler(callsEvents, MockStreamHandler.inline(onListen: (Object? _, MockStreamHandlerEventSink s) {
      sink = s;
    }));
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var skew = 0;
    try {
      GraineCalls.instance.resetForTesting();
      final server = Server(security: security(app: 'report', user: 'enforce', method: 'jwt'));
      final g = GraineInApp.forTesting(const GraineConfig(baseUrl: base, publishableKey: key),
          httpClient: server.client,
          clock: () => DateTime.now().millisecondsSinceEpoch + skew,
          install: true,
          debugBuild: false);
      var asked = 0;
      g.identityTokenRefresher = () async {
        asked++;
        return 'tok-ring';
      };
      g.identify(<String, Object?>{'user_id': 'asha'}, identityToken: 'tok-0');
      await g.loadSession();
      await pumpEventQueue(times: 50);
      expect(server.challenges, 1);
      await GraineCalls.instance.configure(const GraineCallsOptions(publishableKey: key, displayName: 'Acme'));
      await pumpEventQueue(times: 50);
      skew += 19 * 3600 * 1000; // the pass has five hours left
      final rings = <GraineIncomingCall>[];
      final heard = GraineCalls.instance.incomingCalls.listen(rings.add);
      sink!.success(<String, Object?>{
        'event': 'incoming',
        'data': <String, Object?>{'callId': 'c9', 'reason': 'payment_due'},
      });
      await pumpEventQueue(times: 50);
      await heard.cancel();
      expect(rings.single.callId, 'c9');
      expect(GraineInApp.maybeInstance, same(g));
      expect(server.challenges, 2, reason: 'the proof, refreshed before the answer');
      expect(asked, 1, reason: 'and a fresh token asked for');
    } finally {
      GraineInApp.resetForTesting();
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(callsChannel, null);
      messenger.setMockStreamHandler(callsEvents, null);
      GraineCalls.instance.resetForTesting();
    }
  });
}
