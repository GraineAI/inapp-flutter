// ONE AGENT'S SERVER TOKENS (CLIENT-TOKENS.md §2.3), with the clock, the
// jitter and the timers in the test's hands: asked at start; one question at a
// time, however many wait (two connections at once, a connection during a
// background refresh); backoff after a failure, a throw and silence (the 15 s
// timeout); nothing asked in the background, a foreground return inside the
// lead asks; a ring asks; a refusal asks once — at most once in 5 s — and the
// request goes once more only with a different token, while token_scope,
// key_revoked and the bot check are final. Imports ONLY lib/src/core.
import 'dart:async';

import 'package:graine_inapp/src/core/core.dart';
import 'package:test/test.dart';

import 'client_tokens_support.dart';

/// The device's wall clock at the start of each test, in ms: 2026-10-26.
const int base = 1793000000000;

/// A provider whose answer the test decides, counting its questions; [manual]
/// keeps each question open until the test answers it.
class Provider {
  Provider([this.answer]);

  String? Function()? answer;
  bool manual = false;
  int asked = 0;
  final List<Completer<String?>> pending = <Completer<String?>>[];

  Future<String?> call() {
    asked++;
    if (manual) {
      final c = Completer<String?>();
      pending.add(c);
      return c.future;
    }
    return Future<String?>.value(answer?.call());
  }
}

typedef Reply = ({int status, Map<String, Object?> body});

Reply refused(String code, [int status = 401]) =>
    (status: status, body: <String, Object?>{'error': 'Refused.', 'code': code});

const Reply ok = (status: 200, body: <String, Object?>{'ok': true});

