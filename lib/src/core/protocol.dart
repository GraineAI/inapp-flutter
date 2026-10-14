import 'dart:convert';

import 'js.dart';

/// THE WIRE PROTOCOL — the same one the React Native and Android SDKs speak,
/// byte for byte.
///
/// The call runs in a page Graine hosts, inside a WebView this SDK owns. That
/// is the whole reason a Flutter app gets every audio-path fix the day it
/// ships: TURN relays, the dead-media watchdog, connection quality, WebSocket
/// fallback all live in the page, and the page updates without an app release.
///
///   host → page   window.postMessage({type: "graine:…"}, "*")
///   page → host   window.ReactNativeWebView.postMessage("<json>")
///
/// The page was written for React Native's WebView; this SDK installs a
/// JavaScript channel under that same name, so the page needs no idea which
/// platform it runs on. A type that is not listed here is ignored rather than
/// guessed at.
abstract final class Protocol {
  /// The name the page looks for.
  static const String bridgeName = 'ReactNativeWebView';

  /// How long an action handler may take before the agent is told it was not done.
  static const int actionDeadlineMs = 6000;

  /// The engine page's URL. Identical to the React Native launcher's, because
  /// a difference here is a different agent, a different transport, or a
  /// cache that never refreshes.
  ///
  /// [voiceAgentId] is the WEB-CALL agent id. [cacheKey] is the deployment id
  /// from the session (a new deploy is a new URL; the same deploy is served
  /// from the nearest edge). [idle] loads the page without registering
  /// anything, so a later tap costs an INVITE rather than a page load.
  ///
  /// Components are encoded as JavaScript's encodeURIComponent does it —
  /// which is exactly Dart's [Uri.encodeComponent] (spaces as %20).
  static String engineUrl({
    required String baseUrl,
    required String voiceAgentId,
    required Transport transport,
    required String cacheKey,
    required bool idle,
    required String publishableKey,
    String? accent,
  }) {
    final base = trimTrailingSlashes(baseUrl);
    final sb = StringBuffer()
      ..write(base)
      ..write('/embed/')
      ..write(Uri.encodeComponent(voiceAgentId))
      ..write('?mode=voice&branding=0&embed=1')
      ..write('&transport=')
      ..write(transport.wire)
      ..write('&b=')
      ..write(Uri.encodeComponent(cacheKey));
    if (idle) sb.write('&idle=1');
    sb
      ..write('&pk=')
      ..write(Uri.encodeComponent(publishableKey));
    var hex = accent?.trim();
    if (hex != null && hex.startsWith('#')) hex = hex.substring(1);
    if (hex != null && hex.isNotEmpty) {
      sb
        ..write('&accent=')
        ..write(Uri.encodeComponent(hex));
    }
    return sb.toString();
  }

  /// The JavaScript that delivers one message into the page.
  ///
  /// `true;` at the end because the platforms hand the statement's value
  /// back, and a non-serialisable one is an error on every message (iOS
  /// throws it at the caller). U+2028/U+2029 are escaped: legal in JSON,
  /// not in a JavaScript string literal on an older engine.
  static String deliver(Map<String, Object?> message) {
    final json = jsonEncode(toJson(message))
        .replaceAll(_lineSeparator, r'\u' '2028')
        .replaceAll(_paragraphSeparator, r'\u' '2029');
    return 'window.postMessage($json, "*"); true;';
  }

  static final String _lineSeparator = String.fromCharCode(0x2028);
  static final String _paragraphSeparator = String.fromCharCode(0x2029);

  /// One outgoing message: `{type, ...fields}`, every value made JSON-safe.
  static Map<String, Object?> out(String type,
      [Map<String, Object?> fields = const <String, Object?>{}]) {
    return <String, Object?>{
      'type': type,
      for (final e in fields.entries) e.key: toJson(e.value),
    };
  }

  /// Dart values → JSON values, recursively. Anything else becomes its
  /// string form; a non-finite number (which JSON cannot carry) is null.
  static Object? toJson(Object? v) {
    if (v == null || v is String || v is bool || v is int) return v;
    if (v is double) return v.isFinite ? v : null;
    if (v is num) return v;
    if (v is Map) {
      return <String, Object?>{
        for (final e in v.entries) e.key.toString(): toJson(e.value),
      };
    }
    if (v is Iterable) return <Object?>[for (final x in v) toJson(x)];
    if (v is Enum) return v.name;
    return v.toString();
  }

