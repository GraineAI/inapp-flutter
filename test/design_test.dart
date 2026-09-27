// The design, drawn: the bar, the launcher, the transcript and a component
// card, each under real sessions' designs (sdk/contract/design.json — every
// one of them) and under none — where every surface must look exactly as it
// did before designs. Fakes only: no WebView, no network.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graine_inapp/graine_inapp.dart';
import 'package:graine_inapp/src/glyph.dart';

import 'contract_files.dart';

const String base = 'https://www.graine.ai';

/// The call as the widgets see it, with every field settable.
class FakeCall extends ChangeNotifier implements GraineCallState {
  @override
  bool connected = false;
  @override
  bool connecting = false;
  @override
  bool muted = false;
  @override
  bool ready = true;
  @override
  bool reconnecting = false;
  @override
  bool? online;
  @override
  ConnectionQuality quality = ConnectionQuality.unknown;
  @override
  GraineConnectivity connectivity = GraineConnectivity.ready;
  @override
  List<Caption> captions = const <Caption>[];
  @override
  bool agentSpeaking = false;
  @override
  bool micDenied = false;
  @override
  Map<String, Object?> appearance = const <String, Object?>{};

  @override
  Caption? get caption => captions.isEmpty ? null : captions.last;

  int starts = 0;

  @override
  Future<void> start() async => starts++;
  @override
  void end() {}
  @override
  void setMuted(bool muted) {}
  @override
  void retry() {}
}

/// A screen: 800x600, the device light or dark, reduced motion on or off.
Widget host(Widget child, {Brightness brightness = Brightness.light, bool still = false}) => MediaQuery(
      data: MediaQueryData(size: const Size(800, 600), platformBrightness: brightness, disableAnimations: still),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(children: <Widget>[child]),
      ),
    );

/// A launcher or transcript placed at the top left, at its own size.
Widget placed(Widget child, {Brightness brightness = Brightness.light}) =>
    host(Positioned(left: 10, top: 10, width: 400, child: Align(alignment: Alignment.topLeft, child: child)),
        brightness: brightness);

Color hex(String h) => Color(int.parse('FF${h.substring(1)}', radix: 16));

/// [c] at [opacity] — as the SDK fades a shadow or a glass surface.
Color faded(Color c, double opacity) => Color.lerp(c.withAlpha(0), c, opacity)!;

BoxDecoration decorationOf(WidgetTester tester, Finder f) => tester.widget<Container>(f).decoration! as BoxDecoration;

/// The first Container at or under [f] that paints a fill.
BoxDecoration fillOf(WidgetTester tester, Finder f) {
  final all = find.descendant(of: f, matching: find.byType(Container), matchRoot: true);
  for (final c in tester.widgetList<Container>(all)) {
    final d = c.decoration;
    if (d is BoxDecoration && d.color != null) return d;
  }
  fail('no filled Container under $f');
}

TextStyle styleOf(WidgetTester tester, String text) => tester.widget<Text>(find.text(text)).style!;

Map<String, Object?> card({Map<String, Object?> style = const <String, Object?>{}}) => <String, Object?>{
      'widget_id': 'cars:1',
      'kind': 'product_list',
      'style': <String, Object?>{'surface': 'card', 'preset': 'cards', ...style},
      'data': <String, Object?>{
        'title': 'Two that fit',
        'prompt': 'Tap one.',
        'selectLabel': 'Choose',
        'items': <Object?>[
          <String, Object?>{'id': 'creta', 'title': 'Creta', 'price': '₹19.2 lakh'},
          <String, Object?>{'id': 'seltos', 'title': 'Seltos'},
        ],
      },
    };

