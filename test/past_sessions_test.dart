// PAST SESSIONS (0.14.3): sdk/contract/past-sessions.json, run by every SDK —
// a list page read as the SDK keeps it (`pages`), pages appended in order
// (`append`), a transcript's turns in the SDK's words (`transcripts`) and a
// refusal's error word (`refusals`) — plus the chat close delay's bounds
// (GraineConfig.chatCloseDelaySeconds). A missing contract file FAILS.
// Imports ONLY lib/src/core.
import 'dart:convert';

import 'package:graine_inapp/src/core/core.dart';
import 'package:test/test.dart';

import 'contract_files.dart';

String? _iso(DateTime? t) => t?.toUtc().toIso8601String();

/// An expected time from the contract, as the SDK reads it.
String? _want(Object? v) => v == null ? null : DateTime.parse(v as String).toUtc().toIso8601String();

String _channel(GrainePastSessionChannel c) => c.name;

String? _direction(GrainePastSessionDirection? d) => d?.name;

Map<String, Object?> _wire(GrainePastSession s) => <String, Object?>{
      'id': s.id,
      'startedAt': _iso(s.startedAt),
      'endedAt': _iso(s.endedAt),
      'durationSeconds': s.durationSeconds,
      'channel': _channel(s.channel),
      'direction': _direction(s.direction),
      'status': s.status,
      'turns': s.turns,
      'preview': s.preview,
    };

Map<String, Object?> _expected(Map<String, Object?> e) => <String, Object?>{
      ...e,
      'startedAt': _want(e['startedAt']),
      'endedAt': _want(e['endedAt']),
    };

