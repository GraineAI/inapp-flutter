/// WHAT THE AGENT REMEMBERS about the signed-in user, as they may read it —
/// already redacted by Graine. Read leniently, like every answer.
library;

import 'js.dart';
import 'scheduling.dart';

/// One thing the agent remembers.
class GraineMemory {
  const GraineMemory({required this.id, required this.text, this.createdAt, this.updatedAt});

  final String id;

  /// What is remembered, in a sentence.
  final String text;

  /// When it was first remembered, in UTC; null when the server does not say.
  final DateTime? createdAt;

  /// When it last changed, in UTC; null when the server does not say.
  final DateTime? updatedAt;

  /// Null for anything that is not a memory with an id and some words.
  static GraineMemory? fromJson(Object? raw) {
    final r = Js.asMap(raw);
    if (r == null) return null;
    final id = r['id'];
    final text = r['text'];
    if (id is! String || id.trim().isEmpty || text is! String || text.trim().isEmpty) return null;
    return GraineMemory(
      id: id.trim(),
      text: text,
      createdAt: ScheduledCalls.parseTime(Js.firstDefined(<Object?>[r['createdAt'], r['created_at']])),
      updatedAt: ScheduledCalls.parseTime(Js.firstDefined(<Object?>[r['updatedAt'], r['updated_at']])),
    );
  }

  /// `{memories: [...]}` (or a bare list), in the server's order — newest
  /// first. Entries that are not memories are skipped.
  static List<GraineMemory> listFrom(Object? body) {
    final m = Js.asMap(body);
    return <GraineMemory>[
      for (final x in Js.asList(m == null ? body : m['memories']))
        if (fromJson(x) case final GraineMemory memory) memory,
    ];
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'text': text,
        'createdAt': createdAt?.toUtc().toIso8601String(),
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      other is GraineMemory &&
      other.id == id &&
      other.text == text &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, text, createdAt, updatedAt);

  @override
  String toString() => 'GraineMemory($id)';
}
