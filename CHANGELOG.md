## 0.4.0

- Window chrome: the chat, caption and components open as desktop windows when the design says so — Desktop Buddy does. With the design's `chrome: "window"` (contract/DESIGN.md, "Window chrome"), a title bar runs across the top of each surface: solid `surfaceRaised` — even when the design is glass — with a `borderWidth` outline below it, under the surface's own top corners; 32 high on the chat window and components, 24 on the caption card. The traffic lights sit 12 in from the left (10 across, 8 on the caption, 6 apart, always #FF5F57, #FEBC2E and #28C840), and the title is centred on the whole bar on one line, in the platform's monospace at the caption size, `textMuted`, regular weight, lower case — clear of the lights. The chat window's title bar replaces its header: the heading, after the 6-point `success` dot while online and alone while offline, and the collapse chevron 12 in from the right end; no launcher mark. The caption card reads "captions". A component card's own title moves into its bar and is not drawn again in the body (its rows keep theirs; with no title, the lights stand alone), and its body is `surface`, so the `surfaceRaised` bar reads as a title bar — the white window under the grey bar (a host's own `GraineWidgetTheme.surface` still wins, for the body and the bar alike); the loader card and the answered line are unchanged. Every other design — and a server that does not send `chrome` — keeps the plain surfaces.
- `ThemeTokens.chrome` (`"none"` or `"window"`; absent or unknown is `"none"`) and `ThemeTokens.window`; `WindowChrome` and `ChromeSurface` carry the title bar's numbers for hosts drawing their own.

## 0.3.0

- The voice bar is the Garage's design, element by element (contract/DESIGN.md, "Voice bar"): a 60-point bar on the design's surface — translucent over a blur with glass — with its outline, `radius.xl` corners and the floating shadow, or the neo-brutalist solid offset, never blurred; the accent avatar with the launcher glyph (else the logo filling it, else the name's first letter); the name and the status line in the design's type; a four-bar meter beside "Listening" and "Speaking" that moves at the design's pace and stands still without motion or under reduce motion; the microphone in the accent (danger when muted, at 40% while it cannot act) that starts, mutes and retries; the end button that hangs up during a call and closes off one (`onClose`). The status words are the contract's, in its order and in sentence case — "Unavailable", "No connection", "Reconnecting…", "Needs microphone", "Couldn’t load · tap to retry", "Connecting…", "Muted", "Thinking…", "Speaking", "Weak connection", "Listening", "Tap to talk" — with the dashboard's loader and its words while the call connects, reconnects or the agent thinks. The caption card (with "YOU" over the customer's own lines) and the chat window rise into place at the design's pace.
- Icons in the design's style: the SDK's microphone, hang up, send, chat, call, chevron and close are painted from the dashboard's own path data, in the design's icon style (outline, sharp, filled, duotone) and stroke — no emoji anywhere on the bar.
- The design's typeface, loaded by the SDK: the faces a design draws with are fetched from `/api/embed/font` on the SDK's base URL, kept in the app's cache directory by URL (fetched once), registered with `FontLoader` and drawn as their own weight on the bar, the caption, the chat window, components, the launcher and the transcript. Until a face arrives — and if it never does — text is in the platform font at the design's weight. `GraineConfig.fonts` now lists families the app bundles itself, which win and are never fetched; `GraineInApp.fontFaces` names what has loaded.
- A glass surface paints its shadow only outside itself, as the dashboard's preview does, so a translucent bar never shows its own shadow through it.
- `GraineAgentBar`: `onClose`, `showCaptions`, and — for an agent offered as both a call and a chat — `chat` (a `GraineChatState` your app runs), `surface` and `onSurfaceChange`, which add the switch and the chat window (header, bubbles in the design's style, composer). `GraineVoice.phase` and `GraineVoice.error` (a misconfigured transport, said as "Unavailable"); `voiceBarStatus`, `callPhase`, `DesignFonts` and `SdkIcons` for hosts drawing their own.

## 0.2.0

- Draws the brand's design. The session now carries the design chosen in the dashboard, resolved into light and dark tokens; the bar, components and loaders draw from them (surfaces, outlines, corners, shadows or a solid offset, glass, type, motion, chips, buttons), picking light or dark as the brand fixed it or as the device is — and switching with the device. From a server without designs, everything looks exactly as before.
- `GraineLauncher`: a floating button in the design's shape and glyph. `GraineTranscriptView`: the conversation so far, in the design's bubbles.
- `GraineConfig.fonts`: the font families your app bundles. A design's font is used only when listed; otherwise the platform font.
- `GraineInApp.design`, `GraineInApp.tokens` and `tokensListenable`, for a host drawing its own UI.

## 0.1.1

- Back in the foreground, an idle engine is told to warm (`graine:warm`). The engine keeps a SIP registration warm so a tap costs only the call itself, but a phone drops that idle connection while the app is in the background, and the engine page is not reliably told by its own web view. The SDK now says so when the app returns — only when the page is ready, never during a call.
- Connecting is faster in the hosted engine itself — a warm tap connects in about 0.2 s — with no change to this package.

## 0.1.0

First release.

- `GraineEngine` hosts Graine's voice engine once, above the navigator, so a call outlives every route.
- Screen context (`setScreen`), prompt variables (`identify`, `setVariables`) and in-app actions (`registerAction`), masked on the device before anything leaves it.
- Components the agent draws — product lists in five looks, plan comparisons, choices, calendar slots — with the dashboard's loader while one is on its way.
- `GraineAgentBar`: draggable, keyboard-aware, and says what the network is doing ("weak connection", "no connection", "reconnecting…").
- Tested against the same contract as the React Native, Android and iOS SDKs.
