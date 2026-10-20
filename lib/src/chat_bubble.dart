// ONE MESSAGE OF THE CHAT WINDOW (contract/DESIGN.md, "Chat window v2" →
// Bubbles, Times, Message status): the bubble in its shape — rounded,
// squircle, tail or flat, with a group's tight inner corners — its fill
// (a colour, a gradient, glass, or none), the agent's words formatted and
// revealed smoothly while they arrive, the time below or inside with its
// delivery mark, and a message's status. Not exported: ChatWindow draws it.
import 'dart:math' as math;
import 'dart:ui' as ui show ImageFilter;

import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/widgets.dart';

import 'chat_window.dart' show ChatLook;
import 'core/core.dart';
import 'sdk_icon.dart';
import 'style.dart';

/// Where a bubble's tail is, on screen.
enum BubbleTail { none, left, right }

/// A bubble's corners and tail, resolved for the reading direction.
class BubbleGeometry {
  const BubbleGeometry(this.radius, {this.tail = BubbleTail.none, this.continuous = false});

  /// Each corner, left and right as drawn.
  final BorderRadius radius;
  final BubbleTail tail;

  /// Continuous (squircle) corners — only when all four are equal; a group's
  /// differing corners are drawn circular.
  final bool continuous;

  /// THE CORNERS OF A BUBBLE of [shape] at [position] in its group. The
  /// speaker's side is the trailing side for the user, the leading side for
  /// the agent — so both flip in RTL.
  ///
  ///  - `rounded`: every corner [radius], the bottom speaker-side one always
  ///    [tight] (v1), the top speaker-side one tight for middle and last;
  ///  - `squircle`: every corner [radius]; in a group the top speaker-side
  ///    one tight for middle and last, the bottom one for first and middle;
  ///  - `tail`: as squircle — and on a single or last bubble the bottom
  ///    speaker-side corner is square and carries the tail;
  ///  - `flat`: every corner [radius].
  static BubbleGeometry of({
    required String shape,
    required double radius,
    required double tight,
    required ChatGroupPosition position,
    required bool user,
    required TextDirection direction,
  }) {
    final speakerRight = user == (direction == TextDirection.ltr);
    final middleOrLast = position == ChatGroupPosition.middle || position == ChatGroupPosition.last;
    final firstOrMiddle = position == ChatGroupPosition.first || position == ChatGroupPosition.middle;
    var top = radius;
    var bottom = radius;
    var tail = BubbleTail.none;
    switch (shape) {
      case 'flat':
        break;
      case 'squircle':
      case 'tail':
        if (middleOrLast) top = tight;
        if (firstOrMiddle) bottom = tight;
        if (shape == 'tail' && (position == ChatGroupPosition.single || position == ChatGroupPosition.last)) {
          bottom = 0;
          tail = speakerRight ? BubbleTail.right : BubbleTail.left;
        }
      default: // rounded
        bottom = tight;
        if (middleOrLast) top = tight;
    }
    final far = Radius.circular(radius);
    final r = BorderRadius.only(
      topLeft: speakerRight ? far : Radius.circular(top),
      topRight: speakerRight ? Radius.circular(top) : far,
      bottomLeft: speakerRight ? far : Radius.circular(bottom),
      bottomRight: speakerRight ? Radius.circular(bottom) : far,
    );
    final equal = top == radius && bottom == radius;
    return BubbleGeometry(r, tail: tail, continuous: shape == 'squircle' && equal);
  }
}

/// A squircle's corner drawn by [ContinuousRectangleBorder] reaches as deep
/// at 45° as a circular corner this many times smaller: its curve's midpoint
/// sits at an eighth of its radius, a circle's at 1 − cos 45°.
const double _continuousScale = 2.343;

/// THE OUTLINE OF A BUBBLE that a box cannot draw: continuous corners, or a
/// tail. The tail is the contract's closed path, outside the bubble's width:
/// for a bubble whose bottom-right corner carries it, M W,H−12 · Q W+1,H−2
/// W+8,H · L W−12,H · Z — mirrored at the bottom-left.
class ChatBubbleBorder extends ShapeBorder {
  const ChatBubbleBorder({required this.geometry, this.side = BorderSide.none});

