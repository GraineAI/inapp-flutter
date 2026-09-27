import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'chat_window.dart';
import 'core/core.dart';
import 'glyph.dart';
import 'graine.dart';
import 'loader_view.dart';
import 'sdk_icon.dart';
import 'style.dart';
import 'widget_view.dart';

/// THE VOICE BAR — what the customer sees during a call, drawn by the SDK
/// from the brand's design and nothing else.
///
/// The dashboard's Garage draws this bar in its phone preview, and the SDK
/// draws the same one, element by element as contract/DESIGN.md ("Voice
/// bar") specifies: a 60-point bar on `surface` (translucent over a blur with
/// glass) with its outline, `radius.xl` corners and the floating shadow — or
/// the neo-brutalist solid offset; the accent avatar with the launcher glyph;
/// the name in the design's face and a status line whose meter moves at the
/// design's pace; the microphone in `accent`, hang up in `danger`; the SDK's
/// icons in the design's icon style; the design's typeface, which the SDK
/// fetches itself. The app passes nothing about how it looks.
///
/// It says the network's name out loud — "Weak connection", "No connection",
/// "Reconnecting…" — because a customer whose agent goes quiet on a train
/// reads "Listening" and concludes the agent is broken.
///
/// One unit, bottom up: the bar, the live caption (or the chat window), and
/// the components the agent draws ([GraineWidgetView]) — so a card sits on
/// the bar and moves with it.
///
///  - The DASHBOARD decides how it looks: the brand's design when the session
///    carries one, else Appearance (accent, heading, logo, light/dark/auto,
///    radius). [accent], [name], [avatarUrl], [scheme] and [radius] override
///    one thing each.
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
    this.showCaptions = true,
    this.onClose,
    this.chat,
    this.surface,
    this.onSurfaceChange,
  });

  /// The call to draw. Default: [GraineInApp.instance]'s voice.
  final GraineCallState? call;

  /// The components to draw above the bar. Default: [GraineInApp.instance]'s.
  final GraineComponents? components;

  /// #RRGGBB for the avatar, the microphone, the meter and components. Default: the design's accent, else the dashboard's.
  final String? accent;

  /// The name beside the status. Default: the dashboard's heading, else "Assistant".
  final String? name;

  /// A face for the avatar, over the design's glyph. Default: the design's
  /// glyph, else the dashboard's logo, else the name's first letter.
  final String? avatarUrl;

  /// "light", "dark" or "auto" (the device). Default: the design's, else the dashboard's theme.
  final String? scheme;

  /// Corner rounding for the caption and components. Default: the design's, else the dashboard's radius.
  final double? radius;

  /// The design to draw. Default: the session's ([GraineInApp.design]); with
  /// none, the bar keeps the colours, corners and depth it had before designs.
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

  /// Show the line being said above the bar during a call.
  final bool showCaptions;

  /// The end button was pressed: after a hang-up, or — off a call — to close
  /// the bar. Hide it here if your app shows the bar on demand.
  final VoidCallback? onClose;

  /// THE CHAT, for an agent the dashboard offers as both a call and a chat
  /// (Embed & Widgets → mode). This SDK carries the call; an app that runs
  /// the chat conversation hands it here, and the bar offers the switch
  /// between them and draws the chat window above itself. Without one the
  /// bar is the call alone.
  final GraineChatState? chat;

  /// Which to open when both are offered — the dashboard's `start` otherwise.
  /// A surface the dashboard does not allow is never opened.
  final AgentSurface? surface;

  /// The customer switched between the call and the chat, or the dashboard's
  /// setting moved them. Open or close your chat connection here.
  final ValueChanged<AgentSurface>? onSurfaceChange;

  /// The bar itself — the 60-point frame with the avatar and the buttons.
  static const Key barKey = ValueKey<String>('graine-bar');

  /// The button that starts the call, retries a load that failed, or ends
  /// the call: the microphone off a call, the end button on one.
  static const Key callButtonKey = ValueKey<String>('graine-call');

  /// The microphone during a call, where it mutes.
  static const Key muteButtonKey = ValueKey<String>('graine-mute');

  /// The end button off a call, where it closes.
  static const Key closeButtonKey = ValueKey<String>('graine-close');

  /// The switch between the call and the chat (only when both are offered).
  static const Key switchButtonKey = ValueKey<String>('graine-switch');

  /// The status line.
  static const Key statusKey = ValueKey<String>('graine-status');

  /// The four-bar meter beside "Listening" and "Speaking".
  static const Key meterKey = ValueKey<String>('graine-meter');

  /// The avatar.
  static const Key avatarKey = ValueKey<String>('graine-avatar');

  /// The live caption above the bar.
  static const Key captionKey = ValueKey<String>('graine-caption');

  /// The chat window above the bar.
  static const Key chatKey = ValueKey<String>('graine-chat');

  @override
  State<GraineAgentBar> createState() => _GraineAgentBarState();
}

