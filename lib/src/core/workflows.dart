/// WORKFLOWS THE APP STARTS (0.14.4) — `GraineInApp.startWorkflow`, every
/// SDK's rule (sdk/contract/PUBLIC-STATE.md §7): what is checked on the
/// device, what of the app's data is sent, and how the answer is read. Pure,
/// so plain tests hold it.
///
/// The run is for the identified user, never for anyone the app names: who
/// the run is for never leaves the device in `data`. What could never be kept
/// is left out before anything is sent — a list, a map, null, a text over 200
/// characters, a name no workflow can allow, `user_id` / `user_field` /
/// `reference_id`, a `graine_` name — and the first 12 of the rest go, in the
/// map's order. Left out, never refused.
library;

import 'dart:math';

import 'js.dart';

/// A run `startWorkflow` started — or the one the user already had under way
/// ([alreadyRunning]: that run, never a second).
class GraineWorkflowRun {
  const GraineWorkflowRun({required this.runId, this.workflowId, this.alreadyRunning = false});

  /// The run's id (`oex_…`).
  final String runId;

  /// The workflow's id (`owf_…`); null when the answer did not say.
  final String? workflowId;

  /// True when the user already had a run of this workflow under way.
  final bool alreadyRunning;

  @override
  bool operator ==(Object other) =>
      other is GraineWorkflowRun &&
      other.runId == runId &&
      other.workflowId == workflowId &&
      other.alreadyRunning == alreadyRunning;

  @override
  int get hashCode => Object.hash(runId, workflowId, alreadyRunning);

  @override
  String toString() => 'GraineWorkflowRun($runId, $workflowId, alreadyRunning: $alreadyRunning)';
}

/// The rules (internal: the library hides it).
abstract final class Workflows {
  static const int nameMax = 120;
  static const int fieldsMax = 12;
  static const int valueMax = 200;

  /// After a request that got no answer, the one more ask (the same key) waits this long.
  static const Duration retryDelay = Duration(seconds: 1);
  static const String keyMessage = 'idempotencyKey is 8 to 128 letters, digits, _ - . or :.';
  static const String nameMessage = "Pass the workflow's exact name or its id (at most $nameMax characters).";

  /// Never sent: who the run is for, the engine's `fields`, and where a step sends by default.
  static const Set<String> _reserved = <String>{'user_id', 'user_field', 'reference_id', 'fields', 'mobile_number', 'email'};
  static final RegExp _fieldName = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
  static final RegExp _key = RegExp(r'^[A-Za-z0-9_.:-]{8,128}$');

  /// The workflow's name or id as sent — trimmed — or null when empty or over 120 characters.
  static String? name(String raw) {
    final name = raw.trim();
    return name.isEmpty || name.length > nameMax ? null : name;
  }

  static bool isIdempotencyKey(String value) => _key.hasMatch(value);

  /// A fresh key for one call: a UUIDv4, lowercase.
  static String newKey([Random? random]) {
    final r = random ?? _random;
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final hex = b.map((int x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static final Random _random = _secureOrNot();

  static Random _secureOrNot() {
    try {
      return Random.secure();
    } catch (_) {
      return Random();
    }
  }

  /// The fields sent: what could be kept, the first 12 in the map's order.
  static Map<String, Object> data(Map<String, Object?> data) {
    final out = <String, Object>{};
    for (final entry in data.entries) {
      if (out.length >= fieldsMax) break;
      final name = entry.key;
      if (!_fieldName.hasMatch(name) || _reserved.contains(name) || name.toLowerCase().startsWith('graine_')) continue;
      final value = entry.value;
      if (value is String) {
        // Code points, as Graine counts them: an emoji is one.
        if (value.runes.length > valueMax) continue;
        out[name] = value;
      } else if (value is bool) {
        out[name] = value;
      } else if (value is num) {
        if (!value.isFinite) continue;
        out[name] = value;
      }
    }
    return out;
  }

  /// The run in the answer — `{runId, workflowId, alreadyRunning}` — or null without a run id.
  static GraineWorkflowRun? runFrom(Map<String, Object?> body) {
    String? text(Object? v) => v is String && v.isNotEmpty ? v : null;
    final runId = text(body['runId']) ?? text(body['run_id']);
    if (runId == null) return null;
    return GraineWorkflowRun(
      runId: runId,
      workflowId: text(body['workflowId']) ?? text(body['workflow_id']),
      alreadyRunning: Js.firstDefined(<Object?>[body['alreadyRunning'], body['already_running']]) == true,
    );
  }
}
