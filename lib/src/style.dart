// Drawing helpers the SDK's widgets share. Not exported: an app with its own
// design system draws from the public state, not from these.
import 'dart:ui' as ui show ImageFilter;

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
/// did before designs. [design] is a widget's own; else the session's.
/// [scheme] is a widget's override ("light", "dark", "auto"). Reads the
/// device's brightness through MediaQuery, so a surface re-picks the moment
/// the device switches.
ThemeTokens? tokensFor(BuildContext context, {ResolvedDesign? design, String? scheme}) {
  final d = design ?? GraineInApp.maybeInstance?.design;
  if (d == null) return null;
  final b = MediaQuery.maybePlatformBrightnessOf(context);
  return d.pick(deviceDark: b == null ? null : b == Brightness.dark, scheme: scheme);
}

/// A design family the app bundles ([GraineConfig.fonts]), or null for the platform's font.
String? familyOf(String family) => Design.fontFamily(family, GraineInApp.maybeInstance?.config.fonts ?? const <String>[]);

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
/// whatever is behind, clipped to the corners, and the shadow stays outside
/// the clip.
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
  required Widget child,
}) {
  final outline = borderWidth > 0 ? Border.all(color: border, width: borderWidth) : null;
  if (glass == null) {
    return Container(
      key: key,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(color: color, borderRadius: radius, border: outline, boxShadow: shadows),
      child: child,
    );
  }
  return Container(
    key: key,
    margin: margin,
    decoration: BoxDecoration(borderRadius: radius, boxShadow: shadows),
    child: ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: glass.blur, sigmaY: glass.blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(color: color, borderRadius: radius, border: outline),
          child: child,
        ),
      ),
    ),
  );
}
