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
  graine_inapp: ^0.10.1
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
at mount, so a tap starts the call at once instead of waiting for a page load.

`GraineAgentBar` is optional — the voice bar the dashboard's Garage shows in
its phone preview, drawn by the SDK from the brand's design (see Design
below). Your app passes nothing about how it looks:

- the avatar with the design's launcher glyph (or the brand's logo — drawn
  whole, fitted into the circle and never cropped, on the plate the dashboard
  chose for it: the accent, or white with a hairline — or the name's first
  letter), the name, and a status line; the microphone starts a call, mutes
  it during one, retries a load that failed and places a new call after one
  that could not connect; the end button hangs up
  during a call and closes the bar off one (`onClose` hears both — hide the
  bar there, and bring it back with a `GraineLauncher`);
- names the network before the agent takes the blame: *Unavailable*,
  *No connection*, *Reconnecting…*, *Needs microphone*,
  *Couldn’t load · tap to retry*, *Couldn’t connect · tap to retry*,
  *Connecting…*, *Muted*, *Thinking…*, *Speaking*, *Weak connection*,
  *Listening*, *Tap to talk* — the dashboard's loader stands in for the words
  while it connects, reconnects or thinks, and a four-bar meter moves beside
  *Listening* and *Speaking* at the design's pace;
- says where a connect is: a retry or a switch to the other transport is the
  loader's *reconnecting* moment in the brand's own words, and a connect the
  customer has waited on for 4 s says *Still connecting…* — only while the
  brand's connecting words are the default *Connecting…*; a wording the brand
  chose is never replaced;
- **draggable** up and down (a movement under 8 px is still a tap), clamped to
  the screen, restored from `initialOffset`, reported by `onPlacementChange`;
- **keyboard-aware**: rises by `MediaQuery.viewInsets.bottom` (0 below a route
  that already resized, so never a double lift);
- shows the live caption (`showCaptions: false` to hide it), and the agent's
  components above itself (`showComponents: false` to draw them elsewhere
  with `GraineWidgetView`);
- **the chat**: an agent the dashboard offers as a chat, or as both a call and
  a chat (Embed & Widgets → mode), gets the SDK's own text chat — the bar
  offers the switch as the dashboard allows, draws the chat window in the
  design, ends the call before it opens the chat (one conversation at a time)
  and hangs the chat up when the customer leaves it. A typing bubble shows
  while the agent composes; messages typed offline stay on screen and go the
  moment it connects. Run your own chat instead with `chat:` (a
  `GraineChatState`), or none with `builtInChat: false`; `onSurfaceChange`
  tells you when the customer switches;
- from a server that predates designs it keeps the colours, corners and
  depth Appearance gave it (accent, heading, logo, light/dark/auto, radius);
  `accent`, `name`, `avatarUrl`, `scheme`, `radius` override one thing each.

Draw your own instead from `GraineInApp.instance.voice` — a `ChangeNotifier`
implementing `GraineCallState` (`connected`, `connecting`, `ready`, `muted`,
`quality`, `online`, `reconnecting`, `connectivity`, `captions`, `caption`,
`agentSpeaking`, `micDenied`; `start()`, `end()`, `setMuted()`, `retry()`),
plus `phase` (idle, connecting, reconnecting, thinking, speaking, listening),
the CC switch (`GraineCaptionsSwitch`: `captionsOn`, `setCaptionsOn()`, `clearCaptions()`),
`error`, and — as `GraineConnectProgress` — `connectStage` (registering,
dialling, retrying, switching, or null outside a connect), `slowConnect`
(after `GraineTiming.slowConnectMs`, 4 s by default, of a connect the customer
is waiting on: a call being placed, or a bar on screen — `viewOpened()` /
`viewClosed()` — while the page loads) and `callFailed` (nothing could carry
the call; a `start()` tries again). `voiceBarStatus(...)` gives the bar's
words for any state. The brand's logo arrives as `Appearance.resolve(...)`'s
`logoUrl` and `logoPlate` (`LogoPlate.accent` or `.white`); `BrandLogo.box`
and `BrandLogo.plateLook` give the square to fit it into and its plate.

## 4. Tell the agent what is happening

