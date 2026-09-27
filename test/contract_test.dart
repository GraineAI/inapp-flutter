// THE SHARED CONTRACT, generated from the React Native SDK.
//
// sdk/contract/fixtures.json is produced by sdk/contract/generate.mjs, which
// runs the RN SDK's own built code: what gets masked, what "weak connection"
// means, what the engine page's URL is. Every answer must be reproduced here
// exactly. sdk/contract/rn-parity.json (generate-rn-parity.mjs: the RN SDK's
// answers for the component, loader, placement, appearance and friction
// rules) is held to the same standard, every section of it. So is
// sdk/contract/design.json (generate-design.mjs: real sessions' `design`
// objects, which set of tokens each picks, and the glyph image URLs).
//
// A missing file FAILS. A skipped contract is a silent pass, and a silent
// pass is how two SDKs drift apart. Imports ONLY lib/src/core.
import 'dart:convert';
import 'dart:io';

import 'package:graine_inapp/src/core/core.dart';
import 'package:test/test.dart';

import 'contract_files.dart';

/// JSON and Dart values in one comparable shape: every number a double.
Object? canon(Object? v) {
  if (v is num) return v.toDouble();
  if (v is Map) return <String, Object?>{for (final e in v.entries) e.key.toString(): canon(e.value)};
  if (v is List) return <Object?>[for (final x in v) canon(x)];
  return v;
}

List<Map<String, Object?>> cases(Map<String, Object?> fx, String name) =>
    <Map<String, Object?>>[for (final c in fx[name]! as List<Object?>) c! as Map<String, Object?>];

double? n(Object? v) => v is num ? v.toDouble() : null;

