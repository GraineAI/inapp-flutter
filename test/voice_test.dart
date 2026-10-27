// The call's wiring, against a fake engine page and a mocked session
// endpoint: the URL it loads, the order of what it posts, the action round
// trip, and every timer (the end watchdog, the background confirm, the load
// watchdog and its retry ladder) on the test's fake clock.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart'
    show Brightness, Directionality, MediaQuery, MediaQueryData, Size, SizedBox, Stack, TextDirection, Widget;
import 'package:flutter_test/flutter_test.dart';
import 'package:graine_inapp/graine_inapp.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'contract_files.dart';
import 'device_mock.dart';

const String base = 'https://www.graine.ai';

/// What a page would receive, and a way to speak as the page.
class FakePage implements GraineEnginePage {
  late GraineEngineSink sink;
  final List<String> loads = <String>[];
  final List<String> scripts = <String>[];
  int reloads = 0;
  bool disposed = false;

  @override
  void bind(GraineEngineSink s) => sink = s;
  @override
  void load(String url) => loads.add(url);
  @override
  void reload() => reloads++;
  @override
  void run(String javaScript) => scripts.add(javaScript);
  @override
  void dispose() => disposed = true;

  /// The messages posted into the page, decoded.
  List<Map<String, Object?>> get posted => <Map<String, Object?>>[
        for (final js in scripts)
          if (js.startsWith('window.postMessage('))
            jsonDecode(js.substring('window.postMessage('.length, js.lastIndexOf(', "*")'))) as Map<String, Object?>,
      ];

  List<String> get types => <String>[for (final m in posted) m['type']! as String];

  void say(Map<String, Object?> message) => sink.message(jsonEncode(message));

  void clear() => scripts.clear();
}

/// Everything the SDK reported, in order.
class Log with GraineListener {
  final List<String> events = <String>[];
  @override
  void onCallState(bool connected, bool connecting) => events.add('call $connected $connecting');
  @override
  void onEnded() => events.add('ended');
  @override
  void onMicDenied(String reason) => events.add('mic-denied $reason');
  @override
  void onError(String message) => events.add('error $message');
  @override
  void onConnectivity(GraineConnectivity state, int attempt, String? reason) =>
      events.add('connectivity ${state.name} $attempt $reason');
  @override
  void onActionCompleted(String name, ActionResult result) => events.add('action $name ${result.status.wire}');
  @override
  void onQuality(ConnectionQuality quality) => events.add('quality ${quality.name}');
}