```dart
final graine = GraineInApp.instance;

graine.identify({'user_id': user.id, 'name': user.name, 'plan': user.plan});   // null on sign-out
graine.setVariables({'app_version': info.version});        // merged; null under a key removes it

graine.setScreen(GraineScreen(
  'signup_email',
  title: 'Your email address',
  journey: const GraineJourney('Sign-up', step: 2, of: 4, next: 'Choose a password'),
  fields: [
    GraineField('email', label: 'Email', value: email,
        status: error != null ? FieldStatus.invalid : (email.isEmpty ? FieldStatus.empty : FieldStatus.filled),
        error: error),
  ],
));
graine.updateField(GraineField('email', value: email, status: FieldStatus.filled));   // one field changed
graine.clearScreen('signup_email');           // in a screen's dispose: only if it is still the one described
graine.track('otp_failed', {'attempt': 2});   // context, not an interruption; last ten kept
graine.tap('help_button');                    // a control you name, as "tap:help_button"
```

Report real values: PAN, card, phone, Aadhaar and email are masked on the
device before anything leaves it (`Masking.addRule` for your own formats). An
unchanged screen is not resent; the first change goes out at once and a burst
after it as one more frame at the end of 400 ms. A screen's
`availableActions` are narrowed to the actions this build registered.
`GraineEngine` also tells the agent what the customer taps while a screen is
set — a control with an accessibility label (`Semantics(label: …)` or a
tooltip) by its label, anywhere else as "tap:screen" with where — at most two
a second (`GraineConfig(captureTaps: false)` to turn it off).

### Who the user is, and what the agent remembers

The agent's **Memory** settings (Agent → Memory, or Embed & Widgets → Users &
memory) name the trait that identifies a user — `user_id` unless they say
`email`, `phone` or a custom trait such as `customer_id`. Pass it in `identify`: that one value is also sent, unmasked,
only where Graine needs it to recognise the user, and never as a prompt
variable. A placeholder ("guest", "null", a masked value), a boolean or a
fraction identifies nobody, and such a conversation has no memory.

```dart
graine.identify({'user_id': user.id, 'name': user.name}, memory: user.allowsMemory);
graine.setMemory(false);            // this user's conversations are neither remembered nor recalled
final remembered = await graine.memories();   // List<GraineMemory>: what the agent remembers, newest first
final deleted = await graine.forgetMemory();  // how many memories were deleted
graine.identify(null);              // sign-out: this device is no longer theirs; their chat ends
final id = await graine.installId;  // this install's id, the same one the native call engine sends
```

The memory choice is kept on the device for each user, so it need not be
repeated. `memories()` and `forgetMemory()` work only from a device that is the
user's (`GraineException.code`: `identity_required`, `device_limit`). Identity
is fixed per conversation: a change reaches the next one; someone else signing
in without `identify(null)` first signs the last user out.

## 5. Let the agent act

