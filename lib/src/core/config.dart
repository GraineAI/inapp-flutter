import 'chat_size.dart';
import 'design.dart';
import 'friction.dart';
import 'identity.dart';
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
    this.slowConnectMs = 4000,
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

  /// How long a connect the customer is waiting on runs before it becomes
  /// `slowConnect` ("Still connecting…"). The default is
  /// ConnectProgress.slowConnectMs.
  final int slowConnectMs;
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
    this.fonts = const <String>[],
    this.captureTaps = true,
    this.chatSize,
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

  /// THE FONT FAMILIES THIS APP BUNDLES ITSELF, by family name as its
  /// pubspec declares them (`fonts: - family: Inter`).
  ///
  /// The brand chooses the agent's typeface in the dashboard, and the SDK
  /// fetches and registers it by itself — nothing here is needed for that. A
  /// family listed here is the app's own copy: it wins over the download and
  /// is never fetched. Empty (the default): the SDK fetches every family the
  /// design draws with, and until one arrives draws the platform's font.
  final List<String> fonts;

  /// TELL THE AGENT WHAT THE CUSTOMER TAPS, while a screen is set: a tap on a
  /// control with an accessibility label (`Semantics(label: …)`) as
  /// "tap:<label>", anywhere else as "tap:screen" with where — in the recent
  /// events, at most two a second, masked like everything else. On by
  /// default; [GraineEngine] sees the taps.
  final bool captureTaps;

  /// HOW BIG THE CHAT WINDOW OPENS, over the dashboard's choice (Embed &
  /// Widgets → Appearance → Chat window → Window size): `compact` above the
  /// bar, `large` a sheet over most of a phone (a panel on a tablet), `full`
  /// the whole screen. Null, the default, follows the dashboard; a size passed
  /// to `GraineChat.open` wins for that open.
  final GraineChatSize? chatSize;
}

/// Whether the page that carries the call is actually there.
enum GraineConnectivity { loading, ready, retrying, failed }

/// The agent's memory switch, as the session serves it.
class MemorySetting {
  const MemorySetting({this.enabled = false});

  /// The agent remembers identified users between conversations.
  final bool enabled;

  static MemorySetting? fromJson(Object? raw) {
    final r = Js.asMap(raw);
    if (r == null) return null;
    return MemorySetting(enabled: r['enabled'] == true);
  }
}

/// THE AGENT'S CALLING WINDOW, as booking applies it (from the session's
/// `calls.scheduling.callingWindow`): the hours Graine may ring — from
/// [start] up to, not including, [end] ("HH:MM", 24-hour, never across
/// midnight) on the [days] it names (0 Monday … 6 Sunday) — read on the
/// device's clock, in its own time zone. The booking sheet and
/// `GraineInApp.bookingSlots` offer only the times inside it.
final class GraineCallingWindow {
  const GraineCallingWindow({required this.start, required this.end, required this.days});

  /// When it opens, "HH:MM" — offered.
  final String start;

  /// When it closes, "HH:MM" — never offered.
  final String end;

  /// The days it is open: 0 Monday … 6 Sunday, each once, in order.
  final List<int> days;

  @override
  bool operator ==(Object other) =>
      other is GraineCallingWindow &&
      other.start == start &&
      other.end == end &&
      other.days.length == days.length &&
      Iterable<int>.generate(days.length).every((int i) => other.days[i] == days[i]);

  @override
  int get hashCode => Object.hash(start, end, Object.hashAll(days));

  @override
  String toString() => 'GraineCallingWindow($start–$end, days: $days)';
}

final RegExp _clockTime = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');

