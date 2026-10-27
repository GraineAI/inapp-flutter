// The in-app platform's device rules, proven without a device: who the user
// is (contract §1), the calls they book (§3.3, §4), the text chat's wire and
// how its frames become one message per turn, the screen's actions, and the
// chat and call design tokens (§7). The identity rules are held against the
// contract's own vectors (sdk/contract/identity-vectors.json) and the ticket
// and context-token rules against the native engines' (native-calls.json).
// Imports ONLY lib/src/core — no package:flutter.
import 'dart:convert';
import 'dart:math' as math;

import 'package:graine_inapp/src/core/core.dart';
import 'package:test/test.dart';

import 'contract_files.dart';

Object? canon(Object? v) {
  if (v is num) return v.toDouble();
  if (v is Map) return <String, Object?>{for (final e in v.entries) e.key.toString(): canon(e.value)};
  if (v is List) return <Object?>[for (final x in v) canon(x)];
  return v;
}

final DateTime t0 = DateTime.utc(2026, 10, 13, 9, 30);

void main() {
  group('Identity (§1.2)', () {
    test('a placeholder, null, a boolean, a fraction or an object identifies nobody', () {
      for (final v in <Object?>[
        null, true, false, 4.5, 4242.0, <String, Object?>{'a': 1}, <Object?>['x'], '', '  ', 'null', 'NULL', ' Undefined ',
        'none', 'nil', 'NaN', 'unknown', 'anonymous', 'anon', 'Guest', '0', '-', 'n/a', 'NA', 'test', '[PHONE]', '[email]',
        '[PAN]', '[aadhaar]', '[CARD]', 'x' * 257,
      ]) {
        expect(Identity.valueOf(v), isNull, reason: '$v');
      }
    });

    test('a real value is sent raw — an integer as its decimal string', () {
      expect(Identity.valueOf('  P-1234  '), '  P-1234  ', reason: 'the servers trim; the device never rewrites');
      expect(Identity.valueOf('Asha.Rao@Example.com'), 'Asha.Rao@Example.com');
      expect(Identity.valueOf(4242), '4242');
      expect(Identity.valueOf('x' * 256), 'x' * 256);
    });

    test("the setting's field picks the trait — exactly, else by its normalised name", () {
      final traits = <String, Object?>{'name': 'Asha', 'email': 'asha@example.com', 'Patient_ID': 'MRN-000981'};
      expect(Identity.pick(traits, 'email'), 'asha@example.com');
      expect(Identity.pick(traits, 'patient_id'), 'MRN-000981');
      expect(Identity.pick(traits, 'user_id'), isNull);
      expect(Identity.pick(null, 'user_id'), isNull);
      expect(Identity.pick(<String, Object?>{'user_id': 'guest'}, 'user_id'), isNull);
    });

    test('a field is trimmed, lower case and a name; anything else is none', () {
      expect(Identity.normaliseField(' Patient_ID '), 'patient_id');
      expect(Identity.normaliseField('patient-id'), isNull);
      expect(Identity.normaliseField('1abc'), isNull);
      expect(Identity.normaliseField(42), isNull);
      expect(Identity.normaliseField('a' * 41), isNull);
    });

    test('the install id and the zone are sent only in the shapes the servers take', () {
      expect(Identity.normaliseInstallId('3F2504E0-4F89-11D3-9A0C-0305E82C3301'), '3f2504e0-4f89-11d3-9a0c-0305e82c3301');
      expect(Identity.normaliseInstallId('short'), isNull);
      expect(Identity.normaliseInstallId(null), isNull);
      expect(Identity.normaliseTimezone('Asia/Kolkata'), 'Asia/Kolkata');
      expect(Identity.normaliseTimezone('America/Argentina/Buenos_Aires'), 'America/Argentina/Buenos_Aires');
      expect(Identity.normaliseTimezone('UTC'), 'UTC');
      expect(Identity.normaliseTimezone('IST +05:30'), isNull, reason: 'an abbreviation is not a zone');
      expect(Identity.normaliseTimezone(''), isNull);
    });

    test('a fallback install id is a lower-case UUIDv4 the servers accept', () {
      final id = Identity.uuidV4(math.Random(7));
      expect(id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(Identity.normaliseInstallId(id), id);
      expect(Identity.uuidV4(), isNot(Identity.uuidV4()));
    });

    test("the memory choice is kept under the iOS SDK's fingerprint, never the identifier", () {
      final a = Identity.memoryKey('email', 'Asha.Rao@Example.com ');
      expect(a, hasLength(32));
      expect(a, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(a, Sha256.hex(Sha256.ofText('graine:memory:v1\nemail\nasha.rao@example.com').sublist(0, 16)));
      expect(Identity.memoryKey('email', 'asha.rao@example.com'), a, reason: 'one user, however it is typed');
      expect(Identity.memoryKey('email', 'ravi@example.com'), isNot(a));
      expect(Identity.memoryKey('user_id', 'asha.rao@example.com'), isNot(a), reason: 'per field');
      expect(Identity.memoryKey('phone', '+91 98765 43210'), Identity.memoryKey('phone', '098765-43210'));
    });

    test('the identifying trait never rides as a variable', () {
      final traits = <String, Object?>{'name': 'Asha', 'Email': 'asha@example.com', 'plan': 'Gold'};
      expect(Identity.withoutIdentity(traits, 'email'), <String, Object?>{'name': 'Asha', 'plan': 'Gold'});
      expect(Identity.withoutIdentity(traits, null), traits, reason: 'no session yet: the trait is not known');
      expect(Identity.withoutIdentity(null, 'email'), isNull);
    });

    test('the identity fields of a request, in the contract order, absent ones left out', () {
      expect(
        Identity.requestFields(value: 'P-1', installId: testInstall, memory: false, timezone: 'Asia/Kolkata', callId: 'c1'),
        <String, Object?>{
          'identity': <String, Object?>{'value': 'P-1'},
          'installId': testInstall,
          'memory': false,
          'timezone': 'Asia/Kolkata',
          'callId': 'c1',
        },
      );
      expect(Identity.requestFields(installId: testInstall).keys, <String>['installId'],
          reason: 'anonymous: no identity key at all');
    });

    test('the setting as the session serves it, clamped; an older server says nothing', () {
      expect(IdentitySetting.fromJson(<String, Object?>{'field': 'Email', 'devicesPerUser': 9}),
          const IdentitySetting(field: 'email', devicesPerUser: 5));
      expect(IdentitySetting.fromJson(<String, Object?>{'field': 'not a field!', 'devicesPerUser': 0}),
          const IdentitySetting(field: 'user_id', devicesPerUser: 1));
      expect(IdentitySetting.fromJson(null), isNull);
      expect(IdentitySetting.standard.field, 'user_id');
    });
  });

  group('SHA-256', () {
    test('the FIPS 180-4 examples', () {
      expect(Sha256.hex(Sha256.ofText('')), 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(Sha256.hex(Sha256.ofText('abc')), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(Sha256.hex(Sha256.ofText('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq')),
          '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1');
      expect(Sha256.hex(Sha256.hash(List<int>.filled(1000000, 0x61))),
          'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0');
    });
  });

  group('sdk/contract/identity-vectors.json', () {
    late Map<String, Object?> fx;
    setUpAll(() async => fx = await contractJson('contract/identity-vectors.json'));

    String base32(List<int> bytes) {
      const alphabet = 'abcdefghijklmnopqrstuvwxyz234567';
      final out = StringBuffer();
      var buffer = 0, bits = 0;
      for (final b in bytes) {
        buffer = (buffer << 8) | b;
        bits += 8;
        while (bits >= 5) {
          out.write(alphabet[(buffer >> (bits - 5)) & 31]);
          bits -= 5;
        }
        buffer &= (1 << bits) - 1;
      }
      if (bits > 0) out.write(alphabet[(buffer << (5 - bits)) & 31]);
      return out.toString();
    }

    test('the value normalises exactly as the servers normalise it (composition aside)', () {
      final combining = RegExp('[\u0300-\u036f]');
      var checked = 0;
      for (final c in (fx['user_keys']! as List<Object?>).cast<Map<String, Object?>>()) {
        final field = c['normalised_field'];
        if (field is! String) continue;
        final v = c['value'];
        if (v is String && combining.hasMatch(v)) continue; // NFC: the servers' step
        expect(Identity.normaliseValue(field, v), c['normalised_value'], reason: '$field $v');
        checked++;
      }
      expect(checked, greaterThan(15));
    });

    test("this SHA-256 reproduces the servers' user keys — the hash the memory choice is kept under", () {
      final defaultOrg = fx['org_id']! as String;
      for (final c in (fx['user_keys']! as List<Object?>).cast<Map<String, Object?>>()) {
        final key = c['user_key'];
        if (key is! String) continue;
        final org = (c['org_id'] as String?) ?? defaultOrg;
        final digest = Sha256.ofText('graine:user:v1\n$org\n${c['normalised_field']}\n${c['normalised_value']}');
        expect('u1_${base32(digest).substring(0, 26)}', key, reason: '${c['field']} ${c['value']}');
      }
    });

    test("the device never withholds an identity the servers would key — and withholds every placeholder", () {
      final cases = (fx['user_keys']! as List<Object?>).cast<Map<String, Object?>>();
      expect(cases, isNotEmpty);
      var withheld = 0;
      for (final c in cases) {
        final sent = Identity.valueOf(c['value']);
        if (sent == null) {
          withheld++;
          expect(c['user_key'], isNull, reason: 'the SDK dropped ${c['value']} but the servers key it');
        }
        final v = c['value'];
        final placeholder = v == null || v is bool || (v is String && Identity.placeholders.contains(v.trim().toLowerCase()));
        if (placeholder) expect(sent, isNull, reason: '$v is no identity');
      }
      expect(withheld, greaterThan(0), reason: 'the vectors must exercise the placeholders');
    });

    test('the trait the setting names normalises as the servers normalise the field', () {
      for (final c in (fx['user_keys']! as List<Object?>).cast<Map<String, Object?>>()) {
        expect(Identity.normaliseField(c['field']), c['normalised_field'], reason: '${c['field']}');
      }
    });

    test('an install id is sent exactly when the servers can derive its ref', () {
      for (final c in (fx['install_refs']! as List<Object?>).cast<Map<String, Object?>>()) {
        final ours = Identity.normaliseInstallId(c['install_id']);
        expect(ours == null, c['install_ref'] == null, reason: '${c['install_id']}');
      }
    });
  });

  group('the session (§5.1)', () {
    test('identity, memory, hosted calls, scheduling and the socket host', () {
      final s = SessionConfig.fromJson(<String, Object?>{
        'agentId': 'agent-1',
        'wsHost': 'wss://socket.test/',
        'identity': <String, Object?>{'field': 'patient_id', 'devicesPerUser': 3},
        'memory': <String, Object?>{'enabled': true},
        'calls': <String, Object?>{
          'hosted': true,
          'platforms': <Object?>['ios', 'Android', 3],
          'ringTimeoutSeconds': 90,
          'callName': ' Asha · Graine Care ',
          'scheduling': <String, Object?>{'usersCanBook': true, 'maxDaysAhead': 7, 'minLeadMinutes': 1, 'maxPendingPerUser': 2},
        },
      });
      expect(s.wsHost, 'wss://socket.test/');
      expect(s.identitySetting, const IdentitySetting(field: 'patient_id', devicesPerUser: 3));
      expect(s.memory!.enabled, isTrue);
      expect(s.calls!.hosted, isTrue);
      expect(s.calls!.platforms, <String>['ios', 'android']);
      expect(s.calls!.ringTimeoutSeconds, 60, reason: 'clamped to 20–60');
      expect(s.calls!.callName, 'Asha · Graine Care');
      final b = s.calls!.scheduling!;
      expect(<Object?>[b.usersCanBook, b.maxDaysAhead, b.minLeadMinutes, b.maxPendingPerUser], <Object?>[true, 7, 2, 2]);
    });

    test('an older server says none of it: user_id, no memory setting, no calls', () {
      final s = SessionConfig.fromJson(const <String, Object?>{'agentId': 'a'});
      expect(s.identity, isNull);
      expect(s.identitySetting.field, 'user_id');
      expect(s.memory, isNull);
      expect(s.calls, isNull);
      expect(s.wsHost, isNull);
    });

    test("a refusal is the wire's code, typed, with a sentence for whoever must act", () {
      final r = EmbedRefusal.of(409, <String, Object?>{'error': 'That time is outside the calling hours.', 'code': 'outside_window'})!;
      expect(r.code, GraineErrorCode.outsideWindow);
      expect(r.codeName, 'outside_window');
      expect(r.message, 'That time is outside the calling hours.');
      expect(r.statusCode, 409);
      expect(EmbedRefusal.of(401, const <String, Object?>{})!.code, GraineErrorCode.invalidKey);
      expect(EmbedRefusal.of(403, const <String, Object?>{})!.message, contains('app://'));
      final limited = EmbedRefusal.of(429, const <String, Object?>{'error': 'Slow down.', 'code': 'rate_limited'}, retryAfter: '30')!;
      expect(limited.code, GraineErrorCode.rateLimited);
      expect(limited.retryAfterSeconds, 30);
      expect(EmbedRefusal.of(429, const <String, Object?>{}, retryAfter: 'soon')!.retryAfterSeconds, isNull);
      expect(EmbedRefusal.of(400, const <String, Object?>{})!.code, GraineErrorCode.invalidRequest);
      expect(EmbedRefusal.of(503, const <String, Object?>{})!.code, GraineErrorCode.unavailable);
      expect(EmbedRefusal.of(500, const <String, Object?>{})!.code, GraineErrorCode.unknown);
      final newer = EmbedRefusal.of(409, const <String, Object?>{'error': 'Nope.', 'code': 'quiet_hours'})!;
      expect(newer.code, GraineErrorCode.unknown, reason: 'a code this build does not know');
      expect(newer.codeName, 'quiet_hours', reason: 'kept as Graine said it');
      expect(EmbedRefusal.of(204, const <String, Object?>{}), isNull);
    });

    // 0.14.4 — the docs' table: a gateway in front of Graine that failed or timed out is an outage.
    test('502 and 504 with no code are unavailable, like 503; 500 stays unknown; a code said is the code', () {
      for (final status in <int>[502, 503, 504]) {
        final r = EmbedRefusal.of(status, const <String, Object?>{})!;
        expect(r.code, GraineErrorCode.unavailable, reason: '$status');
        expect(r.codeName, isNull, reason: 'Graine said none');
        expect(r.statusCode, status);
      }
      expect(EmbedRefusal.of(500, const <String, Object?>{})!.code, GraineErrorCode.unknown);
      expect(EmbedRefusal.of(504, const <String, Object?>{'error': 'Took too long.'})!.message, 'Took too long.');
      expect(EmbedRefusal.of(502, const <String, Object?>{'error': 'Slow down.', 'code': 'rate_limited'})!.code,
          GraineErrorCode.rateLimited);
    });

    // 0.14.4 review — one rule for a refusal's code on every SDK (inapp-platform-contract.md, "A refusal's code"),
    // held to the vectors every SDK's suite runs.
    test("a refusal's code: every vector in contract/http-status.json", () async {
      final vectors = ((await contractJson('contract/http-status.json'))['vectors']! as List<Object?>).cast<Map<String, Object?>>();
      expect(vectors, isNotEmpty);
      for (final v in vectors) {
        final status = (v['status']! as num).toInt();
        // The body as the SDK reads an answer's bytes: JSON, and an object or nothing.
        final body = Js.asMap(jsonDecode(jsonEncode(v['body']))) ?? <String, Object?>{};
        final r = EmbedRefusal.of(status, body)!;
        final word = r.code == GraineErrorCode.unknown ? (r.codeName ?? GraineErrorCode.unknown.wire) : r.code.wire;
        expect(word, v['code'], reason: '${v['name']} ($status)');
        expect(r.statusCode, status, reason: '${v['name']}');
        if (v['raw'] != null) {
          expect(r.codeName, isNull, reason: "${v['name']}: Graine said no code — Flutter's unknown carries no word");
        }
      }
    });

    test("a code that is not a string is no code: the status decides, as the contract's rule says", () {
      expect(EmbedRefusal.of(503, const <String, Object?>{'code': 42})!.code, GraineErrorCode.unavailable);
      expect(EmbedRefusal.of(503, const <String, Object?>{'code': 42})!.codeName, isNull);
      expect(EmbedRefusal.of(401, const <String, Object?>{'code': true})!.code, GraineErrorCode.invalidKey);
      expect(EmbedRefusal.of(404, const <String, Object?>{'code': <Object?>['not_found']})!.codeName, isNull);
    });

    test('every code on the wire, and network and unknown', () {
      expect(<String>[for (final c in GraineErrorCode.values) c.wire], <String>[
        'invalid_key', 'origin_refused', 'rate_limited', 'invalid_request', 'identity_required', 'device_limit',
        'scheduling_off', 'too_soon', 'too_far', 'outside_window', 'too_many_pending', 'not_found', 'unavailable',
        // startWorkflow (0.14.4).
        'not_allowed', 'not_verified',
        // 0.14.4 — your app and your users (APP-IDENTITY.md §2.3; app_identity_test.dart reads them from the contract).
        'app_not_allowed', 'app_not_verified', 'identity_unverified',
        // Server tokens, keys and the website bot check (0.14.4, sdk/contract/client-tokens.json).
        'token_required', 'token_invalid', 'token_expired', 'token_scope', 'key_revoked', 'bot_check_failed',
        'network', 'unknown',
      ]);
      expect(GraineErrorCode.fromWire(' TOO_SOON '), GraineErrorCode.tooSoon);
      expect(GraineErrorCode.fromWire(null), GraineErrorCode.unknown);
    });
  });

  group('scheduled calls (§3.3, §4.2)', () {
    test("the wire's ScheduledCall, read leniently; an unknown status passes through", () {
      final c = GraineScheduledCall.fromJson(<String, Object?>{
        'id': 'sc_1',
        'at': '2026-10-14T18:00:00+05:30',
        'status': 'NO_DEVICE',
        'reason': 'KYC follow-up',
        'source': 'sdk',
      })!;
      expect(c.id, 'sc_1');
      expect(c.at, DateTime.utc(2026, 10, 14, 12, 30));
      expect(c.at!.isUtc, isTrue);
      expect(c.status, GraineCallStatus.noDevice);
      expect(c.statusWire, 'NO_DEVICE');
      expect(c.toJson(), <String, Object?>{
        'id': 'sc_1', 'at': '2026-10-14T12:30:00.000Z', 'status': 'NO_DEVICE', 'source': 'sdk', 'reason': 'KYC follow-up',
      });
      expect(c.source, GraineCallSource.app, reason: 'wire "sdk" is this app');
      expect(c.isUpcoming, isFalse);
      expect(c.canCancel, isFalse);
      const booked = GraineScheduledCall(id: 'b');
      expect(booked.isUpcoming, isTrue);
      expect(booked.canCancel, isTrue);
      const ringing = GraineScheduledCall(id: 'r', status: GraineCallStatus.ringing);
      expect(ringing.isUpcoming, isTrue);
      expect(ringing.canCancel, isFalse, reason: 'a ringing call is answered or declined, not cancelled');
      expect(GraineCallSource.fromWire('partner'), GraineCallSource.unknown);
      expect(GraineCallSource.fromWire(null), isNull);
      expect(<String>[for (final v in GraineCallStatus.values) v.wire], <String>[
        'scheduled', 'ringing', 'answered', 'completed', 'declined', 'missed', 'failed', 'cancelled', 'expired',
        'no_device', 'unknown',
      ]);
      final paged = GraineScheduledCall.fromJson(<String, Object?>{'id': 'x', 'at': '2026-10-14T12:00:00Z', 'status': 'paged'})!;
      expect(paged.status, GraineCallStatus.unknown);
      expect(paged.statusWire, 'paged', reason: 'a newer status passes through as the server said it');
      expect(GraineScheduledCall.fromJson(<String, Object?>{'call_id': 'x', 'scheduled_at': '2026-10-14T12:00:00Z'})!.status,
          GraineCallStatus.scheduled, reason: 'a booking just made says no status');
      final unsaid = GraineScheduledCall.fromJson(<String, Object?>{'id': 'x', 'at': null, 'status': 'expired'})!;
      expect(unsaid.at, isNull, reason: 'at may be null on the wire');
      expect(GraineScheduledCall.fromJson(<String, Object?>{'at': '2026-10-14T12:00:00Z'}), isNull, reason: 'no id is no call');
    });

    test('the wire time carries the offset, to the second; a time without a zone reads as UTC', () {
      final at = DateTime.utc(2026, 10, 14, 12, 30, 5, 900);
      expect(ScheduledCalls.atWire(at, offset: const Duration(hours: 5, minutes: 30)), '2026-10-14T18:00:05+05:30');
      expect(ScheduledCalls.atWire(at, offset: const Duration(hours: -4)), '2026-10-14T08:30:05-04:00');
      expect(ScheduledCalls.atWire(at, offset: Duration.zero), '2026-10-14T12:30:05Z');
      final local = DateTime(2026, 10, 14, 18);
      expect(ScheduledCalls.parseTime(ScheduledCalls.atWire(local)), local.toUtc(), reason: "the device's own offset");
      expect(ScheduledCalls.parseTime('2026-10-14T12:00:00'), DateTime.utc(2026, 10, 14, 12));
      expect(ScheduledCalls.parseTime('nonsense'), isNull);
    });

    test("the rules: the session's, or no booking at all from a server that says nothing", () {
      const none = GraineSchedulingRules();
      expect(GraineSchedulingRules.of(null).usersCanBook, isFalse);
      expect(<Object?>[none.minLeadMinutes, none.maxDaysAhead, none.maxPendingPerUser, none.ringTimeoutSeconds],
          <Object?>[5, 14, 3, 45]);
      final rules = GraineSchedulingRules.of(CallsSetting.fromJson(<String, Object?>{
        'hosted': true,
        'platforms': <Object?>['android'],
        'ringTimeoutSeconds': 30,
        'callName': 'Asha · Acme Care',
        'scheduling': <String, Object?>{'usersCanBook': true, 'minLeadMinutes': 15, 'maxDaysAhead': 7, 'maxPendingPerUser': 2},
      }));
      expect(<Object?>[rules.usersCanBook, rules.minLeadMinutes, rules.maxDaysAhead, rules.maxPendingPerUser],
          <Object?>[true, 15, 7, 2]);
      expect(<Object?>[rules.ringTimeoutSeconds, rules.callName, rules.hostedRinging, rules.platforms],
          <Object?>[30, 'Asha · Acme Care', true, <String>['android']]);
      final now = DateTime.utc(2026, 10, 13, 9);
      expect(rules.earliest(now), DateTime.utc(2026, 10, 13, 9, 15));
      expect(rules.latest(now), DateTime.utc(2026, 10, 20, 9));
    });

    test("a cancel answers with the call's status afterwards: cancelled unless the server says", () {
      expect(ScheduledCalls.statusAfterCancel(const <String, Object?>{'ok': true}), GraineCallStatus.cancelled);
      expect(ScheduledCalls.statusAfterCancel(const <String, Object?>{'ok': true, 'status': 'ringing'}), GraineCallStatus.ringing);
      expect(ScheduledCalls.statusAfterCancel(null), GraineCallStatus.cancelled);
    });

    test("a list is the calls in the server's order (upcoming first), whatever it is wrapped in", () {
      final body = <String, Object?>{
        'calls': <Object?>[
          <String, Object?>{'id': 'b', 'at': '2026-10-15T09:00:00Z', 'status': 'scheduled'},
          'junk',
          <String, Object?>{'id': 'a', 'at': '2026-10-14T09:00:00Z', 'status': 'ringing'},
        ],
      };
      expect(ScheduledCalls.listFrom(body).map((GraineScheduledCall c) => c.id), <String>['b', 'a']);
      expect(ScheduledCalls.listFrom(body['calls']).length, 2, reason: 'a bare list');
      expect(ScheduledCalls.listFrom(const <String, Object?>{}), isEmpty);
      expect(ScheduledCalls.oneFrom(<String, Object?>{'call': <String, Object?>{'id': 'a', 'at': '2026-10-14T09:00:00Z'}})!.id, 'a');
      expect(ScheduledCalls.oneFrom(<String, Object?>{'id': 'a', 'at': '2026-10-14T09:00:00Z'})!.id, 'a');
      expect(GraineCallStatus.ringing.upcoming, isTrue);
      expect(GraineCallStatus.missed.upcoming, isFalse);
    });
  });

  group('what the agent remembers', () {
    test("the wire's Memory, read leniently, in the server's order", () {
      final list = GraineMemory.listFrom(<String, Object?>{
        'memories': <Object?>[
          <String, Object?>{'id': 'm2', 'text': 'Prefers calls after 6 pm', 'createdAt': '2026-10-12T10:00:00Z', 'updatedAt': null},
          <String, Object?>{'id': 'm1', 'text': 'Drives a Creta'},
          <String, Object?>{'id': '', 'text': 'no id'},
          <String, Object?>{'id': 'm0', 'text': '  '},
          7,
        ],
      });
      expect(list.map((GraineMemory m) => m.id), <String>['m2', 'm1']);
      expect(list.first.createdAt, DateTime.utc(2026, 10, 12, 10));
      expect(list.first.updatedAt, isNull);
      expect(list.first.toJson(), <String, Object?>{
        'id': 'm2', 'text': 'Prefers calls after 6 pm', 'createdAt': '2026-10-12T10:00:00.000Z', 'updatedAt': null,
      });
      expect(GraineMemory.listFrom(<Object?>[<String, Object?>{'id': 'a', 'text': 'b'}]), hasLength(1), reason: 'a bare list');
      expect(GraineMemory.listFrom(null), isEmpty);
    });
  });

  group('the chat wire', () {
    test('a marker is not a word: removed in any case, the turn boundary kept', () {
      expect(AgentChunk.read('<beginning_of_stream>'), const AgentChunk('', startsTurn: true));
      expect(AgentChunk.read('Hello! How can I help?<END_OF_STREAM>'),
          const AgentChunk('Hello! How can I help?', endsTurn: true));
      expect(AgentChunk.read(' help you '), const AgentChunk(' help you '), reason: 'spaces are load-bearing');
      expect(AgentChunk.read('a < b'), const AgentChunk('a < b'));
      expect(AgentChunk.read(null), const AgentChunk(''));
      expect(AgentChunk.read(42), const AgentChunk('42'));
    });

    test('every frame the chat reads, typed; anything else ignored', () {
      expect((ChatFrame.parse('{"type":"text","data":"Hi"}')! as ChatText).chunk.text, 'Hi');
      expect((ChatFrame.parse('{"type":"widget","widget":{"widget_id":"w1"}}')! as ChatWidget).widget['widget_id'], 'w1');
      expect(ChatFrame.parse('{"type":"widget_pending"}'), isA<ChatWidgetPending>());
      final a = ChatFrame.parse('{"type":"app_action","action":{"action_id":"a1","name":"open","arguments":{"x":1}}}')!
          as ChatAction;
      expect(<Object?>[a.actionId, a.name, a.arguments], <Object?>['a1', 'open', <String, Object?>{'x': 1}]);
      expect((ChatFrame.parse('{"type":"beginning_of_stream"}')! as ChatStream).start, isTrue);
      expect((ChatFrame.parse('{"type":"end_of_stream"}')! as ChatStream).start, isFalse);
      expect(ChatFrame.parse('{"type":"interruption"}'), isA<ChatClear>());
      expect(ChatFrame.parse(utf8.encode('{"type":"clear"}')), isA<ChatClear>(), reason: 'a binary frame of JSON');
      for (final junk in <Object?>['{"type":"pong"}', '{"type":"ack"}', 'not json', '[1]', null, '{"type":"app_action"}']) {
        expect(ChatFrame.parse(junk), isNull, reason: '$junk');
      }
    });

    test('what goes out, byte for byte', () {
      expect(ChatWire.init(const <String, String>{'name': 'Asha'}), <String, Object?>{
        'type': 'init',
        'event': 'start',
        'meta_data': <String, Object?>{'client': 'graine-flutter-sdk', 'context_data': <String, Object?>{'name': 'Asha'}},
      });
      expect(ChatWire.stop, <String, Object?>{'type': 'stop', 'event': 'stop', 'data': 'client_hangup'});
      expect(ChatWire.text('Hi'), <String, Object?>{'type': 'text', 'data': 'Hi'});
      expect(ChatWire.widgetResult('w1', const <String, Object?>{'chosen': 'Yes'}),
          <String, Object?>{'type': 'widget_result', 'widget_id': 'w1', 'data': <String, Object?>{'chosen': 'Yes'}});
      expect(ChatWire.actionResult('a1', const ActionResult.ok('Done', <String, Object?>{'n': 1})), <String, Object?>{
        'type': 'app_action_result', 'action_id': 'a1', 'status': 'ok', 'message': 'Done', 'data': <String, Object?>{'n': 1},
      });
      expect(ChatWire.actionResult('a2', const ActionResult.ok()),
          <String, Object?>{'type': 'app_action_result', 'action_id': 'a2', 'status': 'ok'});
      expect(
        ChatWire.appContext(<String, Object?>{'context': <String, Object?>{'screen': 'pan'}, 'availableActions': <String>[], 'seq': 3}),
        <String, Object?>{'type': 'app_context', 'context': <String, Object?>{'screen': 'pan'}, 'available_actions': <String>[], 'seq': 3},
        reason: "the socket's own spelling, and [] carried exactly",
      );
      expect(ChatWire.appContext(<String, Object?>{'context': <String, Object?>{}, 'seq': 1}).containsKey('available_actions'),
          isFalse);
      expect(
        ChatWire.appEvent('component_dismissed', detail: 'Closed.', data: const <String, Object?>{'quiet': true}),
        <String, Object?>{
          'type': 'app_event',
          'event': <String, Object?>{'name': 'component_dismissed', 'detail': 'Closed.', 'quiet': true},
        },
      );
    });

    // 0.14.4 review — the event's shape on every SDK (iOS ChatWire.appEventFrame; RN's AppEvent):
    // {name, detail?, cooldown_seconds?, max_per_session?, quiet?, data?}.
    test("an app event's name and detail are the call's own: a data key never replaces them; the pacing at the "
        "event's level, everything else under data", () {
      expect(
        ChatWire.appEvent('medication_due', detail: 'The 8 pm dose is due.', data: const <String, Object?>{
          'name': 'Metformin',
          'detail': 'not the detail',
          'dose_mg': 500,
          'cooldown_seconds': 0,
          'max_per_session': 5,
          'quiet': false,
        }),
        <String, Object?>{
          'type': 'app_event',
          'event': <String, Object?>{
            'name': 'medication_due',
            'detail': 'The 8 pm dose is due.',
            'cooldown_seconds': 0,
            'max_per_session': 5,
            'quiet': false,
            'data': <String, Object?>{'name': 'Metformin', 'detail': 'not the detail', 'dose_mg': 500},
          },
        },
      );
      expect(
        ChatWire.appEvent('reminder_opened', data: const <String, Object?>{'detail': 'from data'})['event'],
        <String, Object?>{
          'name': 'reminder_opened',
          'data': <String, Object?>{'detail': 'from data'},
        },
        reason: 'no detail given: a data key is data, never the detail',
      );
      expect(
        ChatWire.appEvent('component_dismissed', detail: 'Closed.', data: <String, Object?>{
          'quiet': true,
          'data': <String, Object?>{'widget_id': 'w1', 'kind': 'cards'},
          'kind': 'not this',
          'screen': 'plans',
        })['event'],
        <String, Object?>{
          'name': 'component_dismissed',
          'detail': 'Closed.',
          'quiet': true,
          'data': <String, Object?>{'widget_id': 'w1', 'kind': 'cards', 'screen': 'plans'},
        },
        reason: "a data map of its own is the event's data; other keys join it, never over it",
      );
      expect(
        ChatWire.appEvent('x', data: <String, Object?>{'data': 'plain', 'at': DateTime.utc(2026, 10, 26), 'ratio': double.nan})['event'],
        <String, Object?>{
          'name': 'x',
          'data': <String, Object?>{'data': 'plain', 'at': '2026-10-26 00:00:00.000Z', 'ratio': null},
        },
        reason: 'a data that is not a map is kept, under data; what JSON cannot carry is made so',
      );
    });

    test('without a ticket, the runtime directly — a text chat — with the variables on the URL', () {
      expect(ChatWire.directUrl(null, 'webcall-1'), 'wss://ws.graine.ai/chat/v1/webcall-1?text_chat=1');
      expect(ChatWire.directUrl('wss://ws.graine.ai//', 'a b'), 'wss://ws.graine.ai/chat/v1/a%20b?text_chat=1');
      expect(ChatWire.withContextToken('wss://socket.test/x?text_chat=1', 'a+b'), 'wss://socket.test/x?text_chat=1&context_token=a%2Bb');
      expect(ChatWire.withContextToken('wss://socket.test/x', 'tok'), 'wss://socket.test/x?context_token=tok');
      expect(ChatWire.withContextToken('wss://socket.test/x', null), 'wss://socket.test/x');
    });
  });

  group('sdk/contract/native-calls.json: the variables on a socket and a ticket', () {
    late Map<String, Object?> fx;
    setUpAll(() async => fx = await contractJson('contract/native-calls.json'));

    test('contextToken, byte for byte', () {
      final cases = (fx['contextToken']! as List<Object?>).cast<Map<String, Object?>>();
      expect(cases, isNotEmpty);
      for (final c in cases) {
        expect(
          Protocol.contextToken((c['vars']! as Map<String, Object?>), callType: c['callType']! as String),
          c['expect'],
          reason: '${c['name']}',
        );
      }
      final chat = Protocol.contextToken(const <String, Object?>{'name': 'Asha'}, callType: 'text_chat')!;
      expect(jsonDecode(utf8.decode(base64.decode(chat))), <String, Object?>{
        'name': 'Asha',
        'call_type': 'text_chat',
        'recipient_data': <String, Object?>{'name': 'Asha', 'call_type': 'text_chat'},
      });
    });

    test('ticket metadata, cut and capped as the server caps it', () {
      final t = fx['ticketMetadata']! as Map<String, Object?>;
      final limits = t['limits']! as Map<String, Object?>;
      expect(<Object?>[Protocol.ticketMaxKeys, Protocol.ticketMaxKeyLength, Protocol.ticketMaxValueLength, Protocol.ticketMaxBytes],
          <Object?>[limits['keys'], limits['keyLength'], limits['valueLength'], limits['totalBytes']]);
      final cases = (t['cases']! as List<Object?>).cast<Map<String, Object?>>();
      expect(cases, hasLength(8));
      for (final c in cases) {
        final got = Protocol.ticketMetadata(c['vars']! as Map<String, Object?>);
        expect(got, c['expect'], reason: '${c['name']}');
        // And in the same order: who_called and call_reason ride first.
        final want = c['expect'] as Map<String, Object?>?;
        if (want != null) expect(got!.keys.toList(), want.keys.toList(), reason: '${c['name']}: keys, in order');
      }
    });

    test('the chat speaks the same subprotocol, ping and open timeout as the native engines', () {
      final frames = fx['frames']! as Map<String, Object?>;
      expect(ChatWire.subprotocol, frames['subprotocol']);
      expect(ChatWire.pingMs, frames['pingMs']);
      expect(ChatWire.openTimeoutMs, frames['socketOpenTimeoutMs']);
      expect(ChatWire.stop, frames['stop']);
      expect(ChatWire.ping, frames['ping']);
    });
  });

  group('ChatTranscript: one turn per agent reply', () {
    DateTime at(int s) => t0.add(Duration(seconds: s));
    List<String> said(ChatTranscript c) => <String>[for (final t in c.turns) '${t.role.name}: ${t.text}'];

    test("a reply streams into one turn and ends on its marker; the next reply is its own", () {
      final c = ChatTranscript();
      expect(c.agent('Hello! ', at(0)), isTrue, reason: 'the welcome: the agent spoke first');
      c.agent('How can I help?', at(0));
      c.turnEnded();
      c.agent('By the way, your KYC is pending.', at(5));
      c.turnEnded();
      expect(said(c), <String>['agent: Hello! How can I help?', 'agent: By the way, your KYC is pending.']);
      expect(c.turns.every((GraineChatTurn t) => !t.live), isTrue, reason: 'a finished turn is not provisional');
      expect(c.turns.map((GraineChatTurn t) => t.proactive), <bool>[true, true]);
      expect(c.turns.map((GraineChatTurn t) => t.id), <String>['t1', 't2']);
      expect(c.turns.first.delivery, isNull, reason: "delivery is a user turn's");
      expect(c.messages.first, const Caption(Role.agent, 'Hello! How can I help?'));
    });

    test('typing: from the user to the first word of the answer — which is no volunteer', () {
      final c = ChatTranscript();
      expect(c.agentTyping, isFalse);
      final mine = c.customer('Where is my card?', at(1));
      expect(mine.role, GraineChatRole.user);
      expect(mine.delivery, GraineChatDelivery.sent);
      expect(c.agentTyping, isTrue);
      c.turnStarted();
      expect(c.agentTyping, isTrue, reason: 'the start marker, no words yet');
      expect(c.agent('It shipped ', at(2)), isFalse, reason: 'an answer, not a volunteer');
      expect(c.turns.last.proactive, isFalse);
      expect(c.agentTyping, isFalse);
      expect(c.turns.last.live, isTrue);
      c.turnEnded();
      c.turnStarted();
      expect(c.agentTyping, isTrue, reason: 'the agent opened a turn of its own');
      c.closed();
      expect(c.agentTyping, isFalse, reason: 'a closed socket owes nothing');
    });

    test('the user speaking ends the turn; later words of it open a new turn', () {
      final c = ChatTranscript();
      c.agent('Let me check', at(0));
      c.customer('Actually, cancel it', at(1));
      c.agent(' — done.', at(2));
      expect(c.turns.map((GraineChatTurn t) => '${t.role.name}:${t.text}:${t.live}'),
          <String>['agent:Let me check:false', 'user:Actually, cancel it:false', 'agent: — done.:true']);
    });

    test('typed offline: sending, then sent; not sent when the chat gives up, and sending again on the next try', () {
      final c = ChatTranscript();
      final t = c.customer('Hello?', at(0), pending: true);
      expect(t.delivery, GraineChatDelivery.sending);
      expect(c.pending.map((GraineChatTurn p) => p.text), <String>['Hello?']);
      expect(c.agentTyping, isFalse);
      c.failPending();
      expect(c.turns.single.delivery, GraineChatDelivery.failed);
      expect(c.pending, hasLength(1), reason: 'still to go');
      c.retryFailed();
      expect(c.turns.single.delivery, GraineChatDelivery.sending);
      c.sent(t.id);
      expect(c.pending, isEmpty);
      expect(c.turns.single.delivery, GraineChatDelivery.sent);
      expect(c.agentTyping, isTrue);
    });

    test('a component belongs to the agent turn it came with — or is a turn of its own', () {
      final c = ChatTranscript();
      final cars = GraineWidget.adopt(<String, Object?>{'widget_id': 'w1', 'kind': 'choices'}, 'https://www.graine.ai')!;
      c.component(cars, at(0));
      expect(c.turns.single.component, same(cars));
      expect(c.turns.single.text, '', reason: 'only a component');
      c.customer('The first', at(1));
      c.agent('Here are three:', at(2));
      final more = GraineWidget.adopt(<String, Object?>{'widget_id': 'w2', 'kind': 'choices'}, 'https://www.graine.ai')!;
      c.component(more, at(2));
      expect(c.turns.last.component, same(more));
      expect(c.turns.last.text, 'Here are three:');
    });

    test('a component answered: the turn is over and an answer is owed', () {
      final c = ChatTranscript();
      c.agent('Pick one', at(0));
      c.expectReply();
      expect(c.turns.single.live, isFalse);
      expect(c.agentTyping, isTrue);
    });

    test('kept to its size, oldest first out; cleared for someone else', () {
      final c = ChatTranscript(max: 3);
      for (var i = 0; i < 5; i++) {
        c.customer('m$i', at(i));
      }
      expect(c.turns.map((GraineChatTurn t) => t.text), <String>['m2', 'm3', 'm4']);
      expect(c.turns.last.id, 't5');
      c.clear();
      expect(c.turns, isEmpty);
      expect(c.agentTyping, isFalse);
    });
  });

  group("a screen's actions (the React Native SDK's rule)", () {
    test('stated, narrowed to what is registered; [] when the screen said so; absent when nothing is registered', () {
      expect(ContextFrame.availableActions(<String>['a', 'b'], <String>['b', 'c']), <String>['b']);
      expect(ContextFrame.availableActions(null, <String>['b', 'c']), <String>['b', 'c']);
      expect(ContextFrame.availableActions(<String>['a'], <String>['b']), <String>[],
          reason: 'the screen stated its actions and none is in this build');
      expect(ContextFrame.availableActions(<String>[], <String>['b']), <String>[]);
      expect(ContextFrame.availableActions(null, const <String>[]), isNull,
          reason: 'an empty registry must not disarm the agent');
      expect(ContextFrame.availableActions(<String>['a'], null), <String>['a'], reason: 'no registry given: as stated');
    });

    test('the frame carries the narrowed list', () {
      final frame = ContextFrame.build(
        screen: const GraineScreen('pan', availableActions: <String>['fill_pan', 'not_built']),
        screenSinceMs: 0,
        nowMs: 0,
        registeredActions: const <String>['fill_pan', 'open_help'],
      )!;
      expect(frame['availableActions'], <String>['fill_pan']);
    });

    test('a field replaced by name, added, or removed', () {
      const s = GraineScreen('kyc', title: 'KYC', fields: <GraineField>[GraineField('pan', value: 'A'), GraineField('dob')]);
      final replaced = s.withField(const GraineField('pan', value: 'AB', status: FieldStatus.filled));
      expect(replaced.fields.map((GraineField f) => f.value), <String?>['AB', null]);
      expect(replaced.title, 'KYC');
      expect(s.withField(const GraineField('city')).fields.map((GraineField f) => f.name), <String>['pan', 'dob', 'city']);
      expect(s.withoutField('dob').fields.map((GraineField f) => f.name), <String>['pan']);
      expect(identical(s.withoutField('nope'), s), isTrue);
    });
  });

  group('the chat and call tokens (§7)', () {
    Map<String, Object?> chatTokens() => <String, Object?>{
          'title': 'Ask Asha',
          'subtitle': 'Replies in seconds',
          'avatar': 'glyph',
          'placeholder': 'Type here…',
          'showTimestamps': true,
          'suggestions': <Object?>['Track my order', 'Talk to a person', 'Refunds', 'Change address', 'Fifth'],
          'background': '#F4F6FF',
          'pattern': 'dots',
          'patternColor': '#DDE2F0',
          'headerBackground': '#3B5BDB',
          'headerText': '#FFFFFF',
          'headerSubtext': '#D7DEFA',
          'composerBackground': '#FFFFFF',
          'composerText': '#101318',
          'composerPlaceholder': '#5F6672',
          'composerBorder': '#E5E4E0',
          'size': 'large',
          'showUpcomingCalls': false,
          'upcomingTitle': 'Your calls',
          'showHistory': false,
          'newConversation': false,
        };
    Map<String, Object?> callTokens() => <String, Object?>{
          'background': '#3B5BDB',
          'backgroundTo': '#20327A',
          'text': '#FFFFFF',
          'textMuted': '#D7DEFA',
          'avatar': 'initials',
          'avatarShape': 'squircle',
          'avatarFill': '#FFFFFF',
          'avatarText': '#3B5BDB',
          'buttonFill': '#4C69DE',
          'buttonIcon': '#FFFFFF',
          'buttonActiveFill': '#FFFFFF',
          'buttonActiveIcon': '#3B5BDB',
          'endFill': '#DC2626',
          'endIcon': '#FFFFFF',
          'endShape': 'pill',
          'acceptFill': '#16A34A',
          'acceptIcon': '#FFFFFF',
          'declineFill': '#DC2626',
          'declineIcon': '#FFFFFF',
          'callbackFill': '#FFFFFF',
          'callbackIcon': '#3B5BDB',
          'captions': false,
          'timer': true,
          'controls': <Object?>['speaker', 'mute', 'end'],
          'ringtone': 'soft',
          'statusText': <String, Object?>{
            'ringing': 'Asha is calling',
            'scheduled': 'Your booked call',
            'connecting': 'Joining…',
            'ended': 'Bye',
            'missed': 'You missed Asha',
          },
        };
    Map<String, Object?> tokens({Map<String, Object?>? chat, Map<String, Object?>? call}) => <String, Object?>{
          'scheme': 'light',
          'colors': <String, Object?>{'accent': '#3B5BDB', 'background': '#F7F7F5', 'surface': '#FFFFFF'},
          if (chat != null) 'chat': chat,
          if (call != null) 'call': call,
        };

    test('served, every token is read — and read back key for key', () {
      final full = <String, Object?>{...chatTokens(), 'suggestions': <Object?>['Track my order', 'Talk to a person']};
      final t = ThemeTokens.fromJson(tokens(chat: full, call: callTokens()))!;
      expect(t.servedChat, isNotNull);
      expect(canon(t.toJson()['chat']), canon(full));
      expect(canon(t.toJson()['call']), canon(callTokens()));
      expect(t.chat.title, 'Ask Asha');
      expect(t.chat.pattern, 'dots');
      expect(t.call.statusText.ringing, 'Asha is calling');
      expect(t.call.backgroundTo, '#20327A');
    });

    test('at most four starters; every in-call button list ends with a way to hang up', () {
      final t = ThemeTokens.fromJson(tokens(chat: chatTokens(), call: <String, Object?>{...callTokens(), 'controls': <Object?>['mute', 'bogus', 'mute']}))!;
      expect(t.chat.suggestions, <String>['Track my order', 'Talk to a person', 'Refunds', 'Change address']);
      expect(t.call.controls, <String>['mute', 'end']);
    });

    test('a token that is not what it should be draws as the window always was', () {
      final bad = <String, Object?>{'headerBackground': 'blue', 'avatar': 'face', 'pattern': 'zigzag'};
      final logo = ThemeTokens.fromJson(
          <String, Object?>{...tokens(chat: bad), 'icons': <String, Object?>{'launcher': null}})!;
      expect(logo.chat.headerBackground, '#FFFFFF', reason: 'the surface, as the header was');
      expect(logo.chat.avatar, 'logo', reason: 'the launcher shows the logo: so does the header');
      expect(logo.chat.pattern, 'none');
      expect(logo.chat.background, '#F7F7F5');
      final glyph = ThemeTokens.fromJson(tokens(chat: bad))!;
      expect(glyph.chat.avatar, 'glyph', reason: "the launcher's glyph (Graine Classic's, unsaid)");
    });

    test('from an older server: nothing served, nothing read back — and the window as it was', () {
      final t = ThemeTokens.fromJson(tokens())!;
      expect(t.servedChat, isNull);
      expect(t.servedCall, isNull);
      expect(t.toJson().containsKey('chat'), isFalse, reason: 'an older session read back is what it said');
      expect(t.toJson().containsKey('call'), isFalse);
      expect(t.chat.headerBackground, t.colors.surface);
      expect(t.chat.composerBackground, t.colors.surfaceRaised);
      expect(t.chat.placeholder, '', reason: '"" is "Message…"');
      expect(t.call.background, '#0F1115', reason: 'the fixed dark call screen');
      expect(t.call.controls, ThemeCall.defaultControls);
      expect(t.call.statusText.ended, 'Call ended');
      expect(t.call.statusText.scheduled, 'Scheduled call');
      expect(t.call.statusText.missed, 'Missed call');
      expect(t.call.callbackFill, t.colors.accent, reason: 'Call back in the accent');
    });

    test('mixHex is the design system\'s', () {
      expect(Design.mixHex('#000000', '#FFFFFF', 0.5), '#808080');
      expect(Design.mixHex('#318CE7', '#318CE7', 0.3), '#318CE7');
      expect(Design.mixHex('#FFFFFF', '#000000', 0), '#FFFFFF');
      expect(Design.mixHex('nope', '#FFFFFF', 1), '#FFFFFF');
    });
  });
}

const String testInstall = '3f2504e0-4f89-11d3-9a0c-0305e82c3301';
