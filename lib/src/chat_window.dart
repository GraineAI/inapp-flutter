// The chat window the voice bar opens above itself when the customer is in
// the chat. Not exported: GraineAgentBar draws it from a GraineChatState.
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'core/core.dart';
import 'glyph.dart';
import 'sdk_icon.dart';
import 'style.dart';
import 'window_chrome.dart';

/// Everything the chat window draws with, resolved once: the design's tokens
/// (contract/DESIGN.md, "Chat window"), or — with no design — the component
/// palette and the dashboard's accent, as the transcript drew it before designs.
class ChatLook {
  const ChatLook({
    required this.background,
    required this.header,
    required this.raised,
    required this.border,
    required this.borderWidth,
    required this.text,
    required this.muted,
    required this.success,
    required this.accent,
    required this.onAccentHex,
    required this.soft,
    required this.userBubble,
    required this.userBubbleText,
    required this.agentBubble,
    required this.agentBubbleText,
    required this.bubbles,
    required this.sm,
    required this.lg,
    required this.xl,
    required this.pad,
    required this.gap,
    required this.markRadius,
    required this.glyph,
    required this.iconStyle,
    required this.iconStroke,
    required this.shadows,
    required this.titleStyle,
    required this.statusStyle,
    required this.bodyStyle,
    required this.inputStyle,
    this.glass,
    this.chrome,
  });

  factory ChatLook.design(ThemeTokens t, {Color? accent}) {
    final c = t.colors;
    final f = t.font;
    final text = tokenColor(c.text);
    final muted = tokenColor(c.textMuted);
    final surface = tokenColor(c.surface);
    final a = accent ?? tokenColor(c.accent);
    final titleSize = math.min(f.scale.title, 16).toDouble();
    // A pill is drawn as a circle at this size: a 30-point mark has no label to be wide for.
    final shape = t.shape.launcher == 'pill' ? 'circle' : t.shape.launcher;
    return ChatLook(
      background: tokenColor(c.background),
      header: t.glass == null ? surface : fade(surface, t.glass!.surfaceOpacity),
      raised: tokenColor(c.surfaceRaised),
      border: tokenColor(c.border),
      borderWidth: t.shape.borderWidth,
      text: text,
      muted: muted,
      success: tokenColor(c.success),
      accent: a,
      onAccentHex: accent == null ? c.onAccent : readableHexOn(accent),
      soft: accent == null ? tokenColor(c.accentSoft) : softFor(accent, surface, dark: t.dark),
      userBubble: tokenColor(c.userBubble),
      userBubbleText: tokenColor(c.userBubbleText),
      agentBubble: tokenColor(c.agentBubble),
      agentBubbleText: tokenColor(c.agentBubbleText),
      bubbles: t.bubbles,
      sm: t.shape.radius.sm,
      lg: t.shape.radius.lg,
      xl: t.shape.radius.xl,
      pad: t.spacing.cardPadding,
      gap: t.spacing.gap,
      markRadius: Design.launcherRadius(shape, t.shape.radius, 30),
      glyph: t.icons.launcher,
      iconStyle: t.icons.style,
      iconStroke: t.icons.stroke,
      shadows: raisedShadows(t, t.elevation.floating, text),
      titleStyle: designText(text, titleSize, f.heading, f.weights.title,
          height: f.lineHeight.title, letterSpacing: em(titleSize, f.letterSpacing.title)),
      statusStyle: designText(muted, f.scale.caption, f.body, f.weights.body,
          height: 1.2, letterSpacing: em(f.scale.caption, f.letterSpacing.body)),
      bodyStyle: designText(text, f.scale.body, f.body, f.weights.body,
          height: f.lineHeight.body, letterSpacing: em(f.scale.body, f.letterSpacing.body)),
      inputStyle: designText(text, f.scale.body - 1, f.body, f.weights.body),
      glass: t.glass,
      chrome: ChromeLook.of(t),
    );
  }