/// The session's `callingWindow`, read as every Graine SDK reads it
/// (sdk/contract/booking-slots.json, `window`): an object whose `start` and
/// `end` are "HH:MM" with start before end; `days` missing or null for every
/// day, else the whole numbers 0–6 it holds, each once, in order. Anything
/// else — no day left, days not a list, a time that is not one — is no
/// window: what cannot be read is never a reason to offer nothing.
GraineCallingWindow? _callingWindowOf(Object? raw) {
  if (raw is! Map) return null;
  final r = Js.asMap(raw)!;
  String? clock(Object? v) {
    if (v is! String) return null;
    final s = v.trim();
    return _clockTime.hasMatch(s) ? s : null;
  }

  final start = clock(r['start']);
  final end = clock(r['end']);
  if (start == null || end == null || start.compareTo(end) >= 0) return null;
  final rawDays = r['days'];
  final List<int> days;
  if (rawDays == null) {
    days = const <int>[0, 1, 2, 3, 4, 5, 6];
  } else if (rawDays is List) {
    final kept = <int>{
      for (final d in rawDays)
        if (d is num && d.isFinite && d == d.roundToDouble() && d >= 0 && d <= 6) d.toInt(),
    };
    days = List<int>.unmodifiable(kept.toList()..sort());
  } else {
    return null;
  }
  if (days.isEmpty) return null;
  return GraineCallingWindow(start: start, end: end, days: days);
}

/// What users may book from the app (Agent → Calls & scheduling).
class SchedulingSetting {
  const SchedulingSetting({
    this.usersCanBook = false,
    this.maxDaysAhead = 14,
    this.minLeadMinutes = 5,
    this.maxPendingPerUser = 3,
    this.callingWindow,
  });

  /// `scheduleCall` is allowed at all.
  final bool usersCanBook;
  final int maxDaysAhead;
  final int minLeadMinutes;
  final int maxPendingPerUser;

  /// The agent's calling window (`callingWindow`); null when it has none —
  /// every time between the earliest and the latest is offered.
  final GraineCallingWindow? callingWindow;

  static SchedulingSetting? fromJson(Object? raw) {
    final r = Js.asMap(raw);
    if (r == null) return null;
    int n(Object? v, int fallback, int min, int max) {
      final d = Js.finite(v);
      return d == null ? fallback : d.round().clamp(min, max);
    }

    return SchedulingSetting(
      usersCanBook: r['usersCanBook'] == true,
      maxDaysAhead: n(r['maxDaysAhead'], 14, 1, 30),
      minLeadMinutes: n(r['minLeadMinutes'], 5, 2, 1440),
      maxPendingPerUser: n(r['maxPendingPerUser'], 3, 1, 10),
      callingWindow: _callingWindowOf(r['callingWindow']),
    );
  }
}

/// Calls Graine rings on this workspace's apps (hosted ringing).
class CallsSetting {
  const CallsSetting({
    this.hosted = false,
    this.platforms = const <String>[],
    this.ringTimeoutSeconds = 45,
    this.callName,
    this.scheduling,
  });

  /// The workspace uploaded push credentials: Graine rings its users' devices.
  final bool hosted;

  /// Where it can ring: `ios`, `android`.
  final List<String> platforms;
  final int ringTimeoutSeconds;

  /// What the phone shows for the agent's calls; null — the agent's display name.
  final String? callName;
  final SchedulingSetting? scheduling;

  static CallsSetting? fromJson(Object? raw) {
    final r = Js.asMap(raw);
    if (r == null) return null;
    final ring = Js.finite(r['ringTimeoutSeconds']);
    return CallsSetting(
      hosted: r['hosted'] == true,
      platforms: <String>[
        for (final p in Js.asList(r['platforms']))
          if (p is String && p.trim().isNotEmpty) p.trim().toLowerCase(),
      ],
      ringTimeoutSeconds: ring == null ? 45 : ring.round().clamp(20, 60),
      callName: r['callName'] is String && (r['callName']! as String).trim().isNotEmpty
          ? (r['callName']! as String).trim()
          : null,
      scheduling: SchedulingSetting.fromJson(r['scheduling']),
    );
  }
}

/// WHY GRAINE SAID NO — the wire's codes, typed (WIRE.md, "Errors"), plus
/// [network] (Graine could not be reached) and [unknown] (a code this build
/// does not know: its word is kept beside it).
enum GraineErrorCode {
  invalidKey('invalid_key'),
  originRefused('origin_refused'),

  /// Too many requests: wait `retryAfterSeconds` when given.
  rateLimited('rate_limited'),
  invalidRequest('invalid_request'),
  identityRequired('identity_required'),
  deviceLimit('device_limit'),
  schedulingOff('scheduling_off'),
  tooSoon('too_soon'),
  tooFar('too_far'),
  outsideWindow('outside_window'),
  tooManyPending('too_many_pending'),
  notFound('not_found'),
  unavailable('unavailable'),
  network('network'),
  unknown('unknown');

