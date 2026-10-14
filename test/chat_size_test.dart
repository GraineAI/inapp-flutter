// HOW BIG THE CHAT OPENS — contract/DESIGN.md "Chat window" → Size: the
// design's `chat.size` (compact when absent or a word this build does not
// know), the open's size over the app's over the design's, where each size
// goes on a phone and a tablet — the same answers as the React Native SDK's
// chatSizeOf and chatPresentation — and the bar and GraineChat.open drawing
// it: the compact window above the bar, a sheet over the dimmed app with its
// grab handle, a tablet's 420-wide panel, the whole screen with the chevron
// leading the header. Closing any of them does what the chevron does.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graine_inapp/graine_inapp.dart';
import 'package:graine_inapp/src/chat_frames.dart';
import 'package:graine_inapp/src/chat_window.dart';
import 'package:graine_inapp/src/core/core.dart' show ChatClose, ChatPresentation, ChatWindowLayout;

import 'contract_files.dart';

/// The call as the bar sees it.
class FakeCall extends ChangeNotifier implements GraineCallState {
  FakeCall(this.appearance);
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
  Map<String, Object?> appearance;
  @override
  Caption? get caption => captions.isEmpty ? null : captions.last;
  int ends = 0;
  @override
  Future<void> start() async {}
  @override
  void end() => ends++;
  @override
  void setMuted(bool muted) {}
  @override
  void retry() {}
}

/// A chat the app runs itself.
class FakeChat extends ChangeNotifier implements GraineChatState {
  @override
  List<Caption> messages = const <Caption>[];
  @override
  bool connected = true;
  @override
  void send(String text) {}
}

/// The test's screen at [size], 1:1, with a phone's status bar and home indicator.
void screenOf(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
  addTearDown(tester.view.reset);
}

