import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'core/core.dart';
import 'graine.dart';
import 'style.dart';

/// THE CONVERSATION SO FAR, drawn as the brand's chat window.
///
/// What the customer and the agent have said on this call —
/// [GraineCallState.captions], oldest first, the turn still being said drawn
/// provisional — for an app that wants the whole exchange on screen rather
/// than the bar's one live line. Place it where it should appear; it takes
/// the width it is given and scrolls inside [maxHeight], newest at the bottom.
///
/// The design draws it (contract/DESIGN.md, "Chat window"): the page in
/// `background`, a header in `surface` with the title in the heading font;
/// bubbles with `radius.lg` corners (`radius.sm` nearest the speaker),
/// padded by `spacing.cardPadding`, in the design's style — `filled`
/// (`userBubble` / `agentBubble`), `outline` (a `borderWidth` outline, the
/// customer's in `accent`, the agent's in `border`) or `minimal` (the agent's
/// words plain on the page, the customer's on `accentSoft`). A voice call has
/// nothing to type into, so there is no composer. Without a design it takes
/// the component palette and the dashboard's accent.
class GraineTranscriptView extends StatelessWidget {
  const GraineTranscriptView({
    super.key,
    this.call,
    this.title,
    this.showHeader = true,
    this.design,
    this.scheme,
    this.maxHeight = 320,
    this.app,
  });

  /// The call whose words to show. Default: [app]'s voice.
  final GraineCallState? call;

  /// The agent whose call this is: its call, session and design. Default:
  /// the agent [call] belongs to, else the default agent ([GraineInApp.instance]).
  final GraineInApp? app;

  /// The agent this view draws for.
  GraineInApp? get _agent {
    final c = call;
    return app ?? (c is GraineVoice ? c.app : null) ?? GraineInApp.maybeInstance;
  }

  /// The header's words. Default: the dashboard's heading, else "Assistant".
  final String? title;
  final bool showHeader;

  /// The design to draw. Default: the session's ([GraineInApp.design]).
  final ResolvedDesign? design;

  /// "light", "dark" or "auto" (the device). Default: the design's own.
  final String? scheme;

  /// The most height it takes; the conversation scrolls inside.
  final double maxHeight;

  static const Key headerKey = ValueKey<String>('graine-transcript-header');

  /// The [index]th turn's bubble (oldest is 0).
  static Key bubbleKey(int index) => ValueKey<String>('graine-bubble-$index');

  @override
  Widget build(BuildContext context) {
    final app = _agent;
    final c = call ?? app?.voice;
    if (c == null) return const SizedBox.shrink();
    // A design handed over directly has its typeface fetched too (each face once).
    if (design != null) app?.loadDesignFonts(design);
    return ListenableBuilder(
      listenable: surfaceListenable(<Listenable?>[c], app: app),
      builder: (BuildContext context, Widget? _) => _build(context, c),
    );
  }

  Widget _build(BuildContext context, GraineCallState c) {
    final app = _agent;
    final appearance = c.appearance;
    final dash = Appearance.resolve(appearance, accent: Appearance.defaultAccent, heading: 'Assistant', origin: app?.config.baseUrl);
    final tokens = tokensFor(context, design: design, scheme: scheme, app: app);
    final look = tokens != null
        ? _ChatLook.design(tokens)
        : _ChatLook.appearance(context, appearance, dash.accent, dash.radius);
    final turns = c.captions.where((Caption t) => t.text.trim().isNotEmpty).toList();

    final body = turns.isEmpty
        ? Padding(
            padding: EdgeInsets.all(look.pad),
            child: Text('What you and the assistant say appears here.', style: look.emptyStyle),
          )
        : SingleChildScrollView(
            // Newest at the bottom, and the bottom is where it opens.
            reverse: true,
            padding: EdgeInsets.all(look.pad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (var i = 0; i < turns.length; i++) ...<Widget>[
                  if (i > 0) SizedBox(height: look.gap),
                  _bubble(i, turns[i], look),
                ],
              ],
            ),
          );

