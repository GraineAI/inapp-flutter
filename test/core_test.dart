// The pure core, proven without a device, a WebView or Flutter: every rule
// the Android SDK's CoreTest and WidgetTest pin, ported case for case, plus
// the Dart-side pieces (the action registry, session parsing, captions, the
// voice bar's status words, phase, meter and surfaces, design tokens, the
// design's typefaces, the SDK's icons and the glyph path reader). Imports
// ONLY lib/src/core — no package:flutter.
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
  voiceBarTests();
  designTests();
  fontTests();
  iconTests();
  svgPathTests();
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

/// One scheme's tokens, as a session might send them — only what a test needs.
Map<String, Object?> tokensJson(String scheme, {String accent = '#7C3AED', Map<String, Object?> extra = const <String, Object?>{}}) =>
    <String, Object?>{
      'v': 1,
      'preset': 'graine-classic',
      'scheme': scheme,
      'colors': <String, Object?>{'accent': accent, 'surface': scheme == 'dark' ? '#101010' : '#FAFAFA'},
      ...extra,
    };

void designTests() {
  group('Design tokens', () {
    test('no design, or not one: null — and the SDK draws from appearance as before', () {
      for (final raw in <Object?>[
        null,
        'graine-classic',
        5,
        const <Object?>[],
        const <String, Object?>{},
        const <String, Object?>{'light': 'x', 'dark': 7},
        // Tokens without colours are too little to call a design.
        const <String, Object?>{'light': <String, Object?>{'preset': 'x'}},
      ]) {
        expect(ResolvedDesign.fromJson(raw), isNull, reason: '$raw');
      }
    });

    test('unknown keys, at every level, change nothing', () {
      final plain = ResolvedDesign.fromJson(<String, Object?>{
        'config': <String, Object?>{'preset': 'graine-classic'},
        'light': tokensJson('light'),
        'dark': tokensJson('dark'),
      })!;
      final noisy = ResolvedDesign.fromJson(<String, Object?>{
        'config': <String, Object?>{'preset': 'graine-classic'},
        'future': <String, Object?>{'a': 1},
        'light': tokensJson('light', extra: <String, Object?>{
          'sparkle': true,
          'colors': <String, Object?>{'accent': '#7C3AED', 'surface': '#FAFAFA', 'hologram': '#123456'},
          'shape': <String, Object?>{'launcher': 'circle', 'wobble': 3},
        }),
        'dark': tokensJson('dark', extra: <String, Object?>{'motion': <String, Object?>{'durationMs': 200, 'jitter': 2}}),
      })!;
      expect(noisy.light.toJson(), plain.light.toJson());
      expect(noisy.dark.toJson(), plain.dark.toJson());
    });

    test('a token that is missing or wrong draws as Graine Classic; numbers are clamped', () {
      final t = ThemeTokens.fromJson(<String, Object?>{
        'colors': <String, Object?>{'accent': 'abc', 'text': 'red', 'surface': '#12345'},
        'font': <String, Object?>{'weights': <String, Object?>{'body': 1000, 'title': 'bold'}, 'scale': <String, Object?>{'body': -3}},
        'shape': <String, Object?>{'launcher': 'blob', 'radius': <String, Object?>{'sm': -4, 'lg': 30}, 'borderWidth': '2'},
        'elevation': <String, Object?>{'card': 'soft', 'floating': null},
        'motion': <String, Object?>{'durationMs': -1, 'easing': 'wiggle'},
        'glass': <String, Object?>{'surfaceOpacity': 3},
        'bubbles': 'bubbly',
      }, scheme: 'dark')!;
      expect(t.scheme, 'dark');
      expect(t.colors.accent, '#AABBCC', reason: '#rgb is a colour');
      expect(t.colors.text, '#F5F5F4', reason: "not a colour: the classic dark text");
      expect(t.colors.surface, '#17181B');
      expect(t.font.weights.body, 900);
      expect(t.font.weights.title, 600);
      expect(t.font.scale.body, 1);
      expect(t.shape.launcher, 'circle');
      expect(t.shape.radius.sm, 0);
      expect(t.shape.radius.lg, 30);
      expect(t.shape.borderWidth, 1, reason: 'a string is not a number');
      expect(t.elevation.card, isNull, reason: 'present and not a shadow: none');
      expect(t.elevation.floating, isNull, reason: 'present and null: none');
      expect(t.motion.durationMs, 0);
      expect(t.motion.none, isTrue);
      expect(t.motion.easing, 'standard');
      expect(t.glass!.surfaceOpacity, 1);
      expect(t.glass!.blur, 20);
      expect(t.bubbles, 'filled');
      expect(t.icons.launcher?.id, 'waveform', reason: 'absent: the classic glyph');
    });

    test('one readable set stands in for both', () {
      final d = ResolvedDesign.fromJson(<String, Object?>{'dark': tokensJson('dark'), 'light': 'broken'})!;
      expect(d.light.scheme, 'dark');
      expect(d.pick(deviceDark: false).colors.surface, '#101010');
    });

    test("the brand's scheme, else the device's, else light; a host's scheme wins", () {
      ResolvedDesign design(Object? scheme) => ResolvedDesign.fromJson(<String, Object?>{
            'config': <String, Object?>{'preset': 'graine-classic', if (scheme != null) 'scheme': scheme},
            'light': tokensJson('light'),
            'dark': tokensJson('dark'),
          })!;
      expect(design(null).pick(deviceDark: true).scheme, 'dark');
      expect(design(null).pick(deviceDark: false).scheme, 'light');
      expect(design(null).pick().scheme, 'light');
      expect(design('auto').pick(deviceDark: true).scheme, 'dark');
      expect(design(' Dark ').pick(deviceDark: false).scheme, 'dark');
      expect(design('light').pick(deviceDark: true).scheme, 'light');
      expect(design('sepia').pick(deviceDark: true).scheme, 'dark', reason: 'unknown is auto');
      expect(design('light').pick(deviceDark: false, scheme: 'dark').scheme, 'dark');
      expect(design('light').pick(deviceDark: true, scheme: 'auto').scheme, 'dark');
      expect(design('dark').pick(scheme: 'nonsense').scheme, 'dark');
    });

    test('a design font only when the app bundles it; system is always the platform font', () {
      expect(Design.fontFamily('system', const <String>['system']), isNull);
      expect(Design.fontFamily(null, const <String>['Inter']), isNull);
      expect(Design.fontFamily('Inter', const <String>[]), isNull);
      expect(Design.fontFamily('inter', const <String>[' Inter ']), 'Inter');
      expect(Design.fontFamily('Playfair Display', const <String>['Inter']), isNull);
    });

    test("the launcher's corners by shape, never past half its height", () {
      const r = ThemeRadius(sm: 8, md: 12, lg: 36, xl: 48);
      expect(Design.launcherRadius('circle', r, 56), 28);
      expect(Design.launcherRadius('pill', r, 56), 28);
      expect(Design.launcherRadius('squircle', r, 56), closeTo(16.8, 1e-9));
      expect(Design.launcherRadius('rounded-square', r, 56), 28);
      expect(Design.launcherRadius('rounded-square', const ThemeRadius(sm: 0, md: 0, lg: 18, xl: 0), 56), 18);
      expect(Design.launcherRadius('square', r, 56), 8);
    });

    test('glyph URLs: clamped, quartered, encoded as the React Native SDK builds them', () {
      expect(Design.glyphUrl(null, 'Mic', '#fff', 0, 0),
          'https://www.graine.ai/api/embed/glyph?id=mic&c=FFFFFF&s=96&w=2&v=2');
      expect(Design.glyphUrl('https://x.test//', ' a b ', 'nope', double.nan, 2.6),
          'https://x.test/api/embed/glyph?id=a%20b&c=FFFFFF&s=96&w=2.5&v=2');
      expect(Design.glyphUrl('https://x.test', 'waveform', '101318', 10, 0.1),
          'https://x.test/api/embed/glyph?id=waveform&c=101318&s=16&w=0.5&v=2');
      expect(Design.glyphUrl('https://x.test', 'waveform', '#318ce7', 76.5, 2.63),
          'https://x.test/api/embed/glyph?id=waveform&c=318CE7&s=77&w=2.75&v=2');
    });
  });
}

