// The chat window the voice bar opens above itself when the customer is in
// the chat, and GraineChat fills a screen with. Not exported: GraineAgentBar
// and GraineChat draw it from a GraineChatState.
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
    required this.md,
    required this.lg,
    required this.xl,
    required this.pad,
    required this.gap,
    required this.markRadius,
    required this.markRadius48,
    this.markShape = 'circle',
    required this.glyph,
    required this.iconStyle,
    required this.iconStroke,
    required this.shadows,
    required this.cardShadows,
    required this.cardFill,
    required this.cardBody,
    required this.titleStyle,
    required this.statusStyle,
    required this.bodyStyle,
    required this.inputStyle,
    required this.timeStyle,
    required this.emptyTitleStyle,
    required this.emptySubtitleStyle,
    required this.starterStyle,
    required this.cardTitleStyle,
    required this.rowTimeStyle,
    required this.rowNameStyle,
    required this.cancelStyle,
    this.glass,
    this.chrome,
    this.designed = false,
    this.title = '',
    this.subtitle = '',
    this.avatar,
    this.placeholder = '',
    this.showTimestamps = false,
    this.suggestions = const <String>[],
    this.pattern,
    this.showUpcomingCalls = true,
    this.upcomingTitle = '',
    this.showHistory = true,
    this.newConversation = true,
    Color? dot,
    Color? chevron,
    Color? composerBorder,
    Color? composerPlaceholder,
  })  : dot = dot ?? success,
        chevron = chevron ?? muted,
        composerBorder = composerBorder ?? border,
        composerPlaceholder = composerPlaceholder ?? muted;

  factory ChatLook.design(ThemeTokens t, {Color? accent}) {
    final c = t.colors;
    final f = t.font;
    // The chat's own tokens (contract §7) — from an older server, the window
    // exactly as it was drawn before them.
    final k = t.chat;
    final text = tokenColor(c.text);
    final muted = tokenColor(c.textMuted);
    final surface = tokenColor(c.surface);
    final headerFill = tokenColor(k.headerBackground);
    // A surface header is the design's surface; any other (the accent) is solid,
    // and its online dot is drawn in the header's own text colour.
    final surfaceHeader = Design.normaliseHex(k.headerBackground) == Design.normaliseHex(c.surface);
    final glass = surfaceHeader ? t.glass : null;
    final a = accent ?? tokenColor(c.accent);
    final titleSize = math.min(f.scale.title, 16).toDouble();
    final emptySize = math.min(f.scale.title, 18).toDouble();
    final timeSize = math.max(10, f.scale.caption - 1).toDouble();
    // A pill is drawn as a circle at this size: a 30-point mark has no label to be wide for.
    final shape = t.shape.launcher == 'pill' ? 'circle' : t.shape.launcher;
    return ChatLook(
      background: tokenColor(k.background),
      header: glass == null ? headerFill : fade(headerFill, glass.surfaceOpacity),
      raised: tokenColor(k.composerBackground),
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
      md: t.shape.radius.md,
      lg: t.shape.radius.lg,
      xl: t.shape.radius.xl,
      pad: t.spacing.cardPadding,
      gap: t.spacing.gap,
      markRadius: Design.launcherRadius(shape, t.shape.radius, 30),
      markRadius48: Design.launcherRadius(shape, t.shape.radius, 48),
      markShape: shape,
      glyph: t.icons.launcher,
      iconStyle: t.icons.style,
      iconStroke: t.icons.stroke,
      shadows: raisedShadows(t, t.elevation.floating, text),
      cardShadows: raisedShadows(t, t.elevation.card, text),
      cardFill: tokenColor(c.surfaceRaised),
      cardBody: surface,
      titleStyle: designText(tokenColor(k.headerText), titleSize, f.heading, f.weights.title,
          height: f.lineHeight.title, letterSpacing: em(titleSize, f.letterSpacing.title)),
      statusStyle: designText(tokenColor(k.headerSubtext), f.scale.caption, f.body, f.weights.body,
          height: 1.2, letterSpacing: em(f.scale.caption, f.letterSpacing.body)),
      bodyStyle: designText(text, f.scale.body, f.body, f.weights.body,
          height: f.lineHeight.body, letterSpacing: em(f.scale.body, f.letterSpacing.body)),
      inputStyle: designText(tokenColor(k.composerText), f.scale.body - 1, f.body, f.weights.body),
      timeStyle: designText(muted, timeSize, f.body, f.weights.body),
      emptyTitleStyle: designText(text, emptySize, f.heading, f.weights.title,
          height: f.lineHeight.title, letterSpacing: em(emptySize, f.letterSpacing.title)),
      emptySubtitleStyle: designText(muted, f.scale.caption, f.body, f.weights.body),
      starterStyle: designText(text, f.scale.body - 1, f.body, f.weights.strong),
      cardTitleStyle: designText(muted, f.scale.caption, f.body, f.weights.strong),
      rowTimeStyle: designText(text, f.scale.body - 1, f.body, f.weights.strong),
      rowNameStyle: designText(muted, f.scale.caption, f.body, f.weights.body),
      cancelStyle: designText(text, f.scale.caption, f.body, f.weights.strong),
      glass: glass,
      chrome: ChromeLook.of(t),
      designed: t.servedChat != null,
      title: k.title.trim(),
      subtitle: k.subtitle.trim(),
      avatar: k.avatar,
      placeholder: k.placeholder.trim(),
      showTimestamps: k.showTimestamps,
      suggestions: k.suggestions,
      pattern: k.pattern == 'dots' ? tokenColor(k.patternColor) : null,
      showUpcomingCalls: k.showUpcomingCalls,
      upcomingTitle: k.upcomingTitle.trim(),
      showHistory: k.showHistory,
      newConversation: k.newConversation,
      dot: surfaceHeader ? tokenColor(c.success) : tokenColor(k.headerText),
      chevron: tokenColor(k.headerSubtext),
      composerBorder: tokenColor(k.composerBorder),
      composerPlaceholder: tokenColor(k.composerPlaceholder),
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
      md: math.min(radius, 12),
      lg: math.min(radius, 16),
      xl: math.min(26, radius + 8),
      pad: 12,
      gap: 8,
      markRadius: 15,
      markRadius48: 24,
      glyph: null,
      iconStyle: 'outline',
      iconStroke: 2,
      shadows: shadows,
      cardShadows: const <BoxShadow>[BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2))],
      cardFill: dark ? const Color(0xFF1F2024) : const Color(0xFFF7F7F5),
      cardBody: surface,
      titleStyle: textStyle(text, 15, weight: 700, height: 1.25),
      statusStyle: textStyle(muted, 12, height: 1.2),
      bodyStyle: textStyle(text, 14.5, height: 21 / 14.5),
      inputStyle: textStyle(text, 14),
      timeStyle: textStyle(muted, 11),
      emptyTitleStyle: textStyle(text, 17, weight: 700, height: 1.25),
      emptySubtitleStyle: textStyle(muted, 12),
      starterStyle: textStyle(text, 13.5, weight: 600),
      cardTitleStyle: textStyle(muted, 12, weight: 600),
      rowTimeStyle: textStyle(text, 13.5, weight: 600),
      rowNameStyle: textStyle(muted, 12),
      cancelStyle: textStyle(text, 12, weight: 600),
    );
  }

  final Color background;

  /// The header's fill: `chat.headerBackground`, translucent with [glass].
  final Color header;

  /// The composer field: `chat.composerBackground`.
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
  final double md;
  final double lg;
  final double xl;

  /// `spacing.cardPadding` and `spacing.gap`.
  final double pad;
  final double gap;

  /// The 30-point launcher mark's corners, and the 48-point one's (the empty chat).
  final double markRadius;
  final double markRadius48;

  /// The mark's shape — the launcher's, a pill drawn as a circle — which
  /// sets the square the brand's logo is fitted into ([BrandLogo.box]).
  final String markShape;
  final LauncherGlyph? glyph;
  final String iconStyle;
  final double iconStroke;

  /// The window's depth: `elevation.floating`, or the solid offset.
  final List<BoxShadow> shadows;

  /// The Upcoming calls card's: `elevation.card`, or the solid offset.
  final List<BoxShadow> cardShadows;

  /// The Upcoming calls card: `surfaceRaised` — and, under a window-chrome
  /// title bar, its body `surface`.
  final Color cardFill;
  final Color cardBody;
  final TextStyle titleStyle;
  final TextStyle statusStyle;
  final TextStyle bodyStyle;
  final TextStyle inputStyle;
  final TextStyle timeStyle;
  final TextStyle emptyTitleStyle;
  final TextStyle emptySubtitleStyle;
  final TextStyle starterStyle;
  final TextStyle cardTitleStyle;
  final TextStyle rowTimeStyle;
  final TextStyle rowNameStyle;
  final TextStyle cancelStyle;

  /// A day separator's words: caption size, strong, muted — the card title's style.
  TextStyle get dayStyle => cardTitleStyle;

  /// An earlier call's row: caption size, muted — the booked call's name style.
  TextStyle get callStyle => rowNameStyle;

  /// Only on a surface header: an accent header is solid.
  final ThemeGlass? glass;

  /// The design opens the chat as a desktop window: its title bar replaces
  /// the header. Null — a design without window chrome, or none — keeps the header.
  final ChromeLook? chrome;

  /// The session carried the chat's tokens: the empty chat is the avatar and
  /// the title. Without them (an older server) it is the sentence it always was.
  final bool designed;

  /// The brand's title for the header; "" is the heading.
  final String title;

  /// Under the title while online; "" is "Online".
  final String subtitle;

  /// The header's mark: `logo`, `glyph` or `none`; null — before designs —
  /// the launcher's mark as it always was (its glyph, else the logo).
  final String? avatar;

  /// The composer's placeholder; "" is "Message…".
  final String placeholder;
  final bool showTimestamps;

  /// Conversation starters for a chat the customer has not written in yet.
  final List<String> suggestions;

  /// The dot pattern's colour over [background]; null for none.
  final Color? pattern;

  /// The pieces the design can leave out (contract/DESIGN.md, "Chat window"):
  /// the booked-calls card and its title ("" is the SDK's words), the
  /// earlier messages, and the header's "New conversation". On before designs.
  final bool showUpcomingCalls;
  final String upcomingTitle;
  final bool showHistory;
  final bool newConversation;

  /// The online dot: `success` on a surface header, the header's text colour on any other.
  final Color dot;

  /// The collapse chevron: `chat.headerSubtext`.
  final Color chevron;
  final Color composerBorder;
  final Color composerPlaceholder;

  Color get onAccent => tokenColor(onAccentHex);
}

