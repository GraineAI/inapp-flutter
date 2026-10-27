import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

// SERVER TOKENS — a short-lived token your server mints for the signed-in user
// of one agent, which the SDK sends with every request to Graine (contract:
// sdk/contract/CLIENT-TOKENS.md, vectors in client-tokens.json). Once the
// agent's "Require server tokens" is enforced, the publishable key alone opens
// nothing: every request without a good token is refused.
//
// The SDK never reads a token beyond its `iat` and `exp` — when it was minted
// and when it lapses, unverified — and only to know when to ask for the next
// one. It never logs one, never keeps one on the device, and never ends a live
// chat or call because one expired: tokens are checked when a conversation
// starts, never while it runs.

/// What a token says about its own life, unverified: `iat` and `exp`, in
/// seconds since the epoch; null when not readable.
typedef ClientTokenClaims = ({double? iat, double? exp});

/// Runs a task after [delayMs] milliseconds; returns what cancels it.
typedef ClientTokenTimer = void Function() Function(int delayMs, void Function() task);

/// THE RULES, pure — every number and word the contract fixes, so the vectors
/// in client-tokens.json hold them (test/client_tokens_contract_test.dart) and
/// every SDK refreshes on the same schedule. Not exported.
abstract final class ClientTokenRules {
  /// The top-level field every request to Graine carries the token in.
  static const String field = 'clientToken';

  /// A new connection uses the token it holds while it has more than this left.
  static const int usableForConnectionMs = 15000;

  /// Otherwise it waits at most this long for a refresh, then goes with the newest token it has.
  static const int connectionWaitMs = 10000;

  /// A refusal asks for a new token at most once in this long.
  static const int forcedMinIntervalMs = 5000;

  /// A refresh in the background is never sooner than this after the last token arrived.
  static const int backgroundMinIntervalMs = 30000;

  /// How long the engine page — and the native call engine — wait for the token they asked for.
  static const int pageWaitMs = 5000;

  /// A provider that has not answered in this long has answered null.
  static const int providerTimeoutMs = 15000;

  /// Each backoff after a failure is varied by up to this share, either way.
  static const double backoffJitter = 0.2;

  /// The engine page's messages: the token, host → page; a request for one, page → host.
  static const String pageToken = 'graine:client-token';
  static const String pageNeedsToken = 'graine:need-client-token';

  /// The native call engine's method that takes the newest token, and its event asking for one (§2.4).
  static const String hostSetToken = 'setClientToken';
  static const String hostNeedsToken = 'needClientToken';

  /// Refusals a fresh token can fix: refresh, then the same request once more.
  static const Set<String> refreshable = <String>{'token_required', 'token_invalid', 'token_expired'};

  /// Every refusal for the token, the publishable key or the website bot
  /// check: final for the request that met it — a conversation refused with
  /// one is never tried another way.
  static const Set<String> refusals = <String>{
    'token_required',
    'token_invalid',
    'token_expired',
    'token_scope',
    'key_revoked',
    'bot_check_failed',
  };

