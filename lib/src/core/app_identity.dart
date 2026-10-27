/// YOUR APP AND YOUR USERS (0.14.4) — the device's half of the contract
/// (sdk/contract/APP-IDENTITY.md): which app is asking (the declaration every
/// request carries), the identity token's rules, what the server answers
/// (`security` in the session, `verification` on tickets and proofs), the
/// passes it issues, and development mode's debug tokens.
///
/// Pure — no Flutter, no I/O, no platform: the plugin's native code only READS
/// (the bundle id and a Keychain access group, the package and its signing
/// certificates) and PROVES (App Attest, Play Integrity); every rule applied to
/// what it read lives here and is proven by plain tests against the contract's
/// own vectors (sdk/contract/app-identity.json).
library;

import 'dart:convert';
import 'dart:math' as math;

import 'js.dart';
import 'sha256.dart';

/// How one of an agent's two checks stands, as the session says it: off,
/// counted but never refused ([report]), or applied ([enforce]).
enum GraineVerifyMode {
  off('off'),
  report('report'),
  enforce('enforce');

  const GraineVerifyMode(this.wire);

  /// The word on the wire.
  final String wire;

  /// The session's word; anything else (an older server, a word this build
  /// does not know) is [off].
  static GraineVerifyMode fromWire(Object? s) {
    final w = s is String ? s.trim().toLowerCase() : '';
    for (final v in values) {
      if (v.wire == w) return v;
    }
    return off;
  }
}

/// THE AGENT'S TWO CHECKS, as the session serves them (`security`): "Require a
/// verified app" ([appVerify], with the Google Cloud project Play Integrity is
/// asked under) and "Require verified users" ([userVerify], with how the
/// identity tokens are made). Both are off until a person turns them on in the
/// dashboard (Agent → Embed & Widgets → Install).
class SecuritySetting {
  const SecuritySetting({
    this.appVerify = GraineVerifyMode.off,
    this.cloudProjectNumber,
    this.userVerify = GraineVerifyMode.off,
    this.userMethod,
  });

  /// Whether this app proves it is yours (App Attest on iOS, Play Integrity on Android).
  final GraineVerifyMode appVerify;

  /// The Google Cloud project number a Play Integrity request names, when the agent set one.
  final String? cloudProjectNumber;

  /// Whether the identity `GraineInApp.identify` sends must be proven by an identity token.
  final GraineVerifyMode userVerify;

  /// How identity tokens are made: `hmac` or `jwt`; null when not set.
  final String? userMethod;

  /// Nothing configured — what an older server, which says nothing, means.
  static const SecuritySetting none = SecuritySetting();

  static final RegExp _digits = RegExp(r'^\d{1,20}$');