/// THE CHAT WINDOW (contract/DESIGN.md, "Chat window"): the page in
/// `chat.background` with an outline, `radius.xl` corners and the floating
/// shadow (or the hard offset); a 50-point header on `chat.headerBackground` —
/// the avatar, the title in the heading face, the status after its dot, and a
/// chevron back to the call; the Upcoming calls card, the messages as bubbles
/// in the design's style (or the empty chat), the starters and a 58-point
/// composer. A design with window chrome replaces the header with a 32-point
/// title bar ("Window chrome"): the traffic lights, the title lower case in
/// the platform's monospace after the online dot, and the chevron at its right
/// end — no avatar. From an older server it draws exactly as before the
/// chat's tokens.
class ChatWindow extends StatefulWidget {
  const ChatWindow({
    super.key,
    required this.look,
    required this.heading,
    required this.messages,
    required this.online,
    required this.onSend,
    this.onCollapse,
    this.logoUrl,
    this.logoPlate = LogoPlate.accent,
    this.origin,
    this.lifted = false,
    this.typing = false,
    this.fill = false,
    this.keepFrame = false,
    this.leadingChevron = false,
    this.collapseLabel = 'Collapse',
    this.below,
    this.connectingText,
    this.upcoming = const <GraineScheduledCall>[],
    this.cancelStateOf,
    this.onCancelUpcoming,
    this.callName,
    this.now,
    this.turns,
    this.onNewConversation,
    this.bookingAvailable = false,
    this.onBook,
  });

