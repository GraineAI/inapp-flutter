## 0.1.0

First release.

- `GraineEngine` hosts Graine's voice engine once, above the navigator, so a call outlives every route.
- Screen context (`setScreen`), prompt variables (`identify`, `setVariables`) and in-app actions (`registerAction`), masked on the device before anything leaves it.
- Components the agent draws — product lists in five looks, plan comparisons, choices, calendar slots — with the dashboard's loader while one is on its way.
- `GraineAgentBar`: draggable, keyboard-aware, and says what the network is doing ("weak connection", "no connection", "reconnecting…").
- Tested against the same contract as the React Native, Android and iOS SDKs.
