import 'dart:math' as math;

import 'config.dart';
import 'js.dart';
import 'loader.dart';
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
///
/// The 0.2.0 words, kept for hosts that print them. The agent bar now says
/// [voiceBarStatus] — the contract's words, in the contract's order.
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

// ── the voice bar (contract/DESIGN.md, "Voice bar") ─────────────────────────

/// Where the call stands, in one word — the React Native launcher's
/// `GrainePhase`, derived from the same state by [callPhase].
enum CallPhase {
  /// No call; ready to start one.
  idle,

  /// The page loading, or a call being placed.
  connecting,

  /// The page failed and is being reloaded, or the network dropped the call.
  reconnecting,

  /// The customer finished a sentence and the agent has not answered yet.
  thinking,

  /// The agent is talking.
  speaking,

  /// The agent is waiting for the customer.
  listening,
}

/// THE CALL'S PHASE, exactly as the React Native launcher derives it.
///
/// Thinking is the gap between the customer's final line and the agent's
/// first: the last thing said is the customer's, settled. Read from the
/// transcript rather than kept as a flag, because the transcript is the
/// truth about who last spoke — a flag set by one message and cleared by
/// another is how a bar ends up "thinking" through the agent's whole answer.
CallPhase callPhase({
  required bool reconnecting,
  required GraineConnectivity connectivity,
  required bool connecting,
  required bool ready,
  required bool connected,
  required Caption? caption,
  bool agentSpeaking = false,
}) {
  if (reconnecting || connectivity == GraineConnectivity.failed || connectivity == GraineConnectivity.retrying) {
    return CallPhase.reconnecting;
  }
  if (connecting || !ready) return CallPhase.connecting;
  if (!connected) return CallPhase.idle;
  if (agentSpeaking || (caption != null && caption.role == Role.agent && caption.live)) return CallPhase.speaking;
  if (caption != null && caption.role == Role.customer && !caption.live) return CallPhase.thinking;
  return CallPhase.listening;
}

/// WHERE THE VOICE BAR'S CALL IS, in one word (contract/PUBLIC-STATE.md,
/// "Voice") — what the SDK's own bar draws from, for a bar of your own:
/// `GraineVoice.status`. [of] derives it in the bar's order ([voiceBarStatus]).
enum GraineVoiceStatus {
  /// No call yet; a start places one.
  idle('idle'),

  /// The engine page loading, or a call being placed.
  connecting('connecting'),

  /// On the call; the agent is waiting for the customer.
  listening('listening'),

  /// The customer finished a sentence and the agent has not answered yet.
  thinking('thinking'),

  /// The agent is talking.
  speaking('speaking'),

  /// The network interrupted the call and it is being re-established — or the
  /// page is loading again after a failed load, or the call being placed is
  /// trying again or moving to the other transport.
  reconnecting('reconnecting'),

  /// On the call with the customer's microphone muted.
  muted('muted'),

  /// The call cannot happen as things stand — `GraineVoice.failure` says why
  /// in a sentence: a setting someone must change, the microphone refused,
  /// an engine page that could not load, or a call neither transport could
  /// carry. A start (or `retry()`, for the page) tries again.
  failed('failed'),

  /// A call was on and is over; the next start places another.
  ended('ended');

  const GraineVoiceStatus(this.wire);

  /// The word every Graine SDK uses.
  final String wire;