  const GraineErrorCode(this.wire);

  /// The word on the wire.
  final String wire;

  static GraineErrorCode fromWire(String? s) {
    final w = (s ?? '').trim().toLowerCase();
    for (final v in values) {
      if (v.wire == w) return v;
    }
    return unknown;
  }
}

/// A refusal from one of the SDK's routes: `{ error, code }`, with the
/// sentence written for whoever has to act on it.
class EmbedRefusal {
  const EmbedRefusal(this.message, {required this.code, this.codeName, this.statusCode, this.retryAfterSeconds});

  final String message;

  /// The wire's code, typed; [GraineErrorCode.unknown] when the server gave
  /// one this build does not know (see [codeName]) or none the status explains.
  final GraineErrorCode code;

  /// The code as the server said it, or null when it said none.
  final String? codeName;
  final int? statusCode;

  /// How long to wait before asking again, from `Retry-After`.
  final int? retryAfterSeconds;

  /// Null for a 2xx. [retryAfter] is the response's `Retry-After` header.
  static EmbedRefusal? of(int status, Map<String, Object?> body, {String? retryAfter}) {
    if (status >= 200 && status <= 299) return null;
    final said = Js.strOrEmpty(body['error']).trim();
    final rawCode = Js.strOrEmpty(body['code']).trim();
    final code = rawCode.isNotEmpty
        ? GraineErrorCode.fromWire(rawCode)
        : switch (status) {
            400 => GraineErrorCode.invalidRequest,
            401 => GraineErrorCode.invalidKey,
            403 => GraineErrorCode.originRefused,
            404 => GraineErrorCode.notFound,
            429 => GraineErrorCode.rateLimited,
            503 => GraineErrorCode.unavailable,
            _ => GraineErrorCode.unknown,
          };
    final wait = int.tryParse((retryAfter ?? '').trim());
    final message = switch (code) {
      GraineErrorCode.invalidKey => 'Publishable key was rejected. Check it against Embed & Widgets in the dashboard.',
      GraineErrorCode.originRefused => 'This agent does not accept connections from a mobile app yet. Add "app://" to '
          'its Allowed domains in the dashboard, under Embed & Widgets.',
      GraineErrorCode.rateLimited => said.isEmpty ? 'Too many requests. Try again in a moment.' : said,
      _ => said.isEmpty ? 'Request refused ($status)' : said,
    };
    return EmbedRefusal(message,
        code: code,
        codeName: rawCode.isEmpty ? null : rawCode,
        statusCode: status,
        retryAfterSeconds: wait == null || wait < 0 ? null : wait);
  }
}

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
    this.design,
    this.wsHost,
    this.identity,
    this.memory,
    this.calls,
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

  /// The design the brand chose, resolved by the server into light and dark
  /// tokens. Null from an older server — every surface then draws from
  /// [appearance], as before.
  final ResolvedDesign? design;

  /// Where the chat socket goes when there is no ticket. Null: the default host.
  final String? wsHost;

  /// Which trait identifies a user. Null from an older server, which means
  /// the `user_id` trait ([identitySetting]).
  final IdentitySetting? identity;

  /// The agent's memory switch; null from an older server.
  final MemorySetting? memory;

  /// Hosted ringing and what users may book; null from an older server.
  final CallsSetting? calls;

  /// [identity], or what a server that does not say means.
  IdentitySetting get identitySetting => identity ?? IdentitySetting.standard;

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
    final wsHost = data['wsHost'] is String ? (data['wsHost']! as String).trim() : '';
    return SessionConfig(
      agentId: agentId,
      webcallAgentId: webcall.isEmpty ? agentId : webcall,
      appearance: Js.asMap(data['appearance']) ?? <String, Object?>{},
      variables: Js.asMap(data['variables']) ?? <String, Object?>{},
      pageVersion: page.isEmpty ? null : page,
      declaredActions: declared,
      friction: Js.asMap(data['friction']),
      design: ResolvedDesign.fromJson(data['design']),
      wsHost: wsHost.isEmpty ? null : wsHost,
      identity: IdentitySetting.fromJson(data['identity']),
      memory: MemorySetting.fromJson(data['memory']),
      calls: CallsSetting.fromJson(data['calls']),
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
