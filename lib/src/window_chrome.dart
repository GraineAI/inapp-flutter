// The title bar a design with window chrome draws across the top of the chat
// window, the caption card and every component card. Not exported: those
// surfaces draw it themselves; the numbers are WindowChrome's, in the core.
import 'package:flutter/widgets.dart';

import 'core/core.dart';
import 'style.dart';

/// What a title bar draws with, resolved once per surface — or null, and then
/// the surface is the plain one it always was: the design's chrome is "none",
/// or there is no design at all.
@immutable
class ChromeLook {
  const ChromeLook({
    required this.fill,
    required this.border,
    required this.borderWidth,
    required this.titleStyle,
    required this.success,
  });

  /// Null unless [t] opens its surfaces as windows. The tokens give every
  /// colour (`surfaceRaised`, `border`, `textMuted`, `success`); a surface
  /// that lets the host override its own colours passes them in [fill],
  /// [border] and [muted], so the bar stays one piece with the card under it.
  static ChromeLook? of(ThemeTokens? t, {Color? fill, Color? border, Color? muted}) {
    if (t == null || !t.window) return null;
    final c = t.colors;
    return ChromeLook(
      fill: fill ?? tokenColor(c.surfaceRaised),
      border: border ?? tokenColor(c.border),
      borderWidth: t.shape.borderWidth,
      titleStyle: monospaceTitle(muted ?? tokenColor(c.textMuted), t.font.scale.caption),
      success: tokenColor(c.success),
    );
  }

  /// The bar's fill: `surfaceRaised`, solid — even when the design is glass.
  final Color fill;

  /// Its bottom outline, `borderWidth` wide.
  final Color border;
  final double borderWidth;

  /// The platform's monospace at `font.scale.caption`, in `textMuted`.
  final TextStyle titleStyle;

  /// The chat's online dot.
  final Color success;
}

/// The title's type: the platform's monospace at [size], in [color] — every
/// property explicit, so no host theme changes it.
TextStyle monospaceTitle(Color color, double size) => TextStyle(
      color: color,
      fontSize: size,
      fontWeight: FontWeight.w400,
      height: 1.2,
      fontFamily: WindowChrome.monospace,
      fontFamilyFallback: WindowChrome.monospaceFallback,
      decoration: TextDecoration.none,
    );

/// THE TITLE BAR (contract/DESIGN.md, "Window chrome"): [WindowChrome.barHeight]
/// high with its bottom outline, filled `surfaceRaised` under the surface's
/// own top corners; the three traffic lights 12 in from the left; the title
/// centred on the whole bar on one line — after the `success` dot while the
/// chat is [online] — and [trailing] (the chat window's chevron) at the right
/// end. Place it first inside the surface's outline, full width.
class WindowTitleBar extends StatelessWidget {
  const WindowTitleBar({
    super.key,
    required this.look,
    required this.surface,
    required this.title,
    required this.topRadius,
    this.online = false,
    this.trailing,
  });

  final ChromeLook look;
  final ChromeSurface surface;

  /// Already lower case — [WindowChrome.title].
  final String title;

  /// The surface's top corners, inside its outline ([WindowChrome.innerRadius]).
  final double topRadius;

  /// The chat is connected: a 6-point `success` dot before the title.
  final bool online;

  /// At the bar's right end: the chat window's collapse chevron.
  final Widget? trailing;

  /// The traffic light at [index]: 0 close, 1 minimise, 2 zoom.
  static Key lightKey(int index) => ValueKey<String>('graine-window-light-$index');

  /// The title's text.
  static const Key titleKey = ValueKey<String>('graine-window-title');

  /// The chat's online dot.
  static const Key onlineKey = ValueKey<String>('graine-window-online');

  @override
  Widget build(BuildContext context) {
    final line = look.borderWidth > 0 ? look.borderWidth : 0.0;
    final height = WindowChrome.barHeight(surface) - line;
    final size = WindowChrome.lightSize(surface);

    final lights = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < WindowChrome.lights.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: WindowChrome.lightsGap),
          Container(
            key: lightKey(i),
            width: size,
            height: size,
            decoration: BoxDecoration(color: tokenColor(WindowChrome.lights[i]), shape: BoxShape.circle),
          ),
        ],
      ],
    );

    Widget heading = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (online) ...<Widget>[
          Semantics(
            label: 'Online',
            child: Container(
              key: onlineKey,
              width: WindowChrome.onlineDot,
              height: WindowChrome.onlineDot,
              decoration: BoxDecoration(color: look.success, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: WindowChrome.onlineDotGap),
        ],
        Flexible(
          child: Text(
            title,
            key: titleKey,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: look.titleStyle,
          ),
        ),
      ],
    );
    if (title.isNotEmpty) heading = Semantics(header: true, child: heading);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          height: height > 0 ? height : 0,
          decoration: BoxDecoration(
            color: look.fill,
            borderRadius: BorderRadius.vertical(top: Radius.circular(topRadius)),
          ),
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: WindowChrome.titleInset(surface, chevron: trailing != null)),
                  child: Center(child: heading),
                ),
              ),
              // The window's controls in look only: nothing to announce.
              Positioned(
                left: WindowChrome.lightsInset,
                top: 0,
                bottom: 0,
                child: ExcludeSemantics(child: lights),
              ),
              if (trailing != null)
                Positioned(right: WindowChrome.chevronInset, top: 0, bottom: 0, child: Center(child: trailing)),
            ],
          ),
        ),
        // The bar's bottom outline.
        if (line > 0) Container(height: line, color: look.border),
      ],
    );
  }
}
