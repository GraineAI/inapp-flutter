// The design, drawn: the voice bar (and its caption, meter, icons, chat
// window and typeface), the launcher, the transcript and a component card,
// each under real sessions' designs (sdk/contract/design.json — every one of
// them) and under none — where every surface keeps the colours, corners and
// depth it had before designs. Fakes only: no WebView, and no network — font
// files come from a mock HTTP client.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graine_inapp/graine_inapp.dart';
import 'package:graine_inapp/src/agent_bar.dart' show BarMeter;
import 'package:graine_inapp/src/chat_window.dart' show ChatWindow;
import 'package:graine_inapp/src/glyph.dart';
import 'package:graine_inapp/src/sdk_icon.dart';
import 'package:graine_inapp/src/style.dart' show OutsideShadowPainter;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

/// The shadows a surface wears: its decoration's — or, for a glass surface,
/// whose shadow is painted only outside it, the outside painter's.
List<BoxShadow> shadowsOn(WidgetTester tester, Finder f) {
  final w = tester.widget(f);
  if (w is Container) {
    final d = w.decoration;
    if (d is BoxDecoration && d.color != null) return d.boxShadow ?? const <BoxShadow>[];
  }
  for (final c in tester.widgetList<CustomPaint>(find.descendant(of: f, matching: find.byType(CustomPaint)))) {
    final painter = c.painter;
    if (painter is OutsideShadowPainter) return painter.shadows;
  }
  fail('no shadows found on $f');
}

/// The one SDK icon called [name] on screen.
SdkIconView icon(WidgetTester tester, String name) =>
    tester.widget<SdkIconView>(find.byWidgetPredicate((Widget w) => w is SdkIconView && w.name == name));

/// A design's soft shadow, as the SDK draws it.
BoxShadow soft(ThemeShadow s) => BoxShadow(
    color: faded(hex(s.color), s.opacity), offset: Offset(0, s.y), blurRadius: s.blur, spreadRadius: s.spread);

/// The first four bytes of a TrueType file, and enough after them to be one.
final Uint8List ttf = Uint8List.fromList(<int>[0, 1, 0, 0, ...List<int>.filled(60, 7)]);