/// Everything the bar draws with, resolved once: the design's tokens in the
/// contract's roles, or — with no design — the bar's colours before designs
/// (ui.tsx's two palettes, the dashboard's accent and radius) in those roles.
class _BarLook {
  _BarLook({
    required this.surface,
    required this.border,
    required this.borderWidth,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccentHex,
    required this.soft,
    required this.danger,
    required this.barRadius,
    required this.captionRadius,
    required this.barShadows,
    required this.captionShadows,
    required this.nameStyle,
    required this.statusStyle,
    required this.waitingStyle,
    required this.captionStyle,
    required this.youStyle,
    required this.iconStyle,
    required this.iconStroke,
    required this.chat,
    this.glyph,
    this.glass,
    this.tokens,
  });

  /// Before designs: the palettes, corners and depth the bar always had,
  /// drawn onto the contract's elements.
  factory _BarLook.appearance({required bool dark, required Color accent, required double radius}) {
    final surface = dark ? const Color(0xFF17161A) : const Color(0xFFFFFFFF);
    final text = dark ? const Color(0xFFF2F3F5) : const Color(0xFF16181C);
    final sub = dark ? const Color(0xFF9AA0A6) : const Color(0xFF61666D);
    const barShadows = <BoxShadow>[BoxShadow(color: Color(0x4D000000), blurRadius: 16, offset: Offset(0, 6))];
    return _BarLook(
      surface: surface,
      border: dark ? const Color(0x17FFFFFF) : const Color(0x1A000000),
      borderWidth: 1,
      text: text,
      muted: sub,
      accent: accent,
      onAccentHex: readableHexOn(accent),
      soft: dark ? const Color(0x14FFFFFF) : const Color(0x0D000000),
      danger: dark ? const Color(0xFFE5484D) : const Color(0xFFD32F2F),
      barRadius: math.min(26, radius + 8),
      captionRadius: radius,
      barShadows: barShadows,
      captionShadows: const <BoxShadow>[BoxShadow(color: Color(0x2E000000), blurRadius: 12, offset: Offset(0, 4))],
      nameStyle: textStyle(text, 14, weight: 600, height: 1.25),
      statusStyle: textStyle(sub, 12, height: 1.3),
      waitingStyle: textStyle(sub, 12, weight: 600, height: 1.3),
      captionStyle: textStyle(text, 13, weight: 600, height: 1.35),
      youStyle: textStyle(accent, 10.5, weight: 600, letterSpacing: 0.6),
      iconStyle: 'outline',
      iconStroke: 2,
      chat: ChatLook.appearance(dark: dark, accent: accent, radius: radius, shadows: barShadows),
    );
  }

  /// The design's "Voice bar", element by element.
  factory _BarLook.design(ThemeTokens t, {Color? accent, double? radius}) {
    final c = t.colors;
    final f = t.font;
    final a = accent ?? tokenColor(c.accent);
    final surface = tokenColor(c.surface);
    final text = tokenColor(c.text);
    final muted = tokenColor(c.textMuted);
    final caption = f.scale.caption;
    return _BarLook(
      surface: t.glass == null ? surface : fade(surface, t.glass!.surfaceOpacity),
      border: tokenColor(c.border),
      borderWidth: t.shape.borderWidth,
      text: text,
      muted: muted,
      accent: a,
      // The design's onAccent was chosen for the design's accent; a host's own accent gets ink by luminance.
      onAccentHex: accent == null ? c.onAccent : readableHexOn(accent),
      soft: accent == null ? tokenColor(c.accentSoft) : softFor(accent, surface, dark: t.dark),
      danger: tokenColor(c.danger),
      barRadius: radius != null ? math.min(26, radius + 8) : t.shape.radius.xl,
      captionRadius: radius ?? t.shape.radius.lg,
      barShadows: raisedShadows(t, t.elevation.floating, text),
      captionShadows: raisedShadows(t, t.elevation.card, text),
      // Name: 14, the BODY family at the strong weight — the Garage's line, not the title's.
      nameStyle:
          designText(text, 14, f.body, f.weights.strong, height: 1.25, letterSpacing: em(14, f.letterSpacing.body)),
      statusStyle: designText(muted, caption, f.body, f.weights.body,
          height: 1.3, letterSpacing: em(caption, f.letterSpacing.body)),
      // The loader's words for a moment, as the React Native loader sets them.
      waitingStyle: designText(muted, math.max(caption, 9), f.body, f.weights.strong, height: 1.3),
      captionStyle:
          designText(text, 13, f.body, f.weights.strong, height: 1.35, letterSpacing: em(13, f.letterSpacing.body)),
      youStyle: designText(a, 10.5, f.body, f.weights.strong, letterSpacing: 0.6),
      iconStyle: t.icons.style,
      iconStroke: t.icons.stroke,
      chat: ChatLook.design(t, accent: accent),
      glyph: t.icons.launcher,
      glass: t.glass,
      tokens: t,
    );
  }

