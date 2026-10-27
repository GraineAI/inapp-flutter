part of 'graine.dart';

/// THE PLUGIN'S APP CHANNEL, `ai.graine.inapp/app` — what its native code
/// reads and proves for "Your app and your users" (sdk/contract
/// APP-IDENTITY.md §1.2, §3.4–§3.6). It only reads and proves; every rule
/// applied to what it returns is in core/app_identity.dart:
///
///   `declaration`     → {platform: "ios", id, accessGroup?}      the bundle id, and the access group of
///                                                                 a Keychain item the app owns (Team ID)
///                       {platform: "android", id, certificates?}  the package, its signing certificates' DER
///   `readDebugToken`  → String?   development mode's token, kept with the install id
///   `writeDebugToken`   String
///   `prove`             {challenge, cloudProjectNumber?} → {kind: "attest", keyId, attestation}
///                       · {kind: "assert", keyId, assertion} · {kind: "play", token}
///                       · {error: "unsupported" | "missing_dependency" | "backoff" | "failed", message?}
///   `forgetProofKey`    the App Attest key Graine no longer knows is let go (iOS; nothing on Android)
///
/// Where there is no platform side (a test, a desktop build) nothing can be
/// read: no declaration — so no `app` on any request — and no debug token.
class _AppPlatform {
  _AppPlatform(this._channel);

  final MethodChannel _channel;
  Future<Map<String, Object?>?>? _declaration;
  Future<String?>? _debugToken;

  /// Development mode's token once it has been read; null before, and where it cannot be kept.
  String? debugTokenNow;

  /// The native proofs, one after another, whichever agent asks: two App
  /// Attest assertions racing could reach Graine out of order.
  Future<void> _proofs = Future<void>.value();

  /// The declaration, read once per process.
  Future<Map<String, Object?>?> declaration() => _declaration ??= _readDeclaration();

  Future<Map<String, Object?>?> _readDeclaration() async {
    try {
      return AppIdentity.declaration(await _channel.invokeMethod<Object?>('declaration'));
    } catch (_) {
      return null; // no platform side, or it could not say: no declaration, and no `app`
    }
  }

  /// DEVELOPMENT MODE'S TOKEN (§3.6): the one this install keeps, else a new
  /// one, kept — and logged once per install. Null where it cannot be kept.
  /// Only ever asked for when development mode is on: a release build that did
  /// not opt in never creates, logs or sends one.
  Future<String?> debugToken(_Device device) => _debugToken ??= _readDebugToken(device);

  Future<String?> _readDebugToken(_Device device) async {
    String token;
    try {
      final kept = await _channel.invokeMethod<String>('readDebugToken');
      if (AppIdentity.isDebugToken(kept)) {
        token = kept!;
      } else {
        token = AppIdentity.newDebugToken();
        await _channel.invokeMethod<void>('writeDebugToken', token);
      }
    } catch (_) {
      return null; // nowhere to keep one: no token on this platform
    }
    debugTokenNow = token;
    // ONCE per install: the device remembers which token it last named (a fingerprint, never the token).
    final mark = Sha256.hex(Sha256.ofText('graine:debug-token:v1\n$token').sublist(0, 8));
    if ((await device.prefs())['debugTokenLogged'] != mark) {
      debugPrint(AppIdentity.debugTokenLine(token));
      await device.updatePrefs((Map<String, Object?> p) => p['debugTokenLogged'] = mark);
    }
    return token;
  }

