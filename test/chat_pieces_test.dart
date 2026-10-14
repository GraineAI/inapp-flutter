// THE PIECES THE GARAGE SETS (contract/DESIGN.md, "Chat window" → Booked
// calls, Earlier messages, New conversation): the four chat tokens as the
// session serves them — on, and the SDK's words, when absent or of the wrong
// type — what the chat window draws of them, run against
// sdk/contract/history.json → `display` (the same cases every SDK runs), and
// the window honouring each.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graine_inapp/graine_inapp.dart';
import 'package:graine_inapp/src/chat_window.dart';

import 'contract_files.dart';

DateTime _at(String iso) => DateTime.parse(iso);

void main() {
  late List<Map<String, Object?>> designs;
  late List<Map<String, Object?>> display;
  setUpAll(() async {
    designs = ((await contractJson('contract/design.json'))['cases']! as List<Object?>).cast<Map<String, Object?>>();
    display = ((await contractJson('contract/history.json'))['display']! as List<Object?>).cast<Map<String, Object?>>();
  });

  ResolvedDesign designOf(Map<String, Object?> c) => ResolvedDesign.fromJson(c['design'])!;
  ThemeTokens plain() => designOf(designs.first).light;
  ThemeChat fallback() => ThemeChat.fallback(plain().colors, dark: false, hasGlyph: false);

  group('the tokens', () {
    test('read as the session serves them, the same in light and dark', () {
      final off = <String>{};
      for (final c in designs) {
        final d = designOf(c);
        final raw = c['design']! as Map<String, Object?>;
        for (final scheme in <String>['light', 'dark']) {
          final served = (raw[scheme]! as Map<String, Object?>)['chat']! as Map<String, Object?>;
          final chat = (scheme == 'light' ? d.light : d.dark).chat;
          expect(chat.showUpcomingCalls, served['showUpcomingCalls']);
          expect(chat.upcomingTitle, served['upcomingTitle']);
          expect(chat.showHistory, served['showHistory']);
          expect(chat.newConversation, served['newConversation']);
          if (!chat.showUpcomingCalls) off.add('calls');
          if (!chat.showHistory) off.add('history');
          if (!chat.newConversation) off.add('compose');
          if (chat.upcomingTitle.isNotEmpty) off.add('title');
        }
        expect(d.light.chat.showHistory, d.dark.chat.showHistory, reason: 'not a colour: one value for both schemes');
      }
      expect(off, <String>{'calls', 'history', 'compose', 'title'}, reason: 'the contract turns each away from its default');
    });

    test('absent, or of the wrong type, is on and the SDK\'s words', () {
      final older = ThemeChat.fromJson(<String, Object?>{}, fallback());
      expect(<Object?>[older.showUpcomingCalls, older.upcomingTitle, older.showHistory, older.newConversation], <Object?>[true, '', true, true]);
      for (final Object? odd in <Object?>['false', 0, null, <Object?>['off'], <String, Object?>{'showHistory': false}]) {
        final t = ThemeChat.fromJson(<String, Object?>{'showUpcomingCalls': odd, 'showHistory': odd, 'newConversation': odd}, fallback());
        expect(<Object?>[t.showUpcomingCalls, t.showHistory, t.newConversation], <Object?>[true, true, true], reason: '$odd: never read as off');
      }
      for (final Object? odd in <Object?>[7, false, null, <Object?>['Calls'], '   ']) {
        expect(ThemeChat.fromJson(<String, Object?>{'upcomingTitle': odd}, fallback()).upcomingTitle, '', reason: "$odd: the SDK's words");
      }
      final off = ThemeChat.fromJson(
          <String, Object?>{'showUpcomingCalls': false, 'upcomingTitle': '  Your calls  ', 'showHistory': false, 'newConversation': false},
          fallback());
      expect(<Object?>[off.showUpcomingCalls, off.upcomingTitle, off.showHistory, off.newConversation], <Object?>[false, 'Your calls', false, false]);
      // Written back as the session spelled them, and read again the same.
      final again = ThemeChat.fromJson(off.toJson(), fallback());
      expect(again.toJson(), off.toJson());
    });
  });

  group('history.json → display', () {
    test('what the window draws is the contract\'s', () {
      expect(display.length, greaterThanOrEqualTo(8));
      for (final c in display) {
        final name = c['name'];
        final offset = Duration(minutes: (c['utcOffsetMinutes']! as num).toInt());
        DateTime local(DateTime t) => t.toUtc().add(offset);
        final chat = ThemeChat.fromJson((c['chat']! as Map<String, Object?>), fallback());
        final turns = <GraineChatTurn>[
          for (final t in (c['turns']! as List<Object?>).cast<Map<String, Object?>>())
            GraineChatTurn(
              id: t['id']! as String,
              role: t['role'] == 'agent' ? GraineChatRole.agent : GraineChatRole.user,
              text: t['text']! as String,
              at: _at(t['at']! as String),
              restored: t['restored'] == true,
              channel: t['channel'] == 'voice' ? GraineChatChannel.voice : GraineChatChannel.chat,
            ),
        ];
        final p = ChatPieces.ofChat(turns, chat, upcomingCount: (c['upcoming']! as num).toInt());
        expect(p.turns.map((GraineChatTurn t) => t.id).toList(), c['shown'], reason: '$name: the turns drawn');
        final rows = <String>[
          for (final row in ChatRows.build(p.turns, now: _at(c['now']! as String), local: local))
            switch (row) {
              ChatDayRow() => 'day:${row.contractKey}',
              ChatVoiceRow() => 'voice:${row.first}-${row.last}',
              ChatTurnRow() => 'turn:${row.index}',
            },
        ];
        final want = <String>[
          for (final r in (c['rows']! as List<Object?>).cast<Map<String, Object?>>())
            if (r['day'] != null)
              'day:${r['day']}'
            else if (r['voice'] != null)
              'voice:${(r['voice']! as List<Object?>)[0]}-${(r['voice']! as List<Object?>)[1]}'
            else
              'turn:${r['turn']}',
        ];
        expect(rows, want, reason: '$name: rows');
        expect(p.starters, c['starters'], reason: '$name: starters');
        expect(p.newConversation, c['newConversation'], reason: '$name: New conversation');
        expect(p.upcoming, c['card'], reason: '$name: the booked-calls card');
        expect(p.upcomingTitle, c['cardTitle'], reason: '$name: its title');
      }
    });

    test('an older server with no chat tokens draws everything', () {
      final restored = GraineChatTurn(id: 'h1', role: GraineChatRole.user, text: 'Hi', at: DateTime(2026), restored: true);
      final p = ChatPieces.ofChat(<GraineChatTurn>[restored], null, upcomingCount: 2);
      expect(<Object?>[p.turns.length, p.newConversation, p.starters, p.upcoming, p.upcomingTitle], <Object?>[1, true, false, true, 'Upcoming calls']);
      expect(ChatPieces.ofChat(const <GraineChatTurn>[], null, upcomingCount: 1).upcomingTitle, 'Upcoming call');
    });
  });

  group('the chat window honours them', () {
    Widget host(Widget window) => MediaQuery(
          data: const MediaQueryData(size: Size(400, 800)),
          child: Directionality(textDirection: TextDirection.ltr, child: Align(alignment: Alignment.bottomCenter, child: window)),
        );
    final earlier = <GraineChatTurn>[
      GraineChatTurn(id: 'h1', role: GraineChatRole.user, text: 'Is my order shipped?', at: DateTime(2026, 10, 13, 10), restored: true),
      GraineChatTurn(id: 'h2', role: GraineChatRole.agent, text: 'Yes, it left this morning.', at: DateTime(2026, 10, 13, 10, 1), restored: true),
    ];
    final booked = <GraineScheduledCall>[GraineScheduledCall(id: 'a', at: DateTime(2026, 10, 14, 17, 30).toUtc())];

    /// The design.json case whose config turns history and the compose button off, else a plain one with [chat] laid over it.
    ThemeTokens tokens(Map<String, Object?> chat) {
      final t = plain();
      return ResolvedDesign.fromJson(<String, Object?>{
        'config': <String, Object?>{'preset': 'graine-classic', 'chat': chat},
        'light': <String, Object?>{...t.toJson(), 'chat': <String, Object?>{...t.chat.toJson(), ...chat}},
        'dark': <String, Object?>{...t.toJson(), 'chat': <String, Object?>{...t.chat.toJson(), ...chat}},
      })!.light;
    }

    ChatWindow window(ThemeTokens t, {List<GraineChatTurn>? turns, VoidCallback? onNewConversation}) => ChatWindow(
          look: ChatLook.design(t),
          heading: 'Assistant',
          messages: <Caption>[for (final x in turns ?? earlier) x.caption],
          turns: turns ?? earlier,
          online: true,
          onSend: (String _) {},
          onCollapse: () {},
          upcoming: booked,
          callName: 'Asha',
          now: () => DateTime(2026, 10, 14, 12),
          onNewConversation: onNewConversation ?? () {},
        );

    testWidgets('by default: the earlier messages under their day, New conversation, the booked call', (WidgetTester tester) async {
      await tester.pumpWidget(host(window(tokens(<String, Object?>{}))));
      expect(find.text('Is my order shipped?'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.byKey(ChatWindow.newConversationKey), findsOneWidget);
      expect(find.byKey(ChatWindow.upcomingKey), findsOneWidget);
      expect(find.text('Upcoming call'), findsOneWidget);
    });

    testWidgets('Earlier messages off: the window opens like a new chat, the agent still remembering', (WidgetTester tester) async {
      final off = designs.firstWhere((Map<String, Object?> c) => ((c['config']! as Map<String, Object?>)['chat'] as Map<String, Object?>?)?['showHistory'] == false);
      final t = designOf(off).light;
      expect(t.chat.showHistory, isFalse);
      await tester.pumpWidget(host(window(t)));
      expect(find.text('Is my order shipped?'), findsNothing);
      expect(find.text('Yesterday'), findsNothing);
      expect(find.byKey(ChatWindow.emptyKey), findsOneWidget, reason: 'the empty chat, as a new chat opens');
      expect(find.byKey(ChatWindow.newConversationKey), findsNothing, reason: 'nothing earlier on screen');
    });

    testWidgets('New conversation off: no compose control, the earlier messages still shown', (WidgetTester tester) async {
      await tester.pumpWidget(host(window(tokens(<String, Object?>{'newConversation': false}))));
      expect(find.text('Is my order shipped?'), findsOneWidget);
      expect(find.byKey(ChatWindow.newConversationKey), findsNothing);
    });

    testWidgets('Booked calls off: no card; on, the brand\'s title', (WidgetTester tester) async {
      await tester.pumpWidget(host(window(tokens(<String, Object?>{'showUpcomingCalls': false}))));
      expect(find.byKey(ChatWindow.upcomingKey), findsNothing);
      await tester.pumpWidget(host(window(tokens(<String, Object?>{'upcomingTitle': 'Your calls with Asha'}))));
      expect(find.byKey(ChatWindow.upcomingKey), findsOneWidget);
      expect(find.text('Your calls with Asha'), findsOneWidget);
      expect(find.text('Upcoming call'), findsNothing);
    });
  });
}