  /// Parse one message from the page. Null for anything that is not ours.
  static PageMessage? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    final o = Js.asMap(decoded);
    if (o == null) return null;
    switch (_optString(o, 'type')) {
      case ProtocolIn.ready:
        return const PageReady();
      case ProtocolIn.call:
        return PageCall(
            connected: _optBool(o, 'connected'),
            connecting: _optBool(o, 'connecting'));
      case ProtocolIn.muted:
        return PageMuted(_optBool(o, 'muted'));
      case ProtocolIn.caption:
        return PageCaption(
          role: _optString(o, 'role') == 'agent' ? Role.agent : Role.customer,
          text: _optString(o, 'text'),
          live: _optBool(o, 'live'),
        );
      case ProtocolIn.widget:
        return PageWidget(Js.asMap(o['widget']) ?? <String, Object?>{});
      case ProtocolIn.widgetPending:
        return PageWidgetPending(Js.asMap(o['widget']) ?? <String, Object?>{});
      case ProtocolIn.appAction:
        final a = Js.asMap(o['action']);
        if (a == null) return null;
        return PageAppAction(
          actionId: _optString(a, 'action_id'),
          name: _optString(a, 'name'),
          arguments: Js.asMap(a['arguments']) ?? <String, Object?>{},
        );
      case ProtocolIn.ended:
        return const PageEnded();
      case ProtocolIn.micDenied:
        return PageMicDenied(_optString(o, 'reason', 'NotAllowedError'));
      case ProtocolIn.transport:
        final reason = _optString(o, 'reason');
        final message = _optString(o, 'message');
        return PageTransport(
          transport: Transport.from(_optString(o, 'transport')),
          requested: Transport.from(_optString(o, 'requested')),
          reason: reason.isEmpty ? null : reason,
          message: message.isEmpty ? null : message,
        );
      case ProtocolIn.quality:
        final s = Js.asMap(o['sample']) ?? const <String, Object?>{};
        return PageQuality(
          rttMs: _measurement(s['rtt']),
          jitterMs: _measurement(s['jitter']),
          loss: _measurement(s['loss']),
        );
      case ProtocolIn.network:
        return PageNetwork(_optBool(o, 'online'));
      case ProtocolIn.reconnecting:
        return PageReconnecting(_optBool(o, 'active'));
      case ProtocolIn.progress:
        return PageProgress(_optString(o, 'stage'));
      default:
        return null;
    }
  }

  /// A frame off a socket — text, or UTF-8 bytes — as JSON. Throws on
  /// anything that is not JSON.
  static Object? decodeJson(Object? raw) {
    if (raw is String) return jsonDecode(raw);
    if (raw is List<int>) return jsonDecode(utf8.decode(raw, allowMalformed: true));
    throw const FormatException('not a text frame');
  }

  /// THE VARIABLES ON THE ONE CHANNEL A DIRECT SOCKET'S RUNTIME READS —
  /// `?context_token=` (the React Native SDK's contextToken, byte for byte):
  /// base64 of the UTF-8 JSON `{...vals, call_type, recipient_data: {...vals,
  /// call_type}}`, where `vals` are the values with nulls, maps and lists
  /// dropped and every other value as JavaScript's `String()` writes it. Null
  /// when there is nothing to say.
  static String? contextToken(Map<String, Object?>? variables, {String callType = 'webcall'}) {
    final vals = <String, Object?>{};
    variables?.forEach((String k, Object? v) {
      if (v == null || v is Map || v is Iterable) return;
      final key = k.trim();
      if (key.isNotEmpty) vals[key] = v is String ? v : Js.str(v);
    });
    if (vals.isEmpty) return null;
    final payload = <String, Object?>{
      ...vals,
      'call_type': callType,
      'recipient_data': <String, Object?>{...vals, 'call_type': callType},
    };
    return base64.encode(utf8.encode(jsonEncode(payload)));
  }

  /// The ticket's limits on variables: it travels in a subprotocol header.
  static const int ticketMaxKeys = 12;
  static const int ticketMaxKeyLength = 40;
  static const int ticketMaxValueLength = 200;
  static const int ticketMaxBytes = 1024;

  /// THE VARIABLES THAT RIDE A TICKET as its `metadata` (the React Native
  /// SDK's variablesForTicket): the first 12 usable values, keys cut to 40
  /// characters and values to 200 — and nothing at all when the whole would
  /// pass a kilobyte, exactly as the server would drop it. Null when empty.
  static Map<String, String>? ticketMetadata(Map<String, Object?>? variables) {
    if (variables == null) return null;
    final out = <String, String>{};
    for (final e in variables.entries) {
      if (out.length >= ticketMaxKeys) break;
      final v = e.value;
      if (v == null || v is Map || v is Iterable) continue;
      final key = _cut(e.key, ticketMaxKeyLength);
      final value = _cut(v is String ? v : Js.str(v), ticketMaxValueLength);
      if (key.isEmpty || value.isEmpty) continue;
      out[key] = value;
    }
    if (out.isEmpty) return null;
    var bytes = 2;
    out.forEach((String k, String v) => bytes += utf8.encode(k).length + utf8.encode(v).length + 6);
    return bytes > ticketMaxBytes ? null : out;
  }

  /// `String.prototype.slice(0, n)`: UTF-16 units, as JavaScript counts them.
  static String _cut(String s, int n) => s.length <= n ? s : s.substring(0, n);

  /// `baseUrl` without its trailing slashes.
  static String trimTrailingSlashes(String s) {
    var end = s.length;
    while (end > 0 && s.codeUnitAt(end - 1) == 0x2F) {
      end--;
    }
    return s.substring(0, end);
  }

  /// org.json's `optString`: absent or null is the fallback; a non-string
  /// value is its string form.
  static String _optString(Map<String, Object?> o, String key,
      [String fallback = '']) {
    final v = o[key];
    if (v == null) return fallback;
    if (v is String) return v;
    if (v is Map || v is List) return jsonEncode(v);
    return Js.str(v);
  }

  /// org.json's `optBoolean`: true, or the string "true".
  static bool _optBool(Map<String, Object?> o, String key) {
    final v = o[key];
    return v == true || (v is String && v.toLowerCase() == 'true');
  }

  /// A measurement is a finite, non-negative number; anything else is absent
  /// — never zero, which would read as a perfect line.
  static double? _measurement(Object? v) {
    if (v is! num) return null;
    final d = v.toDouble();
    return d.isFinite && d >= 0 ? d : null;
  }
}

