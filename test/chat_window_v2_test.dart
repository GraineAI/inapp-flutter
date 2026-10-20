// CHAT WINDOW v2, DRAWN AND LIVED IN (contract/DESIGN.md "Chat window v2"):
// which composer, header, welcome and chips each style draws from real
// sessions' tokens (sdk/contract/design.json), the group corners and gaps,
// whose time shows and its delivery mark, the pinned card, the paperclip
// and the call buttons only where they belong, the typing indicators, the
// smooth reveal against the test clock, formatting, copy, message status,
// the reconnect banner, the scroll-to-latest pill, RTL and text size — and
// sdk/contract/chat-window.json → `fold` run against the real chat session
// over a fake socket, with the rating sent as its quiet frame. HTTP is a
// mock; nothing reaches a real host.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graine_inapp/graine_inapp.dart';
import 'package:graine_inapp/src/chat_bubble.dart';
import 'package:graine_inapp/src/chat_parts.dart';
import 'package:graine_inapp/src/chat_window.dart';
import 'package:graine_inapp/src/sdk_icon.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'contract_files.dart';
import 'device_mock.dart';

const String base = 'https://www.graine.ai';

Color hex(String h) => Color(int.parse('FF${h.substring(1)}', radix: 16));

Object? canon(Object? v) {
  if (v is num) return v.toDouble();
  if (v is Map) return <String, Object?>{for (final e in v.entries) e.key.toString(): canon(e.value)};
  if (v is List) return <Object?>[for (final x in v) canon(x)];
  return v;
}

// ── a chat session over a fake socket ───────────────────────────────────────

http.Response jsonResponse(Object? body, [int status = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(body)), status, headers: const <String, String>{'content-type': 'application/json'});

http.Client server({String mode = 'both'}) => MockClient((http.Request req) async {
      switch (req.url.path) {
        case '/api/embed/session':
          return jsonResponse(<String, Object?>{
            'agentId': 'agent-1',
            'webcallAgentId': 'webcall-1',
            'appearance': <String, Object?>{'mode': mode, 'title': 'Asha'},
          });
        case '/api/embed/ticket':
          return jsonResponse(<String, Object?>{'ticket': 'tkt_1', 'wsUrl': 'wss://gateway.test/v1/embed'});
      }
      return jsonResponse(<String, Object?>{'ok': true});
    });

class FakeSocket implements GraineChatSocket {
  final StreamController<Object?> _in = StreamController<Object?>();
  final List<Map<String, Object?>> sent = <Map<String, Object?>>[];

  @override
  Stream<Object?> get frames => _in.stream;

  @override
  void send(String data) => sent.add(jsonDecode(data) as Map<String, Object?>);

  @override
  Future<void> close() async {
    if (!_in.isClosed) unawaited(_in.close());
  }

  void say(Object? frame) => _in.add(jsonEncode(frame));
  void drop() => unawaited(_in.close());
}

class Connector {
  final List<FakeSocket> sockets = <FakeSocket>[];

  Future<GraineChatSocket> call(Uri url, List<String>? protocols) async {
    final s = FakeSocket();
    sockets.add(s);
    return s;
  }

  FakeSocket get last => sockets.last;

  /// Every frame of [type] put on the wire, on every socket, in order.
  List<Map<String, Object?>> sent(String type) => <Map<String, Object?>>[
        for (final s in sockets)
          for (final m in s.sent)
            if (m['type'] == type) m,
      ];
}

GraineInApp makeApp(WidgetTester tester, Connector c, {bool install = false, String mode = 'both'}) => GraineInApp.forTesting(
      const GraineConfig(baseUrl: base, publishableKey: 'pk_test_1'),
      httpClient: server(mode: mode),
      clock: () => tester.binding.clock.now().millisecondsSinceEpoch,
      chatConnector: c.call,
      install: install,
    );

Future<void> finish(WidgetTester tester, GraineInApp g) async {
  if (identical(GraineInApp.maybeInstance, g)) {
    GraineInApp.resetForTesting();
  } else {
    g.dispose();
  }
  await tester.pump(const Duration(milliseconds: 300));
}

Future<FakeSocket> connected(WidgetTester tester, GraineInApp g, Connector c) async {
  g.chat.open();
  await tester.pump();
  await tester.pump();
  expect(g.chat.connected, isTrue, reason: 'the chat did not connect');
  return c.last;
}

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

class FakeChat extends ChangeNotifier implements GraineChatState {
  @override
  List<Caption> messages = const <Caption>[Caption(Role.agent, 'Hi!')];
  @override
  bool connected = true;
  @override
  void send(String text) {}
}

