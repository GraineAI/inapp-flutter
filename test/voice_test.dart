// The call's wiring, against a fake engine page and a mocked session
// endpoint: the URL it loads, the order of what it posts, the action round
// trip, and every timer (the end watchdog, the background confirm, the load
// watchdog and its retry ladder) on the test's fake clock.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';
import 'package:graine_inapp/graine_inapp.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'contract_files.dart';

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
          return http.Response(jsonEncode(<String, Object?>{'agentId': 'agent-1', 'design': neo['design']}), 200);
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
    expect(page.types, <String>['graine:variables', 'graine:app-context', 'graine:warm']);
    expect(page.posted[0]['variables'], <String, Object?>{
      'brand': 'Graine',
      'plan': 'Plus',
      'cart': '1299',
      'name': 'Asha',
      'phone': '[PHONE]',
    });
    final context = page.posted[1]['context']! as Map<String, Object?>;
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
    expect(page.types, <String>['graine:variables', 'graine:start-call']);

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
    await tester.pump(const Duration(milliseconds: 399));
    expect(page.types, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(page.types, <String>['graine:app-context'], reason: 'three changes, one frame');
    final field = ((page.posted.single['context']! as Map<String, Object?>)['fields']! as List<Object?>).single;
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
}
