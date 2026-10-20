// The chat window the voice bar opens above itself when the customer is in
// the chat, and GraineChat fills a screen with. Not exported: GraineAgentBar
// and GraineChat draw it from a GraineChatState.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Scaffold, ScaffoldMessenger, SnackBar;
import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'chat_bubble.dart';
import 'chat_parts.dart';
import 'core/core.dart';
import 'glyph.dart';
import 'sdk_icon.dart';
import 'style.dart';
import 'window_chrome.dart';

/// Everything the chat window draws with, resolved once: the design's tokens
/// (contract/DESIGN.md, "Chat window" and "Chat window v2"), or — with no
/// design — the component palette and the dashboard's accent, as the
/// transcript drew it before designs, with the chat's v2 pieces classic.
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
    required this.chat,
    required this.captionStyle,
    required this.captionStrongStyle,
    required this.bodyStrongStyle,
    required this.headingStyle,
    required this.welcomeTitleStyle,
    required this.heroTitleStyle,
    required this.heroSubtitleStyle,
    this.danger = const Color(0xFFDC2626),
    this.warning = const Color(0xFFB45309),
    this.hardOffset,
    this.motionMs = 0,
    this.designGlass,
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
    String? remapAccent,
    String? remapSoft,
    bool remapAll = false,
    Color? dot,
    Color? chevron,
    Color? composerBorder,
    Color? composerPlaceholder,
  })  : _remapAccent = remapAccent,
        _remapSoft = remapSoft,
        _remapAll = remapAll,
        dot = dot ?? success,
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
    TextStyle heading(double size) =>
        designText(text, size, f.heading, f.weights.title, height: f.lineHeight.title, letterSpacing: em(size, f.letterSpacing.title));
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
      chat: k,
      captionStyle: designText(muted, f.scale.caption, f.body, f.weights.body),
      captionStrongStyle: designText(muted, f.scale.caption, f.body, f.weights.strong),
      bodyStrongStyle: designText(text, f.scale.body, f.body, f.weights.strong,
          height: f.lineHeight.body, letterSpacing: em(f.scale.body, f.letterSpacing.body)),
      headingStyle: heading(titleSize),
      welcomeTitleStyle: heading(math.min(f.scale.title, 17).toDouble()),
      heroTitleStyle: heading(math.min(f.scale.display, 26).toDouble()),
      heroSubtitleStyle: designText(text, f.scale.body, f.body, f.weights.body, height: f.lineHeight.body),
      danger: tokenColor(c.danger),
      warning: tokenColor(c.warning),
      hardOffset: t.elevation.hardOffset,
      motionMs: t.motion.none ? 0 : t.motion.durationMs,
      designGlass: t.glass,
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
      // A host's own accent recolours what the design drew in its accent.
      remapAccent: accent == null ? null : c.accent,
      remapSoft: accent == null ? null : c.accentSoft,
      dot: surfaceHeader ? tokenColor(c.success) : tokenColor(k.headerText),
      chevron: tokenColor(k.headerSubtext),
      composerBorder: tokenColor(k.composerBorder),
      composerPlaceholder: tokenColor(k.composerPlaceholder),
    );
  }

  /// Before designs: the component palette ([Appearance.palette]) and the
  /// accent ([accentHex] its #RRGGBB, when the caller has it), with every
  /// v2 piece classic.
  factory ChatLook.appearance({
    required bool dark,
    required Color accent,
    required double radius,
    required List<BoxShadow> shadows,
    String? accentHex,
  }) {
    final surface = dark ? const Color(0xFF17181B) : const Color(0xFFFFFFFF);
    final border = dark ? const Color(0xFF2C2E33) : const Color(0xFFE5E4E0);
    final text = dark ? const Color(0xFFF5F5F4) : const Color(0xFF101318);
    final muted = dark ? const Color(0xFFA0A5AE) : const Color(0xFF5F6672);
    final onAccentHex = readableHexOn(accent);
    // The same palette as #RRGGBB, so the chat's classic v2 pieces derive from it exactly.
    final surfaceHex = dark ? '#17181B' : '#FFFFFF';
    final borderHex = dark ? '#2C2E33' : '#E5E4E0';
    final known = Design.normaliseHex(accentHex);
    final accentWord = known ?? Appearance.defaultAccent;
    final colors = ThemeColors(
      background: surfaceHex,
      surface: surfaceHex,
      surfaceRaised: dark ? '#1F2024' : '#F7F7F5',
      text: dark ? '#F5F5F4' : '#101318',
      textMuted: dark ? '#A0A5AE' : '#5F6672',
      border: borderHex,
      accent: accentWord,
      onAccent: onAccentHex,
      // The translucent fills this look always drew, laid on the page they sit on.
      accentSoft: Design.mixHex(surfaceHex, accentWord, 0.15),
      success: dark ? '#22C55E' : '#16A34A',
      warning: dark ? '#F59E0B' : '#B45309',
      danger: dark ? '#F87171' : '#DC2626',
      userBubble: accentWord,
      userBubbleText: onAccentHex,
      agentBubble: Design.mixHex(surfaceHex, borderHex, 0.6),
      agentBubbleText: dark ? '#F5F5F4' : '#101318',
      scrim: '#000000',
    );
    final md = math.min(radius, 12).toDouble();
    final lg = math.min(radius, 16).toDouble();
    final xl = math.min(26, radius + 8).toDouble();
    final chat = ThemeChat.fallback(
      colors,
      dark: dark,
      hasGlyph: false,
      base: ChatClassicBase(
        colors: colors,
        radius: ThemeRadius(sm: 5, md: md, lg: lg, xl: xl),
        borderWidth: 1,
        spacing: const ThemeSpacing(unit: 4, cardPadding: 12, gap: 8),
        cardShadow: const ThemeShadow(y: 2, blur: 8, spread: 0, opacity: 0.08, color: '#000000'),
      ),
    );
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
      md: md,
      lg: lg,
      xl: xl,
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
      chat: chat,
      captionStyle: textStyle(muted, 12),
      captionStrongStyle: textStyle(muted, 12, weight: 600),
      bodyStrongStyle: textStyle(text, 14.5, weight: 600, height: 21 / 14.5),
      headingStyle: textStyle(text, 15, weight: 700, height: 1.25),
      welcomeTitleStyle: textStyle(text, 17, weight: 700, height: 1.25),
      heroTitleStyle: textStyle(text, 22, weight: 700, height: 1.25),
      heroSubtitleStyle: textStyle(text, 14.5),
      danger: tokenColor(colors.danger),
      warning: tokenColor(colors.warning),
      // An accent the caller only had as a colour: what the pieces drew in the default accent is drawn in
      // it — everywhere, since the words on it were chosen for it (onAccentHex).
      remapAccent: known == null ? accentWord : null,
      remapSoft: known == null ? colors.accentSoft : null,
      remapAll: true,
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

  /// The chat's tokens, every v2 group complete (classic from an older server).
  final ThemeChat chat;

  /// Caption size, in the body family: status lines, a message's status, the banner.
  final TextStyle captionStyle;
  final TextStyle captionStrongStyle;

  /// The body at `weights.strong`: bold words in the agent's messages.
  final TextStyle bodyStrongStyle;

  /// The heading family at `weights.title`, `min(scale.title, 16)`: the rating's question, a context card's title.
  final TextStyle headingStyle;

  /// The welcome card's title (`min(scale.title, 17)`), the hero's (`min(scale.display, 26)`) and its subtitle.
  final TextStyle welcomeTitleStyle;
  final TextStyle heroTitleStyle;
  final TextStyle heroSubtitleStyle;
  final Color danger;
  final Color warning;

  /// The design's solid offset shadow, for cards that draw it.
  final ThemeOffset? hardOffset;

  /// The design's pace; 0 for none.
  final int motionMs;

  /// The design's own glass (a surface header frosts with it, as in v1).
  final ThemeGlass? designGlass;
  final String? _remapAccent;
  final String? _remapSoft;
  final bool _remapAll;

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

  /// A v2 token's colour. A fill that carries words (a header, a bubble)
  /// keeps the design's colour under a host's own accent, as v1 did — its
  /// words were chosen for it; [accentInk] is for what only decorates.
  Color ink(String hex) => _remapAll ? accentInk(hex) : tokenColor(hex);

  /// A decoration's colour (an outline, an icon, a chip, the send button):
  /// the host's own accent where the design drew its accent.
  Color accentInk(String hex) {
    if (_remapAccent != null && hex == _remapAccent) return accent;
    if (_remapSoft != null && hex == _remapSoft) return soft;
    return tokenColor(hex);
  }

  /// Ink that reads on [fill]: [onAccent] on the accent, else [hex]'s colour.
  Color inkOn(Color fill, String hex) => fill == accent ? onAccent : ink(hex);
}