/// A chat the app runs itself.
class FakeChat extends ChangeNotifier implements GraineChatState {
  FakeChat(this.messages);
  @override
  List<Caption> messages;
  @override
  bool connected = true;
  @override
  void send(String text) {}
}

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
    Map<String, Object?> caseOf(String preset) =>
        all.firstWhere((Map<String, Object?> c) => (c['config']! as Map<String, Object?>).length == 1 &&
            (c['config']! as Map<String, Object?>)['preset'] == preset);
    ResolvedDesign preset(String id) => ResolvedDesign.fromJson(caseOf(id)['design'])!;

    testWidgets("no design: the colours, corners and depth it always had, on the contract's elements",
        (WidgetTester tester) async {
      final call = FakeCall();
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false)));
      final d = decorationOf(tester, bar());
      expect(d.color, const Color(0xFFFFFFFF));
      expect(d.borderRadius, BorderRadius.circular(26));
      expect(d.border, Border.all(color: const Color(0x1A000000)));
      expect(d.boxShadow, const <BoxShadow>[BoxShadow(color: Color(0x4D000000), blurRadius: 16, offset: Offset(0, 6))]);
      expect(tester.getSize(bar()).height, 60);
      expect(styleOf(tester, 'Tap to talk').fontSize, 12);
      expect(styleOf(tester, 'Tap to talk').fontFamily, isNull);
      expect(find.text('A'), findsOneWidget, reason: "no glyph and no logo: the name's first letter");
      expect(icon(tester, 'mic').style, 'outline');
      expect(icon(tester, 'mic').color, const Color(0xFFFFFFFF), reason: "readable on the dashboard's accent");
      expect(fillOf(tester, find.byKey(GraineAgentBar.callButtonKey)).color, const Color(0xFF318CE7));
      expect(fillOf(tester, find.byKey(GraineAgentBar.closeButtonKey)).color, const Color(0x0D000000));
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(AnimatedContainer), findsNothing);

      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false), brightness: Brightness.dark));
      expect(decorationOf(tester, bar()).color, const Color(0xFF17161A));
    });

    testWidgets('a design draws it element by element — and re-picks when the device switches',
        (WidgetTester tester) async {
      final t = designs[0].light;
      final call = FakeCall();
      Widget widget() => GraineAgentBar(call: call, showComponents: false, design: designs[0]);
      await tester.pumpWidget(host(widget()));
      var d = decorationOf(tester, bar());
      expect(d.color, hex(t.colors.surface));
      expect(d.borderRadius, BorderRadius.circular(t.shape.radius.xl));
      expect(d.border, Border.all(color: hex(t.colors.border), width: t.shape.borderWidth));
      expect(d.boxShadow, <BoxShadow>[soft(t.elevation.floating!)]);
      expect(d.padding, EdgeInsets.all(t.shape.borderWidth), reason: 'the outline; 9 more inside it');
      expect(tester.getSize(bar()).height, 60);

      // 38 round, 10 apart, 9 from the ends.
      final avatar = tester.getRect(find.byKey(GraineAgentBar.avatarKey));
      final mic = tester.getRect(find.byKey(GraineAgentBar.callButtonKey));
      final close = tester.getRect(find.byKey(GraineAgentBar.closeButtonKey));
      expect(avatar.size, const Size(38, 38));
      expect(avatar.left - tester.getRect(bar()).left, 9 + t.shape.borderWidth);
      expect(tester.getRect(bar()).right - close.right, 9 + t.shape.borderWidth);
      expect(close.left - mic.right, 10);
      expect(mic.size, const Size(38, 38));
      expect(avatar.center.dy, closeTo(tester.getRect(bar()).center.dy, 0.01), reason: 'centred vertically');

      final name = styleOf(tester, 'Assistant');
      expect(name.fontSize, 14);
      expect(name.fontWeight, FontWeight.w600, reason: 'the body family at weights.strong');
      expect(name.color, hex(t.colors.text));
      final status = styleOf(tester, 'Tap to talk');
      expect(status.color, hex(t.colors.textMuted));
      expect(status.fontSize, t.font.scale.caption);
      expect(status.fontWeight, FontWeight.w400);

      expect(fillOf(tester, find.byKey(GraineAgentBar.callButtonKey)).color, hex(t.colors.accent));
      expect(icon(tester, 'mic').color, hex(t.colors.onAccent));
      expect(fillOf(tester, find.byKey(GraineAgentBar.closeButtonKey)).color, hex(t.colors.accentSoft));
      expect(icon(tester, 'close').color, hex(t.colors.textMuted));
      final glyph = find.byKey(const ValueKey<String>('graine-glyph'));
      expect(glyph, findsOneWidget, reason: "the design's glyph, painted");
      expect(tester.getSize(glyph), const Size(18, 18));

      await tester.pumpWidget(host(widget(), brightness: Brightness.dark));
      await tester.pump(const Duration(milliseconds: 400));
      d = decorationOf(tester, bar());
      expect(d.color, hex(designs[0].dark.colors.surface));
      expect(styleOf(tester, 'Tap to talk').color, hex(designs[0].dark.colors.textMuted));
    });

    testWidgets('during a call: the microphone on the accent, hang up danger with its icon in white, the meter',
        (WidgetTester tester) async {
      final t = designs[0].light;
      final call = FakeCall()..connected = true;
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false, design: designs[0])));
      await tester.pump(const Duration(milliseconds: 400));
      expect(fillOf(tester, find.byKey(GraineAgentBar.muteButtonKey)).color, hex(t.colors.accent));
      expect(icon(tester, 'mic').color, hex(t.colors.onAccent));
      expect(fillOf(tester, find.byKey(GraineAgentBar.callButtonKey)).color, hex(t.colors.danger));
      expect(icon(tester, 'end').color, const Color(0xFFFFFFFF));
      final meter = tester.widget<BarMeter>(find.byKey(GraineAgentBar.meterKey));
      expect(meter.color, hex(t.colors.accent));
      expect(meter.durationMs, t.motion.durationMs);
      expect(tester.getSize(find.byKey(GraineAgentBar.meterKey)), const Size(2.5 * 4 + 2 * 3, 12));

      call
        ..muted = true
        ..notifyListeners();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400)); // the fill eases at the design's pace
      expect(fillOf(tester, find.byKey(GraineAgentBar.muteButtonKey)).color, hex(t.colors.danger));
      expect(icon(tester, 'micOff').color, const Color(0xFFFFFFFF));
    });

    testWidgets("glass and a hard offset: translucent over a blur, the solid copy only outside; the brand's dark",
        (WidgetTester tester) async {
      final t = designs[1].dark;
      final call = FakeCall()
        ..connected = true
        ..captions = const <Caption>[Caption(Role.agent, 'Hi, how can I help?')];
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false, design: designs[1], name: 'Riya')));
      expect(find.descendant(of: bar(), matching: find.byType(BackdropFilter)), findsOneWidget);
      expect(find.descendant(of: find.byKey(GraineAgentBar.captionKey), matching: find.byType(BackdropFilter)),
          findsOneWidget);
      final hard = <BoxShadow>[BoxShadow(color: hex(t.colors.text), offset: const Offset(4, 4))];
      expect(shadowsOn(tester, bar()), hard, reason: 'the solid offset copy, never blurred');
      expect(shadowsOn(tester, find.byKey(GraineAgentBar.captionKey)), hard);
      final fill = fillOf(tester, bar());
      expect(fill.color, faded(hex(t.colors.surface), t.glass!.surfaceOpacity));
      expect(fill.borderRadius, BorderRadius.zero);
      expect(fill.border, Border.all(color: hex(t.colors.border), width: 2));
      // The brand shows its logo; with none uploaded, the name's first letter.
      expect(find.text('R'), findsOneWidget);
      expect(find.byType(AnimatedContainer), findsNothing, reason: 'motion: none');
      expect(tester.widget<BarMeter>(find.byKey(GraineAgentBar.meterKey)).durationMs, 0, reason: 'still');
      expect(icon(tester, 'mic').style, 'filled', reason: 'the iconStyle knob');
    });

    testWidgets('neo-brutalism: the solid text-coloured copy under the bar and the caption, offset, never blurred',
        (WidgetTester tester) async {
      final neo = preset('neo-brutalism');
      final t = neo.light;
      final call = FakeCall()
        ..connected = true
        ..captions = const <Caption>[Caption(Role.agent, 'Here are two that fit.')];
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false, design: neo)));
      final offset = t.elevation.hardOffset!;
      final d = decorationOf(tester, bar());
      expect(d.boxShadow, <BoxShadow>[BoxShadow(color: hex(t.colors.text), offset: Offset(offset.x, offset.y))]);
      expect(d.boxShadow!.single.blurRadius, 0);
      expect(d.color, hex(t.colors.surface));
      expect(d.border, Border.all(color: hex(t.colors.border), width: t.shape.borderWidth));
      expect(d.borderRadius, BorderRadius.circular(t.shape.radius.xl));
      final caption = decorationOf(tester, find.byKey(GraineAgentBar.captionKey));
      expect(caption.boxShadow, d.boxShadow);
      expect(caption.borderRadius, BorderRadius.circular(t.shape.radius.lg));
      expect(find.byKey(BrandMark.glyphKey), findsOneWidget, reason: "the design's zap, painted");
    });

    testWidgets('liquid glass: the surface at its opacity over a blur of the glass radius, its shadow only outside',
        (WidgetTester tester) async {
      final glass = preset('liquid-glass');
      final t = glass.light;
      await tester.pumpWidget(host(GraineAgentBar(call: FakeCall(), showComponents: false, design: glass)));
      final filter = tester.widget<BackdropFilter>(find.descendant(of: bar(), matching: find.byType(BackdropFilter)));
      expect(filter.filter, ui.ImageFilter.blur(sigmaX: t.glass!.blur, sigmaY: t.glass!.blur));
      expect(fillOf(tester, bar()).color, faded(hex(t.colors.surface), t.glass!.surfaceOpacity));
      expect(shadowsOn(tester, bar()), <BoxShadow>[soft(t.elevation.floating!)]);
      expect(fillOf(tester, bar()).borderRadius, BorderRadius.circular(t.shape.radius.xl));
    });

    testWidgets('a shadow painted outside a translucent surface never shows through it', (WidgetTester tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: CustomPaint(
                painter: OutsideShadowPainter(
                  shadows: const <BoxShadow>[BoxShadow(color: Color(0xFF000000), offset: Offset(4, 4))],
                  radius: BorderRadius.zero,
                ),
                child: const SizedBox(width: 32, height: 32),
              ),
            ),
          ),
        ),
      ));
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final rgba = (await tester.runAsync(() async {
        final image = await boundary.toImage();
        return image.toByteData(format: ui.ImageByteFormat.rawRgba);
      }))!;
      int alphaAt(int x, int y) => rgba.getUint8((y * 48 + x) * 4 + 3);
      expect(alphaAt(8 + 30, 8 + 30), 0, reason: 'inside the surface: nothing');
      expect(alphaAt(8 + 34, 8 + 34), 255, reason: 'the offset copy, outside it');
      expect(alphaAt(8 + 34, 8 + 2), 0, reason: 'offset down and right only');
    });

    testWidgets("the SDK's icons in the design's icon style and stroke — painted, never typed",
        (WidgetTester tester) async {
      for (final id in <String>['graine-classic', 'carbon', 'soft-playful', 'warm-earthy']) {
        final design = preset(id);
        final t = design.light;
        final call = FakeCall()..connected = true;
        await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false, design: design, key: UniqueKey())));
        for (final name in <String>['mic', 'end']) {
          final view = icon(tester, name);
          expect(view.style, t.icons.style, reason: '$id $name');
          expect(view.stroke, t.icons.stroke, reason: '$id $name');
          expect(view.size, 18);
          final painter = tester
              .widget<CustomPaint>(find.descendant(
                  of: find.byWidgetPredicate((Widget w) => w is SdkIconView && w.name == name),
                  matching: find.byType(CustomPaint)))
              .painter! as SdkIconPainter;
          expect(painter.treatment, SdkIcons.treatment(t.icons.style, t.icons.stroke), reason: '$id $name');
        }
        for (final typed in <String>['🎙', '🔇', '✕', '📞', '↻', '✦']) {
          expect(find.text(typed), findsNothing, reason: '$id: no emoji or text glyphs');
        }
      }
    });

    testWidgets('a filled icon fills its body, a duotone tints it, an outline leaves it hollow',
        (WidgetTester tester) async {
      Future<int> alphaInMic(String style) async {
        final key = GlobalKey();
        await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: SdkIconView('mic', color: const Color(0xFF000000), size: 48, style: style, stroke: 2),
            ),
          ),
        ));
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final rgba = (await tester.runAsync(() async {
          final image = await boundary.toImage();
          return image.toByteData(format: ui.ImageByteFormat.rawRgba);
        }))!;
        return rgba.getUint8((16 * 48 + 24) * 4 + 3); // (12, 8) in the icon's box: inside the capsule
      }

      expect(await alphaInMic('filled'), 255);
      expect(await alphaInMic('duotone'), closeTo(0.28 * 255, 3));
      expect(await alphaInMic('outline'), 0);
      expect(await alphaInMic('sharp'), 0);
    });

    testWidgets('the meter moves at the design pace — and never when the design or the platform says still',
        (WidgetTester tester) async {
      final call = FakeCall()..connected = true;
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false, design: designs[2])));
      expect(tester.widget<BarMeter>(find.byKey(GraineAgentBar.meterKey)).durationMs, designs[2].light.motion.durationMs);
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false, design: designs[2]), still: true));
      expect(tester.widget<BarMeter>(find.byKey(GraineAgentBar.meterKey)).durationMs, 0);
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false, design: preset('retro-terminal'))));
      expect(tester.widget<BarMeter>(find.byKey(GraineAgentBar.meterKey)).durationMs, 0, reason: 'durationMs 0 in the design');
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

    testWidgets('the caption rises into place over the design duration; with no motion it is simply there',
        (WidgetTester tester) async {
      final call = FakeCall()..connected = true;
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false, design: designs[2])));
      call
        ..captions = const <Caption>[Caption(Role.agent, 'Sure.')]
        ..notifyListeners();
      await tester.pump();
      Opacity rise() => tester.widget<Opacity>(
          find.ancestor(of: find.byKey(GraineAgentBar.captionKey), matching: find.byType(Opacity)).first);
      expect(rise().opacity, lessThan(0.2), reason: 'arriving');
      await tester.pump(Duration(milliseconds: designs[2].light.motion.durationMs));
      expect(rise().opacity, 1);

      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false, design: designs[1], key: UniqueKey())));
      expect(rise().opacity, 1, reason: 'motion: none');
    });

    testWidgets('the chat window in the design: header, mark, status, chevron, bubbles and composer',
        (WidgetTester tester) async {
      final t = designs[0].light;
      final call = FakeCall()..appearance = const <String, Object?>{'mode': 'both', 'start': 'chat', 'title': 'Asha'};
      final chat = FakeChat(const <Caption>[Caption(Role.agent, 'Hi! Looking for something?'), Caption(Role.customer, 'Headphones')]);
      await tester.pumpWidget(host(GraineAgentBar(call: call, chat: chat, showComponents: false, design: designs[0])));
      await tester.pump(const Duration(seconds: 1));
      final window = find.descendant(of: find.byKey(GraineAgentBar.chatKey), matching: find.byType(Container)).first;
      final frame = decorationOf(tester, window);
      expect(frame.color, hex(t.colors.background));
      expect(frame.borderRadius, BorderRadius.circular(t.shape.radius.xl));
      expect(frame.border, Border.all(color: hex(t.colors.border), width: t.shape.borderWidth));
      expect(frame.boxShadow, <BoxShadow>[soft(t.elevation.floating!)]);

      final header = find.byKey(ChatWindow.headerKey);
      expect(tester.getSize(header).height + t.shape.borderWidth, 50);
      expect(fillOf(tester, header).color, hex(t.colors.surface));
      final title = tester.widget<Text>(find.descendant(of: header, matching: find.text('Asha'))).style!;
      expect(title.fontSize, 16, reason: 'min(font.scale.title, 16)');
      expect(title.fontWeight, FontWeight.w600, reason: 'the heading family at weights.title');
      final dot = find.descendant(of: header, matching: find.byWidgetPredicate((Widget w) =>
          w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).shape == BoxShape.circle));
      expect(tester.getSize(dot), const Size(6, 6));
      expect(decorationOf(tester, dot).color, hex(t.colors.success));
      final status = tester.widgetList<Text>(find.descendant(of: header, matching: find.text('Online'))).single.style!;
      expect(status.color, hex(t.colors.textMuted));
      expect(status.fontSize, t.font.scale.caption);
      expect(icon(tester, 'chevron').turned, isTrue, reason: 'drawn pointing up; the header turns it down');
      expect(icon(tester, 'chevron').color, hex(t.colors.textMuted));
      final glyph = find.descendant(of: header, matching: find.byKey(BrandMark.glyphKey));
      expect(tester.getSize(glyph), const Size(14, 14));
      final mark = find.ancestor(of: glyph, matching: find.byType(Container)).first;
      expect(tester.getSize(mark), const Size(30, 30));
      expect(decorationOf(tester, mark).color, hex(t.colors.accent));
      expect(decorationOf(tester, mark).borderRadius, BorderRadius.circular(15), reason: 'the launcher shape: a circle');

      final agent = decorationOf(tester, find.byKey(ChatWindow.messageKey(0)));
      final customer = decorationOf(tester, find.byKey(ChatWindow.messageKey(1)));
      expect(agent.color, hex(t.colors.agentBubble));
      expect(customer.color, hex(t.colors.userBubble));
      expect(customer.borderRadius, BorderRadius.only(
        topLeft: Radius.circular(t.shape.radius.lg),
        topRight: Radius.circular(t.shape.radius.lg),
        bottomLeft: Radius.circular(t.shape.radius.lg),
        bottomRight: Radius.circular(t.shape.radius.sm),
      ));
      expect(styleOf(tester, 'Headphones').color, hex(t.colors.userBubbleText));

      final field = find.byKey(ChatWindow.composerKey);
      expect(tester.getSize(field).height, 40);
      expect(decorationOf(tester, field).color, hex(t.colors.surfaceRaised));
      expect(decorationOf(tester, field).borderRadius, BorderRadius.circular(t.shape.radius.xl));
      expect(find.text('Message…'), findsOneWidget);
      expect(styleOf(tester, 'Message…').color, hex(t.colors.textMuted));
      final send = find.byKey(ChatWindow.sendKey);
      expect(tester.getSize(send), const Size(40, 40));
      expect(fillOf(tester, send).color, hex(t.colors.accent));
      expect(icon(tester, 'send').color, hex(t.colors.onAccent));
      expect(tester.getSize(find.ancestor(of: field, matching: find.byType(Container)).first).height, 58,
          reason: 'the composer row');
      expect(find.text('Online'), findsNWidgets(2), reason: "the chat's status on the bar too");
    });

    testWidgets("the design's typeface, fetched by the SDK and drawn as its own weight; never fetched twice",
        (WidgetTester tester) async {
      final neo = preset('neo-brutalism');
      final want = (caseOf('neo-brutalism')['fontFaces']! as List<Object?>).cast<Map<String, Object?>>();
      final requests = <String>[];
      final registered = <String>[];
      addTearDown(GraineInApp.resetForTesting);
      GraineInApp.forTesting(
        const GraineConfig(baseUrl: base, publishableKey: 'pk_test_1'),
        install: true,
        httpClient: MockClient((http.Request req) async {
          requests.add(req.url.toString());
          return http.Response.bytes(ttf, 200);
        }),
        fontRegistrar: (String name, Uint8List bytes) async => registered.add(name),
      );
      final call = FakeCall();
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false, design: neo)));
      final before = styleOf(tester, 'Assistant');
      expect(before.fontFamily, isNull, reason: 'until it lands: the platform font');
      expect(before.fontWeight, FontWeight.w700, reason: 'at the weight the design asked for');
      await tester.pump();
      await tester.pump();

      expect(requests.toSet(), <String>{for (final f in want) f['url']! as String});
      expect(requests, hasLength(want.length));
      expect(registered.toSet(), <String>{for (final f in want) f['name']! as String});
      final name = styleOf(tester, 'Assistant');
      expect(name.fontFamily, 'Graine-DMSans-700');
      expect(name.fontWeight, FontWeight.normal, reason: 'a loaded face IS its weight');
      final status = styleOf(tester, 'Tap to talk');
      expect(status.fontFamily, 'Graine-DMSans-500');
      expect(status.fontWeight, FontWeight.normal);
      expect(GraineInApp.instance.fontFaces.value,
          <String, String>{'DM Sans|500': 'Graine-DMSans-500', 'DM Sans|700': 'Graine-DMSans-700'});

      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false, design: neo, key: UniqueKey())));
      await GraineInApp.instance.loadDesignFonts(neo);
      await tester.pump();
      expect(requests, hasLength(want.length), reason: 'each face is fetched once');
    });

    testWidgets('a face that is not a font, or never arrives, leaves the text in the platform font — silently',
        (WidgetTester tester) async {
      final neo = preset('neo-brutalism');
      final registered = <String>[];
      addTearDown(GraineInApp.resetForTesting);
      GraineInApp.forTesting(
        const GraineConfig(baseUrl: base, publishableKey: 'pk_test_1'),
        install: true,
        httpClient: MockClient((http.Request req) async =>
            req.url.queryParameters['w'] == '700' ? http.Response('<html>oops</html>', 200) : http.Response('', 404)),
        fontRegistrar: (String name, Uint8List bytes) async => registered.add(name),
      );
      await tester.pumpWidget(host(GraineAgentBar(call: FakeCall(), showComponents: false, design: neo)));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(registered, isEmpty);
      expect(styleOf(tester, 'Assistant').fontFamily, isNull);
      expect(styleOf(tester, 'Assistant').fontWeight, FontWeight.w700);
    });

    testWidgets("the app's own copy of a family wins, and is never fetched", (WidgetTester tester) async {
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
      final requests = <String>[];
      final client = MockClient((http.Request req) async {
        requests.add(req.url.toString());
        return http.Response('', 404);
      });
      addTearDown(GraineInApp.resetForTesting);

      GraineInApp.forTesting(const GraineConfig(baseUrl: base, publishableKey: 'pk_test_1'),
          install: true, httpClient: client);
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false, design: design)));
      await tester.pump();
      expect(styleOf(tester, 'Tap to talk').fontFamily, isNull, reason: 'not bundled and not arrived: the platform font');
      expect(requests, contains('$base/api/embed/font?f=Inter&w=400&v=1'), reason: 'so the SDK fetches it');

      GraineInApp.resetForTesting();
      requests.clear();
      GraineInApp.forTesting(const GraineConfig(baseUrl: base, publishableKey: 'pk_test_1', fonts: <String>['inter']),
          install: true, httpClient: client);
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false, design: design, key: UniqueKey())));
      await tester.pump();
      expect(styleOf(tester, 'Tap to talk').fontFamily, 'inter');
      expect(styleOf(tester, 'Tap to talk').fontWeight, FontWeight.w400, reason: "the app's family, at the weight");
      expect(styleOf(tester, 'Assistant').fontFamily, 'inter');
      expect(requests, isEmpty, reason: "the app's own file wins; nothing to fetch");
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

          // The bar: 60 high on surface (translucent with glass), radius.xl,
          // the floating shadow — or the solid offset — or none.
          final bar = fillOf(tester, find.byKey(GraineAgentBar.barKey));
          final surface = hex(t.colors.surface);
          expect(bar.color, t.glass == null ? surface : faded(surface, t.glass!.surfaceOpacity), reason: why);
          expect(bar.borderRadius, BorderRadius.circular(t.shape.radius.xl), reason: why);
          expect(tester.getSize(find.byKey(GraineAgentBar.barKey)).height, 60, reason: why);
          expect(find.descendant(of: find.byKey(GraineAgentBar.barKey), matching: find.byType(BackdropFilter)),
              t.glass == null ? findsNothing : findsOneWidget,
              reason: why);
          final hard = t.elevation.hardOffset;
          expect(
              shadowsOn(tester, find.byKey(GraineAgentBar.barKey)),
              hard != null
                  ? <BoxShadow>[BoxShadow(color: hex(t.colors.text), offset: Offset(hard.x, hard.y))]
                  : <BoxShadow>[if (t.elevation.floating != null) soft(t.elevation.floating!)],
              reason: why);
          // The customer spoke last: the agent is working out its answer.
          expect(styleOf(tester, 'Thinking…').color, hex(t.colors.textMuted), reason: why);
          expect(
              tester
                  .widget<Text>(find.descendant(of: find.byKey(GraineAgentBar.barKey), matching: find.text('Assistant')))
                  .style!
                  .fontSize,
              14,
              reason: why);
          expect(fillOf(tester, find.byKey(GraineAgentBar.callButtonKey)).color, hex(t.colors.danger), reason: why);
          expect(icon(tester, 'mic').style, t.icons.style, reason: why);
          expect(icon(tester, 'mic').stroke, t.icons.stroke, reason: why);

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

  group('every design on a small phone', () {
    testWidgets('the bar, the caption and the chat window fit 320 points in every state, light and dark',
        (WidgetTester tester) async {
      for (final c in all) {
        final design = ResolvedDesign.fromJson(c['design'])!;
        final name = (c['config']! as Map<String, Object?>)['preset'];
        for (final device in <Brightness>[Brightness.light, Brightness.dark]) {
          final call = FakeCall()
            ..appearance = const <String, Object?>{
              'mode': 'both',
              'title': 'Priya from Northwind Home Loans',
              'loader': <String, Object?>{
                'text': <String, Object?>{'connecting': 'Connecting you to a specialist now'},
              },
            };
          final chat = FakeChat(const <Caption>[
            Caption(Role.agent, 'Hi! I can compare the two plans for you, side by side, with the fees.'),
            Caption(Role.customer, 'Yes please, and the prepayment charges too'),
          ]);
          final states = <String, void Function()>{
            'idle': () {},
            'connecting': () => call.connecting = true,
            'on a call': () {
              call
                ..connecting = false
                ..connected = true
                ..captions = const <Caption>[
                  Caption(Role.customer, 'Can you tell me what the prepayment charges are on the second plan?'),
                ];
            },
          };
          for (final state in states.entries) {
            state.value();
            await tester.pumpWidget(MediaQuery(
              data: MediaQueryData(size: const Size(320, 640), platformBrightness: device),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Stack(children: <Widget>[
                  GraineAgentBar(call: call, chat: chat, showComponents: false, design: design, key: UniqueKey()),
                ]),
              ),
            ));
            await tester.pump(const Duration(seconds: 1));
            expect(tester.takeException(), isNull, reason: '$name, ${device.name}, ${state.key}');
          }
          // And the chat.
          await tester.tap(find.byKey(GraineAgentBar.switchButtonKey));
          await tester.pump(const Duration(seconds: 1));
          expect(find.byKey(GraineAgentBar.chatKey), findsOneWidget);
          expect(tester.takeException(), isNull, reason: '$name, ${device.name}, in the chat');
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