void svgPathTests() {
  group('SvgPath', () {
    test('the waveform glyph: moves and relative verticals', () {
      expect(SvgPath.parse('M2 10v3M6 6v11M10 3v18M14 8v7M18 5v13M22 10v3'), const <PathCommand>[
        PathMoveTo(2, 10), PathLineTo(2, 13),
        PathMoveTo(6, 6), PathLineTo(6, 17),
        PathMoveTo(10, 3), PathLineTo(10, 21),
        PathMoveTo(14, 8), PathLineTo(14, 15),
        PathMoveTo(18, 5), PathLineTo(18, 18),
        PathMoveTo(22, 10), PathLineTo(22, 13),
      ]);
    });

    test('pairs after a move are lines, relative when the move was', () {
      expect(SvgPath.parse('m1 1 2 2 3 3'), const <PathCommand>[PathMoveTo(1, 1), PathLineTo(3, 3), PathLineTo(6, 6)]);
      expect(SvgPath.parse('M1 1 2 2L3 3 4 4'),
          const <PathCommand>[PathMoveTo(1, 1), PathLineTo(2, 2), PathLineTo(3, 3), PathLineTo(4, 4)]);
    });

    test('H and V, absolute and relative', () {
      expect(SvgPath.parse('M1 2H5h2V9v-1'), const <PathCommand>[
        PathMoveTo(1, 2), PathLineTo(5, 2), PathLineTo(7, 2), PathLineTo(7, 9), PathLineTo(7, 8),
      ]);
    });

    test('S and T reflect the last control point; after anything else they start at the pen', () {
      expect(SvgPath.parse('M0 0C1 1 2 2 3 3S5 5 6 6'),
          const <PathCommand>[PathMoveTo(0, 0), PathCubicTo(1, 1, 2, 2, 3, 3), PathCubicTo(4, 4, 5, 5, 6, 6)]);
      expect(SvgPath.parse('M0 0s1 1 2 2'), const <PathCommand>[PathMoveTo(0, 0), PathCubicTo(0, 0, 1, 1, 2, 2)]);
      expect(SvgPath.parse('M0 0Q1 1 2 0T4 0t2 0'), const <PathCommand>[
        PathMoveTo(0, 0), PathQuadTo(1, 1, 2, 0), PathQuadTo(3, -1, 4, 0), PathQuadTo(5, 1, 6, 0),
      ]);
      expect(SvgPath.parse('M0 0L1 1T3 3'), const <PathCommand>[PathMoveTo(0, 0), PathLineTo(1, 1), PathQuadTo(1, 1, 3, 3)]);
    });

    test('arcs, flags packed or not, relative end points', () {
      expect(SvgPath.parse('M0 0a1 1 0 011 1'),
          const <PathCommand>[PathMoveTo(0, 0), PathArcTo(1, 1, 0, false, true, 1, 1)]);
      expect(SvgPath.parse('M12 .5a.5.5 0 0 1 0-.96A9 9 0 1 0 4 16.1'), const <PathCommand>[
        PathMoveTo(12, 0.5),
        PathArcTo(0.5, 0.5, 0, false, true, 12, -0.45999999999999996),
        PathArcTo(9, 9, 0, true, false, 4, 16.1),
      ]);
    });

    test('numbers as minifiers pack them; Z returns the pen to where the subpath began', () {
      expect(SvgPath.parse('M.5.5l0-.96'), const <PathCommand>[PathMoveTo(.5, .5), PathLineTo(.5, -0.45999999999999996)]);
      expect(SvgPath.parse('M1e1,2E-1'), const <PathCommand>[PathMoveTo(10, 0.2)]);
      expect(SvgPath.parse('M1 1l1 0zl1 1'),
          const <PathCommand>[PathMoveTo(1, 1), PathLineTo(2, 1), PathClose(), PathLineTo(2, 2)]);
    });

    test('every launcher glyph the design system ships reads', () {
      // theme.ts LAUNCHER_ICONS, verbatim: (id, stroke, path).
      const glyphs = <(String, bool, String)>[
        ('waveform', true, 'M2 13a2 2 0 0 0 2 -2V7a2 2 0 0 1 4 0v13a2 2 0 0 0 4 0V4a2 2 0 0 1 4 0v13a2 2 0 0 0 4 0v-4a2 2 0 0 1 2 -2'),
        ('audio-lines', true, 'M2 10v3M6 6v11M10 3v18M14 8v7M18 5v13M22 10v3'),
        ('sparkles', true, 'M11.017 2.814a1 1 0 0 1 1.966 0l1.051 5.558a2 2 0 0 0 1.594 1.594l5.558 1.051a1 1 0 0 1 0 1.966l-5.558 1.051a2 2 0 0 0 -1.594 1.594l-1.051 5.558a1 1 0 0 1 -1.966 0l-1.051 -5.558a2 2 0 0 0 -1.594 -1.594l-5.558 -1.051a1 1 0 0 1 0 -1.966l5.558 -1.051a2 2 0 0 0 1.594 -1.594zM20 2v4M22 4h-4M2 20a2 2 0 1 0 4 0a2 2 0 1 0 -4 0z'),
        ('microphone', true, 'M12 19v3M19 10v2a7 7 0 0 1 -14 0v-2M12 2h0a3 3 0 0 1 3 3v7a3 3 0 0 1 -3 3h0a3 3 0 0 1 -3 -3v-7a3 3 0 0 1 3 -3z'),
        ('message-circle', true, 'M2.992 16.342a2 2 0 0 1 0.094 1.167l-1.065 3.29a1 1 0 0 0 1.236 1.168l3.413 -0.998a2 2 0 0 1 1.099 0.092a10 10 0 1 0 -4.777 -4.719'),
        ('headset', true, 'M3 11h3a2 2 0 0 1 2 2v3a2 2 0 0 1 -2 2H5a2 2 0 0 1 -2 -2v-5Zm0 0a9 9 0 1 1 18 0m0 0v5a2 2 0 0 1 -2 2h-1a2 2 0 0 1 -2 -2v-3a2 2 0 0 1 2 -2h3ZM21 16v2a4 4 0 0 1 -4 4h-5'),
        ('bot', true, 'M12 8V4H8M6 8h12a2 2 0 0 1 2 2v8a2 2 0 0 1 -2 2h-12a2 2 0 0 1 -2 -2v-8a2 2 0 0 1 2 -2zM2 14h2M20 14h2M15 13v2M9 13v2'),
        ('phone', true, 'M13.832 16.568a1 1 0 0 0 1.213 -0.303l0.355 -0.465A2 2 0 0 1 17 15h3a2 2 0 0 1 2 2v3a2 2 0 0 1 -2 2A18 18 0 0 1 2 4a2 2 0 0 1 2 -2h3a2 2 0 0 1 2 2v3a2 2 0 0 1 -0.8 1.6l-0.468 0.351a1 1 0 0 0 -0.292 1.233a14 14 0 0 0 6.392 6.384'),
        ('zap', true, 'M15.914 4a1.5 1.5 0 0 0 -2.474 -1.561l-9 9A1.5 1.5 0 0 0 5.5 14h4.002a0.5 0.5 0 0 1 0.471 0.666L8.086 20a1.5 1.5 0 0 0 2.475 1.56l9 -9A1.5 1.5 0 0 0 18.5 10h-3.997a0.5 0.5 0 0 1 -0.472 -0.667z'),
        ('star', true, 'M11.525 2.295a0.53 0.53 0 0 1 0.95 0l2.31 4.679a2.123 2.123 0 0 0 1.595 1.16l5.166 0.756a0.53 0.53 0 0 1 0.294 0.904l-3.736 3.638a2.123 2.123 0 0 0 -0.611 1.878l0.882 5.14a0.53 0.53 0 0 1 -0.771 0.56l-4.618 -2.428a2.122 2.122 0 0 0 -1.973 0L6.396 21.01a0.53 0.53 0 0 1 -0.77 -0.56l0.881 -5.139a2.122 2.122 0 0 0 -0.611 -1.879L2.16 9.795a0.53 0.53 0 0 1 0.294 -0.906l5.165 -0.755a2.122 2.122 0 0 0 1.597 -1.16z'),
        ('orbit', true, 'M20.341 6.484A10 10 0 0 1 10.266 21.85M3.659 17.516A10 10 0 0 1 13.74 2.152M9 12a3 3 0 1 0 6 0a3 3 0 1 0 -6 0zM17 5a2 2 0 1 0 4 0a2 2 0 1 0 -4 0zM3 19a2 2 0 1 0 4 0a2 2 0 1 0 -4 0z'),
        ('sparkle-filled', false, 'M19.5 13.5a1.479 1.479 0 0 1 -0.977 1.401L13.688 16.688l-1.781 4.839a1.492 1.492 0 0 1 -2.801 0L7.312 16.688l-4.839 -1.781a1.492 1.492 0 0 1 0 -2.801L7.312 10.312l1.781 -4.839a1.492 1.492 0 0 1 2.801 0L13.688 10.312l4.839 1.781A1.479 1.479 0 0 1 19.5 13.5ZM14.25 4.5h1.5V6a0.75 0.75 0 0 0 1.5 0V4.5h1.5a0.75 0.75 0 0 0 0 -1.5H17.25V1.5a0.75 0.75 0 0 0 -1.5 0V3H14.25a0.75 0.75 0 0 0 0 1.5Zm8.25 3h-0.75V6.75a0.75 0.75 0 0 0 -1.5 0v0.75h-0.75a0.75 0.75 0 0 0 0 1.5h0.75v0.75a0.75 0.75 0 0 0 1.5 0V9h0.75a0.75 0.75 0 0 0 0 -1.5Z'),
        ('chat-dots-filled', false, 'M12 2.25A9.75 9.75 0 0 0 3.392 16.582L2.328 19.775a1.5 1.5 0 0 0 1.897 1.897l3.192 -1.064A9.75 9.75 0 1 0 12 2.25ZM7.875 13.125a1.125 1.125 0 1 1 1.125 -1.125A1.125 1.125 0 0 1 7.875 13.125Zm4.125 0a1.125 1.125 0 1 1 1.125 -1.125A1.125 1.125 0 0 1 12 13.125Zm4.125 0a1.125 1.125 0 1 1 1.125 -1.125A1.125 1.125 0 0 1 16.125 13.125Z'),
        ('graphic-eq', false, 'M7 17v-10q0 -0.425 0.288 -0.713T8 6q0.425 0 0.713 0.288T9 7v10q0 0.425 -0.288 0.713T8 18q-0.425 0 -0.713 -0.288T7 17Zm4 4v-18q0 -0.425 0.288 -0.713T12 2q0.425 0 0.713 0.288T13 3v18q0 0.425 -0.288 0.713T12 22q-0.425 0 -0.713 -0.288T11 21ZM3 13v-2q0 -0.425 0.288 -0.713T4 10q0.425 0 0.713 0.288T5 11v2q0 0.425 -0.288 0.713T4 14q-0.425 0 -0.713 -0.288T3 13Zm12 4v-10q0 -0.425 0.288 -0.713T16 6q0.425 0 0.713 0.288T17 7v10q0 0.425 -0.288 0.713T16 18q-0.425 0 -0.713 -0.288T15 17Zm4 -4v-2q0 -0.425 0.288 -0.713T20 10q0.425 0 0.713 0.288T21 11v2q0 0.425 -0.288 0.713T20 14q-0.425 0 -0.713 -0.288T19 13Z'),
      ];
      expect(glyphs, hasLength(14));
      for (final (id, _, d) in glyphs) {
        final commands = SvgPath.parse(d);
        expect(commands, isNotNull, reason: id);
        expect(commands, isNotEmpty, reason: id);
        expect(commands!.first, isA<PathMoveTo>(), reason: id);
      }
    });

    test('a close then a relative move starts from where the subpath began', () {
      // headset: "…v-5Zm0 0a9 9 0 1 1 18 0m0 0v5…"
      expect(SvgPath.parse('M3 11h3v2h-3Zm0 0a9 9 0 1 1 18 0m0 0v5'), const <PathCommand>[
        PathMoveTo(3, 11), PathLineTo(6, 11), PathLineTo(6, 13), PathLineTo(3, 13), PathClose(),
        PathMoveTo(3, 11), PathArcTo(9, 9, 0, true, true, 21, 11), PathMoveTo(21, 11), PathLineTo(21, 16),
      ]);
    });

    test('anything malformed is null, never a throw; empty is an empty path', () {
      for (final bad in <String>['L1 1', 'M1', 'M1 1 X', 'M0 0a1 1 0 2 1 1 1', 'M0 0C1 2 3', 'M--1 0', 'M1 1e']) {
        expect(SvgPath.parse(bad), isNull, reason: bad);
      }
      expect(SvgPath.parse(''), isEmpty);
      expect(SvgPath.parse('   '), isEmpty);
    });
  });
}