  /// `iat` and `exp` from the token's payload — the middle of its three
  /// parts, base64url JSON — or nulls. Nothing else is read.
  static ClientTokenClaims decode(String? token) {
    const ClientTokenClaims none = (iat: null, exp: null);
    if (token == null) return none;
    final parts = token.trim().split('.');
    if (parts.length < 2 || parts[1].isEmpty) return none;
    Object? json;
    try {
      json = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    } catch (_) {
      return none;
    }
    if (json is! Map) return none;
    double? seconds(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
    return (iat: seconds(json['iat']), exp: seconds(json['exp']));
  }

  /// `exp − iat`, in ms; null without both, or with no life between them.
  static int? lifetimeMs(ClientTokenClaims claims) {
    final iat = claims.iat;
    final exp = claims.exp;
    if (iat == null || exp == null) return null;
    final life = ((exp - iat) * 1000).round();
    return life > 0 ? life : null;
  }

  /// WHEN A TOKEN LAPSES, BY THIS DEVICE'S CLOCK (ms): `min(exp, receivedAt +
  /// lifetime)` — a token the app's server cached keeps its real expiry, and a
  /// clock that runs behind only refreshes early — or, when that is no more
  /// than 15 s after it arrived (a clock far ahead, a stale token),
  /// `receivedAt + lifetime`: the token is used and Graine judges it. Null when
  /// the token has no readable `iat` and `exp`, or no life between them: then
  /// nothing is refreshed in the background, and only a refusal asks for another.
  static int? localExpiry(ClientTokenClaims claims, int receivedAtMs) {
    final life = lifetimeMs(claims);
    final exp = claims.exp;
    if (life == null || exp == null) return null;
    final local = math.min((exp * 1000).round(), receivedAtMs + life);
    return local <= receivedAtMs + usableForConnectionMs ? receivedAtMs + life : local;
  }

  /// How long before it lapses a token is refreshed: `clamp(lifetime / 5, min(60 s, lifetime / 2), 600 s)`.
  static int leadMs(int lifetimeMs) {
    final low = math.min(60000, lifetimeMs ~/ 2);
    return math.max(low, math.min(lifetimeMs ~/ 5, 600000));
  }

  /// The most a refresh is moved earlier, so a fleet does not refresh in step: `min(30 s, lifetime / 10)`.
  static int maxJitterMs(int lifetimeMs) => math.min(30000, lifetimeMs ~/ 10);

  /// A new connection may go with a token that has more than 15 s left; one with no readable expiry always may.
  static bool usable(int? localExpMs, int nowMs) => localExpMs == null || localExpMs - nowMs > usableForConnectionMs;

  /// The wait after the [failures]-th failure in a row, before its jitter: `min(60, 2^n)` seconds.
  static int backoffMs(int failures) => math.min(60000, (1 << failures.clamp(1, 6)) * 1000);

  /// The error code an answer's body names, trimmed and lowercased; null when it names none.
  static String? codeOf(Map<String, Object?>? body) {
    final c = body?['code'];
    if (c is! String) return null;
    final t = c.trim().toLowerCase();
    return t.isEmpty ? null : t;
  }

  /// A refusal Graine can lift with a fresh token: the request is sent once more with one.
  static bool isRefreshable(int status, Map<String, Object?>? body) =>
      (status < 200 || status > 299) && refreshable.contains(codeOf(body));

  /// The SDK's own sentence for a refusal Graine sent without one.
  static String sentence(String code) => switch (code) {
        'token_required' => 'This agent requires a server token: set tokenProvider in GraineConfig.',
        'token_invalid' => 'The server token could not be checked.',
        'token_expired' => 'The server token expired, and a fresh one did not come in time.',
        'token_scope' => 'The server token does not allow this.',
        'key_revoked' => "This publishable key was revoked. Update the app with the agent's new key.",
        'bot_check_failed' => 'The bot check did not pass.',
        _ => 'Graine refused the request.',
      };
}

/// One question to the provider under way, and who waits for its answer.
class _Flight {
  _Flight(this.generation);

  /// The user it was asked for ([ClientTokens.renew] moves on): an answer for an earlier one is not kept.
  final int generation;
  final List<void Function(String?)> waiters = <void Function(String?)>[];
  void Function()? cancelTimeout;
  bool done = false;
}

/// ONE AGENT'S SERVER TOKENS (CLIENT-TOKENS.md §2.3): the newest token, when
/// to ask for the next, and everyone waiting for it.
///
///   at start        asked at once ([start])
///   in the          at the token's local expiry, less the lead, less a
///   background      jitter — never sooner than 30 s after the last token
///                   arrived; none for a token with no readable expiry
///   one at a time   one question to the provider at a time; every caller
///                   waits on the one under way
///   a failure       (null, a throw, no answer in 15 s) asked again after 2,
///                   4, 8, 16, 32, 60, 60… s, ±20 %; reset by a token
///   the app away    nothing asked while the app is in the background; back
///                   in front, asked when inside the lead
///   a connection    (the session, a ticket) goes with the token while it has
///                   more than 15 s left, else waits at most 10 s for a
///                   refresh, then goes with the newest it has
///   a refusal       (token_required, token_expired, token_invalid) asks
///                   again — at most once in 5 s — and the request goes once
///                   more, only with a different token
///   a ring          asked in the background before anyone answers
///
/// Nothing here ever touches a live chat or call. Without a provider tokens
/// are not in play ([inPlay]) and no request carries one. The clock, the
/// jitter's randomness and the timers are the caller's to hand in. Not exported.
class ClientTokens {
  ClientTokens(
    this._provider, {
    int Function()? clock,
    double Function()? random,
    ClientTokenTimer? schedule,
    this.providerTimeoutMs = ClientTokenRules.providerTimeoutMs,
    this.connectionWaitMs = ClientTokenRules.connectionWaitMs,
  })  : _clock = clock ?? _wallClock,
        _random = random ?? math.Random().nextDouble,
        _schedule = schedule ?? _dartTimer;

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;