  final BubbleGeometry geometry;
  final BorderSide side;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  ShapeBorder scale(double t) => ChatBubbleBorder(geometry: geometry, side: side.scale(t));

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final g = geometry;
    if (g.continuous && g.tail == BubbleTail.none) {
      return ContinuousRectangleBorder(borderRadius: BorderRadius.circular(g.radius.topLeft.x * _continuousScale))
          .getOuterPath(rect);
    }
    final half = math.min(rect.width, rect.height) / 2;
    double c(Radius r) => math.min(r.x, half);
    final tl = c(g.radius.topLeft), tr = c(g.radius.topRight), br = c(g.radius.bottomRight), bl = c(g.radius.bottomLeft);
    final l = rect.left, t = rect.top, r = rect.right, b = rect.bottom;
    final p = Path()..moveTo(l + tl, t);
    p.lineTo(r - tr, t);
    if (tr > 0) p.arcToPoint(Offset(r, t + tr), radius: Radius.circular(tr));
    if (g.tail == BubbleTail.right) {
      p
        ..lineTo(r, b - 12)
        ..quadraticBezierTo(r + 1, b - 2, r + 8, b);
    } else {
      p.lineTo(r, b - br);
      if (br > 0) p.arcToPoint(Offset(r - br, b), radius: Radius.circular(br));
    }
    if (g.tail == BubbleTail.left) {
      p
        ..lineTo(l - 8, b)
        ..quadraticBezierTo(l - 1, b - 2, l, b - 12);
    } else {
      p.lineTo(l + bl, b);
      if (bl > 0) p.arcToPoint(Offset(l, b - bl), radius: Radius.circular(bl));
    }
    p.lineTo(l, t + tl);
    if (tl > 0) p.arcToPoint(Offset(l + tl, t), radius: Radius.circular(tl));
    return p..close();
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width <= 0) return;
    canvas.drawPath(getOuterPath(rect, textDirection: textDirection), side.toPaint());
  }

  @override
  bool operator ==(Object other) =>
      other is ChatBubbleBorder &&
      other.side == side &&
      other.geometry.radius == geometry.radius &&
      other.geometry.tail == geometry.tail &&
      other.geometry.continuous == geometry.continuous;

  @override
  int get hashCode => Object.hash(side, geometry.radius, geometry.tail, geometry.continuous);
}

/// One side's look, resolved to colours.
class BubbleSideLook {
  BubbleSideLook(ChatLook l, ThemeChatBubbleSide s)
      : color = s.color == null ? null : l.ink(s.color!),
        colorTo = s.colorTo == null ? null : l.ink(s.colorTo!),
        text = l.ink(s.text),
        textMuted = l.ink(s.textMuted),
        border = s.border == null ? null : l.ink(s.border!),
        bare = s.bare,
        link = l.ink(s.link);

  final Color? color;
  final Color? colorTo;
  final Color text;
  final Color textMuted;
  final Color? border;
  final bool bare;
  final Color link;
}

/// THE BUBBLE ITSELF around [child]: its fill (a colour, a gradient top →
/// bottom, or none), outline (`max(1, borderWidth)`), shadow, corners and
/// tail — glass on an agent bubble with a fill. A bare side is no box at all.
Widget chatBubbleBox(
  ChatLook l, {
  required bool user,
  required ChatGroupPosition position,
  required TextDirection direction,
  required Widget child,
  Key? key,
  EdgeInsetsGeometry? padding,
}) {
  final b = l.chat.bubbles;
  final side = BubbleSideLook(l, user ? b.user : b.agent);
  final d = l.chat.density;
  if (side.bare) {
    return Container(key: key, padding: const EdgeInsets.all(2), child: child);
  }
  final geometry = BubbleGeometry.of(
      shape: b.shape, radius: b.radius, tight: b.tightRadius, position: position, user: user, direction: direction);
  final glass = !user && side.color != null ? l.chat.glass : null;
  Color? fill = side.color;
  Gradient? gradient;
  if (side.colorTo != null && fill != null) {
    gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[glass == null ? fill : fade(fill, glass.opacity), glass == null ? side.colorTo! : fade(side.colorTo!, glass.opacity)],
    );
    fill = null;
  } else if (fill != null && glass != null) {
    fill = fade(fill, glass.opacity);
  }
  final outline = side.border == null ? null : BorderSide(color: side.border!, width: math.max(1, l.borderWidth));
  final shadows = shadowsOf(b.shadow);
  final pad = padding ?? EdgeInsets.symmetric(horizontal: d.padX, vertical: d.padY);
  final Decoration decoration;
  CustomClipper<Path>? clip;
  if (geometry.continuous || geometry.tail != BubbleTail.none) {
    final shape = ChatBubbleBorder(geometry: geometry, side: outline ?? BorderSide.none);
    decoration = ShapeDecoration(color: fill, gradient: gradient, shape: shape, shadows: shadows);
    clip = _ShapeClip(shape);
  } else {
    decoration = BoxDecoration(
      color: fill,
      gradient: gradient,
      border: outline == null ? null : Border.fromBorderSide(outline),
      borderRadius: geometry.radius,
      boxShadow: shadows.isEmpty ? null : shadows,
    );
  }
  Widget box = Container(key: key, padding: pad, decoration: decoration, child: child);
  if (glass != null && glass.blur > 0) {
    final filter = ui.ImageFilter.blur(sigmaX: glass.blur, sigmaY: glass.blur);
    box = clip != null
        ? ClipPath(clipper: clip, child: BackdropFilter(filter: filter, child: box))
        : ClipRRect(borderRadius: geometry.radius, child: BackdropFilter(filter: filter, child: box));
  }
  return box;
}