void voiceBarTests() {
  group('voiceBarStatus', () {
    BarStatus status({
      bool error = false,
      bool inChat = false,
      bool chatOnline = false,
      bool? online,
      bool reconnecting = false,
      GraineConnectivity connectivity = GraineConnectivity.ready,
      bool micDenied = false,
      bool ready = true,
      bool connecting = false,
      bool muted = false,
      bool connected = false,
      bool thinking = false,
      bool speaking = false,
      ConnectionQuality quality = ConnectionQuality.unknown,
    }) =>
        voiceBarStatus(
          error: error,
          inChat: inChat,
          chatOnline: chatOnline,
          online: online,
          reconnecting: reconnecting,
          connectivity: connectivity,
          micDenied: micDenied,
          ready: ready,
          connecting: connecting,
          muted: muted,
          connected: connected,
          thinking: thinking,
          speaking: speaking,
          quality: quality,
        );

    test('each rung, in sentence case, beats every rung below it — the contract order', () {
      // Everything that could be true at once, peeled away one rung at a time:
      // each line proves its words win over all the ones after it.
      var s = status(
          error: true, online: false, reconnecting: true, micDenied: true, connectivity: GraineConnectivity.failed,
          ready: false, connecting: true, muted: true, connected: true, thinking: true, speaking: true,
          quality: ConnectionQuality.poor);
      expect(s, const BarStatus('Unavailable'));
      s = status(
          online: false, reconnecting: true, micDenied: true, connectivity: GraineConnectivity.failed, ready: false,
          connecting: true, muted: true, connected: true, thinking: true, speaking: true, quality: ConnectionQuality.poor);
      expect(s, const BarStatus('No connection'));
      s = status(
          reconnecting: true, micDenied: true, connectivity: GraineConnectivity.failed, ready: false, connecting: true,
          muted: true, connected: true, thinking: true, speaking: true, quality: ConnectionQuality.poor);
      expect(s, const BarStatus('Reconnecting…', waiting: 'reconnecting'));
      s = status(
          micDenied: true, connectivity: GraineConnectivity.failed, ready: false, connecting: true, muted: true,
          connected: true, thinking: true, speaking: true, quality: ConnectionQuality.poor);
      expect(s, const BarStatus('Needs microphone'));
      s = status(
          connectivity: GraineConnectivity.failed, ready: false, connecting: true, muted: true, connected: true,
          thinking: true, speaking: true, quality: ConnectionQuality.poor);
      expect(s, const BarStatus('Couldn’t load · tap to retry'), reason: 'a curly apostrophe, as React Native says it');
      s = status(
          ready: false, connecting: true, muted: true, connected: true, thinking: true, speaking: true,
          quality: ConnectionQuality.poor);
      expect(s, const BarStatus('Connecting…', waiting: 'connecting'));
      s = status(muted: true, connected: true, thinking: true, speaking: true, quality: ConnectionQuality.poor);
      expect(s, const BarStatus('Muted'));
      s = status(connected: true, thinking: true, speaking: true, quality: ConnectionQuality.poor);
      expect(s, const BarStatus('Thinking…', waiting: 'thinking'));
      s = status(connected: true, speaking: true, quality: ConnectionQuality.poor);
      expect(s, const BarStatus('Speaking', meter: true));
      s = status(connected: true, quality: ConnectionQuality.poor);
      expect(s, const BarStatus('Weak connection'));
      expect(status(connected: true, quality: ConnectionQuality.good), const BarStatus('Listening', meter: true));
      expect(status(), const BarStatus('Tap to talk'));
    });

    test('a retrying page reconnects; placing a call, or a page not ready, connects', () {
      expect(status(connectivity: GraineConnectivity.retrying), const BarStatus('Reconnecting…', waiting: 'reconnecting'));
      expect(status(ready: false), const BarStatus('Connecting…', waiting: 'connecting'));
      expect(status(connecting: true), const BarStatus('Connecting…', waiting: 'connecting'));
    });

    test('in the chat, none of the call\'s words are true: "Online", or connecting', () {
      expect(status(inChat: true, chatOnline: true, online: false, connected: true, muted: true), const BarStatus('Online'));
      expect(status(inChat: true, reconnecting: true), const BarStatus('Connecting…', waiting: 'connecting'));
      expect(status(inChat: true, error: true), const BarStatus('Unavailable'), reason: 'a broken agent is broken everywhere');
    });

    test('thinking, speaking and listening are only ever said on a call', () {
      expect(status(thinking: true), const BarStatus('Tap to talk'));
      expect(status(speaking: true), const BarStatus('Tap to talk'));
      expect(status(quality: ConnectionQuality.poor), const BarStatus('Tap to talk'));
    });
  });

  group('callPhase', () {
    CallPhase phase({
      bool reconnecting = false,
      GraineConnectivity connectivity = GraineConnectivity.ready,
      bool connecting = false,
      bool ready = true,
      bool connected = true,
      Caption? caption,
      bool agentSpeaking = false,
    }) =>
        callPhase(
          reconnecting: reconnecting,
          connectivity: connectivity,
          connecting: connecting,
          ready: ready,
          connected: connected,
          caption: caption,
          agentSpeaking: agentSpeaking,
        );

    test("thinking is the gap between the customer's final line and the agent's first", () {
      expect(phase(), CallPhase.listening);
      expect(phase(caption: const Caption(Role.customer, 'My PAN is', live: true)), CallPhase.listening,
          reason: 'still talking');
      expect(phase(caption: const Caption(Role.customer, 'My PAN is ABCDE1234F')), CallPhase.thinking);
      expect(phase(caption: const Caption(Role.agent, 'Got it', live: true)), CallPhase.speaking);
      expect(phase(caption: const Caption(Role.agent, 'Got it, thanks.')), CallPhase.listening);
      expect(phase(caption: const Caption(Role.customer, 'Hi'), agentSpeaking: true), CallPhase.speaking);
    });

    test('the transcript folded the React Native way says thinking exactly while the agent owes an answer', () {
      var log = const <Caption>[];
      CallPhase now() => phase(caption: log.isEmpty ? null : log.last);
      log = Captions.fold(log, const Caption(Role.customer, 'Show me', live: true));
      expect(now(), CallPhase.listening);
      log = Captions.fold(log, const Caption(Role.customer, '')); // the customer's full stop
      expect(now(), CallPhase.thinking);
      log = Captions.fold(log, const Caption(Role.agent, 'Here', live: true));
      expect(now(), CallPhase.speaking);
      log = Captions.fold(log, const Caption(Role.agent, 'Here they are.'));
      expect(now(), CallPhase.listening);
    });

    test('off a call, coming up, or coming back: idle, connecting, reconnecting', () {
      expect(phase(connected: false), CallPhase.idle);
      expect(phase(connecting: true), CallPhase.connecting);
      expect(phase(ready: false, connected: false), CallPhase.connecting);
      expect(phase(reconnecting: true), CallPhase.reconnecting);
      expect(phase(connectivity: GraineConnectivity.failed, connected: false), CallPhase.reconnecting);
      expect(phase(connectivity: GraineConnectivity.retrying), CallPhase.reconnecting);
    });
  });

  group('VoiceMeter', () {
    test("four bars, 2.5 wide and 2 apart, at 55/100/70/40% of 12", () {
      expect(VoiceMeter.heights, <double>[0.55, 1, 0.7, 0.4]);
      expect(VoiceMeter.height, 12);
      expect(VoiceMeter.barWidth, 2.5);
      expect(VoiceMeter.gap, 2);
      expect(VoiceMeter.low, 0.35);
      expect(VoiceMeter.staggerMs, 90);
    });

    test('each leg is max(420, durationMs × 3.2) ms', () {
      expect(VoiceMeter.legMs(0), 420);
      expect(VoiceMeter.legMs(120), 420);
      expect(VoiceMeter.legMs(150), closeTo(480, 1e-9));
      expect(VoiceMeter.legMs(200), closeTo(640, 1e-9));
      expect(VoiceMeter.legMs(500), closeTo(1600, 1e-9));
      expect(VoiceMeter.legMs(201), closeTo(643.2, 1e-9), reason: 'not rounded');
    });

    test('bar i waits i × 90 ms at 35%, rises for one leg, falls for the next, forever', () {
      const d = 200; // a 640 ms leg
      final leg = VoiceMeter.legMs(d);
      for (var i = 0; i < 4; i++) {
        final start = i * 90.0;
        if (i > 0) expect(VoiceMeter.scale(i, start - 1, d), VoiceMeter.low, reason: 'bar $i before its turn');
        expect(VoiceMeter.scale(i, start, d), VoiceMeter.low, reason: 'bar $i at its start');
        expect(VoiceMeter.scale(i, start + leg / 2, d), closeTo((VoiceMeter.low + 1) / 2, 1e-9), reason: 'bar $i halfway up');
        expect(VoiceMeter.scale(i, start + leg - 0.001, d), closeTo(1, 1e-5), reason: 'bar $i at full height');
        expect(VoiceMeter.scale(i, start + leg * 1.5, d), closeTo((VoiceMeter.low + 1) / 2, 1e-9), reason: 'bar $i halfway down');
        expect(VoiceMeter.scale(i, start + leg * 2 + 1e-6, d), closeTo(VoiceMeter.low, 1e-6), reason: 'bar $i back at the bottom');
        expect(VoiceMeter.scale(i, start + leg * 20.5, d), closeTo((VoiceMeter.low + 1) / 2, 1e-6), reason: 'forever');
      }
      // The easing shapes a leg without moving its ends.
      double easeIn(double t) => t * t;
      expect(VoiceMeter.scale(0, leg / 2, d, easeIn), closeTo(VoiceMeter.low + (1 - VoiceMeter.low) * 0.25, 1e-9));
    });

    test('still at full height when the design has no motion', () {
      expect(VoiceMeter.still(0), isTrue);
      expect(VoiceMeter.still(150), isFalse);
      for (var i = 0; i < 4; i++) {
        for (final t in <double>[0, 100, 5000]) {
          expect(VoiceMeter.scale(i, t, 0), 1);
        }
      }
    });
  });

  group('Surfaces', () {
    test("the dashboard's mode decides which exist, its start which opens, a preference wins when allowed", () {
      var p = Surfaces.resolve(null);
      expect(p.allowed, <AgentSurface>[AgentSurface.voice, AgentSurface.chat]);
      expect(p.start, AgentSurface.voice);
      expect(p.canSwitch, isTrue);

      p = Surfaces.resolve(const <String, Object?>{'mode': 'Voice'});
      expect(p.allowed, <AgentSurface>[AgentSurface.voice]);
      expect(p.canSwitch, isFalse);

      p = Surfaces.resolve(const <String, Object?>{'mode': 'chat'}, AgentSurface.voice);
      expect(p.start, AgentSurface.chat, reason: 'a surface the brand turned off is not opened');
      expect(p.canSwitch, isFalse);

      expect(Surfaces.resolve(const <String, Object?>{'start': 'chat'}).start, AgentSurface.chat);
      expect(Surfaces.resolve(const <String, Object?>{'start': 'chat'}, AgentSurface.voice).start, AgentSurface.voice);
      expect(Surfaces.resolve(const <String, Object?>{'mode': 'both', 'start': 'fax'}).start, AgentSurface.voice);
      expect(Surfaces.resolve(const <String, Object?>{'mode': 7}).allowed, hasLength(2), reason: 'junk is both');
    });
  });
}

