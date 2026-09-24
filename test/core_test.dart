// The pure core, proven without a device, a WebView or Flutter: every rule
// the Android SDK's CoreTest and WidgetTest pin, ported case for case, plus
// the Dart-side pieces (the action registry, session parsing, captions, the
// bar's status word). Imports ONLY lib/src/core — no package:flutter.
import 'dart:async';
import 'dart:convert';

import 'package:graine_inapp/src/core/core.dart';
import 'package:test/test.dart';

const String base = 'https://www.graine.ai';

/// The dashboard's own car showcase, as the agent sends it.
Map<String, Object?> cars([String extra = '']) => jsonDecode('''
{"widget_id":"car_showcase:run:3","kind":"product_list","fallback_text":"Three that fit",
 "data":{"title":"Three that fit your budget","prompt":"Tap one and I'll tell you more.","selectLabel":"Compare",
   "items":[
     {"id":"creta","title":"Creta","price":"₹19.2 lakh","imageUrl":"/samples/car-blue.png","facts":["6 airbags","Automatic","18 kmpl","extra"],"subtitle":"Best value"},
     {"id":"seltos","title":"Seltos","price":"₹17.8 lakh","imageUrl":"/samples/car-silver.png"},
     {"id":"vitara","title":"Grand Vitara","unavailable":true}
   ]}$extra}''') as Map<String, Object?>;

Map<String, Object?> obj(String json) => jsonDecode(json) as Map<String, Object?>;

void main() {
  protocolTests();
  maskingTests();
  variableStoreTests();
  loadWatchdogTests();
  retryLadderTests();
  contextFrameTests();
  actionRegistryTests();
  sessionTests();
  jsSemanticsTests();
  widgetStyleTests();
  placementTests();
  widgetAdoptTests();
  widgetContentTests();
  widgetFlowTests();
  frictionTests();
  appearanceTests();
  loaderTests();
  barTests();
}

void protocolTests() {
  group('Protocol', () {
    test('a message into the page is a postMessage that evaluates to true', () {
      final js = Protocol.deliver(Protocol.out(ProtocolOut.setMuted, <String, Object?>{'muted': true}));
      expect(js, startsWith('window.postMessage({'));
      expect(js, contains('"type":"graine:set-muted"'));
      expect(js, contains('"muted":true'));
      // The platforms hand the statement's value back; a non-serialisable one is an error.
      expect(js, endsWith('"*"); true;'));
    });

    test('a line separator in a value cannot break the statement', () {
      final ls = String.fromCharCode(0x2028);
      final ps = String.fromCharCode(0x2029);
      final js = Protocol.deliver(Protocol.out(ProtocolOut.variables,
          <String, Object?>{'variables': <String, Object?>{'note': 'a${ls}b${ps}c'}}));
      expect(js, isNot(contains(ls)));
      expect(js, isNot(contains(ps)));
      expect(js, contains(r'a\u' '2028b' r'\u' '2029c'));
      // Still the same string once the page parses it.
      final json = js.substring('window.postMessage('.length, js.indexOf(', "*")'));
      expect(((jsonDecode(json) as Map<String, Object?>)['variables']! as Map<String, Object?>)['note'], 'a${ls}b${ps}c');
    });

    test('outgoing values are made JSON-safe, recursively', () {
      final m = Protocol.out(ProtocolOut.appActionResult, <String, Object?>{
        'data': <Object?, Object?>{1: 2.5, 'nan': double.nan, 'list': <Object?>{'a', Transport.webrtc}},
      });
      expect(m, <String, Object?>{
        'type': 'graine:app-action-result',
        'data': <String, Object?>{'1': 2.5, 'nan': null, 'list': <Object?>['a', 'webrtc']},
      });
    });

    test('every message the page sends is understood', () {
      expect(Protocol.parse('{"type":"graine:ready"}'), const PageReady());
      expect(Protocol.parse('{"type":"graine:call","connected":true,"connecting":false}'),
          const PageCall(connected: true, connecting: false));
      expect(Protocol.parse('{"type":"graine:muted","muted":true}'), const PageMuted(true));
      expect(Protocol.parse('{"type":"graine:caption","role":"agent","text":"Hi Asha","live":true}'),
          const PageCaption(role: Role.agent, text: 'Hi Asha', live: true));
      expect(Protocol.parse('{"type":"graine:caption","role":"user","text":"hello"}'),
          const PageCaption(role: Role.customer, text: 'hello', live: false));
      expect(Protocol.parse('{"type":"graine:ended"}'), const PageEnded());
      expect(Protocol.parse('{"type":"graine:mic-denied","reason":"NotAllowedError"}'),
          const PageMicDenied('NotAllowedError'));
      expect(Protocol.parse('{"type":"graine:mic-denied"}'), const PageMicDenied('NotAllowedError'));
      expect(Protocol.parse('{"type":"graine:network","online":false}'), const PageNetwork(false));
      expect(Protocol.parse('{"type":"graine:reconnecting","active":true}'), const PageReconnecting(true));

      final q = Protocol.parse('{"type":"graine:quality","sample":{"rtt":480,"jitter":40,"loss":0.1}}')! as PageQuality;
      expect(ConnectionQuality.classify(q.rttMs, q.jitterMs, q.loss), ConnectionQuality.poor);

      final t = Protocol.parse('{"type":"graine:transport","transport":"ws","requested":"rtc","reason":"media","message":"no audio path"}')!
          as PageTransport;
      expect(t.transport, Transport.websocket);
      expect(t.requested, Transport.webrtc);
      expect(t.reason, 'media');
      expect(t.message, 'no audio path');

      final a = Protocol.parse('{"type":"graine:app-action","action":{"action_id":"a1","name":"set_tenure","arguments":{"months":24}}}')!
          as PageAppAction;
      expect(a.actionId, 'a1');
      expect(a.name, 'set_tenure');
      expect(a.arguments['months'], 24);

      final w = Protocol.parse('{"type":"graine:widget","widget":{"kind":"product_list","widget_id":"w1"}}')! as PageWidget;
      expect(w.widget['widget_id'], 'w1');
      final p = Protocol.parse('{"type":"graine:widget-pending","widget":{"kind":"choices","widget_id":"w2"}}')!
          as PageWidgetPending;
      expect(p.widget['kind'], 'choices');
    });

    test('anything that is not ours is ignored rather than guessed at', () {
      for (final raw in <String?>[
        null, '', 'not json', '{}', '{"type":"graine:unheard-of"}', '{"type":"graine:app-action"}', '[1,2]', '"graine:ready"',
      ]) {
        expect(Protocol.parse(raw), isNull, reason: 'raw: $raw');
      }
    });

    test('a missing quality number is unknown, not zero', () {
      // Zero would read as a perfect line. Absent is not perfect.
      final q = Protocol.parse('{"type":"graine:quality","sample":{}}')! as PageQuality;
      expect(ConnectionQuality.classify(q.rttMs, q.jitterMs, q.loss), ConnectionQuality.unknown);
      // Not a measurement: a string, a negative, a NaN.
      final junk = Protocol.parse('{"type":"graine:quality","sample":{"rtt":"450","jitter":-3,"loss":null}}')! as PageQuality;
      expect(<double?>[junk.rttMs, junk.jitterMs, junk.loss], <double?>[null, null, null]);
      expect(ConnectionQuality.classify(double.nan, -1, double.infinity), ConnectionQuality.unknown);
    });

    test('the engine URL trims every trailing slash and encodes like encodeURIComponent', () {
      final url = Protocol.engineUrl(
        baseUrl: 'https://x.test//',
        voiceAgentId: 'a b/c',
        transport: Transport.webrtc,
        cacheKey: "k!~*'()",
        idle: false,
        publishableKey: 'pk+1&2',
        accent: ' #ff8800 ',
      );
      expect(url,
          "https://x.test/embed/a%20b%2Fc?mode=voice&branding=0&embed=1&transport=rtc&b=k!~*'()&pk=pk%2B1%262&accent=ff8800");
      expect(
          Protocol.engineUrl(
              baseUrl: base, voiceAgentId: 'a', transport: Transport.websocket, cacheKey: 'b', idle: true,
              publishableKey: 'k', accent: '#'),
          '$base/embed/a?mode=voice&branding=0&embed=1&transport=ws&b=b&idle=1&pk=k');
    });

    test('a transport word that is not rtc is the WebSocket', () {
      expect(Transport.from('rtc'), Transport.webrtc);
      for (final s in <String?>['ws', 'RTC', '', null, 'webrtc']) {
        expect(Transport.from(s), Transport.websocket, reason: '$s');
      }
    });
  });
}