  /// One proof from the platform for [challenge] (§3.4, §3.5).
  Future<Map<String, Object?>> prove(String challenge, {String? cloudProjectNumber}) {
    final run = _proofs.then((_) => _prove(challenge, cloudProjectNumber));
    _proofs = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  Future<Map<String, Object?>> _prove(String challenge, String? cloudProjectNumber) async {
    try {
      final answer = await _channel.invokeMapMethod<String, Object?>('prove', <String, Object?>{
        'challenge': challenge,
        if (cloudProjectNumber != null) 'cloudProjectNumber': cloudProjectNumber,
      });
      return answer ?? const <String, Object?>{'error': 'unsupported'};
    } on MissingPluginException {
      return const <String, Object?>{'error': 'unsupported'};
    } catch (e) {
      return <String, Object?>{'error': 'failed', 'message': '$e'};
    }
  }

  /// Graine no longer knows the App Attest key: the next proof makes a new one.
  Future<void> forgetProofKey() async {
    try {
      await _channel.invokeMethod<void>('forgetProofKey');
    } catch (_) {
      // Nothing to let go of on this platform.
    }
  }
}

/// One answer from the app-verify routes: its body, or why it was refused.
typedef _VerifyAnswer = ({Map<String, Object?> data, EmbedRefusal? refusal});

/// YOUR APP AND YOUR USERS, FOR ONE AGENT (APP-IDENTITY.md): its verdicts
/// ([GraineInApp.verification]), the app pass it holds for its publishable
/// key (kept on the device), the user pass for the current identity (in
/// memory only), and the proof — in the background after the session, again
/// when less than six hours of the pass remain, on a ring, and before a
/// conversation under "enforce".
class _Verifier {
  _Verifier(this._g);

  final GraineInApp _g;
  final ValueNotifier<GraineVerification> state = ValueNotifier<GraineVerification>(GraineVerification.off);

  IssuedPass? _appPass;
  Future<void>? _appPassLoad;
  IssuedPass? _userPass;
  Future<GraineAppVerdict>? _proving;
  Timer? _backoff;
  int _backoffStep = 0;
  bool _waitingForForeground = false;
  bool _disposed = false;

  /// This device or build cannot prove itself (no App Attest, no Play Integrity in the app): not asked again.
  bool _unsupported = false;

  _Agents get _group => _g._group;
  int _now() => _g._clock();

  /// Development mode is on for this agent: its requests carry the debug
  /// token, and it never runs App Attest or Play Integrity.
  bool get usesDebugToken => AppIdentity.usesDebugToken(_g.config.debugTokenMode, debugBuild: _group.debugBuild);

  /// What development mode exposes: the token while in use, null otherwise.
  String? get debugToken => usesDebugToken ? _group.platform.debugTokenNow : null;

  void _set(GraineVerification next) {
    if (!_disposed && next != state.value) state.value = next;
  }

  void dispose() {
    _disposed = true;
    _cancelBackoff();
  }

  // ── the declaration, on every request ───────────────────────────────────

  /// `{'app': {…}}` for one request body (§1.1) — the declaration, the app
  /// pass held while unexpired, and in development mode the debug token — or
  /// nothing at all when the platform could not say which app this is. [pass]
  /// is sent instead of the one held, expired or not (the outage grace).
  Future<Map<String, Object?>> appEntry({IssuedPass? pass}) async {
    final facts = await _group.platform.declaration();
    if (facts == null) return const <String, Object?>{};
    await _loadAppPass();
    final held = pass ?? _appPass;
    final debug = usesDebugToken ? await _group.platform.debugToken(_g._device) : null;
    return <String, Object?>{
      'app': <String, Object?>{
        ...facts,
        if (held != null && (pass != null || held.liveAt(_now()))) 'pass': held.pass,
        if (debug != null) 'debugToken': debug,
      },
    };
  }

  // ── the identity token and the user pass ────────────────────────────────

  /// The identity token to send with [value]: the app's, only when it was
  /// given for that same value (§1.3).
  String? tokenFor(String? value) {
    final token = _group.identityToken;
    final s = _g.session;
    if (value == null || token == null || s == null) return null;
    return Identity.pick(_group.tokenTraits, s.identitySetting.field) == value ? token : null;
  }

  /// The user pass to send with [value]: the one Graine issued for that value, while unexpired.
  String? userPassFor(String? value) {
    final p = _userPass;
    return value == null || p == null || p.value != value || !p.liveAt(_now()) ? null : p.pass;
  }

  /// The identity changed: its pass is not the next one's.
  void dropUserPass() => _userPass = null;

  /// The identity or its token changed: nothing is proven about it yet.
  void resetUser() {
    final s = _g.session;
    if (s == null) return;
    if (s.securitySetting.userVerify == GraineVerifyMode.off) {
      _set(state.value.withUser(GraineUserVerdict.off));
      return;
    }
    final token = tokenFor(_g._identityValueFor(_g._traits));
    _set(state.value.withUser(GraineUserVerdict.unverified, token == null ? 'missing' : null));
  }

  // ── what the server answers ─────────────────────────────────────────────