void fontTests() {
  group('DesignFonts', () {
    test('the nearest weight a family has; on a tie, the heavier', () {
      expect(DesignFonts.nearestWeight(const <int>[400, 600], 500), 600);
      expect(DesignFonts.nearestWeight(const <int>[300, 400, 500, 600, 700], 800), 700);
      expect(DesignFonts.nearestWeight(const <int>[200, 300, 400, 600, 700, 800, 900], 500), 600, reason: 'Martel has no 500');
      expect(DesignFonts.nearestWeight(const <int>[400], 900), 400);
      expect(DesignFonts.nearestWeight(const <int>[], 400), isNull);
    });

    test('a face: the curated spelling, the nearest weight, its name and its URL', () {
      final f = DesignFonts.faceFor('ibm plex sans', 650, origin: 'https://example.test//')!;
      expect(f.family, 'IBM Plex Sans');
      expect(f.weight, 700);
      expect(f.name, 'Graine-IBMPlexSans-700');
      expect(f.url, 'https://example.test/api/embed/font?f=IBM%20Plex%20Sans&w=700&v=${DesignFonts.assetVersion}');
      expect(f.key, 'IBM Plex Sans|700');
      expect(DesignFonts.faceFor('Baloo 2', 300)!.url, '$base/api/embed/font?f=Baloo%202&w=400&v=1',
          reason: 'the default origin; Baloo 2 starts at 400');
    });

    test('"system", nothing, and a family this build has no files for are never fetched', () {
      for (final family in <String?>['system', 'System', ' ', '', null, 'Comic Sans MS']) {
        expect(DesignFonts.faceFor(family, 400), isNull, reason: '$family');
      }
    });

    test('a token set draws with the body at body and strong, the heading at title and strong — each once', () {
      final t = ThemeTokens.fromJson(tokensJson('light', extra: <String, Object?>{
        'font': <String, Object?>{
          'body': 'Nunito',
          'heading': 'Baloo 2',
          'weights': <String, Object?>{'body': 400, 'strong': 700, 'title': 700},
        },
      }))!;
      expect(DesignFonts.facesFor(t).map((DesignFontFace f) => f.name), <String>[
        'Graine-Nunito-400',
        'Graine-Nunito-700',
        'Graine-Baloo2-700',
      ]);
    });
  });
}