class _ShapeClip extends CustomClipper<Path> {
  _ShapeClip(this.shape);
  final ShapeBorder shape;

  @override
  Path getClip(Size size) => shape.getOuterPath(Offset.zero & size);

  @override
  bool shouldReclip(_ShapeClip old) => old.shape != shape;
}

// ── the words ────────────────────────────────────────────────────────────────

/// THE AGENT'S WORDS, FORMATTED ([ChatMarkdown]): paragraphs 6 apart, bold at
/// `weights.strong`, italic, code in the platform's monospace on a quiet
/// tint with 4 corners, links in the side's link colour, always underlined —
/// a tap hands them to [onOpenLink] — and bullets and numbers hanging their
/// wrapped lines under the words.
class ChatFormattedWords extends StatefulWidget {
  const ChatFormattedWords({
    super.key,
    required this.blocks,
    required this.style,
    required this.strongStyle,
    required this.ink,
    required this.link,
    required this.codeFill,
    this.onOpenLink,
  });

  final List<ChatBlock> blocks;
  final TextStyle style;
  final TextStyle strongStyle;
  final Color ink;
  final Color link;
  final Color codeFill;
  final ValueChanged<Uri>? onOpenLink;

  @override
  State<ChatFormattedWords> createState() => _ChatFormattedWordsState();
}

class _ChatFormattedWordsState extends State<ChatFormattedWords> {
  final List<TapGestureRecognizer> _taps = <TapGestureRecognizer>[];

  void _clear() {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  InlineSpan _span(ChatSpan s) {
    var style = (s.bold ? widget.strongStyle : widget.style).copyWith(color: widget.ink);
    if (s.italic) style = style.copyWith(fontStyle: FontStyle.italic);
    if (s.code) {
      final size = (widget.style.fontSize ?? 15) - 1;
      return WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(color: widget.codeFill, borderRadius: BorderRadius.circular(4)),
          child: Text(
            s.text,
            style: style.copyWith(
              fontFamily: WindowChrome.monospace,
              fontFamilyFallback: WindowChrome.monospaceFallback,
              fontSize: size,
              height: 1.3,
            ),
          ),
        ),
      );
    }
    final link = s.link;
    if (link != null) {
      final uri = Uri.tryParse(link);
      final open = widget.onOpenLink;
      TapGestureRecognizer? tap;
      if (uri != null && open != null) {
        tap = TapGestureRecognizer()..onTap = () => open(uri);
        _taps.add(tap);
      }
      return TextSpan(
        text: s.text,
        style: style.copyWith(color: widget.link, decoration: TextDecoration.underline, decorationColor: widget.link),
        recognizer: tap,
      );
    }
    return TextSpan(text: s.text, style: style);
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    final rows = <Widget>[];
    for (var i = 0; i < widget.blocks.length; i++) {
      final b = widget.blocks[i];
      if (i > 0) rows.add(const SizedBox(height: 6));
      final words = Text.rich(TextSpan(children: <InlineSpan>[for (final s in b.spans) _span(s)]),
          style: widget.style.copyWith(color: widget.ink));
      if (b.kind == ChatBlockKind.paragraph) {
        rows.add(words);
        continue;
      }
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(b.kind == ChatBlockKind.bullet ? '•' : '${b.n}.', style: widget.style.copyWith(color: widget.ink)),
          const SizedBox(width: 8),
          Flexible(child: words),
        ],
      ));
    }
    if (rows.length == 1) return rows.single;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}