  final ChatLook look;
  final String heading;
  final List<Caption> messages;

  /// The SDK's own chat's turns — when given, drawn instead of [messages],
  /// with their times and delivery.
  final List<GraineChatTurn>? turns;

  /// The chat is connected: the subtitle ("Online"), else "Connecting…".
  final bool online;
  final ValueChanged<String> onSend;

  /// The chevron: back to the call, or — an agent that is only a chat —
  /// closed. Null: no chevron.
  final VoidCallback? onCollapse;
  final String? logoUrl;

  /// What the logo sits on in the header's mark: the accent, or white with a hairline.
  final LogoPlate logoPlate;
  final String? origin;

  /// The keyboard is up: fewer messages, so the composer stays in view.
  final bool lifted;

  /// The agent is composing: a typing bubble after the last message.
  final bool typing;

  /// Fill the space given — a full-screen chat ([GraineChat]): square, no
  /// outline or shadow, the messages taking every point the header and the
  /// composer leave.
  final bool fill;

  /// Filling its space but keeping the whole frame — outline, corners, shadow:
  /// a tablet's panel (contract/DESIGN.md "Chat window" → Size).
  final bool keepFrame;

  /// The chevron leads the header, before the avatar: a full screen has no
  /// corner to close it by. (With window chrome it stays at the bar's end.)
  final bool leadingChevron;

  /// What the chevron is called: "Collapse" back to a call, "Close" where the chat is all there is.
  final String collapseLabel;

  /// Drawn between the messages and the composer — the components the agent
  /// draws in a full-screen chat.
  final Widget? below;

  /// The loader's words for connecting; default "Connecting…".
  final String? connectingText;

  /// The user's booked calls, soonest first: the Upcoming calls card (the
  /// first three). Empty: no card.
  final List<GraineScheduledCall> upcoming;

  /// Where each booked call's Cancel is.
  final GraineUpcomingCancel Function(String id)? cancelStateOf;

  /// A booked call's Cancel was tapped.
  final ValueChanged<String>? onCancelUpcoming;

  /// What a booked call is called — the agent's call name; default the
  /// chat's title, else the heading ([Booking.callName]).
  final String? callName;

  /// The time now, for "Today" and "Tomorrow" (tests).
  final DateTime Function()? now;

  /// "New conversation" — the compose icon in the header, offered only while
  /// [turns] holds an earlier conversation (restored turns). Null: never.
  final VoidCallback? onNewConversation;

  /// Booking is available here (`GraineInApp.bookingAvailable`): "Book a
  /// call" in the Upcoming calls card — or, while nothing is booked, a
  /// compact row in its place — opening [onBook].
  final bool bookingAvailable;

  /// Opens the booking sheet. Null: no "Book a call".
  final VoidCallback? onBook;

  /// "Book a call": in the card, or the row in its place.
  static const Key bookKey = ValueKey<String>('graine-chat-book');