  /// The status of a call in this state — the voice bar's own order: a
  /// setting to fix; a reconnect; a refusal, a load or a connect that failed;
  /// connecting (the page not ready, or a call being placed); then on the
  /// call muted, thinking, speaking or listening; else ended (a call was on)
  /// or idle.
  static GraineVoiceStatus of({
    String? error,
    required bool reconnecting,
    required GraineConnectivity connectivity,
    ConnectStage? connectStage,
    required bool micDenied,
    bool callFailed = false,
    required bool ready,
    required bool connecting,
    required bool connected,
    required bool muted,
    required CallPhase phase,
    bool ended = false,
  }) {
    if (error != null) return failed;
    if (reconnecting ||
        connectivity == GraineConnectivity.retrying ||
        connectStage == ConnectStage.retrying ||
        connectStage == ConnectStage.switching) {
      return GraineVoiceStatus.reconnecting;
    }
    if (micDenied || connectivity == GraineConnectivity.failed || callFailed) return failed;
    if (connecting || !ready) return GraineVoiceStatus.connecting;
    if (connected) {
      if (muted) return GraineVoiceStatus.muted;
      return switch (phase) {
        CallPhase.thinking => thinking,
        CallPhase.speaking => speaking,
        _ => listening,
      };
    }
    return ended ? GraineVoiceStatus.ended : idle;
  }

  /// The sentence a failed load gives: the page could not be reached.
  static const String couldNotLoad = 'The assistant could not load. Check your connection and try again.';

  /// The sentence a refused microphone gives.
  static const String micRefused = 'The microphone is not allowed, so the call could not start.';

  /// The sentence a call neither transport could carry gives.
  static const String couldNotConnect = 'The call could not be connected. Try again.';

  /// Why [of] is [failed], as a sentence for a person — [error] itself for a
  /// setting to fix — in the same order; null when it is not.
  static String? failureOf({
    String? error,
    required bool reconnecting,
    required GraineConnectivity connectivity,
    ConnectStage? connectStage,
    required bool micDenied,
    bool callFailed = false,
  }) {
    if (error != null) return error;
    if (reconnecting ||
        connectivity == GraineConnectivity.retrying ||
        connectStage == ConnectStage.retrying ||
        connectStage == ConnectStage.switching) {
      return null;
    }
    if (micDenied) return micRefused;
    if (connectivity == GraineConnectivity.failed) return couldNotLoad;
    if (callFailed) return couldNotConnect;
    return null;
  }
}

/// What the voice bar's status line says ([voiceBarStatus]).
class BarStatus {
  const BarStatus(this.text, {this.waiting, this.meter = false, this.label});

  /// The words, in sentence case, exactly as the contract lists them.
  final String text;

  /// A loader moment — `connecting`, `reconnecting` or `thinking` — to draw
  /// instead of [text]: the dashboard's loader, with its words for that
  /// moment. Null for plain words.
  final String? waiting;

  /// Precede the words with the four-bar meter ([VoiceMeter]).
  final bool meter;

  /// Words the loader says in place of the brand's words for [waiting] —
  /// only "Still connecting…" sets it, and only while those words are the
  /// default ([connectingLook]). Null: the brand's words for the moment.
  final String? label;

  @override
  bool operator ==(Object other) =>
      other is BarStatus &&
      other.text == text &&
      other.waiting == waiting &&
      other.meter == meter &&
      other.label == label;

  @override
  int get hashCode => Object.hash(text, waiting, meter, label);

  @override
  String toString() => 'BarStatus("$text"${waiting != null ? ', loader: $waiting' : ''}'
      '${label != null ? ', label: $label' : ''}${meter ? ', meter' : ''})';
}

/// WHERE A CALL BEING PLACED IS, as the engine reports it (`graine:progress`).
enum ConnectStage {
  /// A credential and a line are being set up (a cold start).
  registering,

  /// The call is on its way to the agent.
  dialling,

  /// The first attempt went unanswered; a fresh connection is being made —
  /// on mobile data, usually a connection the phone dropped while idle.
  retrying,

  /// The call is moving to the other transport.
  switching;

  /// The stage for a word on the wire, or null for one this SDK does not
  /// know — and for "failed", which ends a connect rather than being a stage of one.
  static ConnectStage? from(String? wire) {
    for (final s in values) {
      if (s.name == wire) return s;
    }
    return null;
  }

  /// The word on the wire.
  String get wire => name;
}

