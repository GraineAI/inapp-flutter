/// The pure half of the SDK — no Flutter, no I/O, no platform — so every rule
/// here is proven by a plain `package:test` run (test/core_test.dart,
/// test/contract_test.dart). The Flutter half (GraineInApp, GraineVoice and
/// the widgets) is a thin shell around these.
library;

export 'appearance.dart';
export 'bar.dart';
export 'config.dart';
export 'context.dart';
export 'design.dart';
export 'fonts.dart';
export 'friction.dart';
export 'icons.dart';
export 'js.dart';
export 'loader.dart';
export 'loading.dart';
export 'logo.dart';
export 'masking.dart';
export 'placement.dart';
export 'protocol.dart';
export 'socket_trace.dart';
export 'svg_path.dart';
export 'variables.dart';
export 'version.dart';
export 'widget_flow.dart';
export 'widgets.dart';
export 'window_chrome.dart';
