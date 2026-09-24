import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'core/core.dart';
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
///  - The DASHBOARD decides how it looks (accent, heading, logo,
///    light/dark/auto, radius); [accent], [name], [avatarUrl], [scheme] and
///    [radius] override one thing each.
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

  /// "light", "dark" or "auto" (the device). Default: the dashboard's theme.
  final String? scheme;

  /// Corner rounding for the caption and components. Default: the dashboard's radius.
  final double? radius;

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

  @override
  State<GraineAgentBar> createState() => _GraineAgentBarState();
}

/// ui.tsx's two palettes, with the dashboard choosing between them.
class _BarPalette {
  const _BarPalette.dark()
      : surface = const Color(0xFF17161A),
        border = const Color(0x17FFFFFF),
        text = const Color(0xFFF2F3F5),
        sub = const Color(0xFF9AA0A6),
        chip = const Color(0x14FFFFFF),
        danger = const Color(0xFFE5484D);

  const _BarPalette.light()
      : surface = const Color(0xFFFFFFFF),
        border = const Color(0x1A000000),
        text = const Color(0xFF16181C),
        sub = const Color(0xFF61666D),
        chip = const Color(0x0D000000),
        danger = const Color(0xFFD32F2F);

  final Color surface;
  final Color border;
  final Color text;
  final Color sub;
  final Color chip;
  final Color danger;
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
    final accentHex = (widget.accent != null && Appearance.argb(widget.accent) != null) ? widget.accent! : dash.accent;
    final accent = colorOf(accentHex) ?? colorOf(Appearance.defaultAccent)!;
    final theme = widget.scheme ?? Js.strOrEmpty(appearance['theme']);
    final dark = Appearance.isDark(theme.isEmpty ? 'auto' : theme, deviceDark(context));
    final p = dark ? const _BarPalette.dark() : const _BarPalette.light();
    final radius = widget.radius ?? dash.radius;
    final loader = Loaders.resolve(appearance['loader']);
    final loaderColor = colorOf(loader.color) ?? accent;
    final name = widget.name ?? dash.heading;
    final avatar = widget.avatarUrl ?? dash.logoUrl;

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
      required VoidCallback onTap,
    }) =>
        Tap(
          key: key,
          label: label,
          onTap: onTap,
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
            child: Text(glyph, style: textStyle(p.text, 16, height: 1)),
          ),
        );

    final bar = Container(
      key: GraineAgentBar.barKey,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(math.min(26, radius + 8)),
        border: Border.all(color: p.border),
        boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x4D000000), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Row(
        children: <Widget>[
          _avatar(avatar, accent, p),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: textStyle(p.text, 15, weight: 800)),
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
                                child: Text(status,
                                    maxLines: 1, overflow: TextOverflow.ellipsis, style: textStyle(p.sub, 12.5)),
                              ),
                            ],
                          )
                        : Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, style: textStyle(p.sub, 12.5)),
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
              fill: call.muted ? p.danger : p.chip,
              onTap: () => call.setMuted(!call.muted),
            ),
            const SizedBox(width: 8),
          ],
          round(
            key: GraineAgentBar.callButtonKey,
            glyph: failed ? '↻' : (live ? '✕' : '📞'),
            label: failed ? 'Try again' : (live ? 'End call' : 'Start a call'),
            fill: live ? p.danger : accent,
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
            maxHeight: math.max(160, (bounds.windowHeight - bottom - bounds.topMargin - height - 16) * 0.9),
          ),
        if (showCaption)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: p.border),
              boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x2E000000), blurRadius: 12, offset: Offset(0, 4))],
            ),
            child: Opacity(
              opacity: caption.live ? 0.8 : 1,
              child: Text(caption.text,
                  maxLines: 3, overflow: TextOverflow.ellipsis, style: textStyle(p.text, 15, weight: 600, height: 1.4)),
            ),
          ),
        bar,
      ],
    );

    WidgetsBinding.instance.addPostFrameCallback((Duration _) => _measure());

    return DefaultTextStyle(
      style: textStyle(p.text, 14),
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

  Widget _avatar(String? url, Color accent, _BarPalette p) {
    final glyph = Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
      child: Text('✦', style: textStyle(const Color(0xFFFFFFFF), 16, height: 1)),
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