void main() {
  late Map<String, Object?> contract;
  setUpAll(() async {
    final file = await requireFile('contract/past-sessions.json');
    contract = jsonDecode(await file.readAsString()) as Map<String, Object?>;
  });

  List<Map<String, Object?>> section(String name) => (contract[name]! as List<Object?>).cast<Map<String, Object?>>();

  group('past-sessions.json', () {
    test('every section has cases', () {
      for (final name in <String>['pages', 'append', 'transcripts', 'refusals']) {
        expect(section(name), isNotEmpty, reason: name);
      }
    });

    test('pages: a list answer → the sessions the SDK keeps, and the next cursor', () {
      for (final c in section('pages')) {
        final page = PastSessionsWire.page(c['response']);
        expect(page.sessions.map(_wire).toList(),
            (c['sessions']! as List<Object?>).cast<Map<String, Object?>>().map(_expected).toList(),
            reason: c['name']! as String);
        expect(page.next, c['next'], reason: c['name']! as String);
      }
    });

    test('append: refresh replaces, load more appends without an id twice — and hasMore follows next', () {
      for (final c in section('append')) {
        var state = GrainePastSessions.empty;
        final steps = (c['steps']! as List<Object?>).cast<Map<String, Object?>>();
        final states = (c['states']! as List<Object?>).cast<Map<String, Object?>>();
        for (var i = 0; i < steps.length; i++) {
          final more = steps[i].containsKey('more');
          state = PastSessionsWire.after(state, PastSessionsWire.page(steps[i][more ? 'more' : 'refresh']), more: more);
          expect(state.sessions.map((GrainePastSession s) => s.id).toList(), states[i]['ids'], reason: '${c['name']} #$i');
          expect(state.hasMore, states[i]['hasMore'], reason: '${c['name']} #$i');
          expect(state.loading, isFalse);
          expect(state.error, isNull);
        }
      }
    });

    test("transcripts: a session's turns, oldest first, customer and agent — the unreadable skipped", () {
      for (final c in section('transcripts')) {
        final t = PastSessionsWire.transcript(c['response'], id: 'asked');
        expect(
          <Map<String, Object?>>[
            for (final turn in t.turns) <String, Object?>{'role': turn.role.name, 'text': turn.text, 'at': _iso(turn.at)},
          ],
          <Map<String, Object?>>[
            for (final e in (c['turns']! as List<Object?>).cast<Map<String, Object?>>())
              <String, Object?>{...e, 'at': _want(e['at'])},
          ],
          reason: c['name']! as String,
        );
        final r = c['response']! as Map<String, Object?>;
        expect(t.id, r['id']);
        expect(_iso(t.startedAt), _want(r['startedAt']));
        expect(_iso(t.endedAt), _want(r['endedAt']));
        expect(t.durationSeconds, r['durationSeconds']);
        expect(_channel(t.channel), r['channel']);
        expect(_direction(t.direction), r['direction']);
        expect(t.status, r['status']);
      }
    });

    test("refusals: status and body → the state's error word", () {
      for (final c in section('refusals')) {
        final body = (c['body']! as Map<String, Object?>);
        final refusal = EmbedRefusal.of(c['status']! as int, body);
        expect(refusal, isNotNull, reason: c['name']! as String);
        expect(PastSessionsWire.errorWord(refusal!), c['error'], reason: c['name']! as String);
      }
    });
  });

  group('reading leniently', () {
    test('a transcript that names no id is the one asked for; one that is not an object is empty', () {
      expect(PastSessionsWire.transcript(<String, Object?>{'turns': <Object?>[]}, id: 'ex-1').id, 'ex-1');
      final none = PastSessionsWire.transcript('nonsense', id: 'ex-2');
      expect(none.id, 'ex-2');
      expect(none.turns, isEmpty);
      expect(none.startedAt, isNull);
      expect(none.channel, GrainePastSessionChannel.chat);
      expect(none.status, '');
    });

    test('a page that is not an object, or with no list, is empty; an empty cursor is the end', () {
      expect(PastSessionsWire.page(null).sessions, isEmpty);
      expect(PastSessionsWire.page(<String, Object?>{'sessions': 'x', 'next': ''}).next, isNull);
      expect(PastSessionsWire.page(<String, Object?>{'sessions': <Object?>[], 'next': 7}).next, isNull);
    });

    test('turns: a whole number, even written 3.0; a fraction, a negative or text is 0', () {
      Map<String, Object?> s(Object? turns) => <String, Object?>{'id': 'a', 'startedAt': '2026-10-21T10:00:00Z', 'turns': turns};
      expect(PastSessionsWire.session(s(3))!.turns, 3);
      expect(PastSessionsWire.session(s(3.0))!.turns, 3);
      expect(PastSessionsWire.session(s(2.5))!.turns, 0);
      expect(PastSessionsWire.session(s(-1))!.turns, 0);
      expect(PastSessionsWire.session(s('4'))!.turns, 0);
    });

    test('an id twice in one page is kept once, the first', () {
      final page = PastSessionsWire.page(<String, Object?>{
        'sessions': <Object?>[
          <String, Object?>{'id': 'a', 'startedAt': '2026-10-21T10:00:00Z', 'preview': 'first'},
          <String, Object?>{'id': 'a', 'startedAt': '2026-10-20T10:00:00Z', 'preview': 'second'},
        ],
      });
      expect(page.sessions.map((GrainePastSession s) => s.preview), <String>['first']);
    });

    test('values: equal when every field is', () {
      final a = PastSessionsWire.session(<String, Object?>{'id': 'a', 'startedAt': '2026-10-21T10:00:00Z', 'turns': 2})!;
      final b = PastSessionsWire.session(<String, Object?>{'id': 'a', 'startedAt': '2026-10-21T10:00:00+00:00', 'turns': 2})!;
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(GrainePastSessions(sessions: <GrainePastSession>[a]), GrainePastSessions(sessions: <GrainePastSession>[b]));
      expect(GrainePastSessions.empty, const GrainePastSessions());
      expect(const GrainePastSessions(loading: true), isNot(GrainePastSessions.empty));
      expect(a.toString(), contains('a'));
    });
  });

  group('chatCloseDelaySeconds', () {
    test('15 seconds by default', () {
      expect(const GraineConfig(baseUrl: 'https://www.graine.ai', publishableKey: 'pk').chatCloseDelaySeconds, 15);
      expect(ChatCloseDelay.ms(const GraineConfig(baseUrl: 'https://www.graine.ai', publishableKey: 'pk').chatCloseDelaySeconds), 15000);
    });

    test('0 closes at once; a value of your own is kept, fractions too', () {
      expect(ChatCloseDelay.ms(0), 0);
      expect(ChatCloseDelay.ms(42), 42000);
      expect(ChatCloseDelay.ms(2.5), 2500);
    });

    test('held to 0–300 seconds; null or not a number is the default', () {
      expect(ChatCloseDelay.ms(-5), 0);
      expect(ChatCloseDelay.ms(1000), 300000);
      expect(ChatCloseDelay.ms(300), 300000);
      expect(ChatCloseDelay.ms(double.nan), 15000);
      expect(ChatCloseDelay.ms(double.infinity), 15000);
      expect(ChatCloseDelay.ms(null), 15000);
    });
  });
}