void iconTests() {
  group('SdkIcons', () {
    test('the eight icons, each a body a fill can sit in and lines that are only stroked', () {
      expect(SdkIcons.all.keys, <String>['mic', 'micOff', 'end', 'send', 'chat', 'call', 'chevron', 'close']);
      for (final e in SdkIcons.all.entries) {
        final icon = e.value;
        expect(icon.body != null || icon.lines != null, isTrue, reason: e.key);
        for (final d in <String?>[icon.body, icon.lines]) {
          if (d == null) continue;
          expect(SvgPath.parse(d), isNotEmpty, reason: '${e.key}: $d');
        }
      }
    });

    test('outline, sharp, filled and duotone stroke and fill as the contract says', () {
      expect(SdkIcons.treatment('outline', 2),
          const IconTreatment(fillBody: false, bodyFillOpacity: 0, bodyStroke: 2, lineStroke: 2, square: false));
      expect(SdkIcons.treatment('sharp', 1.5),
          const IconTreatment(fillBody: false, bodyFillOpacity: 0, bodyStroke: 1.5, lineStroke: 1.5, square: true));
      expect(SdkIcons.treatment('filled', 2),
          const IconTreatment(fillBody: true, bodyFillOpacity: 1, bodyStroke: 1.5, lineStroke: 2, square: false));
      expect(SdkIcons.treatment('filled', 1.25).bodyStroke, 1, reason: '0.75 × the stroke, at least 1');
      expect(SdkIcons.treatment('duotone', 1.5),
          const IconTreatment(fillBody: true, bodyFillOpacity: 0.28, bodyStroke: 1.5, lineStroke: 1.5, square: false));
      expect(SdkIcons.treatment('embossed', 2), SdkIcons.treatment('outline', 2), reason: 'an unknown style is outline');
    });
  });
}