  /// The bar's and the caption's fill, already translucent with [glass].
  final Color surface;
  final Color border;
  final double borderWidth;
  final Color text;
  final Color muted;
  final Color accent;
  final String onAccentHex;

  /// `accentSoft`: the switch, and the end button off a call.
  final Color soft;
  final Color danger;
  final double barRadius;
  final double captionRadius;
  final List<BoxShadow> barShadows;
  final List<BoxShadow> captionShadows;
  final TextStyle nameStyle;
  final TextStyle statusStyle;
  final TextStyle waitingStyle;
  final TextStyle captionStyle;
  final TextStyle youStyle;
  final String iconStyle;
  final double iconStroke;
  final ChatLook chat;

  /// The design's launcher glyph; null for the logo, and before designs.
  final LauncherGlyph? glyph;
  final ThemeGlass? glass;

  /// Null before designs.
  final ThemeTokens? tokens;

  Color get onAccent => tokenColor(onAccentHex);
}

const Color _white = Color(0xFFFFFFFF);

class _GraineAgentBarState extends State<GraineAgentBar> {
  final GlobalKey _unitKey = GlobalKey();
  late int _offset = widget.initialOffset ?? 0;
  double _barHeight = 0;
  bool _dragging = false;
  int _dragStart = 0;
  double _dragOriginY = 0;

  /// The customer's last switch between the call and the chat.
  AgentSurface? _chosen;

  /// The surface last announced to [GraineAgentBar.onSurfaceChange].
  AgentSurface? _announced;

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

  double _topMargin(BuildContext context) => widget.topMargin ?? math.max(48, MediaQuery.paddingOf(context).top + 8);

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

  /// Move the customer between the call and the chat. Going to the chat ends
  /// the call — exactly one conversation is open at a time.
  void _setSurface(AgentSurface next, GraineCallState call) {
    if (next == AgentSurface.chat && (call.connected || call.connecting)) call.end();
    setState(() => _chosen = next);
  }

  /// The end button: hang up (or cancel a call being placed), then tell the app.
  void _endOrClose(GraineCallState call) {
    call.end();
    widget.onClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    final call = _call;
    // A design handed to this bar directly has its typeface fetched too; the
    // session's is fetched when the session arrives. Each face once.
    if (widget.design != null) GraineInApp.maybeInstance?.loadDesignFonts(widget.design);
    return ListenableBuilder(
      listenable: surfaceListenable(<Listenable?>[call, widget.chat]),
      builder: (BuildContext context, Widget? _) => _build(context, call),
    );
  }