/// The numbers and words of a connect that says where it is.
abstract final class ConnectProgress {
  /// When a connect stops being "Connecting…" and becomes "Still
  /// connecting…": past the point a healthy connect finishes (warm 0.2–0.9 s,
  /// cold 1.5–2.5 s on a good network) and well inside the ten seconds after
  /// which, without a word of explanation, people assume it is broken. The
  /// React Native SDK's SLOW_CONNECT_MS.
  static const int slowConnectMs = 4000;

  /// A slow connect, while the brand's connecting words are the default.
  static const String stillConnecting = 'Still connecting…';

  /// Neither transport could carry the call (a curly apostrophe).
  static const String couldNotConnect = 'Couldn’t connect · tap to retry';
}

/// WHAT A CONNECT SAYS WHILE IT RUNS — contract/DESIGN.md, "Connecting"; the
/// React Native voice bar's connectingLook.
///
/// Measured, the commonest slow connect on mobile data is a connection the
/// phone dropped while idle being replaced: a few seconds the customer will
/// wait if the bar says what is happening, and will not if it says
/// "Connecting…" for all of them.
///
/// The words stay the BRAND's. The loader draws each moment in the wording
/// set under Appearance → Loading — often not English — so a retry or a
/// switch to the other transport is the "reconnecting" moment, in their
/// words, and a slow connect says "Still connecting…" only while
/// [connectingText] (the brand's words for connecting) is still the default
/// "Connecting…". A wording someone chose is never overwritten.
BarStatus connectingLook({
  ConnectStage? stage,
  bool slow = false,
  String? connectingText,
}) {
  final words = connectingText ?? Loaders.defaultText.connecting!;
  if (stage == ConnectStage.retrying || stage == ConnectStage.switching) {
    return const BarStatus('Reconnecting…', waiting: 'reconnecting');
  }
  if (slow && words == Loaders.defaultText.connecting) {
    return const BarStatus(ConnectProgress.stillConnecting,
        waiting: 'connecting', label: ConnectProgress.stillConnecting);
  }
  return BarStatus(words, waiting: 'connecting');
}

/// THE VOICE BAR'S STATUS LINE — contract/DESIGN.md, "Status words": the
/// first that matches wins.
///
/// While the call is being placed the words are [connectingLook]'s, from
/// [connectStage], [slowConnect] and the brand's [connectingText] (the
/// loader's words for connecting; default "Connecting…"). [callFailed] —
/// nothing could carry the call — says "Couldn’t connect · tap to retry".
///
/// The network gets named before the agent takes the blame for it: a customer
/// whose agent goes quiet on a train reads "Listening" and concludes the agent
/// is broken. In the chat none of the call's words are true, so the chat has
/// its own two.
BarStatus voiceBarStatus({
  bool error = false,
  bool inChat = false,
  bool chatOnline = false,
  required bool? online,
  required bool reconnecting,
  required GraineConnectivity connectivity,
  required bool micDenied,
  required bool ready,
  required bool connecting,
  required bool muted,
  required bool connected,
  bool thinking = false,
  required bool speaking,
  required ConnectionQuality quality,
  bool callFailed = false,
  ConnectStage? connectStage,
  bool slowConnect = false,
  String? connectingText,
}) {
  if (error) return const BarStatus('Unavailable');
  if (inChat) return chatOnline ? const BarStatus('Online') : const BarStatus('Connecting…', waiting: 'connecting');
  if (online == false) return const BarStatus('No connection');
  if (reconnecting || connectivity == GraineConnectivity.retrying) {
    return const BarStatus('Reconnecting…', waiting: 'reconnecting');
  }
  if (micDenied) return const BarStatus('Needs microphone');
  if (connectivity == GraineConnectivity.failed) return const BarStatus('Couldn’t load · tap to retry');
  // Neither transport could carry the call. The microphone tries again.
  if (callFailed) return const BarStatus(ConnectProgress.couldNotConnect);
  if (!ready || connecting) {
    return connectingLook(stage: connectStage, slow: slowConnect, connectingText: connectingText);
  }
  if (muted) return const BarStatus('Muted');
  if (connected && thinking) return const BarStatus('Thinking…', waiting: 'thinking');
  if (connected && speaking) return const BarStatus('Speaking', meter: true);
  if (connected && quality == ConnectionQuality.poor) return const BarStatus('Weak connection');
  if (connected) return const BarStatus('Listening', meter: true);
  return const BarStatus('Tap to talk');
}

