part of 'graine.dart';

/// THE DEVICE, AS THE PLUGIN'S PLATFORM SIDE REPORTS IT — over the
/// `ai.graine.inapp/device` channel:
///
///   `installId` → String     the install id the native SDK keeps (iOS
///                            Keychain, Android no-backup storage) — the SAME
///                            id the native call engine sends
///   `timezone`  → String     the IANA zone the device is set to
///   `readPrefs` → String?    this package's own few bytes of preferences (JSON)
///   `writePrefs` String      … written back
///
/// Where there is no platform side (a test, a desktop build) the install id
/// is a UUIDv4 kept in memory for this process, the zone is unknown, and the
/// preferences live in memory.
class _Device {
  _Device(this._channel);

  final MethodChannel _channel;
  Future<String>? _installId;
  String? _installIdNow;
  Future<Map<String, Object?>>? _prefs;
  Map<String, Object?>? _prefsNow;
  String? _timezoneNow;
  bool _warned = false;

  /// The install id, read once per process.
  Future<String> installId() => _installId ??= _readInstallId();

  /// The install id if it has been read already — for a message that must
  /// not wait.
  String? get installIdNow => _installIdNow;

  Future<String> _readInstallId() async {
    String? id;
    try {
      id = Identity.normaliseInstallId(await _channel.invokeMethod<String>('installId'));
    } catch (e) {
      _quiet('the install id is kept in memory for this run ($e)');
    }
    id ??= Identity.uuidV4();
    _installIdNow = id;
    return id;
  }

  /// The device's IANA zone, read each time (people travel); null when unknown.
  Future<String?> timezone() async {
    try {
      _timezoneNow = Identity.normaliseTimezone(await _channel.invokeMethod<String>('timezone'));
    } catch (_) {
      // No platform side: unknown, and the server uses the agent's own zone.
    }
    return _timezoneNow;
  }

  /// The zone as last read.
  String? get timezoneNow => _timezoneNow;

  /// This package's preferences, read once.
  Future<Map<String, Object?>> prefs() => _prefs ??= _readPrefs();

  /// The preferences if they have been read already.
  Map<String, Object?>? get prefsNow => _prefsNow;

  Future<Map<String, Object?>> _readPrefs() async {
    var p = <String, Object?>{};
    try {
      final raw = await _channel.invokeMethod<String>('readPrefs');
      if (raw != null && raw.isNotEmpty) p = Js.asMap(jsonDecode(raw)) ?? <String, Object?>{};
    } catch (_) {
      // Unreadable or no platform side: start empty.
    }
    return _prefsNow = p;
  }

  /// Change the preferences and write them back (best effort).
  Future<void> updatePrefs(void Function(Map<String, Object?> prefs) change) async {
    final p = await prefs();
    change(p);
    try {
      await _channel.invokeMethod<void>('writePrefs', jsonEncode(p));
    } catch (e) {
      _quiet('preferences are kept in memory for this run ($e)');
    }
  }

  void _quiet(String message) {
    if (_warned) return;
    _warned = true;
    debugPrint('[Graine] $message');
  }

  /// THE MEMORY CHOICES, in the preferences: fingerprint of (install, user)
  /// → on or off. The newest [_memoryCap] are kept.
  static const int _memoryCap = 50;

  /// The choice kept under [key], from preferences already read; null when
  /// there is none (or they have not been read).
  bool? memoryChoiceNow(String key) {
    final v = Js.asMap(_prefsNow?['memory'])?[key];
    return v is bool ? v : null;
  }

  Future<void> rememberMemory(String key, bool enabled) => updatePrefs((Map<String, Object?> p) {
        final m = Js.asMap(p['memory']) ?? <String, Object?>{};
        m.remove(key); // re-inserted last: the newest
        m[key] = enabled;
        while (m.length > _memoryCap) {
          m.remove(m.keys.first);
        }
        p['memory'] = m;
      });
}