  Widget _build(BuildContext context, GraineCallState call) {
    final app = GraineInApp.maybeInstance;
    final appearance = call.appearance;
    final dash = Appearance.resolve(appearance,
        accent: Appearance.defaultAccent, heading: 'Assistant', origin: app?.config.baseUrl);
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
    final loader = Loaders.resolve(appearance['loader']);
    final loaderColor = colorOf(loader.color) ?? p.accent;
    final name = widget.name ?? dash.heading;
    final motion = motionOf(context, tokens);
    final curve = curveOf(tokens);

    // The call or the chat: the chat only when the app runs one, and only
    // as the dashboard allows.
    final chat = widget.chat;
    final policy = Surfaces.resolve(appearance, _chosen ?? widget.surface);
    final surface = chat == null ? AgentSurface.voice : policy.start;
    final isChat = surface == AgentSurface.chat;
    final canSwitch = chat != null && policy.canSwitch;
    _announce(surface);

    // A host's own call state need not say; GraineVoice does.
    final fault = switch (call) { GraineCallFault(:final error) => error, _ => null };
    final phase = callPhase(
      reconnecting: call.reconnecting,
      connectivity: call.connectivity,
      connecting: call.connecting,
      ready: call.ready,
      connected: call.connected,
      caption: call.caption,
      agentSpeaking: call.agentSpeaking,
    );
    final status = voiceBarStatus(
      error: fault != null,
      inChat: isChat,
      chatOnline: chat?.connected ?? false,
      online: call.online,
      reconnecting: call.reconnecting,
      connectivity: call.connectivity,
      micDenied: call.micDenied,
      ready: call.ready,
      connecting: call.connecting,
      muted: call.muted,
      connected: call.connected,
      thinking: phase == CallPhase.thinking,
      speaking: phase == CallPhase.speaking,
      quality: call.quality,
    );
    final failed = call.connectivity == GraineConnectivity.failed;
    // The microphone cannot act while the call is being placed, before the
    // page is ready (a failed load aside: then it retries), once it has been
    // refused, or while the agent is misconfigured.
    final micBlocked = fault != null || call.micDenied || call.connecting || (!call.ready && !failed);
    final caption = call.caption;
    final showCaption =
        !isChat && widget.showCaptions && call.connected && caption != null && caption.text.trim().isNotEmpty;
    final components = widget.showComponents ? _components : null;

    // Where it sits: the anchor, the customer's offset, the keyboard — and
    // never past the top margin however they add up.
    final bounds = _bounds(context);
    final offset = widget.draggable ? Placement.clampOffset(_offset.toDouble(), bounds) : 0;
    final keyboard =
        widget.keyboardAware ? KeyboardLift.liftFor(MediaQuery.viewInsetsOf(context).bottom, 0).toDouble() : 0.0;
    final height = _barHeight > 0 ? _barHeight : 60.0;
    final maxBottom = math.max(0.0, bounds.windowHeight - bounds.topMargin - height);
    final bottom = math.min(widget.bottomInset + offset + keyboard, math.max(widget.bottomInset, maxBottom));

    Widget icon(String name, Color color) =>
        SdkIconView(name, color: color, size: 18, style: p.iconStyle, stroke: p.iconStroke);

    Widget round({
      required Key key,
      required String label,
      required Color fill,
      required Widget child,
      required VoidCallback onTap,
      bool enabled = true,
    }) {
      final decoration = BoxDecoration(color: fill, shape: BoxShape.circle);
      // A call starting or a mute going on eases between its colours, at the design's pace.
      final face = motion == Duration.zero
          ? Container(width: 38, height: 38, alignment: Alignment.center, decoration: decoration, child: child)
          : AnimatedContainer(
              duration: motion,
              curve: curve,
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: decoration,
              child: child,
            );
      return Tap(
        key: key,
        label: label,
        enabled: enabled,
        onTap: onTap,
        child: Opacity(opacity: enabled ? 1 : 0.4, child: face),
      );
    }

    // The status line: the loader with that moment's words while the call
    // comes up (or the agent works out its answer); else the words, after
    // the meter while it is listening or speaking.
    final waiting = status.waiting;
    final Widget statusLine = waiting != null
        ? GraineLoaderView(
            look: loader,
            color: loaderColor,
            trackColor: p.border,
            size: 14,
            label: loader.text.forMoment(waiting) ?? status.text,
            labelColor: p.muted,
            labelStyle: p.waitingStyle,
            logoUrl: dash.logoUrl,
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (status.meter) ...<Widget>[
                BarMeter(key: GraineAgentBar.meterKey, color: p.accent, durationMs: motion.inMilliseconds),
                const SizedBox(width: 6),
              ],
              Flexible(child: Text(status.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: p.statusStyle)),
            ],
          );

