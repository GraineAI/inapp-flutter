/// WHO THE USER IS — the device's half of the in-app identity contract
/// (sdk/contract/inapp-platform-contract.md, §1).
///
/// The platform decides who a user is: the agent's Identity setting names
/// one trait (`user_id` by default, or `email`, `phone`, or a custom one such
/// as `patient_id`), and the RAW value of that trait is the identity. It
/// travels only in the identity channel — the ticket and the SDK requests
/// that need it — and never as a prompt variable or in `context.user`. The servers derive the key; the device never
/// does, so nothing here hashes a person.
library;

import 'dart:math' as math;

import 'js.dart';
import 'sha256.dart';

/// The agent's identity setting, as the session serves it.
class IdentitySetting {
  const IdentitySetting({this.field = Identity.defaultField, this.devicesPerUser = 2});

  /// Which trait identifies a user: `user_id`, `email`, `phone` or a custom name.
  final String field;

  /// How many devices one user may hold at a time (1–5).
  final int devicesPerUser;

  /// What an older server, which says nothing, means: the `user_id` trait.
  static const IdentitySetting standard = IdentitySetting();

  /// Null when [raw] is not an object — the server did not say.
  static IdentitySetting? fromJson(Object? raw) {
    final r = Js.asMap(raw);
    if (r == null) return null;
    final devices = Js.finite(r['devicesPerUser']);
    return IdentitySetting(
      field: Identity.normaliseField(r['field']) ?? Identity.defaultField,
      devicesPerUser: devices == null ? 2 : devices.round().clamp(1, 5),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is IdentitySetting && other.field == field && other.devicesPerUser == devicesPerUser;

  @override
  int get hashCode => Object.hash(field, devicesPerUser);
}

/// The rules every SDK applies on the device before an identity leaves it.
abstract final class Identity {
  static const String defaultField = 'user_id';

  /// Values that identify nobody (§1.4 `PLACEHOLDERS`), compared without
  /// regard to case after trimming. A masked value is one of them: an app
  /// that hands over an already-masked email has handed over no one.
  static const Set<String> placeholders = <String>{
    '', 'null', 'undefined', 'none', 'nil', 'nan', 'unknown', 'anonymous', 'anon', 'guest', '0', '-', 'n/a',
    'na', 'test', '[phone]', '[email]', '[pan]', '[aadhaar]', '[card]',
  };

  /// Longer than any identifier the servers key (a user id or custom trait is
  /// at most 256 characters): such a value is never sent.
  static const int maxValueLength = 256;

  static final RegExp _field = RegExp(r'^[a-z][a-z0-9_]{0,39}$');
  static final RegExp _install = RegExp(r'^[0-9a-f-]{16,64}$');
  static final RegExp _zone = RegExp(r'^[A-Za-z][A-Za-z0-9_+\-]*(?:/[A-Za-z0-9_+\-]+){0,3}$');

  /// A trait name as the setting stores it: trimmed, lower case, and
  /// `^[a-z][a-z0-9_]{0,39}$` — else null.
  static String? normaliseField(Object? field) {
    if (field is! String) return null;
    final f = serverTrim(field).toLowerCase();
    return _field.hasMatch(f) ? f : null;
  }

  /// ONE TRAIT AS THE IDENTITY CHANNEL CARRIES IT — raw — or null when it
  /// cannot identify anyone: null, a boolean, a fraction, an object or a list,
  /// a placeholder, or a value longer than [maxValueLength]. An integer is its
  /// decimal string. Nothing else is changed: the servers normalise.
  static String? valueOf(Object? v) {
    final String s;
    if (v is String) {
      s = v;
    } else if (v is int) {
      s = v.toString();
    } else {
      return null; // null, bool, double, Map, List, anything else
    }
    if (s.length > maxValueLength) return null;
    if (placeholders.contains(serverTrim(s).toLowerCase())) return null;
    return s;
  }

  /// The identity in [traits] for the setting's [field]: the trait under
  /// exactly that name, else one whose name normalises to it (`Patient_ID`
  /// for `patient_id`). Null when there is none, or it identifies nobody.
  static String? pick(Map<String, Object?>? traits, String field) {
    if (traits == null) return null;
    if (traits.containsKey(field)) return valueOf(traits[field]);
    for (final e in traits.entries) {
      if (normaliseField(e.key) == field) return valueOf(e.value);
    }
    return null;
  }

  /// An install id this SDK will send: lower case, `^[0-9a-f-]{16,64}$`.
  /// Null for anything else.
  static String? normaliseInstallId(Object? id) {
    if (id is! String) return null;
    final i = id.trim().toLowerCase();
    return _install.hasMatch(i) ? i : null;
  }

  /// An IANA zone name the servers can use (`Asia/Kolkata`, `UTC`), or null.
  static String? normaliseTimezone(Object? zone) {
    if (zone is! String) return null;
    final z = zone.trim();
    return z.length <= 64 && _zone.hasMatch(z) ? z : null;
  }

  /// A random UUIDv4, lower case — the install id of a process the platform
  /// cannot give one to (a test, a desktop build). Kept in memory only.
  static String uuidV4([math.Random? random]) {
    final r = random ?? math.Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final hex = <String>[for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  /// ASCII digits only, as the server counts them: other scripts' digits do not make a phone number.
  static final RegExp _notDigit = RegExp(r'[^0-9]');

  /// What the server trims (Python's `str.strip()`, contract §1.4) — not Dart's `trim()`: it KEEPS U+FEFF,
  /// which `trim()` strips, and strips U+001C–U+001F. Pinned by identity-vectors.json.
  static bool _isServerSpace(int c) =>
      (c >= 0x09 && c <= 0x0D) || (c >= 0x1C && c <= 0x20) || c == 0x85 || c == 0xA0 || c == 0x1680 ||
      (c >= 0x2000 && c <= 0x200A) || c == 0x2028 || c == 0x2029 || c == 0x202F || c == 0x205F || c == 0x3000;

  static bool _isCaseIgnorable(int c) =>
      c == 0x27 || c == 0x2E || c == 0x3A || c == 0x5E || c == 0x60 || c == 0xA8 || c == 0xAD || c == 0xAF ||
      c == 0xB4 || c == 0xB7 || c == 0xB8 || c == 0x2019 || (c >= 0x300 && c <= 0x36F);

  static bool _isCased(int c) {
    final ch = String.fromCharCode(c);
    return ch.toLowerCase() != ch.toUpperCase();
  }

  /// Python's `str.lower()` (contract §1.4): the full mapping of U+0130 ("İ" → "i̇") and the context-sensitive
  /// final sigma ("ΟΔΟΣ" → "οδος"), which Dart's `toLowerCase()` does not apply.
  static String serverLowercase(String s) {
    final r = s.runes.toList();
    final b = StringBuffer();
    for (var i = 0; i < r.length; i++) {
      final c = r[i];
      if (c == 0x130) {
        b.write('i\u0307');
        continue;
      }
      if (c == 0x3A3) {
        var j = i - 1;
        while (j >= 0 && _isCaseIgnorable(r[j])) {
          j--;
        }
        final before = j >= 0 && _isCased(r[j]);
        var k = i + 1;
        while (k < r.length && _isCaseIgnorable(r[k])) {
          k++;
        }
        final after = k < r.length && _isCased(r[k]);
        b.write(before && !after ? '\u03C2' : '\u03C3');
        continue;
      }
      b.write(String.fromCharCode(c).toLowerCase());
    }
    return b.toString();
  }

  static String serverTrim(String s) {
    var start = 0, end = s.length;
    while (start < end && _isServerSpace(s.codeUnitAt(start))) {
      start++;
    }
    while (end > start && _isServerSpace(s.codeUnitAt(end - 1))) {
      end--;
    }
    return s.substring(start, end);
  }

  /// THE VALUE AS THE SERVERS NORMALISE IT (§1.4): trimmed; a placeholder is
  /// none; an email lower case and shaped like one, at most 254 characters; a
  /// phone's digits, 8 to 15 of them, the last ten kept; anything else at
  /// most 256 characters, exact. The SDK never sends this — only the raw
  /// value — but keys its users' memory choices by it, so "Asha@Example.com"
  /// and "asha@example.com" are one user's. (Unicode composition, which Dart
  /// has no table for, is the one step left to the servers.)
  static String? normaliseValue(String field, Object? value) {
    final raw = value is int ? value.toString() : (value is String ? value : null);
    if (raw == null) return null;
    final v = serverTrim(raw);
    if (placeholders.contains(v.toLowerCase())) return null;
    switch (field) {
      case 'email':
        final lower = serverLowercase(v);
        return lower.runes.length <= 254 && _email.hasMatch(lower) ? lower : null;
      case 'phone':
        final digits = v.replaceAll(_notDigit, '');
        final count = digits.runes.length;
        if (count < 8 || count > 15) return null;
        return String.fromCharCodes(digits.runes.skip(count > 10 ? count - 10 : 0));
      default:
        return v.runes.length <= 256 ? v : null;
    }
  }

  /// WHERE ONE USER'S MEMORY CHOICE IS KEPT on the device — the iOS SDK's
  /// fingerprint: the first 16 bytes of SHA-256 of
  /// `"graine:memory:v1\n" + field + "\n" + normalised value`, as hex. The
  /// preferences never hold the identifier itself.
  static String memoryKey(String field, String value) {
    final normalised = normaliseValue(field, value) ?? value;
    return Sha256.hex(Sha256.ofText('graine:memory:v1\n$field\n$normalised').sublist(0, 16));
  }

  /// [traits] without the trait that identifies the user — it travels only in
  /// the identity channel, never as a variable or as `context.user`. Null
  /// [field] (no session yet): as they are.
  static Map<String, Object?>? withoutIdentity(Map<String, Object?>? traits, String? field) {
    if (traits == null || field == null) return traits;
    return <String, Object?>{
      for (final e in traits.entries)
        if (e.key != field && normaliseField(e.key) != field) e.key: e.value,
    };
  }

  /// THE IDENTITY FIELDS OF ONE REQUEST (§1.3), in the order every SDK sends
  /// them: `identity: {value}` only when there is one; `installId` always;
  /// `memory`, `timezone` and `callId` when known.
  static Map<String, Object?> requestFields({
    String? value,
    required String installId,
    bool? memory,
    String? timezone,
    String? callId,
  }) =>
      <String, Object?>{
        if (value != null) 'identity': <String, Object?>{'value': value},
        'installId': installId,
        if (memory != null) 'memory': memory,
        if (timezone != null) 'timezone': timezone,
        if (callId != null) 'callId': callId,
      };
}
