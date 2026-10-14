// Drawing helpers the SDK's widgets share. Not exported: an app with its own
// design system draws from the public state, not from these.
import 'dart:math' as math;
import 'dart:ui' as ui show ImageFilter;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

import 'core/core.dart';
import 'graine.dart';

/// [c] at a fraction of its own alpha — through withAlpha and lerp, which
/// every Flutter from 3.19 on has and none has deprecated.
Color fade(Color c, double f) => Color.lerp(c.withAlpha(0), c, f.clamp(0.0, 1.0))!;

/// A dashboard colour (#rgb, #rrggbb, #aarrggbb), or null for anything else.
Color? colorOf(String? hex) {
  final v = Appearance.argb(hex);
  return v == null ? null : Color(v);
}

/// A CSS weight (100–900) as a FontWeight.
FontWeight weightOf(int w) {
  final i = ((w / 100).round() - 1).clamp(0, 8);
  return FontWeight.values[i];
}

/// Text with every property explicit, so no host theme (and no missing
/// Material ancestor) changes what the SDK draws. [family] null is the
/// platform's font.
TextStyle textStyle(Color color, double size,
        {int weight = 400, double? height, double? letterSpacing, String? family}) =>
    TextStyle(
      color: color,
      fontSize: size,
      fontWeight: weightOf(weight),
      height: height,
      letterSpacing: letterSpacing,
      fontFamily: family,
      decoration: TextDecoration.none,
    );

/// Whether the device is in dark mode, read without a Material theme.
bool deviceDark(BuildContext context) =>
    (MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light) == Brightness.dark;

// ── the design ──────────────────────────────────────────────────────────────

/// THE TOKENS A SURFACE DRAWS WITH, or null — and then it draws exactly as it
/// did before designs. [design] is a widget's own; else the session's — of
/// [app], the agent the surface draws (the default agent unless handed one).
/// [scheme] is a widget's override ("light", "dark", "auto"). Reads the
/// device's brightness through MediaQuery, so a surface re-picks the moment
/// the device switches.
ThemeTokens? tokensFor(BuildContext context, {ResolvedDesign? design, String? scheme, GraineInApp? app}) {
  final d = design ?? (app ?? GraineInApp.maybeInstance)?.design;
  if (d == null) return null;
  final b = MediaQuery.maybePlatformBrightnessOf(context);
  return d.pick(deviceDark: b == null ? null : b == Brightness.dark, scheme: scheme);
}

/// HOW TO SET TEXT IN A DESIGN [family] AT [weight] (contract/DESIGN.md, "Fonts"):
///
///  - the app bundles the family ([GraineConfig.fonts]) → that family, at the weight;
///  - the SDK has loaded a face of it ([GraineInApp.fontFaces]) → that face,
///    at normal weight: a loaded face IS its weight, and bold on top of a
///    bold face would embolden it twice;
///  - neither, yet or ever → the platform's font at the weight, silently.
({String? family, FontWeight weight}) faceOf(String family, int weight) {
  // The app's agents share one loader, and one app bundle: every agent's.
  final app = GraineInApp.maybeInstance;
  final own = Design.fontFamily(family, <String>{
    for (final g in GraineInApp.all.values) ...g.config.fonts,
  });
  if (own != null) return (family: own, weight: weightOf(weight));
  final face = DesignFonts.faceFor(family, weight);
  final name = face == null ? null : app?.fontFaces.value[face.key];
  if (name != null) return (family: name, weight: FontWeight.normal);
  return (family: null, weight: weightOf(weight));
}

/// [textStyle] in a design family: the face [faceOf] chooses for [weight].
TextStyle designText(Color color, double size, String family, int weight, {double? height, double? letterSpacing}) {
  final f = faceOf(family, weight);
  return TextStyle(
    color: color,
    fontSize: size,
    fontWeight: f.weight,
    height: height,
    letterSpacing: letterSpacing,
    fontFamily: f.family,
    decoration: TextDecoration.none,
  );
}

/// A design's letter spacing (em) at [size], in logical pixels — rounded as
/// the other SDKs round it; null for none.
double? em(double size, double em) {
  final v = (size * em * 100).roundToDouble() / 100;
  return v == 0 ? null : v;
}