  /// AN ANSWER'S `verification` (§2.2), from a ticket or app-verify: the
  /// verdicts, the passes it carries — the user pass for [value], the value
  /// that was sent — and, for a token that expired, a refresh in the background.
  void noteVerification(Object? verification, {String? value}) {
    final v = Js.asMap(verification);
    if (v == null) return;
    final now = _now();
    final appPass = IssuedPass.fromVerification(v, app: true, nowMs: now);
    if (appPass != null) unawaited(_keepAppPass(appPass));
    final userPass = value == null ? null : IssuedPass.fromVerification(v, app: false, nowMs: now, value: value);
    if (userPass != null) _userPass = userPass;
    _set(state.value.merge(v));
    if (v['user'] == GraineUserVerdict.invalid.wire && v['userReason'] == 'expired') {
      unawaited(_g._refreshIdentityToken());
    }
  }

  /// WHAT THE NATIVE CALL ENGINE WAS TOLD (the calls plugin's `verification`
  /// event: Graine's verdicts on the engine's own requests — a call's ticket,
  /// its credential). Folded in only when it proves more than this client
  /// knows: an app verdict that proves the app, while the agent checks apps and
  /// this client's own does not; a user verdict that proves the user, while the
  /// agent checks users, this client's own does not, and the engine was
  /// speaking for exactly the traits identified here now — a late word about
  /// the user before is not this one's. Never less: an unproven native verdict
  /// changes nothing, and nothing is taken before the session says what the
  /// agent checks.
  void noteNative(Map<Object?, Object?> event) {
    final s = _g.session;
    if (s == null || _disposed) return;
    final security = s.securitySetting;
    var next = state.value;
    final app = _named(GraineAppVerdict.values, event['app']);
    if (security.appVerify != GraineVerifyMode.off && app != null && _provesApp(app) && !_provesApp(next.app)) {
      next = next.withApp(app);
    }
    final user = _named(GraineUserVerdict.values, event['user']);
    final traits = _g._traits;
    if (security.userVerify != GraineVerifyMode.off &&
        user != null &&
        _provesUser(user) &&
        !_provesUser(next.user) &&
        traits != null &&
        deepEquals(Protocol.toJson(traits), event['traits'])) {
      next = next.withUser(user);
    }
    _set(next);
  }

  static bool _provesApp(GraineAppVerdict v) =>
      v == GraineAppVerdict.verified || v == GraineAppVerdict.testBuild || v == GraineAppVerdict.debugToken;

  static bool _provesUser(GraineUserVerdict v) => v == GraineUserVerdict.verified || v == GraineUserVerdict.testUser;

  /// The verdict a native event names by the word every SDK uses (`testBuild`, `testUser`…); null for another.
  static T? _named<T extends Enum>(List<T> values, Object? word) {
    for (final v in values) {
      if (v.name == word) return v;
    }
    return null;
  }

  /// A route refused this app or user: the verdict says so — and a pass
  /// Graine called expired or invalid is not sent again.
  void noteRefusal(EmbedRefusal r) {
    if (r.code == GraineErrorCode.appNotVerified) {
      _set(state.value.withApp(GraineAppVerdict.unverified, r.reason));
      if ((r.reason == 'expired' || r.reason == 'invalid') && _appPass != null) unawaited(_dropAppPass());
    } else if (r.code == GraineErrorCode.identityUnverified) {
      _set(state.value.withUser(GraineUserVerdict.unverified, state.value.userReason));
    }
  }

  /// The session arrived: the verdicts start from what it says, and the app
  /// proves itself in the background when the agent asks for it (§2.1).
  Future<void> sessionArrived(SessionConfig s) async {
    await _loadAppPass();
    if (_disposed) return;
    final security = s.securitySetting;
    if (security.appVerify == GraineVerifyMode.off) {
      _set(state.value.withApp(GraineAppVerdict.off));
    } else if (state.value.app == GraineAppVerdict.off) {
      final held = _appPass;
      if (await _group.platform.declaration() == null) {
        // Which app this is cannot be said here (no platform side): nothing to send, nothing to prove.
        _set(state.value.withApp(GraineAppVerdict.unverified, 'unsupported'));
      } else {
        _set(state.value.withApp(!usesDebugToken && held != null && held.liveAt(_now())
            ? held.appVerdict
            // Development mode proves nothing: the first answer says whether the token is registered.
            : GraineAppVerdict.checking));
      }
    }
    if (state.value.user == GraineUserVerdict.off || security.userVerify == GraineVerifyMode.off) resetUser();
    if (security.appVerify != GraineVerifyMode.off && !usesDebugToken) unawaited(prove());
  }