  /// Null when [raw] is not an object.
  static SecuritySetting? fromJson(Object? raw) {
    final r = Js.asMap(raw);
    if (r == null) return null;
    final app = Js.asMap(r['app']) ?? const <String, Object?>{};
    final user = Js.asMap(r['user']) ?? const <String, Object?>{};
    final project = app['cloudProjectNumber'];
    final projectText = project is String ? project.trim() : (project is int ? '$project' : '');
    final method = user['method'];
    return SecuritySetting(
      appVerify: GraineVerifyMode.fromWire(app['verify']),
      cloudProjectNumber: _digits.hasMatch(projectText) ? projectText : null,
      userVerify: GraineVerifyMode.fromWire(user['verify']),
      userMethod: method is String && method.trim().isNotEmpty ? method.trim().toLowerCase() : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SecuritySetting &&
      other.appVerify == appVerify &&
      other.cloudProjectNumber == cloudProjectNumber &&
      other.userVerify == userVerify &&
      other.userMethod == userMethod;

  @override
  int get hashCode => Object.hash(appVerify, cloudProjectNumber, userVerify, userMethod);

  @override
  String toString() => 'SecuritySetting(app: ${appVerify.wire}, user: ${userVerify.wire})';
}

/// WHETHER GRAINE KNOWS THIS IS YOUR APP — [GraineVerification.app].
enum GraineAppVerdict {
  /// "Require a verified app" is off for this agent, or its session has not arrived.
  off('off'),

  /// A proof is on its way, or no answer has given a verdict yet.
  checking('checking'),

  /// Proven: App Attest on iOS, Play Integrity on Android.
  verified('verified'),

  /// A development build, accepted because the agent allows development builds.
  testBuild('test_build'),

  /// A debug token registered on the agent (development mode).
  debugToken('debug_token'),

  /// Not proven — [GraineVerification.appReason] says why.
  unverified('unverified');

  const GraineAppVerdict(this.wire);

  /// The word on the wire. [checking] is the SDK's own and never on it.
  final String wire;

  /// The server's word; null for anything else ([checking] included).
  static GraineAppVerdict? fromWire(Object? s) {
    if (s is! String) return null;
    final w = s.trim();
    for (final v in values) {
      if (v != checking && v.wire == w) return v;
    }
    return null;
  }
}

/// WHETHER GRAINE KNOWS WHO THE USER IS — [GraineVerification.user].
enum GraineUserVerdict {
  /// "Require verified users" is off for this agent, or its session has not arrived.
  off('off'),

  /// The identity token (or the pass it earned) proved the identity.
  verified('verified'),

  /// One of the agent's test users, from an install with a registered debug token.
  testUser('test_user'),

  /// No proof yet — [GraineVerification.userReason] says why (`missing`: no token).
  unverified('unverified'),

  /// The token did not prove the identity — [GraineVerification.userReason] says why.
  invalid('invalid');

  const GraineUserVerdict(this.wire);

  /// The word on the wire.
  final String wire;

  /// The server's word; null for anything else.
  static GraineUserVerdict? fromWire(Object? s) {
    if (s is! String) return null;
    final w = s.trim();
    for (final v in values) {
      if (v.wire == w) return v;
    }
    return null;
  }
}

/// THE AGENT'S VERDICTS ON THIS APP AND THIS USER — `GraineInApp.verification`:
/// `off` until a session says the agent checks, then what Graine last said.
class GraineVerification {
  const GraineVerification({
    this.app = GraineAppVerdict.off,
    this.appReason,
    this.user = GraineUserVerdict.off,
    this.userReason,
  });

  final GraineAppVerdict app;

  /// Why [app] is [GraineAppVerdict.unverified], when known: the server's
  /// word (`missing`, `expired`, `invalid`, `debug_token_unknown`,
  /// `debug_token_expired`, …) or the SDK's: `unsupported` (this device or
  /// build cannot prove itself — a simulator, no Play Integrity in the app),
  /// `unavailable` (Apple, Google or Graine could not be reached; tried again
  /// later) or `failed` (the platform's proof failed). Null otherwise.
  final String? appReason;

  final GraineUserVerdict user;

  /// Why [user] is [GraineUserVerdict.unverified] or [GraineUserVerdict.invalid],
  /// when known (`missing`, `expired`, `signature`, `mismatch`, …). Null otherwise.
  final String? userReason;

  /// Both checks off.
  static const GraineVerification off = GraineVerification();

  /// This, with the app's verdict [app] (a reason only beside `unverified`).
  GraineVerification withApp(GraineAppVerdict app, [String? reason]) => GraineVerification(
      app: app, appReason: app == GraineAppVerdict.unverified ? reason : null, user: user, userReason: userReason);

  /// This, with the user's verdict [user] (a reason only beside `unverified` or `invalid`).
  GraineVerification withUser(GraineUserVerdict user, [String? reason]) => GraineVerification(
      app: app,
      appReason: appReason,
      user: user,
      userReason: user == GraineUserVerdict.unverified || user == GraineUserVerdict.invalid ? reason : null);

  /// This after an answer's `verification` object (contract §2.2). A verdict
  /// word this build does not know reads as unverified — never as a stale
  /// verified; an answer that names no verdict changes nothing.
  GraineVerification merge(Object? verification) {
    final v = Js.asMap(verification);
    if (v == null) return this;
    var next = this;
    final app = v['app'];
    if (app is String && app.trim().isNotEmpty) {
      final verdict = GraineAppVerdict.fromWire(app) ?? GraineAppVerdict.unverified;
      next = next.withApp(verdict, _word(v['appReason']));
    }
    final user = v['user'];
    if (user is String && user.trim().isNotEmpty) {
      final verdict = GraineUserVerdict.fromWire(user) ?? GraineUserVerdict.unverified;
      next = next.withUser(verdict, _word(v['userReason']));
    }
    return next;
  }

  static String? _word(Object? s) => s is String && s.trim().isNotEmpty ? s.trim() : null;

  @override
  bool operator ==(Object other) =>
      other is GraineVerification &&
      other.app == app &&
      other.appReason == appReason &&
      other.user == user &&
      other.userReason == userReason;

  @override
  int get hashCode => Object.hash(app, appReason, user, userReason);

  @override
  String toString() => 'GraineVerification(app: ${app.name}${appReason == null ? '' : ' ($appReason)'}, '
      'user: ${user.name}${userReason == null ? '' : ' ($userReason)'})';
}

/// DEVELOPMENT MODE (contract §3.6) — whether this build sends a debug token
/// INSTEAD of proving itself with App Attest or Play Integrity, which a
/// simulator, an emulator, a sideloaded build or CI cannot pass.
enum GraineDebugTokenMode {
  /// A debug build (`kDebugMode`) creates a debug token once per install and
  /// sends it; a release build never creates, logs or sends one. The default.
  automatic,

  /// Every build sends one, a release build included — for an internal QA
  /// build. Never ship it to a store.
  always,

  /// No debug token, even in a debug build: the build proves itself like a
  /// release one.
  never,
}

/// A PASS THE SERVER ISSUED (contract §3.3): opaque — never parsed — with when
/// it stops being sent, the verdict an app pass vouches for, and the identity
/// value a user pass was issued for. Not exported.
class IssuedPass {
  const IssuedPass({required this.pass, required this.expiresAtMs, this.verdict, this.value});

  final String pass;

  /// When it expires, in milliseconds since the epoch.
  final int expiresAtMs;

  /// An app pass's verdict, as the wire says it (`verified`, `test_build`).
  final String? verdict;

  /// A user pass's identity value: it is sent with no other.
  final String? value;

  /// Unexpired at [nowMs].
  bool liveAt(int nowMs) => nowMs < expiresAtMs;

  /// How long it has left at [nowMs] (negative once expired).
  int leftMs(int nowMs) => expiresAtMs - nowMs;

  /// The app verdict it vouches for.
  GraineAppVerdict get appVerdict => GraineAppVerdict.fromWire(verdict) ?? GraineAppVerdict.verified;

  /// At most a week, whatever an answer says.
  static const int _maxTtlSeconds = 7 * 86400;

  /// An answer's pass (§2.2) — `appPass` with `appPassExpiresIn`, or
  /// `userPass` with `userPassExpiresIn` — or null when it carries none. A
  /// missing or unreadable lifetime is the contract's: 24 h for an app pass,
  /// 1 h for a user pass.
  static IssuedPass? fromVerification(Object? verification, {required bool app, required int nowMs, String? value}) {
    final v = Js.asMap(verification);
    if (v == null) return null;
    final p = v[app ? 'appPass' : 'userPass'];
    if (p is! String || p.isEmpty || p.length > AppIdentity.maxIdentityTokenLength) return null;
    final said = Js.finite(v[app ? 'appPassExpiresIn' : 'userPassExpiresIn']);
    final fallback = app ? AppIdentity.appPassSeconds : AppIdentity.userPassSeconds;
    final seconds = said == null || said <= 0 ? fallback : math.min(said, _maxTtlSeconds.toDouble());
    final verdict = app && v['app'] is String ? (v['app']! as String).trim() : null;
    return IssuedPass(
        pass: p, expiresAtMs: nowMs + (seconds * 1000).round(), verdict: verdict, value: app ? null : value);
  }

  /// As the device keeps an app pass.
  Map<String, Object?> toJson() =>
      <String, Object?>{'pass': pass, 'exp': expiresAtMs, if (verdict != null) 'verdict': verdict};

  /// A kept app pass, or null for anything else.
  static IssuedPass? fromJson(Object? raw) {
    final r = Js.asMap(raw);
    final p = r?['pass'];
    final exp = r?['exp'];
    if (p is! String || p.isEmpty || exp is! num || !exp.isFinite) return null;
    final verdict = r?['verdict'];
    return IssuedPass(pass: p, expiresAtMs: exp.toInt(), verdict: verdict is String ? verdict : null);
  }
}

/// The contract's rules for the app declaration, identity tokens, passes and
/// debug tokens — each held to sdk/contract/app-identity.json by the tests.
/// Not exported.
abstract final class AppIdentity {
  static const String ios = 'ios';
  static const String android = 'android';

  /// At most five signing-certificate digests in a declaration.
  static const int maxCerts = 5;

  /// An identity token is at most 4096 characters, as given.
  static const int maxIdentityTokenLength = 4096;

  /// An app pass lasts 24 hours unless its answer says otherwise.
  static const int appPassSeconds = 86400;

  /// A user pass lasts an hour unless its answer says otherwise.
  static const int userPassSeconds = 3600;

  /// The app pass is refreshed in the background once less than 6 hours remain.
  static const int appPassRefreshBelowMs = 21600 * 1000;

  /// An expired app pass is kept this long for the outage grace (§3.2).
  static const int outageGraceMs = 604800 * 1000;

  /// A JWT with less than this many seconds left is refreshed before a conversation starts.
  static const int jwtRefreshBelowSeconds = 60;

  /// The app's token refresher is called at most once in this many milliseconds.
  static const int refresherIntervalMs = 30 * 1000;

  /// The longest a request waits for the refresher, or for a proof in flight.
  static const int waitMs = 10 * 1000;

  /// After a proof Apple, Google or Graine could not answer: 30 s, 2 min,
  /// 10 min — then the next time the app comes to the foreground.
  static const List<int> backoffMs = <int>[30 * 1000, 2 * 60 * 1000, 10 * 60 * 1000];

  static final RegExp _teamId = RegExp(r'^[A-Z0-9]{10}$');
  static final RegExp _debugToken = RegExp(r'^gdt_[A-Za-z0-9_-]{32}$');
  static final RegExp _challenge = RegExp(r'^[A-Za-z0-9_-]{48}$');
  static final RegExp _segment = RegExp(r'^[A-Za-z0-9_-]+$');
  static final RegExp _signature = RegExp(r'^[A-Za-z0-9_-]*$');

  /// THE TEAM ID IN A KEYCHAIN ACCESS GROUP (§1.2): the part before the first
  /// ".", when it is ten capital letters and digits; null otherwise — never
  /// guessed.
  static String? teamFromAccessGroup(Object? accessGroup) {
    if (accessGroup is! String) return null;
    final dot = accessGroup.indexOf('.');
    if (dot <= 0) return null;
    final team = accessGroup.substring(0, dot);
    return _teamId.hasMatch(team) ? team : null;
  }

  /// One signing certificate's digest (§1.2): SHA-256 of its DER bytes,
  /// lower-case hex, no colons.
  static String certificateDigest(List<int> der) => Sha256.hex(Sha256.hash(der));

  /// The digests a declaration carries: one per certificate, de-duplicated, in
  /// order, at most [maxCerts].
  static List<String> certificateDigests(Iterable<Object?> certificates) {
    final out = <String>[];
    for (final c in certificates) {
      if (c is! List || c.isEmpty || c.any((Object? b) => b is! int)) continue;
      final digest = certificateDigest(c.cast<int>());
      if (!out.contains(digest)) out.add(digest);
      if (out.length == maxCerts) break;
    }
    return out;
  }

  /// THE APP DECLARATION (§1.1) from what the platform read — `{platform, id}`,
  /// with `team` on iOS (from the access group) and `certs` on Android (from
  /// the certificates' DER bytes) when they could be read — or null when the
  /// app's id could not be: the whole `app` object is then left out.
  static Map<String, Object?>? declaration(Object? read) {
    final r = Js.asMap(read);
    if (r == null) return null;
    final platform = r['platform'];
    final id = r['id'];
    if ((platform != ios && platform != android) || id is! String || id.trim().isEmpty) return null;
    final out = <String, Object?>{'platform': platform, 'id': id.trim()};
    if (platform == ios) {
      final team = teamFromAccessGroup(r['accessGroup']);
      if (team != null) out['team'] = team;
    } else {
      final certs = certificateDigests(Js.asList(r['certificates']));
      if (certs.isNotEmpty) out['certs'] = certs;
    }
    return out;
  }

  /// AN IDENTITY TOKEN AS THE SDK KEEPS IT (§1.3): a non-empty string of at
  /// most 4096 characters, exactly as given; null for anything else.
  static String? identityToken(Object? token) =>
      token is String && token.isNotEmpty && token.length <= maxIdentityTokenLength ? token : null;

  /// The `exp` of a JWT — three base64url segments — read WITHOUT verifying it,
  /// only to decide whether to ask the app for a fresh token. Null for a token
  /// that is not a JWT, or has no numeric `exp`.
  static int? jwtExpiry(String token) {
    final parts = token.split('.');
    if (parts.length != 3 ||
        !_segment.hasMatch(parts[0]) ||
        !_segment.hasMatch(parts[1]) ||
        !_signature.hasMatch(parts[2])) {
      return null;
    }
    try {
      final payload = Js.asMap(jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))));
      final exp = payload?['exp'];
      if (exp is num && exp.isFinite) return exp.floor();
    } catch (_) {
      // Not a JWT after all: nothing to decide on.
    }
    return null;
  }

  /// Whether to ask for a fresh token before a ticket or a call session: a JWT
  /// whose `exp` is less than [jwtRefreshBelowSeconds] away (or past) at [nowMs].
  static bool jwtNeedsRefresh(String token, int nowMs) {
    final exp = jwtExpiry(token);
    return exp != null && exp * 1000 - nowMs < jwtRefreshBelowSeconds * 1000;
  }

  /// A NEW DEBUG TOKEN (§1.1, §3.6): `gdt_` and 24 random bytes, base64url
  /// without padding — 32 characters.
  static String newDebugToken([math.Random? random]) {
    final r = random ?? math.Random.secure();
    return 'gdt_${base64Url.encode(List<int>.generate(24, (_) => r.nextInt(256))).replaceAll('=', '')}';
  }

  /// Whether [token] has a debug token's shape.
  static bool isDebugToken(Object? token) => token is String && _debugToken.hasMatch(token);

  /// Whether [challenge] has the shape the server's challenges have.
  static bool isChallenge(Object? challenge) => challenge is String && _challenge.hasMatch(challenge);

  /// Whether this build sends a debug token instead of proving itself.
  static bool usesDebugToken(GraineDebugTokenMode mode, {required bool debugBuild}) => switch (mode) {
        GraineDebugTokenMode.always => true,
        GraineDebugTokenMode.never => false,
        GraineDebugTokenMode.automatic => debugBuild,
      };

  /// The one line development mode logs per install (§3.6), exactly.
  static String debugTokenLine(String token) => 'Graine debug token for this install: $token — register it '
      'under Agent → Embed & Widgets → Install → Development → Debug tokens to use this build while '
      '"Require a verified app" is on.';

  /// Where one publishable key's app pass is kept: a fingerprint, never the key.
  static String passKey(String publishableKey) =>
      Sha256.hex(Sha256.ofText('graine:apppass:v1\n${publishableKey.trim()}').sublist(0, 16));
}