  static void Function() _dartTimer(int delayMs, void Function() task) =>
      Timer(Duration(milliseconds: delayMs), task).cancel;

  /// The app's provider; null: tokens are not in play.
  final Future<String?> Function()? _provider;

  /// The device's wall clock, in ms: a token's life is read against it.
  final int Function() _clock;

  /// Uniform in [0, 1): the jitter of a refresh and of a backoff.
  final double Function() _random;
  final ClientTokenTimer _schedule;

  /// A provider that has not answered in this long has answered null.
  final int providerTimeoutMs;

  /// The most a new connection, or a request refused for its token, waits for a refresh.
  final int connectionWaitMs;

  String? _held;
  int? _localExp;
  int? _lifetime;

  /// This token's jitter, drawn when it arrived: its refresh moves earlier by it.
  int _jitterMs = 0;
  int? _lastTokenAt;
  int? _lastForcedAt;
  int _failures = 0;
  _Flight? _flight;

  /// Bumped by [renew]: a question asked for the user before finishes, but its answer is not kept.
  int _generation = 0;

  /// [start] was called: [renew] asks at once.
  bool _started = false;

  /// The background question armed, and its generation: a task from an older one does nothing.
  void Function()? _armed;
  int _armGeneration = 0;
  bool _foreground = true;
  bool _disposed = false;
  final List<void Function(String?)> _watchers = <void Function(String?)>[];

  /// Tokens are in play: the app gave a provider. Otherwise no request carries one — nothing changes.
  bool get inPlay => _provider != null;

  /// The newest token held — even one past its expiry: Graine may still take
  /// it, answering a ring within its grace. Null before the first arrives.
  String? get newest => _held;

  /// The token's expiry by this device's clock, in ms; null without a token or a readable expiry.
  int? get localExpiry => _localExp;

  /// The app's provider is asked at once.
  void start() {
    _started = true;
    if (_provider != null && !_disposed) _ask(forced: false);
  }

  /// ANOTHER USER: identify() named someone else, or nobody. The token held
  /// was minted for the user before — sent now it would speak for them — so
  /// it is let go of, an answer still on its way for them is not kept, and a
  /// fresh one is asked for at once. Until it comes, a new connection waits
  /// for it (at most 10 s) and other requests go without a token. What signs
  /// the user before out carries their token, taken before this
  /// ([ClientTokenWire.post] `pinned`).
  void renew() {
    if (_provider == null || _disposed) return;
    // A question under way finishes as it would (its waiters hear the newest token then), but its answer is not kept.
    _generation++;
    _flight = null;
    final had = _held != null;
    _held = null;
    _localExp = null;
    _lifetime = null;
    _jitterMs = 0;
    _failures = 0;
    _lastForcedAt = null;
    _cancelArmed();
    if (had) _announce(null);
    if (_started) _ask(forced: false);
  }

  /// Hear every new token — the engine page and the native call engine are
  /// handed each. Returns what stops it.
  void Function() onChange(void Function(String?) watch) {
    _watchers.add(watch);
    return () => _watchers.remove(watch);
  }

  /// THE TOKEN A NEW CONNECTION GOES WITH — the session, a ticket: the one
  /// held while it has more than 15 s left; otherwise a refresh, waited for at
  /// most 10 s, then the newest token there is (perhaps none). Null at once
  /// when tokens are not in play.
  Future<String?> forConnection() {
    if (_provider == null || _disposed) return Future<String?>.value(_held);
    final t = _held;
    if (t != null && ClientTokenRules.usable(_localExp, _clock())) return Future<String?>.value(t);
    return _await(forced: false);
  }

  /// A REQUEST CARRYING [sent] WAS REFUSED for its token (token_required,
  /// token_expired, token_invalid): a fresh token is asked for — joining the
  /// question under way, or asking anew at most once in 5 s — and waited for.
  /// The token to send the request again with, or null when there is none
  /// other than [sent]: the same token, or none, leaves the refusal standing.
  Future<String?> afterRefusal(String? sent) async {
    if (_provider == null || _disposed) return null;
    if (_mayAskAgain()) await _await(forced: true);
    final h = _held;
    return h != null && h != sent ? h : null;
  }

  /// SOMEONE ELSE WAS REFUSED FOR ITS TOKEN — the engine page
  /// (`graine:need-client-token`), the native call engine (`needClientToken`):
  /// a fresh token by the refusal rule — the question under way joined, at
  /// most one asked anew in 5 s — and then the newest there is; at once when
  /// none may be asked for now. Null with no provider.
  Future<String?> refresh() {
    if (_provider == null || _disposed || !_mayAskAgain()) return Future<String?>.value(_held);
    final done = Completer<String?>();
    _ask(forced: true, then: done.complete);
    return done.future;
  }