  /// The header's "New conversation".
  static const Key newConversationKey = ValueKey<String>('graine-chat-new-conversation');

  /// A day separator, by its local date (YYYY-MM-DD).
  static Key dayKey(String date) => ValueKey<String>('graine-chat-day-$date');

  /// An earlier call's one row, by its first turn's id.
  static Key voiceKey(String turnId) => ValueKey<String>('graine-chat-voice-$turnId');

  static const Key headerKey = ValueKey<String>('graine-chat-header');
  static const Key composerKey = ValueKey<String>('graine-chat-composer');
  static const Key sendKey = ValueKey<String>('graine-chat-send');
  static const Key collapseKey = ValueKey<String>('graine-chat-collapse');

  /// The typing bubble.
  static const Key typingKey = ValueKey<String>('graine-chat-typing');

  /// The row of conversation starters.
  static const Key suggestionsKey = ValueKey<String>('graine-chat-suggestions');

  /// The empty chat: the avatar, the title and the subtitle.
  static const Key emptyKey = ValueKey<String>('graine-chat-empty');

  /// The header's avatar.
  static const Key avatarKey = ValueKey<String>('graine-chat-avatar');

  /// The Upcoming calls card.
  static const Key upcomingKey = ValueKey<String>('graine-chat-upcoming');

  /// The [index]th message's bubble (oldest is 0).
  static Key messageKey(int index) => ValueKey<String>('graine-chat-message-$index');

  /// The [index]th conversation starter.
  static Key suggestionKey(int index) => ValueKey<String>('graine-chat-suggestion-$index');

  /// A booked call's row, and its Cancel.
  static Key upcomingRowKey(String id) => ValueKey<String>('graine-chat-upcoming-$id');
  static Key cancelKey(String id) => ValueKey<String>('graine-chat-cancel-$id');

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

  /// The header's title: the brand's, else the heading.
  String get _title => widget.look.title.isNotEmpty ? widget.look.title : widget.heading;

  /// What the window draws of the pieces the design can leave out: earlier
  /// messages, "New conversation", the booked-calls card. Null without the
  /// SDK's own turns (captions carry no earlier conversation).
  ChatPieces? get _pieces {
    final turns = widget.turns;
    if (turns == null) return null;
    final l = widget.look;
    return ChatPieces.of(
      turns,
      showHistory: l.showHistory,
      newConversation: l.newConversation,
      showUpcomingCalls: l.showUpcomingCalls,
      upcomingTitle: l.upcomingTitle,
      upcomingCount: math.min(widget.upcoming.length, 3),
      bookingAvailable: widget.bookingAvailable && widget.onBook != null,
    );
  }

  /// "Book a call" is offered: the design keeps the booked-calls piece and
  /// booking is available — the same rule with or without the SDK's turns.
  bool get _book =>
      _pieces?.book ?? (widget.look.showUpcomingCalls && widget.bookingAvailable && widget.onBook != null);

  bool get _h24 => MediaQuery.maybeAlwaysUse24HourFormatOf(context) ?? false;

