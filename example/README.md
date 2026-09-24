# graine_inapp example

The whole integration in one screen: `GraineInApp.init` in `main`, the engine
and the agent bar around the navigator, a KYC field reported with
`setScreen`, a registered action (`fill_pan`), a component area with
previews, a text field to raise the keyboard, and the bar's dragged position
persisted with `shared_preferences`.

```bash
flutter run --dart-define=GRAINE_PUBLISHABLE_KEY=pk_live_…   # default: the Android sample's key
```