    return DefaultTextStyle(
      style: look.baseStyle,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: look.background,
            borderRadius: BorderRadius.circular(look.lg),
            border: look.borderWidth > 0 ? Border.all(color: look.border, width: look.borderWidth) : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (showHeader)
                surfaceBox(
                  key: headerKey,
                  color: look.surface,
                  border: look.border,
                  borderWidth: 0,
                  radius: BorderRadius.zero,
                  shadows: const <BoxShadow>[],
                  glass: look.glass,
                  padding: EdgeInsets.symmetric(horizontal: look.pad, vertical: look.pad * 0.75),
                  child: Text(title ?? dash.heading, maxLines: 1, overflow: TextOverflow.ellipsis, style: look.titleStyle),
                ),
              if (showHeader) Container(height: look.borderWidth > 0 ? look.borderWidth : 1, color: look.border),
              Flexible(child: body),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bubble(int i, Caption turn, _ChatLook look) {
    final customer = turn.role == Role.customer;
    final Color? fill;
    final Color ink;
    Border? outline;
    switch (look.style) {
      case 'outline':
        fill = null;
        ink = look.text;
        outline = Border.all(color: customer ? look.accent : look.border, width: math.max(1, look.borderWidth));
      case 'minimal':
        fill = customer ? look.accentSoft : null;
        ink = look.text;
      default: // filled
        fill = customer ? look.userBubble : look.agentBubble;
        ink = customer ? look.userBubbleText : look.agentBubbleText;
    }
    // Minimal: the agent's words sit on the page, no bubble at all.
    final bare = look.style == 'minimal' && !customer;
    final lg = Radius.circular(look.lg);
    final sm = Radius.circular(look.sm);
    final bubble = Container(
      key: bubbleKey(i),
      padding: bare
          ? EdgeInsets.symmetric(vertical: look.pad * 0.75)
          : EdgeInsets.symmetric(horizontal: look.pad, vertical: look.pad * 0.75),
      decoration: bare
          ? null
          : BoxDecoration(
              color: fill,
              border: outline,
              // The corner nearest the speaker is the small one.
              borderRadius: BorderRadius.only(
                topLeft: lg,
                topRight: lg,
                bottomLeft: customer ? lg : sm,
                bottomRight: customer ? sm : lg,
              ),
            ),
      child: Text(turn.text, style: look.bubbleStyle.copyWith(color: ink)),
    );
    // At most 84% of the width (contract/DESIGN.md, "Chat window"), on the
    // speaker's side, as wide as its words.
    final side = customer ? Alignment.centerRight : Alignment.centerLeft;
    return FractionallySizedBox(
      widthFactor: 0.84,
      alignment: side,
      child: Align(alignment: side, child: Opacity(opacity: turn.live ? 0.8 : 1, child: bubble)),
    );
  }
}

/// Everything the transcript draws with: the design's chat tokens, or the
/// component palette and the dashboard's accent before designs.
class _ChatLook {
  _ChatLook({
    required this.style,
    required this.background,
    required this.surface,
    required this.border,
    required this.borderWidth,
    required this.text,
    required this.accent,
    required this.accentSoft,
    required this.userBubble,
    required this.userBubbleText,
    required this.agentBubble,
    required this.agentBubbleText,
    required this.lg,
    required this.sm,
    required this.pad,
    required this.gap,
    required this.baseStyle,
    required this.titleStyle,
    required this.bubbleStyle,
    required this.emptyStyle,
    this.glass,
  });

  factory _ChatLook.design(ThemeTokens t) {
    final c = t.colors;
    final f = t.font;
    final text = tokenColor(c.text);
    return _ChatLook(
      style: t.bubbles,
      background: tokenColor(c.background),
      surface: t.glass == null ? tokenColor(c.surface) : fade(tokenColor(c.surface), t.glass!.surfaceOpacity),
      border: tokenColor(c.border),
      borderWidth: t.shape.borderWidth,
      text: text,
      accent: tokenColor(c.accent),
      accentSoft: tokenColor(c.accentSoft),
      userBubble: tokenColor(c.userBubble),
      userBubbleText: tokenColor(c.userBubbleText),
      agentBubble: tokenColor(c.agentBubble),
      agentBubbleText: tokenColor(c.agentBubbleText),
      lg: t.shape.radius.lg,
      sm: t.shape.radius.sm,
      pad: t.spacing.cardPadding,
      gap: t.spacing.gap,
      baseStyle: designText(text, f.scale.body, f.body, f.weights.body),
      titleStyle: designText(text, f.scale.title, f.heading, f.weights.title,
          height: f.lineHeight.title, letterSpacing: f.letterSpacing.title * f.scale.title),
      bubbleStyle: designText(text, f.scale.body, f.body, f.weights.body,
          height: f.lineHeight.body, letterSpacing: f.letterSpacing.body * f.scale.body),
      emptyStyle: textStyle(tokenColor(c.textMuted), f.scale.caption, height: f.lineHeight.body),
      glass: t.glass,
    );
  }

  factory _ChatLook.appearance(BuildContext context, Map<String, Object?> appearance, String accentHex, double radius) {
    final p = Appearance.palette(appearance, deviceDark: deviceDark(context), accent: accentHex);
    final text = colorOf(p.text)!;
    final accent = colorOf(accentHex) ?? colorOf(Appearance.defaultAccent)!;
    final border = colorOf(p.border)!;
    return _ChatLook(
      style: 'filled',
      background: colorOf(p.surface)!,
      surface: colorOf(p.surface)!,
      border: border,
      borderWidth: 1,
      text: text,
      accent: accent,
      accentSoft: fade(accent, 0.15),
      userBubble: accent,
      userBubbleText: colorOf(p.onAccent)!,
      agentBubble: fade(border, 0.6),
      agentBubbleText: text,
      lg: math.min(radius, 16),
      sm: 5,
      pad: 12,
      gap: 8,
      baseStyle: textStyle(text, 14.5),
      titleStyle: textStyle(text, 15, weight: 800),
      bubbleStyle: textStyle(text, 14.5, height: 21 / 14.5),
      emptyStyle: textStyle(colorOf(p.muted)!, 14, height: 1.5),
    );
  }

  /// `filled`, `outline` or `minimal`.
  final String style;
  final Color background;
  final Color surface;
  final Color border;
  final double borderWidth;
  final Color text;
  final Color accent;
  final Color accentSoft;
  final Color userBubble;
  final Color userBubbleText;
  final Color agentBubble;
  final Color agentBubbleText;
  final double lg;
  final double sm;
  final double pad;
  final double gap;
  final TextStyle baseStyle;
  final TextStyle titleStyle;
  final TextStyle bubbleStyle;
  final TextStyle emptyStyle;
  final ThemeGlass? glass;
}
