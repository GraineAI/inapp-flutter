# graine_inapp — the Graine in-app agent for Flutter

An AI agent inside your app: it sees the screen you describe, acts through
the actions you register, draws components (product lists, choices, time
slots), and talks by voice.

The call runs in a page Graine hosts, inside a WebView this package owns — one
invisible pixel ([`GraineEngine`](lib/src/engine.dart)). Every audio-path fix
(TURN relay, dead-media watchdog, WebSocket fallback, connection quality)
ships in that page and reaches your installed app with no release. Dart
handles the session, prompt variables, screen context, actions, lifecycle and
UI. The wire protocol is the React Native SDK's, byte for byte, and the rules
(masking, quality, URL, components, placement, friction) are pinned to the RN
SDK's own answers by the files in `contract/`.

Integration guide: https://www.graine.ai/docs/in-app/flutter

## 1. Add it

```yaml
dependencies:
  graine_inapp: ^0.2.0
  permission_handler: ^11.0.0   # or whatever your app already uses for permissions
```

Flutter 3.19+ (Dart 3.3+). Dependencies: `webview_flutter` (+ its Android and
WebKit implementations) and `http` — nothing else.

### Android — `android/app/src/main/AndroidManifest.xml`

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
```

`minSdk` 24 or higher (the first Android whose system WebView reliably runs
WebRTC). A WebView cannot hold a permission the app does not: the app must be
granted `RECORD_AUDIO` at runtime — see `requestMicrophone` below.

### iOS — `ios/Runner/Info.plist`

```xml
<key>NSMicrophoneUsageDescription</key>
<string>The assistant listens when you talk to it.</string>
```

iOS 15+ lets the SDK answer the page's microphone request itself; earlier iOS
shows the system prompt.

### The dashboard

Agent → Embed & Widgets: copy the **publishable key**, and add `app://` to
**Allowed domains** — without it every request is refused (the SDK's error
says so). Declare the in-app actions your app registers.

## 2. Initialise — once, before `runApp`

```dart
import 'package:graine_inapp/graine_inapp.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  GraineInApp.init(GraineConfig(
    baseUrl: 'https://www.graine.ai',
    publishableKey: 'pk_live_…',
    variables: {'brand': 'Acme'},            // prompt {variables} known at build time
    appVersion: '4.2.0',
    debug: kDebugMode,                        // bridge messages + page console in the log
    // The app asks for the microphone; the SDK grants it to the engine page.
    requestMicrophone: () async => (await Permission.microphone.request()).isGranted,
  ));
  runApp(const MyApp());
}
```

Other options: `transport` (force `Transport.webrtc` / `.websocket`; default
is the dashboard's Call audio setting), `endOnBackground` (default true: a
call ends two seconds after the app leaves the foreground), `timing` (load
watchdog and retry ladder), `friction` (your layer of the stuck-customer rules),
`fonts` (the font families your app bundles — see Design below).

## 3. Place the engine and the bar — once, around the navigator

```dart
MaterialApp(
  builder: (context, child) => GraineEngine(
    child: Stack(children: [
      child!,
      GraineAgentBar(
        initialOffset: prefs.getInt('graine.bar'),              // where the customer left it
        onPlacementChange: (o) => prefs.setInt('graine.bar', o), // persist it; the SDK stores nothing
      ),
    ]),
  ),
  home: const HomeScreen(),
);
```

Place `GraineEngine` ONCE near the root: a call must outlive every screen, and
the agent's job is to move the customer between them. It loads the engine idle
at mount, so a tap is an INVITE away rather than a page load away.

`GraineAgentBar` is optional — a working default:

- names the network: *weak connection*, *no connection*, *reconnecting…*,
  *connecting…*, *listening*, *speaking*, *muted*, *tap to talk*,
  *couldn't load · tap to retry* (the call button retries);
- **draggable** up and down (a movement under 8 px is still a tap), clamped to
  the screen, restored from `initialOffset`, reported by `onPlacementChange`;
- **keyboard-aware**: rises by `MediaQuery.viewInsets.bottom` (0 below a route
  that already resized, so never a double lift);
- shows the live caption, and the agent's components above itself
  (`showComponents: false` to draw them elsewhere with `GraineWidgetView`);
- looks as the brand's design says (see Design below), or — from a server
  that predates designs — as Appearance says (accent, heading, logo,
  light/dark/auto, radius); `accent`, `name`, `avatarUrl`, `scheme`, `radius`
  override one thing each.