void main() {
  late List<Map<String, Object?>> cases;
  setUpAll(() async {
    final fx = await contractJson('contract/design.json');
    cases = (fx['cases']! as List<Object?>).cast<Map<String, Object?>>();
  });

  /// The contract's design whose chat opens at [size] (compact: Graine Classic as it comes).
  ResolvedDesign designOf(GraineChatSize size) => ResolvedDesign.fromJson(cases.firstWhere((Map<String, Object?> c) {
        final light = (c['design']! as Map<String, Object?>)['light']! as Map<String, Object?>;
        return (light['chat']! as Map<String, Object?>)['size'] == size.wire;
      })['design'])!;

  group('the token and the rule', () {
    test('every design says its size, the same in light and dark', () {
      final seen = <GraineChatSize>{};
      for (final c in cases) {
        final raw = c['design']! as Map<String, Object?>;
        final d = ResolvedDesign.fromJson(raw)!;
        for (final (scheme, t) in <(String, ThemeTokens)>[('light', d.light), ('dark', d.dark)]) {
          final served = ((raw[scheme]! as Map<String, Object?>)['chat']! as Map<String, Object?>)['size'];
          expect(t.chat.size.wire, served, reason: scheme);
          seen.add(t.chat.size);
        }
        expect(d.light.chat.size, d.dark.chat.size);
      }
      expect(seen, GraineChatSize.values.toSet(), reason: 'the contract has a design of each size');
    });

    test('absent, unknown or not a word is compact; the size is written back with the design', () {
      final classic = designOf(GraineChatSize.compact).light;
      ThemeChat chat(Object? size) => ThemeChat.fromJson(<String, Object?>{if (size != null) 'size': size}, classic.chat);
      expect(chat(null).size, GraineChatSize.compact, reason: 'an older server says nothing');
      for (final odd in <Object?>['cinema', '', 'LARGEST', 3, true, <String>['full']]) {
        expect(chat(odd).size, GraineChatSize.compact, reason: '$odd');
      }
      expect(chat(' Large ').size, GraineChatSize.large);
      expect(chat('full').size, GraineChatSize.full);
      expect(GraineChatSize.fromWire('huge'), isNull);
      expect(GraineChatSize.values.map((GraineChatSize s) => s.wire), <String>['compact', 'large', 'full']);
      final full = designOf(GraineChatSize.full);
      expect(ResolvedDesign.fromJson(full.toJson())!.light.chat.size, GraineChatSize.full, reason: 'kept with the cached design');
    });

    test("the open's size, then the app's, then the design's", () {
      expect(ChatWindowLayout.size(open: GraineChatSize.full, config: GraineChatSize.large, token: GraineChatSize.compact),
          GraineChatSize.full);
      expect(ChatWindowLayout.size(config: GraineChatSize.large, token: GraineChatSize.full), GraineChatSize.large);
      expect(ChatWindowLayout.size(token: GraineChatSize.full), GraineChatSize.full);
      expect(ChatWindowLayout.size(), GraineChatSize.compact);
      expect(const GraineConfig(baseUrl: 'https://www.graine.ai', publishableKey: 'pk').chatSize, isNull);
      expect(const GraineConfig(baseUrl: 'https://www.graine.ai', publishableKey: 'pk', chatSize: GraineChatSize.large).chatSize,
          GraineChatSize.large);
    });

    test('where phones and tablets put each size', () {
      for (final (w, h) in <(double, double)>[(390, 844), (844, 390), (820, 1180)]) {
        expect(ChatWindowLayout.presentation(GraineChatSize.compact, w, h), ChatPresentation.window);
        expect(ChatWindowLayout.presentation(GraineChatSize.full, w, h), ChatPresentation.screen, reason: "a tablet's too");
      }
      expect(ChatWindowLayout.presentation(GraineChatSize.large, 390, 844), ChatPresentation.sheet);
      expect(ChatWindowLayout.presentation(GraineChatSize.large, 844, 390), ChatPresentation.sheet, reason: 'a phone on its side');
      expect(ChatWindowLayout.presentation(GraineChatSize.large, 820, 1180), ChatPresentation.panel);
      expect(ChatWindowLayout.presentation(GraineChatSize.large, 600, 1000), ChatPresentation.panel, reason: '600 across is a tablet');
      expect(ChatWindowLayout.presentation(GraineChatSize.large, 599, 1000), ChatPresentation.sheet);
      expect(ChatWindowLayout.panelSize(1180), (width: 420.0, height: 760.0));
      expect(ChatWindowLayout.panelSize(700), (width: 420.0, height: 630.0));
      expect(ChatWindowLayout.barPresentation(inChat: false, open: GraineChatSize.full, width: 390, height: 844), isNull);
      expect(ChatWindowLayout.close(canSwitch: true), ChatClose.backToCall);
      expect(ChatWindowLayout.close(canSwitch: false), ChatClose.closeBar);
      expect(ChatWindowLayout.dragCloses(120, 0), isTrue);
      expect(ChatWindowLayout.dragCloses(20, 1500), isTrue);
      expect(ChatWindowLayout.dragCloses(40, 200), isFalse);
    });
  });

  group('the bar draws the size', () {
    const phone = Size(390, 844);
    const tablet = Size(820, 1180);

    Widget host(WidgetTester tester, Widget child, {Size size = phone}) {
      screenOf(tester, size);
      return MediaQuery(
        data: MediaQueryData(size: size, padding: const EdgeInsets.only(top: 47, bottom: 34)),
        child: Directionality(textDirection: TextDirection.ltr, child: Stack(children: <Widget>[child])),
      );
    }

    Future<({FakeCall call, List<String> closed})> mount(WidgetTester tester, GraineChatSize size,
        {String mode = 'chat', Size screen = phone, GraineChatSize? override}) async {
      final call = FakeCall(<String, Object?>{'title': 'Asha', 'mode': mode, 'start': 'chat'});
      final closed = <String>[];
      final design = designOf(size);
      await tester.pumpWidget(host(
        tester,
        GraineAgentBar(
          call: call,
          chat: FakeChat(),
          design: design,
          showComponents: false,
          onClose: () => closed.add('closed'),
        ),
        size: screen,
      ));
      // The compact window's rise, done.
      await tester.pump(const Duration(seconds: 1));
      return (call: call, closed: closed);
    }

    testWidgets('compact: the window above the bar, as before', (WidgetTester tester) async {
      await mount(tester, GraineChatSize.compact);
      expect(find.byKey(GraineAgentBar.chatKey), findsOneWidget);
      expect(find.byKey(chatOverScreenKey), findsNothing);
      expect(tester.getBottomLeft(find.byKey(GraineAgentBar.chatKey)).dy, lessThan(tester.getTopLeft(find.byKey(GraineAgentBar.barKey)).dy + 1),
          reason: 'above the bar');
    });

    testWidgets('large on a phone: a sheet, its top 8% of the screen below the status bar, over the dimmed app',
        (WidgetTester tester) async {
      final m = await mount(tester, GraineChatSize.large);
      expect(find.byKey(chatOverScreenKey), findsOneWidget);
      final sheet = find.byKey(ChatSheetFrame.sheetKey);
      expect(sheet, findsOneWidget);
      expect(tester.getTopLeft(sheet).dy, closeTo(47 + 0.08 * 844, 0.01));
      expect(tester.getSize(sheet).width, 390, reason: 'the full width');
      expect(tester.getBottomLeft(sheet).dy, 844, reason: 'to the bottom edge');
      expect(find.byKey(ChatSheetFrame.handleKey), findsOneWidget, reason: 'its grab handle');
      expect(tester.getSize(find.byKey(ChatSheetFrame.handleKey)).height, ChatWindowLayout.handleStrip);
      final t = designOf(GraineChatSize.large).light;
      final frame = tester.widget<AnimatedContainer>(sheet).decoration! as BoxDecoration;
      expect(frame.borderRadius, BorderRadius.vertical(top: Radius.circular(t.shape.radius.xl)), reason: 'top corners only');
      // A tap on the dimmed app closes it: a chat-only agent's bar closes.
      await tester.tapAt(const Offset(195, 40));
      await tester.pump();
      expect(m.closed, <String>['closed']);
    });

    testWidgets('a sheet dragged down by its handle closes; a nudge settles back', (WidgetTester tester) async {
      final m = await mount(tester, GraineChatSize.large);
      await tester.drag(find.byKey(ChatSheetFrame.handleKey), const Offset(0, 30));
      await tester.pumpAndSettle();
      expect(m.closed, isEmpty, reason: 'a short drag settles back');
      await tester.drag(find.byKey(ChatSheetFrame.handleKey), const Offset(0, 160));
      await tester.pumpAndSettle();
      expect(m.closed, <String>['closed']);
    });

    testWidgets('with a call to go back to, closing a sheet goes back to it, and the chat opens as a sheet again',
        (WidgetTester tester) async {
      await mount(tester, GraineChatSize.large, mode: 'both');
      expect(find.byKey(ChatSheetFrame.sheetKey), findsOneWidget);
      await tester.tap(find.byKey(ChatWindow.collapseKey));
      await tester.pump();
      expect(find.byKey(chatOverScreenKey), findsNothing);
      expect(find.byKey(GraineAgentBar.switchButtonKey), findsOneWidget, reason: 'back on the call');
      await tester.tap(find.byKey(GraineAgentBar.switchButtonKey));
      await tester.pump();
      expect(find.byKey(ChatSheetFrame.sheetKey), findsOneWidget, reason: 'the size is kept');
    });

    testWidgets('full on a phone: the whole screen, the chevron leading the header', (WidgetTester tester) async {
      final m = await mount(tester, GraineChatSize.full);
      expect(find.byKey(chatOverScreenKey), findsOneWidget);
      expect(find.byKey(ChatSheetFrame.sheetKey), findsNothing);
      expect(tester.getSize(find.byKey(chatOverScreenKey)), phone);
      final chevron = tester.getTopLeft(find.byKey(ChatWindow.collapseKey));
      // This design draws no avatar ("none"): the title is the first thing after the chevron.
      final title = tester.getTopLeft(
          find.descendant(of: find.byKey(ChatWindow.headerKey), matching: find.text(designOf(GraineChatSize.full).light.chat.title)));
      expect(chevron.dx, lessThan(title.dx), reason: 'before the title');
      expect(chevron.dy, greaterThanOrEqualTo(47), reason: 'below the status bar');
      await tester.tap(find.byKey(ChatWindow.collapseKey));
      await tester.pump();
      expect(m.closed, <String>['closed']);
    });

    testWidgets("a tablet: large is a 420-wide panel in the corner; full is still the screen", (WidgetTester tester) async {
      await mount(tester, GraineChatSize.large, screen: tablet);
      expect(find.byKey(ChatSheetFrame.sheetKey), findsNothing, reason: 'no sheet, no scrim');
      final panel = find.byKey(chatPanelKey);
      expect(tester.getSize(panel), const Size(420, 760));
      expect(tester.getBottomRight(panel), const Offset(820 - 24, 1180 - 24 - 34));
      await mount(tester, GraineChatSize.full, screen: tablet);
      expect(tester.getSize(find.byKey(chatOverScreenKey)), tablet);
    });

    testWidgets('GraineChat.open with the bar on screen: the bar moves to the chat at that size, until it closes',
        (WidgetTester tester) async {
      final call = FakeCall(<String, Object?>{'title': 'Asha', 'mode': 'both', 'start': 'voice'});
      late BuildContext context;
      await tester.pumpWidget(host(tester, Builder(builder: (BuildContext c) {
        context = c;
        return GraineAgentBar(call: call, chat: FakeChat(), design: designOf(GraineChatSize.compact), showComponents: false);
      })));
      expect(find.byKey(GraineAgentBar.chatKey), findsNothing, reason: 'on the call');
      var done = false;
      GraineChat.open(context, size: GraineChatSize.full).then((_) => done = true);
      await tester.pump();
      expect(find.byKey(chatOverScreenKey), findsOneWidget, reason: 'the whole screen, over the design\'s compact');
      await tester.tap(find.byKey(ChatWindow.collapseKey));
      await tester.pump();
      expect(find.byKey(chatOverScreenKey), findsNothing);
      expect(done, isTrue, reason: 'the open completes when the chat window closes');
    });
  });

  group('GraineChat.open with no bar', () {
    Widget app(Size size, Widget home) => MediaQuery(
          data: MediaQueryData(size: size, padding: const EdgeInsets.only(top: 47, bottom: 34)),
          child: WidgetsApp(
            color: const Color(0xFF000000),
            pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
                PageRouteBuilder<T>(settings: settings, pageBuilder: (BuildContext c, _, __) => builder(c)),
            home: home,
          ),
        );

    Future<BuildContext> start(WidgetTester tester, Size size) async {
      screenOf(tester, size);
      late BuildContext context;
      await tester.pumpWidget(app(size, Builder(builder: (BuildContext c) {
        context = c;
        return const SizedBox.expand();
      })));
      return context;
    }

    testWidgets('large is a sheet; compact, which rides on the bar, is a sheet too', (WidgetTester tester) async {
      for (final size in <GraineChatSize>[GraineChatSize.large, GraineChatSize.compact]) {
        final context = await start(tester, const Size(390, 844));
        GraineChat.open(context, size: size);
        await tester.pumpAndSettle();
        expect(find.byKey(ChatSheetFrame.sheetKey), findsOneWidget, reason: size.wire);
        expect(tester.getTopLeft(find.byKey(ChatSheetFrame.sheetKey)).dy, closeTo(47 + 0.08 * 844, 0.01));
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets("a tablet's large is the panel; full is a screen of its own", (WidgetTester tester) async {
      var context = await start(tester, const Size(820, 1180));
      GraineChat.open(context, size: GraineChatSize.large);
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(chatPanelKey)), const Size(420, 760));
      await tester.pumpWidget(const SizedBox());

      context = await start(tester, const Size(390, 844));
      GraineChat.open(context, size: GraineChatSize.full);
      await tester.pumpAndSettle();
      expect(find.byType(ChatFrameScope), findsOneWidget, reason: 'a route of its own, leading with its chevron');
      expect(find.byKey(ChatSheetFrame.sheetKey), findsNothing);
    });

    testWidgets("GraineChat in a full screen of its own leads with its chevron", (WidgetTester tester) async {
      screenOf(tester, const Size(390, 844));
      Widget chat({required bool leads}) => MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: ChatFrameScope(
                leadingChevron: leads,
                child: GraineChat(chat: FakeChat(), design: designOf(GraineChatSize.compact), onClose: () {}),
              ),
            ),
          );
      await tester.pumpWidget(chat(leads: true));
      expect(tester.getTopLeft(find.byKey(ChatWindow.collapseKey)).dx, lessThan(tester.getTopLeft(find.byKey(ChatWindow.avatarKey)).dx));
      await tester.pumpWidget(chat(leads: false));
      expect(tester.getTopLeft(find.byKey(ChatWindow.collapseKey)).dx, greaterThan(tester.getTopLeft(find.byKey(ChatWindow.avatarKey)).dx),
          reason: 'GraineChat as an app places it: the chevron at the end, as before');
    });
  });
}