```dart
final unregister = graine.registerAction('set_reminder', (args) async {
  final minutes = args['minutes'];
  if (minutes is! int) return const ActionResult.refused('No time was given.');
  await reminders.schedule(Duration(minutes: minutes));
  return ActionResult.ok('Reminder set for $minutes minutes from now.');
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
answers once ("Compare: Creta and Seltos"). The dashboard's loader stands
where a component will appear, for at least 450 ms; the answer stays as one
line until the agent replies. A component's `on_select` runs your registered
action (or `open_screen` with a `path`) first.

## 7. Design

The brand chooses how the agent looks in the dashboard (Web components →
Design): a design philosophy and a few knobs. The session carries it already
resolved — every colour, size, radius, shadow and glyph, for light and dark —
and the SDK draws those tokens, so a new design reaches your installed app
without a release. The voice bar is drawn element by element as the Garage
previews it (surface, outline, corners, the floating shadow or the solid
offset, glass, the meter, the SDK's icons in the design's icon style); the
components and loaders follow it too; so do two optional widgets:

- `GraineLauncher` — a floating button in the design's shape (circle,
  squircle, rounded square, square, or a pill with a label) and glyph — or
  the brand's logo, whole, on its plate; a tap starts the call, or runs
  `onPressed`.
- `GraineTranscriptView` — the conversation so far as the design's chat
  window, in its bubble style (filled, outline, minimal).

Light or dark follows the brand's choice, else the device, and switches with
it. The platform's reduce-motion setting always wins over the design's motion.
A design with window chrome (Desktop Buddy's, or any design with the knob on)
opens the chat window, the caption and the components as desktop windows — a
title bar with traffic lights and a monospaced, lower-case title.

Fonts: a design may name a typeface, and the SDK loads it by itself — the
faces the design draws with, from `<baseUrl>/api/embed/font`, kept in the
app's cache directory so each is fetched once — and redraws in it as it
lands. Until then, and if it never arrives, text is in the platform font at
the design's weight: never an error the customer sees. A family your app
already bundles is used instead, and never fetched:

```dart
GraineInApp.init(GraineConfig(baseUrl: …, publishableKey: …, fonts: const ['Inter']));
```

Drawing your own UI? `GraineInApp.instance.tokens` is the set to draw with
right now (`tokensListenable` to redraw when the device switches);
`GraineInApp.instance.fontFaces` names the design's faces the SDK has loaded
(set `fontFamily` to one with `FontWeight.normal` — a loaded face is its
weight); `Design.glyphUrl(...)` builds the launcher glyph as an image.

## 8. Chat

`GraineInApp.instance.chat` is the text chat — the same agent and context as
the call, in writing. `GraineAgentBar` opens it for you; for a chat screen of
its own:

```dart
Navigator.of(context).push(PageRouteBuilder<void>(
  pageBuilder: (context, _, __) => GraineChat(onClose: () => Navigator.of(context).pop()),
));
```

`GraineChat` fills the space it is given, opens the chat while it is on screen,
draws the components the agent shows above the composer, and keeps clear of
the status bar, the home indicator and the keyboard. The design's chat
settings — title, subtitle, avatar, placeholder, conversation starters,
timestamps, background and the header's and composer's colours — reach it
from the dashboard. While the user has calls booked, an **Upcoming calls**
card heads the conversation: the time in their own time zone, and Cancel. Drawing your own? `chat` is a `ChangeNotifier`:
`turns` (`GraineChatTurn`: `id`, `role`, `text`, `at`, `delivery` — sending,
sent, failed — `proactive`, `component`), `connected`, `connecting`,
`reconnecting` (a dropped chat being made again), `failed` (it gave up), `agentTyping`, `upcomingCalls`, `send()`, `open()`, `close()`,
`cancelUpcoming(id)`.

### Conversations continue

A user you `identify()` who comes back — later today, tomorrow, on their other
phone — finds the chat where they left it, and the agent picks up from there
instead of greeting them again. The chat opens with the recent messages (the
last 50, kept for a while after the last one), earlier calls show as one
"Voice call · 6:05 PM" row, and day lines say Today, Yesterday or the date.
Drawing your own chat? `turn.restored` marks a message from an earlier
conversation and `turn.channel` (`GraineChatChannel.chat`, `.voice`) where it
was said; `ChatRows.build(turns, now: …)` gives the rows to draw.
`await chat.newConversation()` starts a fresh thread (the chat window's header
offers it while an earlier conversation is on screen); what the agent
remembers about the user stays. `forgetMemory()` clears the chat on screen too.
Anonymous users, and those with memory off, start fresh every time; each agent
in your app keeps its own conversation.

### A bigger chat window

How big the bar's chat opens is set per agent in the dashboard — **Embed &
Widgets → Appearance → Chat window → Window size** — and `GraineAgentBar` draws
it with no code:

| Size | On a phone | On a tablet |
|---|---|---|
| Compact | The window above the bar, as always | The same |
| Large | A sheet over most of the screen, the app dimmed behind it; drag it down or tap outside to close | A panel 420 wide in the bottom corner |
| Full screen | The whole screen, closed with the chevron at the top left | The whole screen |

Your app can choose otherwise, for every chat or for one:

```dart
GraineInApp.init(const GraineConfig(baseUrl: 'https://www.graine.ai', publishableKey: 'pk_live_…',
    chatSize: GraineChatSize.large));

