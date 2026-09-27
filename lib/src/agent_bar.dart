import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'core/core.dart';
import 'glyph.dart';
import 'graine.dart';
import 'loader_view.dart';
import 'style.dart';
import 'widget_view.dart';

/// THE DEFAULT AGENT BAR — a working UI, not a requirement.
///
/// A bar rather than a sheet: the agent can see the screen and tell the
/// customer what to tap, and a sheet would cover the very thing it is talking
/// about. It says the network's name out loud — "weak connection", "no
/// connection", "reconnecting…" — because a customer whose agent goes quiet
/// on a train reads "listening" and concludes the agent is broken.
///
/// One unit, bottom up: the bar, the live caption, and the components the
/// agent draws ([GraineWidgetView]) — so a card sits on the bar and moves
/// with it.
///
///  - The DASHBOARD decides how it looks: the brand's design when the
///    session carries one (surface, outline, corners, shadow, glass, type,
///    motion — contract/DESIGN.md, "Voice bar"), else Appearance (accent,
///    heading, logo, light/dark/auto, radius). [accent], [name], [avatarUrl],
///    [scheme] and [radius] override one thing each.
///  - The CUSTOMER decides where it sits: drag it up or down; a movement under
///    8 logical pixels is still a tap. Restore a saved spot with
///    [initialOffset]; hear about a new one in [onPlacementChange] and persist
///    it — the SDK has no storage of its own.
///  - The KEYBOARD never covers it: it rises by the keyboard inset it is given
///    (`MediaQuery.viewInsets`), which a route that already resized reports as 0.
///
/// Place it in a [Stack] over the app — for example next to the navigator in
/// `MaterialApp.builder`. It fills its parent and lets touches through
/// everywhere but on itself.
class GraineAgentBar extends StatefulWidget {
  const GraineAgentBar({
    super.key,
    this.call,
    this.components,
    this.accent,
    this.name,
    this.avatarUrl,
    this.scheme,
    this.radius,
    this.design,
    this.bottomInset = 96,
    this.horizontalInset = 12,
    this.draggable = true,
    this.initialOffset,
    this.onPlacementChange,
    this.keyboardAware = true,
    this.showComponents = true,
    this.topMargin,
  });

  /// The call to draw. Default: [GraineInApp.instance]'s voice.
  final GraineCallState? call;

  /// The components to draw above the bar. Default: [GraineInApp.instance]'s.
  final GraineComponents? components;

  /// #RRGGBB for the avatar, the call button and components. Default: the dashboard's accent.
  final String? accent;

  /// The name beside the status. Default: the dashboard's heading, else "Assistant".
  final String? name;

  /// A face. Default: the dashboard's logo, else a glyph on the accent.
  final String? avatarUrl;

  /// "light", "dark" or "auto" (the device). Default: the design's, else the dashboard's theme.
  final String? scheme;

  /// Corner rounding for the caption and components. Default: the design's, else the dashboard's radius.
  final double? radius;

  /// The design to draw. Default: the session's ([GraineInApp.design]); with
  /// none, the bar looks as it did before designs.
  final ResolvedDesign? design;

  /// Where the bar sits with no offset: above your tab bar.
  final double bottomInset;
  final double horizontalInset;

  /// Let the customer drag it up and down. The offset is 0 while off.
  final bool draggable;

  /// A position the app persisted, in logical pixels above the anchor.
  final int? initialOffset;

  /// The customer let go somewhere new. Persist it and pass it back as [initialOffset].
  final ValueChanged<int>? onPlacementChange;

  /// Rise above the soft keyboard. Turn off only if your layout already does.
  final bool keyboardAware;

  /// Mount a [GraineWidgetView] above the bar.
  final bool showComponents;

  /// Space to keep clear at the top. Default: 48, or the status bar and 8 if taller.
  final double? topMargin;

  /// The bar itself — the pill with the avatar and the buttons.
  static const Key barKey = ValueKey<String>('graine-bar');

  /// The call / end / retry button.
  static const Key callButtonKey = ValueKey<String>('graine-call');

  /// The mute button (shown during a call).
  static const Key muteButtonKey = ValueKey<String>('graine-mute');

  /// The status line.
  static const Key statusKey = ValueKey<String>('graine-status');