/// THE CHAT WINDOW (contract/DESIGN.md, "Chat window" and "Chat window v2"):
/// the frame on the wallpaper (a colour, a gradient or a pattern); the
/// header — surface, accent, gradient or plain, its title start or centred,
/// its status line, a call button, "New conversation" and the chevron — or,
/// with window chrome, the title bar; the card the app pins; the calm
/// reconnect banner; the thread — the pinned card, booked calls, the welcome,
/// the messages grouped in their bubbles with their times, the agent's
/// suggested replies, the typing indicator and the rating — over the
/// wallpaper, lazily; the starters and replies docked as the design places
/// them; the scroll-to-latest pill; and the composer as a bar, a pill or a
/// floating capsule. From an older server it draws exactly as before the
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
    this.pin,
    this.quickReplies = const <GraineQuickReply>[],
    this.onQuickReply,
    this.ended = false,
    this.rating,
    this.onRate,
    this.onAttach,
    this.onCall,
    this.reconnecting = false,
    this.offline = false,
    this.onRetry,
    this.onOpenLink,
    this.loader,
    this.loaderColor,
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

  /// The agent is composing: a typing indicator after the last message.
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

  /// What the app pinned (`chat.pin`): a bar under the header or a card atop
  /// the thread, as `header.contextCard` says.
  final GraineChatPin? pin;

  /// The replies the agent suggests for its latest turn, as chips.
  final List<GraineQuickReply> quickReplies;

  /// A reply tapped. Default: its words sent through [onSend].
  final ValueChanged<GraineQuickReply>? onQuickReply;

  /// The agent ended the conversation: the rating, where the design asks for one.
  final bool ended;

  /// The user's answer to the rating, once given.
  final GraineChatRating? rating;

  /// A rating chosen. Null: the rating card is not drawn.
  final void Function(GraineChatRatingStyle style, int value)? onRate;

  /// The app handles attachments: the paperclip, where the design asks for one.
  final VoidCallback? onAttach;

  /// Starts a call with the agent, exactly as the voice bar's call does —
  /// set only where the agent takes calls and this SDK can start one from the
  /// chat. Null: no call button, and no microphone in the composer.
  final VoidCallback? onCall;

  /// A dropped chat is being made again: "Reconnecting…" in the header and the banner.
  final bool reconnecting;

  /// Not connected and not trying: with a message waiting, the offline banner.
  final bool offline;

  /// "Not sent · Tap to retry".
  final VoidCallback? onRetry;

  /// A link tapped in the agent's words.
  final ValueChanged<Uri>? onOpenLink;

  /// The dashboard's loader — the classic typing indicator, the banner's
  /// spinner — and its colour.
  final LoaderLook? loader;
  final Color? loaderColor;

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

  /// The typing indicator.
  static const Key typingKey = ValueKey<String>('graine-chat-typing');

  /// The conversation starters, wherever they are placed.
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

  // ── v2 ─────────────────────────────────────────────────────────────────────

  /// The agent's suggested replies, and the [index]th of them.
  static const Key quickRepliesKey = ValueKey<String>('graine-chat-quick-replies');
  static Key quickReplyKey(int index) => ValueKey<String>('graine-chat-quick-reply-$index');

  /// The card the app pinned: as a bar under the header, or a card in the thread.
  static const Key contextBarKey = ValueKey<String>('graine-chat-context-bar');
  static const Key contextCardKey = ValueKey<String>('graine-chat-context-card');

  /// The reconnect banner.
  static const Key bannerKey = ValueKey<String>('graine-chat-banner');

  /// The welcome as a card, or as a hero.
  static const Key welcomeKey = ValueKey<String>('graine-chat-welcome');

  /// The end-of-chat rating card.
  static const Key ratingKey = ValueKey<String>('graine-chat-rating');

  /// The scroll-to-latest pill.
  static const Key pillKey = ValueKey<String>('graine-chat-scroll-pill');

  /// The header's call button, and the composer's.
  static const Key headerCallKey = ValueKey<String>('graine-chat-header-call');
  static const Key composerCallKey = ValueKey<String>('graine-chat-composer-call');

  /// The paperclip.
  static const Key attachKey = ValueKey<String>('graine-chat-attach');

  /// "Copied", after a long press.
  static const Key copiedKey = ValueKey<String>('graine-chat-copied');

  /// The thread's list.
  static const Key threadKey = ValueKey<String>('graine-chat-thread');

  @override
  State<ChatWindow> createState() => _ChatWindowState();
}

/// One row of the thread, built only when it scrolls into view.
class _Item {
  const _Item(this.key, this.build, {this.gap, this.bleed = false, this.message = false});

  /// Stable while the conversation grows.
  final String key;
  final Widget Function(BuildContext context) build;

  /// The space above it; null — the density's gap (none for the first).
  final double? gap;

  /// The window's full width (the hero), not the thread's.
  final bool bleed;

  /// A message — counted as "new" while the reader is scrolled up.
  final bool message;
}