void maskingTests() {
  group('Masking', () {
    tearDown(Masking.clearCustomRules);

    test('the five rules, in order, with their tokens', () {
      expect(Masking.mask('PAN ABCDE1234F, card 4111-1111-1111-1111, +91 9876543210, 1234 5678 9012'),
          'PAN [PAN], card [CARD], [PHONE], [AADHAAR]');
      expect(Masking.mask('mail a.b@c.io'), 'mail [EMAIL]');
    });

    test('a rule of the app\'s own applies after the built-in five, globally', () {
      Masking.addRule(RegExp(r'POL-\d{6}'));
      expect(Masking.mask('POL-123456 and POL-654321'), '[REDACTED] and [REDACTED]');
    });

    test('a custom token uses JavaScript\'s replacement patterns', () {
      Masking.addRule(RegExp(r'(ACCT)-(\d+)'), r'$1-[NUM]');
      Masking.addRule(RegExp(r'(?<kind>POL)#(\d+)'), r'$<kind>#[$$]');
      Masking.addRule(RegExp(r'X(\d)'), r'[$&|$2|$0]');
      expect(Masking.mask('ACCT-991 POL#77 X5'), r'ACCT-[NUM] POL#[$] [X5|$2|$0]');
    });

    test('deep masking touches every string value and nothing else', () {
      final out = Masking.deep(<String, Object?>{
        'ABCDE1234F': 'ABCDE1234F',
        'n': 9876543210,
        'list': <Object?>['9876543210', 12, true, null, <String, Object?>{'pan': 'ABCDE1234F'}],
      });
      expect(out, <String, Object?>{
        'ABCDE1234F': '[PAN]',
        'n': 9876543210,
        'list': <Object?>['[PHONE]', 12, true, null, <String, Object?>{'pan': '[PAN]'}],
      });
    });
  });
}

void variableStoreTests() {
  group('VariableStore', () {
    test('precedence is dashboard, then build, then runtime, then identity', () {
      final v = VariableStore(<String, Object?>{'plan': 'Free', 'city': 'Pune'});
      v.setDashboardDefaults(<String, Object?>{'plan': 'Default', 'greeting': 'Hi'});
      v.setRuntime(<String, Object?>{'plan': 'Plus', 'cart_total': 1299});
      v.setIdentity(<String, Object?>{'name': 'Asha', 'plan': 'Pro'});
      expect(v.merged(), <String, String>{
        'plan': 'Pro', 'greeting': 'Hi', 'city': 'Pune', 'cart_total': '1299', 'name': 'Asha',
      });
    });

    test('runtime merges, removes on null and drops objects', () {
      final v = VariableStore();
      v.setRuntime(<String, Object?>{'a': '1', 'nested': <String, Object?>{'x': 1}, 'list': <Object?>[1]});
      v.setRuntime(<String, Object?>{'b': true, 'ratio': 0.5});
      v.setRuntime(<String, Object?>{'a': null});
      expect(v.merged(), <String, String>{'b': 'true', 'ratio': '0.5'});
      v.setRuntime(null);
      expect(v.merged(), isEmpty);
    });

    test('numbers are the words a sentence needs: no ".0" on an integer', () {
      final v = VariableStore(<String, Object?>{'n': 3.0, 'x': 12.5, 'i': 7, '': 'dropped'});
      expect(v.merged(), <String, String>{'n': '3', 'x': '12.5', 'i': '7'});
    });

    test('what the app hands over is masked like everything else', () {
      final v = VariableStore();
      v.setIdentity(<String, Object?>{'name': 'Asha', 'phone': '9876543210'});
      v.setRuntime(<String, Object?>{'note': 'PAN ABCDE1234F'});
      expect(v.merged()['phone'], '[PHONE]');
      expect(v.merged()['note'], 'PAN [PAN]');
      expect(v.merged()['name'], 'Asha');
      expect(v.identity(), <String, String>{'name': 'Asha', 'phone': '[PHONE]'});
    });

    test('sign-out clears who it was', () {
      final v = VariableStore();
      v.setIdentity(<String, Object?>{'name': 'Asha'});
      v.setIdentity(null);
      expect(v.merged(), isEmpty);
    });
  });
}

