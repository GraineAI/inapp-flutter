import 'config.dart';
import 'protocol.dart';

/// One caption line: who, what, and whether it is still being said.
class Caption {
  const Caption(this.role, this.text, {this.live = false});

  final Role role;
  final String text;

  /// Still being recognised or streamed — render it as provisional.
  final bool live;

  Caption settled() => Caption(role, text);

  @override
  bool operator ==(Object other) =>
      other is Caption && other.role == role && other.text == text && other.live == live;

  @override
  int get hashCode => Object.hash(role, text, live);

  @override
  String toString() => 'Caption(${role.name}, "$text"${live ? ', live' : ''})';
}

/// WHAT HAS BEEN SAID SO FAR, oldest first — folded the way the RN launcher
/// folds it.
///
/// The engine sends a turn many times as its words arrive (`live: true`,
/// fuller each time), then once settled. A live turn REPLACES the tail it
/// belongs to (same role, still live), so the log never fills with one
/// sentence growing a word at a time. An empty line is a full stop, not a
/// line: it settles the open turn of that role and is otherwise ignored.
abstract final class Captions {
  /// How many turns are kept. A caption box shows two or three.
  static const int history = 12;

  static List<Caption> fold(List<Caption> prev, Caption next, {int max = history}) {
    final tail = prev.isEmpty ? null : prev.last;
    if (next.text.isEmpty) {
      if (tail != null && tail.live && tail.role == next.role) {
        return <Caption>[...prev.sublist(0, prev.length - 1), tail.settled()];
      }
      return prev;
    }
    final continues = tail != null && tail.live && tail.role == next.role;
    final merged = continues
        ? <Caption>[...prev.sublist(0, prev.length - 1), next]
        : <Caption>[...prev, next];
    return merged.length > max ? merged.sublist(merged.length - max) : merged;
  }
}

/// THE BAR'S ONE WORD, in the Android SDK's order — the network gets named,
/// or the agent takes the blame for it. A customer whose agent goes quiet on
/// a train reads "listening" and concludes the agent is broken.
String agentBarStatus({
  required GraineConnectivity connectivity,
  required bool? online,
  required bool reconnecting,
  required bool connecting,
  required bool ready,
  required bool muted,
  required bool connected,
  required ConnectionQuality quality,
  required bool agentSpeaking,
  bool micDenied = false,
}) {
  if (connectivity == GraineConnectivity.failed) return "couldn't load · tap to retry";
  if (online == false) return 'no connection';
  if (reconnecting) return 'reconnecting…';
  if (connectivity == GraineConnectivity.retrying) return 'reconnecting…';
  if (connecting || !ready) return 'connecting…';
  if (micDenied && !connected) return 'needs microphone';
  if (muted) return 'muted';
  if (connected && quality == ConnectionQuality.poor) return 'weak connection';
  if (connected && agentSpeaking) return 'speaking';
  if (connected) return 'listening';
  return 'tap to talk';
}
