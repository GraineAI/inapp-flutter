// The chat window's smaller pieces (contract/DESIGN.md, "Chat window v2"):
// the typing indicators, chips, the starters as a list, the rating card, the
// wallpaper's patterns, the scroll-to-latest pill, the reconnect banner and
// the card the app pins. Not exported: ChatWindow draws them.
import 'dart:math' as math;
import 'dart:ui' as ui show ImageFilter;

import 'package:flutter/widgets.dart';

import 'chat_window.dart' show ChatLook;
import 'core/core.dart';
import 'loader_view.dart';
import 'sdk_icon.dart';
import 'style.dart';

/// A box in the design's glass when [glass] is set: its colour (already
/// faded) over a blur of what is behind, clipped to [radius].
Widget frosted({required Widget child, required BorderRadius radius, ThemeChatGlass? glass}) {
  if (glass == null || glass.blur <= 0) return child;
  return ClipRRect(
    borderRadius: radius,
    child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: glass.blur, sigmaY: glass.blur), child: child),
  );
}

// ── typing ───────────────────────────────────────────────────────────────────

/// THE AGENT IS TYPING, in `chat.typing.style`: the design's loader in an
/// agent bubble (classic), three fading dots, a wave of dots, or words with
/// no bubble — still when the OS asks for less motion. Announced politely.
class ChatTypingIndicator extends StatefulWidget {
  const ChatTypingIndicator({
    super.key,
    required this.look,
    required this.name,
    required this.bubble,
    this.loader,
    this.loaderColor,
  });

  final ChatLook look;

  /// Who is typing: "{name} is typing".
  final String name;

  /// An agent bubble around [child], as the thread draws one.
  final Widget Function(Widget child, {EdgeInsetsGeometry? padding}) bubble;
  final LoaderLook? loader;
  final Color? loaderColor;

  @override
  State<ChatTypingIndicator> createState() => _ChatTypingIndicatorState();
}

