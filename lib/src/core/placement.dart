import 'dart:math' as math;

import 'js.dart';

/// The bounds a dragged bar is clamped to.
class PlacementBounds {
  const PlacementBounds({
    required this.windowHeight,
    required this.baseBottom,
    required this.barHeight,
    this.topMargin = 48,
  });

  /// The screen's height.
  final double windowHeight;

  /// Where the bar sits with no offset.
  final double baseBottom;

  /// The bar's rendered height, as last measured. 0 before the first layout.
  final double barHeight;

  /// Space to keep clear at the top — status bar, notch.
  final double topMargin;
}

/// WHERE THE BAR MAY SIT — arithmetic only, ported from the RN SDK's
/// placement-math.ts. The bar is anchored to the bottom; the customer drags
/// it and the result is an OFFSET above that anchor, clamped so the bar can
/// never leave the screen. Units are logical pixels, the same as the RN and
/// Android SDKs, so a persisted offset means the same on every platform.
abstract final class Placement {
  /// A drag that moved less than this (in both axes) is a tap, and the tap
  /// must still work.
  static const double dragSlop = 8;

  static int clampOffset(double offset, PlacementBounds b) {
    if (!offset.isFinite) return 0;
    final height = b.barHeight > 0 ? b.barHeight : 64.0;
    final maxOffset = math.max(0.0, b.windowHeight - b.topMargin - height - b.baseBottom);
    return Js.round(math.min(math.max(offset, 0.0), maxOffset)).toInt();
  }

  /// The offset during a drag: where it started plus how far the finger moved
  /// UP (dy grows downward, so it is subtracted).
  static int offsetDuringDrag(double startOffset, double dy, PlacementBounds b) =>
      clampOffset(startOffset - dy, b);

  static bool isTap(double dx, double dy) => dx.abs() < dragSlop && dy.abs() < dragSlop;
}

/// HOW FAR A BOTTOM-ANCHORED BAR MUST RISE TO STAY ABOVE THE KEYBOARD: the
/// keyboard's height minus whatever the window already shrank. In Flutter the
/// shrink is already folded into `MediaQuery.viewInsets` — a route that
/// resized for the keyboard reports a zero inset below it — so the bar passes
/// the inset it sees and 0.
abstract final class KeyboardLift {
  static int liftFor(double keyboardHeight, double windowShrink) {
    if (!(keyboardHeight > 0)) return 0;
    final shrink = windowShrink > 0 ? windowShrink : 0.0;
    return math.max(0.0, Js.round(keyboardHeight - shrink)).toInt();
  }
}