  /// The live caption above the bar.
  static const Key captionKey = ValueKey<String>('graine-caption');

  @override
  State<GraineAgentBar> createState() => _GraineAgentBarState();
}

/// Everything the bar draws with, resolved once: the design's tokens, or —
/// with no design — ui.tsx's two palettes exactly as before.
class _BarLook {
  _BarLook({
    required this.surface,
    required this.border,
    required this.borderWidth,
    required this.text,
    required this.sub,
    required this.chip,
    required this.danger,
    required this.accent,
    required this.onAccent,
    required this.onDanger,
    required this.micFill,
    required this.micInk,
    required this.barRadius,
    required this.captionRadius,
    required this.barShadows,
    required this.captionShadows,
    required this.nameStyle,
    required this.statusStyle,
    required this.captionStyle,
    required this.glyphInk,
    required this.glyphInkHex,
    this.glass,
    this.tokens,
  });

  /// Before designs: ui.tsx's palettes, the accent and radius from Appearance.
  factory _BarLook.appearance({required bool dark, required Color accent, required double radius}) {
    final surface = dark ? const Color(0xFF17161A) : const Color(0xFFFFFFFF);
    final text = dark ? const Color(0xFFF2F3F5) : const Color(0xFF16181C);
    final sub = dark ? const Color(0xFF9AA0A6) : const Color(0xFF61666D);
    final chip = dark ? const Color(0x14FFFFFF) : const Color(0x0D000000);
    final danger = dark ? const Color(0xFFE5484D) : const Color(0xFFD32F2F);
    return _BarLook(
      surface: surface,
      border: dark ? const Color(0x17FFFFFF) : const Color(0x1A000000),
      borderWidth: 1,
      text: text,
      sub: sub,
      chip: chip,
      danger: danger,
      accent: accent,
      onAccent: text,
      onDanger: text,
      micFill: chip,
      micInk: text,
      barRadius: math.min(26, radius + 8),
      captionRadius: radius,
      barShadows: const <BoxShadow>[BoxShadow(color: Color(0x4D000000), blurRadius: 16, offset: Offset(0, 6))],
      captionShadows: const <BoxShadow>[BoxShadow(color: Color(0x2E000000), blurRadius: 12, offset: Offset(0, 4))],
      nameStyle: textStyle(text, 15, weight: 800),
      statusStyle: textStyle(sub, 12.5),
      captionStyle: textStyle(text, 15, weight: 600, height: 1.4),
      glyphInk: const Color(0xFFFFFFFF),
      glyphInkHex: '#FFFFFF',
    );
  }

  /// The design's "Voice bar": `surface` (translucent over a blur with glass),
  /// a `borderWidth` outline in `border`, `radius.xl` corners, the floating
  /// shadow; the status line `textMuted` at the caption size; the microphone
  /// `accent`/`onAccent`, fully round; the end button `danger`/white.
  factory _BarLook.design(ThemeTokens t, {Color? accent, double? radius}) {
    final c = t.colors;
    final a = accent ?? tokenColor(c.accent);
    // The design's onAccent was chosen for the design's accent; a host's own accent gets ink by luminance.
    final onAHex = accent == null ? c.onAccent : readableHexOn(accent);
    final onA = tokenColor(onAHex);
    final text = tokenColor(c.text);
    final muted = tokenColor(c.textMuted);
    final f = t.font;
    final heading = familyOf(f.heading);
    final body = familyOf(f.body);
    final floating = shadowsOf(t.elevation.floating);
    return _BarLook(
      surface: t.glass == null ? tokenColor(c.surface) : fade(tokenColor(c.surface), t.glass!.surfaceOpacity),
      border: tokenColor(c.border),
      borderWidth: t.shape.borderWidth,
      text: text,
      sub: muted,
      chip: tokenColor(c.accentSoft),
      danger: tokenColor(c.danger),
      accent: a,
      onAccent: onA,
      onDanger: const Color(0xFFFFFFFF),
      micFill: a,
      micInk: onA,
      barRadius: radius != null ? math.min(26, radius + 8) : t.shape.radius.xl,
      captionRadius: radius ?? t.shape.radius.lg,
      barShadows: floating,
      captionShadows: floating,
      nameStyle: textStyle(text, f.scale.body,
          weight: f.weights.title, letterSpacing: f.letterSpacing.title * f.scale.body, family: heading),
      statusStyle: textStyle(muted, f.scale.caption, weight: f.weights.body, family: body),
      captionStyle: textStyle(text, f.scale.body,
          weight: f.weights.strong,
          height: f.lineHeight.body,
          letterSpacing: f.letterSpacing.body * f.scale.body,
          family: body),
      glyphInk: onA,
      glyphInkHex: onAHex,
      glass: t.glass,
      tokens: t,
    );
  }