void loadWatchdogTests() {
  group('LoadWatchdog', () {
    test('a load still arriving is never called stuck, however slow', () {
      final w = LoadWatchdog(stallMs: 40, bootMs: 40, hardCapMs: 10000);
      w.start(0);
      var t = 0;
      for (var p = 1; p <= 20; p++) {
        t += 30;
        w.progress(p * 4, t);
        expect(w.check(t), LoadVerdict.wait);
      }
    });

    test('silence is a stall, and a mute page is a boot timeout', () {
      final w = LoadWatchdog(stallMs: 40, bootMs: 40);
      w.start(0);
      w.progress(30, 10);
      expect(w.check(60), LoadVerdict.stalled);
      w.start(0);
      w.progress(100, 10);
      expect(w.check(60), LoadVerdict.bootTimeout);
      w.start(0);
      w.loaded(20);
      expect(w.check(59), LoadVerdict.wait);
      expect(w.check(60), LoadVerdict.bootTimeout);
      expect(LoadVerdict.bootTimeout.reason, 'boot_timeout');
      expect(LoadVerdict.loadCap.reason, 'load_cap');
    });

    test('a lower progress report is not the page going backwards', () {
      final w = LoadWatchdog(stallMs: 40);
      w.start(0);
      w.progress(90, 10);
      w.progress(10, 30);
      w.progress(10, 45);
      expect(w.check(55), LoadVerdict.stalled);
    });

    test('a link that dribbles forever still ends', () {
      final w = LoadWatchdog(stallMs: 1000, hardCapMs: 100);
      w.start(0);
      w.progress(50, 90);
      expect(w.check(101), LoadVerdict.loadCap);
    });

    test('it never wakes more than four times a second at the default window', () {
      final w = LoadWatchdog();
      w.start(0);
      expect(w.nextCheckInMs(14999), 250);
      expect(w.nextCheckInMs(0), 15000);
    });

    test('a short window is checked within a quarter of itself', () {
      final w = LoadWatchdog(stallMs: 40);
      w.start(0);
      expect(w.nextCheckInMs(39), 10);
    });
  });
}

void retryLadderTests() {
  group('RetryLadder', () {
    test('jittered within a quarter, and then exhausted', () {
      final lo = RetryLadder(delaysMs: <int>[1000, 2000], random: () => 0.0);
      expect(lo.next(), 750);
      expect(lo.next(), 1500);
      expect(lo.next(), isNull);
      expect(lo.exhausted, isTrue);
      expect(lo.attempt, 2);
      final hi = RetryLadder(delaysMs: <int>[1000], random: () => 1.0);
      expect(hi.next(), 1250);
      hi.reset();
      expect(hi.exhausted, isFalse);
      expect(hi.attempt, 0);
    });

    test('the default ladder is six rungs, 1s to 15s', () {
      final l = RetryLadder(random: () => 0.5);
      final got = <int?>[for (var i = 0; i < 7; i++) l.next()];
      expect(got, <int?>[1000, 2000, 4000, 8000, 15000, 15000, null]);
    });
  });
}

void contextFrameTests() {
  group('ContextFrame', () {
    test('the frame is the shape the runtime reads, and is masked', () {
      final frame = ContextFrame.build(
        screen: const GraineScreen(
          'kyc_documents',
          title: 'Upload your documents',
          journey: GraineJourney('KYC', step: 2, of: 4),
          fields: <GraineField>[
            GraineField('pan', label: 'PAN', value: 'ABCDE1234F', status: FieldStatus.invalid, error: 'Not recognised'),
          ],
          availableActions: <String>['fill_pan'],
        ),
        screenSinceMs: 1000,
        nowMs: 46000,
        identity: const <String, String>{'name': 'Asha'},
        appVersion: '2.4.0',
      )!;
      final ctx = frame['context']! as Map<String, Object?>;
      expect(ctx['screen'], 'kyc_documents');
      expect((ctx['journey']! as Map<String, Object?>)['step'], 2);
      final field = (ctx['fields']! as List<Object?>).first! as Map<String, Object?>;
      expect(field['value'], '[PAN]');
      expect(field['status'], 'invalid');
      expect(ctx['idle_ms'], 45000);
      expect((ctx['user']! as Map<String, Object?>)['name'], 'Asha');
      expect(ctx['app_version'], '2.4.0');
      expect(frame['availableActions'], <String>['fill_pan']);
    });

    test('exactly the keys the React Native SDK sends, and nothing absent', () {
      final frame = ContextFrame.build(
        screen: const GraineScreen('home', data: <String, Object?>{'balance': 1200.5, 'note': 'call 9876543210'}),
        screenSinceMs: 5000,
        nowMs: 1000, // a clock that went backwards is not a negative idle
        recentEvents: <Map<String, Object?>>[
          <String, Object?>{'name': 'otp_failed', 'at': 1, 'data': <String, Object?>{'phone': '9876543210'}},
        ],
      )!;
      expect(frame.keys, <String>['context']);
      expect(frame['context'], <String, Object?>{
        'screen': 'home',
        'data': <String, Object?>{'balance': 1200.5, 'note': 'call [PHONE]'},
        'idle_ms': 0,
        'recent_events': <Object?>[
          <String, Object?>{'name': 'otp_failed', 'at': 1, 'data': <String, Object?>{'phone': '[PHONE]'}},
        ],
      });
    });

    test('nothing to say is no frame', () {
      expect(ContextFrame.build(screen: null, screenSinceMs: 0, nowMs: 0), isNull);
    });

    test('an unchanged screen is equal, so it is not resent', () {
      GraineScreen s(String v) => GraineScreen('pan',
          fields: <GraineField>[GraineField('pan', value: v)],
          data: <String, Object?>{'a': <Object?>[1, <String, Object?>{'b': v}]});
      expect(s('x'), s('x'));
      expect(s('x').hashCode, s('x').hashCode);
      expect(s('x'), isNot(s('y')));
    });
  });
}