await GraineChat.open(context, size: GraineChatSize.full);   // opens the chat now, at this size, this once
```

The size passed to `GraineChat.open` wins for that open, then
`GraineConfig.chatSize`, then the dashboard's; the future completes when the
chat closes. With the agent's bar on screen, the bar moves to the chat and
draws it; switching between the call and the chat keeps the size. With no bar,
`GraineChat.open` shows the chat on your navigator — a sheet, a tablet's panel
or a screen of its own — and `compact`, which rides on the bar, opens as
`large`. The `GraineChat` widget stays as it is, for a chat you place yourself.

## 9. Calls the user books

When the agent allows it (Calls & scheduling → users may book), the user can
ask the agent to call them back — Graine rings their devices at that time:

```dart
final rules = graine.schedulingRules;                       // GraineSchedulingRules, from the dashboard
final call = await graine.scheduleCall(at: DateTime(2026, 10, 14, 18), reason: 'Follow-up');
final upcoming = await graine.scheduledCalls();             // List<GraineScheduledCall>, upcoming first
final status = await graine.cancelScheduledCall(call.id);   // GraineCallStatus.cancelled
```

The time is checked on the device first — `rules.usersCanBook`, and between
`rules.earliest(now)` and `rules.latest(now)` — then by Graine (the calling
hours, how many each user may have pending). A refusal is a `GraineException`
whose `code` (a `GraineErrorCode`) says why: `schedulingOff`, `tooSoon`,
`tooFar`, `outsideWindow`, `tooManyPending`, `rateLimited` (with
`retryAfterSeconds`), `network`… A `GraineScheduledCall` has `id`, `at`,
`status`, `source`, `reason`, `isUpcoming` and `canCancel`. The reason (at most
120 characters) is kept with the call for the agent and never put in the push
that rings it.

### Booking a call from your app

When your workspace has Graine ring its users and the agent lets them book,
the SDK draws the booking screen itself — "Call me at…" with no screen of your
own:

```dart
if (graine.bookingAvailable) {                 // rung here, booking on, the user identified
  final call = await GraineBooking.show(context, reason: 'Help with my settings');
  if (call != null) print('Booked ${call.id} for ${call.at}');   // null: closed without booking
}
```

The sheet is drawn in the agent's design, light or dark: the day (chips from
today to the furthest day the agent allows), the time (Flutter's own time
picker; a time the agent's rules do not allow moves to the nearest one that
they do), the phone's time zone, "What's it about? (optional)" — 120
characters; `reason` fills it — and **Book call**. A refusal stays in the sheet
as one line: "Pick a time at least 5 minutes from now", "Pick a time within 14
days", "That time is outside the hours we can call — pick another", "You
already have 3 calls booked — cancel one first", "Sign in to book a call",
"Couldn't book just now — try again". Once it is booked, the sheet says when
the agent will call, and Done closes it. A sheet on a phone, a centred panel on
a tablet; `GraineBookingSheet` is the same sheet for a route or a sheet of your
own. The time picker is Material's: an app with no `MaterialApp` still gets it.

`bookingAvailable` is each agent's own (`graine.bookingListenable` redraws a
widget when it changes): true only when Graine rings this phone (the
workspace's In-app calling, for this platform), the agent lets users book, and
the user is identified with the trait the agent's Identity setting names. The
SDK's chat window follows the same rule: **Book a call** under the booked calls
in its Upcoming calls card, or on its own in the card's place when none are
booked — and none when the design hides the booked-calls card.

## 10. Listen

```dart
class Analytics with GraineListener {
  @override void onCallState(bool connected, bool connecting) { … }
  @override void onError(String message) { … }   // loud for you, invisible to the customer
}
graine.addListener(Analytics());
```

Every callback is optional: session ready, call state, captions, components,
ended, mic denied, quality, network, reconnecting, transport, connectivity,
actions, friction, the agent volunteering in the chat, errors.

## 11. Several agents

One app can run several agents — each with its own publishable key — and
choose per screen which one the customer talks to: a support agent in Help, a
sales agent on Plans.

```dart
GraineInApp.init(const GraineConfig(baseUrl: 'https://www.graine.ai', publishableKey: 'pk_live_main'));
GraineInApp.init(const GraineConfig(baseUrl: 'https://www.graine.ai', publishableKey: 'pk_live_support'),
    name: 'support');

final support = GraineInApp.named('support')!;   // GraineInApp.instance is the default agent
support.registerAction('raise_ticket', (args) => const ActionResult.ok('Ticket raised'));

// The views take the agent they talk to:
GraineChat(app: support);
GraineAgentBar(app: support);