Draw your own instead from `GraineInApp.instance.voice` — a `ChangeNotifier`
implementing `GraineCallState` (`connected`, `connecting`, `ready`, `muted`,
`quality`, `online`, `reconnecting`, `connectivity`, `captions`, `caption`,
`agentSpeaking`, `micDenied`; `start()`, `end()`, `setMuted()`, `retry()`).

## 4. Tell the agent what is happening

```dart
final graine = GraineInApp.instance;

graine.identify({'name': user.name, 'plan': user.plan});   // null on sign-out
graine.setVariables({'cart_total': cart.total});           // merged; null under a key removes it

graine.setScreen(GraineScreen(
  'kyc_pan',
  title: 'PAN verification',
  journey: const GraineJourney('KYC', step: 2, of: 4, next: 'Selfie check'),
  fields: [
    GraineField('pan', label: 'PAN', value: pan,
        status: error != null ? FieldStatus.invalid : (pan.isEmpty ? FieldStatus.empty : FieldStatus.filled),
        error: error),
  ],
));
graine.track('otp_failed', {'attempt': 2});   // context, not an interruption; last ten kept
```

Report real values: PAN, card, phone, Aadhaar and email are masked on the
device before anything leaves it (`Masking.addRule` for your own formats). An
unchanged screen is not resent; bursts go out as one frame per 400 ms.

## 5. Let the agent act

```dart
final unregister = graine.registerAction('set_tenure', (args) async {
  final months = args['months'];
  if (months is! int) return const ActionResult.refused('No tenure was given.');
  await loan.setTenure(months);
  return ActionResult.ok('Tenure set to $months months.');
});
```

Handlers answer within six seconds or the agent is told the app did not
answer; a throw is an `error`, an unregistered name is `refused`. Tell the
truth — "ok" makes the agent say it is done. `checkActions()` lists what is
usable, undeclared and unhandled; log it once.

## 6. Components

`GraineWidgetView` draws what the agent shows: product lists in five looks
(gallery, cards, list, spotlight, compact; one or two columns), plan
comparisons, info cards, choices and quick actions as chips, calendar slots,
and — for a kind this build cannot draw — the agent's own fallback sentence.
Choosing one answers at once; `select: "many"` ticks up to `maxSelect` and
answers once ("Let's compare Creta and Seltos."). The dashboard's loader stands
where a component will appear, for at least 450 ms; the answer stays as one
line until the agent replies. A component's `on_select` runs your registered
action (or `open_screen` with a `path`) first.

## 7. Design

The brand chooses how the agent looks in the dashboard (Web components →
Design): a design philosophy and a few knobs. The session carries it already
resolved — every colour, size, radius, shadow and glyph, for light and dark —
and the SDK draws those tokens, so a new design reaches your installed app
without a release. The bar, components and loaders follow it; so do two
optional widgets:

- `GraineLauncher` — a floating button in the design's shape (circle,
  squircle, rounded square, square, or a pill with a label) and glyph; a tap
  starts the call, or runs `onPressed`.
- `GraineTranscriptView` — the conversation so far as the design's chat
  window, in its bubble style (filled, outline, minimal).

Light or dark follows the brand's choice, else the device, and switches with
it. The platform's reduce-motion setting always wins over the design's motion.

Fonts: a design may name a font family. The SDK uses it only if your app
bundles it and says so, otherwise the platform font — never a download,
never an error:

```dart
GraineInApp.init(GraineConfig(baseUrl: …, publishableKey: …, fonts: const ['Inter']));
```

Drawing your own UI? `GraineInApp.instance.tokens` is the set to draw with
right now (`tokensListenable` to redraw when the device switches);
`Design.glyphUrl(...)` builds the launcher glyph as an image.

## 8. Listen

```dart
class Analytics with GraineListener {
  @override void onCallState(bool connected, bool connecting) { … }
  @override void onError(String message) { … }   // loud for you, invisible to the customer
}
graine.addListener(Analytics());
```

Every callback is optional: session ready, call state, captions, components,
ended, mic denied, quality, network, reconnecting, transport, connectivity,
actions, friction, errors.

## Tests

```bash
flutter test          # core, contract (contract/*.json), the call on a fake page, the widgets on fakes
flutter analyze
```

`test/contract_test.dart` walks up to `contract/fixtures.json`,
`contract/rn-parity.json` and `contract/design.json` and must reproduce every
answer the React Native SDK produced; a missing file fails, it is never
skipped. `lib/src/core/` is
pure Dart (a test holds it to that).

## Example

`example/` — the bar, a component area with previews, a text field for the
keyboard lift, and a drag offset persisted with `shared_preferences`:

```bash
cd example && flutter run --dart-define=GRAINE_PUBLISHABLE_KEY=pk_live_…
```