/// A REPLY STILL ARRIVING, REVEALED SMOOTHLY ([ChatReveal]): every frame a
/// little more of [text], formatted as it goes (`live`); when the turn ends
/// the rest at the same pace, then the whole. [animate] false — no motion in
/// the design, or the OS asked for less — draws it as it arrives.
class ChatRevealWords extends StatefulWidget {
  const ChatRevealWords({super.key, required this.text, required this.live, required this.animate, required this.builder});

  final String text;
  final bool live;
  final bool animate;

  /// The words to draw: [visible] of them, still arriving or whole.
  final Widget Function(String visible, bool arriving) builder;

  @override
  State<ChatRevealWords> createState() => _ChatRevealWordsState();
}

class _ChatRevealWordsState extends State<ChatRevealWords> with SingleTickerProviderStateMixin {
  late int _shown = widget.live && widget.animate ? 0 : widget.text.length;
  Ticker? _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(ChatRevealWords old) {
    super.didUpdateWidget(old);
    if (!widget.animate) _shown = widget.text.length;
    if (_shown > widget.text.length) _shown = widget.text.length;
    _sync();
  }

  void _sync() {
    final behind = widget.animate && _shown < widget.text.length;
    if (behind) {
      _ticker ??= createTicker(_tick);
      if (!_ticker!.isActive) {
        _last = Duration.zero;
        _ticker!.start();
      }
    } else if (_ticker?.isActive ?? false) {
      _ticker!.stop();
    }
  }

  void _tick(Duration elapsed) {
    final step = elapsed - _last;
    _last = elapsed;
    final next = ChatReveal.length(_shown, widget.text.length, step.inMicroseconds / 1000);
    if (next != _shown) setState(() => _shown = next);
    if (_shown >= widget.text.length) _ticker?.stop();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final whole = _shown >= widget.text.length;
    if (whole && !widget.live) return widget.builder(widget.text, false);
    return widget.builder(ChatReveal.slice(widget.text, _shown), true);
  }
}

// ── one message ──────────────────────────────────────────────────────────────

/// Where a user's message is, as the window draws it.
enum ChatMessageStatus { sent, waiting, failed }

/// ONE MESSAGE ROW: the bubble on its speaker's side, at most
/// `bubbles.maxWidth` of the thread, its time (below or inside) and delivery
/// mark, and a status line for a message waiting or not sent. One element to
/// a screen reader — "{name}: {words}", the time, the status — with Copy (and
/// each link) as actions; a long press copies the plain words.
class ChatMessageRow extends StatelessWidget {
  const ChatMessageRow({
    super.key,
    required this.look,
    required this.user,
    required this.text,
    required this.speaker,
    required this.position,
    this.bubbleKey,
    this.live = false,
    this.animate = false,
    this.blocks,
    this.time,
    this.status = ChatMessageStatus.sent,
    this.onRetry,
    this.onCopy,
    this.onOpenLink,
  });

  final ChatLook look;
  final bool user;
  final String text;

  /// "You", or the agent's name.
  final String speaker;
  final ChatGroupPosition position;
  final Key? bubbleKey;

  /// Still arriving.
  final bool live;

  /// Reveal it smoothly while it arrives.
  final bool animate;

  /// The agent's words formatted (non-live, parsed once by the window); null parses here.
  final List<ChatBlock>? blocks;

  /// The time to draw ("9:41 PM"), or null for none.
  final String? time;
  final ChatMessageStatus status;
  final VoidCallback? onRetry;

  /// A long press, or the screen reader's Copy: the plain words.
  final ValueChanged<String>? onCopy;
  final ValueChanged<Uri>? onOpenLink;

  static const String waitingWords = 'Waiting for connection…';
  static const String failedWords = 'Not sent · Tap to retry';

  List<ChatBlock> _blocks(String words, {bool live = false}) =>
      !live && words == text && blocks != null ? blocks! : ChatMarkdown.parse(words, live: live);