/// Messages this SDK sends into the page.
abstract final class ProtocolOut {
  static const String startCall = 'graine:start-call';
  static const String endCall = 'graine:end-call';
  static const String setMuted = 'graine:set-muted';
  static const String warm = 'graine:warm';
  static const String variables = 'graine:variables';
  static const String appContext = 'graine:app-context';
  static const String appActionResult = 'graine:app-action-result';
  static const String appEvent = 'graine:app-event';
  static const String widgetResult = 'graine:widget-result';

  /// Who the user is, for the tickets the page mints:
  /// `{value, installId, memory, timezone}` — `value` the raw identity, or
  /// null for an anonymous user (contract §1.3).
  static const String identity = 'graine:identity';
}

/// Messages the page sends out.
abstract final class ProtocolIn {
  static const String ready = 'graine:ready';
  static const String call = 'graine:call';
  static const String muted = 'graine:muted';
  static const String caption = 'graine:caption';
  static const String widget = 'graine:widget';
  static const String widgetPending = 'graine:widget-pending';
  static const String appAction = 'graine:app-action';
  static const String ended = 'graine:ended';
  static const String micDenied = 'graine:mic-denied';
  static const String transport = 'graine:transport';
  static const String quality = 'graine:quality';
  static const String network = 'graine:network';
  static const String reconnecting = 'graine:reconnecting';

  /// Where a connect is: `{stage}` — registering, dialling, retrying,
  /// switching, or failed (contract/DESIGN.md, "Connecting").
  static const String progress = 'graine:progress';
}

/// How the call's audio travels.
enum Transport {
  /// Raw PCM on the conversation socket. Works everywhere; a lossy network sounds lossy.
  websocket('ws'),

  /// Opus over WebRTC with a jitter buffer and the device's echo canceller.
  /// Falls back to [websocket].
  webrtc('rtc');

  const Transport(this.wire);

  /// The word on the wire and in the URL.
  final String wire;

  static Transport from(String? s) => s == 'rtc' ? webrtc : websocket;
}

/// Who said a caption.
enum Role { agent, customer }

/// Everything the page can say, typed.
sealed class PageMessage {
  const PageMessage();
}

final class PageReady extends PageMessage {
  const PageReady();
  @override
  bool operator ==(Object other) => other is PageReady;
  @override
  int get hashCode => 1;
}

final class PageCall extends PageMessage {
  const PageCall({required this.connected, required this.connecting});
  final bool connected;
  final bool connecting;
  @override
  bool operator ==(Object other) =>
      other is PageCall &&
      other.connected == connected &&
      other.connecting == connecting;
  @override
  int get hashCode => Object.hash(connected, connecting);
}

final class PageMuted extends PageMessage {
  const PageMuted(this.muted);
  final bool muted;
  @override
  bool operator ==(Object other) => other is PageMuted && other.muted == muted;
  @override
  int get hashCode => muted.hashCode;
}

