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