  /// Before designs: the component palette ([Appearance.palette]) and the accent.
  factory ChatLook.appearance({
    required bool dark,
    required Color accent,
    required double radius,
    required List<BoxShadow> shadows,
  }) {
    final surface = dark ? const Color(0xFF17181B) : const Color(0xFFFFFFFF);
    final border = dark ? const Color(0xFF2C2E33) : const Color(0xFFE5E4E0);
    final text = dark ? const Color(0xFFF5F5F4) : const Color(0xFF101318);
    final muted = dark ? const Color(0xFFA0A5AE) : const Color(0xFF5F6672);
    final onAccentHex = readableHexOn(accent);
    return ChatLook(
      background: surface,
      header: surface,
      raised: dark ? const Color(0xFF1F2024) : const Color(0xFFF7F7F5),
      border: border,
      borderWidth: 1,
      text: text,
      muted: muted,
      success: dark ? const Color(0xFF22C55E) : const Color(0xFF16A34A),
      accent: accent,
      onAccentHex: onAccentHex,
      soft: fade(accent, 0.15),
      userBubble: accent,
      userBubbleText: tokenColor(onAccentHex),
      agentBubble: fade(border, 0.6),
      agentBubbleText: text,
      bubbles: 'filled',
      sm: 5,
      lg: math.min(radius, 16),
      xl: math.min(26, radius + 8),
      pad: 12,
      gap: 8,
      markRadius: 15,
      glyph: null,
      iconStyle: 'outline',
      iconStroke: 2,
      shadows: shadows,
      titleStyle: textStyle(text, 15, weight: 700, height: 1.25),
      statusStyle: textStyle(muted, 12, height: 1.2),
      bodyStyle: textStyle(text, 14.5, height: 21 / 14.5),
      inputStyle: textStyle(text, 14),
    );
  }

  final Color background;

  /// The header's fill: `surface`, translucent with [glass].
  final Color header;

  /// The composer field: `surfaceRaised`.
  final Color raised;
  final Color border;
  final double borderWidth;
  final Color text;
  final Color muted;
  final Color success;
  final Color accent;
  final String onAccentHex;
  final Color soft;
  final Color userBubble;
  final Color userBubbleText;
  final Color agentBubble;
  final Color agentBubbleText;

  /// `filled`, `outline` or `minimal`.
  final String bubbles;
  final double sm;
  final double lg;
  final double xl;

  /// `spacing.cardPadding` and `spacing.gap`.
  final double pad;
  final double gap;

  /// The 30-point launcher mark's corners.
  final double markRadius;
  final LauncherGlyph? glyph;
  final String iconStyle;
  final double iconStroke;

  /// The window's depth: `elevation.floating`, or the solid offset.
  final List<BoxShadow> shadows;
  final TextStyle titleStyle;
  final TextStyle statusStyle;
  final TextStyle bodyStyle;
  final TextStyle inputStyle;
  final ThemeGlass? glass;

  /// The design opens the chat as a desktop window: its title bar replaces
  /// the header. Null — a design without window chrome, or none — keeps the header.
  final ChromeLook? chrome;

  Color get onAccent => tokenColor(onAccentHex);
}

/// THE CHAT WINDOW (contract/DESIGN.md, "Chat window"): the page in
/// `background` with an outline, `radius.xl` corners and the floating shadow
/// (or the hard offset); a 50-point header on `surface` — the launcher mark,
/// the heading in the heading face, "Online" after a `success` dot, and a
/// chevron back to the call; the messages as bubbles in the design's style;
/// and a 58-point composer. A design with window chrome replaces the header
/// with a 32-point title bar ("Window chrome"): the traffic lights, the
/// heading lower case in the platform's monospace after the online dot, and
/// the chevron at its right end — no launcher mark.
class ChatWindow extends StatefulWidget {
  const ChatWindow({
    super.key,
    required this.look,
    required this.heading,
    required this.messages,
    required this.online,
    required this.onSend,
    required this.onCollapse,
    this.logoUrl,
    this.origin,
    this.lifted = false,
  });

  final ChatLook look;
  final String heading;
  final List<Caption> messages;

  /// The chat is connected: "Online", else "Connecting…".
  final bool online;
  final ValueChanged<String> onSend;

  /// The chevron: back to the call, or — an agent that is only a chat — closed.
  final VoidCallback onCollapse;
  final String? logoUrl;
  final String? origin;

  /// The keyboard is up: fewer messages, so the composer stays in view.
  final bool lifted;

  static const Key headerKey = ValueKey<String>('graine-chat-header');
  static const Key composerKey = ValueKey<String>('graine-chat-composer');
  static const Key sendKey = ValueKey<String>('graine-chat-send');
  static const Key collapseKey = ValueKey<String>('graine-chat-collapse');