/// THE METER — four bars beside "Listening" and "Speaking" that move at the
/// design's own pace, so the motion knob is visible on the one surface a
/// customer watches. The Garage's `dg-eq`, as numbers.
abstract final class VoiceMeter {
  /// Each bar's height, as a fraction of [height].
  static const List<double> heights = <double>[0.55, 1, 0.7, 0.4];
  static const double height = 12;
  static const double barWidth = 2.5;
  static const double gap = 2;

  /// The low point of the swing: a bar scales from its bottom between this and 1.
  static const double low = 0.35;

  /// Bar i starts i × this late.
  static const int staggerMs = 90;

  /// One leg — low to full, or back: `max(420, durationMs × 3.2)` ms.
  static double legMs(int durationMs) => math.max(420, durationMs * 3.2);

  /// Still at full height: no motion in the design (or the OS asked for less).
  static bool still(int durationMs) => durationMs <= 0;

  /// Bar [bar]'s vertical scale [elapsedMs] after the meter appeared. Before
  /// its stagger a bar waits at [low]; then it rises for one leg and falls
  /// for the next, forever. [ease] shapes each leg (the widget passes
  /// ease-in-out); still, every bar is 1.
  static double scale(int bar, double elapsedMs, int durationMs, [double Function(double t)? ease]) {
    if (still(durationMs)) return 1;
    final t = elapsedMs - bar * staggerMs;
    if (t <= 0) return low;
    final leg = legMs(durationMs);
    final phase = t % (2 * leg);
    final rising = phase < leg;
    final raw = (rising ? phase : phase - leg) / leg;
    final f = ease == null ? raw : ease(raw);
    return rising ? low + (1 - low) * f : 1 - (1 - low) * f;
  }
}

/// The two ways a customer can be with the agent.
enum AgentSurface { voice, chat }

/// Which surfaces the dashboard allows, which to open, and whether to offer
/// a switch between them.
class SurfacePolicy {
  const SurfacePolicy({required this.allowed, required this.start, required this.canSwitch});

  /// In the order to offer them.
  final List<AgentSurface> allowed;
  final AgentSurface start;

  /// Draw a switch at all: false when the agent is one or the other.
  final bool canSwitch;
}

/// THE CALL OR THE CHAT — the React Native SDK's resolveSurface. The
/// dashboard's `mode` says which exist ("voice", "chat", else both) and its
/// `start` which opens first; a preference ([prefer] — the host's, or the
/// customer's last switch) wins when the dashboard allows it, and is clamped
/// when it does not: the brand's setting is not something an app can talk
/// its way past.
abstract final class Surfaces {
  static SurfacePolicy resolve(Map<String, Object?>? appearance, [AgentSurface? prefer]) {
    final rawMode = appearance?['mode'];
    final mode = (rawMode == null ? 'both' : Js.str(rawMode)).toLowerCase();
    final allowed = mode == 'voice'
        ? const <AgentSurface>[AgentSurface.voice]
        : mode == 'chat'
            ? const <AgentSurface>[AgentSurface.chat]
            : const <AgentSurface>[AgentSurface.voice, AgentSurface.chat];
    final configured = Js.strOrEmpty(appearance?['start']).toLowerCase();
    AgentSurface? named;
    if (configured == 'voice') named = AgentSurface.voice;
    if (configured == 'chat') named = AgentSurface.chat;
    final start = (prefer != null && allowed.contains(prefer))
        ? prefer
        : (named != null && allowed.contains(named) ? named : allowed.first);
    return SurfacePolicy(allowed: allowed, start: start, canSwitch: allowed.length > 1);
  }
}