  final Color surface;
  final Color border;
  final double borderWidth;
  final Color text;
  final Color sub;

  /// Quiet fills: the avatar's backing behind a logo.
  final Color chip;
  final Color danger;
  final Color accent;

  /// Ink on [accent], and on [danger].
  final Color onAccent;
  final Color onDanger;

  /// The microphone (mute) button while it is live.
  final Color micFill;
  final Color micInk;
  final double barRadius;
  final double captionRadius;
  final List<BoxShadow> barShadows;
  final List<BoxShadow> captionShadows;
  final TextStyle nameStyle;
  final TextStyle statusStyle;
  final TextStyle captionStyle;

  /// The avatar's glyph, on the accent.
  final Color glyphInk;
  final String glyphInkHex;
  final ThemeGlass? glass;

  /// Null before designs.
  final ThemeTokens? tokens;

  /// The bar's surfaces — the bar, the caption — in its fill, outline and glass.
  Widget box({Key? key, required double radius, required List<BoxShadow> shadows,
          required EdgeInsetsGeometry padding, EdgeInsetsGeometry? margin, required Widget child}) =>
      surfaceBox(
        key: key,
        color: surface,
        border: border,
        borderWidth: borderWidth,
        radius: BorderRadius.circular(radius),
        shadows: shadows,
        glass: glass,
        padding: padding,
        margin: margin,
        child: child,
      );
}

class _GraineAgentBarState extends State<GraineAgentBar> {
  final GlobalKey _unitKey = GlobalKey();
  late int _offset = widget.initialOffset ?? 0;
  double _barHeight = 0;
  bool _dragging = false;
  int _dragStart = 0;
  double _dragOriginY = 0;

  GraineCallState get _call => widget.call ?? GraineInApp.instance.voice;
  GraineComponents? get _components => widget.components ?? GraineInApp.maybeInstance?.components;

  @override
  void didUpdateWidget(GraineAgentBar old) {
    super.didUpdateWidget(old);
    // A restored position arriving later (read from storage after the first frame).
    if (widget.initialOffset != old.initialOffset && widget.initialOffset != null && !_dragging) {
      _offset = widget.initialOffset!;
    }
  }

  double _topMargin(BuildContext context) =>
      widget.topMargin ?? math.max(48, MediaQuery.paddingOf(context).top + 8);

  PlacementBounds _bounds(BuildContext context) => PlacementBounds(
        windowHeight: MediaQuery.sizeOf(context).height,
        baseBottom: widget.bottomInset,
        barHeight: _barHeight,
        topMargin: _topMargin(context),
      );

  void _measure() {
    final size = _unitKey.currentContext?.size;
    if (size != null && size.height > 0) _barHeight = size.height;
  }