  @override
  Widget build(BuildContext context) {
    final l = widget.look;
    final bw = l.borderWidth;
    final framed = !widget.fill || widget.keepFrame;
    final outline = bw > 0 && framed ? Border.all(color: l.border, width: bw) : null;
    final chrome = l.chrome;
    final radius = framed ? l.xl : 0.0;
    final starters = _starters();
    return Container(
      decoration: BoxDecoration(
        color: l.background,
        border: outline,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: framed ? l.shadows : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(math.max(0, radius - (outline == null ? 0 : bw))),
        child: Column(
          mainAxisSize: widget.fill ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (chrome != null) _titleBar(l, chrome) else _header(l),
            if (widget.fill) Expanded(child: _thread(l)) else _thread(l),
            if (widget.below != null) widget.below!,
            if (starters.isNotEmpty) _suggestions(l, starters),
            _composer(l),
          ],
        ),
      ),
    );
  }

  /// "New conversation": the compose icon beside the chevron, only while the
  /// window holds an earlier conversation.
  Widget? _compose(ChatLook l, double padding, double size) {
    final start = widget.onNewConversation;
    final pieces = _pieces;
    if (start == null || pieces == null || !pieces.newConversation) return null;
    return Tap(
      key: ChatWindow.newConversationKey,
      label: 'New conversation',
      onTap: start,
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: SdkIconView('compose', color: l.chevron, size: size, style: l.iconStyle, stroke: l.iconStroke),
      ),
    );
  }

  Widget? _chevron(ChatLook l, double padding, double size) {
    final collapse = widget.onCollapse;
    if (collapse == null) return null;
    return Tap(
      key: ChatWindow.collapseKey,
      label: widget.collapseLabel,
      onTap: collapse,
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: SdkIconView('chevron', color: l.chevron, size: size, style: l.iconStyle, stroke: l.iconStroke, turned: true),
      ),
    );
  }

  /// Window chrome: the title bar in the header's place — the title, lower
  /// case, after the online dot; the chevron back to the call (or closing a
  /// chat-only agent) at the right end; no avatar.
  Widget _titleBar(ChatLook l, ChromeLook chrome) => WindowTitleBar(
        look: chrome,
        surface: ChromeSurface.chat,
        title: WindowChrome.title(ChromeSurface.chat, heading: _title),
        online: widget.online,
        topRadius: widget.fill && !widget.keepFrame ? 0 : WindowChrome.innerRadius(l.xl, l.borderWidth),
        trailing: _trailing(l),
      );

  /// The title bar's right end: "New conversation" (while there is history to
  /// start over from) beside the chevron.
  Widget? _trailing(ChatLook l) {
    final pad = (WindowChrome.chevronBox - WindowChrome.chevronIcon) / 2;
    final chevron = _chevron(l, pad, WindowChrome.chevronIcon);
    final compose = _compose(l, pad, WindowChrome.chevronIcon);
    if (compose == null) return chevron;
    return Row(mainAxisSize: MainAxisSize.min, children: <Widget>[compose, if (chevron != null) chevron]);
  }

  /// THE AVATAR at [size] (30 in the header, 48 in the empty chat), per
  /// `chat.avatar`: `logo` — the brand's logo, whole, on its plate; with none
  /// uploaded, the launcher glyph when the design has one, else the title's
  /// first letter. `glyph` — the launcher mark. `none` — nothing. Before the
  /// chat's tokens: the launcher's mark as it always was.
  Widget? _avatar(ChatLook l, double size, {Key? key}) {
    final avatar = l.avatar ?? (l.glyph != null ? 'glyph' : 'logo');
    if (avatar == 'none') return null;
    final url = widget.logoUrl;
    final logo = url != null && url.isNotEmpty ? url : null;
    final glyph = (avatar == 'glyph' || logo == null) ? l.glyph : null;
    final onPlate = glyph == null && logo != null ? widget.logoPlate : LogoPlate.accent;
    final fill = logoPlateOf(onPlate, accent: l.accent, border: l.border, borderWidth: l.borderWidth);
    final box = BrandLogo.box(l.markShape, size).toDouble();
    Widget letter() => Text(initialOf(_title),
        style: textStyle(tokenColor(inkOnPlate(onPlate, l.onAccentHex)), size * 0.4, weight: 700, height: 1));
    return Container(
      key: key,
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: fill.color,
        borderRadius: BorderRadius.circular(size == 30 ? l.markRadius : l.markRadius48),
        border: fill.border,
      ),
      child: glyph != null
          ? BrandMark(
              glyph: glyph,
              colorHex: l.onAccentHex,
              size: (size * Design.launcherGlyphScale).roundToDouble(),
              stroke: l.iconStroke,
              logoUrl: widget.logoUrl,
              logoSize: box,
              name: _title,
              origin: widget.origin,
            )
          : logo != null
              ? logoWhole(logo, box, fallback: letter)
              : letter(),
    );
  }

  Widget _header(ChatLook l) {
    final line = l.borderWidth > 0 ? l.borderWidth : 0.0;
    final mark = _avatar(l, 30, key: ChatWindow.avatarKey);
    final online = l.subtitle.isNotEmpty ? l.subtitle : 'Online';
    final chevron = _chevron(l, 6, 18);
    final compose = _compose(l, 6, 18);
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
              // A full screen: the chevron leads.
              if (chevron != null && widget.leadingChevron) ...<Widget>[chevron, const SizedBox(width: 10)],
              if (mark != null) ...<Widget>[mark, const SizedBox(width: 10)],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis, style: l.titleStyle),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (widget.online) ...<Widget>[
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(color: l.dot, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(widget.online ? online : (widget.connectingText ?? 'Connecting…'),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: l.statusStyle),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (compose != null) ...<Widget>[const SizedBox(width: 10), compose],
              if (chevron != null && !widget.leadingChevron) ...<Widget>[const SizedBox(width: 10), chevron],
            ],
          ),
        ),
        // The header's bottom outline.
        if (line > 0) Container(height: line, color: l.border),
      ],
    );
  }

  /// THE THREAD: the Upcoming calls card first, then the messages (or the
  /// empty chat) and the typing bubble, over the dot pattern, which stands
  /// still while they scroll.
  /// The lines to draw: the turns (with their times and delivery) — a day
  /// line where the day changes, and an earlier call as one row — else the
  /// captions.
  List<_Line> _lines() {
    final turns = _pieces?.turns;
    if (turns != null) {
      final said = <GraineChatTurn>[
        for (final t in turns)
          if (t.text.trim().isNotEmpty) t,
      ];
      final now = (widget.now ?? DateTime.now)();
      return <_Line>[
        for (final row in ChatRows.build(said, now: now))
          switch (row) {
            ChatDayRow() => _Line.day(ChatRows.dayLabel(row, now: now), key: ChatWindow.dayKey(row.date)),
            ChatVoiceRow() => _Line.call(row.at, key: ChatWindow.voiceKey(row.id.substring('voice-'.length))),
            ChatTurnRow(turn: final t) => _Line(t.caption,
                at: t.at, unsent: t.delivery == GraineChatDelivery.sending || t.delivery == GraineChatDelivery.failed),
          },
      ];
    }
    return <_Line>[
      for (final m in widget.messages)
        if (m.text.trim().isNotEmpty) _Line(m),
    ];
  }

  Widget _thread(ChatLook l) {
    final said = _lines();
    final card = _upcomingCard(l);
    final Widget content;
    if (said.isEmpty && !widget.typing) {
      final empty = l.designed ? _emptyChat(l) : _emptySentence(l);
      content = card == null
          ? (widget.fill ? Center(child: SingleChildScrollView(child: empty)) : empty)
          : SingleChildScrollView(
              reverse: true,
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[card, SizedBox(height: l.gap), empty],
              ),
            );
    } else {
      content = SingleChildScrollView(
        // Newest at the bottom, and the bottom is where it opens.
        reverse: true,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (card != null) ...<Widget>[card, SizedBox(height: l.gap)],
            for (var i = 0, m = 0; i < said.length; i++) ...<Widget>[
              if (i > 0) SizedBox(height: l.gap),
              if (said[i].dayLabel != null)
                _dayLine(l, said[i])
              else if (said[i].callAt != null)
                _callLine(l, said[i])
              else ...<Widget>[
                chatBubble(l, said[i].caption, key: ChatWindow.messageKey(m++), unsent: said[i].unsent),
                if (l.showTimestamps) _time(l, said[i]),
              ],
            ],
            if (widget.typing) ...<Widget>[
              if (said.isNotEmpty) SizedBox(height: l.gap),
              _TypingBubble(key: ChatWindow.typingKey, look: l),
            ],
          ],
        ),
      );
    }
    final pattern = l.pattern;
    final painted = pattern == null ? content : CustomPaint(painter: _DotPattern(pattern), child: content);
    if (widget.fill) return painted;
    return ConstrainedBox(constraints: BoxConstraints(maxHeight: widget.lifted ? 150 : 260), child: painted);
  }

  /// Before the chat's tokens: the sentence the window always opened with.
  Widget _emptySentence(ChatLook l) {
    final empty = widget.online ? '${widget.heading} can see what you’re looking at — ask it anything.' : 'Connecting…';
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(empty, style: l.bodyStyle.copyWith(color: l.muted)),
    );
  }

  /// THE EMPTY CHAT: the avatar at 48, the title 12 below it, the subtitle 4
  /// below that (only when the brand wrote one) — centred, no dot.
  Widget _emptyChat(ChatLook l) {
    final mark = _avatar(l, 48);
    return Padding(
      key: ChatWindow.emptyKey,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (mark != null) ...<Widget>[mark, const SizedBox(height: 12)],
          Text(_title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: l.emptyTitleStyle),
          if (l.subtitle.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(l.subtitle, textAlign: TextAlign.center, style: l.emptySubtitleStyle),
          ],
        ],
      ),
    );
  }

  /// A day separator: centred, caption size, strong, muted (DESIGN.md "Day separators").
  Widget _dayLine(ChatLook l, _Line line) => Semantics(
        key: line.key,
        header: true,
        child: Text(line.dayLabel!, textAlign: TextAlign.center, style: l.dayStyle),
      );

  /// An earlier call, as one row: the call icon and "Voice call · 6:05 PM" —
  /// that it happened, never what was said.
  Widget _callLine(ChatLook l, _Line line) {
    final clock = ChatTime.clock(line.callAt!, h24: _h24);
    return Semantics(
      key: line.key,
      label: ChatRows.callSpoken(clock),
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          SdkIconView('call', color: l.muted, size: 14, style: l.iconStyle, stroke: l.iconStroke),
          const SizedBox(width: 6),
          Flexible(child: Text(ChatRows.callLabel(clock), maxLines: 1, overflow: TextOverflow.ellipsis, style: l.callStyle)),
        ],
      ),
    );
  }

  /// When a message was said, 4 under it, on its speaker's side, in the
  /// device's short time.
  Widget _time(ChatLook l, _Line line) {
    final at = line.at;
    if (at == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        ChatTime.clock(at, h24: _h24),
        textAlign: line.caption.role == Role.agent ? TextAlign.left : TextAlign.right,
        style: l.timeStyle,
      ),
    );
  }

  /// THE UPCOMING CALLS CARD — a component card: the soonest three booked
  /// calls, each with its time in the device's zone, the call's name, and
  /// Cancel. No booked calls, no card.
  Widget? _upcomingCard(ChatLook l) {
    final calls = widget.upcoming;
    if (!l.showUpcomingCalls) return null;
    // Nothing booked: where booking is available, "Book a call" stands in the card's place.
    if (calls.isEmpty) return _book ? _bookRow(l) : null;
    final shown = calls.take(3).length;
    final title = l.upcomingTitle.isNotEmpty ? l.upcomingTitle : (shown == 1 ? 'Upcoming call' : 'Upcoming calls');
    final now = (widget.now ?? DateTime.now)();
    final rows = <Widget>[
      for (final c in calls.take(3)) _upcomingRow(l, c, now),
    ];
    final bw = l.borderWidth;
    final chrome = l.chrome;
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // In window chrome the title moves into the bar.
        if (chrome == null) ...<Widget>[Text(title, style: l.cardTitleStyle), SizedBox(height: l.gap)],
        for (var i = 0; i < rows.length; i++) ...<Widget>[if (i > 0) SizedBox(height: l.gap), rows[i]],
        if (_book) ...<Widget>[SizedBox(height: l.gap), _bookButton(l)],
      ],
    );
    final decoration = BoxDecoration(
      color: chrome == null ? l.cardFill : l.cardBody,
      border: bw > 0 ? Border.all(color: l.border, width: bw) : null,
      borderRadius: BorderRadius.circular(l.lg),
      boxShadow: l.cardShadows,
    );
    if (chrome == null) {
      return Container(
        key: ChatWindow.upcomingKey,
        padding: EdgeInsets.all(l.pad),
        decoration: decoration,
        child: body,
      );
    }
    return Container(
      key: ChatWindow.upcomingKey,
      decoration: decoration,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          WindowTitleBar(
            look: chrome,
            surface: ChromeSurface.component,
            title: WindowChrome.title(ChromeSurface.component, componentTitle: title),
            topRadius: WindowChrome.innerRadius(l.lg, bw),
          ),
          Padding(padding: EdgeInsets.all(l.pad), child: body),
        ],
      ),
    );
  }

  /// "Book a call" closing the card: as wide as it, 32 high, outlined in the
  /// accent, the call icon before the words.
  Widget _bookButton(ChatLook l) => Tap(
        key: ChatWindow.bookKey,
        label: 'Book a call',
        onTap: widget.onBook,
        child: Container(
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: l.accent, width: math.max(1, l.borderWidth)),
            borderRadius: BorderRadius.circular(math.min(l.md, 16)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SdkIconView('call', color: l.accent, size: 14, style: l.iconStyle, stroke: l.iconStroke),
              const SizedBox(width: 6),
              Text('Book a call', style: l.cancelStyle),
            ],
          ),
        ),
      );

  /// "Book a call" in the card's place while nothing is booked: one compact
  /// row drawn like the card's — the accent disc with the call icon, the
  /// words, and "{call name} will call you" under them.
  Widget _bookRow(ChatLook l) {
    final name = Booking.callName(<String?>[widget.callName, l.title, widget.heading]);
    return Tap(
      key: ChatWindow.bookKey,
      label: 'Book a call',
      onTap: widget.onBook,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: l.pad, vertical: (l.pad * 0.75).roundToDouble()),
        decoration: BoxDecoration(
          color: l.cardFill,
          border: l.borderWidth > 0 ? Border.all(color: l.border, width: l.borderWidth) : null,
          borderRadius: BorderRadius.circular(l.lg),
          boxShadow: l.cardShadows,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: l.accent, shape: BoxShape.circle),
              child: SdkIconView('call', color: l.onAccent, size: 16, style: l.iconStyle, stroke: l.iconStroke),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Book a call', maxLines: 1, overflow: TextOverflow.ellipsis, style: l.rowTimeStyle),
                  Text(Booking.subtitle(name), maxLines: 1, overflow: TextOverflow.ellipsis, style: l.rowNameStyle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _upcomingRow(ChatLook l, GraineScheduledCall c, DateTime now) {
    final state = widget.cancelStateOf?.call(c.id) ?? GraineUpcomingCancel.none;
    final at = c.at;
    final when = switch (state) {
      GraineUpcomingCancel.cancelling => 'Cancelling…',
      GraineUpcomingCancel.failed => 'Couldn’t cancel · tap to retry',
      GraineUpcomingCancel.none => at == null ? 'Booked' : ChatTime.booked(at, now, h24: _h24),
    };
    final cancel = widget.onCancelUpcoming;
    return Row(
      key: ChatWindow.upcomingRowKey(c.id),
      children: <Widget>[
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: l.accent, shape: BoxShape.circle),
          child: SdkIconView('call', color: l.onAccent, size: 16, style: l.iconStyle, stroke: l.iconStroke),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(when, maxLines: 1, overflow: TextOverflow.ellipsis, style: l.rowTimeStyle),
              Text(Booking.callName(<String?>[widget.callName, l.title, widget.heading]),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: l.rowNameStyle),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Tap(
          key: ChatWindow.cancelKey(c.id),
          label: 'Cancel the call',
          enabled: cancel != null && state != GraineUpcomingCancel.cancelling,
          onTap: cancel == null ? null : () => cancel(c.id),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: l.border, width: math.max(1, l.borderWidth)),
              borderRadius: BorderRadius.circular(math.min(l.md, 16)),
            ),
            child: Text('Cancel', style: l.cancelStyle),
          ),
        ),
      ],
    );
  }

  /// The brand's conversation starters, while the customer has written
  /// nothing — and never on a conversation that continues.
  List<String> _starters() {
    if (widget.look.suggestions.isEmpty) return const <String>[];
    final pieces = _pieces;
    final fresh = pieces != null
        ? pieces.starters
        : !widget.messages.any((Caption m) => m.role == Role.customer);
    return fresh ? widget.look.suggestions.take(ThemeChat.maxSuggestions).toList() : const <String>[];
  }

  /// THE STARTERS, on the customer's side just above the composer: chips 34
  /// high, outlined in the accent, wrapping onto more rows; a tap sends the
  /// words as the customer's message, exactly as written.
  Widget _suggestions(ChatLook l, List<String> starters) => Container(
        key: ChatWindow.suggestionsKey,
        color: l.background,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) => Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (var i = 0; i < starters.length; i++)
                Tap(
                  key: ChatWindow.suggestionKey(i),
                  label: starters[i],
                  onTap: () => widget.onSend(starters[i]),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: box.maxWidth),
                    child: Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: l.background,
                        border: Border.all(color: l.accent, width: math.max(1, l.borderWidth)),
                        borderRadius: BorderRadius.circular(math.min(l.xl, 17)),
                      ),
                      child: Text(starters[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: l.starterStyle),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _composer(ChatLook l) {
    final ready = _draft.text.trim().isNotEmpty;
    final bw = l.borderWidth;
    final placeholder = l.placeholder.isNotEmpty ? l.placeholder : 'Message…';
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
                  border: bw > 0 ? Border.all(color: l.composerBorder, width: bw) : null,
                  borderRadius: BorderRadius.circular(l.xl),
                ),
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: <Widget>[
                    if (_draft.text.isEmpty)
                      IgnorePointer(
                        child: Text(placeholder,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: l.inputStyle.copyWith(color: l.composerPlaceholder)),
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

/// One line of the thread: what was said, when, and whether it is still to go
/// out — or a day separator, or an earlier call's one row.
class _Line {
  const _Line(this.caption, {this.at, this.unsent = false})
      : dayLabel = null,
        callAt = null,
        key = null;

  const _Line.day(String this.dayLabel, {this.key})
      : caption = const Caption(Role.agent, ''),
        at = null,
        unsent = false,
        callAt = null;

  const _Line.call(DateTime this.callAt, {this.key})
      : caption = const Caption(Role.agent, ''),
        at = null,
        unsent = false,
        dayLabel = null;

  final Caption caption;
  final DateTime? at;
  final bool unsent;
  final String? dayLabel;
  final DateTime? callAt;
  final Key? key;
}

/// THE AGENT IS TYPING: three dots in an agent bubble, rising in turn —
/// still when the OS asked for less motion.
class _TypingBubble extends StatefulWidget {
  const _TypingBubble({super.key, required this.look});

  final ChatLook look;

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _t.stop();
    } else if (!_t.isAnimating) {
      _t.repeat();
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.look;
    const Caption shape = Caption(Role.agent, ' ');
    return Semantics(
      label: 'Typing',
      child: ExcludeSemantics(
        child: chatBubble(
          l,
          shape,
          content: AnimatedBuilder(
            animation: _t,
            builder: (BuildContext context, Widget? _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (var i = 0; i < 3; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: 4),
                  Transform.translate(
                    offset: Offset(0, -2.5 * _lift(_t.value, i)),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: fade(l.bubbles == 'filled' ? l.agentBubbleText : l.text, 0.55),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Dot [i]'s lift at [t] (0–1 through the cycle): up and down in the first
  /// half of its own staggered slot.
  static double _lift(double t, int i) {
    final p = (t - i * 0.18) % 1.0;
    return p < 0.5 ? math.sin(p * 2 * math.pi).abs() : 0;
  }
}

/// The dot pattern over the thread (contract/DESIGN.md, "Chat window"): dots
/// 2 across on an 18-point grid, the first centred 9 in from the top-left.
class _DotPattern extends CustomPainter {
  _DotPattern(this.color);

  final Color color;

  static const double step = 18;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var y = step / 2; y < size.height; y += step) {
      for (var x = step / 2; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotPattern old) => old.color != color;
}

/// ONE MESSAGE, per contract/DESIGN.md: at most 84% of the width, on the
/// speaker's side; corners `radius.lg` with the one nearest the speaker at
/// `radius.sm`; padding `cardPadding × 0.75` by `cardPadding`. `filled` —
/// each side its own colours; `outline` — both clear, the customer outlined
/// in `accent`, the agent in `border`, text in `text`; `minimal` — the
/// agent's words plain on the page, the customer's on `accentSoft`.
Widget chatBubble(ChatLook l, Caption m, {Key? key, Widget? content, bool unsent = false}) {
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
    // Still arriving, or typed while offline and not sent yet: provisional.
    child: content ??
        Opacity(
          opacity: unsent ? 0.6 : (m.live ? 0.75 : 1),
          child: Text(m.text, style: l.bodyStyle.copyWith(color: ink)),
        ),
  );
  final side = user ? Alignment.centerRight : Alignment.centerLeft;
  return FractionallySizedBox(widthFactor: 0.84, alignment: side, child: Align(alignment: side, child: box));
}