void actionRegistryTests() {
  group('ActionRegistry', () {
    test('an action this build does not implement is refused, by name', () async {
      final requested = <String>[];
      final done = <ActionResult>[];
      final r = await ActionRegistry().execute('open_x', <String, Object?>{},
          onRequested: requested.add, onCompleted: (String n, ActionResult res) => done.add(res));
      expect(r, const ActionResult.refused('This app build does not implement "open_x".'));
      expect(requested, <String>['open_x']);
      expect(done, <ActionResult>[r]);
    });

    test('sync, async and silent handlers all answer', () async {
      final reg = ActionRegistry();
      reg.register('sync', (Map<String, Object?> a) => ActionResult.ok('set ${a['months']}'));
      reg.register('later', (Map<String, Object?> a) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return const ActionResult.refused('locked after submission');
      });
      reg.register('silent', (Map<String, Object?> a) => null);
      expect(await reg.execute('sync', <String, Object?>{'months': 24}), const ActionResult.ok('set 24'));
      expect(await reg.execute('later', <String, Object?>{}), const ActionResult.refused('locked after submission'));
      expect((await reg.execute('silent', <String, Object?>{})).status, ActionStatus.ok);
    });

    test('a handler that throws is an error, in its own words', () async {
      final reg = ActionRegistry();
      reg.register('boom', (Map<String, Object?> a) => throw Exception('no network'));
      reg.register('boom_async', (Map<String, Object?> a) async => throw StateError('bad state'));
      expect(await reg.execute('boom', <String, Object?>{}), const ActionResult.error('no network'));
      expect(await reg.execute('boom_async', <String, Object?>{}), const ActionResult.error('Bad state: bad state'));
    });

    test('a slow handler is told off at the deadline, exactly once', () async {
      final reg = ActionRegistry(deadline: const Duration(milliseconds: 40));
      final completer = Completer<ActionResult?>();
      reg.register('slow', (Map<String, Object?> a) => completer.future);
      final done = <ActionResult>[];
      final r = await reg.execute('slow', <String, Object?>{},
          onCompleted: (String n, ActionResult res) => done.add(res));
      expect(r.status, ActionStatus.error);
      expect(r.message, 'The app did not answer within 0 seconds.');
      completer.complete(const ActionResult.ok('too late'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(done, hasLength(1));
      expect(ActionRegistry().deadline.inMilliseconds, 6000);
    });

    test('unregistering removes only the handler that was registered', () {
      final reg = ActionRegistry();
      ActionResult first(Map<String, Object?> a) => const ActionResult.ok('1');
      ActionResult second(Map<String, Object?> a) => const ActionResult.ok('2');
      final off = reg.register('go', first);
      reg.register('go', second);
      off();
      expect(reg.names, <String>['go']);
      expect(reg.has('go'), isTrue);
    });
  });
}

void sessionTests() {
  group('SessionConfig', () {
    test('the session response is read the way the Android SDK reads it', () {
      final s = SessionConfig.fromJson(obj('''{
        "agentId":"a1","webcallAgentId":"w1","pageVersion":"dpl_9",
        "appearance":{"audioTransport":"rtc","accent":"318CE7","title":"Asha"},
        "variables":{"brand":"Graine","n":2},
        "appActions":[{"tool_name":"open_screen"},{"toolName":"set_tenure"},{"name":"fill_pan"},{"name":""},"junk"],
        "friction":{"idle":{"afterMs":20000}}
      }'''));
      expect(s.agentId, 'a1');
      expect(s.webcallAgentId, 'w1');
      expect(s.pageVersion, 'dpl_9');
      expect(s.preferredTransport, Transport.webrtc);
      expect(s.accent, '318CE7');
      expect(s.variables, <String, Object?>{'brand': 'Graine', 'n': 2});
      expect(s.declaredActions, <String>{'open_screen', 'set_tenure', 'fill_pan'});
      expect(FrictionConfig.fromJson(s.friction)!.idleAfterMs, 20000);
    });

    test('an agent with no separate web-call id calls itself; no page version is no cache key', () {
      final s = SessionConfig.fromJson(obj('{"agentId":"a1","pageVersion":""}'));
      expect(s.webcallAgentId, 'a1');
      expect(s.pageVersion, isNull);
      expect(s.preferredTransport, Transport.websocket);
      expect(s.accent, isNull);
      expect(s.declaredActions, isEmpty);
    });

    test('a refusal says what to fix', () {
      expect(SessionConfig.errorFor(200, <String, Object?>{}), isNull);
      expect(SessionConfig.errorFor(403, <String, Object?>{'error': 'origin not allowed'}),
          'This agent does not accept connections from a mobile app yet. Add "app://" to its Allowed domains '
          'in the dashboard, under Embed & Widgets. (server said: origin not allowed)');
      expect(SessionConfig.errorFor(403, <String, Object?>{}), endsWith('(server said: forbidden)'));
      expect(SessionConfig.errorFor(401, <String, Object?>{}),
          'Publishable key was rejected. Check it against Embed & Widgets in the dashboard.');
      expect(SessionConfig.errorFor(429, <String, Object?>{'error': 'slow down'}), 'slow down');
      expect(SessionConfig.errorFor(500, <String, Object?>{}), 'Embed rejected (500)');
    });
  });
}

void jsSemanticsTests() {
  group('Js', () {
    test('numbers print the way JavaScript prints them', () {
      expect(Js.str(5.0), '5');
      expect(Js.str(19.5), '19.5');
      expect(Js.str(-3.0), '-3');
      expect(Js.str(0.000015), '0.000015');
      expect(Js.str(1e-7), '1e-7');
      expect(Js.str(1e20), '100000000000000000000');
      expect(Js.str(1e21), '1e+21');
      expect(Js.str(-0.0), '0');
      expect(Js.str(double.nan), 'NaN');
      expect(Js.str(double.negativeInfinity), '-Infinity');
      expect(Js.str(7), '7');
    });

    test('truthiness and String() are JavaScript\'s', () {
      expect(Js.truthy(''), isFalse);
      expect(Js.truthy(0), isFalse);
      expect(Js.truthy(double.nan), isFalse);
      expect(Js.truthy(null), isFalse);
      expect(Js.truthy('0'), isTrue);
      expect(Js.truthy(<String, Object?>{}), isTrue);
      expect(Js.truthy(<Object?>[]), isTrue);
      expect(Js.str(null), 'null');
      expect(Js.str(<String, Object?>{}), '[object Object]');
      expect(Js.str(<Object?>['a', null, 2]), 'a,,2');
      expect(Js.strOrEmpty(null), '');
      expect(Js.round(2.5), 3);
      expect(Js.round(-2.5), -2);
    });
  });
}

void widgetStyleTests() {
  group('WidgetStyle', () {
    test('nothing, garbage and arrays are the default look', () {
      for (final raw in <Object?>[null, '', 0, 'gallery', <Object?>[], 42]) {
        expect(Widgets.normaliseStyle(raw), const WidgetStyle(), reason: '$raw');
      }
    });

    test('a Dart map is read like JSON', () {
      expect(Widgets.normaliseStyle(<String, Object?>{'preset': 'LIST', 'select': 'many', 'maxSelect': 4}),
          const WidgetStyle(preset: 'list', select: 'many', maxSelect: 4));
    });

    test('a look built by hand with junk still draws', () {
      expect(Widgets.resolveLook(const WidgetStyle(preset: 'hologram'), 'x').preset, 'cards');
    });

    test('several chosen are named the way a person would', () {
      expect(Widgets.manySummary(<String>['Creta', ' Seltos ', '', 'Venue']), "Let's compare Creta, Seltos and Venue.");
      expect(Widgets.manySummary(<String>['Creta'], 'choose'), "Let's choose Creta.");
      expect(Widgets.manySummary(<String>[' ']), '');
    });
  });
}

void placementTests() {
  group('Placement', () {
    const b = PlacementBounds(windowHeight: 844, baseBottom: 96, barHeight: 64);

    test('dragging up raises the bar; the gesture\'s dy grows downward', () {
      expect(Placement.offsetDuringDrag(0, -120, b), 120);
      expect(Placement.offsetDuringDrag(100, 30, b), 70);
      expect(Placement.offsetDuringDrag(0, 500, b), 0);
      expect(Placement.clampOffset(10000, b), 844 - 48 - 64 - 96);
    });

    test('garbage is the anchor, not NaN', () {
      expect(Placement.clampOffset(double.nan, b), 0);
      expect(Placement.clampOffset(double.infinity, b), 0);
    });

    test('a small movement is a tap, in either axis', () {
      expect(Placement.isTap(3, 4), isTrue);
      expect(Placement.isTap(Placement.dragSlop, 0), isFalse);
      expect(Placement.isTap(0, -Placement.dragSlop), isFalse);
    });

    test('no keyboard is no lift, whatever the window did', () {
      expect(KeyboardLift.liftFor(double.nan, 0), 0);
      expect(KeyboardLift.liftFor(0, 200), 0);
      expect(KeyboardLift.liftFor(336, double.nan), 336);
      expect(KeyboardLift.liftFor(336, 330), 6);
      expect(KeyboardLift.liftFor(200, -100), 200);
    });
  });
}

void widgetAdoptTests() {
  group('GraineWidget.adopt', () {
    test('a frame is adopted as the React Native SDK adopts it', () {
      final w = GraineWidget.adopt(
          cars(',"style":{"preset":"Gallery","onclick":"x"},"on_select":{"path":"compare?ids={id}"}'), base)!;
      expect(w.id, 'car_showcase:run:3');
      expect(w.kind, 'product_list');
      expect(w.style.preset, 'gallery');
      expect(w.onSelect.path, 'compare?ids={id}');
      final first = (w.data['items']! as List<Object?>).first! as Map<String, Object?>;
      expect(first['imageUrl'], '$base/samples/car-blue.png');
    });

    test('no widget_id is not a component', () {
      expect(GraineWidget.adopt(obj('{"kind":"product_list"}'), base), isNull);
      expect(GraineWidget.adopt(obj('{"widget_id":"","kind":"x"}'), base), isNull);
      expect(GraineWidget.adopt(null, base), isNull);
      expect(GraineWidget.adopt(obj('{"id":"w9","kind":"x"}'), base)!.id, 'w9');
    });

    test('on_select is also read under its camelCase name', () {
      expect(GraineWidget.adopt(obj('{"widget_id":"w","kind":"x","onSelect":{"action":"go"}}'), base)!.onSelect.action, 'go');
    });
  });
}

WidgetContent content(Map<String, Object?> raw) => WidgetContent(GraineWidget.adopt(raw, base)!);

void widgetContentTests() {
  group('WidgetContent', () {
    test('a product list is rows with pictures, prices and at most three facts', () {
      final c = content(cars());
      expect(c.isProducts, isTrue);
      expect(c.drawable, isTrue);
      expect(c.rows, hasLength(3));
      final creta = c.rows[0];
      expect(creta.facts, <String>['6 airbags', 'Automatic', '18 kmpl']);
      expect(creta.image, '$base/samples/car-blue.png');
      expect(creta.subtitle, 'Best value');
      expect(creta.selectLabel, 'Compare');
      expect(c.rows[2].unavailable, isTrue);
      expect(c.title, 'Three that fit your budget');
      expect(c.prompt, "Tap one and I'll tell you more.");
    });

    test('tapping one sends the payload and sentence the runtime reads', () {
      final a = content(cars()).pick(0);
      expect(a.data, <String, Object?>{'id': 'creta', 'title': 'Creta', 'price': '₹19.2 lakh'});
      expect(a.summary, "I'll take a look at Creta at ₹19.2 lakh.");
      final noPrice = content(cars()).pick(2);
      expect(noPrice.summary, "I'll take a look at Grand Vitara.");
      expect(noPrice.data['price'], '');
    });

    test('several chosen are one answer naming them all', () {
      final a = content(cars()).pickMany(<String>['creta', 'seltos']);
      expect(a.data['count'], 2);
      expect(a.data['ids'], 'creta,seltos');
      expect(a.data['titles'], 'Creta, Seltos');
      expect(a.data['items'], hasLength(2));
      expect(a.summary, "Let's compare Creta and Seltos.");
    });

    test('ticking several: the oldest gives way at the cap, and the button counts down to two', () {
      expect(WidgetContent.toggle(<String>['a', 'b'], 'c', 2), <String>['b', 'c']);
      expect(WidgetContent.toggle(<String>['a', 'b'], 'a', 2), <String>['b']);
      expect(WidgetContent.toggle(<String>[], 'a', 3), <String>['a']);
      final c = content(cars());
      expect(c.manyButtonLabel(0), 'Pick 2 more to compare');
      expect(c.manyButtonLabel(1), 'Pick 1 more to compare');
      expect(c.manyButtonLabel(3), 'Compare 3');
    });

    test('a plan comparison is rows too, with its own payload', () {
      final c = content(obj('''{"widget_id":"plans:1","kind":"plan_comparison","data":{"plans":[
          {"id":"basic","name":"Basic","price":"₹299","priceSuffix":"/mo","badge":"Popular","facts":[{"label":"Cover","value":"₹5L"},{"value":"No wait"},{"label":"Tax"}]},
          {"id":"family","name":"Family Shield","price":499}]}}'''));
      expect(c.isProducts, isTrue);
      expect(c.rows[0].price, '₹299/mo');
      expect(c.rows[0].facts, <String>['Cover ₹5L', 'No wait', 'Tax undefined']);
      expect(c.rows[0].subtitle, 'Popular');
      expect(c.rows[1].price, '499');
      expect(c.rows[1].selectLabel, 'Select');
      final a = c.pick(1);
      expect(a.data, <String, Object?>{'id': 'family', 'name': 'Family Shield', 'price': '499'});
      expect(a.summary, "I'll take Family Shield at 499.");
    });

    test('an info card is one row whose button is its action label', () {
      final c = content(obj('{"widget_id":"i","kind":"info_card","data":{"title":"Loan status","summary":"Approved","category":"Loans","actionLabel":"Show EMI","facts":[{"label":"Rate","value":"9.5%"}]}}'));
      expect(c.rows, hasLength(1));
      expect(c.rows[0].facts, <String>['Approved', 'Rate 9.5%']);
      expect(c.rows[0].selectLabel, 'Show EMI');
      expect(c.pick(0), const WidgetAnswer(<String, Object?>{'action': 'Show EMI'}, 'Show EMI'));
      expect(c.surface(Widgets.resolveLook(null, 'info_card')), 'card');
    });

    test('choices and quick actions are chips, with each kind\'s own keys', () {
      final choices = content(obj('{"widget_id":"c","kind":"choices","data":{"options":[{"id":"y","label":"Yes"},"No",{"title":"Maybe"}]}}'));
      expect(choices.isChips, isTrue);
      expect(choices.isProducts, isFalse);
      expect(choices.chips.map((WidgetChip c) => c.label), <String>['Yes', 'No', 'Maybe']);
      expect(choices.pickChip(choices.chips[0]),
          const WidgetAnswer(<String, Object?>{'chosen': 'y', 'label': 'Yes'}, "I'll go with Yes."));
      final quick = content(obj('{"widget_id":"q","kind":"quick_actions","data":{"actions":[{"id":"call","label":"Call me"}]}}'));
      expect(quick.isQuickActions, isTrue);
      expect(quick.pickChip(quick.chips[0]).data, <String, Object?>{'id': 'call', 'label': 'Call me'});
      expect(quick.surface(Widgets.resolveLook(null, 'quick_actions')), 'sheet');
    });

    test('calendar slots are days and their times', () {
      final c = content(obj('''{"widget_id":"s","kind":"calendar_slots","data":{"note":"IST","days":[
          {"label":"Mon","slots":["10:00","11:00"]},{"id":"tue","slots":[]},{"slots":["9:00"]}]}}'''));
      expect(c.isCalendar, isTrue);
      expect(c.days.map((WidgetDay d) => d.label), <String>['Mon', 'Day 3']);
      expect(c.pickSlot(c.days[0], '11:00'),
          const WidgetAnswer(<String, Object?>{'day': 'Mon', 'slot': '11:00'}, 'Mon at 11:00, please.'));
      expect(c.note, 'IST');
    });

    test('a kind this build cannot draw is the fallback sentence, on a card', () {
      final c = content(obj('{"widget_id":"f","kind":"form","fallback_text":"Fill in your address","data":{"fields":[1]}}'));
      expect(c.drawable, isFalse);
      expect(c.surface(Widgets.resolveLook(const WidgetStyle(surface: 'screen'), 'form')), 'card');
      expect(c.widget.fallbackText, 'Fill in your address');
    });

    test('an explicit surface wins for a drawable kind', () {
      final w = GraineWidget.adopt(cars(',"style":{"surface":"card"}'), base)!;
      expect(WidgetContent(w).surface(Widgets.resolveLook(w.style, w.kind)), 'card');
      expect(content(cars()).surface(Widgets.resolveLook(null, 'product_list')), 'screen');
    });
  });
}

void widgetFlowTests() {
  group('WidgetFlow', () {
    final pending = obj('{"widget_id":"car_showcase:run:3","kind":"product_list"}');

    test('a component with no announced wait draws at once', () {
      final f = WidgetFlow(base);
      expect(f.onWidget(cars(), 1000), isTrue);
      expect(f.widget?.id, 'car_showcase:run:3');
      expect(f.nextDeadline(), isNull);
    });

    test('the loader stays at least its minimum, then the component replaces it', () {
      final f = WidgetFlow(base);
      f.onPending(pending, 0);
      expect(f.loading, const WidgetPending('car_showcase:run:3', 'product_list'));
      expect(f.onWidget(cars(), 100), isFalse, reason: 'held: the loader has only been up 100ms');
      expect(f.widget, isNull);
      expect(f.loading, isNotNull, reason: 'still loading while held');
      expect(f.nextDeadline(), Widgets.minLoaderMs);
      expect(f.tick(449), isFalse);
      expect(f.tick(450), isTrue);
      expect(f.widget?.id, 'car_showcase:run:3');
      expect(f.loading, isNull);
    });

    test('a loader nothing arrives for gives up', () {
      final f = WidgetFlow(base);
      f.onPending(pending, 0);
      expect(f.nextDeadline(), Widgets.pendingWidgetMs);
      f.tick(Widgets.pendingWidgetMs - 1);
      expect(f.loading, isNotNull);
      f.tick(Widgets.pendingWidgetMs);
      expect(f.loading, isNull);
    });

    test('closing while it waits cancels the component that was loading', () {
      final f = WidgetFlow(base);
      f.onPending(pending, 0);
      f.onWidget(cars(), 100);
      expect(f.dismiss(), isNull, reason: 'nothing was on screen, so there is nothing to report');
      f.tick(10000);
      expect(f.widget, isNull, reason: 'a component must not appear after the customer closed the wait');
      expect(f.loading, isNull);
    });

    test('answering keeps the choice and waits for the agent', () {
      final f = WidgetFlow(base);
      f.onWidget(cars(), 0);
      final s = f.submit(<String, Object?>{'id': 'creta', 'title': 'Creta', 'price': '₹19.2 lakh'},
          "I'll take a look at Creta.", 1000)!;
      expect(s.widgetId, 'car_showcase:run:3');
      expect(s.action, isNull, reason: 'no on_select: no in-app action');
      expect(f.widget, isNull);
      expect(f.answered?.summary, "I'll take a look at Creta.");
      expect(f.awaitingReply, isTrue);
      f.onAgentStarted();
      expect(f.awaitingReply, isFalse);
      expect(f.answered, isNotNull, reason: 'the line stays after the agent answers');
    });

    test('the wait for the agent is bounded', () {
      final f = WidgetFlow(base);
      f.onWidget(cars(), 0);
      f.submit(<String, Object?>{'id': 'creta'}, 'x', 1000);
      f.tick(1000 + Widgets.awaitingReplyMs);
      expect(f.awaitingReply, isFalse);
    });

    test('a component\'s action runs with the tapped item, and its say replaces the sentence', () {
      final f = WidgetFlow(base);
      f.onWidget(
          cars(',"on_select":{"action":"open_comparison","args":{"id":"{id}","label":"{title} at {price}"},"say":"Comparing {title}."}'),
          0);
      final s = f.submit(<String, Object?>{'id': 'creta', 'title': 'Creta', 'price': '₹19.2 lakh'},
          "I'll take a look at Creta.", 0)!;
      expect(s.action, const SelectCall('open_comparison', <String, String>{'id': 'creta', 'label': 'Creta at ₹19.2 lakh'}));
      expect(s.summary, 'Comparing Creta.');
      expect(f.answered?.summary, 'Comparing Creta.');
    });

    test('a path goes through the one navigate handler with every chosen id', () {
      final f = WidgetFlow(base);
      f.onWidget(cars(',"on_select":{"path":"compare?ids={ids}"}'), 0);
      final many = WidgetContent(f.widget!).pickMany(<String>['creta', 'seltos']);
      final s = f.submit(many.data, many.summary, 0)!;
      expect(s.action, const SelectCall(Widgets.navigateAction, <String, String>{'path': 'compare?ids=creta,seltos'}));
    });

    test('closing tells the agent quietly what was closed, and it can be put back', () {
      final f = WidgetFlow(base);
      f.onWidget(cars(), 0);
      final d = f.dismiss()!;
      expect(d.eventData(), <String, Object?>{
        'tool_name': 'car_showcase', 'kind': 'product_list', 'title': 'Three that fit your budget', 'answered': false,
      });
      expect(f.widget, isNull);
      expect(f.closed?.id, 'car_showcase:run:3');
      expect(f.reopen(), isTrue);
      expect(f.widget?.id, 'car_showcase:run:3');
      expect(f.closed, isNull);
    });

    test('clearing the answered line reports nothing and forgets it', () {
      final f = WidgetFlow(base);
      f.onWidget(cars(), 0);
      f.submit(<String, Object?>{'id': 'creta'}, 'x', 0);
      expect(f.dismiss(), isNull);
      expect(f.answered, isNull);
      expect(f.awaitingReply, isFalse);
    });

    test('the next component replaces the last answer', () {
      final f = WidgetFlow(base);
      f.onWidget(cars(), 0);
      f.submit(<String, Object?>{'id': 'creta'}, 'x', 0);
      f.onWidget(obj('{"widget_id":"slots:9","kind":"calendar_slots","data":{}}'), 5000);
      expect(f.answered, isNull);
      expect(f.awaitingReply, isFalse, reason: 'a component is the agent answering');
      expect(f.widget?.id, 'slots:9');
    });

    test('a retained component is picked up but not replayed over itself', () {
      final f = WidgetFlow(base);
      f.seed(cars());
      expect(f.widget?.id, 'car_showcase:run:3');
      final same = f.widget;
      f.seed(cars());
      expect(identical(same, f.widget), isTrue);
      f.seed(null);
      expect(identical(same, f.widget), isTrue);
    });

    test('a new call starts clean', () {
      final f = WidgetFlow(base);
      f.onPending(pending, 0);
      f.onWidget(cars(), 1000);
      f.dismiss();
      f.reset();
      expect(f.widget, isNull);
      expect(f.closed, isNull);
      expect(f.loading, isNull);
      expect(f.nextDeadline(), isNull);
    });
  });
}

void frictionTests() {
  group('FrictionDetector', () {
    GraineScreen pan(FieldStatus? status, String? error) => GraineScreen('kyc_pan', title: 'PAN', fields: <GraineField>[
          GraineField('pan', label: 'PAN', status: status, error: error),
          const GraineField('middle', label: 'Middle name', status: FieldStatus.empty, optional: true),
        ]);

    test('the SDK default waits for an outstanding field, and names it', () {
      final d = FrictionDetector(rules: Friction.resolve(<FrictionConfig?>[const FrictionConfig(idleAfterMs: 10000)]));
      d.onScreen(pan(FieldStatus.filled, null), 0);
      expect(d.idleDueIn(0), isNull, reason: 'nothing outstanding, nothing to be stuck on');
      d.onScreen(pan(FieldStatus.invalid, 'Not recognised'), 5000);
      expect(d.idleDueIn(5000), 10000, reason: 'the clock starts when the field went wrong');
      final s = d.onIdle(15000)!;
      expect(s.name, 'stalled_on_step');
      expect(s.detail, 'The customer has not touched the "PAN" screen for 10s. The "PAN" field is showing: Not recognised.');
      expect(d.onIdle(40000), isNull, reason: 'once per visit');
    });

    test('an optional blank is not what they are stuck on', () {
      final d = FrictionDetector(rules: Friction.resolve(<FrictionConfig?>[const FrictionConfig(idleAfterMs: 1000)]));
      d.onScreen(const GraineScreen('details', fields: <GraineField>[
        GraineField('middle', label: 'Middle name', status: FieldStatus.empty, optional: true),
      ]), 0);
      expect(d.idleDueIn(0), isNull);
      d.onScreen(const GraineScreen('details', fields: <GraineField>[
        GraineField('middle', label: 'Middle name', status: FieldStatus.empty, optional: true),
        GraineField('pan', label: 'PAN', status: FieldStatus.empty),
      ]), 10);
      expect(d.onIdle(1010)!.detail, 'The customer has not touched the "details" screen for 1s. The "PAN" field is empty.');
    });

    test('a field edit on the same screen does not restart the clock', () {
      final d = FrictionDetector(rules: Friction.resolve(<FrictionConfig?>[const FrictionConfig(idleAfterMs: 10000)]));
      d.onScreen(pan(FieldStatus.empty, null), 0);
      d.onScreen(pan(FieldStatus.invalid, 'Too short'), 6000);
      expect(d.idleDueIn(6000), 4000);
    });

    test('gated on a call, the clock starts when the call does, and a new call may hear it again', () {
      final d = FrictionDetector(
          rules: Friction.resolve(<FrictionConfig?>[const FrictionConfig(idleAfterMs: 10000, cooldownMs: 1)]),
          gateOnCall: true);
      d.onScreen(pan(FieldStatus.empty, null), 0);
      expect(d.idleDueIn(60000), isNull, reason: 'no call, no one to tell');
      d.onCall(true, 60000);
      expect(d.idleDueIn(60000), 10000);
      expect(d.onIdle(70000), isNotNull);
      expect(d.idleDueIn(70001), isNull);
      d.onCall(false, 80000);
      d.onCall(true, 90000);
      expect(d.idleDueIn(90000), 10000, reason: 'a new conversation has not heard it');
    });

    test('the dashboard\'s per-screen rules apply under the app\'s', () {
      final dashboard = FrictionConfig.fromJson(obj('''{"idle":{"afterMs":45000},"nudge":{"openLauncher":true,"maxPerSession":2,"cooldownSeconds":30},
          "screens":{"home":{"idle":false},"agent_demo":{"ignore":true},"otp":{"idle":{"afterMs":"20000"},"message":"OTP for {seconds}s: {field} {error}"}}}'''));
      final rules = Friction.resolve(<FrictionConfig?>[
        dashboard,
        const FrictionConfig(screens: <String, FrictionScreenRule>{'otp': FrictionScreenRule(idleAfterMs: 15000)}),
      ]);
      expect(rules.forScreen('home').idleAfterMs, isNull);
      expect(rules.forScreen('agent_demo').ignore, isTrue);
      expect(rules.forScreen('otp').idleAfterMs, 15000);
      expect(rules.forScreen('anything').idleAfterMs, 45000);
      final d = FrictionDetector(rules: rules);
      d.onScreen(const GraineScreen('otp', fields: <GraineField>[GraineField('code', label: 'OTP', status: FieldStatus.empty)]), 0);
      final s = d.onIdle(15000)!;
      expect(s.detail, 'OTP for 15s: OTP empty');
      expect(s.cooldownSeconds, 30);
      expect(s.maxPerSession, 2);
      expect(s.openLauncher, isTrue);
    });

    test('zero switches it off, and enabled:false silences everything', () {
      expect(Friction.resolve(<FrictionConfig?>[const FrictionConfig(idleAfterMs: 0)]).idleAfterMs, isNull);
      final d = FrictionDetector(
          rules: Friction.resolve(<FrictionConfig?>[const FrictionConfig(enabled: false, idleAfterMs: 10)]));
      d.onScreen(pan(FieldStatus.empty, null), 0);
      expect(d.idleDueIn(0), isNull);
      expect(d.onIdle(100), isNull);
    });
  });
}

void appearanceTests() {
  group('Appearance', () {
    test('colours parse in every shape the dashboard sends', () {
      expect(Appearance.argb('#318CE7'), 0xFF318CE7);
      expect(Appearance.argb('318ce7'), 0xFF318CE7);
      expect(Appearance.argb('#f0a'), 0xFFFF00AA);
      expect(Appearance.argb('#80112233'), 0x80112233);
      expect(Appearance.argb('red'), isNull);
      expect(Appearance.argb(null), isNull);
    });

    test('a tint is the accent at partial strength', () {
      expect(Appearance.tint('#318CE7', 0.15), 0x26318CE7);
      // Not a colour: the neutral slate the RN SDK falls back to.
      expect(Appearance.tint('rebeccapurple', 0.15), (0x26 << 24) | 0x788CAA);
    });

    test('encodeURIComponent is JavaScript\'s', () {
      expect(Appearance.encodeURIComponent('a b+c/&='), 'a%20b%2Bc%2F%26%3D');
      expect(Appearance.encodeURIComponent("it's(ok)!~*-_."), "it's(ok)!~*-_.");
      expect(Appearance.encodeURIComponent('आ'), '%E0%A4%86');
    });

    test('the dashboard decides and the host is the fallback', () {
      final a = Appearance.resolve(<String, Object?>{'accent': 'ff8800', 'title': ' Asha ', 'logo': 'org/logo 1.png', 'radius': '12'},
          accent: '#318CE7', heading: 'Assistant');
      expect(a.accent, '#ff8800');
      expect(a.heading, 'Asha');
      expect(a.logoUrl, 'https://www.graine.ai/api/embed/logo?k=org%2Flogo%201.png');
      expect(a.radius, 12);
      final none = Appearance.resolve(null, accent: '#318CE7', heading: 'Assistant', radius: 60);
      expect(<Object?>[none.accent, none.heading, none.logoUrl, none.radius], <Object?>['#318CE7', 'Assistant', null, 48]);
    });

    test('a button label stays readable on any accent someone picks', () {
      expect(Appearance.palette(<String, Object?>{}, accent: '#318CE7').onAccent, '#FFFFFF');
      expect(Appearance.palette(<String, Object?>{}, accent: '#FFD400').onAccent, '#101318');
      expect(Appearance.palette(<String, Object?>{'theme': 'auto'}, deviceDark: true).mode, 'dark');
      expect(Appearance.palette(<String, Object?>{'theme': 'light'}, deviceDark: true).mode, 'light');
      expect(Appearance.palette(null).mode, 'light');
    });
  });
}

void loaderTests() {
  group('Loaders', () {
    test('junk resolves to the default loader, in the default words', () {
      final l = Loaders.resolve('spinner');
      expect(<Object?>[l.kind, l.color, l.px, l.periodMs, l.skeleton], <Object?>['dots', null, 20, 1100, false]);
      expect(l.text.component, 'Loading…');
      expect(l.text.forMoment('thinking'), 'Thinking…');
    });

    test('the dashboard\'s choices are allowlisted and capped', () {
      final l = Loaders.resolve(<String, Object?>{
        'kind': 'RING', 'color': '#abcdef', 'size': 'large', 'speed': 'quick', 'skeleton': true,
        'text': <String, Object?>{'thinking': '  ${'x' * 50}  ', 'component': '', 'bogus': 'y'},
      });
      expect(<Object?>[l.kind, l.color, l.px, l.periodMs, l.skeleton], <Object?>['ring', '#ABCDEF', 28, 700, true]);
      expect(l.text.thinking, 'x' * 40);
      expect(l.text.component, 'Loading…');
      expect(Loaders.resolve(<String, Object?>{'color': 'Accent'}).color, isNull);
    });
  });
}

void barTests() {
  group('Captions', () {
    test('a live turn replaces its own tail; a settled one closes it', () {
      var log = <Caption>[];
      log = Captions.fold(log, const Caption(Role.agent, 'Hi', live: true));
      log = Captions.fold(log, const Caption(Role.agent, 'Hi Asha', live: true));
      expect(log, <Caption>[const Caption(Role.agent, 'Hi Asha', live: true)]);
      log = Captions.fold(log, const Caption(Role.agent, 'Hi Asha, how can I help?'));
      log = Captions.fold(log, const Caption(Role.customer, 'My PAN', live: true));
      expect(log.map((Caption c) => c.text), <String>['Hi Asha, how can I help?', 'My PAN']);
    });

    test('an empty line is a full stop, not a line', () {
      var log = <Caption>[const Caption(Role.agent, 'Let me check', live: true)];
      log = Captions.fold(log, const Caption(Role.agent, ''));
      expect(log, <Caption>[const Caption(Role.agent, 'Let me check')]);
      expect(Captions.fold(log, const Caption(Role.customer, '')), same(log));
    });

    test('the log is capped at twelve turns', () {
      var log = <Caption>[];
      for (var i = 0; i < 20; i++) {
        log = Captions.fold(log, Caption(i.isEven ? Role.agent : Role.customer, 'line $i'));
      }
      expect(log, hasLength(Captions.history));
      expect(log.first.text, 'line 8');
    });
  });

  group('agentBarStatus', () {
    String status({
      GraineConnectivity connectivity = GraineConnectivity.ready,
      bool? online,
      bool reconnecting = false,
      bool connecting = false,
      bool ready = true,
      bool muted = false,
      bool connected = false,
      ConnectionQuality quality = ConnectionQuality.unknown,
      bool agentSpeaking = false,
      bool micDenied = false,
    }) =>
        agentBarStatus(
            connectivity: connectivity, online: online, reconnecting: reconnecting, connecting: connecting,
            ready: ready, muted: muted, connected: connected, quality: quality, agentSpeaking: agentSpeaking,
            micDenied: micDenied);

    test('the network is named before the agent is blamed', () {
      expect(status(connectivity: GraineConnectivity.failed, online: false), "couldn't load · tap to retry");
      expect(status(online: false, connected: true), 'no connection');
      expect(status(reconnecting: true, connected: true), 'reconnecting…');
      expect(status(connectivity: GraineConnectivity.retrying), 'reconnecting…');
      expect(status(ready: false), 'connecting…');
      expect(status(connecting: true), 'connecting…');
      expect(status(micDenied: true), 'needs microphone');
      expect(status(connected: true, muted: true, quality: ConnectionQuality.poor), 'muted');
      expect(status(connected: true, quality: ConnectionQuality.poor, agentSpeaking: true), 'weak connection');
      expect(status(connected: true, agentSpeaking: true), 'speaking');
      expect(status(connected: true, quality: ConnectionQuality.good), 'listening');
      expect(status(), 'tap to talk');
    });
  });
}