    final row = <Widget>[
      _avatar(p, name: name, logoUrl: dash.logoUrl, origin: app?.config.baseUrl),
      const SizedBox(width: 10),
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
              value: status.text,
              child: ExcludeSemantics(child: statusLine),
            ),
          ],
        ),
      ),
      // The way to the other surface, only when the dashboard allows both.
      if (canSwitch) ...<Widget>[
        const SizedBox(width: 10),
        round(
          key: GraineAgentBar.switchButtonKey,
          label: isChat ? 'Switch to a call' : 'Switch to chat',
          fill: p.soft,
          child: icon(isChat ? 'call' : 'chat', p.text),
          onTap: () => _setSurface(isChat ? AgentSurface.voice : AgentSurface.chat, call),
        ),
      ],
      // Off a call the microphone STARTS one; on a call it is the mute; after
      // a failed load it retries.
      if (!isChat) ...<Widget>[
        const SizedBox(width: 10),
        round(
          key: call.connected ? GraineAgentBar.muteButtonKey : GraineAgentBar.callButtonKey,
          label: failed ? 'Try again' : (!call.connected ? 'Start talking to $name' : (call.muted ? 'Unmute' : 'Mute')),
          fill: call.muted ? p.danger : p.accent,
          enabled: !micBlocked,
          child: icon(call.muted ? 'micOff' : 'mic', call.muted ? _white : p.onAccent),
          onTap: () {
            if (failed) {
              call.retry();
            } else if (call.connected) {
              call.setMuted(!call.muted);
            } else {
              call.start();
            }
          },
        ),
      ],
      // Loud only while there is a call to end; otherwise it closes.
      const SizedBox(width: 10),
      round(
        key: call.connected ? GraineAgentBar.callButtonKey : GraineAgentBar.closeButtonKey,
        label: call.connected ? 'End call' : 'Close',
        fill: call.connected ? p.danger : p.soft,
        child: icon(call.connected ? 'end' : 'close', call.connected ? _white : p.muted),
        onTap: () => _endOrClose(call),
      ),
    ];

    final bar = surfaceBox(
      key: GraineAgentBar.barKey,
      color: p.surface,
      border: p.border,
      borderWidth: p.borderWidth,
      radius: BorderRadius.circular(p.barRadius),
      shadows: p.barShadows,
      glass: p.glass,
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: row),
    );

    Widget? above;
    if (isChat) {
      above = _Rise(
        key: const ValueKey<String>('graine-rise-chat'),
        duration: motion,
        curve: curve,
        child: Padding(
          key: GraineAgentBar.chatKey,
          padding: const EdgeInsets.only(bottom: 8),
          child: ChatWindow(
            look: p.chat,
            heading: name,
            messages: chat!.messages,
            online: chat.connected,
            onSend: chat.send,
            // Back to the call — or, for an agent that is only a chat, closed.
            onCollapse: canSwitch ? () => _setSurface(AgentSurface.voice, call) : () => _endOrClose(call),
            logoUrl: dash.logoUrl,
            origin: app?.config.baseUrl,
            lifted: keyboard > 0,
          ),
        ),
      );
    } else if (showCaption) {
      above = _Rise(
        key: const ValueKey<String>('graine-rise-caption'),
        duration: motion,
        curve: curve,
        child: surfaceBox(
          key: GraineAgentBar.captionKey,
          color: p.surface,
          border: p.border,
          borderWidth: p.borderWidth,
          radius: BorderRadius.circular(p.captionRadius),
          shadows: p.captionShadows,
          glass: p.glass,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // WHO is saying it: captions carry both sides, and an unlabelled
              // "Take me to privacy" reads as the agent talking to itself.
              if (caption.role == Role.customer)
                Padding(padding: const EdgeInsets.only(bottom: 2), child: Text('YOU', style: p.youStyle)),
              Opacity(
                opacity: caption.live ? 0.75 : 1,
                child: Text(caption.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: p.captionStyle),
              ),
            ],
          ),
        ),
      );
    }

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
        if (above != null) above,
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

  /// Tell the app when the surface moved — by the customer's switch, or by a
  /// dashboard setting that no longer allows the one it was on. Not on the
  /// first build: nothing moved.
  void _announce(AgentSurface surface) {
    final before = _announced;
    _announced = surface;
    if (before == null || before == surface) return;
    final notify = widget.onSurfaceChange;
    if (notify != null) SchedulerBinding.instance.addPostFrameCallback((Duration _) => notify(surface));
  }

  /// The avatar, 38 round on the accent: a face the host passed; else the
  /// design's launcher glyph in onAccent at 18; else the brand's logo filling
  /// the circle; else the name's first letter, 15, bold — each falling to
  /// the next when it cannot be shown.
  Widget _avatar(_BarLook p, {required String name, String? logoUrl, String? origin}) {
    final initial = initialOf(name);
    Widget letter() => Text(initial, style: textStyle(p.onAccent, 15, weight: 700, height: 1));
    Widget cover(String url, Widget Function() fallback) => Image.network(
          url,
          width: 38,
          height: 38,
          fit: BoxFit.cover,
          excludeFromSemantics: true,
          errorBuilder: (BuildContext c, Object e, StackTrace? s) => Center(child: fallback()),
        );
    Widget brand() {
      final glyph = p.glyph;
      if (glyph != null) {
        return BrandMark(
          glyph: glyph,
          colorHex: p.onAccentHex,
          size: 18,
          stroke: p.iconStroke,
          logoUrl: logoUrl,
          name: name,
          origin: origin,
        );
      }
      if (logoUrl != null && logoUrl.isNotEmpty) return cover(logoUrl, letter);
      return letter();
    }

    final own = widget.avatarUrl;
    return Container(
      key: GraineAgentBar.avatarKey,
      width: 38,
      height: 38,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
      child: (own != null && own.isNotEmpty) ? cover(own, brand) : brand(),
    );
  }
}

