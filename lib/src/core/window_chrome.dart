/// THE WINDOW CHROME, AS NUMBERS — `chrome: "window"` in a design's tokens
/// (contract/DESIGN.md, "Window chrome"), the playful-desktop look: the chat
/// window, the caption card and every component card open as desktop windows,
/// a title bar across the top with traffic lights at the left and a
/// monospaced, lower-case title in the middle. The chat window's title bar
/// replaces its header, with the collapse chevron at the right end; a
/// component's own title moves into its bar and leaves the body.
///
/// Everything a renderer measures lives here, so the title bar is proven by a
/// plain test and every SDK draws the same one. What the bar is filled and
/// outlined with comes from the tokens: solid `surfaceRaised` (glass or not),
/// and a bottom outline `borderWidth` in `border`, under the surface's own top
/// corners.
library;

import 'dart:math' as math;

/// Which surface wears the title bar — the caption card's is the small one.
enum ChromeSurface { chat, caption, component }

abstract final class WindowChrome {
  /// The title bar's height, its bottom outline included: 32 on the chat
  /// window and components, 24 on the caption card.
  static double barHeight(ChromeSurface surface) => surface == ChromeSurface.caption ? 24 : 32;

  /// The traffic lights sit this far in from the surface's left edge (inside
  /// its outline, as every padding in the contract is measured).
  static const double lightsInset = 12;

  /// Each light's diameter: 10, and 8 on the caption card.
  static double lightSize(ChromeSurface surface) => surface == ChromeSurface.caption ? 8 : 10;

  /// Between one light and the next.
  static const double lightsGap = 6;

  /// Close, minimise, zoom — always these three, whatever the design: they are
  /// the window's controls, not the brand's colours.
  static const List<String> lights = <String>['#FF5F57', '#FEBC2E', '#28C840'];

  /// The three lights, edge to edge.
  static double lightsWidth(ChromeSurface surface) => lightSize(surface) * lights.length + lightsGap * (lights.length - 1);

  /// The `success` dot before the chat's title while it is online, and the
  /// space between it and the heading. Offline, the heading stands alone.
  static const double onlineDot = 6;
  static const double onlineDotGap = 6;

  /// The chat window's collapse chevron at the bar's right end: an 18-point
  /// glyph in a 30-point target whose edge sits 6 in, so the glyph itself sits
  /// 12 in — the lights' inset, mirrored.
  static const double chevronIcon = 18;
  static const double chevronBox = 30;
  static const double chevronInset = 6;

  /// Clear space between the title and the lights (or the chevron).
  static const double titleGap = 8;

  /// How far the title keeps from BOTH ends of the bar: centred on the whole
  /// bar, and never running under the lights or the chevron.
  static double titleInset(ChromeSurface surface, {bool chevron = false}) {
    final left = lightsInset + lightsWidth(surface);
    final right = chevron ? chevronInset + chevronBox : 0.0;
    return math.max(left, right) + titleGap;
  }

  /// The platform's monospace — `monospace` where the platform names one
  /// (Android) — and where to look where it does not (Menlo on iOS).
  static const String monospace = 'monospace';
  static const List<String> monospaceFallback = <String>['Menlo', 'Roboto Mono', 'monospace'];

  /// The caption card's title.
  static const String captionTitle = 'captions';

  /// The title, lower case: the chat window shows the heading, the caption
  /// card "captions", a component card its own title — empty for a component
  /// without one, whose bar is the lights alone.
  static String title(ChromeSurface surface, {String heading = '', String componentTitle = ''}) {
    switch (surface) {
      case ChromeSurface.chat:
        return heading.trim().toLowerCase();
      case ChromeSurface.caption:
        return captionTitle;
      case ChromeSurface.component:
        return componentTitle.trim().toLowerCase();
    }
  }

  /// A surface's own top corner, inside its outline — the title bar's corners.
  static double innerRadius(double radius, double borderWidth) => math.max(0.0, radius - math.max(0.0, borderWidth));
}
