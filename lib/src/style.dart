// Drawing helpers the SDK's widgets share. Not exported: an app with its own
// design system draws from the public state, not from these.
import 'package:flutter/widgets.dart';

import 'core/core.dart';

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
/// Material ancestor) changes what the SDK draws.
TextStyle textStyle(Color color, double size, {int weight = 400, double? height, double? letterSpacing}) =>
    TextStyle(
      color: color,
      fontSize: size,
      fontWeight: weightOf(weight),
      height: height,
      letterSpacing: letterSpacing,
      decoration: TextDecoration.none,
    );

/// Whether the device is in dark mode, read without a Material theme.
bool deviceDark(BuildContext context) =>
    (MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light) == Brightness.dark;

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
