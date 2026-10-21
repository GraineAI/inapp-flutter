// CONVERSATIONS CONTINUE (contract §2.6): sdk/contract/history.json, hand-
// written from CONTINUITY.md and run by every SDK — the history frame read,
// folded into the turns on screen (or, when the server starts over, the old
// opening replaced or a new conversation marked under the earlier lines), and
// laid out as the chat window draws it — plus the words the rows use and the
// two copy fixes. A missing file FAILS.
// Imports ONLY lib/src/core.
import 'dart:convert';

import 'package:graine_inapp/src/core/core.dart';
import 'package:test/test.dart';

import 'contract_files.dart';

DateTime _at(String iso) => ChatHistoryReader.time(iso)!;

String _role(GraineChatRole r) => r == GraineChatRole.agent ? 'agent' : 'customer';

/// A transcript after [c]'s steps (`restore` and `fresh`): {agent} a finished
/// agent turn, {customer, delivery?}, {opened} — what was waiting goes out —
/// and {history}, read off the socket as the chat reads it.
ChatTranscript _run(Map<String, Object?> c) {
  final t = ChatTranscript();
  var clock = 0;
  for (final step in (c['steps']! as List<Object?>).cast<Map<String, Object?>>()) {
    final at = DateTime.fromMillisecondsSinceEpoch(clock += 1000, isUtc: true);
    if (step.containsKey('agent')) {
      t.agent(step['agent']! as String, at);
      t.turnEnded();
    } else if (step.containsKey('customer')) {
      final delivery = step['delivery'] ?? 'sent';
      t.customer(step['customer']! as String, at, pending: delivery != 'sent');
      if (delivery == 'failed') t.failPending();
    } else if (step['opened'] == true) {
      t.opened();
      for (final m in t.turns.where((GraineChatTurn m) => m.delivery == GraineChatDelivery.sending)) {
        t.sent(m.id);
      }
    } else if (step.containsKey('history')) {
      final frame = ChatFrame.parse(jsonEncode(step['history']));
      if (frame is ChatHistory) t.restore(frame.turns);
    } else {
      fail('${c['name']}: unknown step $step');
    }
  }
  return t;
}

/// [t]'s turns are [c]'s `turns`: a field an expected turn leaves out is restored
/// false, the chat channel, and (a customer's) delivered.
void _expectTurns(Map<String, Object?> c, ChatTranscript t) {
  final name = c['name'];
  final want = (c['turns']! as List<Object?>).cast<Map<String, Object?>>();
  final got = t.turns;
  expect(got.length, want.length, reason: '$name: $got');
  for (var i = 0; i < want.length; i++) {
    final w = want[i];
    final turn = got[i];
    expect(_role(turn.role), w['role'], reason: '$name #$i role');
    expect(turn.text, w['text'], reason: '$name #$i text');
    expect(turn.restored, w['restored'] ?? false, reason: '$name #$i restored');
    expect(turn.channel.name, w['channel'] ?? 'chat', reason: '$name #$i channel');
    if (turn.role == GraineChatRole.user) expect(turn.delivery!.name, w['delivery'] ?? 'sent', reason: '$name #$i delivery');
    if (w['id'] != null) expect(turn.id, w['id'], reason: '$name #$i id');
    if (w['at'] != null) expect(turn.at.millisecondsSinceEpoch, _at(w['at']! as String).millisecondsSinceEpoch);
    if (turn.restored) expect(turn.live || turn.proactive, isFalse, reason: '$name #$i: not live, not volunteered');
  }
}

/// The indices of [t]'s turns a "Disconnected · new conversation" row is drawn before.
List<int> _marked(ChatTranscript t) {
  final marks = ChatMarks.of(t);
  return <int>[
    for (var i = 0; i < t.turns.length; i++)
      if (marks.contains(t.turns[i].id)) i,
  ];
}