  // ── the app pass ────────────────────────────────────────────────────────

  Future<void> _loadAppPass() => _appPassLoad ??= () async {
        final prefs = await _g._device.prefs();
        final kept =
            IssuedPass.fromJson(Js.asMap(prefs['appPasses'])?[AppIdentity.passKey(_g.config.publishableKey)]);
        // An expired one is kept for the outage grace — no longer than that.
        if (kept != null && _now() - kept.expiresAtMs < AppIdentity.outageGraceMs) _appPass ??= kept;
      }();

  /// The newest app pass, kept on the device for this publishable key — under a fingerprint of it.
  Future<void> _keepAppPass(IssuedPass pass) async {
    _appPass = pass;
    final key = AppIdentity.passKey(_g.config.publishableKey);
    final now = _now();
    await _g._device.updatePrefs((Map<String, Object?> p) {
      final passes = Js.asMap(p['appPasses']) ?? <String, Object?>{};
      passes.remove(key);
      passes.removeWhere((String _, Object? v) {
        final kept = IssuedPass.fromJson(v);
        return kept == null || now - kept.expiresAtMs >= AppIdentity.outageGraceMs;
      });
      passes[key] = pass.toJson();
      while (passes.length > 8) {
        passes.remove(passes.keys.first);
      }
      p['appPasses'] = passes;
    });
  }

  /// The app pass Graine refused: neither sent nor kept any longer.
  Future<void> _dropAppPass() async {
    _appPass = null;
    final key = AppIdentity.passKey(_g.config.publishableKey);
    await _g._device.updatePrefs((Map<String, Object?> p) {
      final passes = Js.asMap(p['appPasses']);
      if (passes == null) return;
      passes.remove(key);
      p['appPasses'] = passes;
    });
  }

  // ── the proof ───────────────────────────────────────────────────────────

  /// PROVE THE APP (§3) — one proof at a time; a caller during one shares it.
  /// Nothing to do with the check off, in development mode, or with a pass
  /// that has six hours or more left ([ignorePass]: prove anyway — a route
  /// refused it). While backing off after an outage it waits its turn
  /// ([ignoreBackoff]: now).
  Future<GraineAppVerdict> prove({bool ignorePass = false, bool ignoreBackoff = false}) {
    final running = _proving;
    if (running != null) return running;
    final run = _prove(ignorePass: ignorePass, ignoreBackoff: ignoreBackoff);
    _proving = run;
    unawaited(run.whenComplete(() {
      if (identical(_proving, run)) _proving = null;
    }));
    return run;
  }

  Future<GraineAppVerdict> _prove({required bool ignorePass, required bool ignoreBackoff}) async {
    try {
      final s = await _g.loadSession();
      if (s == null || _disposed) return state.value.app;
      final security = s.securitySetting;
      if (security.appVerify == GraineVerifyMode.off) return GraineAppVerdict.off;
      if (usesDebugToken) return state.value.app;
      if (!ignoreBackoff && (_backoff != null || _waitingForForeground)) return state.value.app;
      if (ignoreBackoff) {
        _cancelBackoff();
        _waitingForForeground = false;
      }
      if (_unsupported || await _group.platform.declaration() == null) return _unverified('unsupported');
      await _loadAppPass();
      final held = _appPass;
      if (!ignorePass && held != null && held.leftMs(_now()) >= AppIdentity.appPassRefreshBelowMs) {
        _set(state.value.withApp(held.appVerdict));
        return held.appVerdict;
      }
      if (held == null || !held.liveAt(_now())) _set(state.value.withApp(GraineAppVerdict.checking));
      return await _attempt(security);
    } catch (e) {
      if (_g.config.debug) debugPrint('[Graine] app verification: $e');
      return state.value.app;
    }
  }

