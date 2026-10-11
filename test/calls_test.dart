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

  test("debug reaches the engine as `debug`, for the native SDK's log", () async {
    await GraineCalls.instance
        .configure(const GraineCallsOptions(publishableKey: 'pk_test', displayName: 'Acme', debug: true));
    expect((argsOf('configure').single! as Map<Object?, Object?>)['debug'], isTrue);
  });

  test("the engine's state reaches the call screen, filled in", () async {
    await GraineCalls.instance.configure(const GraineCallsOptions(publishableKey: 'pk_test', displayName: 'Acme'));
    final seen = <GraineCallStatus>[];
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
    expect(seen, <GraineCallStatus>[GraineCallStatus.ringing, GraineCallStatus.active]);
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
    expect(outcomes.first.endReason, 'remote');
    expect(outcomes.last.error, 'no network');
    expect(outcomes.last.endReason, isNull);
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
    expect(GraineCalls.instance.value.status, GraineCallStatus.idle);
  });
}

class _Errors extends GraineListener {
  _Errors(this.errors);
  final List<String> errors;

  @override
  void onError(String message) => errors.add(message);
}
