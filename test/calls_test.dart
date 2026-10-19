// The Dart half of a native call: configuration reaches the engine, the
// engine's state reaches the call screen, what the app tells the agent stays
// in step, and every action the agent asks for is answered — on every path.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graine_inapp/graine_inapp.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const MethodChannel _channel = MethodChannel('ai.graine.inapp/calls');
const EventChannel _events = EventChannel('ai.graine.inapp/calls/events');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  Object? Function(MethodCall call)? reply;
  MockStreamHandlerEventSink? sink;

  List<Object?> argsOf(String method) =>
      calls.where((MethodCall c) => c.method == method).map((MethodCall c) => c.arguments).toList();

  void emit(String event, Map<String, Object?> data) =>
      sink!.success(<String, Object?>{'event': event, 'data': data});

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    reply = null;
    sink = null;
    messenger.setMockMethodCallHandler(_channel, (MethodCall call) async {
      calls.add(call);
      final r = reply;
      if (r != null) return r(call);
      if (call.method == 'snapshot') return <String, Object?>{'state': 'idle'};
      return null;
    });
    messenger.setMockStreamHandler(
      _events,
      MockStreamHandler.inline(onListen: (Object? _, MockStreamHandlerEventSink s) => sink = s),
    );
    GraineCalls.instance.resetForTesting();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(_channel, null);
    messenger.setMockStreamHandler(_events, null);
    GraineInApp.resetForTesting();
  });

  test('configure needs a key and a name, and sends the options the engine reads', () async {
    expect(() => GraineCalls.instance.configure(const GraineCallsOptions(publishableKey: '', displayName: 'Acme')),
        throwsArgumentError);
    expect(() => GraineCalls.instance.configure(const GraineCallsOptions(publishableKey: 'pk_test', displayName: ' ')),
        throwsArgumentError);
    await GraineCalls.instance.configure(const GraineCallsOptions(
      publishableKey: 'pk_test',
      displayName: 'Acme Assistant',
      ringTimeout: Duration(seconds: 45),
      callScreen: GraineCallScreen.app,
      androidSmallIcon: 'ic_call',
    ));
    expect(argsOf('configure').single, <String, Object?>{
      'publishableKey': 'pk_test',
      'displayName': 'Acme Assistant',
      'baseUrl': 'https://www.graine.ai',
      'ringTimeoutMs': 45000,
      'callScreen': 'app',
      'debug': false,
      'android': <String, Object?>{'smallIcon': 'ic_call'},
      'ios': <String, Object?>{'includesCallsInRecents': false},
    });
    expect(argsOf('snapshot'), hasLength(1), reason: 'the state a screen opens on must be read, not waited for');
  });

  test("by default the SDK's own call screens draw the call — natively, in the brand's call screen look", () async {
    // `sdk` hands every moment of the call to the native screens (Android's call
    // activity, iOS's call view), which draw the design's call tokens and their
    // look; nothing about how it looks passes through Dart.
    expect(const GraineCallsOptions(publishableKey: 'pk_test', displayName: 'Acme').callScreen, GraineCallScreen.sdk);
    await GraineCalls.instance.configure(const GraineCallsOptions(publishableKey: 'pk_test', displayName: 'Acme'));
    final sent = argsOf('configure').single! as Map<Object?, Object?>;
    expect(sent['callScreen'], 'sdk');
    expect(sent.keys.where((Object? k) => '$k'.toLowerCase().contains('design') || '$k'.toLowerCase().contains('look')), isEmpty,
        reason: 'the look reaches the native screens with the session, never through the app');
  });

  test("debug reaches the engine as `debug`, for the native SDK's log", () async {
    await GraineCalls.instance
        .configure(const GraineCallsOptions(publishableKey: 'pk_test', displayName: 'Acme', debug: true));
    expect((argsOf('configure').single! as Map<Object?, Object?>)['debug'], isTrue);
  });

  test('callTransport reaches the engine by its word, and only when the app chose one', () async {
    await GraineCalls.instance.configure(const GraineCallsOptions(
        publishableKey: 'pk_test', displayName: 'Acme', callTransport: GraineCallTransport.webrtc));
    expect((argsOf('configure').last! as Map<Object?, Object?>)['callTransport'], 'webrtc');
    await GraineCalls.instance.configure(const GraineCallsOptions(
        publishableKey: 'pk_test', displayName: 'Acme', callTransport: GraineCallTransport.websocket));
    expect((argsOf('configure').last! as Map<Object?, Object?>)['callTransport'], 'websocket');
    await GraineCalls.instance.configure(const GraineCallsOptions(publishableKey: 'pk_test', displayName: 'Acme'));
    expect((argsOf('configure').last! as Map<Object?, Object?>).containsKey('callTransport'), isFalse,
        reason: "auto is the engine's own default: an app that never chose sends what it always sent");
  });

  test("the snapshot says what the call's audio runs on, and why it fell back", () async {
    await GraineCalls.instance.configure(const GraineCallsOptions(publishableKey: 'pk_test', displayName: 'Acme'));
    expect(GraineCalls.instance.value.transport, isNull, reason: 'no call, no transport');
    emit('state', <String, Object?>{'state': 'connecting', 'callId': 'c1', 'transport': 'webrtc'});
    await pumpEventQueue();
    expect(GraineCalls.instance.value.transport, GraineCallTransport.webrtc);
    expect(GraineCalls.instance.value.transportFallbackReason, isNull);
    emit('state', <String, Object?>{
      'state': 'active',
      'callId': 'c1',
      'transport': 'websocket',
      'transportFallbackReason': 'no_answer',
    });
    await pumpEventQueue();
    expect(GraineCalls.instance.value.transport, GraineCallTransport.websocket);
    expect(GraineCalls.instance.value.transportFallbackReason, 'no_answer');
    emit('state', <String, Object?>{'state': 'active', 'callId': 'c1', 'transport': 'auto'});
    await pumpEventQueue();
    expect(GraineCalls.instance.value.transport, isNull, reason: 'a call runs on webrtc or websocket, never on auto');
    expect(GraineCallSnapshot.fromMap(const <String, Object?>{'state': 'active', 'transport': 'webrtc'}),
        isNot(GraineCallSnapshot.fromMap(const <String, Object?>{'state': 'active', 'transport': 'websocket'})),
        reason: 'a change of road is a change of snapshot');
  });

  test('the snapshot says when a connected call is recovering its connection, and when it is back', () async {
    await GraineCalls.instance.configure(const GraineCallsOptions(publishableKey: 'pk_test', displayName: 'Acme'));
    emit('state', <String, Object?>{'state': 'active', 'callId': 'c1'});
    await pumpEventQueue();
    expect(GraineCalls.instance.value.reconnecting, isFalse, reason: 'an engine that says nothing: not recovering');
    emit('state', <String, Object?>{'state': 'active', 'callId': 'c1', 'reconnecting': true});
    await pumpEventQueue();
    expect(GraineCalls.instance.value.reconnecting, isTrue);
    emit('state', <String, Object?>{'state': 'active', 'callId': 'c1', 'reconnecting': false});
    await pumpEventQueue();
    expect(GraineCalls.instance.value.reconnecting, isFalse, reason: 'the audio is back');
    expect(GraineCallSnapshot.fromMap(const <String, Object?>{'state': 'active', 'reconnecting': 'true'}).reconnecting, isFalse,
        reason: 'only a true is recovering');
    expect(GraineCallSnapshot.fromMap(const <String, Object?>{'state': 'active', 'reconnecting': true}),
        isNot(GraineCallSnapshot.fromMap(const <String, Object?>{'state': 'active'})),
        reason: 'recovering is a change of snapshot');
    expect(GraineCallSnapshot.idle.reconnecting, isFalse);
  });

  test("the engine's state reaches the call screen, filled in", () async {
    await GraineCalls.instance.configure(const GraineCallsOptions(publishableKey: 'pk_test', displayName: 'Acme'));
    final seen = <GraineNativeCallStatus>[];
    void listener() => seen.add(GraineCalls.instance.value.status);
    GraineCalls.instance.addListener(listener);
    emit('state', <String, Object?>{'state': 'ringing', 'callId': 'c1', 'direction': 'incoming', 'reason': 'payment_due'});
    emit('state', <String, Object?>{
      'state': 'active',
      'callId': 'c1',
      'direction': 'incoming',
      'agentSpeaking': true,
      'connectedAt': 1760000000000,
      'caption': <String, Object?>{'role': 'agent', 'text': 'Hi Asha', 'live': true},
    });
    await pumpEventQueue();
    GraineCalls.instance.removeListener(listener);
    expect(seen, <GraineNativeCallStatus>[GraineNativeCallStatus.ringing, GraineNativeCallStatus.active]);
    final s = GraineCalls.instance.value;
    expect(s.callId, 'c1');
    expect(s.direction, GraineCallDirection.incoming);
    expect(s.muted, isFalse, reason: 'an unset field must read as its idle value');
    expect(s.reason, isNull, reason: 'each snapshot is whole: a key it leaves out is not carried over');
    expect(s.caption, const GraineCallCaption(Role.agent, 'Hi Asha', live: true));
    expect(s.connectedAt, DateTime.fromMillisecondsSinceEpoch(1760000000000));
  });

  test('outcomes and incoming calls reach their streams, typed', () async {
    await GraineCalls.instance.configure(const GraineCallsOptions(publishableKey: 'pk_test', displayName: 'Acme'));
    final outcomes = <GraineCallOutcome>[];
    final rings = <GraineIncomingCall>[];
    final a = GraineCalls.instance.outcomes.listen(outcomes.add);
    final b = GraineCalls.instance.incomingCalls.listen(rings.add);
    emit('incoming', <String, Object?>{'callId': 'c9', 'reason': 'delivery_delayed', 'callerName': null});
    emit('outcome', <String, Object?>{'callId': 'c9', 'outcome': 'ended', 'reason': 'remote'});
    emit('outcome', <String, Object?>{'callId': 'c10', 'outcome': 'failed', 'error': 'no network'});
    await pumpEventQueue();
    await a.cancel();
    await b.cancel();
    expect(rings.single.callId, 'c9');
    expect(rings.single.reason, 'delivery_delayed');
    expect(outcomes.map((GraineCallOutcome o) => o.wire), <String>['ended', 'failed']);
    expect(outcomes.first.reason, 'remote');
    expect(outcomes.first.outcome, GraineCallOutcomeKind.ended);
    expect(outcomes.last.reason, 'no network', reason: "a failure's reason is why it never connected");
    expect(outcomes.last.outcome, GraineCallOutcomeKind.failed);
  });

  test('outcomes and rings from before the app listened reach its first listener, oldest first', () async {
    await GraineCalls.instance.configure(const GraineCallsOptions(publishableKey: 'pk_test', displayName: 'Acme'));
    // The engine hands over what it held as soon as the channel is listened to — by configure().
    emit('incoming', <String, Object?>{'callId': 'c1', 'reason': 'payment_due'});
    emit('outcome', <String, Object?>{'callId': 'c1', 'outcome': 'answered'});
    emit('outcome', <String, Object?>{'callId': 'c1', 'outcome': 'ended', 'reason': 'remote'});
    await pumpEventQueue();
    final outcomes = <GraineCallOutcome>[];
    final rings = <GraineIncomingCall>[];
    final a = GraineCalls.instance.outcomes.listen(outcomes.add);
    final b = GraineCalls.instance.incomingCalls.listen(rings.add);
    await pumpEventQueue();
    expect(outcomes.map((GraineCallOutcome o) => o.wire), <String>['answered', 'ended']);
    expect(rings.map((GraineIncomingCall c) => c.callId), <String>['c1']);
    emit('outcome', <String, Object?>{'callId': 'c2', 'outcome': 'missed'});
    await pumpEventQueue();
    expect(outcomes.map((GraineCallOutcome o) => o.callId), <String>['c1', 'c1', 'c2']);
    await a.cancel();
    await b.cancel();
  });

  test('a second call while one is live comes back null; the controls reach the engine', () async {
    reply = (MethodCall c) => c.method == 'startCall' ? null : (c.method == 'snapshot' ? <String, Object?>{} : null);
    expect(await GraineCalls.instance.startCall(reason: 'support'), isNull);
    reply = (MethodCall c) => c.method == 'startCall' ? 'call_1' : null;
    expect(await GraineCalls.instance.startCall(reason: 'support', variables: <String, Object?>{'order': 'A-1043'}),
        'call_1');
    await GraineCalls.instance.setMuted(true);
    await GraineCalls.instance.setSpeaker(true);
    await GraineCalls.instance.end();
    expect(argsOf('startCall').last, <String, Object?>{'reason': 'support', 'variables': <String, Object?>{'order': 'A-1043'}});
    expect(argsOf('setMuted'), <Object?>[true]);
    expect(argsOf('setSpeaker'), <Object?>[true]);
    expect(argsOf('end'), hasLength(1));
  });

  test("prepareCall hands the engine startCall's arguments, and places nothing", () async {
    await GraineCalls.instance.prepareCall(reason: 'support', variables: <String, Object?>{'order': 'A-1043'});
    await GraineCalls.instance.prepareCall();
    expect(argsOf('prepareCall'), <Object?>[
      <String, Object?>{'reason': 'support', 'variables': <String, Object?>{'order': 'A-1043'}},
      <String, Object?>{'variables': <String, Object?>{}},
    ]);
    expect(argsOf('startCall'), isEmpty);
  });

  test('a native build from before prepareCall is not an error; off Android and iOS nothing is sent', () async {
    reply = (MethodCall c) {
      if (c.method == 'prepareCall') throw MissingPluginException();
      return c.method == 'snapshot' ? <String, Object?>{'state': 'idle'} : null;
    };
    await GraineCalls.instance.prepareCall(reason: 'support');
    expect(argsOf('prepareCall'), hasLength(1));
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await GraineCalls.instance.prepareCall(reason: 'support');
    expect(argsOf('prepareCall'), hasLength(1));
  });

  test('a push reaches the engine as strings, and is not a call off Android and iOS', () async {
    reply = (MethodCall c) => c.method == 'handlePush';
    expect(
        await GraineCalls.instance.handlePush(<String, Object?>{
          'type': 'agent_call',
          'call_id': 'c_8f2a',
          'variables': <String, Object?>{'name': 'Asha'},
          'attempt': 2,
          'skipped': null,
        }),
        isTrue);
    expect(argsOf('handlePush').single,
        <String, String>{'type': 'agent_call', 'call_id': 'c_8f2a', 'variables': '{"name":"Asha"}', 'attempt': '2'});
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(await GraineCalls.instance.handlePush(<String, Object?>{'type': 'agent_call'}), isFalse);
    expect(argsOf('handlePush'), hasLength(1), reason: 'no platform call where there is no engine');
  });

  test('VoIP tokens reach the app on iOS, null when invalidated; nothing on Android', () async {
    final tokens = <String?>[];
    GraineCalls.instance.enableVoIPPushes(tokens.add);
    expect(argsOf('enableVoIPPushes'), isEmpty, reason: 'Android has no VoIP pushes');
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final off = GraineCalls.instance.enableVoIPPushes(tokens.add);
    await pumpEventQueue();
    expect(argsOf('enableVoIPPushes'), hasLength(1));
    emit('voipToken', <String, Object?>{'token': 'abc'});
    emit('voipToken', <String, Object?>{'token': null});
    await pumpEventQueue();
    off();
    emit('voipToken', <String, Object?>{'token': 'def'});
    await pumpEventQueue();
    expect(tokens, <String?>['abc', null]);
  });

  group('attach', () {
    GraineInApp app() => GraineInApp.forTesting(
          const GraineConfig(baseUrl: 'https://example.test', publishableKey: 'pk_test_1'),
          httpClient: MockClient((http.Request _) async => http.Response('{}', 404)),
          install: true,
        );

    test('hands over who, what and where at once, and keeps them in step', () async {
      final g = app();
      g.identify(<String, Object?>{'name': 'Asha'});
      g.setVariables(<String, Object?>{'plan': 'Plus'});
      g.setScreen(const GraineScreen('billing',
          title: 'Billing',
          fields: <GraineField>[GraineField('pan', label: 'PAN', value: 'ABCDE1234F', status: FieldStatus.invalid)]));
      g.registerAction('open_screen', (Map<String, Object?> args) => ActionResult.ok('Opened ${args['path']}.'));
      final off = GraineCalls.instance.attach(g);
      expect((argsOf('setIdentity').last! as Map<Object?, Object?>)['name'], 'Asha');
      expect((argsOf('setVariables').last! as Map<Object?, Object?>)['plan'], 'Plus');
      expect(argsOf('setScreen').last, <String, Object?>{
        'screen': 'billing',
        'title': 'Billing',
        'fields': <Map<String, Object?>>[
          <String, Object?>{'name': 'pan', 'label': 'PAN', 'value': 'ABCDE1234F', 'status': 'invalid'},
        ],
      });
      expect(argsOf('setActions').last, <String>['open_screen']);

      g.setVariables(<String, Object?>{'plan': 'Gold'});
      expect((argsOf('setVariables').last! as Map<Object?, Object?>)['plan'], 'Gold');
      g.setScreen(const GraineScreen('home'));
      g.registerAction('set_theme', (Map<String, Object?> _) => null);
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect((argsOf('setScreen').last! as Map<Object?, Object?>)['screen'], 'home');
      expect(argsOf('setActions').last, <String>['open_screen', 'set_theme']);

      final before = argsOf('setVariables').length;
      off();
      g.setVariables(<String, Object?>{'plan': 'Platinum'});
      expect(argsOf('setVariables'), hasLength(before), reason: 'a detached app kept updating the call');
      expect(argsOf('setActions').last, isEmpty, reason: 'detaching must stop the engine routing actions here');
    });

    test("the agent's action runs in the app's handler and its answer goes back", () async {
      final g = app();
      g.registerAction('open_screen', (Map<String, Object?> args) => ActionResult.ok('Opened ${args['path']}.'));
      GraineCalls.instance.attach(g);
      await pumpEventQueue();
      emit('action', <String, Object?>{'requestId': 'r1', 'name': 'open_screen', 'arguments': <String, Object?>{'path': '/billing'}});
      await pumpEventQueue();
      expect(argsOf('resolveAction').single, <String, Object?>{
        'requestId': 'r1',
        'result': <String, Object?>{'status': 'ok', 'message': 'Opened /billing.', 'data': <String, Object?>{}},
      });
    });

    test('an action with no app attached is refused, not left hanging', () async {
      await GraineCalls.instance.configure(const GraineCallsOptions(publishableKey: 'pk_test', displayName: 'Acme'));
      emit('action', <String, Object?>{'requestId': 'r2', 'name': 'open_screen', 'arguments': <String, Object?>{}});
      await pumpEventQueue();
      final result = (argsOf('resolveAction').single! as Map<Object?, Object?>)['result']! as Map<Object?, Object?>;
      expect(result['status'], 'refused');
    });

    test('a handler that throws is answered with an error', () async {
      final g = app();
      g.registerAction('open_screen', (Map<String, Object?> _) => throw StateError('boom'));
      GraineCalls.instance.attach(g);
      await pumpEventQueue();
      emit('action', <String, Object?>{'requestId': 'r3', 'name': 'open_screen'});
      await pumpEventQueue();
      final result = (argsOf('resolveAction').single! as Map<Object?, Object?>)['result']! as Map<Object?, Object?>;
      expect(result['status'], 'error');
    });
  });

  group('who the user is, for the native engine', () {
    GraineInApp app() => GraineInApp.forTesting(
          const GraineConfig(baseUrl: 'https://example.test', publishableKey: 'pk_test_1'),
          httpClient: MockClient((http.Request _) async => http.Response('{}', 404)),
          install: true,
        );

    test('configure hands the engine the traits as the app passed them — raw — and the memory choice', () async {
      final g = app();
      g.identify(<String, Object?>{'name': 'Asha', 'email': 'asha@example.com', 'orders': 3}, memory: false);
      expect(argsOf('setIdentity'), isEmpty, reason: 'no engine configured in this run yet');
      await GraineCalls.instance.configure(const GraineCallsOptions(publishableKey: 'pk_test', displayName: 'Acme'));
      await pumpEventQueue();
      expect(argsOf('setIdentity').last, <String, Object?>{'name': 'Asha', 'email': 'asha@example.com', 'orders': 3},
          reason: 'the engine masks for the agent and keeps the identity raw for Graine');
      expect(argsOf('setMemory').last, isFalse);

      g.setMemory(true);
      await pumpEventQueue();
      expect(argsOf('setMemory').last, isTrue);
      g.identify(null);
      await pumpEventQueue();
      expect(argsOf('setIdentity').last, isNull, reason: 'signed out');
    });

    test('an engine from before setMemory is not an error', () async {
      reply = (MethodCall c) {
        if (c.method == 'setMemory') throw MissingPluginException();
        return c.method == 'snapshot' ? <String, Object?>{'state': 'idle'} : null;
      };
      final g = app();
      g.identify(<String, Object?>{'user_id': 'P-1'});
      await GraineCalls.instance.configure(const GraineCallsOptions(publishableKey: 'pk_test', displayName: 'Acme'));
      await pumpEventQueue();
      expect(argsOf('setIdentity').last, <String, Object?>{'user_id': 'P-1'});
    });

    test("Android: FCM's token reaches the engine; iOS needs none", () async {
      await GraineCalls.instance.registerPushToken('  fcm-token-1  ');
      expect(argsOf('registerPushToken').single, <String, Object?>{'token': 'fcm-token-1', 'tokenKind': 'fcm'});
      await GraineCalls.instance.registerPushToken('');
      expect(argsOf('registerPushToken'), hasLength(1), reason: 'no token is no registration');
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await GraineCalls.instance.registerPushToken('apns');
      expect(argsOf('registerPushToken'), hasLength(1));
    });

    test('a ring and an outcome say when Graine rang the call, and how long it lasted', () async {
      await GraineCalls.instance.configure(const GraineCallsOptions(publishableKey: 'pk_test', displayName: 'Acme'));
      final rings = <GraineIncomingCall>[];
      final outcomes = <GraineCallOutcome>[];
      final a = GraineCalls.instance.incomingCalls.listen(rings.add);
      final b = GraineCalls.instance.outcomes.listen(outcomes.add);
      emit('incoming', <String, Object?>{'callId': 'c1', 'callerName': 'Acme', 'hosted': '1'});
      emit('outcome', <String, Object?>{'callId': 'c1', 'outcome': 'ended', 'reason': 'remote', 'durationSeconds': 42.4, 'hosted': true});
      emit('outcome', <String, Object?>{'callId': 'c2', 'outcome': 'missed'});
      await pumpEventQueue();
      await a.cancel();
      await b.cancel();
      expect(rings.single.hosted, isTrue);
      expect(outcomes.first.hosted, isTrue);
      expect(outcomes.first.durationSeconds, 42);
      expect(outcomes.last.hosted, isFalse);
      expect(outcomes.last.durationSeconds, isNull);
    });
  });

  test('a native call takes the line: the WebView engine will not start beside it', () async {
    final g = GraineInApp.forTesting(
      const GraineConfig(baseUrl: 'https://example.test', publishableKey: 'pk_test_1'),
      httpClient: MockClient((http.Request _) async => http.Response('{}', 404)),
      install: true,
    );
    final errors = <String>[];
    g.addListener(_Errors(errors));
    await GraineCalls.instance.configure(const GraineCallsOptions(publishableKey: 'pk_test', displayName: 'Acme'));
    emit('state', <String, Object?>{'state': 'connecting', 'callId': 'c1', 'direction': 'outgoing'});
    await pumpEventQueue();
    await g.voice.start();
    expect(errors, <String>['A call is already in progress.']);
    emit('state', <String, Object?>{'state': 'idle'});
    await pumpEventQueue();
    expect(GraineCalls.instance.value.status, GraineNativeCallStatus.idle);
  });

  group('permissions and setup', () {
    test('the permissions are read from the engine, and a word it does not know is never granted', () async {
      reply = (MethodCall c) => c.method == 'callPermissions'
          ? <String, Object?>{'microphone': 'granted', 'notifications': 'denied', 'fullScreen': 'blocked'}
          : null;
      final p = await GraineCalls.instance.callPermissions();
      expect(p.microphone, GraineCallPermissionStatus.granted);
      expect(p.notifications, GraineCallPermissionStatus.denied);
      expect(p[GraineCallPermission.fullScreen], GraineCallPermissionStatus.blocked);
      expect(p.allGranted, isFalse);
      reply = (MethodCall c) => c.method == 'callPermissions' ? <String, Object?>{'microphone': 'maybe'} : null;
      final unknown = await GraineCalls.instance.callPermissions();
      expect(unknown.microphone, GraineCallPermissionStatus.denied);
      expect(unknown.fullScreen, GraineCallPermissionStatus.denied, reason: 'absent is not granted');
    });

    test('notNeeded counts as granted', () {
      const p = GraineCallPermissions(
        microphone: GraineCallPermissionStatus.granted,
        notifications: GraineCallPermissionStatus.notNeeded,
        fullScreen: GraineCallPermissionStatus.notNeeded,
      );
      expect(p.allGranted, isTrue);
      expect(GraineCallPermissionStatus.blocked.isSatisfied, isFalse);
      expect(GraineCallPermissions.fromMap(const <String, Object?>{
        'microphone': 'granted', 'notifications': 'notNeeded', 'fullScreen': 'notNeeded'}), p);
    });

    test('asking answers the permissions as they stand after, and configure never asks', () async {
      await GraineCalls.instance.configure(const GraineCallsOptions(publishableKey: 'pk_test', displayName: 'Acme'));
      expect(argsOf('requestCallPermissions'), isEmpty, reason: 'the app chooses when to ask');
      reply = (MethodCall c) => switch (c.method) {
            'requestCallPermissions' => <String, Object?>{'microphone': 'granted', 'notifications': 'granted', 'fullScreen': 'granted'},
            'snapshot' => <String, Object?>{'state': 'idle'},
            _ => null,
          };
      final after = await GraineCalls.instance.requestCallPermissions();
      expect(argsOf('requestCallPermissions'), hasLength(1));
      expect(after.allGranted, isTrue);
    });

    test('Settings open by the permission\'s word', () async {
      reply = (MethodCall c) => c.method == 'openCallSettings' ? true : null;
      expect(await GraineCalls.instance.openCallSettings(GraineCallPermission.fullScreen), isTrue);
      expect(argsOf('openCallSettings'), <Object?>['fullScreen']);
      reply = null;
      expect(await GraineCalls.instance.openCallSettings(GraineCallPermission.microphone), isFalse);
    });

    test('setup problems arrive as codes and sentences, and anything else is dropped', () async {
      reply = (MethodCall c) => c.method == 'callSetupProblems'
          ? <Object?>[
              <String, Object?>{'code': 'background_voip_missing', 'message': 'Add voip to UIBackgroundModes.'},
              <String, Object?>{'code': '', 'message': 'no code'},
              'junk',
              <String, Object?>{'code': 'no_push_token'},
            ]
          : null;
      expect(await GraineCalls.instance.callSetupProblems(), const <GraineCallSetupProblem>[
        GraineCallSetupProblem('background_voip_missing', 'Add voip to UIBackgroundModes.'),
        GraineCallSetupProblem('no_push_token', ''),
      ]);
    });

    test('a debug build prints each setup problem once', () async {
      final printed = <String>[];
      final before = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => printed.add(m ?? '');
      try {
        reply = (MethodCall c) => switch (c.method) {
              'callSetupProblems' => <Object?>[
                  <String, Object?>{'code': 'no_push_token', 'message': 'Call registerPushToken.'}
                ],
              'snapshot' => <String, Object?>{'state': 'idle'},
              _ => null,
            };
        await GraineCalls.instance.configure(const GraineCallsOptions(publishableKey: 'pk_test', displayName: 'Acme'));
        await GraineCalls.instance.configure(const GraineCallsOptions(publishableKey: 'pk_test', displayName: 'Acme'));
        await pumpEventQueue();
        expect(printed.where((String m) => m.contains('Calls setup')), <String>['[Graine] Calls setup (no_push_token): Call registerPushToken.']);
      } finally {
        debugPrint = before;
        GraineCalls.instance.resetForTesting();
      }
    });

    test('where there are no native calls, nothing is needed and nothing is asked', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final p = await GraineCalls.instance.callPermissions();
      expect(p.allGranted, isTrue);
      expect(await GraineCalls.instance.requestCallPermissions(), p);
      expect(await GraineCalls.instance.openCallSettings(GraineCallPermission.microphone), isFalse);
      expect(await GraineCalls.instance.callSetupProblems(), isEmpty);
      expect(calls, isEmpty);
    });
  });
}

class _Errors extends GraineListener {
  _Errors(this.errors);
  final List<String> errors;

  @override
  void onError(String message) => errors.add(message);
}