// One engine per agent the customer can call, nested near the root:
MaterialApp(
  builder: (context, child) => GraineEngine(
    app: support,
    child: GraineEngine(child: Stack(children: [child!, const GraineAgentBar()])),
  ),
);
```

- **Each agent has its own** session and design, chat, call, components,
  actions, prompt variables, and its own scheduling and memory requests.
- **Shared by every agent:** the install id; who is signed in —
  `identify(...)` on any agent identifies the user for all of them (each reads
  the trait its own Memory settings name), and `identify(null)`
  signs out everywhere; the user's memory choice; and the screen (`setScreen`,
  `track`, `tap`) — each agent tells it to its own conversation while one is
  live.
- **One conversation at a time:** starting a call or a chat with one agent
  ends a live one with another.
- **Engines:** each agent the customer can call needs its own `GraineEngine`,
  which keeps that agent's page loaded and idle, so a call starts at once
  whichever agent the screen offers. An agent you only chat with needs none.
- **Native calls:** `GraineCalls.instance.startCall(reason: 'question', agent: 'support')`;
  every agent configured under a name goes to the native engine with
  `configure`. A call Graine rings for one of them rings as that agent, in its
  call screen design, and its actions run in that agent's handlers —
  `GraineCallSnapshot.agent`, `GraineIncomingCall.agent` and
  `GraineCallOutcome.agent` say which.

An app with one agent changes nothing: `GraineInApp.init(config)` is the
default agent, and every view draws it.

## Calls like WhatsApp

From 0.6.1, `GraineCalls.instance` puts your agent in a native call: the
customer calls it from your app, or your agent rings the customer through a
push — CallKit and VoIP pushes on iOS, a ringing call notification and call
screen on Android — and the call goes on with the screen off. The audio runs
natively, with the platform's echo canceller.

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GraineInApp.init(const GraineConfig(baseUrl: 'https://www.graine.ai', publishableKey: 'pk_live_…'));
  final calls = GraineCalls.instance;
  await calls.configure(const GraineCallsOptions(publishableKey: 'pk_live_…', displayName: 'Acme Assistant'));
  calls.enableVoIPPushes((token) => myServer.saveVoipToken(token));   // iOS
  calls.attach();                                                      // your screen context and actions
  calls.outcomes.listen((o) => myServer.reportCall(o.callId, o.wire));
  runApp(const MyApp());
}

// A "Call support" button:
await GraineCalls.instance.startCall(reason: 'support');
```

- **iOS** — Signing & Capabilities: Push Notifications, and Background Modes →
  *Audio, AirPlay, and Picture in Picture* and *Voice over IP*. A real iPhone:
  CallKit and VoIP pushes do not run in the simulator.
- **Android** — nothing to add to the manifest: the plugin's declares the call
  screen, the microphone service, a Firebase messaging service and their
  permissions. For calls that ring, add Firebase to the Android app —
  `google-services.json` in `android/app`, the Google services Gradle plugin and
  `com.google.firebase:firebase-messaging` in `android/app/build.gradle.kts` —
  and the SDK registers for pushes itself, natively, with no Dart.
- **Already use `firebase_messaging`?** Its messaging service outranks the SDK's
  and receives every message: hand Graine's pushes to
  `GraineCalls.instance.handlePush(message.data)` from `onBackgroundMessage` and
  `onMessage`, and refreshed tokens to `registerPushToken` (`onTokenRefresh`).
- **Your call screen** — `callScreen: GraineCallScreen.sdk` (the default) shows
  the SDK's; with `GraineCallScreen.app`, draw your own from
  `GraineCalls.instance` (a `ValueListenable<GraineCallSnapshot>`), in the
  design's call colours (`GraineInApp.instance.tokens?.call`).
- **Graine rings your users** — when your workspace has uploaded its push
  credentials (Workspace settings → In-app calling), Graine itself rings the
  calls the agent or the user booked: on Android, Firebase in the app is all it
  takes (the SDK registers the device itself); on iOS `enableVoIPPushes` is all
  it takes. The SDK tells Graine what became of each
  ring, and who is signed in reaches the call as it does the chat.

### What the SDK does, what your app adds

**The SDK does by itself:** CallKit and VoIP pushes on iOS, the ringing call
notification and call screen on Android (its manifest merges every entry),
the call going on with the screen off, the microphone asked for when a call
starts without it, the device registered with Graine and every outcome
reported — and a check of your setup at `configure`, each problem logged once
with its fix (in Xcode's console and logcat, and printed once by `flutter run`
in a debug build).

**Your app adds:** on iOS the capabilities above and, in `ios/Runner/Info.plist`,
`NSMicrophoneUsageDescription` and `UIBackgroundModes` `audio` and `voip` — a
plugin cannot edit Info.plist, so the setup check names whichever is missing;
on Android, Firebase Cloud Messaging in the app (no messaging service of your
own); and one call to ask for
the permissions at a moment you choose (onboarding, a "Call me" screen). The
SDK never asks on its own at launch.

```dart
final p = await GraineCalls.instance.requestCallPermissions();
// p.microphone · p.notifications (Android 13+) · p.fullScreen (Android 14+), each
// granted · denied (not yet) · blocked (only Settings can change it) · notNeeded (iOS: CallKit rings)
if (p.fullScreen == GraineCallPermissionStatus.blocked) {
  // After a sentence of your own: "Allow full-screen calls so Acme can ring your locked phone."
  await GraineCalls.instance.openCallSettings(GraineCallPermission.fullScreen);
}
```