final class PageCaption extends PageMessage {
  const PageCaption({required this.role, required this.text, required this.live});
  final Role role;
  final String text;
  final bool live;
  @override
  bool operator ==(Object other) =>
      other is PageCaption &&
      other.role == role &&
      other.text == text &&
      other.live == live;
  @override
  int get hashCode => Object.hash(role, text, live);
}

final class PageWidget extends PageMessage {
  const PageWidget(this.widget);
  final Map<String, Object?> widget;
}

final class PageWidgetPending extends PageMessage {
  const PageWidgetPending(this.widget);
  final Map<String, Object?> widget;
}

final class PageAppAction extends PageMessage {
  const PageAppAction(
      {required this.actionId, required this.name, required this.arguments});
  final String actionId;
  final String name;
  final Map<String, Object?> arguments;
}

final class PageEnded extends PageMessage {
  const PageEnded();
  @override
  bool operator ==(Object other) => other is PageEnded;
  @override
  int get hashCode => 2;
}

final class PageMicDenied extends PageMessage {
  const PageMicDenied(this.reason);
  final String reason;
  @override
  bool operator ==(Object other) =>
      other is PageMicDenied && other.reason == reason;
  @override
  int get hashCode => reason.hashCode;
}

final class PageTransport extends PageMessage {
  const PageTransport(
      {required this.transport,
      required this.requested,
      this.reason,
      this.message});
  final Transport transport;
  final Transport requested;
  final String? reason;
  final String? message;
  @override
  bool operator ==(Object other) =>
      other is PageTransport &&
      other.transport == transport &&
      other.requested == requested &&
      other.reason == reason &&
      other.message == message;
  @override
  int get hashCode => Object.hash(transport, requested, reason, message);
}

final class PageQuality extends PageMessage {
  const PageQuality({this.rttMs, this.jitterMs, this.loss});
  final double? rttMs;
  final double? jitterMs;
  final double? loss;
  @override
  bool operator ==(Object other) =>
      other is PageQuality &&
      other.rttMs == rttMs &&
      other.jitterMs == jitterMs &&
      other.loss == loss;
  @override
  int get hashCode => Object.hash(rttMs, jitterMs, loss);
}

final class PageNetwork extends PageMessage {
  const PageNetwork(this.online);
  final bool online;
  @override
  bool operator ==(Object other) => other is PageNetwork && other.online == online;
  @override
  int get hashCode => online.hashCode;
}

final class PageReconnecting extends PageMessage {
  const PageReconnecting(this.active);
  final bool active;
  @override
  bool operator ==(Object other) =>
      other is PageReconnecting && other.active == active;
  @override
  int get hashCode => active.hashCode;
}

/// The engine's account of a connect in progress. [stage] is the word as
/// sent — a stage this SDK does not know is carried, and ignored by the
/// call ([ConnectStage.from]), rather than guessed at.
final class PageProgress extends PageMessage {
  const PageProgress(this.stage);
  final String stage;

  /// Nothing could carry the call: stop connecting.
  bool get failed => stage == 'failed';

  @override
  bool operator ==(Object other) => other is PageProgress && other.stage == stage;
  @override
  int get hashCode => stage.hashCode;
}

/// The connection, in one word: excellent, good, poor or lost (unknown before any sample).
///
/// Same thresholds as the React Native SDK, the Android SDK and the website
/// (150ms / 30ms / 2% leaves "excellent", 400ms / 80ms / 8% is "poor"), so
/// every surface means the same thing by "weak connection".
enum ConnectionQuality {
  excellent,
  good,
  poor,
  lost,
  unknown;

  /// One sample → one word. A value that is not a finite, non-negative
  /// number is absent, exactly as the RN SDK's classifyQuality reads it.
  static ConnectionQuality classify(num? rttMs, num? jitterMs, num? loss) {
    final r = _num(rttMs);
    final j = _num(jitterMs);
    final l = _num(loss);
    if (r == null && j == null && l == null) return unknown;
    // Any one of these alone is enough to ruin a call, so the worst wins.
    if ((r ?? 0) >= 400 || (j ?? 0) >= 80 || (l ?? 0) >= 0.08) return poor;
    if ((r ?? 0) >= 150 || (j ?? 0) >= 30 || (l ?? 0) >= 0.02) return good;
    return excellent;
  }

  static double? _num(num? v) {
    if (v == null) return null;
    final d = v.toDouble();
    return d.isFinite && d >= 0 ? d : null;
  }
}