  void _onDragStart(DragStartDetails d) {
    _measure();
    _dragging = true;
    _dragStart = Placement.clampOffset(_offset.toDouble(), _bounds(context));
    _dragOriginY = d.globalPosition.dy;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_dragging) return;
    setState(() {
      _offset = Placement.offsetDuringDrag(_dragStart.toDouble(), d.globalPosition.dy - _dragOriginY, _bounds(context));
    });
  }

  void _onDragEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    final next = Placement.clampOffset(_offset.toDouble(), _bounds(context));
    setState(() => _offset = next);
    if (next != _dragStart) widget.onPlacementChange?.call(next);
  }

  void _onDragCancel() {
    if (!_dragging) return;
    _dragging = false;
    setState(() => _offset = _dragStart);
  }

  @override
  Widget build(BuildContext context) {
    final call = _call;
    final session = GraineInApp.maybeInstance?.sessionListenable;
    return ListenableBuilder(
      listenable: session == null ? call : Listenable.merge(<Listenable>[call, session]),
      builder: (BuildContext context, Widget? _) => _build(context, call),
    );
  }

  Widget _build(BuildContext context, GraineCallState call) {
    final appearance = call.appearance;
    final dash = Appearance.resolve(appearance,
        accent: Appearance.defaultAccent, heading: 'Assistant', origin: GraineInApp.maybeInstance?.config.baseUrl);
    final ownAccent = (widget.accent != null && Appearance.argb(widget.accent) != null) ? colorOf(widget.accent) : null;
    final tokens = tokensFor(context, design: widget.design, scheme: widget.scheme);
    final _BarLook p;
    if (tokens != null) {
      p = _BarLook.design(tokens, accent: ownAccent, radius: widget.radius);
    } else {
      final theme = widget.scheme ?? Js.strOrEmpty(appearance['theme']);
      p = _BarLook.appearance(
        dark: Appearance.isDark(theme.isEmpty ? 'auto' : theme, deviceDark(context)),
        accent: ownAccent ?? colorOf(dash.accent) ?? colorOf(Appearance.defaultAccent)!,
        radius: widget.radius ?? dash.radius,
      );
    }
    final accent = p.accent;
    final loader = Loaders.resolve(appearance['loader']);
    final loaderColor = colorOf(loader.color) ?? accent;
    final name = widget.name ?? dash.heading;
    final avatar = widget.avatarUrl ?? dash.logoUrl;
    final motion = motionOf(context, tokens);
    final curve = curveOf(tokens);

    // Where it sits: the anchor, the customer's offset, the keyboard — and
    // never past the top margin however they add up.
    final bounds = _bounds(context);
    final offset = widget.draggable ? Placement.clampOffset(_offset.toDouble(), bounds) : 0;
    final lift = widget.keyboardAware
        ? KeyboardLift.liftFor(MediaQuery.viewInsetsOf(context).bottom, 0).toDouble()
        : 0.0;
    final height = _barHeight > 0 ? _barHeight : 64.0;
    final maxBottom = math.max(0.0, bounds.windowHeight - bounds.topMargin - height);
    final bottom = math.min(widget.bottomInset + offset + lift, math.max(widget.bottomInset, maxBottom));

    final status = agentBarStatus(
      connectivity: call.connectivity,
      online: call.online,
      reconnecting: call.reconnecting,
      connecting: call.connecting,
      ready: call.ready,
      muted: call.muted,
      connected: call.connected,
      quality: call.quality,
      agentSpeaking: call.agentSpeaking,
      micDenied: call.micDenied,
    );
    // While it is coming up the status line IS the loader the brand chose.
    final waiting = status == 'connecting…' || status == 'reconnecting…';
    final live = call.connected || call.connecting;
    final failed = call.connectivity == GraineConnectivity.failed;
    final caption = call.caption;
    final showCaption = call.connected && caption != null && caption.text.trim().isNotEmpty;
    final components = widget.showComponents ? _components : null;

    Widget round({
      required Key key,
      required String glyph,
      required String label,
      required Color fill,
      required Color ink,
      required VoidCallback onTap,
    }) {
      final face = Text(glyph, style: textStyle(ink, 16, height: 1));
      final decoration = BoxDecoration(color: fill, shape: BoxShape.circle);
      return Tap(
        key: key,
        label: label,
        onTap: onTap,
        // A call starting or a mute going on eases between its colours, at the design's pace.
        child: motion == Duration.zero
            ? Container(width: 38, height: 38, alignment: Alignment.center, decoration: decoration, child: face)
            : AnimatedContainer(
                duration: motion,
                curve: curve,
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: decoration,
                child: face,
              ),
      );
    }

    final bar = p.box(
      key: GraineAgentBar.barKey,
      radius: p.barRadius,
      shadows: p.barShadows,
      padding: const EdgeInsets.all(8),
      child: Row(
        children: <Widget>[
          _avatar(avatar, name, p),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: p.nameStyle),
                const SizedBox(height: 1),
                Semantics(
                  key: GraineAgentBar.statusKey,
                  label: 'Agent status',
                  value: status,
                  child: ExcludeSemantics(
                    child: waiting
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              GraineLoaderView(
                                  look: loader, color: loaderColor, trackColor: p.border, size: 12, logoUrl: dash.logoUrl),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, style: p.statusStyle),
                              ),
                            ],
                          )
                        : Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, style: p.statusStyle),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 11),
          if (call.connected) ...<Widget>[
            round(
              key: GraineAgentBar.muteButtonKey,
              glyph: call.muted ? '🔇' : '🎙',
              label: call.muted ? 'Unmute' : 'Mute',
              fill: call.muted ? p.danger : p.micFill,
              ink: call.muted ? p.onDanger : p.micInk,
              onTap: () => call.setMuted(!call.muted),
            ),
            const SizedBox(width: 8),
          ],
          round(
            key: GraineAgentBar.callButtonKey,
            glyph: failed ? '↻' : (live ? '✕' : '📞'),
            label: failed ? 'Try again' : (live ? 'End call' : 'Start a call'),
            fill: live ? p.danger : accent,
            ink: live ? p.onDanger : p.onAccent,
            onTap: () {
              if (failed) {
                call.retry();
              } else if (live) {
                call.end();
              } else {
                call.start();
              }
            },
          ),
        ],
      ),
    );

    final unit = Column(
      key: _unitKey,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (components != null)
          GraineWidgetView(
            components: components,
            accent: widget.accent,
            radius: widget.radius,
            scheme: widget.scheme,
            appearance: appearance,
            design: widget.design,
            maxHeight: math.max(160, (bounds.windowHeight - bottom - bounds.topMargin - height - 16) * 0.9),
          ),
        if (showCaption)
          p.box(
            key: GraineAgentBar.captionKey,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            radius: p.captionRadius,
            shadows: p.captionShadows,
            child: Opacity(
              opacity: caption.live ? 0.8 : 1,
              child: Text(caption.text, maxLines: 3, overflow: TextOverflow.ellipsis, style: p.captionStyle),
            ),
          ),
        bar,
      ],
    );

    WidgetsBinding.instance.addPostFrameCallback((Duration _) => _measure());

    return DefaultTextStyle(
      style: textStyle(p.text, 14, family: p.statusStyle.fontFamily),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(widget.horizontalInset, 0, widget.horizontalInset, bottom),
          child: RawGestureDetector(
            behavior: HitTestBehavior.deferToChild,
            gestures: widget.draggable
                ? <Type, GestureRecognizerFactory>{
                    VerticalDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<VerticalDragGestureRecognizer>(
                      () => VerticalDragGestureRecognizer(),
                      (VerticalDragGestureRecognizer r) {
                        r
                          // Claimed only once it is clearly a drag (8px, the RN SDK's slop),
                          // so a tap on the bar and its buttons still taps.
                          ..gestureSettings = const DeviceGestureSettings(touchSlop: Placement.dragSlop)
                          ..dragStartBehavior = DragStartBehavior.down
                          ..onStart = _onDragStart
                          ..onUpdate = _onDragUpdate
                          ..onEnd = _onDragEnd
                          ..onCancel = _onDragCancel;
                      },
                    ),
                  }
                : const <Type, GestureRecognizerFactory>{},
            child: unit,
          ),
        ),
      ),
    );
  }

  /// A face: the logo, else — with a design — the design's glyph on the
  /// accent (its first letter when the brand chose its logo and has none),
  /// else the SDK's own mark.
  Widget _avatar(String? url, String name, _BarLook p) {
    final t = p.tokens;
    final glyph = Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
      child: t == null
          ? Text('✦', style: textStyle(p.glyphInk, 16, height: 1))
          : BrandMark(
              glyph: t.icons.launcher,
              colorHex: p.glyphInkHex,
              size: (38 * Design.launcherGlyphScale).roundToDouble(),
              stroke: t.icons.stroke,
              name: name,
              origin: GraineInApp.maybeInstance?.config.baseUrl,
            ),
    );
    if (url == null || url.isEmpty) return glyph;
    return ClipOval(
      child: Container(
        width: 38,
        height: 38,
        color: p.chip,
        child: Image.network(url,
            width: 38,
            height: 38,
            fit: BoxFit.cover,
            excludeFromSemantics: true,
            errorBuilder: (BuildContext c, Object e, StackTrace? s) => glyph),
      ),
    );
  }
}
