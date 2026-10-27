// SERVER TOKENS, KEYS AND THE BOT CHECK — the contract's vectors
// (sdk/contract/CLIENT-TOKENS.md, client-tokens.json), every case of each:
// the six codes as this SDK's error type with their retry rule and reasons,
// what a token says about its own life (`sdk.decode`), when each is refreshed
// (`sdk.schedule`, by the rule and by the token manager itself), when a
// connection may use one (`sdk.usable`), the backoff (`sdk.backoffSeconds`),
// and the words and numbers every SDK shares. A missing contract file FAILS.
// Imports ONLY lib/src/core.
import 'dart:convert';

import 'package:graine_inapp/src/core/core.dart';
import 'package:test/test.dart';

import 'client_tokens_support.dart';
import 'contract_files.dart';

void main() {
  late Map<String, Object?> contract;
  late Map<String, Object?> sdk;

  setUpAll(() async {
    contract = await contractJson('contract/client-tokens.json');
    sdk = contract['sdk']! as Map<String, Object?>;
  });

  List<Map<String, Object?>> cases(Map<String, Object?> o, String name) {
    final list = (o[name]! as List<Object?>).cast<Map<String, Object?>>();
    expect(list, isNotEmpty, reason: 'section $name is empty');
    return list;
  }

  String token(String name) => ((contract['token']! as Map<String, Object?>)['tokens']! as Map<String, Object?>)[name]! as String;

  double? seconds(Object? v) => v is num ? v.toDouble() : null;

  group('the codes', () {
    test("every code is this SDK's, with its wire word and its retry rule", () {
      final codes = cases(contract, 'errorCodes');
      for (final c in codes) {
        final wire = c['wire']! as String;
        final code = GraineErrorCode.fromWire(wire);
        expect(code.wire, wire);
        expect(code.name, c['dart'], reason: 'the Dart name of $wire');
        expect(GraineErrorCode.fromWire('  ${wire.toUpperCase()} '), code, reason: 'case and spaces never matter');
        switch (c['retry']) {
          case 'refresh_then_retry_once':
            // A fresh token can lift it: asked for again, and the request goes once more.
            expect(ClientTokenRules.refreshable, contains(wire));
          case 'never':
            // Final for the request: surfaced, never looped.
            expect(ClientTokenRules.refreshable, isNot(contains(wire)));
          case 'website_challenge_then_retry_once':
            // The website's alone: an app never answers a challenge, so never retries it.
            expect(ClientTokenRules.refreshable, isNot(contains(wire)));
          default:
            fail('a retry rule this SDK does not know: ${c['retry']}');
        }
      }
      expect(ClientTokenRules.refusals, <String>{for (final c in codes) c['wire']! as String},
          reason: 'every refusal of the contract, and only those, is final for a conversation');
    });

    test('a refusal is read with its status, its sentence and its reason', () {
      final reasons = contract['reasons']! as Map<String, Object?>;
      for (final c in cases(contract, 'errorCodes')) {
        final wire = c['wire']! as String;
        final status = c['status']! as int;
        final said = <String?>[for (final r in (reasons[wire] as List<Object?>?) ?? const <Object?>[]) r! as String];
        for (final reason in said.isEmpty ? <String?>[null] : said) {
          final body = <String, Object?>{'error': 'Refused.', 'code': wire, if (reason != null) 'reason': reason};
          final r = EmbedRefusal.of(status, body)!;
          expect(r.code.wire, wire);
          expect(r.codeName, wire);
          expect(r.message, 'Refused.', reason: "Graine's sentence, never the key or domains one");
          expect(r.reason, reason);
          expect(r.statusCode, status);
          // The session's reading: Graine's sentence too.
          expect(SessionConfig.errorFor(status, body), 'Refused.');
          // Graine without a sentence: the SDK's own — never the allowed-domains or the key one.
          final bare = EmbedRefusal.of(status, <String, Object?>{'code': wire})!;
          expect(bare.message, ClientTokenRules.sentence(wire));
          expect(bare.message, isNot(contains('app://')));
          expect(SessionConfig.errorFor(status, <String, Object?>{'code': wire}), ClientTokenRules.sentence(wire));
        }
      }
      // Any other refusal reads as it always did.
      expect(EmbedRefusal.of(403, const <String, Object?>{})!.message, contains('app://'));
      expect(SessionConfig.errorFor(401, const <String, Object?>{}), contains('Publishable key was rejected'));
      expect(EmbedRefusal.of(200, const <String, Object?>{'code': 'token_scope'}), isNull);
      expect(EmbedRefusal.of(429, const <String, Object?>{'code': 'rate_limited'})!.reason, isNull);
    });
  });

  group('what a token says about its own life', () {
    test('every token decodes as the vectors say', () {
      for (final c in cases(sdk, 'decode')) {
        final name = c['token']! as String;
        final claims = ClientTokenRules.decode(token(name));
        expect(claims.iat, seconds(c['iat']), reason: '$name iat');
        expect(claims.exp, seconds(c['exp']), reason: '$name exp');
      }
      for (final t in <String?>[null, '', 'a..c', 'a.!!!.c', 'h.${base64Url.encode(utf8.encode('[1,2]'))}.s']) {
        expect(ClientTokenRules.decode(t), (iat: null, exp: null), reason: '$t');
      }
      expect(ClientTokenRules.localExpiry(ClientTokenRules.decode('not-a-token'), 1000), isNull,
          reason: 'no readable expiry: nothing in the background');
    });

    test('every schedule is the vectors own', () {
      for (final c in cases(sdk, 'schedule')) {
        final name = c['name']! as String;
        final claims = (iat: seconds(c['iat']), exp: seconds(c['exp']));
        final receivedAt = (c['receivedAt']! as int) * 1000;
        final life = ClientTokenRules.lifetimeMs(claims)!;
        final localExp = ClientTokenRules.localExpiry(claims, receivedAt)!;
        expect(localExp, (c['localExp']! as int) * 1000, reason: '$name localExp');
        expect(ClientTokenRules.leadMs(life), (c['lead']! as int) * 1000, reason: '$name lead');
        expect(localExp - ClientTokenRules.leadMs(life), (c['refreshAt']! as int) * 1000, reason: '$name refreshAt');
        expect(ClientTokenRules.maxJitterMs(life), (c['maxJitter']! as int) * 1000, reason: '$name maxJitter');
      }
    });

    // The same vectors through the token manager itself: a token minted with
    // each case's `iat` and `exp`, arriving at `receivedAt`, is asked for again
    // at `refreshAt` less its jitter (none, then the most) — and never sooner
    // than 30 s after it arrived.
    test('the token manager refreshes at each vector\'s moment', () async {
      for (final c in cases(sdk, 'schedule')) {
        for (final draw in <double>[0, 1]) {
          final name = c['name']! as String;
          final timers = ManualTimers();
          final receivedAt = (c['receivedAt']! as int) * 1000;
          final minted = mintToken(c['iat']! as int, c['exp']! as int);
          var asked = 0;
          final tokens = ClientTokens(() async {
            asked++;
            return minted;
          }, clock: () => receivedAt + timers.now, random: () => draw, schedule: timers.schedule);
          tokens.start();
          await settle();
          expect(asked, 1, reason: name);
          final jitter = (draw * (c['maxJitter']! as int) * 1000).round();
          final refreshAt = (c['refreshAt']! as int) * 1000 - jitter;
          final earliest = receivedAt + ClientTokenRules.backgroundMinIntervalMs;
          final due = (refreshAt > earliest ? refreshAt : earliest) - receivedAt;
          await timers.advance(due - 1);
          expect(asked, 1, reason: '$name (jitter $jitter): not before its moment');
          await timers.advance(1);
          expect(asked, 2, reason: '$name (jitter $jitter): at its moment');
          tokens.dispose();
        }
      }
    });

    test('a connection uses a token as the vectors say', () {
      for (final c in cases(sdk, 'usable')) {
        expect(ClientTokenRules.usable((c['localExp']! as int) * 1000, (c['now']! as int) * 1000), c['usable'],
            reason: '$c');
      }
      expect(ClientTokenRules.usable(null, 0), isTrue, reason: 'no readable expiry: the token is used, and Graine judges it');
    });

    test('the backoff is the vectors own', () {
      final list = (sdk['backoffSeconds']! as List<Object?>).cast<int>();
      expect(list.length, greaterThanOrEqualTo(6));
      for (var i = 0; i < list.length; i++) {
        expect(ClientTokenRules.backoffMs(i + 1), list[i] * 1000, reason: 'failure ${i + 1}');
      }
      expect(ClientTokenRules.backoffJitter, (sdk['backoffJitter']! as num).toDouble());
    });
  });

  test('the words and numbers are the contract\'s', () {
    expect(ClientTokenRules.field, sdk['wireField']);
    final page = sdk['pageMessages']! as Map<String, Object?>;
    expect(ClientTokenRules.pageToken, page['toPage']);
    expect(ClientTokenRules.pageNeedsToken, page['toHost']);
    expect(ClientTokenRules.pageWaitMs, page['pageWaitMs']);
    expect(ClientTokenRules.usableForConnectionMs, (sdk['usableForNewConnectionSeconds']! as int) * 1000);
    expect(ClientTokenRules.connectionWaitMs, (sdk['newConnectionWaitSeconds']! as int) * 1000);
    expect(ClientTokenRules.forcedMinIntervalMs, (sdk['forcedRefreshMinIntervalSeconds']! as int) * 1000);
    expect(ClientTokenRules.backgroundMinIntervalMs, (sdk['minSecondsBetweenBackgroundRefreshes']! as int) * 1000);
    expect(GraineVersion.name, contract['sdkVersion']);
    // The calls host's method and event, as CLIENT-TOKENS.md §2.4 names them.
    expect(ClientTokenRules.hostSetToken, 'setClientToken');
    expect(ClientTokenRules.hostNeedsToken, 'needClientToken');
  });
}