class _ChatTypingIndicatorState extends State<ChatTypingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(vsync: this, duration: _period);

  Duration get _period => switch (widget.look.chat.typing.style) {
        'wave' => const Duration(milliseconds: 900),
        'text' => const Duration(milliseconds: 1400),
        _ => const Duration(milliseconds: 1200),
      };

  bool get _animated => widget.look.chat.typing.style != 'loader';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(ChatTypingIndicator old) {
    super.didUpdateWidget(old);
    _t.duration = _period;
    _sync();
  }

  void _sync() {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still || !_animated) {
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

  bool get _still => (MediaQuery.maybeDisableAnimationsOf(context) ?? false) || !_t.isAnimating;

  @override
  Widget build(BuildContext context) {
    final l = widget.look;
    final typing = l.chat.typing;
    final color = l.accentInk(typing.color);
    final Widget body;
    switch (typing.style) {
      case 'dots':
      case 'wave':
        final wave = typing.style == 'wave';
        body = widget.bubble(AnimatedBuilder(
          animation: _t,
          builder: (BuildContext context, Widget? _) => SizedBox(
            height: 7 + (wave ? 4 : 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (var i = 0; i < 3; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: 5),
                  Transform.translate(
                    offset: Offset(0, wave && !_still ? -4 * _rise(i) : 0),
                    child: Opacity(
                      opacity: wave ? 1 : (_still ? 0.6 : _fade(i)),
                      child: Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ));
      case 'text':
        body = AnimatedBuilder(
          animation: _t,
          builder: (BuildContext context, Widget? _) => Opacity(
            opacity: _still ? 1 : 0.55 + 0.45 * (0.5 - 0.5 * math.cos(2 * math.pi * _t.value)),
            child: Text(typing.words, style: l.captionStyle.copyWith(color: color)),
          ),
        );
      default: // loader: the design's "while the assistant thinks" loader, at 14, in an agent bubble.
        final look = widget.loader ?? Loaders.resolve(null);
        body = widget.bubble(
          GraineLoaderView(look: look, color: widget.loaderColor ?? l.accent, trackColor: l.border, size: 14),
          padding: EdgeInsets.symmetric(horizontal: l.chat.density.padX, vertical: (l.pad * 0.5).roundToDouble()),
        );
    }
    return Semantics(liveRegion: true, label: '${widget.name} is typing', child: ExcludeSemantics(child: body));
  }

  /// Dot [i]'s opacity: 0.35 → 1 → 0.35 over the period, i × 160 ms late.
  double _fade(int i) {
    final p = (_t.value - i * 160 / 1200) % 1.0;
    return 0.35 + 0.65 * (0.5 - 0.5 * math.cos(2 * math.pi * p));
  }

  /// Dot [i]'s rise, 0–1: up and back over the period, i × 120 ms late.
  double _rise(int i) {
    final p = (_t.value - i * 120 / 900) % 1.0;
    return 0.5 - 0.5 * math.cos(2 * math.pi * p);
  }
}

// ── chips ────────────────────────────────────────────────────────────────────

/// ONE CHIP — a starter or a quick reply, one look (`chat.chips`): its
/// height (growing with the text), 14 in, its corners, fill, outline and
/// shadow, the words on one line. A tap sends them.
Widget chatChip(ChatLook l, String words, {Key? key, required VoidCallback? onTap, double? maxWidth}) {
  final k = l.chat.chips;
  final border = k.border;
  final radius = BorderRadius.circular(k.radius);
  final glass = k.style == 'elevated' ? l.chat.glass : null;
  // Chips decorate: a host's own accent recolours them, the words following the fill.
  final fill = l.accentInk(k.fill);
  Widget chip = Container(
    constraints: BoxConstraints(minHeight: k.height),
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
      color: glass == null ? fill : fade(fill, glass.opacity),
      border: border != null && k.borderWidth > 0 ? Border.all(color: l.accentInk(border), width: k.borderWidth) : null,
      borderRadius: radius,
      boxShadow: shadowsOf(k.shadow),
    ),
    // As wide as its words (a Container's own alignment would stretch it across a row), centred in its height.
    child: Center(
      widthFactor: 1,
      child: Text(words, maxLines: 1, overflow: TextOverflow.ellipsis, style: l.starterStyle.copyWith(color: l.inkOn(fill, k.text))),
    ),
  );
  chip = frosted(child: chip, radius: radius, glass: glass);
  if (maxWidth != null) chip = ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: chip);
  return Tap(key: key, label: words, onTap: onTap, child: chip);
}

/// CHIPS TOGETHER: rows that wrap, 8 apart both ways, on [alignment]'s side
/// — or (`chips.scroll: row`) one row that scrolls sideways, 8 apart,
/// starting [edge] in.
Widget chatChips(
  ChatLook l,
  List<String> words, {
  Key? key,
  required Key Function(int index) chipKey,
  required void Function(int index) onTap,
  WrapAlignment alignment = WrapAlignment.end,
  double edge = 12,
}) {
  if (l.chat.chips.scroll == 'row') {
    return Builder(
      key: key,
      builder: (BuildContext context) {
        // As tall as a chip is with the user's text size, and room for an elevated chip's shadow.
        final words1 = MediaQuery.textScalerOf(context).scale(l.starterStyle.fontSize ?? 14) * 1.35 + 8;
        return SizedBox(
          height: math.max(l.chat.chips.height, words1) + 8,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: edge, vertical: 4),
            itemCount: words.length,
            separatorBuilder: (BuildContext _, int __) => const SizedBox(width: 8),
            itemBuilder: (BuildContext _, int i) => Center(child: chatChip(l, words[i], key: chipKey(i), onTap: () => onTap(i))),
          ),
        );
      },
    );
  }
  return Padding(
    key: key,
    padding: EdgeInsets.symmetric(horizontal: edge),
    child: LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) => Wrap(
        alignment: alignment,
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (var i = 0; i < words.length; i++)
            chatChip(l, words[i], key: chipKey(i), onTap: () => onTap(i), maxWidth: box.maxWidth),
        ],
      ),
    ),
  );
}