/// THE METER — four bars in the accent, 2.5 wide and 2 apart, bottoms aligned,
/// at 55%, 100%, 70% and 40% of 12; each scales from its bottom between 35%
/// and 100% and back, each leg `max(420, durationMs × 3.2)` ms, bar i
/// starting i × 90 ms late, forever ([VoiceMeter]). Still at full height when
/// [durationMs] is 0 — no motion in the design, or the OS asked for less.
class BarMeter extends StatefulWidget {
  const BarMeter({super.key, required this.color, required this.durationMs});

  final Color color;

  /// The design's transition length after the OS has had its say.
  final int durationMs;

  @override
  State<BarMeter> createState() => _BarMeterState();
}

class _BarMeterState extends State<BarMeter> with SingleTickerProviderStateMixin {
  /// Milliseconds since the meter started moving.
  final ValueNotifier<double> _elapsed = ValueNotifier<double>(0);
  Ticker? _ticker;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(BarMeter old) {
    super.didUpdateWidget(old);
    if (old.durationMs != widget.durationMs) _sync();
  }

  void _sync() {
    if (VoiceMeter.still(widget.durationMs)) {
      _ticker?.stop();
      _elapsed.value = 0;
      return;
    }
    final ticker = _ticker ??= createTicker((Duration d) => _elapsed.value = d.inMicroseconds / 1000);
    if (!ticker.isActive) ticker.start();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _elapsed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const n = 4;
    return ExcludeSemantics(
      child: SizedBox(
        width: VoiceMeter.barWidth * n + VoiceMeter.gap * (n - 1),
        height: VoiceMeter.height,
        child:
            CustomPaint(painter: _MeterPainter(color: widget.color, durationMs: widget.durationMs, elapsed: _elapsed)),
      ),
    );
  }
}

class _MeterPainter extends CustomPainter {
  _MeterPainter({required this.color, required this.durationMs, required this.elapsed}) : super(repaint: elapsed);

  final Color color;
  final int durationMs;
  final ValueListenable<double> elapsed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..isAntiAlias = true
      ..color = color;
    for (var i = 0; i < VoiceMeter.heights.length; i++) {
      final scale = VoiceMeter.scale(i, elapsed.value, durationMs, Curves.easeInOut.transform);
      final h = VoiceMeter.height * VoiceMeter.heights[i] * scale;
      final x = i * (VoiceMeter.barWidth + VoiceMeter.gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x, size.height - h, VoiceMeter.barWidth, h), const Radius.circular(VoiceMeter.barWidth / 2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_MeterPainter old) => old.color != color || old.durationMs != durationMs;
}

/// A SURFACE ARRIVING — the caption, the chat window: opacity 0 → 1 and 8
/// points of rise over the design's duration, with its easing; nothing at all
/// when that is 0 (or the OS asked for less motion). Once, on arrival.
class _Rise extends StatefulWidget {
  const _Rise({super.key, required this.duration, required this.curve, required this.child});

  final Duration duration;
  final Curve curve;
  final Widget child;

  @override
  State<_Rise> createState() => _RiseState();
}

class _RiseState extends State<_Rise> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: widget.duration == Duration.zero ? 1 : 0,
  );

  @override
  void initState() {
    super.initState();
    if (_t.value < 1) _t.forward();
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // One shape before, during and after the rise: a tree that changed shape
    // when it landed would rebuild what it carries — the chat's draft with it.
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        // A spring overshoots: the rise may, the opacity may not.
        final v = widget.curve.transform(_t.value);
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, 8 * (1 - v)), child: child),
        );
      },
    );
  }
}