`callPermissions()` reads them at any time — again when the app returns to the
foreground, as the customer may have changed Settings; `allGranted` is true
when each is granted or not needed. On Android the SDK asks from a transparent
screen of its own, so nothing forwards a permission result.

**What is still missing**, in plain words — the same list the log shows:

```dart
for (final p in await GraineCalls.instance.callSetupProblems()) {
  debugPrint('${p.code}: ${p.message}');
}
```

iOS: `microphone_usage_missing`, `background_audio_missing`,
`background_voip_missing`, `push_entitlement_missing`, `voip_pushes_not_enabled`
(no `enableVoIPPushes` 15 seconds after `configure`), `no_voip_token`. Android:
`manifest_entry_missing`, `no_push_token` (no push token 15 seconds after
`configure`: Firebase missing or not set up in the Android app, or — with
`firebase_messaging` — no `registerPushToken`), `notifications_not_allowed`,
`full_screen_not_allowed`.
Both: `microphone_blocked`, `hosted_ringing_off` (Graine can't ring this phone:
no push credentials uploaded). A problem is never an exception: calls still
work where they can.

The push your server sends and the rest of the build:
https://www.graine.ai/docs/in-app/calling#flutter

### WebRTC calls

Calls carry their audio over a WebSocket unless you build with WebRTC. With
it, they carry it over WebRTC: a jitter buffer, loss concealment and a
connection that holds up better on mobile data. Nothing else changes — your
code, the ring, the call screen and the outcomes stay the same.

**iOS** — at the top of `ios/Podfile`:

```ruby
ENV['GRAINE_WEBRTC'] = '1'
```

**Android** — in `android/gradle.properties`:

```properties
graineWebRtc=true
```

On a build server, `GRAINE_WEBRTC=1` in the build's environment turns it on
for both. Then rebuild: `flutter build` runs `pod install` when the Podfile
changes — with only the environment variable, run `pod install` in `ios/` too.

- **Choose** with `GraineCallsOptions(callTransport: …)`:
  `GraineCallTransport.auto` (the default — WebRTC in a build that has it),
  `.websocket` or `.webrtc`. The agent's **In-app call audio** setting in the
  dashboard can switch WebRTC off for every install at once, without a release.
- **If WebRTC cannot set up a call**, the call goes on over the WebSocket inside
  the same ring and call screen: no second ring, no error. The snapshot says
  which one carried it — `transport` (`GraineCallTransport.webrtc` or
  `.websocket`) and `transportFallbackReason` (why a call that tried WebRTC is
  on the WebSocket: `no_answer`, `ice_timeout`, …).
- **Sound:** the agent's voice arrives at telephone bandwidth over WebRTC
  today — steadier on a weak network, narrower than the WebSocket's on a
  perfect one.
- **Size:** a prebuilt WebRTC library, per phone: about 12 MB installed on an
  iPhone, about 7.4 MB on a 64-bit Android phone. Its symbols are renamed, so it
  never clashes with another copy of WebRTC in your app (flutter_webrtc, a
  video-calling SDK); CocoaPods installs one version of this build, so a library
  that pins it at another version cannot be installed beside it.
- **Android** adds `ACCESS_NETWORK_STATE` to your manifest (a normal
  permission: nothing is asked). The R8 rules ship with the plugin.
- **Licences:** WebRTC is BSD 3-Clause with Google's patent grant — list it in
  your app's open-source licences.

## Tests

```bash
flutter test          # core, contract (contract/*.json), the call on a fake page, native calls on a mocked channel, the widgets on fakes
flutter analyze
```

`test/contract_test.dart` walks up to `contract/fixtures.json`,
`contract/rn-parity.json` and `contract/design.json` and must reproduce every
answer the React Native SDK produced — down to the faces and font URLs each
design loads and the SDK's icon paths; a missing file fails, it is never
skipped. `lib/src/core/` is pure Dart (a test holds it to that), and no test
reaches a network host: font files come from a mock HTTP client.

## Example

`example/` — the bar, a component area with previews, a text field for the
keyboard lift, and a drag offset persisted with `shared_preferences`:

```bash
cd example && flutter run --dart-define=GRAINE_PUBLISHABLE_KEY=pk_live_…
```