  @override
  Widget build(BuildContext context) {
    final l = look;
    final k = l.chat;
    final direction = Directionality.of(context);
    final side = BubbleSideLook(l, user ? k.bubbles.user : k.bubbles.agent);
    final style = l.bodyStyle;
    final timeInside = time != null && k.timestamps.style == 'inside' && !side.bare;
    final plain = user ? text : ChatMarkdown.plain(_blocks(text));

    Widget words(String visible, bool arriving) {
      if (user) return Text(visible, style: style.copyWith(color: side.text));
      final fill = side.color ?? l.ink(k.wallpaper.color);
      return ChatFormattedWords(
        blocks: _blocks(visible, live: arriving),
        style: style,
        strongStyle: l.bodyStrongStyle,
        ink: side.text,
        link: side.link,
        codeFill: Color.lerp(fill, side.text, 0.1)!,
        onOpenLink: onOpenLink,
      );
    }

    Widget content = user
        ? words(text, false)
        : ChatRevealWords(text: text, live: live, animate: animate, builder: words);
    if (timeInside) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Align(alignment: AlignmentDirectional.centerStart, widthFactor: 1, child: content),
          const SizedBox(height: 2),
          _timeLine(l, time!, side.textMuted),
        ],
      );
    }
    // Still arriving, or typed while offline and not sent yet: provisional.
    content = Opacity(opacity: status == ChatMessageStatus.waiting ? 0.6 : (live ? 0.75 : 1), child: content);
    final bubble = chatBubbleBox(l, user: user, position: position, direction: direction, key: bubbleKey, child: content);
    final align = user ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart;
    final children = <Widget>[
      FractionallySizedBox(widthFactor: k.bubbles.maxWidth, alignment: align, child: Align(alignment: align, child: bubble)),
      if (time != null && !timeInside)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Align(alignment: align, child: _timeLine(l, time!, l.ink(k.wallpaper.textMuted))),
        ),
      if (user && status == ChatMessageStatus.waiting)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Align(alignment: align, child: Text(waitingWords, style: l.captionStyle.copyWith(color: l.ink(k.wallpaper.textMuted)))),
        ),
      if (user && status == ChatMessageStatus.failed)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Align(
            alignment: align,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRetry,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SdkIconView('alert', color: l.danger, size: 14, style: l.iconStyle, stroke: l.iconStroke),
                  const SizedBox(width: 4),
                  Flexible(child: Text(failedWords, style: l.captionStrongStyle.copyWith(color: l.danger))),
                ],
              ),
            ),
          ),
        ),
    ];
    final links = user ? const <ChatSpan>[] : <ChatSpan>[
      for (final b in _blocks(text))
        for (final s in b.spans)
          if (s.link != null) s,
    ];
    final label = StringBuffer('$speaker: $plain');
    if (time != null) label.write(', $time');
    if (user && status == ChatMessageStatus.waiting) label.write(', waiting to send');
    if (user && status == ChatMessageStatus.failed) label.write(', not sent. Double-tap to retry.');
    final copy = onCopy;
    final open = onOpenLink;
    return Semantics(
      container: true,
      label: label.toString(),
      onTap: user && status == ChatMessageStatus.failed ? onRetry : null,
      customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
        if (copy != null) const CustomSemanticsAction(label: 'Copy'): () => copy(plain),
        if (open != null)
          for (final s in links.take(3))
            if (Uri.tryParse(s.link!) != null) CustomSemanticsAction(label: 'Open link: ${s.text}'): () => open(Uri.parse(s.link!)),
      },
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onLongPress: copy == null ? null : () => copy(plain),
        onTap: user && status == ChatMessageStatus.failed ? onRetry : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  /// The time, and beside a user's time (`timestamps.ticks`) its mark: a
  /// clock while it waits, a check once sent, an alert in `danger` if it was not.
  Widget _timeLine(ChatLook l, String clock, Color color) {
    final ticks = user && l.chat.timestamps.ticks;
    final timeStyle = l.timeStyle.copyWith(color: color);
    if (!ticks) return Text(clock, style: timeStyle);
    final (icon, tint) = switch (status) {
      ChatMessageStatus.waiting => ('clock', color),
      ChatMessageStatus.failed => ('alert', l.danger),
      ChatMessageStatus.sent => ('check', color),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(child: Text(clock, style: timeStyle)),
        const SizedBox(width: 4),
        SdkIconView(icon, color: tint, size: 12, style: l.iconStyle, stroke: l.iconStroke),
      ],
    );
  }
}