class _ChatWindowState extends State<ChatWindow> {
  final TextEditingController _draft = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'graine-chat-composer');
  final _ThreadScroll _scroll = _ThreadScroll();

  /// Within 120 of the newest row: new rows bring it along. Scrolled further up, nothing moves it.
  bool _following = true;

  /// Messages that arrived while the reader was scrolled up.
  int _unseen = 0;
  int _messages = 0;
  String _lastSignature = '';
  String _lastBottom = '';

  /// The height of what floats over the thread's bottom (a floating composer and its chips).
  double _overlay = 0;

  bool _copied = false;
  Timer? _copiedTimer;

  /// The agent's words formatted, once per change of a turn's words.
  final Map<String, List<ChatBlock>> _parsed = <String, List<ChatBlock>>{};

  static const double _followWithin = 120;

  @override
  void initState() {
    super.initState();
    _draft.addListener(_changed);
    _scroll.addListener(_scrolled);
  }

  void _changed() => setState(() {});

  // The thread is a reversed list: its scroll offset is the distance from the newest row.
  void _scrolled() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    final near = p.pixels - p.minScrollExtent <= _followWithin;
    if (near != _following) {
      setState(() {
        _following = near;
        if (near) _unseen = 0;
      });
    }
  }

  @override
  void dispose() {
    _draft.removeListener(_changed);
    _draft.dispose();
    _focus.dispose();
    _scroll.removeListener(_scrolled);
    _scroll.dispose();
    _copiedTimer?.cancel();
    super.dispose();
  }

  /// After the frame, back to the newest row — for a reader within 120 of it.
  void _stickToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      // The reader scrolled away meanwhile: nothing moves them.
      if (!mounted || !_scroll.hasClients || !_following) return;
      final p = _scroll.position;
      if (p.pixels - p.minScrollExtent > 0.5) _scroll.jumpTo(p.minScrollExtent);
    });
  }

  void _scrollToLatest() {
    setState(() {
      _unseen = 0;
      _following = true;
    });
    if (!_scroll.hasClients) return;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _scroll.jumpTo(_scroll.position.minScrollExtent);
    } else {
      _scroll
          .animateTo(_scroll.position.minScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut)
          .whenComplete(_stickToBottom);
    }
  }

  void _submit() {
    final text = _draft.text.trim();
    if (text.isEmpty) return;
    _draft.clear();
    widget.onSend(text);
  }

  /// A long press, or the screen reader's Copy: the plain words, and the
  /// platform's confirmation — a snack bar where the app has a Scaffold, else
  /// a brief "Copied" in the window.
  void _copy(String words) {
    unawaited(Clipboard.setData(ClipboardData(text: words)));
    if (Scaffold.maybeOf(context) != null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Copied')));
      return;
    }
    _copiedTimer?.cancel();
    setState(() => _copied = true);
    _copiedTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
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

  /// Reveal a reply smoothly: the design moves, and the OS did not ask for less.
  bool get _reveal => widget.look.motionMs > 0 && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  Duration get _motion => _reveal ? Duration(milliseconds: widget.look.motionMs) : Duration.zero;

  /// The card shadow: the design's hard offset where the cards draw it, else `cards.shadow`.
  List<BoxShadow> _cardShadows(ChatLook l) {
    final hard = l.hardOffset;
    if (l.chat.cards.hard && hard != null) return <BoxShadow>[hardShadowOf(hard, l.text)];
    return shadowsOf(l.chat.cards.shadow);
  }

  /// A card's box (`chat.cards`): `surfaceRaised` (or [color]), the outline
  /// when `cards.border`, `cards.radius`, its shadow.
  BoxDecoration _cardBox(ChatLook l, {Color? color}) {
    final cards = l.chat.cards;
    return BoxDecoration(
      color: color ?? l.cardFill,
      border: cards.border && l.borderWidth > 0 ? Border.all(color: l.border, width: l.borderWidth) : null,
      borderRadius: BorderRadius.circular(cards.radius),
      boxShadow: _cardShadows(l),
    );
  }

  List<ChatBlock> _blocksOf(String text) {
    final cached = _parsed[text];
    if (cached != null) return cached;
    if (_parsed.length > 400) _parsed.clear();
    return _parsed[text] = ChatMarkdown.parse(text);
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.look;
    final k = l.chat;
    final bw = l.borderWidth;
    final framed = !widget.fill || widget.keepFrame;
    final outline = bw > 0 && framed ? Border.all(color: l.border, width: bw) : null;
    final chrome = l.chrome;
    final radius = framed ? l.xl : 0.0;
    final wall = k.wallpaper;
    final gradient = wall.style == 'gradient' && wall.colorTo != null
        ? LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: <Color>[l.ink(wall.color), l.ink(wall.colorTo!)])
        : null;
    final plainHeader = chrome == null && k.header.style == 'plain';
    final floating = k.composer.style == 'floating';
    final docked = _docked();
    final pin = widget.pin;
    final banner = _banner();

    final column = Column(
      mainAxisSize: widget.fill ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (chrome != null) _titleBar(l, chrome) else _header(l),
        if (pin != null && k.header.contextCard == 'bar')
          ChatPinBar(key: ChatWindow.contextBarKey, look: l, pin: pin, glass: _headerGlass(l)),
        AnimatedSize(
          duration: _motion,
          alignment: Alignment.topCenter,
          child: banner == null ? const SizedBox(width: double.infinity) : KeyedSubtree(key: ChatWindow.bannerKey, child: banner),
        ),
        if (widget.fill) Expanded(child: _thread(l, docked, floating)) else _thread(l, docked, floating),
        if (widget.below != null) widget.below!,
        if (!floating && docked != null) docked,
        if (!floating) _composer(l),
      ],
    );
    return Container(
      decoration: BoxDecoration(
        color: gradient == null ? l.background : null,
        gradient: gradient,
        border: outline,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: framed ? l.shadows : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(math.max(0, radius - (outline == null ? 0 : bw))),
        child: plainHeader && _patternPainter(l) != null
            // A plain header: the wallpaper — its pattern too — runs under it, one surface top to bottom.
            ? Stack(children: <Widget>[
                Positioned.fill(child: CustomPaint(painter: _patternPainter(l))),
                column,
              ])
            : column,
      ),
    );
  }

  /// The wallpaper's pattern, standing still while the messages scroll; null for none.
  CustomPainter? _patternPainter(ChatLook l) {
    final w = l.chat.wallpaper;
    if (w.style != 'pattern' || w.pattern == 'none') return null;
    final color = l.ink(w.patternColor);
    return w.pattern == 'dots' ? _DotPattern(color) : ChatLinePattern(w.pattern, color);
  }

  /// The frosting a header (and the context bar under it) wears: a surface
  /// header the design's own glass (v1) or the chat's; a plain one the chat's.
  ThemeGlass? _headerGlass(ChatLook l) {
    final style = l.chat.header.style;
    if (style == 'surface') return l.glass ?? l.designGlass ?? l.chat.glass?.asGlass;
    if (style == 'plain') return l.chat.glass?.asGlass;
    return null;
  }

  // ── the header ──────────────────────────────────────────────────────────

  /// "New conversation": the compose icon beside the chevron, only while the
  /// window holds an earlier conversation.
  Widget? _compose(ChatLook l, double padding, double size, Color color) {
    final start = widget.onNewConversation;
    final pieces = _pieces;
    if (start == null || pieces == null || !pieces.newConversation) return null;
    return Tap(
      key: ChatWindow.newConversationKey,
      label: 'New conversation',
      onTap: start,
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: SdkIconView('compose', color: color, size: size, style: l.iconStyle, stroke: l.iconStroke),
      ),
    );
  }

  Widget? _chevron(ChatLook l, double padding, double size, Color color) {
    final collapse = widget.onCollapse;
    if (collapse == null) return null;
    return Tap(
      key: ChatWindow.collapseKey,
      label: widget.collapseLabel,
      onTap: collapse,
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: SdkIconView('chevron', color: color, size: size, style: l.iconStyle, stroke: l.iconStroke, turned: true),
      ),
    );
  }

  /// The header's call button (`escalation.call: header`), where the agent takes calls.
  Widget? _headerCall(ChatLook l, double padding, double size, Color color) {
    final call = widget.onCall;
    if (call == null || l.chat.escalation.call != 'header') return null;
    return Tap(
      key: ChatWindow.headerCallKey,
      label: 'Call $_title',
      onTap: call,
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: SdkIconView('call', color: color, size: size, style: l.iconStyle, stroke: l.iconStroke),
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

  /// The title bar's right end: the call button and "New conversation"
  /// (while there is history to start over from) beside the chevron.
  Widget? _trailing(ChatLook l) {
    final pad = (WindowChrome.chevronBox - WindowChrome.chevronIcon) / 2;
    final chevron = _chevron(l, pad, WindowChrome.chevronIcon, l.chevron);
    final compose = _compose(l, pad, WindowChrome.chevronIcon, l.chevron);
    final call = _headerCall(l, pad, WindowChrome.chevronIcon, l.muted);
    if (compose == null && call == null) return chevron;
    return Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
      if (call != null) call,
      if (compose != null) compose,
      if (chevron != null) chevron,
    ]);
  }

  /// THE AVATAR at [size] (30 in the header, 24 in a centred one, 48 in the
  /// empty chat, 40 in the welcome card, 56 in the hero), per `chat.avatar`:
  /// `logo` — the brand's logo, whole, on its plate; with none uploaded, the
  /// launcher glyph when the design has one, else the title's first letter.
  /// `glyph` — the launcher mark. `none` — nothing. Before the chat's tokens:
  /// the launcher's mark as it always was.
  Widget? _avatar(ChatLook l, double size, {Key? key}) {
    final avatar = l.avatar ?? (l.glyph != null ? 'glyph' : 'logo');
    if (avatar == 'none') return null;
    final url = widget.logoUrl;
    final logo = url != null && url.isNotEmpty ? url : null;
    final glyph = (avatar == 'glyph' || logo == null) ? l.glyph : null;
    final onPlate = glyph == null && logo != null ? widget.logoPlate : LogoPlate.accent;
    final fill = logoPlateOf(onPlate, accent: l.accent, border: l.border, borderWidth: l.borderWidth);
    final box = BrandLogo.box(l.markShape, size).toDouble();
    final corner = size == 30
        ? l.markRadius
        : size == 48
            ? l.markRadius48
            : Design.launcherRadius(l.markShape, ThemeRadius(sm: l.sm, md: l.md, lg: l.lg, xl: l.xl), size);
    Widget letter() => Text(initialOf(_title),
        style: textStyle(tokenColor(inkOnPlate(onPlate, l.onAccentHex)), size * 0.4, weight: 700, height: 1));
    return Container(
      key: key,
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: fill.color, borderRadius: BorderRadius.circular(corner), border: fill.border),
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

  /// THE STATUS LINE under the title, first match wins: reconnecting,
  /// connecting, the agent typing (with `typingStatus`), none, then the dot
  /// and the words (`online`) or the words alone (`text`).
  Widget? _status(ChatLook l, Color quiet, {required bool centered}) {
    final h = l.chat.header;
    String words;
    var dot = false;
    if (widget.reconnecting) {
      words = widget.loader?.text.reconnecting ?? 'Reconnecting…';
    } else if (!widget.online) {
      words = widget.connectingText ?? 'Connecting…';
    } else if (widget.typing && h.typingStatus) {
      words = l.chat.typing.words;
    } else if (h.status == 'none') {
      return null;
    } else {
      words = l.subtitle.isNotEmpty ? l.subtitle : 'Online';
      dot = h.status == 'online';
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (dot) ...<Widget>[
          Container(width: 6, height: 6, decoration: BoxDecoration(color: l.ink(h.dot), shape: BoxShape.circle)),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(words,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: centered ? TextAlign.center : TextAlign.start,
              style: l.statusStyle.copyWith(color: quiet)),
        ),
      ],
    );
  }

  /// THE HEADER, 50 high (growing with the text): its fill by
  /// `header.style`, the hairline under it when `header.divider`, and — start
  /// aligned — [chevron, full screen only] [avatar] [title and status] [call]
  /// [compose] [chevron]; centred — the same controls at the same edges and
  /// the avatar (24) with the title and status as one group centred on the
  /// whole width, kept 8 clear of them.
  Widget _header(ChatLook l) {
    final h = l.chat.header;
    final line = h.divider && l.borderWidth > 0 ? l.borderWidth : 0.0;
    final centered = h.align == 'center';
    final ink = l.ink(h.fill.text);
    final quiet = l.ink(h.fill.textMuted);
    final mark = _avatar(l, centered ? 24 : 30, key: ChatWindow.avatarKey);
    final chevron = _chevron(l, 6, 18, quiet);
    final compose = _compose(l, 6, 18, quiet);
    final call = _headerCall(l, 6, 18, ink);
    final leading = chevron != null && widget.leadingChevron;
    final words = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(_title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: centered ? TextAlign.center : TextAlign.start,
              style: l.titleStyle.copyWith(color: ink)),
        ),
        if (_status(l, quiet, centered: centered) case final status?) status,
      ],
    );
    final trailing = <Widget>[
      if (call != null) ...<Widget>[const SizedBox(width: 10), call],
      if (compose != null) ...<Widget>[const SizedBox(width: 10), compose],
      if (chevron != null && !leading) ...<Widget>[const SizedBox(width: 10), chevron],
    ];
    final Widget row;
    if (!centered) {
      row = Row(
        children: <Widget>[
          // A full screen: the chevron leads.
          if (leading) ...<Widget>[chevron, const SizedBox(width: 10)],
          if (mark != null) ...<Widget>[mark, const SizedBox(width: 10)],
          Expanded(child: words),
          ...trailing,
        ],
      );
    } else {
      // Each control is 30 across with 10 before it: the group keeps 8 clear of the widest end.
      final before = leading ? 40.0 : 0.0;
      final after = (call != null ? 40.0 : 0.0) + (compose != null ? 40.0 : 0.0) + (chevron != null && !leading ? 40.0 : 0.0);
      final inset = math.max(before, after) + 8.0;
      row = Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Row(children: <Widget>[if (leading) chevron, const Spacer(), ...trailing]),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: inset),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (mark != null) ...<Widget>[mark, const SizedBox(width: 8)],
                Flexible(child: words),
              ],
            ),
          ),
        ],
      );
    }
    final glass = _headerGlass(l);
    final fill = h.fill;
    final Color color;
    Gradient? gradient;
    switch (h.style) {
      case 'gradient':
        color = l.ink(fill.color);
        // Leading → trailing, mirrored in RTL.
        gradient = LinearGradient(
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
          colors: <Color>[l.ink(fill.color), l.ink(fill.colorTo ?? fill.color)],
        );
      case 'plain':
        // No fill: the wallpaper runs under it — frosted with the chat's glass.
        color = glass == null ? const Color(0x00000000) : fade(l.ink(fill.color), glass.surfaceOpacity);
      case 'surface':
        color = glass == null ? l.ink(fill.color) : fade(l.ink(fill.color), glass.surfaceOpacity);
      default: // accent: solid
        color = l.ink(fill.color);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        surfaceBox(
          key: ChatWindow.headerKey,
          color: color,
          gradient: gradient,
          border: l.border,
          borderWidth: 0,
          radius: BorderRadius.zero,
          shadows: const <BoxShadow>[],
          glass: glass,
          minHeight: 50 - line,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: row,
        ),
        // The header's bottom outline.
        if (line > 0) Container(height: line, color: l.border),
      ],
    );
  }

  // ── the banner ──────────────────────────────────────────────────────────

  bool get _waiting =>
      widget.turns?.any((GraineChatTurn t) =>
          t.delivery == GraineChatDelivery.sending || t.delivery == GraineChatDelivery.failed) ??
      false;

  /// The calm banner: while the chat reconnects, or is offline with a message waiting.
  Widget? _banner() {
    final l = widget.look;
    if (widget.reconnecting) {
      return ChatReconnectBanner(
        look: l,
        reconnecting: true,
        loader: widget.loader,
        loaderColor: widget.loaderColor,
        reconnectingText: widget.loader?.text.reconnecting,
      );
    }
    if (widget.offline && _waiting) return ChatReconnectBanner(look: l, reconnecting: false);
    return null;
  }

  // ── the thread ──────────────────────────────────────────────────────────

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

  /// The chips docked above the composer: the agent's replies where they
  /// are placed there, else the brand's starters (when chips, placed `both`
  /// or `above-composer`). Null: none.
  Widget? _docked() {
    final l = widget.look;
    final k = l.chat;
    final placement = k.chips.placement;
    final replies = widget.quickReplies;
    final chips = k.welcome.starters == 'chips';
    if (placement == 'above-composer' && replies.isNotEmpty) {
      return _dockedChips(l, ChatWindow.quickRepliesKey, <String>[for (final r in replies) r.label], ChatWindow.quickReplyKey,
          (int i) => _tapReply(replies[i]));
    }
    final starters = _starters();
    if (chips && starters.isNotEmpty && placement != 'inline') {
      return _dockedChips(l, ChatWindow.suggestionsKey, starters, ChatWindow.suggestionKey, (int i) => widget.onSend(starters[i]));
    }
    return null;
  }

  /// Docked chips: on the customer's side, wrapping onto rows (v1) or in one
  /// row that scrolls sideways, 8 above the composer.
  Widget _dockedChips(ChatLook l, Key key, List<String> words, Key Function(int) chipKey, void Function(int) onTap) => Padding(
        key: key,
        padding: const EdgeInsets.only(bottom: 8),
        child: chatChips(l, words,
            chipKey: chipKey, onTap: onTap, alignment: WrapAlignment.end, edge: l.chat.density.edge),
      );

  void _tapReply(GraineQuickReply reply) {
    final tap = widget.onQuickReply;
    if (tap != null) {
      tap(reply);
    } else {
      widget.onSend(reply.text);
    }
  }

  /// The welcome is drawn (card, hero): a conversation that does not continue an earlier one.
  bool get _welcomes {
    final l = widget.look;
    if (!l.designed) return false;
    final layout = l.chat.welcome.layout;
    if (layout != 'card' && layout != 'hero') return false;
    final turns = _pieces?.turns;
    return turns == null || !turns.any((GraineChatTurn t) => t.restored);
  }

  /// The starters drawn in the thread: as a list (always), or as chips placed `inline`.
  Widget? _threadStarters(ChatLook l, {WrapAlignment alignment = WrapAlignment.end, double edge = 0}) {
    final starters = _starters();
    if (starters.isEmpty) return null;
    final k = l.chat;
    if (k.welcome.starters == 'list') {
      return chatStarterList(l, starters,
          key: ChatWindow.suggestionsKey, rowKey: ChatWindow.suggestionKey, onTap: (int i) => widget.onSend(starters[i]));
    }
    if (k.chips.placement != 'inline') return null;
    return chatChips(l, starters,
        key: ChatWindow.suggestionsKey,
        chipKey: ChatWindow.suggestionKey,
        onTap: (int i) => widget.onSend(starters[i]),
        alignment: alignment,
        edge: edge);
  }

  /// The messages and rows to draw, oldest first.
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
            ChatDayRow() => _Line.day(ChatRows.dayLabel(row, now: now), 'row-${row.key}', key: ChatWindow.dayKey(row.date)),
            ChatVoiceRow() =>
              _Line.call(row.at, 'row-${row.key}', key: ChatWindow.voiceKey(row.id.substring('voice-'.length))),
            ChatTurnRow(turn: final t) => _Line(t.caption, 'row-${row.key}',
                at: t.at,
                status: switch (t.delivery) {
                  GraineChatDelivery.sending => ChatMessageStatus.waiting,
                  GraineChatDelivery.failed => ChatMessageStatus.failed,
                  _ => ChatMessageStatus.sent,
                }),
          },
      ];
    }
    return <_Line>[
      for (var i = 0; i < widget.messages.length; i++)
        if (widget.messages[i].text.trim().isNotEmpty) _Line(widget.messages[i], 'row-m$i'),
    ];
  }

  /// THE THREAD's rows, in order: the pinned card (`contextCard: card`), the
  /// booked calls, the welcome (a card, or a hero), the messages — grouped,
  /// with their times and status — the agent's suggested replies under its
  /// turn, the starters placed in the thread, the typing indicator, and the
  /// rating once the agent ended the conversation.
  List<_Item> _items(ChatLook l, List<_Line> lines) {
    final k = l.chat;
    final d = k.density;
    final items = <_Item>[];
    final pin = widget.pin;
    if (pin != null && k.header.contextCard == 'card') {
      items.add(_Item('pin', (BuildContext _) => chatPinCard(l, pin, key: ChatWindow.contextCardKey, decoration: _cardBox(l))));
    }
    final card = _upcomingCard(l);
    if (card != null) items.add(_Item('upcoming', (BuildContext _) => card));
    final welcomes = _welcomes;
    var startersPlaced = false;
    if (welcomes) {
      if (k.welcome.layout == 'hero') {
        items.insert(0, _Item('hero', (BuildContext _) => _hero(l), bleed: true, gap: 0));
      } else {
        items.add(_Item('welcome', (BuildContext _) => _welcomeCard(l)));
      }
      startersPlaced = true;
    }
    final grouped = k.bubbles.grouping;
    final positions = grouped
        ? ChatGroups.positions(<ChatGroupItem>[
            for (final line in lines)
              line.caption.text.isEmpty
                  ? const ChatGroupItem(breaks: true)
                  : ChatGroupItem(
                      role: line.caption.role == Role.agent ? 'agent' : 'customer', at: line.at?.millisecondsSinceEpoch),
          ])
        : List<ChatGroupPosition>.filled(lines.length, ChatGroupPosition.single);
    var lastAgent = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].dayLabel == null && lines[i].callAt == null && lines[i].caption.role == Role.agent) lastAgent = i;
    }
    final replies = widget.quickReplies;
    final repliesInThread = replies.isNotEmpty && k.chips.placement != 'above-composer';
    var m = 0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final first = items.isEmpty;
      final afterHero = items.length == 1 && items.first.key == 'hero';
      // Two messages of one group sit closer.
      final inGroup = i > 0 &&
          (positions[i] == ChatGroupPosition.middle || positions[i] == ChatGroupPosition.last) &&
          lines[i - 1].dayLabel == null &&
          lines[i - 1].callAt == null;
      final gap = first ? 0.0 : (afterHero ? 16.0 : (inGroup ? d.groupGap : null));
      if (line.dayLabel != null) {
        items.add(_Item(line.id, (BuildContext _) => _dayLine(l, line), gap: gap));
      } else if (line.callAt != null) {
        items.add(_Item(line.id, (BuildContext _) => _callLine(l, line), gap: gap));
      } else {
        final index = m++;
        final position = positions[i];
        final time = line.at != null && ChatGroups.showsTime(k.timestamps.show, position) ? ChatTime.clock(line.at!, h24: _h24) : null;
        final user = line.caption.role != Role.agent;
        final text = line.caption.text;
        final live = line.caption.live;
        final blocks = user || live ? null : _blocksOf(text);
        items.add(_Item(
          line.id,
          (BuildContext _) => ChatMessageRow(
            look: l,
            user: user,
            text: text,
            speaker: user ? 'You' : _title,
            position: position,
            bubbleKey: ChatWindow.messageKey(index),
            live: live,
            animate: _reveal,
            blocks: blocks,
            time: time,
            status: line.status,
            onRetry: widget.onRetry,
            onCopy: _copy,
            onOpenLink: widget.onOpenLink,
          ),
          gap: gap,
          message: true,
        ));
        if (repliesInThread && i == lastAgent) items.add(_repliesItem(l, replies, gap: 8));
      }
    }
    // Replies with no agent turn on screen (its words not drawn): at the thread's end, on the agent's side.
    if (repliesInThread && lastAgent < 0) items.add(_repliesItem(l, replies, gap: items.isEmpty ? 0 : 8));
    if (!startersPlaced) {
      final row = k.chips.scroll == 'row' && k.welcome.starters == 'chips';
      final starters = _threadStarters(l, edge: row ? d.edge : 0);
      if (starters != null) {
        items.add(_Item('starters', (BuildContext _) => starters, gap: items.isEmpty ? 0 : null, bleed: row));
      }
    }
    if (widget.typing) {
      items.add(_Item(
        'typing',
        (BuildContext _) => Align(
          alignment: AlignmentDirectional.centerStart,
          child: ChatTypingIndicator(
            key: ChatWindow.typingKey,
            look: l,
            name: _title,
            loader: widget.loader,
            loaderColor: widget.loaderColor,
            bubble: (Widget child, {EdgeInsetsGeometry? padding}) => chatBubbleBox(l,
                user: false,
                position: ChatGroupPosition.single,
                direction: Directionality.of(context),
                padding: padding,
                child: child),
          ),
        ),
        gap: items.isEmpty ? 0 : null,
      ));
    }
    if (widget.ended && k.rating.show && widget.onRate != null) {
      items.add(_Item(
        'rating',
        (BuildContext _) => ChatRatingCard(
          key: ChatWindow.ratingKey,
          look: l,
          decoration: _cardBox(l),
          rating: widget.rating,
          onRate: widget.onRate,
        ),
        gap: items.isEmpty ? 0 : null,
      ));
    }
    return items;
  }

  /// The agent's replies in the thread, under its turn, on its side — a
  /// sideways row runs the window's full width, starting the density's edge in.
  _Item _repliesItem(ChatLook l, List<GraineQuickReply> replies, {required double gap}) {
    final row = l.chat.chips.scroll == 'row';
    return _Item(
      'replies',
      (BuildContext _) => chatChips(l, <String>[for (final r in replies) r.label],
          key: ChatWindow.quickRepliesKey,
          chipKey: ChatWindow.quickReplyKey,
          onTap: (int r) => _tapReply(replies[r]),
          alignment: WrapAlignment.start,
          edge: row ? l.chat.density.edge : 0),
      gap: gap,
      bleed: row,
    );
  }

  Widget _thread(ChatLook l, Widget? docked, bool floating) {
    final k = l.chat;
    final lines = _lines();
    final empty = lines.isEmpty && !widget.typing;
    final centeredWelcome = empty && (k.welcome.layout == 'centered' || !l.designed);
    final items = centeredWelcome ? const <_Item>[] : _items(l, lines);
    _noteGrowth(items, lines);

    final pattern = l.chrome == null && k.header.style == 'plain' ? null : _patternPainter(l);
    final bottom = floating ? _overlay : 0.0;
    final edge = k.density.edge;
    final Widget content;
    if (centeredWelcome) {
      content = Padding(padding: EdgeInsets.only(bottom: bottom), child: _emptyState(l));
    } else {
      final lazy = widget.fill || items.length >= 12;
      final last = items.length - 1;
      Widget row(BuildContext context, int i) {
        final item = items[i];
        final gap = i == 0 ? 0.0 : (item.gap ?? k.density.gap);
        return KeyedSubtree(
          key: ValueKey<String>(item.key),
          child: Padding(
            padding: EdgeInsets.only(top: gap, left: item.bleed ? 0 : edge, right: item.bleed ? 0 : edge),
            child: item.build(context),
          ),
        );
      }

      // A hero is the thread's first block, flush under the header.
      final padding = EdgeInsets.only(top: items.isNotEmpty && items.first.bleed ? 0 : edge, bottom: edge + bottom);
      // Newest at the bottom, and the bottom is where it opens: a reversed list,
      // so a short conversation sits by the composer, as the window always drew
      // it, and rows added below a reader who scrolled up leave what they read
      // where it is (the list lays out from the rows it already has).
      // A welcome card or hero stays at the top of the conversation: a short
      // thread hangs from the header instead of sitting by the composer.
      final hangs = widget.fill && _welcomes;
      final list = ListView.builder(
        key: ChatWindow.threadKey,
        controller: _scroll,
        reverse: true,
        shrinkWrap: hangs,
        padding: padding,
        itemCount: items.length,
        findChildIndexCallback: (Key key) {
          if (key is! ValueKey<String>) return null;
          final i = items.indexWhere((_Item it) => it.key == key.value);
          return i < 0 ? null : last - i;
        },
        itemBuilder: (BuildContext context, int index) => row(context, last - index),
      );
      content = lazy
          ? (hangs ? Align(alignment: Alignment.topCenter, child: list) : list)
          // A short thread in the compact window: every row built, as it always was.
          : SingleChildScrollView(
              key: ChatWindow.threadKey,
              controller: _scroll,
              reverse: true,
              padding: padding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[for (var i = 0; i < items.length; i++) row(context, i)],
              ),
            );
    }
    final stack = Stack(
      children: <Widget>[
        if (pattern != null) Positioned.fill(child: CustomPaint(painter: pattern)),
        if (widget.fill) Positioned.fill(child: content) else content,
        if (floating)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _Measured(
              onSize: (Size s) {
                if (!mounted || (s.height - _overlay).abs() <= 0.5) return;
                setState(() => _overlay = s.height);
                _stickToBottom();
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (docked != null) docked,
                  Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 10), child: _composer(l)),
                ],
              ),
            ),
          ),
        if (!_following && !centeredWelcome)
          Positioned(
            left: 0,
            right: 0,
            bottom: 8 + bottom,
            child: Center(
              child: ChatScrollPill(
                key: ChatWindow.pillKey,
                look: l,
                unseen: _unseen,
                onTap: _scrollToLatest,
                shadows: _cardShadows(l),
              ),
            ),
          ),
        if (_copied)
          Positioned(
            left: 0,
            right: 0,
            top: 8,
            child: Center(
              child: Semantics(
                liveRegion: true,
                child: Container(
                  key: ChatWindow.copiedKey,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: l.text, borderRadius: BorderRadius.circular(14)),
                  child: Text('Copied', style: l.captionStrongStyle.copyWith(color: l.background)),
                ),
              ),
            ),
          ),
      ],
    );
    if (widget.fill) return stack;
    final cap = (widget.lifted ? 150.0 : 260.0) + bottom;
    if (centeredWelcome || items.length < 12) return ConstrainedBox(constraints: BoxConstraints(maxHeight: cap), child: stack);
    // A long conversation: the thread at its full height, the list lazy inside it.
    return SizedBox(height: cap, child: stack);
  }

  /// New rows: followed while the reader is at the bottom, counted while they read further up.
  void _noteGrowth(List<_Item> items, List<_Line> lines) {
    final messages = items.where((_Item i) => i.message).length;
    final last = items.isEmpty ? '' : items.last.key;
    // A reply still arriving grows its own row: the thread follows it too.
    final lastText = lines.isEmpty ? 0 : lines.last.caption.text.length;
    // What sits at the bottom of the thread. A row added at the top (a booked
    // call, a pinned card) moves nothing in a reversed list; one at the bottom does.
    final bottom = '$last|$lastText|${widget.typing}|${widget.ended}|${widget.rating}';
    final signature = '${items.length}|$bottom';
    if (signature == _lastSignature) return;
    final added = math.max(0, messages - _messages);
    final below = bottom != _lastBottom;
    _lastSignature = signature;
    _lastBottom = bottom;
    _messages = messages;
    if (_following) {
      _stickToBottom();
    } else if (below) {
      // Something changed below a reader who scrolled up: what they read stays where it is.
      _scroll.holdPlace();
      if (added > 0) _unseen += added;
    }
  }

  /// Before any message: the empty chat (v1) — or, before the chat's
  /// tokens, the sentence the window always opened with — with the booked
  /// calls above it and the starters placed in the thread under it.
  Widget _emptyState(ChatLook l) {
    final card = _upcomingCard(l);
    final empty = l.designed ? _emptyChat(l) : _emptySentence(l);
    final pin = widget.pin;
    final pinCard = pin != null && l.chat.header.contextCard == 'card'
        ? chatPinCard(l, pin, key: ChatWindow.contextCardKey, decoration: _cardBox(l))
        : null;
    final starters = l.designed ? _threadStarters(l, alignment: WrapAlignment.center) : null;
    final edge = l.chat.density.edge;
    if (card == null && pinCard == null && starters == null) {
      return widget.fill ? Center(child: SingleChildScrollView(child: empty)) : empty;
    }
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (pinCard != null) ...<Widget>[pinCard, SizedBox(height: l.chat.density.gap)],
        if (card != null) ...<Widget>[card, SizedBox(height: l.chat.density.gap)],
        empty,
        if (starters != null) starters,
      ],
    );
    return SingleChildScrollView(reverse: true, padding: EdgeInsets.all(edge), child: column);
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
    final w = l.chat.wallpaper;
    return Padding(
      key: ChatWindow.emptyKey,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (mark != null) ...<Widget>[mark, const SizedBox(height: 12)],
          Text(_title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: l.emptyTitleStyle.copyWith(color: l.ink(w.text))),
          if (l.subtitle.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(l.subtitle, textAlign: TextAlign.center, style: l.emptySubtitleStyle.copyWith(color: l.ink(w.textMuted))),
          ],
        ],
      ),
    );
  }

  /// THE WELCOME AS A CARD: the avatar (40) beside the title over the
  /// subtitle, and the starters inside it (a list, or chips placed inline).
  Widget _welcomeCard(ChatLook l) {
    final mark = _avatar(l, 40);
    final starters = _threadStarters(l, alignment: WrapAlignment.start);
    return Container(
      key: ChatWindow.welcomeKey,
      padding: EdgeInsets.all(l.pad),
      decoration: _cardBox(l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (mark != null) ...<Widget>[mark, const SizedBox(width: 10)],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Semantics(header: true, child: Text(_title, style: l.welcomeTitleStyle.copyWith(color: l.text))),
                    if (l.subtitle.isNotEmpty) Text(l.subtitle, style: l.captionStyle),
                  ],
                ),
              ),
            ],
          ),
          if (starters != null) ...<Widget>[SizedBox(height: l.chat.density.gap), starters],
        ],
      ),
    );
  }

  /// THE WELCOME AS A HERO: the window's full width in the header's fill (a
  /// gradient top → bottom), its bottom corners `radius.xl`; the avatar 56,
  /// the title and subtitle centred, and the starters under them.
  Widget _hero(ChatLook l) {
    final fill = l.chat.header.fill;
    final mark = _avatar(l, 56);
    final starters = _threadStarters(l, alignment: WrapAlignment.center);
    final top = l.ink(fill.color);
    return Container(
      key: ChatWindow.welcomeKey,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: fill.colorTo == null ? top : null,
        gradient: fill.colorTo == null
            ? null
            : LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: <Color>[top, l.ink(fill.colorTo!)]),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(l.xl)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (mark != null) ...<Widget>[Center(child: mark), const SizedBox(height: 12)],
          Semantics(
            header: true,
            child: Text(_title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: l.heroTitleStyle.copyWith(color: l.ink(fill.text))),
          ),
          if (l.subtitle.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(l.subtitle, textAlign: TextAlign.center, style: l.heroSubtitleStyle.copyWith(color: l.ink(fill.textMuted))),
          ],
          if (starters != null) ...<Widget>[const SizedBox(height: 16), starters],
        ],
      ),
    );
  }

  /// A day separator: centred, caption size, strong, on the wallpaper (DESIGN.md "Day separators").
  Widget _dayLine(ChatLook l, _Line line) => Semantics(
        key: line.key,
        header: true,
        child: Text(line.dayLabel!, textAlign: TextAlign.center, style: l.dayStyle.copyWith(color: l.ink(l.chat.wallpaper.textMuted))),
      );

  /// An earlier call, as one row: the call icon and "Voice call · 6:05 PM" —
  /// that it happened, never what was said.
  Widget _callLine(ChatLook l, _Line line) {
    final clock = ChatTime.clock(line.callAt!, h24: _h24);
    final muted = l.ink(l.chat.wallpaper.textMuted);
    return Semantics(
      key: line.key,
      label: ChatRows.callSpoken(clock),
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          SdkIconView('call', color: muted, size: 14, style: l.iconStyle, stroke: l.iconStroke),
          const SizedBox(width: 6),
          Flexible(
              child: Text(ChatRows.callLabel(clock),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: l.callStyle.copyWith(color: muted))),
        ],
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
    final decoration = _cardBox(l, color: chrome == null ? l.cardFill : l.cardBody);
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
            topRadius: WindowChrome.innerRadius(l.chat.cards.radius, bw),
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
          constraints: const BoxConstraints(minHeight: 32),
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
    final cards = l.chat.cards;
    return Tap(
      key: ChatWindow.bookKey,
      label: 'Book a call',
      onTap: widget.onBook,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: l.pad, vertical: (l.pad * 0.75).roundToDouble()),
        decoration: BoxDecoration(
          color: l.cardFill,
          border: cards.border && l.borderWidth > 0 ? Border.all(color: l.border, width: l.borderWidth) : null,
          borderRadius: BorderRadius.circular(cards.radius),
          boxShadow: _cardShadows(l),
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
            constraints: const BoxConstraints(minHeight: 32),
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

  // ── the composer ────────────────────────────────────────────────────────

  /// The words the user is writing, and the placeholder while there are none.
  Widget _field(ChatLook l, ThemeChatComposer c) {
    final placeholder = l.placeholder.isNotEmpty ? l.placeholder : 'Message…';
    final style = l.inputStyle.copyWith(color: l.ink(c.text));
    return Stack(
      alignment: AlignmentDirectional.centerStart,
      children: <Widget>[
        if (_draft.text.isEmpty)
          IgnorePointer(
            child: Text(placeholder, maxLines: 1, overflow: TextOverflow.ellipsis, style: style.copyWith(color: l.ink(c.placeholder))),
          ),
        // EditableText, not a Material TextField: the bar sits above the
        // app's Navigator, where there is no Material and no Overlay for a
        // text field's handles to live in.
        EditableText(
          controller: _draft,
          focusNode: _focus,
          style: style,
          cursorColor: l.accent,
          backgroundCursorColor: l.muted,
          maxLines: 1,
          textInputAction: TextInputAction.send,
          // Sent, and the keyboard stays up for the next message.
          onEditingComplete: () {},
          onSubmitted: (String _) => _submit(),
        ),
      ],
    );
  }

  /// THE SEND BUTTON at [size] — or, with `composer.mic` and an empty field
  /// where the agent takes calls, the microphone that calls it. `circle`:
  /// round on `sendFill`; `rounded`: corners `min(radius.md, 12)`; `icon`: no
  /// fill, the icon at 22 in a 44 target. The send icon mirrors in RTL.
  Widget _send(ChatLook l, ThemeChatComposer c, double size) {
    final ready = _draft.text.trim().isNotEmpty;
    final call = widget.onCall;
    final mic = c.mic && call != null && !ready;
    final iconOnly = c.send == 'icon';
    final fill = c.sendFill == null ? null : l.accentInk(c.sendFill!);
    final iconColor = fill != null ? l.inkOn(fill, c.sendIcon) : l.accentInk(c.sendIcon);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    Widget icon = SdkIconView(mic ? 'mic' : 'send',
        color: iconColor, size: iconOnly ? 22 : (size >= 40 ? 18 : 16), style: l.iconStyle, stroke: l.iconStroke);
    if (rtl && !mic) icon = Transform.flip(flipX: true, child: icon);
    final box = iconOnly ? 44.0 : size;
    return Tap(
      key: ChatWindow.sendKey,
      label: mic ? 'Call $_title' : 'Send',
      enabled: mic || ready,
      onTap: mic ? call : _submit,
      child: Opacity(
        opacity: mic || ready ? 1 : 0.4,
        child: Container(
          width: box,
          height: box,
          alignment: Alignment.center,
          decoration: iconOnly || fill == null
              ? null
              : BoxDecoration(
                  color: fill,
                  shape: c.send == 'rounded' ? BoxShape.rectangle : BoxShape.circle,
                  borderRadius: c.send == 'rounded' ? BorderRadius.circular(math.min(l.md, 12)) : null,
                ),
          child: icon,
        ),
      ),
    );
  }

  /// The paperclip (where the design asks for one and the app handles
  /// attachments) and the call button (`escalation.call: composer`, where
  /// the agent takes calls and the microphone does not already call).
  List<Widget> _tools(ChatLook l, ThemeChatComposer c) {
    final color = l.accentInk(c.icon);
    final attach = widget.onAttach;
    final call = widget.onCall;
    Widget tool(Key key, String icon, String label, VoidCallback onTap) => Tap(
          key: key,
          label: label,
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(child: SdkIconView(icon, color: color, size: 20, style: l.iconStyle, stroke: l.iconStroke)),
          ),
        );
    return <Widget>[
      if (c.attach && attach != null) tool(ChatWindow.attachKey, 'attach', 'Attach', attach),
      if (l.chat.escalation.call == 'composer' && call != null && !c.mic)
        tool(ChatWindow.composerCallKey, 'call', 'Call $_title', call),
    ];
  }

  /// THE COMPOSER, by `composer.style`: `bar` — a strip 58 high, the field
  /// and the send button beside it (v1); `pill` — a strip 60 high, the field
  /// a pill with the send button inside it; `floating` — one raised capsule
  /// over the thread, the send button inside it.
  Widget _composer(ChatLook l) {
    final c = l.chat.composer;
    final tools = _tools(l, c);
    final bw = l.borderWidth;
    final border = bw > 0 ? Border.all(color: l.ink(c.border), width: bw) : null;
    final fill = l.ink(c.fill);
    switch (c.style) {
      case 'pill':
      case 'floating':
        final floating = c.style == 'floating';
        final glass = l.chat.glass;
        final radius = BorderRadius.circular(floating ? c.radius : c.height / 2);
        // The send button inside the field, 6 in from a floating capsule's edge, 4 from a pill's.
        final inset = floating ? 6.0 : 4.0;
        final capsule = GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: _focus.requestFocus,
          child: surfaceBox(
            key: ChatWindow.composerKey,
            color: glass == null ? fill : fade(fill, glass.opacity),
            border: l.ink(c.border),
            borderWidth: bw,
            radius: radius,
            shadows: floating ? shadowsOf(c.shadow) : const <BoxShadow>[],
            glass: glass?.asGlass,
            minHeight: c.height,
            padding: EdgeInsetsDirectional.only(start: tools.isEmpty ? 14 : inset, end: inset),
            child: Row(
              children: <Widget>[
                ...tools,
                if (tools.isNotEmpty) const SizedBox(width: 4),
                Expanded(child: _field(l, c)),
                const SizedBox(width: 8),
                _send(l, c, 36),
              ],
            ),
          ),
        );
        if (floating) return capsule;
        return Container(
          constraints: const BoxConstraints(minHeight: 60),
          color: c.strip == null ? null : l.ink(c.strip!),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          alignment: Alignment.center,
          child: capsule,
        );
      default: // bar
        final glass = l.chat.glass;
        final radius = BorderRadius.circular(c.radius);
        return Container(
          constraints: const BoxConstraints(minHeight: 58),
          color: c.strip == null ? null : l.ink(c.strip!),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: <Widget>[
              ...tools,
              if (tools.isNotEmpty) const SizedBox(width: 4),
              Expanded(
                // The whole field focuses the text, not only its one line.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  excludeFromSemantics: true,
                  onTap: _focus.requestFocus,
                  child: frosted(
                    radius: radius,
                    glass: glass,
                    child: Container(
                      key: ChatWindow.composerKey,
                      constraints: BoxConstraints(minHeight: c.height),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: AlignmentDirectional.centerStart,
                      decoration: BoxDecoration(
                        color: glass == null ? fill : fade(fill, glass.opacity),
                        border: border,
                        borderRadius: radius,
                      ),
                      child: _field(l, c),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _send(l, c, 40),
            ],
          ),
        );
    }
  }
}

/// THE THREAD'S SCROLLING. The thread is a reversed list (its offset is the
/// distance from the newest row); when rows arrive, grow or go below a reader
/// who scrolled up, the list lays itself out again from the newest row and
/// what they were reading would slide. [holdPlace] asks the next layout to
/// move the offset by exactly what the content below them changed by, before
/// anything is painted.
class _ThreadScroll extends ScrollController {
  bool _hold = false;

  void holdPlace() => _hold = true;

  @override
  ScrollPosition createScrollPosition(ScrollPhysics physics, ScrollContext context, ScrollPosition? oldPosition) =>
      _ThreadPosition(this, physics: physics, context: context, oldPosition: oldPosition, initialPixels: initialScrollOffset);
}

class _ThreadPosition extends ScrollPositionWithSingleContext {
  _ThreadPosition(this._owner, {required super.physics, required super.context, super.oldPosition, super.initialPixels});

  final _ThreadScroll _owner;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    if (_owner._hold && hasContentDimensions && hasPixels) {
      _owner._hold = false;
      final grew = maxScrollExtent - this.maxScrollExtent;
      if (grew.abs() > 0.5) {
        super.applyContentDimensions(minScrollExtent, maxScrollExtent);
        correctPixels(pixels + grew);
        return false; // lay out again at the held place
      }
    }
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }
}