void main() {
  late Map<String, Object?> contract;
  setUpAll(() async => contract = await contractJson('contract/history.json'));

  List<Map<String, Object?>> section(String name) {
    final list = (contract[name] as List<Object?>).cast<Map<String, Object?>>();
    expect(list, isNotEmpty, reason: 'section $name is empty');
    return list;
  }

  group('history.json', () {
    test('frames are read as the contract says', () {
      for (final c in section('frames')) {
        final name = c['name'];
        final got = ChatHistoryReader.read(c['frame']! as Map<String, Object?>);
        final want = c['turns'] as List<Object?>?;
        if (want == null) {
          expect(got, isNull, reason: '$name: the frame must be ignored');
          continue;
        }
        expect(got, isNotNull, reason: '$name: a readable frame');
        expect(got!.length, want.length, reason: '$name: $got');
        for (var i = 0; i < want.length; i++) {
          final w = want[i]! as Map<String, Object?>;
          final t = got[i];
          expect(t.id, w['id'], reason: '$name #$i id');
          expect(_role(t.role), w['role'], reason: '$name #$i role');
          expect(t.text, w['text'], reason: '$name #$i text');
          expect(t.at.millisecondsSinceEpoch, _at(w['at']! as String).millisecondsSinceEpoch, reason: '$name #$i at');
          expect(t.channel.name, w['channel'] ?? 'chat', reason: '$name #$i channel');
          expect(t.restored && !t.live && !t.proactive, isTrue, reason: '$name #$i: delivered, restored');
          if (t.role == GraineChatRole.user) expect(t.delivery, GraineChatDelivery.sent);
          if (w.containsKey('session')) expect(t.session, w['session'], reason: '$name #$i session');
        }
      }
    });

    // 0.14.0 — sessions.
    test('sessionFrame: the session frame gives the chat its session id', () {
      for (final c in section('sessionFrame')) {
        final frame = ChatFrame.parse(jsonEncode(c['frame']));
        expect(frame, isA<ChatSessionStart>(), reason: '${c['name']}');
        final t = ChatTranscript()..opened();
        t.sessionStarted((frame! as ChatSessionStart).id);
        expect(t.sessionId, c['sessionId'], reason: '${c['name']}');
      }
    });

    test('sessions: derived from the turns, oldest first', () {
      for (final c in section('sessions')) {
        final raw = (c['turns']! as List<Object?>).cast<Map<String, Object?>>();
        final turns = <GraineChatTurn>[
          for (var i = 0; i < raw.length; i++)
            GraineChatTurn(
              id: 't$i',
              role: raw[i]['role'] == 'agent' ? GraineChatRole.agent : GraineChatRole.user,
              text: raw[i]['text']! as String,
              at: _at(raw[i]['at']! as String),
              restored: true,
              channel: raw[i]['channel'] == 'voice' ? GraineChatChannel.voice : GraineChatChannel.chat,
              session: raw[i]['session'] as String?,
            ),
        ];
        final got = ChatSessions.of(turns, c['sessionId'] as String?);
        final want = (c['sessions']! as List<Object?>).cast<Map<String, Object?>>();
        expect(got.length, want.length, reason: '${c['name']}: $got');
        for (var i = 0; i < want.length; i++) {
          final w = want[i];
          expect(got[i].id, w['id'], reason: '${c['name']} #$i id');
          expect(got[i].startedAt, _at(w['startedAt']! as String), reason: '${c['name']} #$i startedAt');
          expect(got[i].endedAt, _at(w['endedAt']! as String), reason: '${c['name']} #$i endedAt');
          expect(got[i].channel.name, w['channel'], reason: '${c['name']} #$i channel');
          expect(got[i].turns, w['turns'], reason: '${c['name']} #$i turns');
          expect(got[i].current, w['current'], reason: '${c['name']} #$i current');
        }
      }
    });

    test("a line typed before the chat connected, and what is said before the session frame, take that connection's session", () {
      DateTime at(int s) => DateTime.fromMillisecondsSinceEpoch(s * 1000, isUtc: true);
      final t = ChatTranscript();
      final typed = t.customer('Typed before it connected', at(1), pending: true);
      expect(t.turns.single.session, isNull, reason: 'no session yet');
      t.opened();
      t.sent(typed.id);
      t.agent('Hello!', at(2));
      t.sessionStarted('s-2');
      t.turnEnded();
      t.customer('How are you?', at(3));
      expect(t.turns.map((GraineChatTurn x) => x.session), <String?>['s-2', 's-2', 's-2']);
      expect(ChatSessions.of(t.turns, t.sessionId).map((GraineChatSessionInfo x) => '${x.id}:${x.turns}:${x.current}'),
          <String>['s-2:3:true']);
      t.closed();
      expect(t.sessionId, isNull, reason: 'its session ended with the connection');
    });

    test('an identity change clears the session id, and the unsent lines it keeps join the next session', () {
      DateTime at(int s) => DateTime.fromMillisecondsSinceEpoch(s * 1000, isUtc: true);
      final t = ChatTranscript()..opened();
      t.sessionStarted('s-1');
      t.agent('Hi.', at(1));
      t.turnEnded();
      expect(t.turns.single.session, 's-1');
      t.closed();
      t.customer('Typed while down', at(2), pending: true);
      t.forgetAllButUnsent();
      expect(t.sessionId, isNull);
      expect(t.turns.map((GraineChatTurn x) => '${x.text}:${x.session}'), <String>['Typed while down:null']);
      t.opened();
      t.sent(t.turns.single.id);
      t.sessionStarted('s-2');
      expect(t.turns.single.session, 's-2');
    });

    test('a waiting line sent after the session frame takes that session, once', () {
      DateTime at(int s) => DateTime.fromMillisecondsSinceEpoch(s * 1000, isUtc: true);
      final t = ChatTranscript()..opened();
      t.sessionStarted('s-3');
      final queued = t.customer('Sent late', at(1), pending: true);
      expect(t.turns.single.session, isNull, reason: 'waiting: not carried yet');
      t.sent(queued.id);
      expect(t.turns.single.session, 's-3', reason: 'carried by the connection whose session is known');
      t.sessionStarted('s-4');
      expect(t.turns.single.session, 's-3', reason: 'never moved to a later session');
    });

    test('restore follows the steps', () {
      for (final c in section('restore')) {
        _expectTurns(c, _run(c));
      }
    });

    test('a new conversation under earlier lines: the opening replaced, or a marker before the new one', () {
      for (final c in section('fresh')) {
        final t = _run(c);
        _expectTurns(c, t);
        expect(_marked(t), <int>[for (final i in c['marks']! as List<Object?>) (i! as num).toInt()], reason: '${c['name']}: marks');
      }
    });

    test('rows are laid out as the contract says', () {
      for (final c in section('rows')) {
        final name = c['name'];
        final offset = Duration(minutes: (c['utcOffsetMinutes']! as num).toInt());
        DateTime local(DateTime t) => t.toUtc().add(offset);
        final raw = (c['turns']! as List<Object?>).cast<Map<String, Object?>>();
        final turns = <GraineChatTurn>[
          for (var i = 0; i < raw.length; i++)
            GraineChatTurn(
              id: 't$i',
              role: raw[i]['role'] == 'agent' ? GraineChatRole.agent : GraineChatRole.user,
              text: raw[i]['text']! as String,
              at: _at(raw[i]['at']! as String),
              restored: true,
              channel: raw[i]['channel'] == 'voice' ? GraineChatChannel.voice : GraineChatChannel.chat,
            ),
        ];
        final shape = <String>[
          for (final row in ChatRows.build(turns, now: _at(c['now']! as String), local: local))
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
        expect(shape, want, reason: '$name');
      }
    });
  });

  group('a new conversation under earlier lines', () {
    DateTime at(int s) => DateTime.fromMillisecondsSinceEpoch(s * 1000, isUtc: true);

    /// A conversation the customer took part in.
    ChatTranscript talked() {
      final t = ChatTranscript()..opened();
      t.agent('Hi Meera!', at(1));
      t.turnEnded();
      t.customer('Is my dose due?', at(2));
      t.agent('Yes, at 8 pm.', at(3));
      t.turnEnded();
      return t;
    }

    final card = GraineWidget.adopt(<String, Object?>{
      'widget_id': 'doses:1',
      'kind': 'product_list',
      'data': <String, Object?>{
        'items': <Object?>[<String, Object?>{'id': 'morning', 'title': 'Morning'}],
      },
    }, 'https://www.graine.ai')!;

    test("the agent's start marker is its first turn too: the marker waits for the turn it stands before", () {
      final t = talked()
        ..opened()
        ..turnStarted();
      expect(_marked(t), isEmpty, reason: 'nothing of the new conversation is here yet');
      t.agent('Hi Meera!', at(4));
      expect(_marked(t), <int>[3]);
      t.turnEnded();
      t.opened();
      t.turnStarted();
      expect(t.turns, hasLength(3), reason: 'an opening nobody answered goes as the next one starts');
      t.agent('Hi Meera!', at(5));
      expect(_marked(t), <int>[3], reason: 'its marker stands before the new one');
    });

    test('so is a component: an opening nobody answered goes, and the component is a turn of its own', () {
      final t = ChatTranscript()..opened();
      t.agent('Hi Meera!', at(1));
      t.turnEnded();
      t.opened();
      t.component(card, at(2));
      expect(t.turns.single.component, same(card));
      expect(ChatMarks.of(t), isEmpty);

      final u = talked()..opened();
      u.component(card, at(4));
      u.agent('Pick one.', at(5));
      expect(_marked(u), <int>[3], reason: 'the component went with the last turn; the marker waited for the next');
    });

    test('a history that restores nothing still says the conversation continued: no marker, nothing replaced', () {
      final t = talked()..opened();
      final frame = ChatFrame.parse('{"type":"history","turns":[],"continued":true}');
      expect(frame, isA<ChatHistory>());
      expect(t.restore((frame! as ChatHistory).turns), isFalse);
      t.agent('Hi Meera!', at(4));
      expect(ChatMarks.of(t), isEmpty);
      expect(t.turns, hasLength(4));
      expect(ChatFrame.parse('{"type":"history","turns":"none"}'), isA<ChatHistory>(),
          reason: 'turns that are not a list restore nothing, and still say so');
    });

    test('clear takes the markers away with the lines; a first connection after it has nothing to mark', () {
      final t = talked()..opened();
      t.agent('Hi Meera!', at(4));
      expect(_marked(t), <int>[3]);
      t.clear();
      expect(ChatMarks.of(t), isEmpty);
      t.opened();
      t.agent('Hi Meera!', at(5));
      expect(ChatMarks.of(t), isEmpty);
    });

    test('the oldest turns go past max, and a marker with its turn', () {
      final t = ChatTranscript(max: 4)..opened();
      t.agent('Hi Meera!', at(1));
      t.turnEnded();
      t.customer('Is my dose due?', at(2));
      t.opened();
      t.agent('Hi Meera!', at(3));
      t.turnEnded();
      expect(_marked(t), <int>[2]);
      t.customer('a', at(4));
      t.customer('b', at(5));
      expect(_marked(t), <int>[1], reason: 'the turn moved up; its marker with it');
      t.customer('c', at(6));
      t.customer('d', at(7));
      expect(ChatMarks.of(t), isEmpty, reason: 'nothing earlier is left to set it under');
    });

    test('the words', () {
      expect(ChatMarks.label, 'Disconnected · new conversation');
      expect(ChatMarks.spoken, 'Disconnected. A new conversation started.');
      expect(ChatRows.newConversationLabel, ChatMarks.label);
      expect(ChatRows.newConversationSpoken, ChatMarks.spoken);
    });

    // 0.14.0 — contract/PUBLIC-STATE.md §1: the row builder lays the markers out.
    test("ChatRows.build: every contract case's markers, each just before the turn it marks", () {
      for (final c in section('fresh')) {
        final t = _run(c);
        final rows = ChatRows.build(t.turns, now: DateTime.utc(2030), newConversationBefore: ChatMarks.of(t));
        final marked = <int>[
          for (var i = 0; i < rows.length; i++)
            if (rows[i] is ChatNewConversationRow) (rows[i + 1] as ChatTurnRow).index,
        ];
        expect(marked, <int>[for (final i in c['marks']! as List<Object?>) (i! as num).toInt()], reason: '${c['name']}');
      }
    });

    test('ChatRows.build: after the day separator, never above the first turn, and a marked voice turn starts its own row', () {
      final now = _at('2026-10-21T12:00:00Z');
      DateTime utc(DateTime t) => t.toUtc();
      GraineChatTurn turn(String id, String iso, {bool voice = false}) => GraineChatTurn(
          id: id,
          role: GraineChatRole.agent,
          text: id,
          at: _at(iso),
          channel: voice ? GraineChatChannel.voice : GraineChatChannel.chat);
      final turns = <GraineChatTurn>[
        turn('a', '2026-10-20T09:00:00Z'),
        turn('v1', '2026-10-20T09:05:00Z', voice: true),
        turn('v2', '2026-10-20T09:06:00Z', voice: true),
        turn('b', '2026-10-21T09:00:00Z'),
      ];
      List<String> shape(Set<String> marks) => <String>[
            for (final row in ChatRows.build(turns, now: now, local: utc, newConversationBefore: marks))
              switch (row) {
                ChatNewConversationRow() => 'fresh:${row.before}',
                ChatDayRow() => 'day:${row.contractKey}',
                ChatVoiceRow() => 'voice:${row.first}-${row.last}',
                ChatTurnRow() => 'turn:${row.index}',
              },
          ];
      expect(shape(<String>{'b'}), <String>['day:yesterday', 'turn:0', 'voice:1-2', 'day:today', 'fresh:b', 'turn:3'],
          reason: "after the turn's day separator");
      expect(shape(<String>{'v2'}), <String>['day:yesterday', 'turn:0', 'voice:1-1', 'fresh:v2', 'voice:2-2', 'day:today', 'turn:3'],
          reason: 'a call row never runs across a new conversation');
      expect(shape(<String>{'a'}), <String>['day:yesterday', 'turn:0', 'voice:1-2', 'day:today', 'turn:3'],
          reason: 'nothing earlier to set apart: no marker above the first turn');
      expect(shape(<String>{'nobody'}), shape(<String>{}), reason: 'an id not among the turns marks nothing');
    });

    test("a chat written before it draws the marker as a separator, in the marker's words", () {
      final now = _at('2026-10-21T12:00:00Z');
      final row = ChatNewConversationRow('t9', ChatDay.today, '2026-10-21', now);
      // An exhaustive switch from before 0.14.0 still compiles and draws it — as a day line.
      final drawn = switch (row as ChatRow) {
        ChatDayRow() => ChatRows.dayLabel(row, now: now),
        ChatVoiceRow() => 'call',
        ChatTurnRow() => 'bubble',
      };
      expect(drawn, 'Disconnected · new conversation');
      expect(row.key, 'fresh-t9', reason: 'its own key, never the day separator\'s');
    });
  });

  group('the words', () {
    final now = _at('2026-10-14T06:30:00Z');
    DateTime india(DateTime t) => t.toUtc().add(const Duration(minutes: 330));

    test('Today, Yesterday, a date — with the year when it is not this one', () {
      ChatDayRow line(ChatDay day, String iso) => ChatDayRow(day, '', _at(iso));
      expect(ChatRows.dayLabel(line(ChatDay.today, '2026-10-14T05:00:00Z'), now: now, local: india), 'Today');
      expect(ChatRows.dayLabel(line(ChatDay.yesterday, '2026-10-13T05:00:00Z'), now: now, local: india), 'Yesterday');
      expect(ChatRows.dayLabel(line(ChatDay.date, '2026-10-10T08:00:00Z'), now: now, local: india), 'Sat 10 Oct');
      expect(ChatRows.dayLabel(line(ChatDay.date, '2025-12-31T08:00:00Z'), now: now, local: india), 'Wed 31 Dec 2025');
      expect(ChatRows.callLabel('6:05 PM'), 'Voice call · 6:05 PM');
      expect(ChatRows.callSpoken('6:05 PM'), 'Voice call at 6:05 PM');
    });

    test('rows keep stable keys; the starters and "New conversation" follow the history', () {
      final earlier = _at('2026-10-13T10:00:00Z');
      final turns = <GraineChatTurn>[
        GraineChatTurn(id: 'a1', role: GraineChatRole.agent, text: 'Hi', at: earlier, restored: true, channel: GraineChatChannel.voice),
        GraineChatTurn(id: 'a2', role: GraineChatRole.user, text: 'Yo', at: earlier, restored: true, channel: GraineChatChannel.voice),
        GraineChatTurn(id: 't1', role: GraineChatRole.user, text: 'Now', at: now),
      ];
      expect(ChatRows.build(turns, now: now, local: india).map((ChatRow r) => r.key),
          <String>['day-2026-10-13', 'voice-a1', 'day-2026-10-14', 't1']);

      final welcome = GraineChatTurn(id: 't1', role: GraineChatRole.agent, text: 'Hi!', at: now, proactive: true);
      final restored = GraineChatTurn(id: 'h1', role: GraineChatRole.agent, text: 'It ships today.', at: earlier, restored: true);
      expect(ChatRows.offersStarters(<GraineChatTurn>[]) && ChatRows.offersStarters(<GraineChatTurn>[welcome]), isTrue);
      expect(ChatRows.offersStarters(<GraineChatTurn>[restored]), isFalse, reason: 'never on a conversation that continues');
      expect(ChatRows.offersNewConversation(<GraineChatTurn>[welcome]), isFalse, reason: 'a live conversation is not an earlier one');
      expect(ChatRows.offersNewConversation(<GraineChatTurn>[restored, welcome]), isTrue);
    });

    test('a turn carries restored and channel through copyWith, equality and toString', () {
      final t = GraineChatTurn(id: 'h1', role: GraineChatRole.agent, text: 'Hi', at: now, restored: true, channel: GraineChatChannel.voice);
      final copy = t.copyWith(text: 'Hi!');
      expect(copy.restored && copy.channel == GraineChatChannel.voice, isTrue);
      expect(t == GraineChatTurn(id: 'h1', role: GraineChatRole.agent, text: 'Hi', at: now), isFalse);
      expect(t.toString(), contains('restored'));
      expect(GraineChatTurn(id: 't1', role: GraineChatRole.user, text: 'x', at: now).restored, isFalse);
    });
  });

  group('the copy', () {
    test('the multi-select button says how many more, never the label read as a verb', () {
      final taken = WidgetContent(GraineWidget.adopt(<String, Object?>{
        'widget_id': 'doses:1',
        'kind': 'product_list',
        'data': <String, Object?>{
          'selectLabel': 'Taken',
          'items': <Object?>[
            <String, Object?>{'id': 'morning', 'title': 'Morning'},
            <String, Object?>{'id': 'evening', 'title': 'Evening'},
          ],
        },
        'style': <String, Object?>{'select': 'many'},
      }, 'https://www.graine.ai')!);
      expect(taken.manyButtonLabel(0), 'Pick 2 more');
      expect(taken.manyButtonLabel(1), 'Pick 1 more');
      expect(taken.manyButtonLabel(2), 'Taken 2');
    });

    test('"Still listening" is a call\'s word', () {
      expect(WidgetContent.screenFooter('', typed: false), (label: 'STILL LISTENING', line: 'Tap one, or just say it.'));
      expect(WidgetContent.screenFooter('Pick a car', typed: false)?.line, 'Pick a car');
      expect(WidgetContent.screenFooter('Pick a car', typed: true), isNull, reason: 'a typed chat has no call to be on');
      expect(WidgetContent.closeLabel(typed: false), 'Close and keep talking');
      expect(WidgetContent.closeLabel(typed: true), 'Close');
    });
  });
}
