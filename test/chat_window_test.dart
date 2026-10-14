// The chat window drawn as contract/DESIGN.md ("Chat window") says, from the
// real sessions' tokens in sdk/contract/design.json: the header (an accent
// header's own dot, no glass on it, the chevron in headerSubtext), the avatar's
// fallbacks, the empty chat, the starters, timestamps, the dot grid, and the
// Upcoming calls card with its Cancel. From an older server it is the window
// it always was.
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graine_inapp/graine_inapp.dart';
import 'package:graine_inapp/src/chat_window.dart';
import 'package:graine_inapp/src/glyph.dart';
import 'package:graine_inapp/src/sdk_icon.dart';

import 'contract_files.dart';

Color hex(String h) => Color(int.parse('FF${h.substring(1)}', radix: 16));

BoxDecoration decorationOf(WidgetTester tester, Finder f) =>
    tester.widget<Container>(f).decoration! as BoxDecoration;

void main() {
  late List<Map<String, Object?>> cases;
  setUpAll(() async {
    final fx = await contractJson('contract/design.json');
    cases = (fx['cases']! as List<Object?>).cast<Map<String, Object?>>();
  });

  /// The design.json case whose `config.chat` passes [test].
  ResolvedDesign chatCase(bool Function(Map<String, Object?> chat) test) {
    final c = cases.firstWhere((Map<String, Object?> c) {
      final chat = (c['config']! as Map<String, Object?>)['chat'];
      return chat is Map<String, Object?> && test(chat);
    });
    return ResolvedDesign.fromJson(c['design'])!;
  }

  ResolvedDesign preset(String id) => ResolvedDesign.fromJson(cases.firstWhere((Map<String, Object?> c) {
        final config = c['config']! as Map<String, Object?>;
        return config.length == 1 && config['preset'] == id;
      })['design'])!;

  Widget host(Widget window, {bool h24 = false}) => MediaQuery(
        data: MediaQueryData(size: const Size(400, 800), alwaysUse24HourFormat: h24),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Align(alignment: Alignment.bottomCenter, child: window),
        ),
      );

  ChatWindow window(
    ThemeTokens t, {
    List<GraineChatTurn> turns = const <GraineChatTurn>[],
    bool online = true,
    ValueChanged<String>? onSend,
    String? logoUrl,
    List<GraineScheduledCall> upcoming = const <GraineScheduledCall>[],
    GraineUpcomingCancel Function(String id)? cancelStateOf,
    ValueChanged<String>? onCancel,
    DateTime Function()? now,
    bool fill = false,
    VoidCallback? onNewConversation,
  }) =>
      ChatWindow(
        look: ChatLook.design(t),
        heading: 'Assistant',
        messages: <Caption>[for (final x in turns) x.caption],
        turns: turns,
        online: online,
        onSend: onSend ?? (String _) {},
        onCollapse: () {},
        logoUrl: logoUrl,
        upcoming: upcoming,
        cancelStateOf: cancelStateOf,
        onCancelUpcoming: onCancel,
        callName: 'Asha · Acme Care',
        now: now,
        fill: fill,
        onNewConversation: onNewConversation,
      );

  testWidgets('an accent header: the title and its dot in headerText, the status and chevron in headerSubtext, solid',
      (WidgetTester tester) async {
    final t = chatCase((Map<String, Object?> chat) => chat['header'] == 'accent').light;
    expect(t.chat.headerBackground, isNot(t.colors.surface), reason: 'the fixture must hold an accent header');
    final hi = <GraineChatTurn>[GraineChatTurn(id: 't1', role: GraineChatRole.agent, text: 'Hi!', at: DateTime(2026, 10, 13, 21, 41))];
    await tester.pumpWidget(host(window(t, turns: hi)));
    final header = find.byKey(ChatWindow.headerKey);
    final fill = tester.widget<Container>(find.descendant(of: header, matching: find.byType(Container)).first);
    expect((fill.decoration! as BoxDecoration).color, hex(t.chat.headerBackground));
    expect(tester.widget<Text>(find.text(t.chat.title)).style!.color, hex(t.chat.headerText));
    final dot = find.descendant(of: header, matching: find.byWidgetPredicate((Widget w) =>
        w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).shape == BoxShape.circle));
    expect(decorationOf(tester, dot).color, hex(t.chat.headerText), reason: 'not success on an accent header');
    expect(tester.widget<Text>(find.text(t.chat.subtitle)).style!.color, hex(t.chat.headerSubtext));
    final chevron = tester.widget<SdkIconView>(
        find.descendant(of: find.byKey(ChatWindow.collapseKey), matching: find.byType(SdkIconView)));
    expect(chevron.color, hex(t.chat.headerSubtext));
    expect(find.text(t.chat.placeholder), findsOneWidget);
    expect(find.text('9:41 PM'), findsOneWidget, reason: 'timestamps on, in the device short time');
    await tester.pumpWidget(host(window(t, turns: hi), h24: true));
    expect(find.text('21:41'), findsOneWidget, reason: 'a 24-hour device');
  });

  testWidgets('the avatar: the logo; with none uploaded the glyph; else the title\'s letter; none is nothing',
      (WidgetTester tester) async {
    final classic = preset('graine-classic').light;
    expect(classic.chat.avatar, 'logo');
    await tester.pumpWidget(host(window(classic)));
    expect(find.descendant(of: find.byKey(ChatWindow.avatarKey), matching: find.byKey(BrandMark.glyphKey)), findsOneWidget,
        reason: 'no logo uploaded: the launcher glyph');

    final noGlyph = ThemeTokens.fromJson(<String, Object?>{
      ...classic.toJson(),
      'icons': <String, Object?>{'style': 'outline', 'stroke': 2, 'launcher': null},
    })!;
    await tester.pumpWidget(host(window(noGlyph)));
    expect(find.descendant(of: find.byKey(ChatWindow.avatarKey), matching: find.text('A')), findsOneWidget,
        reason: "no logo, no glyph: the title's first letter");

    final none = chatCase((Map<String, Object?> chat) => chat['avatar'] == 'none').light;
    await tester.pumpWidget(host(window(none)));
    expect(find.byKey(ChatWindow.avatarKey), findsNothing);
  });

  testWidgets('the empty chat: the avatar at 48, the title, the subtitle only when written; an older server says its sentence',
      (WidgetTester tester) async {
    final t = chatCase((Map<String, Object?> chat) => chat['header'] == 'accent').light;
    await tester.pumpWidget(host(window(t)));
    final empty = find.byKey(ChatWindow.emptyKey);
    expect(empty, findsOneWidget);
    expect(find.descendant(of: empty, matching: find.text(t.chat.title)), findsOneWidget);
    expect(find.descendant(of: empty, matching: find.text(t.chat.subtitle)), findsOneWidget);
    final mark = find.descendant(of: empty, matching: find.byType(Container)).first;
    expect(tester.getSize(mark), const Size(48, 48));

    final classic = preset('graine-classic').light;
    await tester.pumpWidget(host(window(classic)));
    expect(find.descendant(of: find.byKey(ChatWindow.emptyKey), matching: find.text('Online')), findsNothing,
        reason: 'no subtitle written: none under the title, and no dot');

    final older = ThemeTokens.fromJson(<String, Object?>{...classic.toJson()}..remove('chat'))!;
    await tester.pumpWidget(host(window(older)));
    expect(find.byKey(ChatWindow.emptyKey), findsNothing);
    expect(find.text('Assistant can see what you’re looking at — ask it anything.'), findsOneWidget);
  });

  testWidgets('the starters: right-aligned chips 34 high outlined in the accent; a tap sends the words', (WidgetTester tester) async {
    final t = chatCase((Map<String, Object?> chat) => chat['header'] == 'accent').light;
    expect(t.chat.suggestions, isNotEmpty);
    final sent = <String>[];
    await tester.pumpWidget(host(window(t, onSend: sent.add)));
    final chip = find.descendant(of: find.byKey(ChatWindow.suggestionKey(0)), matching: find.byType(Container)).first;
    expect(tester.getSize(chip).height, 34);
    final d = decorationOf(tester, chip);
    expect(d.color, hex(t.chat.background));
    expect((d.border! as Border).top.color, hex(t.colors.accent));
    final rights = <double>[
      for (var i = 0; i < t.chat.suggestions.length; i++)
        tester.getRect(find.descendant(of: find.byKey(ChatWindow.suggestionKey(i)), matching: find.byType(Container)).first).right,
    ];
    final inner = tester.getRect(find.byType(ChatWindow)).right - t.shape.borderWidth;
    expect(rights.reduce(math.max), closeTo(inner - 12, 0.01), reason: "on the customer's side, 12 from the edge");
    await tester.tap(find.byKey(ChatWindow.suggestionKey(0)));
    expect(sent, <String>[t.chat.suggestions.first]);
  });

  testWidgets('a conversation that continues: day lines, one row per call, no starters, "New conversation" in the header',
      (WidgetTester tester) async {
    final t = chatCase((Map<String, Object?> chat) => chat['header'] == 'accent').light;
    expect(t.chat.suggestions, isNotEmpty);
    DateTime now() => DateTime(2026, 10, 14, 12);
    GraineChatTurn earlier(String id, GraineChatRole role, String text, DateTime at, {bool voice = false}) => GraineChatTurn(
        id: id, role: role, text: text, at: at, restored: true, channel: voice ? GraineChatChannel.voice : GraineChatChannel.chat);
    final turns = <GraineChatTurn>[
      earlier('h1', GraineChatRole.user, 'Is my order shipped?', DateTime(2026, 10, 13, 10)),
      earlier('h2', GraineChatRole.agent, 'Yes, it left this morning.', DateTime(2026, 10, 13, 10, 1)),
      earlier('h3', GraineChatRole.agent, 'Hi, this is Asha calling.', DateTime(2026, 10, 13, 18, 5), voice: true),
      earlier('h4', GraineChatRole.user, 'Hi Asha, about my order', DateTime(2026, 10, 13, 18, 6), voice: true),
      GraineChatTurn(id: 't1', role: GraineChatRole.agent, text: 'Anything else?', at: DateTime(2026, 10, 14, 9)),
    ];
    var started = 0;
    await tester.pumpWidget(host(window(t, turns: turns, now: now, onNewConversation: () => started++)));
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.byKey(ChatWindow.dayKey('2026-10-13')), findsOneWidget);
    expect(find.byKey(ChatWindow.voiceKey('h3')), findsOneWidget, reason: 'two voice turns are one row');
    expect(find.text('Voice call · 6:05 PM'), findsOneWidget);
    expect(find.text('Hi, this is Asha calling.'), findsNothing, reason: "the call's transcript is not the chat's");
    expect(find.text('Is my order shipped?'), findsOneWidget);
    expect(find.byKey(ChatWindow.emptyKey), findsNothing);
    expect(find.byKey(ChatWindow.suggestionsKey), findsNothing, reason: 'no starters on a conversation that continues');
    expect(find.byKey(ChatWindow.newConversationKey), findsOneWidget);
    await tester.tap(find.byKey(ChatWindow.newConversationKey));
    expect(started, 1);

    // A new chat: the starters, and nothing to start over from.
    await tester.pumpWidget(host(window(t, turns: <GraineChatTurn>[turns.last], now: now, onNewConversation: () => started++)));
    expect(find.byKey(ChatWindow.newConversationKey), findsNothing, reason: 'a live conversation is not an earlier one');
    expect(find.byKey(ChatWindow.suggestionsKey), findsOneWidget);
    expect(find.text('Today'), findsNothing, reason: 'a conversation all from today looks as it always did');
  });

  testWidgets('the dots: 2 across on an 18-point grid, the first 9 in, still while the thread scrolls',
      (WidgetTester tester) async {
    final t = chatCase((Map<String, Object?> chat) => chat['background'] == 'pattern').light;
    expect(t.chat.pattern, 'dots');
    await tester.pumpWidget(host(window(t)));
    final paints = find.byWidgetPredicate((Widget w) => w is CustomPaint && w.painter != null && w.painter.runtimeType.toString() == '_DotPattern');
    expect(paints, findsOneWidget);
  });

  testWidgets('the Upcoming calls card: soonest three, the time in the device zone, the call name, and Cancel with its states',
      (WidgetTester tester) async {
    final t = preset('graine-classic').light;
    final now = DateTime(2026, 10, 13, 9, 0);
    final calls = <GraineScheduledCall>[
      GraineScheduledCall(id: 'a', at: DateTime(2026, 10, 13, 17, 30).toUtc()),
      GraineScheduledCall(id: 'b', at: DateTime(2026, 10, 14, 9, 0).toUtc()),
      GraineScheduledCall(id: 'c', at: DateTime(2026, 10, 21, 10, 0).toUtc()),
      GraineScheduledCall(id: 'd', at: DateTime(2026, 10, 22, 10, 0).toUtc()),
    ];
    final states = <String, GraineUpcomingCancel>{'b': GraineUpcomingCancel.cancelling, 'c': GraineUpcomingCancel.failed};
    final cancelled = <String>[];
    await tester.pumpWidget(host(window(t,
        upcoming: calls,
        cancelStateOf: (String id) => states[id] ?? GraineUpcomingCancel.none,
        onCancel: cancelled.add,
        now: () => now,
        fill: true)));
    final card = find.byKey(ChatWindow.upcomingKey);
    expect(card, findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('Upcoming calls')), findsOneWidget);
    expect(find.text('Today, 5:30 PM'), findsOneWidget);
    expect(find.text('Cancelling…'), findsOneWidget);
    expect(find.text('Couldn’t cancel · tap to retry'), findsOneWidget);
    expect(find.byKey(ChatWindow.upcomingRowKey('d')), findsNothing, reason: 'at most three rows');
    expect(find.text('Asha · Acme Care'), findsNWidgets(3));
    final d = decorationOf(tester, card);
    expect(d.color, hex(t.colors.surfaceRaised));
    expect(d.borderRadius, BorderRadius.circular(t.shape.radius.lg));
    await tester.tap(find.byKey(ChatWindow.cancelKey('a')));
    await tester.tap(find.byKey(ChatWindow.cancelKey('b')));
    await tester.tap(find.byKey(ChatWindow.cancelKey('c')));
    expect(cancelled, <String>['a', 'c'], reason: 'one already cancelling is not asked twice; a failure retries');

    await tester.pumpWidget(host(window(t, upcoming: calls.sublist(1, 2), now: () => now)));
    expect(find.text('Upcoming call'), findsOneWidget, reason: 'one call');
    expect(find.text('Tomorrow, 9:00 AM'), findsOneWidget);
    await tester.pumpWidget(host(window(t, now: () => now)));
    expect(find.byKey(ChatWindow.upcomingKey), findsNothing, reason: 'no booked calls, no card');
  });

  test("a booked call's day, and the clock, as the device shows them", () {
    final now = DateTime(2026, 10, 13, 9, 0);
    expect(ChatTime.booked(DateTime(2026, 10, 13, 17, 30), now, h24: false), 'Today, 5:30 PM');
    expect(ChatTime.booked(DateTime(2026, 10, 14, 0, 5), now, h24: true), 'Tomorrow, 00:05');
    expect(ChatTime.booked(DateTime(2026, 10, 14, 10, 0), DateTime(2026, 10, 12, 23, 59), h24: false), 'Wed 14 Oct, 10:00 AM');
    expect(ChatTime.booked(DateTime(2027, 1, 1, 12, 0), DateTime(2026, 12, 31, 8, 0), h24: false), 'Tomorrow, 12:00 PM',
        reason: 'across the year');
    expect(ChatTime.clock(DateTime(2026, 10, 13, 0, 7), h24: false), '12:07 AM');
    expect(ChatTime.clock(DateTime(2026, 10, 13, 21, 41), h24: true), '21:41');
  });
}
