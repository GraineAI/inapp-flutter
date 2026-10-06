import 'dart:math' as math;

/// WHAT THE BRAND'S LOGO SITS ON — contract/DESIGN.md, "The brand's logo".
///
/// A logo stands in for the launcher glyph on the launcher, the voice bar's
/// avatar and the chat header's mark. It used to be drawn filling its shape
/// (`cover`): a wordmark lost both ends, a square logo lost its corners to
/// the circle, and a logo drawn in the brand's own colour sat invisible on
/// the brand's own accent. The dashboard reads which plate a logo needs from
/// its pixels on upload, and the brand can change it.
enum LogoPlate {
  /// The shape's own fill — for a white or light logo made for a coloured
  /// background. The default, as logos were drawn before.
  accent,

  /// A white plate with a hairline — for a coloured or dark logo, or an
  /// opaque image, which is what most logo files are.
  white;

  /// `appearance.logoPlate` as the dashboard stores it: exactly "white" is
  /// white; anything else — absent, "WHITE", a number — is the accent, as
  /// the React Native SDK's normaliseLogoPlate reads it.
  static LogoPlate from(Object? value) => value == 'white' ? white : accent;

  /// The word on the wire.
  String get wire => name;
}

/// The fill under a logo, and its outline (none on the accent).
class LogoPlateLook {
  const LogoPlateLook({required this.fill, this.outlineWidth, this.outlineColor});

  /// "#RRGGBB": the accent, or [BrandLogo.plateWhite].
  final String fill;

  /// The hairline round a white plate; null for none.
  final double? outlineWidth;
  final String? outlineColor;

  bool get hasOutline => outlineWidth != null;

  @override
  bool operator ==(Object other) =>
      other is LogoPlateLook &&
      other.fill == fill &&
      other.outlineWidth == outlineWidth &&
      other.outlineColor == outlineColor;

  @override
  int get hashCode => Object.hash(fill, outlineWidth, outlineColor);

  @override
  String toString() => 'LogoPlateLook($fill${hasOutline ? ', $outlineWidth $outlineColor' : ''})';
}

/// The logo's geometry and plate — theme.ts's logoBox and logoPlateLook.
abstract final class BrandLogo {
  /// The white plate.
  static const String plateWhite = '#FFFFFF';

  /// A pill launcher's label on the white plate: the ink readable on white.
  static const String labelOnWhite = '#101318';

  /// THE SQUARE A LOGO IS FITTED INTO — whole, proportions kept, centred,
  /// never cropped — inside a shape [size] across (a pill: pass its height
  /// and "circle"). The largest square a circle holds is 70.7% of its
  /// diameter; a squircle is treated as a circle; `rounded-square` and
  /// `square` give 80% of the side. Rounded down, never up: a box rounded up
  /// pokes its corners past the circle.
  static int box(String shape, double size) {
    final k = shape == 'rounded-square' || shape == 'square' ? 0.8 : 0.7;
    return math.max(1, (size * k).floor());
  }

  /// The white plate's hairline: `max(1, borderWidth)` — a design without
  /// outlines still needs one, or a white plate vanishes on a white bar.
  static double outlineWidth(double borderWidth) => math.max(1, borderWidth).toDouble();

  /// The plate's fill and outline. [accent] and [border] are the design's
  /// colours (or the host's accent).
  static LogoPlateLook plateLook(LogoPlate plate,
      {required String accent, required String border, double borderWidth = 1}) {
    return plate == LogoPlate.white
        ? LogoPlateLook(fill: plateWhite, outlineWidth: outlineWidth(borderWidth), outlineColor: border)
        : LogoPlateLook(fill: accent);
  }
}