void main() {
  late ManualTimers timers;
  setUp(() => timers = ManualTimers());

  int nowSec() => (base + timers.now) ~/ 1000;

  /// A token minted now for [life] seconds.
  String fresh({int life = 3600, String id = 'ct_1'}) => mintToken(nowSec(), nowSec() + life, id: id);

  ClientTokens tokens(Future<String?> Function()? p, {double random = 0.5, int? providerTimeoutMs}) => ClientTokens(p,
      clock: () => base + timers.now,
      random: () => random,
      schedule: timers.schedule,
      providerTimeoutMs: providerTimeoutMs ?? ClientTokenRules.providerTimeoutMs);

  /// One request through the wire, as every Dart request goes: the bodies sent, and the reply that came back.
  Future<({List<Map<String, Object?>> sent, Reply reply})> post(ClientTokens? t, Reply Function(int n) answer,
      {bool newConnection = false}) async {
    final sent = <Map<String, Object?>>[];
    final reply = await ClientTokenWire.post<Reply>(t, <String, Object?>{'publishableKey': 'pk'},
        newConnection: newConnection,
        send: (Map<String, Object?> body) async {
          sent.add(Map<String, Object?>.of(body));
          return answer(sent.length);
        },
        refreshable: (Reply r) => ClientTokenRules.isRefreshable(r.status, r.body));
    return (sent: sent, reply: reply);
  }

  group('asking', () {
    test('start asks at once, and again at the lead before the token expires', () async {
      final t1 = fresh(id: 'ct_1');
      final p = Provider(() => t1);
      final t = tokens(p.call, random: 0);
      expect(p.asked, 0, reason: 'nothing asked before start');
      t.start();
      await settle();
      expect(p.asked, 1);
      expect(t.newest, t1);
      expect(t.inPlay, isTrue);
      // An hour's token: asked again 600 s (the lead) before it lapses.
      await timers.advance(3000000 - 1);
      expect(p.asked, 1);
      p.answer = () => fresh(id: 'ct_2');
      await timers.advance(1);
      expect(p.asked, 2);
      expect(t.newest, isNot(t1));
      t.dispose();
    });

    test('a provider that throws backs off, then succeeds — and a token resets the backoff', () async {
      var calls = 0;
      final good = fresh();
      final t = tokens(() async {
        calls++;
        if (calls <= 2) throw StateError("the app's server is down");
        return good;
      });
      t.start();
      await settle();
      expect(calls, 1);
      expect(t.newest, isNull);
      await timers.advance(1999);
      expect(calls, 1, reason: '2 s after the first failure, not before');
      await timers.advance(1);
      expect(calls, 2);
      await timers.advance(3999);
      expect(calls, 2, reason: 'then 4 s');
      await timers.advance(1);
      expect(calls, 3);
      expect(t.newest, good);
      // A token resets the backoff: the next question is the token's own refresh, not 8 s on.
      await timers.advance(8000);
      expect(calls, 3);
      // A provider that throws before it even returns a future is a failure too.
      final sync = tokens(() => throw StateError('no session'));
      sync.start();
      await settle();
      expect(sync.newest, isNull);
      await timers.advance(2000);
      t.dispose();
      sync.dispose();
    });

    test('null and silence are failures; the backoff is jittered and capped', () async {
      final p = Provider(() => null);
      final t = tokens(p.call, random: 1);
      t.start();
      await settle();
      final waits = <int>[];
      for (var i = 0; i < 8; i++) {
        final before = p.asked;
        final from = timers.now;
        while (p.asked == before) {
          await timers.advance(100);
        }
        waits.add(timers.now - from);
      }
      // 2, 4, 8, 16, 32, 60, 60, 60 s — each 20 % later at the jitter's top.
      expect(waits, <int>[2400, 4800, 9600, 19200, 38400, 72000, 72000, 72000]);
      t.dispose();
    });

    test('a provider that never answers has answered null after 15 s; its late answer is ignored', () async {
      final silent = Provider()..manual = true;
      final s = tokens(silent.call);
      s.start();
      await settle();
      expect(silent.asked, 1);
      await timers.advance(ClientTokenRules.providerTimeoutMs - 1);
      expect(silent.asked, 1);
      await timers.advance(1);
      await timers.advance(2000);
      expect(silent.asked, 2, reason: 'timed out, then asked again 2 s on');
      silent.pending.first.complete(fresh(id: 'ct_late'));
      await settle();
      expect(s.newest, isNull);
      s.dispose();
    });

    test('two connections at once ask the provider once — a refresh racing a new connection', () async {
      final p = Provider()..manual = true;
      final t = tokens(p.call);
      final first = t.forConnection();
      final second = t.forConnection();
      await settle();
      expect(p.asked, 1, reason: 'one question, however many connections wait');
      final token = fresh();
      p.pending.single.complete(token);
      expect(await first, token);
      expect(await second, token);
      expect(p.asked, 1);
      t.dispose();
    });

    test('a connection during a background refresh waits for it and never asks again', () async {
      final short = fresh(life: 60, id: 'ct_short');
      final p = Provider(() => short);
      // A slow provider: still answering once the token has 15 s or less left.
      final t = tokens(p.call, random: 0, providerTimeoutMs: 60000);
      t.start();
      await settle();
      // The background refresh is under way (the provider has not answered yet)…
      p.manual = true;
      await timers.advance(30000);
      expect(p.asked, 2);
      // …and the token has 15 s or less left: a connection waits for that refresh, never asks one of its own.
      await timers.advance(16000);
      String? got;
      unawaited(t.forConnection().then((String? v) => got = v));
      await settle();
      expect(p.asked, 2);
      expect(got, isNull);
      final next = fresh(id: 'ct_next');
      p.pending.single.complete(next);
      await settle();
      expect(got, next);
      expect(p.asked, 2);
      t.dispose();
    });

    test('a usable token is used at once; otherwise a connection waits at most 10 s, then goes with the newest',
        () async {
      final p = Provider(() => fresh());
      final t = tokens(p.call);
      t.start();
      await settle();
      final held = t.newest;
      expect(await t.forConnection(), held, reason: 'plenty left: no question');
      expect(p.asked, 1);
      // A provider that does not answer: the connection goes with the newest token after its wait.
      p.manual = true;
      await timers.advance(3600000);
      String? got = 'unset';
      var done = false;
      unawaited(t.forConnection().then((String? v) {
        got = v;
        done = true;
      }));
      await timers.advance(ClientTokenRules.connectionWaitMs - 1);
      expect(done, isFalse);
      await timers.advance(1);
      expect(done, isTrue);
      expect(got, held, reason: 'expired, but the newest there is: Graine judges it');
      t.dispose();
    });

    test('a token without a readable iat and exp is usable, and never refreshed in the background', () async {
      final p = Provider(() => 'opaque-token');
      final t = tokens(p.call);
      t.start();
      await settle();
      expect(t.localExpiry, isNull);
      expect(await t.forConnection(), 'opaque-token');
      await timers.advance(24 * 3600 * 1000);
      expect(p.asked, 1);
      expect(timers.pending, 0);
      t.dispose();
    });
  });

  group('the app away, and a ring', () {
    test('nothing is asked in the background, and a foreground return inside the lead asks', () async {
      final p = Provider(() => null);
      final t = tokens(p.call);
      t.start();
      await settle();
      expect(p.asked, 1);
      t.setForeground(false);
      await timers.advance(300000);
      expect(p.asked, 1, reason: 'no retries while the app is in the background');
      p.answer = () => fresh();
      t.setForeground(true);
      await settle();
      expect(p.asked, 2, reason: 'back in front after a failure: asked at once');
      // An hour's token, its refresh due at 3000 s: the app away past it, then back.
      t.setForeground(false);
      await timers.advance(3100000);
      expect(p.asked, 2);
      t.setForeground(true);
      await settle();
      expect(p.asked, 3, reason: 'inside the lead: asked');
      // Back in front well before the lead: nothing now, the refresh at its moment.
      t.setForeground(false);
      await timers.advance(60000);
      t.setForeground(true);
      await settle();
      expect(p.asked, 3);
      await timers.advance(3000000 - 60000);
      expect(p.asked, 4);
      t.dispose();
    });

    test('a ring asks for a fresh token — unless one just arrived or a question is under way', () async {
      final p = Provider(() => fresh());
      final t = tokens(p.call);
      t.start();
      await settle();
      t.ring();
      await settle();
      expect(p.asked, 1, reason: 'one arrived just now: enough');
      await timers.advance(31000);
      t.setForeground(false);
      t.ring();
      await settle();
      expect(p.asked, 2, reason: 'asked, even with the app in the background');
      p.manual = true;
      await timers.advance(31000);
      t.ring();
      t.ring();
      await settle();
      expect(p.asked, 3, reason: 'one question under way: the second ring joins it');
      tokens(null).ring();
      t.dispose();
    });
  });

  group('a refusal', () {
    test('token_expired asks once more, and the request goes once more with the new token', () async {
      final first = fresh(id: 'ct_first');
      final second = fresh(id: 'ct_second');
      final p = Provider(() => first);
      final t = tokens(p.call);
      t.start();
      await settle();
      p.answer = () => second;
      final r = await post(t, (int n) => n == 1 ? refused('token_expired') : ok);
      expect(r.reply.status, 200);
      expect(p.asked, 2, reason: 'exactly one more question');
      expect(r.sent, hasLength(2), reason: 'exactly one retry');
      expect(r.sent[0][ClientTokenRules.field], first);
      expect(r.sent[1][ClientTokenRules.field], second);
      t.dispose();
    });

    test('token_scope, key_revoked and the bot check are final, and never retried', () async {
      final p = Provider(() => fresh());
      final t = tokens(p.call);
      t.start();
      await settle();
      for (final (String code, int status) in <(String, int)>[('token_scope', 403), ('key_revoked', 401), ('bot_check_failed', 403)]) {
        final r = await post(t, (int _) => refused(code, status), newConnection: true);
        expect(r.sent, hasLength(1), reason: code);
        expect(ClientTokenRules.codeOf(r.reply.body), code);
        expect(p.asked, 1, reason: '$code: the provider is not asked');
      }
      t.dispose();
    });

    test('a refusal asks at most once in 5 s, and never retries with the same token', () async {
      final p = Provider(() => fresh(id: 'ct_a'));
      final t = tokens(p.call);
      t.start();
      await settle();
      // The app's server hands out the same token again: the refusal stands, with no second request.
      final same = t.newest;
      p.answer = () => same;
      var r = await post(t, (int _) => refused('token_invalid'));
      expect(p.asked, 2);
      expect(r.sent, hasLength(1));
      // None at all: the refusal stands too.
      await timers.advance(5000);
      p.answer = () => null;
      r = await post(t, (int _) => refused('token_required'));
      expect(p.asked, 3);
      expect(r.sent, hasLength(1));
      // A second refusal a second later asks nobody: the refusal stands.
      await timers.advance(1000);
      r = await post(t, (int _) => refused('token_required'));
      expect(p.asked, 3);
      expect(r.sent, hasLength(1));
      // That failure backs off as any other: asked again 2 s after it, in the background.
      p.answer = () => fresh(id: 'ct_b');
      await timers.advance(1000);
      expect(p.asked, 4);
      final older = t.newest;
      expect(jtiOf(older!), 'ct_b');
      // 5 s after the last refusal that asked, one may ask again — and goes once more with what it brought.
      p.answer = () => fresh(id: 'ct_c');
      await timers.advance(3000);
      r = await post(t, (int n) => n == 1 ? refused('token_expired') : ok);
      expect(p.asked, 5);
      expect(<Object?>[for (final b in r.sent) b[ClientTokenRules.field]], <Object?>[older, t.newest]);
      // A refusal for a token older than the newest — a refresh arrived while it was on its way — goes once more
      // with the newest, asking nobody.
      final newest = t.newest;
      await timers.advance(1000);
      expect(await t.afterRefusal(older), newest);
      expect(p.asked, 5);
      // One refused with the newest itself, within the 5 s: the refusal stands.
      expect(await t.afterRefusal(newest), isNull);
      expect(p.asked, 5);
      t.dispose();
    });

    test('someone else refused (the page, the call engine) joins the question under way, at most one anew in 5 s',
        () async {
      final p = Provider(() => fresh(id: 'ct_1'));
      final t = tokens(p.call);
      t.start();
      await settle();
      await timers.advance(10000);
      p.answer = () => fresh(id: 'ct_2');
      final next = await t.refresh();
      expect(p.asked, 2);
      expect(jtiOf(next!), 'ct_2');
      expect(await t.refresh(), next, reason: 'within 5 s: the newest, asking nobody');
      expect(p.asked, 2);
      expect(await tokens(null).refresh(), isNull, reason: 'no provider: answered at once, with none');
      t.dispose();
    });

    test('without a provider no request carries a token, and nothing is retried', () async {
      final t = tokens(null);
      t.start();
      expect(t.inPlay, isFalse);
      expect(await t.forConnection(), isNull);
      final r = await post(t, (int _) => refused('token_required'), newConnection: true);
      expect(r.reply.status, 401);
      expect(r.sent, hasLength(1));
      expect(r.sent.single.containsKey(ClientTokenRules.field), isFalse);
      // And with no manager at all, the body goes as it is.
      final none = await post(null, (int _) => ok);
      expect(none.sent.single, <String, Object?>{'publishableKey': 'pk'});
    });
  });

  test('every new token is announced; dispose stops every timer and answers whoever waits', () async {
    final p = Provider(() => fresh(id: 'ct_1'));
    final t = tokens(p.call);
    final heard = <String?>[];
    final stop = t.onChange(heard.add);
    t.start();
    await settle();
    expect(heard, <String?>[t.newest]);
    // The same token again is no change; a new one is.
    final same = t.newest;
    p.answer = () => same;
    expect(await t.refresh(), same);
    expect(p.asked, 2);
    expect(heard, hasLength(1));
    p.answer = () => fresh(id: 'ct_2');
    await timers.advance(5000);
    await t.refresh();
    expect(p.asked, 3);
    expect(heard, hasLength(2));
    stop();
    // A question under way when the agent goes: whoever waits hears the newest at once, and nothing is left to fire.
    p.manual = true;
    await timers.advance(5000);
    final waiting = t.refresh();
    await settle();
    expect(p.asked, 4);
    final newest = t.newest;
    t.dispose();
    expect(await waiting, newest);
    expect(timers.pending, 0, reason: 'nothing left to fire');
    t.start();
    t.ring();
    expect(p.asked, 4, reason: 'nothing asked after dispose');
  });
}