  /// A call is ringing: a fresh token is asked for in the background, so the
  /// answer finds one — unless one arrived in the last 30 s or a question is
  /// already under way.
  void ring() {
    if (_provider == null || _disposed || _flight != null) return;
    final last = _lastTokenAt;
    if (last != null && _clock() - last < ClientTokenRules.backgroundMinIntervalMs) return;
    _ask(forced: false);
  }

  /// The app came to the front (true) or went to the background: nothing is
  /// asked in the background; back in front, a token inside its lead — or
  /// none, or one whose last question failed — is asked for (never sooner than
  /// 30 s after the last token arrived), and any other is scheduled again.
  void setForeground(bool inFront) {
    if (_foreground == inFront || _disposed) return;
    _foreground = inFront;
    if (!inFront) {
      _cancelArmed();
      return;
    }
    if (_provider == null || _flight != null) return;
    final now = _clock();
    final exp = _localExp;
    final life = _lifetime;
    if (_held == null || _failures > 0) {
      _ask(forced: false);
    } else if (exp == null || life == null) {
      // No readable expiry: never refreshed in the background.
    } else if (now >= exp - ClientTokenRules.leadMs(life)) {
      final earliest = (_lastTokenAt ?? now) + ClientTokenRules.backgroundMinIntervalMs;
      if (now >= earliest) {
        _ask(forced: false);
      } else {
        _arm(earliest - now);
      }
    } else {
      _armRefresh(now);
    }
  }

  /// Stop every timer; whoever waits hears the newest token at once. Nothing is asked after.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelArmed();
    final f = _flight;
    _flight = null;
    _watchers.clear();
    if (f == null || f.done) return;
    f.done = true;
    f.cancelTimeout?.call();
    for (final w in List<void Function(String?)>.of(f.waiters)) {
      w(_held);
    }
  }

  // ── asking ──────────────────────────────────────────────────────────────

  /// A refusal may ask for a token now: one is being asked for already (it is joined), or none was forced in the last 5 s.
  bool _mayAskAgain() {
    if (_flight != null) return true;
    final last = _lastForcedAt;
    return last == null || _clock() - last >= ClientTokenRules.forcedMinIntervalMs;
  }

  /// The newest token once the question under way — or a new one — has its
  /// answer, waiting at most [connectionWaitMs].
  Future<String?> _await({required bool forced}) {
    final done = Completer<String?>();
    void Function()? cancel;
    void finish(String? _) {
      if (done.isCompleted) return;
      cancel?.call();
      done.complete(_held);
    }

    cancel = _schedule(connectionWaitMs, () => finish(null));
    _ask(forced: forced, then: finish);
    return done.future;
  }

  /// One question at a time: [then] hears the newest token once the question
  /// under way — or this one — has its answer.
  void _ask({required bool forced, void Function(String?)? then}) {
    final p = _provider;
    if (p == null || _disposed) {
      then?.call(_held);
      return;
    }
    final under = _flight;
    if (under != null) {
      if (then != null) under.waiters.add(then);
      return;
    }
    final f = _Flight(_generation);
    if (then != null) f.waiters.add(then);
    _flight = f;
    if (forced) _lastForcedAt = _clock();
    _cancelArmed();
    f.cancelTimeout = _schedule(providerTimeoutMs, () => _finish(f, null));
    // A throw — at once or later — is a failure, as is no answer in time; a late answer is ignored.
    unawaited(Future<String?>.sync(p)
        .then<void>((String? token) => _finish(f, token), onError: (Object _) => _finish(f, null)));
  }

  /// The question [f] has its answer — the first one counts, a later one is ignored.
  void _finish(_Flight f, String? answer) {
    if (f.done) return;
    f.done = true;
    if (identical(_flight, f)) _flight = null;
    f.cancelTimeout?.call();
    if (_disposed) return;
    var changed = false;
    // Asked for the user before (renew): its waiters hear the newest token, and its answer is not kept.
    if (f.generation == _generation) {
      final now = _clock();
      final t = answer?.trim();
      if (t != null && t.isNotEmpty) {
        changed = t != _held;
        _accept(t, now);
        _armRefresh(now);
      } else {
        _failures++;
        _armBackoff();
      }
    }
    final newest = _held;
    if (changed) _announce(newest);
    for (final w in List<void Function(String?)>.of(f.waiters)) {
      w(newest);
    }
  }