/// A name's first letter, upper-cased — "A" when there is none: the avatar
/// and the chat's mark when there is neither a glyph nor a logo.
String initialOf(String name) {
  final t = name.trim();
  return t.isEmpty ? 'A' : String.fromCharCodes(t.runes.take(1)).toUpperCase();
}

/// What a surface redraws on: its own state, the session of [app] (the agent
/// it draws; the default agent unless handed one) arriving, the design's
/// typefaces landing — a face that loads after the first frame redraws
/// everything set in it — and whether the user can book a call.
Listenable surfaceListenable(List<Listenable?> own, {GraineInApp? app}) {
  final a = app ?? GraineInApp.maybeInstance;
  final all = <Listenable>[
    for (final l in own)
      if (l != null) l,
    if (a != null) a.sessionListenable,
    if (a != null) a.fontFaces,
    // Whether the user can book: the chat's "Book a call" comes and goes with it.
    if (a != null) a.bookingListenable,
  ];
  return all.length == 1 ? all.single : Listenable.merge(all);
}

/// The accent at chip strength for an accent chosen outside the design: the
/// same mix the design makes for its own — the accent a little way into the
/// surface (RN softFor).
Color softFor(Color accent, Color surface, {required bool dark}) => Color.lerp(surface, accent, dark ? 0.22 : 0.12)!;

/// The depth a raised surface wears: the solid offset copy in `colors.text`
/// when the design has one — never blurred — else [soft]'s shadow.
List<BoxShadow> raisedShadows(ThemeTokens t, ThemeShadow? soft, Color text) {
  final hard = t.elevation.hardOffset;
  return hard != null ? <BoxShadow>[hardShadowOf(hard, text)] : shadowsOf(soft);
}

/// A token colour. Tokens are normalised #RRGGBB, so this never falls through.
Color tokenColor(String hex) => colorOf(hex) ?? const Color(0xFF000000);

/// A design shadow as Flutter draws one; empty for none.
List<BoxShadow> shadowsOf(ThemeShadow? s) => s == null
    ? const <BoxShadow>[]
    : <BoxShadow>[
        BoxShadow(
          color: fade(tokenColor(s.color), s.opacity),
          offset: Offset(0, s.y),
          blurRadius: s.blur,
          spreadRadius: s.spread,
        ),
      ];

/// The solid offset copy a neo-brutalist design draws in `colors.text`.
BoxShadow hardShadowOf(ThemeOffset o, Color text) => BoxShadow(color: text, offset: Offset(o.x, o.y));

/// How long a transition takes: the design's, none without a design, and
/// none — always — when the platform asks for reduced motion.
Duration motionOf(BuildContext context, ThemeTokens? t) {
  if (t == null || t.motion.none) return Duration.zero;
  if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return Duration.zero;
  return Duration(milliseconds: t.motion.durationMs);
}

/// The design's easing. A spring overshoots by its bounce.
Curve curveOf(ThemeTokens? t) {
  final m = t?.motion;
  switch (m?.easing) {
    case 'linear':
      return Curves.linear;
    case 'emphasized':
      return const Cubic(0.05, 0.7, 0.1, 1);
    case 'spring':
      return m!.bounce > 0 ? Cubic(0.34, 1 + m.bounce * 1.8, 0.64, 1) : Curves.easeOutCubic;
    default:
      return const Cubic(0.2, 0, 0, 1);
  }
}

/// A foreground that reads on [bg], as #RRGGBB: dark ink on a light fill,
/// white on a dark one — the rule [Appearance.palette] uses for its onAccent.
String readableHexOn(Color bg) => bg.computeLuminance() > 0.45 ? '#101318' : '#FFFFFF';

/// THE PLATE UNDER THE BRAND'S LOGO (contract/DESIGN.md, "The brand's
/// logo"): the accent, or — for [LogoPlate.white] — white with a
/// `max(1, borderWidth)` hairline in [border]. Pass [LogoPlate.accent]
/// whenever the shape carries a glyph or a letter rather than the logo.
({Color color, Border? border}) logoPlateOf(LogoPlate plate,
    {required Color accent, required Color border, required double borderWidth}) {
  if (plate != LogoPlate.white) return (color: accent, border: null);
  return (
    color: tokenColor(BrandLogo.plateWhite),
    border: Border.all(color: border, width: BrandLogo.outlineWidth(borderWidth)),
  );
}

