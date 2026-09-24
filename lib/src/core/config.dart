import 'friction.dart';
import 'js.dart';
import 'protocol.dart';

/// Load timing, for a field app on a very slow network.
class GraineTiming {
  const GraineTiming({
    this.stallMs = 15000,
    this.bootMs = 15000,
    this.hardCapMs = 120000,
    this.retryDelaysMs = const <int>[1000, 2000, 4000, 8000, 15000, 15000],
    this.endWatchdogMs = 4000,
  });

  /// Silence — nothing downloaded — before a load is given up on.
  final int stallMs;

  /// Downloaded but still not ready: the page is broken, not slow.
  final int bootMs;

  /// Ceiling on one attempt however steadily it is arriving.
  final int hardCapMs;

  /// The whole retry ladder; its length is the number of reloads before the
  /// SDK gives up and reports [GraineConnectivity.failed].
  final List<int> retryDelaysMs;

  /// How long an end-call may go unconfirmed before the call is torn down locally.
  final int endWatchdogMs;
}

/// Everything the SDK needs to know up front.
class GraineConfig {
  const GraineConfig({
    required this.baseUrl,
    required this.publishableKey,
    this.variables = const <String, Object?>{},
    this.transport,
    this.appVersion,
    this.endOnBackground = true,
    this.timing = const GraineTiming(),
    this.debug = false,
    this.friction,
    this.requestMicrophone,
  });

  /// "https://www.graine.ai" unless self-hosted.
  final String baseUrl;

  /// From Agent → Embed & Widgets. Selects the agent. It is not a secret and
  /// cannot place a call on its own — add `app://` to that agent's Allowed
  /// domains, or every request is refused.
  final String publishableKey;

  /// Prompt {variables} known at build time. identify() and setVariables() win over these.
  final Map<String, Object?> variables;

  /// Force a transport. Null (the default) lets the dashboard's Call audio setting decide.
  final Transport? transport;

  /// Lands on the call record, to tell builds apart.
  final String? appVersion;

  /// End a live call when the app goes to the background. On by default; you want it on.
  final bool endOnBackground;

  final GraineTiming timing;

  /// Log every message across the bridge, both ways, and the engine page's
  /// console, with the prefix "[Graine]". Off by default; turn it on in
  /// debug builds — "the agent did not speak" is answered in one read of
  /// this log, and unanswerable without it.
  final bool debug;

  /// This app's friction rules, over the dashboard's. Most apps set nothing here.
  final FrictionConfig? friction;

  /// MAKE SURE THE APP HOLDS THE MICROPHONE, before a call opens.
  ///
  /// A WebView cannot hold a permission its app does not. This package adds
  /// no permission plugin of its own, so the app supplies the one it already
  /// uses — e.g. with permission_handler:
  ///
  ///     requestMicrophone: () async => (await Permission.microphone.request()).isGranted,
  ///
  /// Called by `GraineVoice.start()` before the call is placed. `false` means
  /// no call is opened and `onMicDenied("NotAllowedError")` is reported.
  /// Left null, the SDK assumes the app asked already; if it did not, the page
  /// reports `graine:mic-denied` when the microphone is refused.
  final Future<bool> Function()? requestMicrophone;
}

/// Whether the page that carries the call is actually there.
enum GraineConnectivity { loading, ready, retrying, failed }

/// What the dashboard says about this agent, fetched once per launch from
/// `POST {baseUrl}/api/embed/session`.
class SessionConfig {
  const SessionConfig({
    required this.agentId,
    required this.webcallAgentId,
    this.appearance = const <String, Object?>{},
    this.variables = const <String, Object?>{},
    this.pageVersion,
    this.declaredActions = const <String>{},
    this.friction,
  });

  final String agentId;

  /// The agent the call is filed under. Calling the primary id works, sounds
  /// right, and files every transcript under an agent nobody watches.
  final String webcallAgentId;

  /// Embed & Widgets → Appearance, exactly as stored.
  final Map<String, Object?> appearance;

  /// The dashboard's variable defaults.
  final Map<String, Object?> variables;

  /// The deployment id: the engine page's cache key.
  final String? pageVersion;

  /// The in-app actions the dashboard declares.
  final Set<String> declaredActions;

  /// The dashboard's friction rules, as served.
  final Map<String, Object?>? friction;

  /// The dashboard's Call audio setting.
  Transport get preferredTransport =>
      appearance['audioTransport'] == 'rtc' ? Transport.webrtc : Transport.websocket;

  /// The dashboard's accent, as stored (it may lack its "#").
  String? get accent {
    final a = Js.strOrEmpty(appearance['accent']);
    return a.isEmpty ? null : a;
  }

  /// The session response, parsed exactly as the Android SDK parses it.
  static SessionConfig fromJson(Map<String, Object?> data) {
    String s(Object? v) => v == null ? '' : (v is String ? v : Js.str(v));
    final agentId = s(data['agentId']);
    final declared = <String>{};
    for (final raw in Js.asList(data['appActions'])) {
      final a = Js.asMap(raw);
      if (a == null) continue;
      var n = s(a['tool_name']);
      if (n.isEmpty) n = s(a['toolName']);
      if (n.isEmpty) n = s(a['name']);
      if (n.isNotEmpty) declared.add(n);
    }
    final webcall = s(data['webcallAgentId']);
    final page = s(data['pageVersion']);
    return SessionConfig(
      agentId: agentId,
      webcallAgentId: webcall.isEmpty ? agentId : webcall,
      appearance: Js.asMap(data['appearance']) ?? <String, Object?>{},
      variables: Js.asMap(data['variables']) ?? <String, Object?>{},
      pageVersion: page.isEmpty ? null : page,
      declaredActions: declared,
      friction: Js.asMap(data['friction']),
    );
  }

  /// The sentence for a refused session request — written for whoever has to
  /// fix it — or null for a 2xx.
  static String? errorFor(int status, Map<String, Object?> body) {
    if (status >= 200 && status <= 299) return null;
    final said = body['error'];
    if (status == 403) {
      return 'This agent does not accept connections from a mobile app yet. Add "app://" to its '
          'Allowed domains in the dashboard, under Embed & Widgets. '
          '(server said: ${said == null ? 'forbidden' : Js.str(said)})';
    }
    if (status == 401) {
      return 'Publishable key was rejected. Check it against Embed & Widgets in the dashboard.';
    }
    final text = said == null ? '' : Js.str(said);
    return text.isEmpty ? 'Embed rejected ($status)' : text;
  }
}