/// The session endpoint. A request that is not exactly the SDK's is answered
/// 418 with what arrived, so the test that made it fails saying why.
http.Client session({int status = 200, Map<String, Object?>? body}) => MockClient((http.Request req) async {
      final expected = req.method == 'POST' &&
          req.url.toString() == '$base/api/embed/session' &&
          req.headers['Content-Type'] == 'application/json' &&
          req.body == jsonEncode(<String, Object?>{'publishableKey': 'pk_test_1'});
      if (!expected) {
        return http.Response(jsonEncode(<String, Object?>{'error': 'unexpected ${req.method} ${req.url} ${req.body}'}), 418);
      }
      return http.Response.bytes(
        utf8.encode(jsonEncode(body ??
            <String, Object?>{
              'agentId': 'agent-1',
              'webcallAgentId': 'webcall-1',
              'pageVersion': 'dpl_42',
              'appearance': <String, Object?>{'audioTransport': 'rtc', 'accent': '#318CE7'},
              'variables': <String, Object?>{'brand': 'Graine', 'plan': 'Default'},
              'appActions': <Object?>[
                <String, Object?>{'tool_name': 'set_tenure'},
              ],
            })),
        status,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

GraineInApp app(WidgetTester tester, {http.Client? client, GraineConfig? config}) => GraineInApp.forTesting(
      config ?? const GraineConfig(baseUrl: '$base/', publishableKey: 'pk_test_1', appVersion: '2.4.0'),
      httpClient: client ?? session(),
      clock: () => tester.binding.clock.now().millisecondsSinceEpoch,
    );

/// Stop every timer and let the fake zone drain, so no test ends with one pending.
Future<void> finish(WidgetTester tester, GraineInApp g) async {
  g.dispose();
  await tester.pump();
}

void main() {
  // The platform side answers: the install id and the zone are known by the
  // time the page is ready, so who the user is reaches it before any start.
  setUp(() => DeviceMock().install());
  tearDown(DeviceMock.uninstall);

  testWidgets("the session's design is kept, and re-picked when the device switches light and dark",
      (WidgetTester tester) async {
    Map<String, Object?> tokens(String scheme, String surface) => <String, Object?>{
          'scheme': scheme,
          'colors': <String, Object?>{'surface': surface, 'accent': '#7C3AED'},
        };
    final g = app(tester,
        client: session(body: <String, Object?>{
          'agentId': 'agent-1',
          'appearance': <String, Object?>{'accent': '#7C3AED'},
          'design': <String, Object?>{
            'config': <String, Object?>{'preset': 'graine-classic', 'scheme': 'auto'},
            'light': tokens('light', '#FFFFFF'),
            'dark': tokens('dark', '#17181B'),
          },
        }));
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    expect(g.tokens, isNull, reason: 'nothing before the session');
    await g.loadSession();
    expect(g.design, isNotNull);
    expect(g.tokens?.scheme, 'light');
    final seen = <String?>[];
    g.tokensListenable.addListener(() => seen.add(g.tokens?.scheme));

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    g.didChangePlatformBrightness();
    expect(g.tokens?.colors.surface, '#17181B');
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    g.didChangePlatformBrightness();
    expect(seen, <String?>['dark', 'light']);
    await finish(tester, g);
  });

  testWidgets("the session's typeface is fetched as the session arrives, through the SDK's own client",
      (WidgetTester tester) async {
    final fx = await tester.runAsync(() => contractJson('contract/design.json'));
    final neo = (fx!['cases']! as List<Object?>).cast<Map<String, Object?>>().firstWhere(
        (Map<String, Object?> c) => (c['config']! as Map<String, Object?>)['preset'] == 'neo-brutalism');
    final fonts = <String>[];
    final registered = <String>[];
    final g = GraineInApp.forTesting(
      const GraineConfig(baseUrl: base, publishableKey: 'pk_test_1'),
      clock: () => tester.binding.clock.now().millisecondsSinceEpoch,
      httpClient: MockClient((http.Request req) async {
        if (req.method == 'POST') {
          // UTF-8, as the server sends it: the design's words carry "…".
          return http.Response.bytes(utf8.encode(jsonEncode(<String, Object?>{'agentId': 'agent-1', 'design': neo['design']})), 200,
              headers: const <String, String>{'content-type': 'application/json'});
        }
        fonts.add(req.url.toString());
        return http.Response.bytes(Uint8List.fromList(<int>[0, 1, 0, 0, ...List<int>.filled(32, 0)]), 200);
      }),
      fontRegistrar: (String name, Uint8List bytes) async => registered.add(name),
    );
    expect(g.fontFaces.value, isEmpty);
    await g.loadSession();
    await tester.pump();
    final want = (neo['fontFaces']! as List<Object?>).cast<Map<String, Object?>>();
    expect(fonts.toSet(), <String>{for (final f in want) f['url']! as String});
    expect(registered.toSet(), <String>{for (final f in want) f['name']! as String});
    expect(g.fontFaces.value, <String, String>{
      for (final f in want) '${f['family']}|${f['weight']}': f['name']! as String,
    });
    await finish(tester, g);
  });

  testWidgets("a transport that is not configured is held as the call's error until the next call",
      (WidgetTester tester) async {
    final g = app(tester);
    final page = FakePage();
    g.voice.attach(page);
    await tester.pump();
    page.say(<String, Object?>{'type': 'graine:ready'});
    expect(g.voice.error, isNull);
    page.say(<String, Object?>{
      'type': 'graine:transport',
      'transport': 'ws',
      'requested': 'rtc',
      'reason': 'not_configured',
      'message': 'This deployment has no WebRTC gateway.',
    });
    expect(g.voice.error, 'This deployment has no WebRTC gateway.');
    page.say(<String, Object?>{'type': 'graine:transport', 'transport': 'ws', 'requested': 'rtc', 'reason': 'ice_failed'});
    expect(g.voice.error, 'This deployment has no WebRTC gateway.', reason: 'a bad network is nobody\'s misconfiguration');
    await g.voice.start();
    expect(g.voice.error, isNull, reason: 'a new call is a new attempt');
    await finish(tester, g);
  });

  testWidgets('the phase reads the call the way the React Native launcher does', (WidgetTester tester) async {
    final g = app(tester);
    final page = FakePage();
    g.voice.attach(page);
    await tester.pump();
    expect(g.voice.phase, CallPhase.connecting, reason: 'the page is not ready');
    page.say(<String, Object?>{'type': 'graine:ready'});
    expect(g.voice.phase, CallPhase.idle);
    await g.voice.start();
    page.say(<String, Object?>{'type': 'graine:call', 'connected': true, 'connecting': false});
    expect(g.voice.phase, CallPhase.listening);
    page.say(<String, Object?>{'type': 'graine:caption', 'role': 'customer', 'text': 'What does it cost?', 'live': false});
    expect(g.voice.phase, CallPhase.thinking);
    page.say(<String, Object?>{'type': 'graine:caption', 'role': 'agent', 'text': 'It costs', 'live': true});
    expect(g.voice.phase, CallPhase.speaking);
    page.say(<String, Object?>{'type': 'graine:caption', 'role': 'agent', 'text': 'It costs ₹19 lakh.', 'live': false});
    expect(g.voice.phase, CallPhase.listening);
    page.say(<String, Object?>{'type': 'graine:reconnecting', 'active': true});
    expect(g.voice.phase, CallPhase.reconnecting);
    page.say(<String, Object?>{'type': 'graine:ended'});
    await finish(tester, g);
  });

  // 0.14.0 — contract/PUBLIC-STATE.md §2: the voice bar's state, for a bar of your own.
  testWidgets("status says where the call is in one word — the bar's own order — and ended once a call is over",
      (WidgetTester tester) async {
    final g = app(tester);
    final page = FakePage();
    g.voice.attach(page);
    await tester.pump();
    expect(g.voice.status, GraineVoiceStatus.connecting, reason: 'the page is not ready');
    page.say(<String, Object?>{'type': 'graine:ready'});
    expect(g.voice.status, GraineVoiceStatus.idle, reason: 'nothing started yet');
    await g.voice.start();
    expect(g.voice.status, GraineVoiceStatus.connecting);
    page.say(<String, Object?>{'type': 'graine:progress', 'stage': 'retrying'});
    expect(g.voice.status, GraineVoiceStatus.reconnecting, reason: 'the bar says "Reconnecting…" across a retry');
    page.say(<String, Object?>{'type': 'graine:call', 'connected': true, 'connecting': false});
    expect(g.voice.status, GraineVoiceStatus.listening);
    page.say(<String, Object?>{'type': 'graine:caption', 'role': 'customer', 'text': 'What does it cost?', 'live': false});
    expect(g.voice.status, GraineVoiceStatus.thinking);
    page.say(<String, Object?>{'type': 'graine:caption', 'role': 'agent', 'text': 'It costs', 'live': true});
    expect(g.voice.status, GraineVoiceStatus.speaking);
    expect(g.voice.captions.last.live, isTrue, reason: "the agent's line as it is said — final once live is false");
    expect(<double>[g.voice.agentLevel, g.voice.micLevel], <double>[0, 0],
        reason: 'no levels from the page yet: 0, never an invented one');
    g.voice.setMuted(true);
    expect(g.voice.status, GraineVoiceStatus.muted);
    g.voice.setMuted(false);
    page.say(<String, Object?>{'type': 'graine:reconnecting', 'active': true});
    expect(g.voice.status, GraineVoiceStatus.reconnecting);
    page.say(<String, Object?>{'type': 'graine:ended'});
    expect(g.voice.status, GraineVoiceStatus.ended);
    expect(g.voice.status.wire, 'ended');
    expect(g.voice.failure, isNull);
    await g.voice.start();
    expect(g.voice.status, GraineVoiceStatus.connecting, reason: 'the next start places another');
    await finish(tester, g);
  });

  // 0.14.4 review — the event the page hears on a call is the one the chat sends: the page passes an
  // `event` on as it is (`{name, ...rest}`, the website loader's form), so a data key never renames it.
  testWidgets("reportEvent on a call: the event's own name and detail, the pacing at its level, the app's data under data",
      (WidgetTester tester) async {
    final g = app(tester);
    final page = FakePage();
    g.voice.attach(page);
    await tester.pump();
    page.say(<String, Object?>{'type': 'graine:ready'});
    await g.voice.start();
    page.say(<String, Object?>{'type': 'graine:call', 'connected': true, 'connecting': false});
    g.setScreen(const GraineScreen('pharmacy'));
    page.clear();
    g.reportEvent('medication_due',
        detail: 'The 8 pm dose is due.',
        data: const <String, Object?>{'name': 'Metformin', 'detail': 'x', 'quiet': true, 'dose_mg': 500});
    final sent = page.posted.where((Map<String, Object?> m) => m['type'] == 'graine:app-event').single;
    expect(sent['event'], <String, Object?>{
      'name': 'medication_due',
      'detail': 'The 8 pm dose is due.',
      'quiet': true,
      'data': <String, Object?>{'name': 'Metformin', 'detail': 'x', 'dose_mg': 500},
    });
    expect(sent.keys.toSet(), <String>{'type', 'event'}, reason: 'nothing beside it a page could spread over the name');
    expect(page.types.indexOf('graine:app-context'), lessThan(page.types.indexOf('graine:app-event')),
        reason: 'the screen first: the event is about it');
    page.say(<String, Object?>{'type': 'graine:ended'});
    await finish(tester, g);
  });

  // 0.14.1 — the page's levels (`graine:levels`), for a meter of your own.
  testWidgets('the levels follow the page while a call is live, the microphone 0 while muted, both 0 once it is over',
      (WidgetTester tester) async {
    final g = app(tester);
    final page = FakePage();
    g.voice.attach(page);
    await tester.pump();
    page.say(<String, Object?>{'type': 'graine:ready'});
    var heard = 0;
    g.voice.addListener(() => heard++);
    page.say(<String, Object?>{'type': 'graine:levels', 'agent': 0.5, 'mic': 0.5});
    expect(<double>[g.voice.agentLevel, g.voice.micLevel], <double>[0, 0], reason: 'no call, no levels');
    expect(heard, 0, reason: 'nothing moved: nobody is told');
    await g.voice.start();
    page.say(<String, Object?>{'type': 'graine:call', 'connected': true, 'connecting': false});
    page.say(<String, Object?>{'type': 'graine:levels', 'agent': 0.42, 'mic': 0.1});
    expect(<double>[g.voice.agentLevel, g.voice.micLevel], <double>[0.42, 0.1]);
    page.say(<String, Object?>{'type': 'graine:levels', 'agent': 3, 'mic': -1});
    expect(<double>[g.voice.agentLevel, g.voice.micLevel], <double>[1, 0], reason: 'held to 0–1');
    page.say(<String, Object?>{'type': 'graine:levels', 'agent': 'loud', 'mic': 0.3});
    expect(<double>[g.voice.agentLevel, g.voice.micLevel], <double>[1, 0.3], reason: 'a level that is not a number leaves it as it was');
    final before = heard;
    page.say(<String, Object?>{'type': 'graine:levels', 'agent': 1, 'mic': 0.3});
    expect(heard, before, reason: 'the same levels are no news');
    g.voice.setMuted(true);
    expect(g.voice.micLevel, 0, reason: 'muted: the microphone is 0');
    page.say(<String, Object?>{'type': 'graine:levels', 'agent': 0.2, 'mic': 0.6});
    expect(<double>[g.voice.agentLevel, g.voice.micLevel], <double>[0.2, 0]);
    g.voice.setMuted(false);
    page.say(<String, Object?>{'type': 'graine:ended'});
    expect(<double>[g.voice.agentLevel, g.voice.micLevel], <double>[0, 0], reason: 'the call is over');
    await finish(tester, g);
  });

  testWidgets('status failed says why in a sentence: a setting, a refused microphone, a page that never loaded, a dead connect',
      (WidgetTester tester) async {
    var allow = false;
    final g = app(tester,
        config: GraineConfig(
          baseUrl: base,
          publishableKey: 'pk_test_1',
          requestMicrophone: () async => allow,
          timing: const GraineTiming(stallMs: 400, bootMs: 400, retryDelaysMs: <int>[100]),
        ));
    final page = FakePage();
    g.voice.attach(page);
    await tester.pump();
    page.say(<String, Object?>{'type': 'graine:ready'});
    page.say(<String, Object?>{
      'type': 'graine:transport',
      'transport': 'ws',
      'requested': 'rtc',
      'reason': 'not_configured',
      'message': 'This deployment has no WebRTC gateway.',
    });
    expect(g.voice.status, GraineVoiceStatus.failed);
    expect(g.voice.failure, 'This deployment has no WebRTC gateway.');
    expect(g.voice.transport, Transport.websocket);
    expect(g.voice.transportFallbackReason, 'not_configured');

    await g.voice.start();
    expect(g.voice.status, GraineVoiceStatus.failed);
    expect(g.voice.failure, GraineVoiceStatus.micRefused);

    allow = true;
    await g.voice.start();
    page.say(<String, Object?>{'type': 'graine:call', 'connected': false, 'connecting': true});
    page.say(<String, Object?>{'type': 'graine:progress', 'stage': 'failed'});
    expect(g.voice.status, GraineVoiceStatus.failed);
    expect(g.voice.failure, GraineVoiceStatus.couldNotConnect);

    page.say(<String, Object?>{'type': 'graine:transport', 'transport': 'rtc', 'requested': 'rtc'});
    expect(g.voice.transportFallbackReason, isNull, reason: 'it did not fall back');

    page.sink.pageStarted();
    page.sink.mainFrameError('load-error:-2');
    await tester.pump(const Duration(milliseconds: 130));
    page.sink.pageStarted();
    page.sink.mainFrameError('load-error:-2');
    expect(g.voice.connectivity, GraineConnectivity.failed);
    expect(g.voice.status, GraineVoiceStatus.failed);
    expect(g.voice.failure, GraineVoiceStatus.couldNotLoad);
    await finish(tester, g);
  });

  testWidgets('the captions switch: on by default, off keeps what is said, a clear forgets it and the call goes on',
      (WidgetTester tester) async {
    final g = app(tester);
    final page = FakePage();
    g.voice.attach(page);
    await tester.pump();
    page.say(<String, Object?>{'type': 'graine:ready'});
    await g.voice.start();
    page.say(<String, Object?>{'type': 'graine:call', 'connected': true, 'connecting': false});
    expect(g.voice.captionsOn, isTrue, reason: 'an accessibility default');
    var heard = 0;
    void count() => heard++;
    g.voice.addListener(count);
    g.voice.setCaptionsOn(false);
    expect(g.voice.captionsOn, isFalse);
    expect(heard, 1);
    page.say(<String, Object?>{'type': 'graine:caption', 'role': 'agent', 'text': 'It costs ₹19 lakh.', 'live': false});
    expect(g.voice.captions.single.text, 'It costs ₹19 lakh.', reason: 'off hides the caption; what is said is kept');
    g.voice.clearCaptions();
    expect(g.voice.captions, isEmpty);
    expect(g.voice.caption, isNull);
    expect(g.voice.connected, isTrue, reason: 'the call goes on');
    expect(page.types.where((String t) => t == 'graine:end-call'), isEmpty);
    g.voice.setCaptionsOn(true);
    expect(g.voice.captionsOn, isTrue);
    g.voice.removeListener(count);
    page.say(<String, Object?>{'type': 'graine:ended'});
    await finish(tester, g);
  });

  testWidgets('attaching loads the engine, idle, at the URL the session names', (WidgetTester tester) async {
    final g = app(tester);
    final page = FakePage();
    g.voice.attach(page);
    await tester.pump();
    expect(page.loads, <String>[
      '$base/embed/webcall-1?mode=voice&branding=0&embed=1&transport=rtc&b=dpl_42&idle=1&pk=pk_test_1&accent=318CE7',
    ]);
    expect(g.session?.declaredActions, <String>{'set_tenure'});
    await finish(tester, g);
    expect(page.disposed, isTrue);
  });

  testWidgets('on ready: the variables, then the screen, then warm — nothing is dialled', (WidgetTester tester) async {
    final g = app(tester);
    g.identify(<String, Object?>{'name': 'Asha', 'phone': '9876543210'});
    g.setVariables(<String, Object?>{'plan': 'Plus', 'cart': 1299});
    g.setScreen(const GraineScreen('kyc_pan', fields: <GraineField>[GraineField('pan', value: 'ABCDE1234F')]));
    final page = FakePage();
    g.voice.attach(page);
    await tester.pump();
    page.sink.pageStarted();
    page.say(<String, Object?>{'type': 'graine:ready'});
    expect(page.types, <String>['graine:variables', 'graine:identity', 'graine:app-context', 'graine:warm']);
    expect(page.posted[0]['variables'], <String, Object?>{
      'brand': 'Graine',
      'plan': 'Plus',
      'cart': '1299',
      'name': 'Asha',
      'phone': '[PHONE]',
    });
    final context = page.posted[2]['context']! as Map<String, Object?>;
    expect(context['screen'], 'kyc_pan');
    expect(((context['fields']! as List<Object?>).first! as Map<String, Object?>)['value'], '[PAN]');
    expect(context['app_version'], '2.4.0');
    expect(g.voice.ready, isTrue);
    expect(g.voice.connectivity, GraineConnectivity.ready);
    await finish(tester, g);
  });

  testWidgets('a start before the page is ready is held, and fired on ready after the variables',
      (WidgetTester tester) async {
    final g = app(tester);
    final log = Log();
    g.addListener(log);
    final page = FakePage();
    g.voice.attach(page);
    await tester.pump();
    await g.voice.start();
    expect(g.voice.connecting, isTrue);
    expect(page.types, isNot(contains('graine:start-call')));

    page.say(<String, Object?>{'type': 'graine:call', 'connected': false, 'connecting': false});
    expect(g.voice.connecting, isTrue, reason: 'the customer pressed the button; "not connected" while loading is not idle');

    page.say(<String, Object?>{'type': 'graine:ready'});
    expect(page.types, <String>['graine:variables', 'graine:identity', 'graine:start-call']);

    page.say(<String, Object?>{'type': 'graine:call', 'connected': true, 'connecting': false});
    expect(g.voice.connected, isTrue);
    expect(log.events, contains('call true false'));
    await finish(tester, g);
  });

  testWidgets('an action the agent asks for is run and answered through the page', (WidgetTester tester) async {
    final g = app(tester);
    final log = Log();
    g.addListener(log);
    g.registerAction('set_tenure', (Map<String, Object?> args) async => ActionResult.ok('Set to ${args['months']}', <String, Object?>{'months': args['months']}));
    final page = FakePage();
    g.voice.attach(page);
    await tester.pump();
    page.say(<String, Object?>{
      'type': 'graine:app-action',
      'action': <String, Object?>{'action_id': 'a1', 'name': 'set_tenure', 'arguments': <String, Object?>{'months': 24}},
    });
    page.say(<String, Object?>{
      'type': 'graine:app-action',
      'action': <String, Object?>{'action_id': 'a2', 'name': 'open_x', 'arguments': <String, Object?>{}},
    });
    await tester.pump();
    final results = page.posted.where((Map<String, Object?> m) => m['type'] == 'graine:app-action-result').toList();
    expect(results, <Map<String, Object?>>[
      <String, Object?>{
        'type': 'graine:app-action-result',
        'actionId': 'a2',
        'status': 'refused',
        'message': 'This app build does not implement "open_x".',
        'data': <String, Object?>{},
      },
      <String, Object?>{
        'type': 'graine:app-action-result',
        'actionId': 'a1',
        'status': 'ok',
        'message': 'Set to 24',
        'data': <String, Object?>{'months': 24},
      },
    ]);
    expect(log.events, containsAll(<String>['action set_tenure ok', 'action open_x refused']));
    expect(g.checkActions(), <String, List<String>>{
      'usable': <String>['set_tenure'],
      'undeclared': <String>[],
      'unhandled': <String>[],
    });
    await finish(tester, g);
  });

  testWidgets('a hang-up the page never confirms is forced after the end watchdog', (WidgetTester tester) async {
    final g = app(tester);
    final log = Log();
    g.addListener(log);
    final page = FakePage();
    g.voice.attach(page);
    await tester.pump();
    page.say(<String, Object?>{'type': 'graine:ready'});
    await g.voice.start();
    page.say(<String, Object?>{'type': 'graine:call', 'connected': true, 'connecting': false});
    g.voice.end();
    expect(page.types.last, 'graine:end-call');
    await tester.pump(const Duration(milliseconds: 3999));
    expect(g.voice.connected, isTrue);
    expect(log.events, isNot(contains('ended')));
    await tester.pump(const Duration(milliseconds: 1));
    expect(g.voice.connected, isFalse);
    expect(log.events.where((String e) => e == 'ended'), hasLength(1));
    expect(page.reloads, 1, reason: 'a reload tears the media down for certain');

    // A page that DOES confirm: ended once, and no reload.
    page.say(<String, Object?>{'type': 'graine:call', 'connected': true, 'connecting': false});
    g.voice.end();
    page.say(<String, Object?>{'type': 'graine:ended'});
    await tester.pump(const Duration(seconds: 5));
    expect(page.reloads, 1);
    expect(log.events.where((String e) => e == 'ended'), hasLength(2));
    await finish(tester, g);
  });

  testWidgets('a refused microphone places nothing and says so', (WidgetTester tester) async {
    var asked = 0;
    final g = app(tester,
        config: GraineConfig(
          baseUrl: base,
          publishableKey: 'pk_test_1',
          requestMicrophone: () async {
            asked++;
            return false;
          },
        ));
    final log = Log();
    g.addListener(log);
    final page = FakePage();
    g.voice.attach(page);
    await tester.pump();
    page.say(<String, Object?>{'type': 'graine:ready'});
    await g.voice.start();
    expect(asked, 1);
    expect(page.types, isNot(contains('graine:start-call')));
    expect(g.voice.micDenied, isTrue);
    expect(g.voice.connecting, isFalse);
    expect(log.events, contains('mic-denied NotAllowedError'));
    // And the page's own request is refused from now on.
    expect(page.sink.microphoneRequested(onlyMicrophone: true), isFalse);
    await finish(tester, g);
  });

  testWidgets('the page gets the microphone only, and only when the app has not been refused it',
      (WidgetTester tester) async {
    final g = app(tester);
    final page = FakePage();
    g.voice.attach(page);
    await tester.pump();
    expect(page.sink.microphoneRequested(onlyMicrophone: true), isTrue);
    expect(page.sink.microphoneRequested(onlyMicrophone: false), isFalse, reason: 'never the camera');
    await finish(tester, g);
  });

  testWidgets('back in the foreground, an idle engine is warmed again; a page not ready, or a call, never is',
      (WidgetTester tester) async {
    final g = app(tester);
    final page = FakePage();
    g.voice.attach(page);
    await tester.pump();

    // Not ready yet: graine:ready will warm it; before that a warm goes nowhere.
    g.setForegroundForTesting(false);
    g.setForegroundForTesting(true);
    expect(page.types, isNot(contains('graine:warm')));

    page.say(<String, Object?>{'type': 'graine:ready'});
    expect(page.types.where((String t) => t == 'graine:warm').length, 1);
    page.clear();

    // The phone dropped the idle SIP socket while the app slept: warm again.
    g.setForegroundForTesting(false);
    g.setForegroundForTesting(true);
    expect(page.types, <String>['graine:warm']);
    page.clear();

    // During a call a warm would replace the registration carrying it.
    await g.voice.start();
    page.say(<String, Object?>{'type': 'graine:call', 'connected': true, 'connecting': false});
    page.clear();
    g.setForegroundForTesting(false);
    g.setForegroundForTesting(true);
    expect(page.types, isNot(contains('graine:warm')));
    page.say(<String, Object?>{'type': 'graine:ended'});
    await finish(tester, g);
  });

  testWidgets('leaving the app ends a live call after two seconds; coming back inside them does not',
      (WidgetTester tester) async {
    final g = app(tester);
    final page = FakePage();
    g.voice.attach(page);
    await tester.pump();
    page.say(<String, Object?>{'type': 'graine:ready'});
    await g.voice.start();
    page.say(<String, Object?>{'type': 'graine:call', 'connected': true, 'connecting': false});
    page.clear();

    g.setForegroundForTesting(false); // a permission dialog, say
    await tester.pump(const Duration(milliseconds: 1500));
    g.setForegroundForTesting(true);
    await tester.pump(const Duration(seconds: 3));
    expect(page.types, isNot(contains('graine:end-call')));

    g.setForegroundForTesting(false);
    await tester.pump(const Duration(seconds: 2));
    expect(page.types, contains('graine:end-call'));
    page.say(<String, Object?>{'type': 'graine:ended'});
    await finish(tester, g);
  });

  testWidgets('a page that stops arriving is reloaded on the ladder, and a ladder that runs out says so',
      (WidgetTester tester) async {
    final g = app(tester,
        config: const GraineConfig(
          baseUrl: base,
          publishableKey: 'pk_test_1',
          timing: GraineTiming(stallMs: 400, bootMs: 400, retryDelaysMs: <int>[100, 100]),
        ));
    final log = Log();
    g.addListener(log);
    final page = FakePage();
    g.voice.attach(page);
    await tester.pump();

    page.sink.pageStarted();
    page.sink.progress(40);
    await tester.pump(const Duration(milliseconds: 399));
    expect(g.voice.connectivity, GraineConnectivity.loading);
    await tester.pump(const Duration(milliseconds: 1));
    expect(g.voice.connectivity, GraineConnectivity.retrying);
    expect(log.events.last, 'connectivity retrying 1 stalled');
    await tester.pump(const Duration(milliseconds: 125)); // the rung, jittered at most +25%
    expect(page.reloads, 1);

    // Downloaded but never ready: a boot timeout, then the last rung.
    page.sink.pageStarted();
    page.sink.pageFinished();
    await tester.pump(const Duration(milliseconds: 400));
    expect(log.events.last, 'connectivity retrying 2 boot_timeout');
    await tester.pump(const Duration(milliseconds: 125));
    expect(page.reloads, 2);

    page.sink.pageStarted();
    page.sink.mainFrameError('load-error:-2');
    expect(g.voice.connectivity, GraineConnectivity.failed);
    expect(log.events, contains('error The assistant could not load. Check your connection and try again.'));

    // "Try again" starts the ladder over.
    g.voice.retry();
    expect(g.voice.connectivity, GraineConnectivity.loading);
    expect(page.reloads, 3);
    page.say(<String, Object?>{'type': 'graine:ready'});
    expect(g.voice.connectivity, GraineConnectivity.ready);
    await finish(tester, g);
  });

  testWidgets('a rejected key is an error that names the fix, and nothing loads', (WidgetTester tester) async {
    final g = app(tester, client: session(status: 403, body: <String, Object?>{'error': 'origin not allowed'}));
    final log = Log();
    g.addListener(log);
    final page = FakePage();
    g.voice.attach(page);
    await tester.pump();
    expect(page.loads, isEmpty);
    expect(g.voice.connectivity, GraineConnectivity.failed);
    expect(log.events.any((String e) => e.startsWith('error This agent does not accept connections from a mobile app yet.')),
        isTrue);
    await finish(tester, g);
  });

  testWidgets('the screen reaches a live call coalesced, and components reach the components state',
      (WidgetTester tester) async {
    final g = app(tester);
    final page = FakePage();
    g.voice.attach(page);
    await tester.pump();
    page.say(<String, Object?>{'type': 'graine:ready'});
    await g.voice.start();
    page.say(<String, Object?>{'type': 'graine:call', 'connected': true, 'connecting': false});
    page.clear();

    g.setScreen(const GraineScreen('pan', fields: <GraineField>[GraineField('pan', value: 'A')]));
    g.setScreen(const GraineScreen('pan', fields: <GraineField>[GraineField('pan', value: 'AB')]));
    g.setScreen(const GraineScreen('pan', fields: <GraineField>[GraineField('pan', value: 'ABC')]));
    String valueIn(Map<String, Object?> m) =>
        (((m['context']! as Map<String, Object?>)['fields']! as List<Object?>).single! as Map<String, Object?>)['value']!
            as String;
    expect(page.types, <String>['graine:app-context'], reason: 'the first change goes out at once');
    expect(valueIn(page.posted.single), 'A');
    await tester.pump(const Duration(milliseconds: 399));
    expect(page.types, hasLength(1), reason: 'the rest of the burst waits for the end of the window');
    await tester.pump(const Duration(milliseconds: 1));
    expect(page.types, <String>['graine:app-context', 'graine:app-context'], reason: 'three changes, two frames');
    expect(valueIn(page.posted.last), 'ABC');
    final field = ((page.posted.last['context']! as Map<String, Object?>)['fields']! as List<Object?>).single;
    expect((field! as Map<String, Object?>)['value'], 'ABC');

    page.say(<String, Object?>{
      'type': 'graine:widget-pending',
      'widget': <String, Object?>{'widget_id': 'w1', 'kind': 'choices'},
    });
    expect(g.components.loading?.kind, 'choices');
    page.say(<String, Object?>{
      'type': 'graine:widget',
      'widget': <String, Object?>{
        'widget_id': 'w1',
        'kind': 'choices',
        'data': <String, Object?>{
          'options': <Object?>['Yes', 'No'],
        },
      },
    });
    await tester.pump(const Duration(milliseconds: Widgets.minLoaderMs));
    expect(g.components.widget?.id, 'w1');
    expect(g.pendingWidget?['widget_id'], 'w1');

    g.components.answer(g.components.content!.pickChip(g.components.content!.chips.first));
    final result = page.posted.lastWhere((Map<String, Object?> m) => m['type'] == 'graine:widget-result');
    expect(result, <String, Object?>{
      'type': 'graine:widget-result',
      'widgetId': 'w1',
      'data': <String, Object?>{'chosen': 'Yes', 'label': 'Yes'},
      'summary': "I'll go with Yes.",
    });
    expect(g.pendingWidget, isNull);

    page.say(<String, Object?>{'type': 'graine:caption', 'role': 'agent', 'text': 'Great', 'live': true});
    expect(g.components.awaitingReply, isFalse, reason: 'the agent started');
    expect(g.voice.agentSpeaking, isTrue);
    expect(g.voice.caption, const Caption(Role.agent, 'Great', live: true));

    page.say(<String, Object?>{'type': 'graine:quality', 'sample': <String, Object?>{'rtt': 480}});
    expect(g.voice.quality, ConnectionQuality.poor);
    page.say(<String, Object?>{'type': 'graine:network', 'online': false});
    expect(g.voice.quality, ConnectionQuality.lost);
    expect(g.voice.online, isFalse);
    await finish(tester, g);
  });

  // ── graine:progress — a connect that says where it is (contract/DESIGN.md, "Connecting") ──

  GraineInApp slowApp(WidgetTester tester, Log log) {
    final g = app(tester,
        config: const GraineConfig(
          baseUrl: '$base/',
          publishableKey: 'pk_test_1',
          timing: GraineTiming(slowConnectMs: 120),
        ));
    g.addListener(log);
    return g;
  }

  testWidgets("the engine's stages reach the call, and an answered call clears them", (WidgetTester tester) async {
    final g = app(tester);
    final page = FakePage();
    g.voice.attach(page);
    await tester.pump();
    page.say(<String, Object?>{'type': 'graine:ready'});
    page.say(<String, Object?>{'type': 'graine:call', 'connected': false, 'connecting': true});
    expect(g.voice.connectStage, isNull);
    page.say(<String, Object?>{'type': 'graine:progress', 'stage': 'registering'});
    expect(g.voice.connectStage, ConnectStage.registering);
    page.say(<String, Object?>{'type': 'graine:progress', 'stage': 'dialling'});
    expect(g.voice.connectStage, ConnectStage.dialling);
    page.say(<String, Object?>{'type': 'graine:progress', 'stage': 'retrying'});
    expect(g.voice.connectStage, ConnectStage.retrying);
    page.say(<String, Object?>{'type': 'graine:progress', 'stage': 'nonsense'});
    expect(g.voice.connectStage, ConnectStage.retrying, reason: 'an unknown stage is ignored, not stored');
    page.say(<String, Object?>{'type': 'graine:progress', 'stage': 'switching'});
    expect(g.voice.connectStage, ConnectStage.switching);
    page.say(<String, Object?>{'type': 'graine:call', 'connected': true, 'connecting': false});
    expect(g.voice.connectStage, isNull, reason: 'a connected call still claimed to be switching');
    expect(g.voice.callFailed, isFalse);
    await finish(tester, g);
  });

  testWidgets('when nothing could carry the call, the connect ends and the next start tries again',
      (WidgetTester tester) async {
    final log = Log();
    final g = app(tester);
    g.addListener(log);
    final page = FakePage();
    g.voice.attach(page);
    await tester.pump();
    page.say(<String, Object?>{'type': 'graine:ready'});
    await g.voice.start();
    page.say(<String, Object?>{'type': 'graine:call', 'connected': false, 'connecting': true});
    page.say(<String, Object?>{'type': 'graine:progress', 'stage': 'switching'});
    page.say(<String, Object?>{'type': 'graine:progress', 'stage': 'failed'});
    expect(g.voice.callFailed, isTrue);
    expect(g.voice.connecting, isFalse, reason: 'the bar went on saying connecting after the engine gave up');
    expect(g.voice.connectStage, isNull);
    expect(log.events.last, 'call false false', reason: 'the host was not told the attempt is over');
    // The page said "not connecting" first: the failure is still the end of the attempt.
    await g.voice.start();
    page.say(<String, Object?>{'type': 'graine:call', 'connected': false, 'connecting': false});
    log.events.clear();
    page.say(<String, Object?>{'type': 'graine:progress', 'stage': 'failed'});
    expect(log.events, <String>['call false false']);
    page.clear();
    await g.voice.start();
    expect(g.voice.callFailed, isFalse, reason: "a new attempt still showed the last one's failure");
    expect(page.types, contains('graine:start-call'), reason: 'a start after a failed connect places a new call');
    await finish(tester, g);
  });

  testWidgets('a connect the customer is waiting on admits it is slow; one that lands never does',
      (WidgetTester tester) async {
    final g = slowApp(tester, Log());
    final page = FakePage();
    g.voice.attach(page);
    await tester.pump();
    page.say(<String, Object?>{'type': 'graine:ready'});
    await g.voice.start();
    page.say(<String, Object?>{'type': 'graine:call', 'connected': false, 'connecting': true});
    expect(g.voice.slowConnect, isFalse);
    await tester.pump(const Duration(milliseconds: 100));
    expect(g.voice.slowConnect, isFalse);
    await tester.pump(const Duration(milliseconds: 40));
    expect(g.voice.slowConnect, isTrue, reason: 'past the slow mark, the bar still said Connecting…');
    page.say(<String, Object?>{'type': 'graine:call', 'connected': true, 'connecting': false});
    expect(g.voice.slowConnect, isFalse);
    await finish(tester, g);
  });

  testWidgets('a failed connect is not a slow one', (WidgetTester tester) async {
    final g = slowApp(tester, Log());
    final page = FakePage();
    g.voice.attach(page);
    await tester.pump();
    page.say(<String, Object?>{'type': 'graine:ready'});
    await g.voice.start();
    await tester.pump(const Duration(milliseconds: 200));
    expect(g.voice.slowConnect, isTrue);
    page.say(<String, Object?>{'type': 'graine:progress', 'stage': 'failed'});
    expect(g.voice.slowConnect, isFalse);
    await tester.pump(const Duration(milliseconds: 200));
    expect(g.voice.slowConnect, isFalse);
    await finish(tester, g);
  });

  testWidgets("an idle page loading behind no bar is nobody's slow connect; with a bar open it is",
      (WidgetTester tester) async {
    final g = slowApp(tester, Log());
    final page = FakePage();
    g.voice.attach(page);
    await tester.pump(const Duration(milliseconds: 300));
    expect(g.voice.ready, isFalse);
    expect(g.voice.slowConnect, isFalse, reason: 'nobody is waiting on a page loading idle');
    g.voice.viewOpened();
    await tester.pump(const Duration(milliseconds: 100));
    expect(g.voice.slowConnect, isFalse);
    await tester.pump(const Duration(milliseconds: 40));
    expect(g.voice.slowConnect, isTrue, reason: 'the bar is open and the page is still not there');
    page.say(<String, Object?>{'type': 'graine:ready'});
    expect(g.voice.slowConnect, isFalse, reason: 'it landed');
    g.voice.viewClosed();
    await finish(tester, g);
  });

  testWidgets('closing the last bar clears a failed connect, as the customer closing the agent',
      (WidgetTester tester) async {
    final g = app(tester);
    final page = FakePage();
    g.voice.attach(page);
    await tester.pump();
    g.voice.viewOpened();
    page.say(<String, Object?>{'type': 'graine:ready'});
    await g.voice.start();
    page.say(<String, Object?>{'type': 'graine:progress', 'stage': 'failed'});
    expect(g.voice.callFailed, isTrue);
    var heard = 0;
    void count() => heard++;
    g.voice.addListener(count);
    g.voice.viewClosed();
    expect(g.voice.callFailed, isFalse);
    await tester.pump();
    expect(heard, greaterThan(0), reason: 'listeners hear the failure clear');
    g.voice.removeListener(count);
    await finish(tester, g);
  });

  testWidgets('the bar on screen is a customer waiting: a page slow to load says so, and stops when the bar goes',
      (WidgetTester tester) async {
    final g = slowApp(tester, Log());
    final page = FakePage();
    g.voice.attach(page);
    await tester.pump(const Duration(milliseconds: 300));
    expect(g.voice.slowConnect, isFalse, reason: 'no bar yet: nobody is waiting');
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(800, 600)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(children: <Widget>[GraineAgentBar(call: g.voice, showComponents: false)]),
      ),
    ));
    expect(find.text('Connecting…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 140));
    expect(g.voice.slowConnect, isTrue);
    await tester.pump();
    expect(find.text('Still connecting…'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(g.voice.slowConnect, isFalse, reason: 'the bar closed: nobody is waiting any more');
    await finish(tester, g);
  });
}
