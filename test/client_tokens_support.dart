// What the server-token tests share: timers the test moves by hand, and tokens
// minted for them. Imports only Dart and package:test, so the pure tests stay pure.
import 'dart:convert';

import 'package:test/test.dart';

/// Tokens for the tests: a header, a payload with `iat` and `exp` (seconds),
/// and a signature nobody checks — the SDK reads only the two.
String mintToken(int iat, int exp, {String id = 'ct_test'}) {
  String part(Object json) => base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part(<String, Object?>{'alg': 'EdDSA', 'typ': 'JWT', 'kid': 'test-key-000000'})}.'
      '${part(<String, Object?>{'iss': 'graine', 'aud': 'graine-embed', 'sub': 'user-123', 'scp': <String>['chat', 'call'], 'iat': iat, 'exp': exp, 'jti': id})}'
      '.c2ln';
}

/// The `jti` a test token was minted with.
String jtiOf(String token) {
  final payload = base64Url.normalize(token.split('.')[1]);
  return (jsonDecode(utf8.decode(base64Url.decode(payload))) as Map<String, Object?>)['jti']! as String;
}

/// Everything already on its way — the provider's answer, the waiters it wakes — has happened.
Future<void> settle() => pumpEventQueue();

class _Task {
  _Task(this.due, this.seq, this.run);
  final int due;
  final int seq;
  final void Function() run;
}

/// THE TIMERS, IN THE TEST'S HANDS: [now] in ms from the test's start; a task
/// runs only when [advance] reaches its moment — in order, each followed by
/// everything it set off.
class ManualTimers {
  int now = 0;
  int _seq = 0;
  final List<_Task> _tasks = <_Task>[];

  /// How many tasks are waiting.
  int get pending => _tasks.length;

  void Function() schedule(int delayMs, void Function() task) {
    final t = _Task(now + delayMs, _seq++, task);
    _tasks.add(t);
    return () => _tasks.remove(t);
  }

  /// Move the clock [ms] on, running every task due on the way at its own moment.
  Future<void> advance(int ms) async {
    final until = now + ms;
    while (true) {
      _Task? next;
      for (final t in _tasks) {
        if (t.due > until) continue;
        if (next == null || t.due < next.due || (t.due == next.due && t.seq < next.seq)) next = t;
      }
      if (next == null) break;
      _tasks.remove(next);
      if (next.due > now) now = next.due;
      next.run();
      await settle();
    }
    now = until;
    await settle();
  }
}
