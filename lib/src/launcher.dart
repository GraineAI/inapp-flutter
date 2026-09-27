import 'package:flutter/widgets.dart';

import 'core/core.dart';
import 'glyph.dart';
import 'graine.dart';
import 'style.dart';

/// THE LAUNCHER — the floating button that stands for the agent.
///
/// For an app that wants a button at rest rather than the bar: a tap starts
/// the call, or does whatever [onPressed] says (show the bar, open a screen
/// of your own). Place it yourself, in a [Stack] or a Scaffold's
/// floatingActionButton slot; it sizes itself.
///
/// The brand's design draws it (contract/DESIGN.md, "Launcher"): 56 × 56 — a
/// `pill` 56 high and as wide as its label — filled with `accent`; the
/// design's glyph (or the brand's logo) in `onAccent` at 46% of the height;
/// corners by `shape.launcher` (`circle` fully round, `squircle` 30% of the
/// size, `rounded-square` `radius.lg`, `square` `radius.sm`); the floating
/// shadow, or — neo-brutalist — a solid `colors.text` copy offset by the hard
/// offset inside a `borderWidth` outline in `colors.text`. Without a design:
/// a circle in the dashboard's accent with its logo, else the SDK's mark.
class GraineLauncher extends StatelessWidget {
  const GraineLauncher({
    super.key,
    this.call,
    this.onPressed,
    this.label,
    this.design,
    this.scheme,
  });

  /// The call a tap starts. Default: [GraineInApp.instance]'s voice.
  final GraineCallState? call;

  /// What a tap does instead of starting the call.
  final VoidCallback? onPressed;

  /// A pill's words, and what a screen reader says. Default: the dashboard's
  /// heading, else "Talk to us".
  final String? label;

  /// The design to draw. Default: the session's ([GraineInApp.design]).
  final ResolvedDesign? design;

  /// "light", "dark" or "auto" (the device). Default: the design's own.
  final String? scheme;

  /// The button, for a test to find.
  static const Key launcherKey = ValueKey<String>('graine-launcher');

  GraineCallState? get _call => call ?? GraineInApp.maybeInstance?.voice;

  @override
  Widget build(BuildContext context) {
    final c = _call;
    final session = GraineInApp.maybeInstance?.sessionListenable;
    final listen = <Listenable>[if (c != null) c, if (session != null) session];
    if (listen.isEmpty) return _build(context, c);
    return ListenableBuilder(
      listenable: listen.length == 1 ? listen.single : Listenable.merge(listen),
      builder: (BuildContext context, Widget? _) => _build(context, c),
    );
  }

  Widget _build(BuildContext context, GraineCallState? c) {
    final app = GraineInApp.maybeInstance;
    final appearance = c?.appearance ?? app?.session?.appearance ?? const <String, Object?>{};
    final dash = Appearance.resolve(appearance, accent: Appearance.defaultAccent, heading: '', origin: app?.config.baseUrl);
    final words = label ?? (dash.heading.isNotEmpty ? dash.heading : 'Talk to us');
    final tokens = tokensFor(context, design: design, scheme: scheme);
    const double h = Design.launcherSize;
    final glyphSize = h * Design.launcherGlyphScale;

    final Color fill;
    final String inkHex;
    final String shape;
    final double radius;
    final List<BoxShadow> shadows;
    final Border? outline;
    final Widget mark;
    TextStyle? labelStyle;
    if (tokens != null) {
      final t = tokens;
      fill = tokenColor(t.colors.accent);
      inkHex = t.colors.onAccent;
      shape = t.shape.launcher;
      radius = Design.launcherRadius(shape, t.shape.radius, h);
      final hard = t.elevation.hardOffset;
      final text = tokenColor(t.colors.text);
      shadows = hard != null ? <BoxShadow>[hardShadowOf(hard, text)] : shadowsOf(t.elevation.floating);
      outline = hard != null && t.shape.borderWidth > 0 ? Border.all(color: text, width: t.shape.borderWidth) : null;
      mark = BrandMark(
        glyph: t.icons.launcher,
        colorHex: inkHex,
        size: glyphSize,
        stroke: t.icons.stroke,
        logoUrl: dash.logoUrl,
        name: words,
        origin: app?.config.baseUrl,
      );
      final f = t.font;
      labelStyle = textStyle(tokenColor(inkHex), f.scale.body,
          weight: f.weights.strong, letterSpacing: f.letterSpacing.body * f.scale.body, family: familyOf(f.body));
    } else {
      fill = colorOf(dash.accent) ?? colorOf(Appearance.defaultAccent)!;
      inkHex = readableHexOn(fill);
      shape = 'circle';
      radius = h / 2;
      shadows = const <BoxShadow>[BoxShadow(color: Color(0x4D000000), blurRadius: 16, offset: Offset(0, 6))];
      outline = null;
      // No name: the SDK's own mark when there is no logo, as the bar's avatar shows.
      mark = BrandMark(glyph: null, colorHex: inkHex, size: glyphSize, logoUrl: dash.logoUrl, name: '');
    }

    final pill = shape == 'pill';
    final decoration = BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(radius),
      border: outline,
      boxShadow: shadows,
    );
    final face = pill
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              mark,
              const SizedBox(width: 10),
              // As wide as its label — up to a point, so a long heading cannot span the screen.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(words, maxLines: 1, overflow: TextOverflow.ellipsis, style: labelStyle),
              ),
            ],
          )
        : mark;
    final padding = pill ? const EdgeInsets.symmetric(horizontal: 20) : EdgeInsets.zero;
    final motion = motionOf(context, tokens);
    // A pill is not aligned: an alignment would stretch it to the width it is offered.
    final box = motion == Duration.zero
        ? Container(
            height: h,
            width: pill ? null : h,
            padding: padding,
            alignment: pill ? null : Alignment.center,
            decoration: decoration,
            child: face,
          )
        : AnimatedContainer(
            duration: motion,
            curve: curveOf(tokens),
            height: h,
            width: pill ? null : h,
            padding: padding,
            alignment: pill ? null : Alignment.center,
            decoration: decoration,
            child: face,
          );

    return Tap(
      key: launcherKey,
      label: words,
      onTap: onPressed ??
          (c == null
              ? null
              : () {
                  if (!c.connected && !c.connecting) c.start();
                }),
      child: box,
    );
  }
}