  /// Challenge → the platform's proof → app-verify (§3.1, §3.2), with the one
  /// retry each answer allows: a stale challenge, an App Attest key Graine
  /// no longer knows.
  Future<GraineAppVerdict> _attempt(SecuritySetting security) async {
    var challengeAgain = true;
    var keyAgain = true;
    while (true) {
      final asked = await _verifyPost(_Routes.appVerifyChallenge, const <String, Object?>{});
      if (asked.refusal != null) return _notProven(asked.refusal!);
      final challenge = asked.data['challenge'];
      if (challenge is! String || !AppIdentity.isChallenge(challenge)) return _unverified('invalid');
      final proof = await _group.platform.prove(challenge, cloudProjectNumber: security.cloudProjectNumber);
      switch (proof['error']) {
        case null:
          break;
        case 'backoff':
          // The device could not reach Apple or Google.
          return _outage();
        case 'unsupported':
        case 'missing_dependency':
          _unsupported = true;
          return _unverified('unsupported');
        default:
          if (_g.config.debug) debugPrint('[Graine] app verification: ${proof['message'] ?? proof['error']}');
          return _unverified('failed');
      }
      final answer = await _verifyPost(_Routes.appVerify, <String, Object?>{'challenge': challenge, 'proof': proof});
      final refusal = answer.refusal;
      if (refusal == null) return _proven(answer.data);
      if (refusal.code == GraineErrorCode.appNotVerified) {
        if (refusal.reason == 'challenge' && challengeAgain) {
          challengeAgain = false;
          continue;
        }
        if (refusal.reason == 'unknown_key' && keyAgain) {
          keyAgain = false;
          await _group.platform.forgetProofKey();
          continue;
        }
      }
      return _notProven(refusal);
    }
  }

  /// OUTAGE GRACE (§3.2): the device cannot reach Apple or Google. With a pass
  /// held — even an expired one — Graine is asked to vouch for it a little
  /// longer (`proof: {kind: "unavailable"}`, no challenge); either way the real
  /// proof is tried again later.
  Future<GraineAppVerdict> _outage() async {
    final held = _appPass;
    if (held != null) {
      final grace = await _verifyPost(_Routes.appVerify, const <String, Object?>{
        'proof': <String, Object?>{'kind': 'unavailable'},
      }, pass: held);
      final refusal = grace.refusal;
      if (refusal == null) {
        final verdict = _verdictOf(grace.data);
        _scheduleRetry();
        return verdict;
      }
      if (refusal.code == GraineErrorCode.appNotVerified) _unverified(refusal.reason ?? 'missing');
    } else {
      _unverified('unavailable');
    }
    _scheduleRetry();
    return state.value.app;
  }

  /// A proof Graine accepted: its verdict, the pass kept, the backoff over.
  GraineAppVerdict _proven(Map<String, Object?> data) {
    _backoffStep = 0;
    _waitingForForeground = false;
    _cancelBackoff();
    return _verdictOf(data);
  }

  GraineAppVerdict _verdictOf(Map<String, Object?> data) {
    final said = GraineAppVerdict.fromWire(Js.asMap(data['verification'])?['app']);
    final verdict = said ?? _appPass?.appVerdict ?? GraineAppVerdict.verified;
    _set(state.value.withApp(verdict));
    return verdict;
  }

  /// No proof this time. Graine refusing it is a verdict; Graine or the
  /// network not answering is not — the pass held keeps its verdict, and the
  /// proof is tried again later.
  GraineAppVerdict _notProven(EmbedRefusal r) {
    switch (r.code) {
      case GraineErrorCode.appNotVerified:
        return _unverified(r.reason ?? 'invalid');
      case GraineErrorCode.appNotAllowed:
        return _unverified('app_not_allowed');
      case GraineErrorCode.rateLimited:
        _scheduleRetry(afterSeconds: r.retryAfterSeconds);
      case GraineErrorCode.unavailable || GraineErrorCode.network || GraineErrorCode.unknown:
        _scheduleRetry();
      default:
        return _unverified(r.codeName ?? r.code.wire);
    }
    final held = _appPass;
    if (held == null || !held.liveAt(_now())) _unverified('unavailable');
    return state.value.app;
  }

  GraineAppVerdict _unverified(String reason) {
    _set(state.value.withApp(GraineAppVerdict.unverified, reason));
    return GraineAppVerdict.unverified;
  }