/// One line of the thread: what was said, when, and where it is — or a day
/// separator, or an earlier call's one row.
class _Line {
  const _Line(this.caption, this.id, {this.at, this.status = ChatMessageStatus.sent})
      : dayLabel = null,
        callAt = null,
        key = null;

  const _Line.day(String this.dayLabel, this.id, {this.key})
      : caption = const Caption(Role.agent, ''),
        at = null,
        status = ChatMessageStatus.sent,
        callAt = null;

  const _Line.call(DateTime this.callAt, this.id, {this.key})
      : caption = const Caption(Role.agent, ''),
        at = null,
        status = ChatMessageStatus.sent,
        dayLabel = null;

  final Caption caption;

  /// Stable while the conversation grows.
  final String id;
  final DateTime? at;
  final ChatMessageStatus status;
  final String? dayLabel;
  final DateTime? callAt;
  final Key? key;
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

/// Reports its child's size after each layout that changes it — the height
/// of what floats over the thread, which the thread's last row must clear.
class _Measured extends SingleChildRenderObjectWidget {
  const _Measured({required this.onSize, super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMeasured(onSize);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasured renderObject) => renderObject.onSize = onSize;
}

class _RenderMeasured extends RenderProxyBox {
  _RenderMeasured(this.onSize);

  ValueChanged<Size> onSize;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _last) return;
    _last = size;
    final s = size;
    WidgetsBinding.instance.addPostFrameCallback((Duration _) => onSize(s));
  }
}