void main() {
  group('sdk/contract/fixtures.json', () {
    late Map<String, Object?> fx;

    setUpAll(() async {
      fx = jsonDecode((await requireFile('contract/fixtures.json')).readAsStringSync()) as Map<String, Object?>;
    });

    test('masks exactly what the React Native SDK masks', () {
      final all = cases(fx, 'mask');
      expect(all, isNotEmpty);
      for (final c in all) {
        expect(Masking.mask(c['input']! as String), c['output'], reason: 'input: ${c['input']}');
      }
    });

    test('means the same by "weak connection"', () {
      final all = cases(fx, 'quality');
      expect(all, isNotEmpty);
      for (final c in all) {
        final s = c['sample']! as Map<String, Object?>;
        final got = ConnectionQuality.classify(n(s['rtt']), n(s['jitter']), n(s['loss']));
        expect(got.name, c['quality'], reason: 'sample: $s');
      }
    });

    test('builds the same engine URL', () {
      final all = cases(fx, 'engineUrl');
      expect(all, isNotEmpty);
      for (final c in all) {
        final i = c['input']! as Map<String, Object?>;
        final got = Protocol.engineUrl(
          baseUrl: i['baseUrl']! as String,
          voiceAgentId: i['voiceAgentId']! as String,
          transport: Transport.from(i['transport'] as String?),
          cacheKey: i['cacheKey']! as String,
          idle: i['idle']! as bool,
          publishableKey: i['publishableKey']! as String,
          accent: i['accent'] as String?,
        );
        expect(got, c['url']);
      }
    });
  });

  group('sdk/contract/rn-parity.json', () {
    late Map<String, Object?> fx;

    setUpAll(() async {
      fx = jsonDecode((await requireFile('contract/rn-parity.json')).readAsStringSync()) as Map<String, Object?>;
    });

    void parity(String name, void Function(Map<String, Object?> fx) body) {
      test(name, () => body(fx));
    }

    test('every section is covered, and none is empty', () {
      const covered = <String>{
        'widgetStyle', 'widgetLook', 'widgetSurface', 'platform', 'grammar', 'selectAction', 'selectCall',
        'template', 'manySummary', 'widgetImages', 'loaderStyle', 'clampOffset', 'offsetDuringDrag', 'isTap',
        'liftFor', 'appearance', 'palette', 'frictionIdle',
      };
      final sections = fx.keys.where((String k) => !k.startsWith(r'$')).toSet();
      expect(sections.difference(covered), isEmpty, reason: 'a section this suite does not check');
      for (final k in covered) {
        final v = fx[k];
        expect(v is List ? v.isNotEmpty : (v is Map && v.isNotEmpty), isTrue, reason: '$k is missing or empty');
      }
    });

    parity('normalises a widget style exactly as React Native does', (Map<String, Object?> fx) {
      for (final c in cases(fx, 'widgetStyle')) {
        expect(canon(Widgets.normaliseStyle(c['input']).toMap()), canon(c['output']), reason: 'input ${c['input']}');
      }
    });

    parity('resolves the same look', (Map<String, Object?> fx) {
      for (final c in cases(fx, 'widgetLook')) {
        final look = Widgets.resolveLook(Widgets.normaliseStyle(c['style']), c['kind'] as String?);
        expect(canon(look.toMap()), canon(c['output']), reason: 'style ${c['style']} kind ${c['kind']}');
      }
    });

    parity('puts each kind on the same surface', (Map<String, Object?> fx) {
      for (final c in cases(fx, 'widgetSurface')) {
        expect(Widgets.surface(c['kind'] as String?), c['output'], reason: 'kind ${c['kind']}');
      }
    });

    parity('follows the phone\'s grammar the same way', (Map<String, Object?> fx) {
      for (final c in cases(fx, 'platform')) {
        expect(Widgets.resolvePlatform(c['platform'] as String?, c['os'] as String?, c['manufacturer'] as String?),
            c['output'], reason: '$c');
      }
      final g = fx['grammar']! as Map<String, Object?>;
      for (final name in <String>['ios', 'material', 'oneui']) {
        final got = Widgets.grammar[name]!;
        final mine = <String, Object?>{
          'radius': got.radius, 'chipRadius': got.chipRadius, 'buttonRadius': got.buttonRadius,
          'pillButtons': got.pillButtons, 'separatorInset': got.separatorInset,
          'grabber': <String, Object?>{'width': got.grabberWidth, 'height': got.grabberHeight},
          'titleWeight': got.titleWeight.toString(), 'padBoost': got.padBoost, 'chipOutlined': got.chipOutlined,
        };
        expect(canon(mine), canon(g[name]), reason: name);
      }
    });

    parity('allowlists a tap\'s action the same way (key order included)', (Map<String, Object?> fx) {
      for (final c in cases(fx, 'selectAction')) {
        expect(canon(Widgets.normaliseSelectAction(c['input']).toMap()), canon(c['output']), reason: 'input ${c['input']}');
      }
    });

    parity('runs the same action for a tap, and fills the same templates', (Map<String, Object?> fx) {
      for (final c in cases(fx, 'selectCall')) {
        final call = Widgets.selectCall(
            Widgets.normaliseSelectAction(c['onSelect']), c['item']! as Map<String, Object?>);
        final want = c['output'];
        if (want == null) {
          expect(call, isNull, reason: '$c');
          continue;
        }
        expect(canon(<String, Object?>{'name': call!.name, 'args': call.args}), canon(want), reason: '$c');
      }
      for (final c in cases(fx, 'template')) {
        expect(Widgets.fillSelectTemplate(c['template']! as String, c['item']! as Map<String, Object?>), c['output'],
            reason: '$c');
      }
    });

    parity('names several choices in the same sentence', (Map<String, Object?> fx) {
      for (final c in cases(fx, 'manySummary')) {
        final titles = <String>[for (final t in c['titles']! as List<Object?>) t! as String];
        expect(Widgets.manySummary(titles, c['verb']! as String), c['output']);
      }
    });

    parity('resolves the same pictures', (Map<String, Object?> fx) {
      for (final c in cases(fx, 'widgetImages')) {
        final got = Widgets.resolveImages(c['data']! as Map<String, Object?>, c['baseUrl']! as String);
        expect(canon(got), canon(c['output']), reason: '$c');
      }
    });

    parity('resolves the same loader', (Map<String, Object?> fx) {
      for (final c in cases(fx, 'loaderStyle')) {
        expect(canon(Loaders.normalise(c['input']).toMap()), canon(c['normalised']), reason: 'normalise ${c['input']}');
        final r = Loaders.resolve(c['input']);
        final resolved = <String, Object?>{
          'kind': r.kind, 'color': r.color, 'px': r.px, 'periodMs': r.periodMs, 'skeleton': r.skeleton,
          'text': <String, Object?>{
            'connecting': r.text.connecting, 'reconnecting': r.text.reconnecting,
            'thinking': r.text.thinking, 'component': r.text.component,
          },
        };
        expect(canon(resolved), canon(c['resolved']), reason: 'resolve ${c['input']}');
      }
    });

    PlacementBounds bounds(Map<String, Object?> o) => PlacementBounds(
          windowHeight: n(o['windowHeight'])!,
          baseBottom: n(o['baseBottom'])!,
          barHeight: n(o['barHeight'])!,
          topMargin: n(o['topMargin']) ?? 48,
        );

    parity('places the bar with the same arithmetic', (Map<String, Object?> fx) {
      for (final c in cases(fx, 'clampOffset')) {
        expect(Placement.clampOffset(n(c['offset'])!, bounds(c['bounds']! as Map<String, Object?>)), c['output'],
            reason: '$c');
      }
      for (final c in cases(fx, 'offsetDuringDrag')) {
        expect(Placement.offsetDuringDrag(n(c['start'])!, n(c['dy'])!, bounds(c['bounds']! as Map<String, Object?>)),
            c['output'], reason: '$c');
      }
      for (final c in cases(fx, 'isTap')) {
        expect(Placement.isTap(n(c['dx'])!, n(c['dy'])!), c['output'], reason: '$c');
      }
      for (final c in cases(fx, 'liftFor')) {
        expect(KeyboardLift.liftFor(n(c['keyboard'])!, n(c['shrink'])!), c['output'], reason: '$c');
      }
    });

    parity('translates the dashboard\'s appearance the same way', (Map<String, Object?> fx) {
      for (final c in cases(fx, 'appearance')) {
        final f = c['fallback']! as Map<String, Object?>;
        final a = Appearance.resolve(
          c['appearance'] is Map ? c['appearance']! as Map<String, Object?> : null,
          accent: f['accent']! as String,
          heading: f['heading']! as String,
          radius: n(f['radius']),
          maxRadius: n(f['maxRadius']),
          origin: f['origin'] as String?,
        );
        expect(canon(<String, Object?>{'accent': a.accent, 'heading': a.heading, 'logoUrl': a.logoUrl, 'radius': a.radius}),
            canon(c['output']), reason: '$c');
      }
      for (final c in cases(fx, 'palette')) {
        final p = Appearance.palette(
          c['appearance'] is Map ? c['appearance']! as Map<String, Object?> : null,
          deviceDark: c['scheme'] == 'dark',
          accent: c['accent'] as String?,
        );
        expect(<String, Object?>{
          'surface': p.surface, 'border': p.border, 'text': p.text, 'muted': p.muted,
          'onAccent': p.onAccent, 'mode': p.mode,
        }, c['output'], reason: '$c');
      }
    });

    GraineScreen? screenOf(Object? o) {
      if (o is! Map) return null;
      final m = o as Map<String, Object?>;
      final fields = <GraineField>[
        for (final raw in (m['fields'] as List<Object?>?) ?? const <Object?>[])
          () {
            final f = raw! as Map<String, Object?>;
            return GraineField(
              f['name']! as String,
              label: f['label'] as String?,
              value: f['value'] as String?,
              status: FieldStatus.fromWire(f['status'] as String?),
              error: f['error'] as String?,
              optional: f['optional'] == true,
            );
          }(),
      ];
      return GraineScreen(m['screen']! as String, title: m['title'] as String?, fields: fields);
    }

    parity('notices a stalled customer at the same moment, with the same words', (Map<String, Object?> fx) {
      for (final script in cases(fx, 'frictionIdle')) {
        final layers = <FrictionConfig?>[
          for (final l in script['config']! as List<Object?>) FrictionConfig.fromJson(l! as Map<String, Object?>),
          // The RN rule itself: no outstanding-field gate, no call gate.
          const FrictionConfig(requireOutstandingField: false),
        ];
        final d = FrictionDetector(rules: Friction.resolve(layers));
        final ops = script['ops']! as List<Object?>;
        final want = script['output']! as List<Object?>;
        for (var i = 0; i < ops.length; i++) {
          final op = ops[i]! as List<Object?>;
          Object? got;
          switch (op[0]) {
            case 'screen':
              d.onScreen(screenOf(op[1]), (op[2]! as num).toInt());
            case 'interaction':
              d.onInteraction((op[1]! as num).toInt());
            case 'dueIn':
              got = d.idleDueIn((op[1]! as num).toInt());
            case 'idle':
              final s = d.onIdle((op[1]! as num).toInt());
              got = s == null
                  ? null
                  : <String, Object?>{
                      'name': s.name, 'screen': s.screen, 'detail': s.detail, 'data': s.data,
                      'cooldown_seconds': s.cooldownSeconds, 'max_per_session': s.maxPerSession,
                    };
            default:
              fail('unknown op $op');
          }
          expect(canon(got), canon(want[i]), reason: 'script ${script['config']} op #$i $op');
        }
      }
    });
  });

  group('sdk/contract/design.json', () {
    late Map<String, Object?> fx;

    setUpAll(() async {
      fx = await contractJson('contract/design.json');
    });

    test('parses every token of every design, exactly', () {
      final all = cases(fx, 'cases');
      expect(all, isNotEmpty);
      for (final c in all) {
        final raw = c['design']! as Map<String, Object?>;
        final d = ResolvedDesign.fromJson(raw);
        expect(d, isNotNull, reason: '${c['config']}');
        // Read back key for key: every colour, size, weight, radius, shadow,
        // glyph and flag the server resolved, nothing dropped or renamed.
        expect(canon(d!.light.toJson()), canon(raw['light']), reason: 'light ${c['config']}');
        expect(canon(d.dark.toJson()), canon(raw['dark']), reason: 'dark ${c['config']}');
        expect(canon(d.config), canon(raw['config']));
      }
    });

    test('picks light or dark as the React Native SDK does', () {
      for (final c in cases(fx, 'cases')) {
        final d = ResolvedDesign.fromJson(c['design'])!;
        final picks = c['picks']! as Map<String, Object?>;
        expect(d.pick(deviceDark: false).scheme, picks['deviceLight'], reason: '${c['config']} on a light device');
        expect(d.pick(deviceDark: true).scheme, picks['deviceDark'], reason: '${c['config']} on a dark device');
        expect(d.pick().scheme, picks['deviceUnknown'], reason: '${c['config']} when the device has not said');
      }
    });

    test('an embed that never chose a design carries its Appearance in the tokens', () {
      final legacy = fx['legacy']! as Map<String, Object?>;
      final appearance = legacy['appearance']! as Map<String, Object?>;
      final d = ResolvedDesign.fromJson(legacy['design'])!;
      expect(canon(d.light.toJson()), canon((legacy['design']! as Map<String, Object?>)['light']));
      for (final t in <ThemeTokens>[d.light, d.dark]) {
        expect(t.colors.accent, appearance['accent']);
        expect(t.shape.radius.lg, n(appearance['radius']));
      }
      expect(d.pick(deviceDark: false).scheme, appearance['theme']);
    });

    test("every design's launcher glyph is path data this SDK can paint", () {
      final ids = <String>{};
      for (final c in cases(fx, 'cases')) {
        final d = ResolvedDesign.fromJson(c['design'])!;
        for (final t in <ThemeTokens>[d.light, d.dark]) {
          final glyph = t.icons.launcher;
          if (glyph == null) continue; // the brand's logo
          ids.add(glyph.id);
          final commands = SvgPath.parse(glyph.path);
          expect(commands, isNotNull, reason: '${glyph.id}: ${glyph.path}');
          expect(commands, isNotEmpty, reason: glyph.id);
        }
      }
      expect(ids, isNotEmpty);
    });

    test('builds the same glyph image URLs', () {
      final glyphs = cases(fx, 'glyphs');
      expect(glyphs, isNotEmpty);
      for (final g in glyphs) {
        final a = g['args']! as List<Object?>;
        expect(Design.glyphUrl(a[0] as String?, a[1]! as String, a[2]! as String, a[3]! as num, a[4]! as num), g['url'],
            reason: '$a');
      }
    });

    test('a session carries its design beside appearance', () {
      final c = cases(fx, 'cases').first;
      final session = SessionConfig.fromJson(<String, Object?>{
        'agentId': 'a',
        'appearance': <String, Object?>{'accent': '#318CE7'},
        'design': c['design'],
      });
      expect(canon(session.design!.toJson()), canon(c['design']));
      expect(SessionConfig.fromJson(const <String, Object?>{'agentId': 'a'}).design, isNull,
          reason: 'an older server sends no design; the SDK draws from appearance');
    });
  });

  group('the package itself', () {
    test('the socket tracer is the shared one, verbatim', () async {
      // contract/socket-trace.js is extracted from the Android SDK; every SDK injects the same bytes.
      final shared = await requireFile('contract/socket-trace.js');
      expect(SocketTrace.js, shared.readAsStringSync());
    });

    test('the core imports nothing but Dart itself', () async {
      final root = await packageRoot();
      final dir = Directory('${(root ?? Directory.current).path}/lib/src/core');
      final files = dir.listSync().whereType<File>().where((File f) => f.path.endsWith('.dart')).toList();
      expect(files, isNotEmpty);
      for (final f in files) {
        final imports = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''', multiLine: true)
            .allMatches(f.readAsStringSync())
            .map((Match m) => m[1]!)
            .toList();
        for (final i in imports) {
          final allowed = !i.contains(':') || i == 'dart:async' || i == 'dart:convert' || i == 'dart:math';
          expect(allowed, isTrue, reason: '${f.path} imports $i — the core must stay pure Dart');
        }
      }
    });
  });
}