void main() {
  late List<Map<String, Object?>> cases;
  late Map<String, Object?> vectors;

  setUpAll(() async {
    cases = ((await contractJson('contract/design.json'))['cases']! as List<Object?>).cast<Map<String, Object?>>();
    vectors = await contractJson('contract/chat-window.json');
  });
  setUp(() => DeviceMock().install());
  tearDown(DeviceMock.uninstall);

  /// The design.json case of chat style [preset] (Classic: the one that names it).
  Map<String, Object?> rawCase(String preset) => cases.firstWhere((Map<String, Object?> c) {
        final chat = (c['config']! as Map<String, Object?>)['chat'];
        return chat is Map<String, Object?> && chat['preset'] == preset;
      });

  /// One scheme's tokens of [preset]'s case, the chat's fields and groups patched by [chat].
  /// The case with every v2 knob turned, found by what it says rather than where it sits in the file.
  int everyKnobCase() => cases.indexWhere((c) {
        final chat = (c['config']! as Map)['chat'];
        final typing = chat is Map ? chat['typing'] : null;
        return typing is Map && typing['text'] == 'Writing…';
      });

  ThemeTokens style(String preset, {Map<String, Object?> chat = const <String, Object?>{}, String scheme = 'light', int? caseIndex}) {
    final raw = (caseIndex != null ? cases[caseIndex] : rawCase(preset))['design']! as Map<String, Object?>;
    final tokens = <String, Object?>{...raw[scheme]! as Map<String, Object?>};
    final served = <String, Object?>{...tokens['chat']! as Map<String, Object?>};
    for (final e in chat.entries) {
      final v = e.value;
      served[e.key] = v is Map<String, Object?> && served[e.key] is Map<String, Object?>
          ? <String, Object?>{...served[e.key]! as Map<String, Object?>, ...v}
          : v;
    }
    return ThemeTokens.fromJson(<String, Object?>{...tokens, 'chat': served}, scheme: scheme)!;
  }

  final at = DateTime(2026, 10, 13, 21, 41);
  GraineChatTurn agent(String id, String text, {DateTime? when, bool live = false}) =>
      GraineChatTurn(id: id, role: GraineChatRole.agent, text: text, at: when ?? at, live: live);
  GraineChatTurn user(String id, String text, {DateTime? when, GraineChatDelivery delivery = GraineChatDelivery.sent}) =>
      GraineChatTurn(id: id, role: GraineChatRole.user, text: text, at: when ?? at, delivery: delivery);

  Widget host(Widget child,
          {TextDirection dir = TextDirection.ltr, double scale = 1, bool still = false, Size size = const Size(400, 800)}) =>
      MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale), disableAnimations: still),
        child: Directionality(textDirection: dir, child: Align(alignment: Alignment.bottomCenter, child: child)),
      );

  ChatWindow window(
    ThemeTokens t, {
    List<GraineChatTurn> turns = const <GraineChatTurn>[],
    bool typing = false,
    bool online = true,
    bool fill = false,
    ValueChanged<String>? onSend,
    GraineChatPin? pin,
    List<GraineQuickReply> quickReplies = const <GraineQuickReply>[],
    ValueChanged<GraineQuickReply>? onQuickReply,
    bool ended = false,
    GraineChatRating? rating,
    void Function(GraineChatRatingStyle style, int value)? onRate,
    VoidCallback? onAttach,
    VoidCallback? onCall,
    bool reconnecting = false,
    bool offline = false,
    VoidCallback? onRetry,
    ValueChanged<Uri>? onOpenLink,
  }) =>
      ChatWindow(
        look: ChatLook.design(t),
        heading: 'Assistant',
        messages: <Caption>[for (final x in turns) x.caption],
        turns: turns,
        online: online,
        typing: typing,
        onSend: onSend ?? (String _) {},
        onCollapse: () {},
        fill: fill,
        now: () => at,
        pin: pin,
        quickReplies: quickReplies,
        onQuickReply: onQuickReply,
        ended: ended,
        rating: rating,
        onRate: onRate,
        onAttach: onAttach,
        onCall: onCall,
        reconnecting: reconnecting,
        offline: offline,
        onRetry: onRetry,
        onOpenLink: onOpenLink,
      );

  Widget full(ChatWindow w) => SizedBox(width: 400, height: 700, child: w);

  BoxDecoration box(WidgetTester tester, Finder f) => tester.widget<Container>(f).decoration! as BoxDecoration;
  Finder inThread(Key key) => find.descendant(of: find.byKey(ChatWindow.threadKey), matching: find.byKey(key));
  String iconIn(WidgetTester tester, Key key) =>
      tester.widget<SdkIconView>(find.descendant(of: find.byKey(key), matching: find.byType(SdkIconView)).first).name;

  // ── the fold ───────────────────────────────────────────────────────────────

  group('chat-window.json → fold, through the chat session', () {
    testWidgets('every case: the turns, typing, the replies, the end, the rating, the texts sent and the rating frames',
        (WidgetTester tester) async {
      final fold = (vectors['fold']! as List<Object?>).cast<Map<String, Object?>>();
      for (final c in fold) {
        final name = c['name'];
        final conn = Connector();
        final g = makeApp(tester, conn);
        await connected(tester, g, conn);
        for (final step in (c['steps']! as List<Object?>).cast<Map<String, Object?>>()) {
          if (step.containsKey('frame')) {
            conn.last.say(step['frame']);
          } else if (step.containsKey('send')) {
            g.chat.send(step['send']! as String);
          } else if (step['drop'] == true) {
            conn.last.drop();
          } else if (step.containsKey('rate')) {
            final r = step['rate']! as Map<String, Object?>;
            g.chat.rate(GraineChatRatingStyle.of(r['style']), r['value']! as num);
          } else if (step['clear'] == true) {
            g.chat.clear();
          } else {
            fail('$name: a step this suite does not know: $step');
          }
          await tester.pump();
        }
        final want = (c['turns']! as List<Object?>).cast<Map<String, Object?>>();
        final got = g.chat.turns;
        expect(got.length, want.length, reason: '$name: $got');
        for (var i = 0; i < want.length; i++) {
          final w = want[i];
          final t = got[i];
          expect(t.role == GraineChatRole.agent ? 'agent' : 'customer', w['role'], reason: '$name #$i');
          expect(t.text, w['text'], reason: '$name #$i');
          if (w.containsKey('live')) expect(t.live, w['live'], reason: '$name #$i live');
          if (w.containsKey('proactive')) expect(t.proactive, w['proactive'], reason: '$name #$i proactive');
          expect(t.restored, w['restored'] ?? false, reason: '$name #$i restored');
        }
        expect(g.chat.agentTyping, c['typing'], reason: '$name: typing');
        expect(<Object?>[for (final r in g.chat.quickReplies) r.toJson()], c['quickReplies'], reason: '$name: replies');
        expect(g.chat.ended, c['ended'], reason: '$name: ended');
        expect(canon(g.chat.rating?.toJson()), canon(c['rating']), reason: '$name: rating');
        expect(<Object?>[for (final m in conn.sent('text')) m['data']], c['sent'], reason: '$name: sent');
        expect(canon(conn.sent('app_event')), canon(c['events']), reason: '$name: rating frames');
        await finish(tester, g);
      }
    });

    testWidgets('after the agent ends the conversation the server closes it: no reconnect; the next message connects again',
        (WidgetTester tester) async {
      final conn = Connector();
      final g = makeApp(tester, conn);
      final s = await connected(tester, g, conn);
      s.say(<String, Object?>{'type': 'conversation_end'});
      await tester.pump();
      s.drop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      expect(conn.sockets, hasLength(1), reason: 'a new conversation under the goodbye would greet again');
      expect(g.chat.connecting, isFalse);
      g.chat.send('One more question');
      await tester.pump();
      await tester.pump();
      expect(conn.sockets, hasLength(2));
      expect(conn.last.sent.where((Map<String, Object?> m) => m['type'] == 'text').single['data'], 'One more question');
      expect(g.chat.ended, isFalse);
      await finish(tester, g);
    });
  });

  // ── the pieces each style draws ────────────────────────────────────────────

  group('which pieces each style draws', () {
    testWidgets('the composer: a bar beside the send button, a pill with it inside, a floating capsule over the thread',
        (WidgetTester tester) async {
      final turns = <GraineChatTurn>[agent('t1', 'Hi there!')];
      final classic = style('classic');
      await tester.pumpWidget(host(window(classic, turns: turns)));
      final field = find.byKey(ChatWindow.composerKey);
      expect(tester.getSize(field).height, 40);
      expect(tester.getSize(find.ancestor(of: field, matching: find.byType(Container)).first).height, 58, reason: 'the strip');
      expect(find.descendant(of: field, matching: find.byKey(ChatWindow.sendKey)), findsNothing, reason: 'beside the field');
      expect(tester.getSize(find.byKey(ChatWindow.sendKey)), const Size(40, 40));

      final bold = style('bold');
      await tester.pumpWidget(host(window(bold, turns: turns)));
      final pill = find.byKey(ChatWindow.composerKey);
      expect(tester.getSize(pill).height, 44);
      expect(box(tester, pill).borderRadius, BorderRadius.circular(22));
      expect(find.descendant(of: pill, matching: find.byKey(ChatWindow.sendKey)), findsOneWidget, reason: 'inside the pill');
      expect(tester.getSize(find.byKey(ChatWindow.sendKey)), const Size(36, 36));
      expect(tester.getSize(find.ancestor(of: pill, matching: find.byType(Container)).first).height, 60, reason: 'its strip');

      final soft = style('soft');
      await tester.pumpWidget(host(window(soft, turns: turns)));
      await tester.pump();
      final capsule = tester.getRect(find.byKey(ChatWindow.composerKey));
      final frame = tester.getRect(find.byType(ChatWindow));
      final bw = soft.shape.borderWidth;
      expect(capsule.height, 48);
      expect(frame.bottom - capsule.bottom, closeTo(10 + bw, 0.01), reason: '10 above the window\'s bottom');
      expect(capsule.left - frame.left, closeTo(10 + bw, 0.01), reason: '10 in from the side');
      expect(box(tester, find.byKey(ChatWindow.composerKey)).boxShadow, shadowsOfTest(soft.chat.composer.shadow));
      expect(soft.chat.composer.strip, isNull, reason: 'no strip: the thread runs under it');

      final minimal = style('minimal');
      await tester.pumpWidget(host(window(minimal, turns: turns)));
      final send = find.descendant(of: find.byKey(ChatWindow.sendKey), matching: find.byType(Container)).first;
      expect(tester.getSize(send), const Size(44, 44), reason: '`icon`: no fill, a 44 target');
      expect(tester.widget<Container>(send).decoration, isNull);
    });

    testWidgets('where the chips go: starters docked with replies under the turn, replies docked, starters in the thread, a list',
        (WidgetTester tester) async {
      const starters = <String>['Track it', 'Talk to someone'];
      final replies = <GraineQuickReply>[
        const GraineQuickReply(label: 'Yes', text: 'Yes, please'),
        const GraineQuickReply(label: 'No', text: 'No'),
      ];
      final turns = <GraineChatTurn>[agent('t1', 'Shall I go ahead?')];
      final sent = <String>[];

      // both (classic): the starters docked above the composer, the replies in the thread on the agent's side.
      final classic = style('classic', chat: <String, Object?>{'suggestions': starters});
      await tester.pumpWidget(host(window(classic, turns: turns, quickReplies: replies, onSend: sent.add)));
      expect(find.byKey(ChatWindow.suggestionsKey), findsOneWidget);
      expect(inThread(ChatWindow.suggestionsKey), findsNothing, reason: 'docked');
      expect(inThread(ChatWindow.quickRepliesKey), findsOneWidget, reason: 'under the turn they follow');
      final bubble = tester.getRect(find.byKey(ChatWindow.messageKey(0)));
      final chip = tester.getRect(find.byKey(ChatWindow.quickReplyKey(0)));
      expect(chip.left, closeTo(bubble.left, 0.01), reason: "on the agent's side");
      expect(chip.top - bubble.bottom, closeTo(8, 0.01), reason: '8 below it');
      await tester.tap(find.byKey(ChatWindow.quickReplyKey(0)));
      expect(sent, <String>['Yes, please'], reason: "a tap sends the reply's text as the user's own turn");

      // above-composer (glass): the replies docked, in the starters' place.
      final glass = style('glass', chat: <String, Object?>{'suggestions': starters});
      await tester.pumpWidget(host(window(glass, turns: turns, quickReplies: replies)));
      expect(find.byKey(ChatWindow.quickRepliesKey), findsOneWidget);
      expect(inThread(ChatWindow.quickRepliesKey), findsNothing);
      expect(find.byKey(ChatWindow.suggestionsKey), findsNothing, reason: 'the replies take the starters\' place');
      await tester.pumpWidget(host(window(glass, turns: turns)));
      expect(find.byKey(ChatWindow.suggestionsKey), findsOneWidget, reason: 'no replies: the starters again');

      // inline (bold, a hero welcome): the starters at the end of the welcome, in the thread.
      final bold = style('bold', chat: <String, Object?>{'suggestions': starters});
      await tester.pumpWidget(host(window(bold, turns: turns, quickReplies: replies)));
      await tester.pump(); // the thread follows to its newest row
      expect(find.descendant(of: find.byKey(ChatWindow.welcomeKey), matching: find.byKey(ChatWindow.suggestionsKey)), findsOneWidget);
      expect(inThread(ChatWindow.quickRepliesKey), findsOneWidget);

      // a list (minimal): rows in the thread, 44 high.
      final minimal = style('minimal', chat: <String, Object?>{'suggestions': starters});
      await tester.pumpWidget(host(window(minimal, turns: turns)));
      expect(inThread(ChatWindow.suggestionsKey), findsOneWidget);
      expect(tester.getSize(find.byKey(ChatWindow.suggestionKey(0))).height, 44);
      expect(find.descendant(of: find.byKey(ChatWindow.suggestionKey(0)), matching: find.byType(SdkIconView)), findsOneWidget,
          reason: 'the chevron to the trailing side');

      // Once the user said something, the starters go.
      await tester.pumpWidget(host(window(classic, turns: <GraineChatTurn>[...turns, user('t2', 'Yes')])));
      expect(find.byKey(ChatWindow.suggestionsKey), findsNothing);
    });

    testWidgets('grouped bubbles: tight inner corners by shape and position, closer together, the time under the last',
        (WidgetTester tester) async {
      final soft = style('soft');
      final three = <GraineChatTurn>[
        agent('a1', 'One', when: at),
        agent('a2', 'Two', when: at.add(const Duration(seconds: 20))),
        agent('a3', 'Three', when: at.add(const Duration(seconds: 40))),
      ];
      await tester.pumpWidget(host(window(soft, turns: three)));
      final r = Radius.circular(soft.chat.bubbles.radius);
      final tight = Radius.circular(soft.chat.bubbles.tightRadius);
      // The agent speaks from the leading side: in LTR its corners on the left are the tight ones.
      expect(box(tester, find.byKey(ChatWindow.messageKey(0))).borderRadius,
          BorderRadius.only(topLeft: r, topRight: r, bottomLeft: tight, bottomRight: r), reason: 'first');
      expect(box(tester, find.byKey(ChatWindow.messageKey(1))).borderRadius,
          BorderRadius.only(topLeft: tight, topRight: r, bottomLeft: tight, bottomRight: r), reason: 'middle');
      expect(box(tester, find.byKey(ChatWindow.messageKey(2))).borderRadius,
          BorderRadius.only(topLeft: tight, topRight: r, bottomLeft: r, bottomRight: r), reason: 'last');
      final gap = tester.getRect(find.byKey(ChatWindow.messageKey(1))).top - tester.getRect(find.byKey(ChatWindow.messageKey(0))).bottom;
      expect(gap, closeTo(soft.chat.density.groupGap, 0.01), reason: 'a group sits closer');
      expect(find.text('9:41 PM'), findsOneWidget, reason: 'times by group: under the last');

      // A single squircle bubble: continuous corners.
      await tester.pumpWidget(host(window(soft, turns: <GraineChatTurn>[agent('a1', 'Alone')])));
      final single = tester.widget<Container>(find.byKey(ChatWindow.messageKey(0))).decoration! as ShapeDecoration;
      expect((single.shape as ChatBubbleBorder).geometry.continuous, isTrue);

      // rounded (crisp): the bottom speaker-side corner always tight, the top one for middle and last.
      final crisp = style('crisp');
      await tester.pumpWidget(host(window(crisp, turns: <GraineChatTurn>[
        user('u1', 'First', when: at),
        user('u2', 'Second', when: at.add(const Duration(minutes: 1))),
      ])));
      final cr = Radius.circular(crisp.chat.bubbles.radius);
      final ct = Radius.circular(crisp.chat.bubbles.tightRadius);
      expect(box(tester, find.byKey(ChatWindow.messageKey(0))).borderRadius,
          BorderRadius.only(topLeft: cr, topRight: cr, bottomLeft: cr, bottomRight: ct));
      expect(box(tester, find.byKey(ChatWindow.messageKey(1))).borderRadius,
          BorderRadius.only(topLeft: cr, topRight: ct, bottomLeft: cr, bottomRight: ct));

      // tail (bold): the tail on the last of the group, at the speaker's bottom corner.
      final bold = style('bold');
      await tester.pumpWidget(host(window(bold, turns: <GraineChatTurn>[
        agent('a1', 'One', when: at),
        agent('a2', 'Two', when: at.add(const Duration(seconds: 30))),
      ])));
      expect(tester.widget<Container>(find.byKey(ChatWindow.messageKey(0))).decoration, isA<BoxDecoration>(), reason: 'no tail on the first');
      final last = tester.widget<Container>(find.byKey(ChatWindow.messageKey(1))).decoration! as ShapeDecoration;
      final border = last.shape as ChatBubbleBorder;
      expect(border.geometry.tail, BubbleTail.left);
      expect(border.geometry.radius.bottomLeft, Radius.zero, reason: 'the corner that carries it is square');
      expect(last.gradient, isNull);

      // A gap of more than two minutes, or the other side: two groups.
      await tester.pumpWidget(host(window(soft, turns: <GraineChatTurn>[
        agent('a1', 'One', when: at),
        agent('a2', 'Later', when: at.add(const Duration(minutes: 5))),
      ])));
      expect(find.byType(ChatMessageRow), findsNWidgets(2));
      expect(tester.widget<ChatMessageRow>(find.byType(ChatMessageRow).first).position, ChatGroupPosition.single);

      // flat (compact): every corner the radius.
      final compact = style('compact');
      await tester.pumpWidget(host(window(compact, turns: three)));
      expect(box(tester, find.byKey(ChatWindow.messageKey(1))).borderRadius, BorderRadius.circular(compact.chat.bubbles.radius));
    });

    testWidgets('times: below or inside, by group or always, and the delivery mark beside the user\'s', (WidgetTester tester) async {
      final soft = style('soft');
      await tester.pumpWidget(host(window(soft, turns: <GraineChatTurn>[user('u1', 'Sent one')])));
      expect(find.text('9:41 PM'), findsOneWidget);
      expect(find.byWidgetPredicate((Widget w) => w is SdkIconView && w.name == 'check'), findsOneWidget, reason: 'sent');
      await tester.pumpWidget(host(window(soft, turns: <GraineChatTurn>[user('u1', 'Waiting', delivery: GraineChatDelivery.sending)])));
      expect(find.byWidgetPredicate((Widget w) => w is SdkIconView && w.name == 'clock'), findsOneWidget, reason: 'waiting');
      await tester.pumpWidget(host(window(soft, turns: <GraineChatTurn>[user('u1', 'Lost', delivery: GraineChatDelivery.failed)])));
      final alert = tester.widgetList<SdkIconView>(find.byWidgetPredicate((Widget w) => w is SdkIconView && w.name == 'alert'));
      expect(alert, hasLength(2), reason: 'the mark beside the time, and the status line');
      expect(alert.every((SdkIconView v) => v.color == hex(soft.colors.danger)), isTrue);

      // inside (cozy): the time is in the bubble, under the words.
      final cozy = style('cozy');
      await tester.pumpWidget(host(window(cozy, turns: <GraineChatTurn>[agent('a1', 'Hello')])));
      expect(find.descendant(of: find.byKey(ChatWindow.messageKey(0)), matching: find.text('9:41 PM')), findsOneWidget);

      // never (minimal): none.
      await tester.pumpWidget(host(window(style('minimal'), turns: <GraineChatTurn>[agent('a1', 'Hello')])));
      expect(find.text('9:41 PM'), findsNothing);
    });

    testWidgets('the welcome: centred (classic), a card, a hero the window\'s full width, none (minimal)', (WidgetTester tester) async {
      await tester.pumpWidget(host(window(style('classic'))));
      expect(find.byKey(ChatWindow.emptyKey), findsOneWidget);

      await tester.pumpWidget(host(window(style('soft'))));
      expect(inThread(ChatWindow.welcomeKey), findsOneWidget, reason: 'a card first in the thread');

      final bold = style('bold');
      await tester.pumpWidget(host(window(bold, turns: <GraineChatTurn>[agent('a1', 'Hello!')])));
      final hero = tester.getRect(find.byKey(ChatWindow.welcomeKey));
      final frame = tester.getRect(find.byType(ChatWindow));
      expect(hero.width, closeTo(frame.width - 2 * bold.shape.borderWidth, 0.01), reason: "the window's full width");
      expect(tester.getRect(find.byKey(ChatWindow.messageKey(0))).top - hero.bottom, closeTo(16, 0.01), reason: 'the first message 16 below');

      await tester.pumpWidget(host(window(style('minimal'))));
      expect(find.byKey(ChatWindow.welcomeKey), findsNothing);
      expect(find.byKey(ChatWindow.emptyKey), findsNothing);

      // A conversation that continues has no welcome.
      final restored = GraineChatTurn(id: 'h1', role: GraineChatRole.agent, text: 'Before', at: at, restored: true);
      await tester.pumpWidget(host(window(style('soft'), turns: <GraineChatTurn>[restored])));
      expect(find.byKey(ChatWindow.welcomeKey), findsNothing);
    });

    testWidgets('the header: plain, gradient leading → trailing, centred, its status line', (WidgetTester tester) async {
      final turns = <GraineChatTurn>[agent('a1', 'Hello')];
      await tester.pumpWidget(host(window(style('soft'), turns: turns)));
      final plain = box(tester, find.byKey(ChatWindow.headerKey));
      expect(plain.color, const Color(0x00000000), reason: 'no fill: the wallpaper runs under it');

      final bold = style('bold');
      await tester.pumpWidget(host(window(bold, turns: turns)));
      final g = box(tester, find.byKey(ChatWindow.headerKey)).gradient! as LinearGradient;
      expect(g.begin, AlignmentDirectional.centerStart);
      expect(g.colors, <Color>[hex(bold.chat.header.fill.color), hex(bold.chat.header.fill.colorTo!)]);

      // minimal: centred, no status line.
      await tester.pumpWidget(host(window(style('minimal'), turns: turns)));
      // The avatar (24) with the title, as one group centred on the header's whole width.
      final title = tester.getRect(find.descendant(of: find.byKey(ChatWindow.headerKey), matching: find.text('Assistant')));
      final mark = tester.getRect(find.byKey(ChatWindow.avatarKey));
      expect(mark.size, const Size(24, 24));
      expect(mark.expandToInclude(title).center.dx, closeTo(tester.getCenter(find.byType(ChatWindow)).dx, 1),
          reason: 'centred on the whole width');
      expect(find.text('Online'), findsNothing, reason: 'status: none');

      // crisp: the words without the dot.
      await tester.pumpWidget(host(window(style('crisp'), turns: turns)));
      expect(find.text('Online'), findsOneWidget);
      final dots = find.descendant(
          of: find.byKey(ChatWindow.headerKey),
          matching: find.byWidgetPredicate((Widget w) =>
              w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).shape == BoxShape.circle));
      expect(dots, findsNothing);

      // soft: typing status says so while the reply is coming.
      await tester.pumpWidget(host(window(style('soft'), turns: turns, typing: true)));
      expect(find.descendant(of: find.byKey(ChatWindow.headerKey), matching: find.text('Typing…')), findsOneWidget);
    });

    testWidgets('the wallpaper: a gradient behind the frame, a pattern standing still', (WidgetTester tester) async {
      final glass = style('glass');
      await tester.pumpWidget(host(window(glass, turns: <GraineChatTurn>[agent('a1', 'Hi')])));
      final frame = box(tester, find.descendant(of: find.byType(ChatWindow), matching: find.byType(Container)).first);
      expect((frame.gradient! as LinearGradient).colors,
          <Color>[hex(glass.chat.wallpaper.color), hex(glass.chat.wallpaper.colorTo!)]);
      await tester.pumpWidget(host(window(style('cozy'), turns: <GraineChatTurn>[agent('a1', 'Hi')])));
      expect(find.byWidgetPredicate((Widget w) => w is CustomPaint && w.painter is ChatLinePattern), findsOneWidget, reason: 'diagonal');
      await tester.pumpWidget(host(window(style('lively'), turns: <GraineChatTurn>[agent('a1', 'Hi')])));
      expect(find.byWidgetPredicate((Widget w) => w is CustomPaint && w.painter.runtimeType.toString() == '_DotPattern'), findsOneWidget);
    });

    testWidgets('glass: the agent bubbles, the composer and the header frosted over the wallpaper', (WidgetTester tester) async {
      final glass = style('glass');
      await tester.pumpWidget(host(window(glass, turns: <GraineChatTurn>[agent('a1', 'Frosted'), user('u1', 'Clear')])));
      await tester.pump();
      expect(find.ancestor(of: find.byKey(ChatWindow.messageKey(0)), matching: find.byType(BackdropFilter)), findsOneWidget);
      expect(find.ancestor(of: find.byKey(ChatWindow.messageKey(1)), matching: find.byType(BackdropFilter)), findsNothing,
          reason: "only the agent's bubbles");
      expect(find.descendant(of: find.byKey(ChatWindow.composerKey), matching: find.byType(BackdropFilter)), findsOneWidget);
    });
  });

  // ── what only some chats draw ──────────────────────────────────────────────

  group('pieces that belong only where they belong', () {
    testWidgets('the pinned card: only when the app pins one, as a bar or a card, never for none', (WidgetTester tester) async {
      const pin = GraineChatPin(title: 'Case 1042', subtitle: 'Opened today', badge: 'Open');
      final turns = <GraineChatTurn>[agent('a1', 'Hello')];
      final crisp = style('crisp');
      await tester.pumpWidget(host(window(crisp, turns: turns)));
      expect(find.byKey(ChatWindow.contextBarKey), findsNothing, reason: 'nothing pinned');
      await tester.pumpWidget(host(window(crisp, turns: turns, pin: pin)));
      expect(find.byKey(ChatWindow.contextBarKey), findsOneWidget);
      expect(find.text('Case 1042'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      expect(tester.getSize(find.byKey(ChatWindow.contextBarKey)).height, greaterThanOrEqualTo(52));
      expect(tester.getSemantics(find.byKey(ChatWindow.contextBarKey)).label, 'Pinned: Case 1042, Opened today, Open');

      final none = style('crisp', chat: <String, Object?>{'header': <String, Object?>{'contextCard': 'none'}});
      await tester.pumpWidget(host(window(none, turns: turns, pin: pin)));
      expect(find.byKey(ChatWindow.contextBarKey), findsNothing);
      expect(find.byKey(ChatWindow.contextCardKey), findsNothing);

      final card = style('soft', caseIndex: everyKnobCase());
      expect(card.chat.header.contextCard, 'card');
      await tester.pumpWidget(host(window(card, turns: turns, pin: pin)));
      expect(inThread(ChatWindow.contextCardKey), findsOneWidget, reason: 'the first item of the thread');
    });

    testWidgets('the paperclip: only where the design asks for one AND the app handles attachments', (WidgetTester tester) async {
      var attached = 0;
      final turns = <GraineChatTurn>[agent('a1', 'Hello')];
      final crisp = style('crisp');
      expect(crisp.chat.composer.attach, isTrue);
      await tester.pumpWidget(host(window(crisp, turns: turns)));
      expect(find.byKey(ChatWindow.attachKey), findsNothing, reason: 'no handler');
      await tester.pumpWidget(host(window(crisp, turns: turns, onAttach: () => attached++)));
      expect(find.byKey(ChatWindow.attachKey), findsOneWidget);
      await tester.tap(find.byKey(ChatWindow.attachKey));
      expect(attached, 1);
      await tester.pumpWidget(host(window(style('classic'), turns: turns, onAttach: () => attached++)));
      expect(find.byKey(ChatWindow.attachKey), findsNothing, reason: 'the design asks for none');
    });

    testWidgets('the microphone and the call buttons: only where the agent takes calls', (WidgetTester tester) async {
      var calls = 0;
      final turns = <GraineChatTurn>[agent('a1', 'Hello')];
      final soft = style('soft');
      await tester.pumpWidget(host(window(soft, turns: turns)));
      await tester.pump();
      expect(iconIn(tester, ChatWindow.sendKey), 'send', reason: 'no calls here: the send button');
      await tester.pumpWidget(host(window(soft, turns: turns, onCall: () => calls++)));
      await tester.pump();
      expect(iconIn(tester, ChatWindow.sendKey), 'mic', reason: 'an empty field: the microphone');
      expect(tester.getSemantics(find.byKey(ChatWindow.sendKey)).label, 'Call Assistant');
      await tester.tap(find.byKey(ChatWindow.sendKey));
      expect(calls, 1);
      await tester.enterText(find.byType(EditableText), 'Words');
      await tester.pump();
      expect(iconIn(tester, ChatWindow.sendKey), 'send', reason: 'words in the field: send');

      final bold = style('bold');
      await tester.pumpWidget(host(window(bold, turns: turns)));
      expect(find.byKey(ChatWindow.headerCallKey), findsNothing);
      await tester.pumpWidget(host(window(bold, turns: turns, onCall: () => calls++)));
      expect(find.byKey(ChatWindow.headerCallKey), findsOneWidget);
      await tester.tap(find.byKey(ChatWindow.headerCallKey));
      expect(calls, 2);

      final calm = style('calm');
      await tester.pumpWidget(host(window(calm, turns: turns, onCall: () => calls++)));
      await tester.pump();
      expect(find.byKey(ChatWindow.composerCallKey), findsNothing, reason: 'the microphone already calls');
      final noMic = style('calm', chat: <String, Object?>{'composer': <String, Object?>{'mic': false}});
      await tester.pumpWidget(host(window(noMic, turns: turns, onCall: () => calls++)));
      await tester.pump();
      expect(find.byKey(ChatWindow.composerCallKey), findsOneWidget);
    });

    testWidgets('the bar: its chat calls the agent by switching back to the call and starting it — only for an agent that takes calls',
        (WidgetTester tester) async {
      final design = ResolvedDesign.fromJson(rawCase('bold')['design'])!;
      final call = FakeCall(const <String, Object?>{'mode': 'both', 'start': 'chat', 'title': 'Asha'});
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(400, 800)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(children: <Widget>[GraineAgentBar(call: call, chat: FakeChat(), design: design, showComponents: false)]),
        ),
      ));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(GraineAgentBar.chatKey), findsOneWidget);
      await tester.tap(find.byKey(ChatWindow.headerCallKey));
      await tester.pump(const Duration(seconds: 1));
      expect(call.starts, 1, reason: "the bar's own call");
      expect(find.byKey(GraineAgentBar.chatKey), findsNothing, reason: 'back on the call');

      final chatOnly = FakeCall(const <String, Object?>{'mode': 'chat', 'title': 'Asha'});
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(400, 800)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(children: <Widget>[
            GraineAgentBar(call: chatOnly, chat: FakeChat(), design: design, showComponents: false, key: UniqueKey()),
          ]),
        ),
      ));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(GraineAgentBar.chatKey), findsOneWidget);
      expect(find.byKey(ChatWindow.headerCallKey), findsNothing, reason: 'a chat-only agent takes no calls');
    });
  });

  // ── the agent's components ─────────────────────────────────────────────────

  group("the agent's components take the chat's card style", () {
    Map<String, Object?> component(String preset, {bool images = false}) => <String, Object?>{
          'widget_id': 'pick:$preset',
          'kind': 'product_list',
          'style': <String, Object?>{'surface': 'card', 'preset': preset},
          'data': <String, Object?>{
            'title': 'Two that fit',
            'selectLabel': 'Choose',
            'items': <Object?>[
              <String, Object?>{'id': 'a', 'title': 'First', if (images) 'imageUrl': 'https://example.com/a.png'},
              <String, Object?>{'id': 'b', 'title': 'Second', if (images) 'imageUrl': 'https://example.com/b.png'},
            ],
          },
        };

    testWidgets('corners, outline, shadow and the main button as `chat.cards` says', (WidgetTester tester) async {
      final soft = ResolvedDesign.fromJson(rawCase('soft')['design'])!;
      final cards = soft.light.chat.cards;
      expect(cards.button, 'tonal');
      final comps = GraineComponents(baseUrl: base, clock: () => tester.binding.clock.now().millisecondsSinceEpoch);
      addTearDown(comps.dispose);
      comps.present(component('cards'));
      await tester.pumpWidget(host(GraineWidgetView(components: comps, appearance: const <String, Object?>{}, design: soft)));
      await tester.pump(const Duration(seconds: 1));
      final card = box(tester, find.byKey(const ValueKey<String>('graine-surface-card')));
      expect(card.borderRadius, BorderRadius.circular(cards.radius));
      expect(card.border, isNull, reason: 'cards.border: false');
      expect(card.boxShadow, shadowsOfTest(cards.shadow));
      final words = find.text('Choose').first;
      expect(tester.widget<Text>(words).style!.color, hex(cards.buttonText));
      final button = box(tester, find.ancestor(of: words, matching: find.byType(Container)).first);
      expect(button.color, hex(cards.buttonFill!), reason: 'tonal: the soft fill');

      // Classic: the button it always was — the accent, the words on it.
      final classic = ResolvedDesign.fromJson(cases.first['design'])!;
      await tester.pumpWidget(host(GraineWidgetView(components: comps, appearance: const <String, Object?>{}, design: classic, key: UniqueKey())));
      await tester.pump(const Duration(seconds: 1));
      final filled = box(tester, find.ancestor(of: find.text('Choose').first, matching: find.byType(Container)).first);
      expect(filled.color, hex(classic.light.colors.accent));
    });

    testWidgets("a large image takes the cards' shape: 9:16 of its width, within 100–260", (WidgetTester tester) async {
      final every = ResolvedDesign.fromJson(cases[everyKnobCase()]['design'])!;
      expect(every.light.chat.cards.image, 'wide');
      final comps = GraineComponents(baseUrl: base, clock: () => tester.binding.clock.now().millisecondsSinceEpoch);
      addTearDown(comps.dispose);
      comps.present(component('gallery', images: true));
      await tester.pumpWidget(host(GraineWidgetView(components: comps, appearance: const <String, Object?>{}, design: every)));
      await tester.pump(const Duration(seconds: 1));
      final picture = tester.getSize(find.ancestor(of: find.byType(Image).first, matching: find.byType(Container)).first);
      expect(picture.height, closeTo((picture.width * 9 / 16).clamp(100.0, 260.0), 0.01));
    });
  });

  // ── the experience ─────────────────────────────────────────────────────────

  group('the experience', () {
    testWidgets('the rating: after the agent ends the conversation, one choice, sent as the quiet frame and handed to the app',
        (WidgetTester tester) async {
      final conn = Connector();
      final g = makeApp(tester, conn, install: true);
      addTearDown(() => GraineInApp.maybeInstance == g ? GraineInApp.resetForTesting() : null);
      await g.loadSession();
      final rated = <GraineChatRating>[];
      g.chat.onRated = rated.add;
      final design = ResolvedDesign.fromJson(rawCase('bold')['design'])!;
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(400, 800)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(width: 400, height: 800, child: GraineChat(app: g, design: design, onClose: () {})),
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(g.chat.connected, isTrue);
      final s = conn.last;
      expect(find.byKey(ChatWindow.ratingKey), findsNothing);
      s.say(<String, Object?>{'type': 'text', 'data': '<beginning_of_stream>Glad I could help. Bye!<end_of_stream>'});
      s.say(<String, Object?>{'type': 'conversation_end'});
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump();
      expect(find.byKey(ChatWindow.ratingKey), findsOneWidget, reason: 'stars, at the end of the thread');
      expect(find.text('How was this chat?'), findsOneWidget);
      await tester.tap(find.byKey(ChatRatingCard.choiceKey(4)));
      await tester.pump(const Duration(milliseconds: 16));
      const four = GraineChatRating(value: 4, scale: 5, style: GraineChatRatingStyle.stars);
      expect(conn.sent('app_event'), <Object?>[ChatRatings.frame(four)]);
      expect(g.chat.rating, four);
      expect(rated, <GraineChatRating>[four]);
      expect(find.byKey(ChatRatingCard.thanksKey), findsOneWidget);
      await tester.tap(find.byKey(ChatRatingCard.choiceKey(5)));
      await tester.pump();
      expect(conn.sent('app_event'), hasLength(1), reason: 'one answer per conversation');
      final chosen = tester.getSemantics(find.byKey(ChatRatingCard.choiceKey(4)));
      expect(chosen.label, '4 stars');
      await tester.pumpWidget(const SizedBox());
      await finish(tester, g);
    });

    testWidgets('the rating on a narrow phone: five faces in one row inside the card, at any text size, nothing overflows',
        (WidgetTester tester) async {
      final t = style('classic', chat: <String, Object?>{
        'rating': <String, Object?>{'show': true, 'style': 'emoji'},
      });
      expect(t.chat.cards.border && t.shape.borderWidth > 0, isTrue, reason: 'an outlined card: the outline takes none of the room');
      final pad = t.spacing.cardPadding;
      // The rows' width: the window's, inside the thread's own side padding.
      final thread = 260 - 2 * t.chat.density.edge;
      final fit = ChatRatings.layout('emoji', thread, pad);
      expect(fit.size, lessThan(44), reason: 'too narrow for full-size faces: they are made smaller together');
      const five = GraineChatRating(value: 5, scale: 5, style: GraineChatRatingStyle.emoji);
      for (final scale in <double>[1, 2]) {
        for (final rating in <GraineChatRating?>[null, five]) {
          final why = 'text ×$scale${rating == null ? '' : ', chosen'}';
          await tester.pumpWidget(host(
            SizedBox(
              width: 260,
              height: 600,
              child: window(t,
                  turns: <GraineChatTurn>[agent('a1', 'Glad I could help. Bye!')],
                  fill: true,
                  ended: true,
                  rating: rating,
                  onRate: (GraineChatRatingStyle s, int v) {}),
            ),
            size: const Size(260, 600),
            scale: scale,
          ));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: why);
          expect(tester.getSize(find.byKey(ChatWindow.ratingKey)).width, closeTo(thread, 0.01), reason: why);
          final card = tester.getRect(find.byKey(ChatRatingCard.cardKey));
          expect(card.width, closeTo(fit.width, 1e-6), reason: why);
          final faces = <Rect>[for (var v = 1; v <= 5; v++) tester.getRect(find.byKey(ChatRatingCard.choiceKey(v)))];
          for (var i = 0; i < faces.length; i++) {
            final face = faces[i];
            expect(face.size, within<Size>(distance: 1e-6, from: Size(fit.size, fit.size)), reason: '$why: face ${i + 1}');
            expect(face.top, closeTo(faces.first.top, 1e-6), reason: '$why: one row');
            expect(face.left, greaterThanOrEqualTo(card.left + pad - 1e-6), reason: '$why: face ${i + 1} inside the card');
            expect(face.right, lessThanOrEqualTo(card.right - pad + 1e-6), reason: '$why: face ${i + 1} inside the card');
            expect(face.bottom, lessThanOrEqualTo(card.bottom - pad + 1e-6), reason: '$why: face ${i + 1} inside the card');
            if (i > 0) expect(face.left - faces[i - 1].right, closeTo(fit.gap, 1e-6), reason: '$why: the gap');
            final text = tester.widget<Text>(find.text(ChatRatings.emoji[i]));
            expect(text.textScaler, TextScaler.noScaling, reason: '$why: a picture, never scaled with the text size');
            expect(text.style?.fontSize, closeTo(fit.glyph, 1e-9), reason: why);
          }
          final chosenFace = find.descendant(of: find.byKey(ChatRatingCard.choiceKey(5)), matching: find.byType(Transform));
          expect(tester.widget<Transform>(chosenFace).transform.getMaxScaleOnAxis(), closeTo(rating == null ? 1 : 1.15, 1e-6),
              reason: '$why: the chosen face, scaled');
          expect(find.byKey(ChatRatingCard.thanksKey), rating == null ? findsNothing : findsOneWidget, reason: why);
        }
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("the agent's quick replies: chips under its turn; a tap is the user's own message, and they go",
        (WidgetTester tester) async {
      final conn = Connector();
      final g = makeApp(tester, conn, install: true);
      addTearDown(() => GraineInApp.maybeInstance == g ? GraineInApp.resetForTesting() : null);
      await g.loadSession();
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(400, 800)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(width: 400, height: 800, child: GraineChat(app: g, design: ResolvedDesign.fromJson(cases.first['design'])!)),
        ),
      ));
      await tester.pump();
      await tester.pump();
      final s = conn.last;
      s.say(<String, Object?>{'type': 'text', 'data': '<beginning_of_stream>How can I help?<end_of_stream>'});
      s.say(<String, Object?>{
        'type': 'quick_replies',
        'replies': <Object?>[
          'Where is it?',
          <String, Object?>{'label': 'Talk to someone', 'text': "I'd like to talk to someone"},
        ],
      });
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump();
      expect(g.chat.quickReplies, hasLength(2));
      expect(find.text('Talk to someone'), findsOneWidget);
      await tester.tap(find.byKey(ChatWindow.quickReplyKey(1)));
      await tester.pump(const Duration(milliseconds: 16));
      expect(s.sent.last, <String, Object?>{'type': 'text', 'data': "I'd like to talk to someone"});
      expect(g.chat.quickReplies, isEmpty);
      expect(find.byKey(ChatWindow.quickRepliesKey), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await finish(tester, g);
    });

    testWidgets('a reply still arriving is revealed at the contract pace, the rest when it ends, then whole; at once under reduced motion',
        (WidgetTester tester) async {
      final t = style('classic');
      expect(t.motion.durationMs, greaterThan(0));
      final words = 'The quick reply streams in small pieces, and the window draws it smoothly at a steady pace now.';
      expect(words.length, greaterThan(60));
      String shown() => tester
          .widgetList<Text>(find.descendant(of: find.byKey(ChatWindow.messageKey(0)), matching: find.byType(Text)))
          .map((Text w) => w.textSpan?.toPlainText() ?? w.data ?? '')
          .join();
      await tester.pumpWidget(host(window(t, turns: <GraineChatTurn>[agent('t1', words, live: true)])));
      expect(shown(), '', reason: 'nothing yet');
      await tester.pump(); // the reveal's first frame
      await tester.pump(const Duration(milliseconds: 16));
      var expected = ChatReveal.length(0, words.length, 16);
      expect(shown(), words.substring(0, expected));
      await tester.pump(const Duration(milliseconds: 100));
      expected = ChatReveal.length(expected, words.length, 100);
      expect(shown(), words.substring(0, expected));
      // The turn ends: the rest at the same pace, then the whole.
      await tester.pumpWidget(host(window(t, turns: <GraineChatTurn>[agent('t1', words)])));
      expect(shown().length, lessThan(words.length));
      await tester.pump(const Duration(seconds: 2));
      expect(shown(), words);

      await tester.pumpWidget(host(window(t, turns: <GraineChatTurn>[agent('t2', words, live: true)]), still: true));
      expect(shown(), words, reason: 'reduced motion: drawn as it arrives');
    });

    testWidgets("the agent's words formatted: bold at the strong weight, links underlined in the link colour and opened by the app",
        (WidgetTester tester) async {
      final t = style('classic');
      final opened = <Uri>[];
      await tester.pumpWidget(host(window(t,
          turns: <GraineChatTurn>[agent('a1', 'See **this** and [the guide](https://example.com/g).\n- one\n- two')],
          onOpenLink: opened.add)));
      final texts = tester.widgetList<Text>(find.descendant(of: find.byKey(ChatWindow.messageKey(0)), matching: find.byType(Text))).toList();
      final first = texts.first.textSpan! as TextSpan;
      final spans = first.children!.cast<TextSpan>();
      expect(spans[1].text, 'this');
      expect(spans[1].style!.fontWeight, FontWeight.values[(t.font.weights.strong / 100).round() - 1]);
      final link = spans.firstWhere((TextSpan s) => s.recognizer != null);
      expect(link.text, 'the guide');
      expect(link.style!.decoration, TextDecoration.underline);
      expect(link.style!.color, hex(t.chat.bubbles.agent.link));
      (link.recognizer! as TapGestureRecognizer).onTap!();
      expect(opened, <Uri>[Uri.parse('https://example.com/g')]);
      expect(find.text('•'), findsNWidgets(2), reason: 'bullets');
    });

    testWidgets('a long press copies the plain words and says "Copied"', (WidgetTester tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(host(window(style('classic'), turns: <GraineChatTurn>[agent('a1', '**Hello** there')])));
      await tester.longPress(find.byKey(ChatWindow.messageKey(0)));
      await tester.pump();
      expect(copied, 'Hello there');
      expect(find.byKey(ChatWindow.copiedKey), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(ChatWindow.copiedKey), findsNothing);
    });

    testWidgets('a message waiting, and one not sent: the words under it, the retry on a tap, what a screen reader hears',
        (WidgetTester tester) async {
      var retried = 0;
      final t = style('classic');
      await tester.pumpWidget(host(window(t, turns: <GraineChatTurn>[user('u1', 'Hello?', delivery: GraineChatDelivery.sending)])));
      expect(find.text(ChatMessageRow.waitingWords), findsOneWidget);
      final faded = tester.widget<Opacity>(find.descendant(of: find.byKey(ChatWindow.messageKey(0)), matching: find.byType(Opacity)).first);
      expect(faded.opacity, 0.6);
      await tester.pumpWidget(host(window(t,
          turns: <GraineChatTurn>[user('u1', 'Hello?', delivery: GraineChatDelivery.failed)], onRetry: () => retried++)));
      expect(find.text(ChatMessageRow.failedWords), findsOneWidget);
      expect(tester.widget<Text>(find.text(ChatMessageRow.failedWords)).style!.color, hex(t.colors.danger));
      await tester.tap(find.text(ChatMessageRow.failedWords));
      await tester.tap(find.byKey(ChatWindow.messageKey(0)));
      expect(retried, 2);
      final label = tester.getSemantics(find.byType(ChatMessageRow)).label;
      expect(label, startsWith('You: Hello?'));
      expect(label, endsWith(', not sent. Double-tap to retry.'));
    });

    testWidgets('the calm banner: reconnecting, or offline with a message waiting — never otherwise', (WidgetTester tester) async {
      final t = style('classic');
      await tester.pumpWidget(host(window(t, turns: <GraineChatTurn>[agent('a1', 'Hi')], reconnecting: true, online: false)));
      expect(find.byKey(ChatWindow.bannerKey), findsOneWidget);
      expect(find.descendant(of: find.byKey(ChatWindow.bannerKey), matching: find.byType(GraineLoaderView)), findsOneWidget);
      expect(find.text('Reconnecting…'), findsNWidgets(2), reason: 'the banner and the header');
      await tester.pumpWidget(host(window(t,
          turns: <GraineChatTurn>[user('u1', 'Hi', delivery: GraineChatDelivery.failed)], offline: true, online: false)));
      expect(find.text(ChatReconnectBanner.offlineWords), findsOneWidget);
      await tester.pumpWidget(host(window(t, turns: <GraineChatTurn>[agent('a1', 'Hi')], offline: true, online: false)));
      expect(find.byKey(ChatWindow.bannerKey), findsNothing, reason: 'nothing waiting: nothing to say');
    });

    testWidgets('the typing indicator in each style, announced as the agent typing', (WidgetTester tester) async {
      final turns = <GraineChatTurn>[user('u1', 'Hi')];
      await tester.pumpWidget(host(window(style('classic'), turns: turns, typing: true)));
      expect(find.descendant(of: find.byKey(ChatWindow.typingKey), matching: find.byType(GraineLoaderView)), findsOneWidget);
      expect(tester.getSemantics(find.byKey(ChatWindow.typingKey)).label, 'Assistant is typing');
      await tester.pumpWidget(host(window(style('soft'), turns: turns, typing: true)));
      final dots = find.descendant(
          of: find.byKey(ChatWindow.typingKey),
          matching: find.byWidgetPredicate((Widget w) => w is Container && w.constraints?.maxWidth == 7));
      expect(dots, findsNWidgets(3));
      await tester.pumpWidget(host(window(style('minimal'), turns: turns, typing: true)));
      expect(find.descendant(of: find.byKey(ChatWindow.typingKey), matching: find.text('Typing…')), findsOneWidget);
      await tester.pumpWidget(host(window(style('minimal'), turns: turns, typing: true), still: true));
      expect(tester.takeException(), isNull);
    });

    testWidgets('scrolled up, nothing moves; a pill counts what is new and takes the reader back to it', (WidgetTester tester) async {
      final t = style('classic');
      final turns = <GraineChatTurn>[
        for (var i = 0; i < 30; i++) i.isEven ? agent('a$i', 'Agent line $i') : user('u$i', 'User line $i'),
      ];
      await tester.pumpWidget(host(full(window(t, turns: turns, fill: true))));
      await tester.pump();
      expect(find.byKey(ChatWindow.pillKey), findsNothing, reason: 'at the newest row');
      await tester.drag(find.byKey(ChatWindow.threadKey), const Offset(0, 900));
      await tester.pumpAndSettle();
      expect(find.byKey(ChatWindow.pillKey), findsOneWidget);
      final before = tester.getTopLeft(find.text('Agent line 10')).dy;
      await tester.pumpWidget(host(full(window(t, turns: <GraineChatTurn>[...turns, agent('n1', 'Something new')], fill: true))));
      await tester.pump();
      expect(tester.getTopLeft(find.text('Agent line 10')).dy, before, reason: 'nothing moved under the reader');
      expect(find.text('1 new'), findsOneWidget);
      await tester.tap(find.byKey(ChatWindow.pillKey));
      await tester.pumpAndSettle();
      expect(find.byKey(ChatWindow.pillKey), findsNothing);
      expect(find.text('Something new'), findsOneWidget);
    });

    testWidgets('a long conversation is lazy: only what is on screen is built', (WidgetTester tester) async {
      final turns = <GraineChatTurn>[for (var i = 0; i < 200; i++) agent('a$i', 'Line $i', when: at.add(Duration(minutes: 3 * i)))];
      await tester.pumpWidget(host(full(window(style('classic'), turns: turns, fill: true))));
      await tester.pump();
      await tester.pump();
      expect(find.text('Line 199'), findsOneWidget);
      expect(find.text('Line 0'), findsNothing);
    });
  });

  // ── accessibility, direction, text size ────────────────────────────────────

  group('right to left, and the user\'s text size', () {
    testWidgets("RTL: the user's bubbles on the left, the tail and the send icon mirrored", (WidgetTester tester) async {
      final classic = style('classic');
      await tester.pumpWidget(host(window(classic, turns: <GraineChatTurn>[agent('a1', 'Hello'), user('u1', 'Hi')]), dir: TextDirection.rtl));
      final frame = tester.getRect(find.byType(ChatWindow));
      final edge = classic.chat.density.edge + classic.shape.borderWidth;
      expect(tester.getRect(find.byKey(ChatWindow.messageKey(1))).left, closeTo(frame.left + edge, 0.01), reason: 'the trailing side is the left');
      expect(tester.getRect(find.byKey(ChatWindow.messageKey(0))).right, closeTo(frame.right - edge, 0.01));
      expect(find.descendant(of: find.byKey(ChatWindow.sendKey), matching: find.byType(Transform)), findsOneWidget, reason: 'the send icon mirrors');

      final bold = style('bold');
      await tester.pumpWidget(host(window(bold, turns: <GraineChatTurn>[user('u1', 'Hi')]), dir: TextDirection.rtl));
      final tail = (tester.widget<Container>(find.byKey(ChatWindow.messageKey(0))).decoration! as ShapeDecoration).shape as ChatBubbleBorder;
      expect(tail.geometry.tail, BubbleTail.left, reason: "the user's tail on the trailing side, mirrored");
    });

    testWidgets('fixed heights grow with the text size', (WidgetTester tester) async {
      final t = style('classic', chat: <String, Object?>{'suggestions': <String>['Track it']});
      await tester.pumpWidget(host(window(t, turns: <GraineChatTurn>[agent('a1', 'Hello')]), scale: 3.2));
      expect(tester.getSize(find.byKey(ChatWindow.headerKey)).height, greaterThan(50));
      expect(tester.getSize(find.byKey(ChatWindow.composerKey)).height, greaterThan(40));
      expect(tester.getSize(find.descendant(of: find.byKey(ChatWindow.suggestionKey(0)), matching: find.byType(Container)).first).height,
          greaterThan(34));
      expect(tester.takeException(), isNull);
    });

    testWidgets('each bubble is one element: who, the plain words, the time; Copy among its actions', (WidgetTester tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(window(style('cozy'), turns: <GraineChatTurn>[agent('a1', 'Your **case** is open')])));
      final node = tester.getSemantics(find.byType(ChatMessageRow));
      expect(node.label, 'Assistant: Your case is open, 9:41 PM');
      expect(node.getSemanticsData().customSemanticsActionIds, isNotEmpty);
      handle.dispose();
    });
  });

  // ── every design ───────────────────────────────────────────────────────────

  group('every design in design.json', () {
    testWidgets('draws a whole conversation — compact at 320 wide and full, light and dark — without a fault',
        (WidgetTester tester) async {
      final turns = <GraineChatTurn>[
        agent('a1', 'Hi! I can **compare** the two options for you, side by side, with [the details](https://example.com).', when: at),
        user('u1', 'Yes please, and the timings too', when: at.add(const Duration(seconds: 30))),
        user('u2', 'Thanks', when: at.add(const Duration(seconds: 40)), delivery: GraineChatDelivery.failed),
        agent('a2', 'Here they are:\n1. Option one\n2. Option two', when: at.add(const Duration(minutes: 1))),
      ];
      const pin = GraineChatPin(title: 'Option comparison', subtitle: 'Two options', badge: 'New');
      final replies = <GraineQuickReply>[const GraineQuickReply(label: 'Option one', text: 'Option one')];
      for (final c in cases) {
        final design = ResolvedDesign.fromJson(c['design'])!;
        for (final t in <ThemeTokens>[design.light, design.dark]) {
          final why = '${c['config']} ${t.scheme}';
          for (final fill in <bool>[false, true]) {
            final w = ChatWindow(
              look: ChatLook.design(t),
              heading: 'Priya from Northwind',
              messages: <Caption>[for (final x in turns) x.caption],
              turns: turns,
              online: true,
              typing: true,
              onSend: (String _) {},
              onCollapse: () {},
              fill: fill,
              now: () => at,
              pin: pin,
              quickReplies: replies,
              ended: true,
              onRate: (GraineChatRatingStyle s, int v) {},
              onAttach: () {},
              onCall: () {},
              onRetry: () {},
            );
            await tester.pumpWidget(host(fill ? SizedBox(width: 320, height: 640, child: w) : w, size: const Size(320, 640)));
            await tester.pump(const Duration(milliseconds: 50));
            expect(tester.takeException(), isNull, reason: '$why ${fill ? 'full' : 'compact'}');
          }
        }
      }
      await tester.pumpWidget(const SizedBox());
    });
  });
}

/// A design shadow as the SDK draws one.
List<BoxShadow> shadowsOfTest(ThemeShadow? s) => s == null
    ? const <BoxShadow>[]
    : <BoxShadow>[
        BoxShadow(
            color: Color.lerp(const Color(0x00000000), Color(int.parse('FF${s.color.substring(1)}', radix: 16)), s.opacity)!,
            offset: Offset(0, s.y),
            blurRadius: s.blur,
            spreadRadius: s.spread),
      ];