/// THE STARTERS AS A LIST (`welcome.starters: list`): full width, 8 apart,
/// rows 44 high (they grow), `surfaceRaised`, the outline, `radius.md`, 14
/// in, the words, and a chevron pointing to the trailing side.
Widget chatStarterList(ChatLook l, List<String> words,
    {Key? key, required Key Function(int index) rowKey, required void Function(int index) onTap}) {
  final glass = l.chat.glass;
  final radius = BorderRadius.circular(l.md);
  return Column(
    key: key,
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      for (var i = 0; i < words.length; i++) ...<Widget>[
        if (i > 0) const SizedBox(height: 8),
        Tap(
          key: rowKey(i),
          label: words[i],
          onTap: () => onTap(i),
          child: frosted(
            radius: radius,
            glass: glass,
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: glass == null ? l.cardFill : fade(l.cardFill, glass.opacity),
                border: l.borderWidth > 0 ? Border.all(color: l.border, width: l.borderWidth) : null,
                borderRadius: radius,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text(words[i], style: l.starterStyle.copyWith(color: l.text))),
                  const SizedBox(width: 8),
                  // The chevron is drawn pointing up: a quarter turn points it to the trailing side.
                  Builder(
                    builder: (BuildContext context) => Transform.rotate(
                      angle: Directionality.of(context) == TextDirection.rtl ? -math.pi / 2 : math.pi / 2,
                      child: SdkIconView('chevron', color: l.muted, size: 16, style: l.iconStyle, stroke: l.iconStroke),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ],
  );
}

// ── the rating ───────────────────────────────────────────────────────────────

/// "HOW WAS THIS CHAT?" — the card at the end of a conversation the agent
/// ended (`chat.rating`): the prompt, then two thumbs, five stars or five
/// faces; once chosen, the choice stays, nothing else can be chosen, and
/// "Thanks for your feedback" appears under it. Its width and its choices'
/// size come from the width of the thread it sits in ([ChatRatings.layout]),
/// so a narrow phone or a large display setting never pushes a choice out of
/// the card.
class ChatRatingCard extends StatelessWidget {
  const ChatRatingCard({super.key, required this.look, required this.decoration, this.rating, this.onRate});

  final ChatLook look;

  /// The card's own box (`chat.cards`).
  final BoxDecoration decoration;

  /// The answer, once given.
  final GraineChatRating? rating;

  /// A choice: the style and its value (thumbs 1 up / 0 down; 1–5).
  final void Function(GraineChatRatingStyle style, int value)? onRate;

  static Key choiceKey(int value) => ValueKey<String>('graine-chat-rating-$value');
  static const Key thanksKey = ValueKey<String>('graine-chat-rating-thanks');

  /// The card itself, as wide as the layout says (the widget spans the thread's row).
  static const Key cardKey = ValueKey<String>('graine-chat-rating-card');

  @override
  Widget build(BuildContext context) {
    final l = look;
    final k = l.chat.rating;
    final style = GraineChatRatingStyle.of(k.style);
    final chosen = rating;
    final labels = ChatRatings.labels[style]!;
    Widget choice(int value, Widget face, {required bool on}) => Semantics(
          button: true,
          selected: on,
          enabled: chosen == null && onRate != null,
          label: style == GraineChatRatingStyle.thumbs ? labels[value] : labels[value - 1],
          excludeSemantics: true,
          child: GestureDetector(
            key: choiceKey(value),
            behavior: HitTestBehavior.opaque,
            onTap: chosen == null && onRate != null ? () => onRate!(style, value) : null,
            child: face,
          ),
        );

    // The thread's row is this widget's width (inside the thread's own side
    // padding); with no bound there is room for everything.
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints box) {
      final fit = ChatRatings.layout(style, box.hasBoundedWidth ? box.maxWidth : double.maxFinite, l.pad);
      final List<Widget> choices;
      switch (style) {
        case GraineChatRatingStyle.thumbs:
          Widget thumb(int value, String icon) {
            final on = chosen?.value == value && chosen?.style == style;
            return choice(
              value,
              Container(
                width: fit.size,
                height: fit.size,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: on ? l.accent : l.soft, shape: BoxShape.circle),
                child: SdkIconView(icon, color: on ? l.onAccent : l.text, size: fit.glyph, style: l.iconStyle, stroke: l.iconStroke),
              ),
              on: on,
            );
          }
          choices = <Widget>[thumb(1, 'thumbUp'), thumb(0, 'thumbDown')];
        case GraineChatRatingStyle.stars:
          choices = <Widget>[
            for (var v = 1; v <= 5; v++)
              choice(
                v,
                SizedBox(
                  width: fit.size,
                  height: fit.size,
                  child: Center(
                    child: SdkIconView(
                      'star',
                      color: chosen != null && v <= chosen.value ? l.accent : l.muted,
                      size: fit.glyph,
                      style: chosen != null && v <= chosen.value ? 'filled' : 'outline',
                      stroke: l.iconStroke,
                    ),
                  ),
                ),
                on: chosen?.value == v,
              ),
          ];
        case GraineChatRatingStyle.emoji:
          choices = <Widget>[
            for (var v = 1; v <= 5; v++)
              choice(
                v,
                Container(
                  width: fit.size,
                  height: fit.size,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: chosen?.value == v ? l.soft : null, shape: BoxShape.circle),
                  child: Transform.scale(
                    scale: chosen?.value == v ? 1.15 : 1,
                    // A picture, sized by the layout: never scaled with the system's text size.
                    child: Text(ChatRatings.emoji[v - 1],
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(fontSize: fit.glyph, height: 1, decoration: TextDecoration.none)),
                  ),
                ),
                on: chosen?.value == v,
              ),
          ];
      }
      return Center(
        child: SizedBox(
          key: cardKey,
          width: fit.width,
          // The outline is drawn on the card's edge, inside its padding, so the
          // choices have exactly the width the layout gives them.
          child: DecoratedBox(
            decoration: decoration,
            child: Padding(
              padding: EdgeInsets.all(l.pad),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Semantics(
                    header: true,
                    child: Text(k.prompt.trim().isNotEmpty ? k.prompt : ChatRatings.defaultPrompt,
                        textAlign: TextAlign.center, style: l.headingStyle.copyWith(color: l.text)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (var i = 0; i < choices.length; i++) ...<Widget>[
                        if (i > 0) SizedBox(width: fit.gap),
                        choices[i],
                      ],
                    ],
                  ),
                  if (chosen != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Semantics(
                      liveRegion: true,
                      child: Text(ChatRatings.thanks, key: thanksKey, textAlign: TextAlign.center, style: l.captionStyle),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

// ── the wallpaper's patterns ─────────────────────────────────────────────────

/// `grid` — 1-wide lines at x = 9 + 18k and y = 9 + 18k; `diagonal` — 1-wide
/// lines where x + y is a multiple of 14, rising left to right. Never mirrored.
class ChatLinePattern extends CustomPainter {
  ChatLinePattern(this.pattern, this.color);

  final String pattern;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    if (pattern == 'grid') {
      for (var x = 9.0; x < size.width; x += 18) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
      for (var y = 9.0; y < size.height; y += 18) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
      return;
    }
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var c = 14.0; c < size.width + size.height; c += 14) {
      canvas.drawLine(Offset(c, 0), Offset(0, c), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(ChatLinePattern old) => old.pattern != pattern || old.color != color;
}

// ── scroll to the latest ─────────────────────────────────────────────────────

/// THE PILL that takes a reader scrolled up back to the newest row: 36 high,
/// `surfaceRaised`, the outline, the card shadow, the down arrow — and "N
/// new" ("9+" past nine) once something arrived since.
class ChatScrollPill extends StatelessWidget {
  const ChatScrollPill({super.key, required this.look, required this.unseen, required this.onTap, required this.shadows});

  final ChatLook look;
  final int unseen;
  final VoidCallback onTap;
  final List<BoxShadow> shadows;

  @override
  Widget build(BuildContext context) {
    final l = look;
    return Tap(
      label: 'Scroll to the latest message',
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 36, minWidth: 36),
        padding: EdgeInsets.symmetric(horizontal: unseen > 0 ? 12 : 10),
        decoration: BoxDecoration(
          color: l.cardFill,
          border: Border.all(color: l.border, width: math.max(1, l.borderWidth)),
          borderRadius: BorderRadius.circular(18),
          boxShadow: shadows,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SdkIconView('arrowDown', color: l.text, size: 16, style: l.iconStyle, stroke: l.iconStroke),
            if (unseen > 0) ...<Widget>[
              const SizedBox(width: 6),
              Text(unseen > 9 ? '9+ new' : '$unseen new', style: l.captionStrongStyle.copyWith(color: l.text)),
            ],
          ],
        ),
      ),
    );
  }
}

// ── the reconnect banner ─────────────────────────────────────────────────────

/// THE CALM RECONNECT BANNER under the header: 28 high, `surfaceRaised`,
/// a hairline under it; the loader and "Reconnecting…", or a warning dot and
/// "Offline · messages send when you're back". Never red, never a modal.
class ChatReconnectBanner extends StatelessWidget {
  const ChatReconnectBanner({
    super.key,
    required this.look,
    required this.reconnecting,
    this.loader,
    this.loaderColor,
    this.reconnectingText,
  });

  final ChatLook look;

  /// Reconnecting (true), or offline with a message waiting (false).
  final bool reconnecting;
  final LoaderLook? loader;
  final Color? loaderColor;
  final String? reconnectingText;

  static const String offlineWords = "Offline · messages send when you're back";

  @override
  Widget build(BuildContext context) {
    final l = look;
    final glass = l.chat.glass;
    final words = reconnecting ? (reconnectingText ?? 'Reconnecting…') : offlineWords;
    return Semantics(
      liveRegion: true,
      label: words,
      excludeSemantics: true,
      child: frosted(
        radius: BorderRadius.zero,
        glass: glass,
        child: Container(
          constraints: const BoxConstraints(minHeight: 28),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: glass == null ? l.cardFill : fade(l.cardFill, glass.opacity),
            border: Border(bottom: BorderSide(color: l.border, width: l.borderWidth > 0 ? l.borderWidth : 1)),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (reconnecting)
                GraineLoaderView(look: loader ?? Loaders.resolve(null), color: loaderColor ?? l.accent, trackColor: l.border, size: 12)
              else
                Container(width: 6, height: 6, decoration: BoxDecoration(color: l.warning, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Flexible(child: Text(words, maxLines: 1, overflow: TextOverflow.ellipsis, style: l.captionStyle)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── the card the app pins ────────────────────────────────────────────────────

/// The pin's picture ([size] square, [radius] corners, filled and cropped),
/// or a disc of `accentSoft` with the title's first letter.
Widget chatPinThumb(ChatLook l, GraineChatPin pin, double size, double radius) {
  Widget letter() => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: l.soft, shape: BoxShape.circle),
        child: Text(initialOf(pin.title), style: l.starterStyle.copyWith(color: l.text, fontSize: 14)),
      );
  final url = pin.imageUrl;
  if (url == null) return letter();
  return ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.cover,
      excludeFromSemantics: true,
      errorBuilder: (BuildContext c, Object e, StackTrace? s) => letter(),
    ),
  );
}

/// The badge: a pill 22 high, 8 in, `accentSoft`, the words at caption size.
Widget chatPinBadge(ChatLook l, String words) => Container(
      constraints: const BoxConstraints(minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: l.soft, borderRadius: BorderRadius.circular(11)),
      child: Text(words, maxLines: 1, overflow: TextOverflow.ellipsis, style: l.captionStrongStyle.copyWith(color: l.text)),
    );

/// THE CONTEXT BAR under the header (`contextCard: bar`): 52 high,
/// `colors.surface` (frosted as the header is), a hairline under it; the
/// thumbnail, the title over the subtitle, the badge at the trailing end.
class ChatPinBar extends StatelessWidget {
  const ChatPinBar({super.key, required this.look, required this.pin, this.glass});

  final ChatLook look;
  final GraineChatPin pin;
  final ThemeGlass? glass;

  @override
  Widget build(BuildContext context) {
    final l = look;
    final g = glass;
    final bar = Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: g == null ? l.cardBody : fade(l.cardBody, g.surfaceOpacity),
        border: Border(bottom: BorderSide(color: l.border, width: l.borderWidth > 0 ? l.borderWidth : 1)),
      ),
      child: Row(
        children: <Widget>[
          chatPinThumb(l, pin, 32, l.sm),
          const SizedBox(width: 10),
          Expanded(child: _pinWords(l, pin, l.starterStyle.copyWith(color: l.text))),
          if (pin.badge != null) ...<Widget>[const SizedBox(width: 10), chatPinBadge(l, pin.badge!)],
        ],
      ),
    );
    return Semantics(
      container: true,
      label: pin.spoken,
      excludeSemantics: true,
      child: g == null
          ? bar
          : ClipRect(child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: g.blur, sigmaY: g.blur), child: bar)),
    );
  }
}

/// The pin's title over its subtitle.
Widget _pinWords(ChatLook l, GraineChatPin pin, TextStyle title) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(pin.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: title),
        if (pin.subtitle != null)
          Text(pin.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: l.captionStyle),
      ],
    );

/// THE CONTEXT CARD atop the thread (`contextCard: card`): drawn as a card,
/// a 44 thumbnail, the title in the heading family, the subtitle and badge.
Widget chatPinCard(ChatLook l, GraineChatPin pin, {required BoxDecoration decoration, Key? key}) => Semantics(
      key: key,
      container: true,
      label: pin.spoken,
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.all(l.pad),
        decoration: decoration,
        child: Row(
          children: <Widget>[
            chatPinThumb(l, pin, 44, l.md),
            const SizedBox(width: 10),
            Expanded(child: _pinWords(l, pin, l.headingStyle.copyWith(color: l.text))),
            if (pin.badge != null) ...<Widget>[const SizedBox(width: 10), chatPinBadge(l, pin.badge!)],
          ],
        ),
      ),
    );