void main() {
  // Every design in design.json, and three picked out by what was chosen:
  // [0] Graine Classic, following the device; [1] every knob turned one way —
  // fixed dark, glass, hard shadow, 2px outlines, square corners, a pill
  // launcher showing the logo, outline bubbles, no motion; [2] the other way —
  // fixed light, a squircle, no shadow, minimal bubbles, lively motion.
  late List<Map<String, Object?>> all;
  late List<ResolvedDesign> designs;
  late Map<String, Object?> classicRaw;

  setUpAll(() async {
    final fx = await contractJson('contract/design.json');
    all = (fx['cases']! as List<Object?>).cast<Map<String, Object?>>();
    Map<String, Object?> where(bool Function(Map<String, Object?> config) test) =>
        all.firstWhere((Map<String, Object?> c) => test(c['config']! as Map<String, Object?>));
    final picked = <Map<String, Object?>>[
      where((Map<String, Object?> c) => c.length == 1 && c['preset'] == 'graine-classic'),
      where((Map<String, Object?> c) => c['launcherShape'] == 'pill' && c['shadow'] == 'hard'),
      where((Map<String, Object?> c) => c['launcherShape'] == 'squircle' && c['bubbles'] == 'minimal'),
    ];
    designs = <ResolvedDesign>[for (final c in picked) ResolvedDesign.fromJson(c['design'])!];
    classicRaw = picked.first['design']! as Map<String, Object?>;
    expect(all.length, greaterThanOrEqualTo(3));
  });

  group('GraineAgentBar', () {
    Finder bar() => find.byKey(GraineAgentBar.barKey);

    testWidgets('no design: exactly the bar before designs', (WidgetTester tester) async {
      final call = FakeCall();
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false)));
      final d = decorationOf(tester, bar());
      expect(d.color, const Color(0xFFFFFFFF));
      expect(d.borderRadius, BorderRadius.circular(26));
      expect(d.border, Border.all(color: const Color(0x1A000000)));
      expect(d.boxShadow, const <BoxShadow>[BoxShadow(color: Color(0x4D000000), blurRadius: 16, offset: Offset(0, 6))]);
      expect(styleOf(tester, 'tap to talk').fontSize, 12.5);
      expect(styleOf(tester, 'tap to talk').fontFamily, isNull);
      expect(find.text('✦'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(AnimatedContainer), findsNothing);

      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false), brightness: Brightness.dark));
      expect(decorationOf(tester, bar()).color, const Color(0xFF17161A));
    });

    testWidgets("a design draws it — and it re-picks when the device switches", (WidgetTester tester) async {
      final t = designs[0].light;
      final call = FakeCall();
      Widget widget() => GraineAgentBar(call: call, showComponents: false, design: designs[0]);
      await tester.pumpWidget(host(widget()));
      var d = decorationOf(tester, bar());
      expect(d.color, hex(t.colors.surface));
      expect(d.borderRadius, BorderRadius.circular(t.shape.radius.xl));
      expect(d.border, Border.all(color: hex(t.colors.border), width: t.shape.borderWidth));
      final floating = t.elevation.floating!;
      expect(d.boxShadow, <BoxShadow>[
        BoxShadow(color: faded(const Color(0xFF000000), floating.opacity), offset: Offset(0, floating.y), blurRadius: floating.blur),
      ]);
      expect(styleOf(tester, 'tap to talk').color, hex(t.colors.textMuted));
      expect(styleOf(tester, 'tap to talk').fontSize, t.font.scale.caption);
      expect(fillOf(tester, find.byKey(GraineAgentBar.callButtonKey)).color, hex(t.colors.accent));
      expect(find.byKey(const ValueKey<String>('graine-glyph')), findsOneWidget, reason: "the design's glyph, painted");

      await tester.pumpWidget(host(widget(), brightness: Brightness.dark));
      await tester.pump(const Duration(milliseconds: 400));
      d = decorationOf(tester, bar());
      expect(d.color, hex(designs[0].dark.colors.surface));
      expect(styleOf(tester, 'tap to talk').color, hex(designs[0].dark.colors.textMuted));
    });

    testWidgets('during a call: the microphone on the accent, the end button danger', (WidgetTester tester) async {
      final t = designs[0].light;
      final call = FakeCall()..connected = true;
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false, design: designs[0])));
      await tester.pump(const Duration(milliseconds: 400));
      expect(fillOf(tester, find.byKey(GraineAgentBar.muteButtonKey)).color, hex(t.colors.accent));
      expect(fillOf(tester, find.byKey(GraineAgentBar.callButtonKey)).color, hex(t.colors.danger));
      expect(styleOf(tester, '✕').color, const Color(0xFFFFFFFF));
    });

    testWidgets("glass, square corners and a heavy outline; the brand's dark over a light device",
        (WidgetTester tester) async {
      final t = designs[1].dark;
      final call = FakeCall()
        ..connected = true
        ..captions = const <Caption>[Caption(Role.agent, 'Hi, how can I help?')];
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false, design: designs[1], name: 'Riya')));
      expect(find.descendant(of: bar(), matching: find.byType(BackdropFilter)), findsOneWidget);
      expect(find.descendant(of: find.byKey(GraineAgentBar.captionKey), matching: find.byType(BackdropFilter)),
          findsOneWidget);
      final outer = decorationOf(tester, bar());
      expect(outer.boxShadow, isEmpty, reason: 'no floating shadow in this design');
      final fill = fillOf(tester, bar());
      expect(fill.color, faded(hex(t.colors.surface), t.glass!.surfaceOpacity));
      expect(fill.borderRadius, BorderRadius.zero);
      expect(fill.border, Border.all(color: hex(t.colors.border), width: 2));
      // The brand shows its logo; with none uploaded, the name's first letter.
      expect(find.text('R'), findsOneWidget);
      expect(find.byType(AnimatedContainer), findsNothing, reason: 'motion: none');
    });

    testWidgets('motion at the design pace, and never when the platform asks for less', (WidgetTester tester) async {
      final call = FakeCall();
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false, design: designs[2])));
      expect(find.byType(AnimatedContainer), findsWidgets);
      final animated = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer).first);
      expect(animated.duration, Duration(milliseconds: designs[2].light.motion.durationMs));

      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false, design: designs[2]), still: true));
      expect(find.byType(AnimatedContainer), findsNothing);
    });

    testWidgets('a design font only when the app bundles it', (WidgetTester tester) async {
      final raw = <String, Object?>{
        ...classicRaw,
        'light': <String, Object?>{
          ...classicRaw['light']! as Map<String, Object?>,
          'font': <String, Object?>{
            ...(classicRaw['light']! as Map<String, Object?>)['font']! as Map<String, Object?>,
            'body': 'Inter',
            'heading': 'Inter',
          },
        },
      };
      final design = ResolvedDesign.fromJson(raw)!;
      final call = FakeCall();
      addTearDown(GraineInApp.resetForTesting);

      GraineInApp.forTesting(const GraineConfig(baseUrl: base, publishableKey: 'pk_test_1'), install: true);
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false, design: design)));
      expect(styleOf(tester, 'tap to talk').fontFamily, isNull, reason: 'not bundled: the platform font, silently');

      GraineInApp.resetForTesting();
      GraineInApp.forTesting(const GraineConfig(baseUrl: base, publishableKey: 'pk_test_1', fonts: <String>['inter']),
          install: true);
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false, design: design, key: UniqueKey())));
      expect(styleOf(tester, 'tap to talk').fontFamily, 'inter');
      expect(styleOf(tester, 'Assistant').fontFamily, 'inter');
    });
  });

  group('GraineLauncher', () {
    Finder launcher() => find.byKey(GraineLauncher.launcherKey);
    BoxDecoration box(WidgetTester tester) =>
        decorationOf(tester, find.descendant(of: launcher(), matching: find.byType(Container)).first);

    testWidgets('a circle in the accent, the glyph painted in onAccent, the floating shadow; a tap calls',
        (WidgetTester tester) async {
      final t = designs[0].light;
      final call = FakeCall();
      await tester.pumpWidget(placed(GraineLauncher(call: call, design: designs[0])));
      expect(tester.getSize(launcher()), const Size(56, 56));
      final d = box(tester);
      expect(d.color, hex(t.colors.accent));
      expect(d.borderRadius, BorderRadius.circular(28));
      expect(d.boxShadow, hasLength(1));
      expect(d.boxShadow!.single.blurRadius, t.elevation.floating!.blur);
      final glyph = find.byKey(const ValueKey<String>('graine-glyph'));
      expect(glyph, findsOneWidget);
      expect(tester.getSize(glyph).height, closeTo(56 * 0.46, 0.01));

      await tester.tap(launcher());
      expect(call.starts, 1);
      call.connected = true;
      await tester.tap(launcher());
      expect(call.starts, 1, reason: 'a call already on is not started again');
    });

    testWidgets('a squircle: 30% corners, no shadow when the design has none', (WidgetTester tester) async {
      final t = designs[2].light;
      await tester.pumpWidget(placed(GraineLauncher(call: FakeCall(), design: designs[2])));
      await tester.pump(const Duration(milliseconds: 400));
      final d = box(tester);
      expect(d.borderRadius, BorderRadius.circular(56 * 0.3));
      expect(d.color, hex(t.colors.accent));
      expect(d.boxShadow, isEmpty);
    });

    testWidgets('a pill as wide as its label; neo-brutalist: a solid offset copy and an outline in the text colour',
        (WidgetTester tester) async {
      final t = designs[1].dark;
      await tester.pumpWidget(placed(GraineLauncher(call: FakeCall(), design: designs[1], label: 'Talk to Asha')));
      expect(find.text('Talk to Asha'), findsOneWidget);
      final size = tester.getSize(launcher());
      expect(size.height, 56);
      expect(size.width, greaterThan(56));
      expect(size.width, lessThan(400), reason: 'as wide as its label, not the space it is offered');
      final d = box(tester);
      final ink = hex(t.colors.text);
      expect(d.boxShadow, <BoxShadow>[BoxShadow(color: ink, offset: const Offset(4, 4))]);
      expect(d.border, Border.all(color: ink, width: 2));
      expect(d.borderRadius, BorderRadius.circular(28));
      // The logo, and with none uploaded, the label's first letter.
      expect(find.text('T'), findsOneWidget);
      expect(styleOf(tester, 'Talk to Asha').color, hex(t.colors.onAccent));
    });

    testWidgets("no design: a circle in the dashboard's accent with the SDK's mark", (WidgetTester tester) async {
      final call = FakeCall()..appearance = const <String, Object?>{'accent': '12AB34'};
      await tester.pumpWidget(placed(GraineLauncher(call: call)));
      final d = box(tester);
      expect(d.color, const Color(0xFF12AB34));
      expect(d.borderRadius, BorderRadius.circular(28));
      expect(d.boxShadow, const <BoxShadow>[BoxShadow(color: Color(0x4D000000), blurRadius: 16, offset: Offset(0, 6))]);
      expect(find.text('✦'), findsOneWidget);
    });
  });

  group('GraineTranscriptView', () {
    final said = <Caption>[
      const Caption(Role.agent, 'Which car are you looking at?'),
      const Caption(Role.customer, 'The Creta'),
    ];
    Finder bubble(int i) => find.byKey(GraineTranscriptView.bubbleKey(i));
    BoxDecoration? bubbleBox(WidgetTester tester, int i) => tester.widget<Container>(bubble(i)).decoration as BoxDecoration?;

    testWidgets('filled: the customer in userBubble, the agent in agentBubble, under a surface header',
        (WidgetTester tester) async {
      final t = designs[0].light;
      final call = FakeCall()..captions = said;
      await tester.pumpWidget(placed(GraineTranscriptView(call: call, design: designs[0], title: 'Asha')));
      expect(find.text('Asha'), findsOneWidget);
      expect(styleOf(tester, 'Asha').fontSize, t.font.scale.title);
      expect(fillOf(tester, find.byKey(GraineTranscriptView.headerKey)).color, hex(t.colors.surface));
      expect(bubbleBox(tester, 0)!.color, hex(t.colors.agentBubble));
      expect(bubbleBox(tester, 1)!.color, hex(t.colors.userBubble));
      expect(bubbleBox(tester, 1)!.borderRadius,
          BorderRadius.only(
            topLeft: Radius.circular(t.shape.radius.lg),
            topRight: Radius.circular(t.shape.radius.lg),
            bottomLeft: Radius.circular(t.shape.radius.lg),
            bottomRight: Radius.circular(t.shape.radius.sm),
          ),
          reason: 'the corner nearest the speaker is the small one');
      expect(tester.getRect(bubble(1)).right, greaterThan(tester.getRect(bubble(0)).right), reason: 'the customer on the right');
      expect(styleOf(tester, 'The Creta').color, hex(t.colors.userBubbleText));
    });

    testWidgets('outline: both clear, the customer outlined in the accent, the agent in the border colour',
        (WidgetTester tester) async {
      final t = designs[1].dark;
      await tester.pumpWidget(placed(GraineTranscriptView(call: FakeCall()..captions = said, design: designs[1])));
      expect(find.byKey(GraineTranscriptView.headerKey), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget, reason: 'the header is a glass surface');
      expect(bubbleBox(tester, 0)!.color, isNull);
      expect(bubbleBox(tester, 1)!.color, isNull);
      expect(bubbleBox(tester, 0)!.border, Border.all(color: hex(t.colors.border), width: t.shape.borderWidth));
      expect(bubbleBox(tester, 1)!.border, Border.all(color: hex(t.colors.accent), width: t.shape.borderWidth));
      expect(styleOf(tester, 'The Creta').color, hex(t.colors.text));
    });

    testWidgets("minimal: the agent's words plain on the page, the customer's on accentSoft", (WidgetTester tester) async {
      final t = designs[2].light;
      await tester.pumpWidget(placed(GraineTranscriptView(call: FakeCall()..captions = said, design: designs[2])));
      expect(bubbleBox(tester, 0), isNull);
      expect(bubbleBox(tester, 1)!.color, hex(t.colors.accentSoft));
      expect(styleOf(tester, 'Which car are you looking at?').color, hex(t.colors.text));
    });

    testWidgets("no design: the dashboard's accent for the customer; nothing said yet says so", (WidgetTester tester) async {
      final call = FakeCall()..appearance = const <String, Object?>{'accent': '#12AB34'};
      await tester.pumpWidget(placed(GraineTranscriptView(call: call)));
      expect(find.text('What you and the assistant say appears here.'), findsOneWidget);
      call
        ..captions = said
        ..notifyListeners();
      await tester.pump();
      expect(bubbleBox(tester, 1)!.color, const Color(0xFF12AB34));
    });
  });

  group('GraineWidgetView', () {
    Finder chrome() => find.byKey(const ValueKey<String>('graine-surface-card'));

    Future<GraineComponents> show(WidgetTester tester, Widget Function(GraineComponents c) view,
        {Map<String, Object?> style = const <String, Object?>{}}) async {
      final comps = GraineComponents(baseUrl: base, clock: () => tester.binding.clock.now().millisecondsSinceEpoch);
      comps.present(card(style: style));
      await tester.pumpWidget(host(view(comps)));
      await tester.pump(const Duration(milliseconds: 400));
      return comps;
    }

    Future<void> done(WidgetTester tester, GraineComponents comps) async {
      await tester.pumpWidget(const SizedBox());
      comps.dispose();
    }

    testWidgets('no design: exactly the card before designs', (WidgetTester tester) async {
      final comps = await show(tester, (GraineComponents c) => GraineWidgetView(components: c, appearance: const <String, Object?>{}));
      final d = decorationOf(tester, chrome());
      expect(d.color, const Color(0xFFFFFFFF));
      expect(d.borderRadius, BorderRadius.circular(18));
      expect(d.border, Border.all(color: const Color(0xFFE5E4E0)));
      expect(d.boxShadow, const <BoxShadow>[BoxShadow(color: Color(0x2E000000), blurRadius: 12, offset: Offset(0, 4))]);
      expect(styleOf(tester, 'Two that fit').fontSize, 14.5);
      await done(tester, comps);
    });

    testWidgets('a design: surfaceRaised, radius.lg, the card shadow, the heading at the title size',
        (WidgetTester tester) async {
      final t = designs[0].light;
      final comps = await show(
          tester, (GraineComponents c) => GraineWidgetView(components: c, appearance: const <String, Object?>{}, design: designs[0]));
      final d = decorationOf(tester, chrome());
      expect(d.color, hex(t.colors.surfaceRaised));
      expect(d.borderRadius, BorderRadius.circular(t.shape.radius.lg));
      final s = t.elevation.card!;
      expect(d.boxShadow, <BoxShadow>[
        BoxShadow(color: faded(const Color(0xFF000000), s.opacity), offset: Offset(0, s.y), blurRadius: s.blur),
      ]);
      final title = styleOf(tester, 'Two that fit');
      expect(title.fontSize, t.font.scale.title);
      expect(title.fontWeight, FontWeight.w600);
      expect(styleOf(tester, 'Tap one.').color, hex(t.colors.textMuted));
      expect(styleOf(tester, 'Tap one.').fontSize, t.font.scale.caption);
      // Primary buttons: the accent at radius.md.
      final button = find.ancestor(of: find.text('Choose').first, matching: find.byType(Container)).first;
      expect(decorationOf(tester, button).color, hex(t.colors.accent));
      expect(decorationOf(tester, button).borderRadius, BorderRadius.circular(t.shape.radius.md));
      await done(tester, comps);
    });

    testWidgets('neo-brutalist: the solid offset in the text colour, heavy outline, square corners',
        (WidgetTester tester) async {
      final t = designs[1].dark;
      final comps = await show(
          tester, (GraineComponents c) => GraineWidgetView(components: c, appearance: const <String, Object?>{}, design: designs[1]));
      final d = decorationOf(tester, chrome());
      expect(d.color, hex(t.colors.surfaceRaised));
      expect(d.boxShadow, <BoxShadow>[BoxShadow(color: hex(t.colors.text), offset: const Offset(4, 4))]);
      expect(d.border, Border.all(color: hex(t.colors.border), width: 2));
      expect(d.borderRadius, BorderRadius.zero);
      await done(tester, comps);
    });

    testWidgets("the component's own radius and accent still win over the design", (WidgetTester tester) async {
      final comps = await show(
        tester,
        (GraineComponents c) => GraineWidgetView(components: c, appearance: const <String, Object?>{}, design: designs[0]),
        style: const <String, Object?>{'radius': 6, 'accent': '#FF0000'},
      );
      expect(decorationOf(tester, chrome()).borderRadius, BorderRadius.circular(6));
      final button = find.ancestor(of: find.text('Choose').first, matching: find.byType(Container)).first;
      expect(decorationOf(tester, button).color, const Color(0xFFFF0000));
      await done(tester, comps);
    });
  });

  group('every design in design.json', () {
    testWidgets('draws the bar, the launcher, the transcript and a card from its own tokens, light and dark',
        (WidgetTester tester) async {
      for (final c in all) {
        final design = ResolvedDesign.fromJson(c['design'])!;
        final name = (c['config']! as Map<String, Object?>)['preset'];
        for (final device in <Brightness>[Brightness.light, Brightness.dark]) {
          final t = design.pick(deviceDark: device == Brightness.dark);
          final why = '$name on a ${device.name} device (${t.scheme})';
          final call = FakeCall()
            ..connected = true
            ..captions = const <Caption>[Caption(Role.agent, 'Hello'), Caption(Role.customer, 'Hi there')];
          final comps = GraineComponents(baseUrl: base, clock: () => tester.binding.clock.now().millisecondsSinceEpoch);
          comps.present(card());
          await tester.pumpWidget(MediaQuery(
            data: MediaQueryData(size: const Size(800, 1200), platformBrightness: device),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Stack(children: <Widget>[
                GraineAgentBar(call: call, showComponents: false, design: design, key: UniqueKey()),
                Positioned(left: 10, top: 10, child: GraineLauncher(call: call, design: design, label: 'Talk')),
                Positioned(
                    left: 10, right: 10, top: 90, child: GraineTranscriptView(call: call, design: design, maxHeight: 200)),
                Positioned(
                    left: 10,
                    right: 10,
                    top: 320,
                    child: GraineWidgetView(components: comps, appearance: const <String, Object?>{}, design: design)),
              ]),
            ),
          ));
          await tester.pump(const Duration(seconds: 1));
          expect(tester.takeException(), isNull, reason: why);

          // The bar: surface (translucent with glass), radius.xl, the floating shadow or none.
          final bar = fillOf(tester, find.byKey(GraineAgentBar.barKey));
          final surface = hex(t.colors.surface);
          expect(bar.color, t.glass == null ? surface : faded(surface, t.glass!.surfaceOpacity), reason: why);
          expect(bar.borderRadius, BorderRadius.circular(t.shape.radius.xl), reason: why);
          expect(find.descendant(of: find.byKey(GraineAgentBar.barKey), matching: find.byType(BackdropFilter)),
              t.glass == null ? findsNothing : findsOneWidget,
              reason: why);
          expect(decorationOf(tester, find.byKey(GraineAgentBar.barKey)).boxShadow,
              hasLength(t.elevation.floating == null ? 0 : 1),
              reason: why);
          expect(styleOf(tester, 'listening').color, hex(t.colors.textMuted), reason: why);
          expect(fillOf(tester, find.byKey(GraineAgentBar.callButtonKey)).color, hex(t.colors.danger), reason: why);

          // The launcher: the accent, its shape's corners, its glyph painted (or the logo's stand-in).
          final launcher = find.byKey(GraineLauncher.launcherKey);
          final box = decorationOf(tester, find.descendant(of: launcher, matching: find.byType(Container)).first);
          expect(box.color, hex(t.colors.accent), reason: why);
          expect(box.borderRadius, BorderRadius.circular(Design.launcherRadius(t.shape.launcher, t.shape.radius, 56)),
              reason: why);
          expect(tester.getSize(launcher).height, 56, reason: why);
          if (t.shape.launcher == 'pill') {
            expect(tester.getSize(launcher).width, greaterThan(56), reason: why);
          } else {
            expect(tester.getSize(launcher).width, 56, reason: why);
          }
          final hard = t.elevation.hardOffset;
          if (hard != null) {
            expect(box.boxShadow, <BoxShadow>[BoxShadow(color: hex(t.colors.text), offset: Offset(hard.x, hard.y))],
                reason: why);
          } else {
            expect(box.boxShadow, hasLength(t.elevation.floating == null ? 0 : 1), reason: why);
          }
          expect(
              find.descendant(of: launcher, matching: find.byKey(BrandMark.glyphKey)),
              t.icons.launcher == null ? findsNothing : findsOneWidget,
              reason: why);

          // The transcript: bubbles in the design's style.
          final agent = tester.widget<Container>(find.byKey(GraineTranscriptView.bubbleKey(0))).decoration as BoxDecoration?;
          final customer = tester.widget<Container>(find.byKey(GraineTranscriptView.bubbleKey(1))).decoration as BoxDecoration?;
          switch (t.bubbles) {
            case 'filled':
              expect(agent!.color, hex(t.colors.agentBubble), reason: why);
              expect(customer!.color, hex(t.colors.userBubble), reason: why);
              final words = find.descendant(of: find.byKey(GraineTranscriptView.bubbleKey(1)), matching: find.text('Hi there'));
              expect(tester.widget<Text>(words).style!.color, hex(t.colors.userBubbleText), reason: why);
            case 'outline':
              expect(agent!.color, isNull, reason: why);
              expect((customer!.border! as Border).top.color, hex(t.colors.accent), reason: why);
            case 'minimal':
              expect(agent, isNull, reason: why);
              expect(customer!.color, hex(t.colors.accentSoft), reason: why);
          }

          // The card: surfaceRaised, radius.lg, the card shadow or the hard offset.
          final chrome = decorationOf(tester, find.byKey(const ValueKey<String>('graine-surface-card')));
          expect(chrome.color, hex(t.colors.surfaceRaised), reason: why);
          expect(chrome.borderRadius, BorderRadius.circular(t.shape.radius.lg), reason: why);
          expect(chrome.boxShadow,
              hasLength(hard != null ? 1 : (t.elevation.card == null ? 0 : 1)),
              reason: why);
          expect(styleOf(tester, 'Two that fit').fontSize, t.font.scale.title, reason: why);

          await tester.pumpWidget(const SizedBox());
          comps.dispose();
        }
      }
    });
  });

  group('the launcher glyph, painted', () {
    Future<ByteData> paint(WidgetTester tester, LauncherGlyph glyph) async {
      final key = GlobalKey();
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: BrandMark(glyph: glyph, colorHex: '#000000', size: 48, name: 'x'),
          ),
        ),
      ));
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage();
        return image.toByteData(format: ui.ImageByteFormat.rawRgba);
      });
      return bytes!;
    }

    int alphaAt(ByteData rgba, int x, int y) => rgba.getUint8((y * 48 + x) * 4 + 3);

    testWidgets('a filled glyph fills by the nonzero rule, holes and all', (WidgetTester tester) async {
      // Phosphor's chat-dots: a bubble with three dots cut out of it.
      const dots = LauncherGlyph(
        id: 'chat-dots-filled',
        stroke: false,
        path: 'M12 2.25A9.75 9.75 0 0 0 3.392 16.582L2.328 19.775a1.5 1.5 0 0 0 1.897 1.897l3.192 -1.064A9.75 9.75 0 1 0 12 2.25ZM7.875 13.125a1.125 1.125 0 1 1 1.125 -1.125A1.125 1.125 0 0 1 7.875 13.125Zm4.125 0a1.125 1.125 0 1 1 1.125 -1.125A1.125 1.125 0 0 1 12 13.125Zm4.125 0a1.125 1.125 0 1 1 1.125 -1.125A1.125 1.125 0 0 1 16.125 13.125Z',
      );
      final rgba = await paint(tester, dots);
      // 48 px for 24 units: (12, 6) is inside the bubble; (12, 12) is the middle dot; (1, 1) is outside.
      expect(alphaAt(rgba, 24, 12), 255, reason: 'the bubble is filled');
      expect(alphaAt(rgba, 24, 24), 0, reason: 'the middle dot is a hole');
      expect(alphaAt(rgba, 16, 24), 0, reason: 'so is the left one');
      expect(alphaAt(rgba, 2, 2), 0, reason: 'outside the bubble');
    });

    testWidgets('a stroke glyph is drawn as lines at the design stroke, not filled', (WidgetTester tester) async {
      const bars = LauncherGlyph(id: 'audio-lines', stroke: true, path: 'M2 10v3M6 6v11M10 3v18M14 8v7M18 5v13M22 10v3');
      final rgba = await paint(tester, bars);
      expect(alphaAt(rgba, 20, 24), 255, reason: 'on the line at x=10');
      expect(alphaAt(rgba, 24, 24), 0, reason: 'between the lines');
    });
  });
}