  /// One request to an app-verify route: the key, the install, the declaration — and [extra].
  Future<_VerifyAnswer> _verifyPost(String path, Map<String, Object?> extra, {IssuedPass? pass}) async {
    final body = <String, Object?>{
      'publishableKey': _g.config.publishableKey,
      'installId': await _g._device.installId(),
      ...await appEntry(pass: pass),
      ...extra,
    };
    final http.Response res;
    try {
      res = await _g._http
          .post(_g._embedUrl(path), headers: GraineInApp._json, body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      return (
        data: const <String, Object?>{},
        refusal: EmbedRefusal('Could not reach Graine: $e', code: GraineErrorCode.network),
      );
    }
    Map<String, Object?> data;
    try {
      data = Js.asMap(jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true))) ?? <String, Object?>{};
    } catch (_) {
      data = <String, Object?>{};
    }
    final refusal = EmbedRefusal.of(res.statusCode, data, retryAfter: res.headers['retry-after']);
    if (refusal == null) noteVerification(data['verification']);
    return (data: data, refusal: refusal);
  }

  // ── when to prove ───────────────────────────────────────────────────────

  /// 30 s, 2 min, 10 min — then the next time the app comes to the foreground.
  void _scheduleRetry({int? afterSeconds}) {
    _cancelBackoff();
    if (_disposed) return;
    final int delay;
    if (afterSeconds != null && afterSeconds > 0) {
      delay = math.min(afterSeconds, 3600) * 1000;
    } else if (_backoffStep < AppIdentity.backoffMs.length) {
      delay = AppIdentity.backoffMs[_backoffStep++];
    } else {
      _waitingForForeground = true;
      return;
    }
    _backoff = Timer(Duration(milliseconds: delay), () {
      _backoff = null;
      unawaited(prove());
    });
  }

  void _cancelBackoff() {
    _backoff?.cancel();
    _backoff = null;
  }

  /// Whether the app pass is missing, or has less than six hours left.
  bool get _passDue {
    final held = _appPass;
    return held == null || held.leftMs(_now()) < AppIdentity.appPassRefreshBelowMs;
  }

  bool get _checksApp {
    final s = _g.session;
    return s != null && s.securitySetting.appVerify != GraineVerifyMode.off && !usesDebugToken;
  }

  /// Back in the foreground: a pass running low is refreshed, and a proof
  /// that waited for the foreground runs.
  void foreground() {
    if (!_checksApp || _backoff != null) return;
    if (_waitingForForeground || _passDue) {
      _waitingForForeground = false;
      _backoffStep = 0;
      unawaited(prove(ignoreBackoff: true));
    }
  }

  /// A ring arrived (§6): before the person answers, the proof is refreshed
  /// when it runs low and the app is asked for a fresh identity token, both in
  /// the background.
  void ring() {
    if (_checksApp && _passDue) unawaited(prove(ignoreBackoff: true));
    if (_group.refresher != null) unawaited(_g._refreshIdentityToken());
  }

  /// BEFORE A CONVERSATION STARTS (a ticket, §1.3 and §2.1): a JWT about to
  /// expire is refreshed, and under "enforce" with no unexpired pass the proof
  /// in flight — or one started now — is waited for. Each wait at most 10 s;
  /// then the request goes anyway.
  Future<void> beforeConversation() async {
    final token = _group.identityToken;
    if (token != null && AppIdentity.jwtNeedsRefresh(token, _now())) {
      await _g
          ._refreshIdentityToken()
          .timeout(const Duration(milliseconds: AppIdentity.waitMs), onTimeout: () => false);
    }
    final s = _g.session;
    if (s == null || s.securitySetting.appVerify != GraineVerifyMode.enforce || usesDebugToken) return;
    await _loadAppPass();
    final held = _appPass;
    if (held != null && held.liveAt(_now())) return;
    await prove().timeout(const Duration(milliseconds: AppIdentity.waitMs), onTimeout: () => state.value.app);
  }

  /// Whether a refusal for want of a proof can be answered by proving.
  Future<bool> canProve() async =>
      !usesDebugToken && !_unsupported && await _group.platform.declaration() != null;

  /// The unexpired app pass held now, or null.
  String? get livePass {
    final held = _appPass;
    return held != null && held.liveAt(_now()) ? held.pass : null;
  }
}