  /// Every watcher hears [token] — a new one, or none when [renew] let one go.
  void _announce(String? token) {
    for (final w in List<void Function(String?)>.of(_watchers)) {
      try {
        w(token);
      } catch (_) {
        // A watcher's mistake is its own.
      }
    }
  }

  // ── the token held and its schedule ──────────────────────────────────────

  void _accept(String token, int now) {
    final claims = ClientTokenRules.decode(token);
    final life = ClientTokenRules.lifetimeMs(claims);
    _held = token;
    _lifetime = life;
    _localExp = ClientTokenRules.localExpiry(claims, now);
    _jitterMs = life == null ? 0 : (_random() * ClientTokenRules.maxJitterMs(life)).round();
    _lastTokenAt = now;
    _failures = 0;
  }

  /// The next refresh, in the background: the local expiry less the lead and the jitter, and never within 30 s of the last token.
  void _armRefresh(int now) {
    _cancelArmed();
    if (_provider == null || !_foreground) return;
    final exp = _localExp;
    final life = _lifetime;
    if (exp == null || life == null) return;
    final due = exp - ClientTokenRules.leadMs(life) - _jitterMs;
    final earliest = (_lastTokenAt ?? now) + ClientTokenRules.backgroundMinIntervalMs;
    _arm(math.max(due, earliest) - now);
  }

  /// After a failure: 2, 4, 8, 16, 32, 60, 60… s, each ±20 % — in front only.
  void _armBackoff() {
    _cancelArmed();
    if (_provider == null || !_foreground) return;
    final base = ClientTokenRules.backoffMs(_failures);
    _arm((base * (1 + ClientTokenRules.backoffJitter * (2 * _random() - 1))).round());
  }

  /// The background question, [delayMs] from now — replacing any other.
  void _arm(int delayMs) {
    _cancelArmed();
    final generation = _armGeneration;
    _armed = _schedule(math.max(0, delayMs), () {
      // Replaced or cancelled while it was due: the newer one decides.
      if (generation != _armGeneration) return;
      _armed = null;
      if (_foreground && _flight == null && !_disposed) _ask(forced: false);
    });
  }

  void _cancelArmed() {
    _armGeneration++;
    _armed?.call();
    _armed = null;
  }
}

/// ONE REQUEST TO GRAINE WITH THE SERVER TOKEN (CLIENT-TOKENS.md §2.2): the
/// body carries the newest token as `clientToken` — a new connection's (the
/// session, a ticket) waits for a usable one first — and a refusal a fresh
/// token can lift is answered once: a refresh, and the same request again with
/// the token it brought, only when it is a different one. Tokens not in play:
/// the body goes as it is, and nothing about the request changes. Not exported.
abstract final class ClientTokenWire {
  /// [send] posts [body] and answers with the reply; [refreshable] says
  /// whether a reply is a refusal a fresh token can lift. A throw from [send]
  /// goes up as it is.
  static Future<R> post<R>(
    ClientTokens? tokens,
    Map<String, Object?> body, {
    required bool newConnection,
    required Future<R> Function(Map<String, Object?> body) send,
    required bool Function(R reply) refreshable,
    bool pinned = false,
    String? pinnedToken,
  }) {
    if (tokens == null || !tokens.inPlay) return send(body);
    // PINNED (a sign-out): exactly the token of the user it is about — taken before identify() let it go — and
    // never sent again with another one, which could not speak for them.
    if (pinned) {
      carry(body, pinnedToken);
      return send(body);
    }
    return _withToken(tokens, body, newConnection: newConnection, send: send, refreshable: refreshable);
  }

  static Future<R> _withToken<R>(
    ClientTokens tokens,
    Map<String, Object?> body, {
    required bool newConnection,
    required Future<R> Function(Map<String, Object?> body) send,
    required bool Function(R reply) refreshable,
  }) async {
    final first = newConnection ? await tokens.forConnection() : tokens.newest;
    carry(body, first);
    final reply = await send(body);
    if (!refreshable(reply)) return reply;
    final next = await tokens.afterRefusal(first);
    if (next == null) return reply;
    carry(body, next);
    return send(body);
  }

  /// [token] as the body's `clientToken` — or no such field at all for none.
  static void carry(Map<String, Object?> body, String? token) {
    if (token == null) {
      body.remove(ClientTokenRules.field);
    } else {
      body[ClientTokenRules.field] = token;
    }
  }
}