  /// The [index]th message's bubble (oldest is 0).
  static Key messageKey(int index) => ValueKey<String>('graine-chat-message-$index');

  @override
  State<ChatWindow> createState() => _ChatWindowState();
}

class _ChatWindowState extends State<ChatWindow> {
  final TextEditingController _draft = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'graine-chat-composer');

  @override
  void initState() {
    super.initState();
    _draft.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _draft.removeListener(_changed);
    _draft.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _draft.text.trim();
    if (text.isEmpty) return;
    _draft.clear();
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.look;
    final bw = l.borderWidth;
    final outline = bw > 0 ? Border.all(color: l.border, width: bw) : null;
    final chrome = l.chrome;
    return Container(
      decoration: BoxDecoration(
        color: l.background,
        border: outline,
        borderRadius: BorderRadius.circular(l.xl),
        boxShadow: l.shadows,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(math.max(0, l.xl - bw)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (chrome != null) _titleBar(l, chrome) else _header(l),
            _messages(l),
            _composer(l),
          ],
        ),
      ),
    );
  }

  /// Window chrome: the title bar in the header's place — the heading, lower
  /// case, after the online dot; the chevron back to the call (or closing a
  /// chat-only agent) at the right end; no launcher mark.
  Widget _titleBar(ChatLook l, ChromeLook chrome) => WindowTitleBar(
        look: chrome,
        surface: ChromeSurface.chat,
        title: WindowChrome.title(ChromeSurface.chat, heading: widget.heading),
        online: widget.online,
        topRadius: WindowChrome.innerRadius(l.xl, l.borderWidth),
        trailing: Tap(
          key: ChatWindow.collapseKey,
          label: 'Collapse',
          onTap: widget.onCollapse,
          child: Padding(
            padding: const EdgeInsets.all((WindowChrome.chevronBox - WindowChrome.chevronIcon) / 2),
            child: SdkIconView('chevron',
                color: l.muted, size: WindowChrome.chevronIcon, style: l.iconStyle, stroke: l.iconStroke, turned: true),
          ),
        ),
      );

  Widget _header(ChatLook l) {
    final line = l.borderWidth > 0 ? l.borderWidth : 0.0;
    final initial = initialOf(widget.heading);
    final mark = Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: l.accent, borderRadius: BorderRadius.circular(l.markRadius)),
      child: l.glyph != null
          ? BrandMark(
              glyph: l.glyph,
              colorHex: l.onAccentHex,
              size: 14,
              stroke: l.iconStroke,
              logoUrl: widget.logoUrl,
              name: widget.heading,
              origin: widget.origin,
            )
          : (widget.logoUrl != null && widget.logoUrl!.isNotEmpty)
              ? Image.network(widget.logoUrl!,
                  width: 14,
                  height: 14,
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                  errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                      Text(initial, style: textStyle(l.onAccent, 12, weight: 700, height: 1)))
              : Text(initial, style: textStyle(l.onAccent, 12, weight: 700, height: 1)),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        surfaceBox(
          key: ChatWindow.headerKey,
          color: l.header,
          border: l.border,
          borderWidth: 0,
          radius: BorderRadius.zero,
          shadows: const <BoxShadow>[],
          glass: l.glass,
          height: 50 - line,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: <Widget>[
              mark,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(widget.heading, maxLines: 1, overflow: TextOverflow.ellipsis, style: l.titleStyle),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (widget.online) ...<Widget>[
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(color: l.success, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(widget.online ? 'Online' : 'Connecting…', style: l.statusStyle),
                      ],
                    ),
                  ],
                ),
              ),
              Tap(
                key: ChatWindow.collapseKey,
                label: 'Collapse',
                onTap: widget.onCollapse,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: SdkIconView('chevron',
                      color: l.muted, size: 18, style: l.iconStyle, stroke: l.iconStroke, turned: true),
                ),
              ),
            ],
          ),
        ),
        // The header's bottom outline.
        if (line > 0) Container(height: line, color: l.border),
      ],
    );
  }

  Widget _messages(ChatLook l) {
    final said = widget.messages.where((Caption m) => m.text.trim().isNotEmpty).toList();
    final empty = widget.online ? '${widget.heading} can see what you’re looking at — ask it anything.' : 'Connecting…';
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.lifted ? 150 : 260),
      child: said.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Text(empty, style: l.bodyStyle.copyWith(color: l.muted)),
            )
          : SingleChildScrollView(
              // Newest at the bottom, and the bottom is where it opens.
              reverse: true,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (var i = 0; i < said.length; i++) ...<Widget>[
                    if (i > 0) SizedBox(height: l.gap),
                    chatBubble(l, said[i], key: ChatWindow.messageKey(i)),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _composer(ChatLook l) {
    final ready = _draft.text.trim().isNotEmpty;
    final bw = l.borderWidth;
    return Container(
      height: 58,
      color: l.background,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: <Widget>[
          Expanded(
            // The whole field focuses the text, not only its one line.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _focus.requestFocus,
              child: Container(
                key: ChatWindow.composerKey,
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: l.raised,
                  border: bw > 0 ? Border.all(color: l.border, width: bw) : null,
                  borderRadius: BorderRadius.circular(l.xl),
                ),
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: <Widget>[
                    if (_draft.text.isEmpty)
                      IgnorePointer(
                        child: Text('Message…',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: l.inputStyle.copyWith(color: l.muted)),
                      ),
                    // EditableText, not a Material TextField: the bar sits above
                    // the app's Navigator, where there is no Material and no
                    // Overlay for a text field's handles to live in.
                    EditableText(
                      controller: _draft,
                      focusNode: _focus,
                      style: l.inputStyle,
                      cursorColor: l.accent,
                      backgroundCursorColor: l.muted,
                      maxLines: 1,
                      textInputAction: TextInputAction.send,
                      // Sent, and the keyboard stays up for the next message.
                      onEditingComplete: () {},
                      onSubmitted: (String _) => _submit(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tap(
            key: ChatWindow.sendKey,
            label: 'Send',
            enabled: ready,
            onTap: _submit,
            child: Opacity(
              opacity: ready ? 1 : 0.4,
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: l.accent, shape: BoxShape.circle),
                child: SdkIconView('send', color: l.onAccent, size: 18, style: l.iconStyle, stroke: l.iconStroke),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ONE MESSAGE, per contract/DESIGN.md: at most 84% of the width, on the
/// speaker's side; corners `radius.lg` with the one nearest the speaker at
/// `radius.sm`; padding `cardPadding × 0.75` by `cardPadding`. `filled` —
/// each side its own colours; `outline` — both clear, the customer outlined
/// in `accent`, the agent in `border`, text in `text`; `minimal` — the
/// agent's words plain on the page, the customer's on `accentSoft`.
Widget chatBubble(ChatLook l, Caption m, {Key? key}) {
  final user = m.role != Role.agent;
  Color? fill;
  Color ink;
  Border? outline;
  switch (l.bubbles) {
    case 'outline':
      fill = null;
      ink = l.text;
      if (l.borderWidth > 0) outline = Border.all(color: user ? l.accent : l.border, width: l.borderWidth);
    case 'minimal':
      fill = user ? l.soft : null;
      ink = l.text;
    default: // filled
      fill = user ? l.userBubble : l.agentBubble;
      ink = user ? l.userBubbleText : l.agentBubbleText;
  }
  final bare = l.bubbles == 'minimal' && !user;
  final lg = Radius.circular(l.lg);
  final sm = Radius.circular(l.sm);
  final box = Container(
    key: key,
    padding: bare
        ? const EdgeInsets.all(2)
        : EdgeInsets.symmetric(horizontal: l.pad, vertical: (l.pad * 0.75).roundToDouble()),
    decoration: bare
        ? null
        : BoxDecoration(
            color: fill,
            border: outline,
            borderRadius: BorderRadius.only(
              topLeft: lg,
              topRight: lg,
              bottomLeft: user ? lg : sm,
              bottomRight: user ? sm : lg,
            ),
          ),
    child: Opacity(opacity: m.live ? 0.75 : 1, child: Text(m.text, style: l.bodyStyle.copyWith(color: ink))),
  );
  final side = user ? Alignment.centerRight : Alignment.centerLeft;
  return FractionallySizedBox(widthFactor: 0.84, alignment: side, child: Align(alignment: side, child: box));
}
