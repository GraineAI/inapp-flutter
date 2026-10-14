// CONVERSATIONS CONTINUE (contract §2.6): sdk/contract/history.json, hand-
// written from CONTINUITY.md and run by every SDK — the history frame read,
// folded into the turns on screen, and laid out as the chat window draws it —
// plus the words the rows use and the two copy fixes. A missing file FAILS.
// Imports ONLY lib/src/core.
import 'package:graine_inapp/src/core/core.dart';
import 'package:test/test.dart';

import 'contract_files.dart';

DateTime _at(String iso) => ChatHistoryReader.time(iso)!;

String _role(GraineChatRole r) => r == GraineChatRole.agent ? 'agent' : 'customer';

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
        }
      }
    });

    test('restore follows the steps', () {
      for (final c in section('restore')) {
        final name = c['name'];
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
            final restored = ChatHistoryReader.read(step['history']! as Map<String, Object?>);
            if (restored != null) t.restore(restored);
          } else {
            fail('$name: unknown step $step');
          }
        }
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