/// The ink for a glyph-less mark's letter (or a pill's label) on [plate]:
/// [onAccentHex] on the accent, dark ink on the white plate.
String inkOnPlate(LogoPlate plate, String onAccentHex) =>
    plate == LogoPlate.white ? BrandLogo.labelOnWhite : onAccentHex;

/// THE BRAND'S LOGO, WHOLE: fitted ([BoxFit.contain]) into a [box]-point
/// square — [BrandLogo.box] of its shape — centred, proportions kept, never
/// cropped. [fallback] stands in when it cannot load.
Widget logoWhole(String url, double box, {required Widget Function() fallback}) => Image.network(
      url,
      key: logoKey,
      width: box,
      height: box,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
      errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
          SizedBox(width: box, height: box, child: Center(child: fallback())),
    );

/// The brand's logo where it stands in for the launcher glyph, for a test to find.
const Key logoKey = ValueKey<String>('graine-logo');

/// A tappable area with a button's semantics and no Material dependency.
class Tap extends StatelessWidget {
  const Tap({super.key, required this.label, required this.onTap, required this.child, this.enabled = true});

  final String label;
  final VoidCallback? onTap;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final active = enabled && onTap != null;
    return Semantics(
      button: true,
      enabled: active,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: active ? onTap : null,
        child: child,
      ),
    );
  }
}

/// A SURFACE: its fill and outline, with its shadow outside. With [glass] the
/// fill is translucent (the caller has already faded it) over a blur of
/// whatever is behind, clipped to the corners — and the shadow is painted
/// only OUTSIDE the surface, as CSS paints a box-shadow in the dashboard's
/// preview: under a translucent fill, a shadow drawn whole would show through
/// it, and a neo-brutalist offset copy would grey the entire bar. [height]
/// is the whole surface's, outline included.
Widget surfaceBox({
  Key? key,
  required Color color,
  required Color border,
  required double borderWidth,
  required BorderRadius radius,
  required List<BoxShadow> shadows,
  ThemeGlass? glass,
  EdgeInsetsGeometry? padding,
  EdgeInsetsGeometry? margin,
  double? height,
  required Widget child,
}) {
  final outline = borderWidth > 0 ? Border.all(color: border, width: borderWidth) : null;
  if (glass == null) {
    return Container(
      key: key,
      margin: margin,
      padding: padding,
      height: height,
      decoration: BoxDecoration(color: color, borderRadius: radius, border: outline, boxShadow: shadows),
      child: child,
    );
  }
  return Container(
    key: key,
    margin: margin,
    child: CustomPaint(
      painter: OutsideShadowPainter(shadows: shadows, radius: radius),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: glass.blur, sigmaY: glass.blur),
          child: Container(
            padding: padding,
            height: height,
            decoration: BoxDecoration(color: color, borderRadius: radius, border: outline),
            child: child,
          ),
        ),
      ),
    ),
  );
}

/// Shadows painted only outside a rounded rectangle — for a translucent
/// surface, which must not show its own shadow through itself.
class OutsideShadowPainter extends CustomPainter {
  OutsideShadowPainter({required this.shadows, required this.radius});

  final List<BoxShadow> shadows;
  final BorderRadius radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (shadows.isEmpty) return;
    final rect = Offset.zero & size;
    final shape = radius.toRRect(rect);
    var reach = 0.0;
    for (final s in shadows) {
      reach = math.max(reach, s.offset.distance + s.blurRadius * 2 + s.spreadRadius.abs());
    }
    canvas.save();
    canvas.clipPath(Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(rect.inflate(reach + 1))
      ..addRRect(shape));
    for (final s in shadows) {
      canvas.drawRRect(shape.shift(s.offset).inflate(s.spreadRadius), s.toPaint());
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(OutsideShadowPainter old) => !listEquals(old.shadows, shadows) || old.radius != radius;
}
