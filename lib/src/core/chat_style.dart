part of 'design.dart';

/// THE CHAT WINDOW, PIECE BY PIECE (contract/DESIGN.md, "Chat window v2") —
/// the header, the bubbles, the times, the wallpaper, the chips, the cards,
/// the composer, the typing indicator, the density, the welcome, the rating
/// and the call button, each set in the dashboard and delivered resolved in
/// the token set's `chat` group beside the v1 tokens.
///
/// NOTHING IS TRUSTED, as everywhere in the design: a group the server did
/// not send is CLASSIC — the chat exactly as it was drawn before these
/// tokens, derived from the v1 tokens ([ChatClassic]); a field missing or
/// of the wrong type is that field's classic value; a word this build does
/// not know is the first word listed for it ([ChatWords]).

/// The words each v2 token may take. The first of each is what a word this
/// build does not know is drawn as.
abstract final class ChatWords {
  static const List<String> headerStyles = <String>['surface', 'accent', 'gradient', 'plain'];
  static const List<String> headerAligns = <String>['start', 'center'];
  static const List<String> statusLines = <String>['online', 'text', 'none'];
  static const List<String> contextCards = <String>['bar', 'card', 'none'];
  static const List<String> bubbleShapes = <String>['rounded', 'squircle', 'tail', 'flat'];
  static const List<String> timestampShows = <String>['never', 'group', 'always'];
  static const List<String> timestampStyles = <String>['below', 'inside'];
  static const List<String> wallpaperStyles = <String>['solid', 'gradient', 'pattern'];

  /// A pattern this build does not know is drawn as dots; `none` is no pattern.
  static const List<String> patterns = <String>['dots', 'grid', 'diagonal', 'none'];
  static const List<String> chipStyles = <String>['outline', 'filled', 'soft', 'elevated'];
  static const List<String> chipPlacements = <String>['both', 'inline', 'above-composer'];
  static const List<String> chipScrolls = <String>['wrap', 'row'];
  static const List<String> cardImages = <String>['auto', 'square', 'landscape', 'wide'];
  static const List<String> cardButtons = <String>['filled', 'outline', 'tonal', 'text'];
  static const List<String> composerStyles = <String>['bar', 'floating', 'pill'];
  static const List<String> sendStyles = <String>['circle', 'rounded', 'icon'];
  static const List<String> typingStyles = <String>['loader', 'dots', 'wave', 'text'];
  static const List<String> densities = <String>['comfortable', 'compact', 'spacious'];
  static const List<String> welcomeLayouts = <String>['centered', 'card', 'hero', 'minimal'];
  static const List<String> starterLooks = <String>['chips', 'list'];
  static const List<String> ratingStyles = <String>['thumbs', 'stars', 'emoji'];
  static const List<String> callButtons = <String>['none', 'header', 'composer'];

  /// The keys of the v2 groups inside `chat`: one of them present is a v2 server.
  static const List<String> groups = <String>[
    'preset', 'header', 'bubbles', 'timestamps', 'wallpaper', 'chips', 'cards', 'composer', 'typing', 'density',
    'welcome', 'rating', 'escalation', 'glass',
  ];

  /// What the `text` typing style and the header's typing status say when the brand wrote nothing.
  static const String defaultTyping = 'Typing…';
}

// ── reading one field: absent or the wrong type is the classic value ─────────

String _hexField(Map<String, Object?> r, String key, String classic) => Design.normaliseHex(r[key]) ?? classic;

/// A colour that may be null ("none"): present and null is the design's
/// word; absent, or something that is not a colour, is the classic value.
String? _hexOrNone(Map<String, Object?> r, String key, String? classic) {
  if (!r.containsKey(key)) return classic;
  final v = r[key];
  if (v == null) return null;
  return Design.normaliseHex(v) ?? classic;
}

/// A word: not a string is the classic value; a string this build does not know is the first word listed.
String _wordField(Map<String, Object?> r, String key, List<String> allowed, String classic) {
  final v = r[key];
  if (v is! String) return classic;
  final s = v.trim().toLowerCase();
  return allowed.contains(s) ? s : allowed.first;
}

bool _boolField(Map<String, Object?> r, String key, bool classic) {
  final v = r[key];
  return v is bool ? v : classic;
}

double _numField(Map<String, Object?> r, String key, double classic, {double? min, double? max}) =>
    Js.finite(r[key]) == null ? classic : _num(r[key], classic, min: min, max: max);

String _wordsField(Map<String, Object?> r, String key, String classic) {
  final v = r[key];
  return v is String ? v : classic;
}

/// A shadow that may be null: present and null is none; absent, or not a shadow, the classic one.
ThemeShadow? _shadowField(Map<String, Object?> r, String key, ThemeShadow? classic) {
  if (!r.containsKey(key)) return classic;
  final v = r[key];
  if (v == null) return null;
  return ThemeShadow.fromJson(v) ?? classic;
}

// ── the groups ───────────────────────────────────────────────────────────────

/// A fill — one colour, or a gradient — and the text that reads on all of it.
class ThemeChatFill {
  const ThemeChatFill({required this.color, this.colorTo, required this.text, required this.textMuted});

  final String color;

  /// The gradient's far end; null for one solid colour.
  final String? colorTo;
  final String text;

  /// Quieter text on it: a status line, a time inside a bubble.
  final String textMuted;

  static ThemeChatFill fromJson(Object? raw, ThemeChatFill d) {
    final r = Js.asMap(raw);
    if (r == null) return d;
    return ThemeChatFill(
      color: _hexField(r, 'color', d.color),
      colorTo: _hexOrNone(r, 'colorTo', d.colorTo),
      text: _hexField(r, 'text', d.text),
      textMuted: _hexField(r, 'textMuted', d.textMuted),
    );
  }

  Map<String, Object?> toJson() =>
      <String, Object?>{'color': color, 'colorTo': colorTo, 'text': text, 'textMuted': textMuted};
}

/// `chat.header`: its fill, alignment, status line and context card.
class ThemeChatHeader {
  const ThemeChatHeader({
    required this.style,
    this.align = 'start',
    this.status = 'online',
    this.typingStatus = false,
    this.contextCard = 'bar',
    required this.fill,
    required this.dot,
    this.divider = true,
  });

  /// `surface`, `accent`, `gradient` (leading → trailing) or `plain` (no fill: the wallpaper runs under it).
  final String style;

  /// `start` or `center`.
  final String align;

  /// `online` (the dot and the words), `text` (the words) or `none`.
  final String status;

  /// While the reply is coming, the status line says so.
  final bool typingStatus;

  /// Where the card the app pins is drawn: `bar`, `card` or `none`.
  final String contextCard;
  final ThemeChatFill fill;

  /// The online dot.
  final String dot;

  /// A hairline in `colors.border` under it.
  final bool divider;

  static ThemeChatHeader fromJson(Object? raw, ThemeChatHeader d) {
    final r = Js.asMap(raw);
    if (r == null) return d;
    return ThemeChatHeader(
      style: _wordField(r, 'style', ChatWords.headerStyles, d.style),
      align: _wordField(r, 'align', ChatWords.headerAligns, d.align),
      status: _wordField(r, 'status', ChatWords.statusLines, d.status),
      typingStatus: _boolField(r, 'typingStatus', d.typingStatus),
      contextCard: _wordField(r, 'contextCard', ChatWords.contextCards, d.contextCard),
      fill: ThemeChatFill.fromJson(r['fill'], d.fill),
      dot: _hexField(r, 'dot', d.dot),
      divider: _boolField(r, 'divider', d.divider),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'style': style,
        'align': align,
        'status': status,
        'typingStatus': typingStatus,
        'contextCard': contextCard,
        'fill': fill.toJson(),
        'dot': dot,
        'divider': divider,
      };
}

/// One side's bubbles.
class ThemeChatBubbleSide {
  const ThemeChatBubbleSide({
    this.color,
    this.colorTo,
    required this.text,
    required this.textMuted,
    this.border,
    this.bare = false,
    required this.link,
  });

  /// The fill; null is transparent.
  final String? color;

  /// A gradient's far end, top → bottom; null is solid.
  final String? colorTo;
  final String text;

  /// A time or a mark inside the bubble.
  final String textMuted;

  /// An outline; null is none.
  final String? border;

  /// No bubble at all: the words on the wallpaper.
  final bool bare;

  /// Links in the words, always underlined.
  final String link;

  static ThemeChatBubbleSide fromJson(Object? raw, ThemeChatBubbleSide d) {
    final r = Js.asMap(raw);
    if (r == null) return d;
    return ThemeChatBubbleSide(
      color: _hexOrNone(r, 'color', d.color),
      colorTo: _hexOrNone(r, 'colorTo', d.colorTo),
      text: _hexField(r, 'text', d.text),
      textMuted: _hexField(r, 'textMuted', d.textMuted),
      border: _hexOrNone(r, 'border', d.border),
      bare: _boolField(r, 'bare', d.bare),
      link: _hexField(r, 'link', d.link),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'color': color,
        'colorTo': colorTo,
        'text': text,
        'textMuted': textMuted,
        'border': border,
        'bare': bare,
        'link': link,
      };
}

/// `chat.bubbles`: shape, corners, grouping, width, shadow and each side's look.
class ThemeChatBubbles {
  const ThemeChatBubbles({
    this.shape = 'rounded',
    required this.radius,
    required this.tightRadius,
    this.grouping = false,
    this.maxWidth = 0.84,
    this.shadow,
    required this.user,
    required this.agent,
  });

  /// `rounded`, `squircle`, `tail` or `flat`.
  final String shape;
  final double radius;

  /// The corner nearest the speaker (`rounded`), and a group's inner corners.
  final double tightRadius;
  final bool grouping;

  /// The widest a bubble may be, as a share of the thread's width: 0.6–0.92.
  final double maxWidth;
  final ThemeShadow? shadow;
  final ThemeChatBubbleSide user;
  final ThemeChatBubbleSide agent;

  static ThemeChatBubbles fromJson(Object? raw, ThemeChatBubbles d) {
    final r = Js.asMap(raw);
    if (r == null) return d;
    return ThemeChatBubbles(
      shape: _wordField(r, 'shape', ChatWords.bubbleShapes, d.shape),
      radius: _numField(r, 'radius', d.radius, min: 0),
      tightRadius: _numField(r, 'tightRadius', d.tightRadius, min: 0),
      grouping: _boolField(r, 'grouping', d.grouping),
      maxWidth: _numField(r, 'maxWidth', d.maxWidth, min: 0.6, max: 0.92),
      shadow: _shadowField(r, 'shadow', d.shadow),
      user: ThemeChatBubbleSide.fromJson(r['user'], d.user),
      agent: ThemeChatBubbleSide.fromJson(r['agent'], d.agent),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'shape': shape,
        'radius': radius,
        'tightRadius': tightRadius,
        'grouping': grouping,
        'maxWidth': maxWidth,
        'shadow': shadow?.toJson(),
        'user': user.toJson(),
        'agent': agent.toJson(),
      };
}

/// `chat.timestamps`: whose time is drawn, where, and the delivery marks.
class ThemeChatTimestamps {
  const ThemeChatTimestamps({this.show = 'never', this.style = 'below', this.ticks = false});

  /// `never`, `group` (the last of each group) or `always`.
  final String show;

  /// `below` the bubble, or `inside` it.
  final String style;

  /// A waiting / sent / not-sent mark beside the customer's times.
  final bool ticks;

  static ThemeChatTimestamps fromJson(Object? raw, ThemeChatTimestamps d) {
    final r = Js.asMap(raw);
    if (r == null) return d;
    return ThemeChatTimestamps(
      show: _wordField(r, 'show', ChatWords.timestampShows, d.show),
      style: _wordField(r, 'style', ChatWords.timestampStyles, d.style),
      ticks: _boolField(r, 'ticks', d.ticks),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{'show': show, 'style': style, 'ticks': ticks};
}

/// `chat.wallpaper`: what is behind the thread.
class ThemeChatWallpaper {
  const ThemeChatWallpaper({
    this.style = 'solid',
    required this.color,
    this.colorTo,
    this.pattern = 'none',
    required this.patternColor,
    this.intensity = 0.5,
    required this.text,
    required this.textMuted,
  });

  /// `solid`, `gradient` (top → bottom) or `pattern`.
  final String style;

  /// The base, or the gradient's top.
  final String color;

  /// The gradient's bottom; null unless `gradient`.
  final String? colorTo;

  /// `none`, `dots`, `grid` or `diagonal`.
  final String pattern;
  final String patternColor;
  final double intensity;

  /// Words on the wallpaper itself: a bare bubble, the welcome's title.
  final String text;

  /// Day separators, times under bubbles, the typing words.
  final String textMuted;

  static ThemeChatWallpaper fromJson(Object? raw, ThemeChatWallpaper d) {
    final r = Js.asMap(raw);
    if (r == null) return d;
    return ThemeChatWallpaper(
      style: _wordField(r, 'style', ChatWords.wallpaperStyles, d.style),
      color: _hexField(r, 'color', d.color),
      colorTo: _hexOrNone(r, 'colorTo', d.colorTo),
      pattern: _wordField(r, 'pattern', ChatWords.patterns, d.pattern),
      patternColor: _hexField(r, 'patternColor', d.patternColor),
      intensity: _numField(r, 'intensity', d.intensity, min: 0, max: 1),
      text: _hexField(r, 'text', d.text),
      textMuted: _hexField(r, 'textMuted', d.textMuted),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'style': style,
        'color': color,
        'colorTo': colorTo,
        'pattern': pattern,
        'patternColor': patternColor,
        'intensity': intensity,
        'text': text,
        'textMuted': textMuted,
      };
}

/// `chat.chips`: the brand's starters and the agent's quick replies, one look.
class ThemeChatChips {
  const ThemeChatChips({
    this.style = 'outline',
    this.placement = 'both',
    this.scroll = 'wrap',
    this.height = 34,
    required this.radius,
    required this.fill,
    required this.text,
    this.border,
    this.borderWidth = 1,
    this.shadow,
  });

  /// `outline`, `filled`, `soft` or `elevated`.
  final String style;

  /// `both` (starters docked, replies in the thread), `inline` or `above-composer`.
  final String placement;

  /// `wrap` or `row` (one row that scrolls sideways).
  final String scroll;
  final double height;
  final double radius;
  final String fill;
  final String text;

  /// The outline; null is none.
  final String? border;
  final double borderWidth;
  final ThemeShadow? shadow;

  static ThemeChatChips fromJson(Object? raw, ThemeChatChips d) {
    final r = Js.asMap(raw);
    if (r == null) return d;
    return ThemeChatChips(
      style: _wordField(r, 'style', ChatWords.chipStyles, d.style),
      placement: _wordField(r, 'placement', ChatWords.chipPlacements, d.placement),
      scroll: _wordField(r, 'scroll', ChatWords.chipScrolls, d.scroll),
      height: _numField(r, 'height', d.height, min: 1),
      radius: _numField(r, 'radius', d.radius, min: 0),
      fill: _hexField(r, 'fill', d.fill),
      text: _hexField(r, 'text', d.text),
      border: _hexOrNone(r, 'border', d.border),
      borderWidth: _numField(r, 'borderWidth', d.borderWidth, min: 0),
      shadow: _shadowField(r, 'shadow', d.shadow),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'style': style,
        'placement': placement,
        'scroll': scroll,
        'height': height,
        'radius': radius,
        'fill': fill,
        'text': text,
        'border': border,
        'borderWidth': borderWidth,
        'shadow': shadow?.toJson(),
      };
}

/// `chat.cards`: the agent's components, the upcoming-calls card, a context card and the rating card.
class ThemeChatCards {
  const ThemeChatCards({
    required this.radius,
    this.shadow,
    this.hard = false,
    this.border = true,
    this.image = 'auto',
    this.button = 'filled',
    this.buttonFill,
    required this.buttonText,
    this.buttonBorder,
  });

  final double radius;
  final ThemeShadow? shadow;

  /// The design's hard offset (`elevation.hardOffset`) instead of a shadow.
  final bool hard;
  final bool border;

  /// A component's large image: `auto`, `square`, `landscape` or `wide`.
  final String image;

  /// A component's main button: `filled`, `outline`, `tonal` or `text`.
  final String button;

  /// Null: no fill.
  final String? buttonFill;
  final String buttonText;
  final String? buttonBorder;

  static ThemeChatCards fromJson(Object? raw, ThemeChatCards d) {
    final r = Js.asMap(raw);
    if (r == null) return d;
    return ThemeChatCards(
      radius: _numField(r, 'radius', d.radius, min: 0),
      shadow: _shadowField(r, 'shadow', d.shadow),
      hard: _boolField(r, 'hard', d.hard),
      border: _boolField(r, 'border', d.border),
      image: _wordField(r, 'image', ChatWords.cardImages, d.image),
      button: _wordField(r, 'button', ChatWords.cardButtons, d.button),
      buttonFill: _hexOrNone(r, 'buttonFill', d.buttonFill),
      buttonText: _hexField(r, 'buttonText', d.buttonText),
      buttonBorder: _hexOrNone(r, 'buttonBorder', d.buttonBorder),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'radius': radius,
        'shadow': shadow?.toJson(),
        'hard': hard,
        'border': border,
        'image': image,
        'button': button,
        'buttonFill': buttonFill,
        'buttonText': buttonText,
        'buttonBorder': buttonBorder,
      };
}

/// `chat.composer`: the field, its buttons, and what is behind them.
class ThemeChatComposer {
  const ThemeChatComposer({
    this.style = 'bar',
    this.mic = false,
    this.attach = false,
    this.send = 'circle',
    required this.fill,
    required this.text,
    required this.placeholder,
    required this.border,
    this.strip,
    this.shadow,
    this.height = 40,
    required this.radius,
    this.sendFill,
    required this.sendIcon,
    required this.icon,
  });

  /// `bar`, `floating` or `pill`.
  final String style;

  /// A microphone while the field is empty — it calls the agent (where the agent takes calls).
  final bool mic;

  /// A paperclip — only where the app handles attachments.
  final bool attach;

  /// `circle`, `rounded` or `icon`.
  final String send;

  /// The field.
  final String fill;
  final String text;
  final String placeholder;
  final String border;

  /// The strip behind the field; null — the thread shows through (`floating`).
  final String? strip;
  final ThemeShadow? shadow;

  /// The field's height and corners.
  final double height;
  final double radius;

  /// The send button's fill; null — none (`icon`).
  final String? sendFill;
  final String sendIcon;

  /// The paperclip and the call button.
  final String icon;

  static ThemeChatComposer fromJson(Object? raw, ThemeChatComposer d) {
    final r = Js.asMap(raw);
    if (r == null) return d;
    return ThemeChatComposer(
      style: _wordField(r, 'style', ChatWords.composerStyles, d.style),
      mic: _boolField(r, 'mic', d.mic),
      attach: _boolField(r, 'attach', d.attach),
      send: _wordField(r, 'send', ChatWords.sendStyles, d.send),
      fill: _hexField(r, 'fill', d.fill),
      text: _hexField(r, 'text', d.text),
      placeholder: _hexField(r, 'placeholder', d.placeholder),
      border: _hexField(r, 'border', d.border),
      strip: _hexOrNone(r, 'strip', d.strip),
      shadow: _shadowField(r, 'shadow', d.shadow),
      height: _numField(r, 'height', d.height, min: 1),
      radius: _numField(r, 'radius', d.radius, min: 0),
      sendFill: _hexOrNone(r, 'sendFill', d.sendFill),
      sendIcon: _hexField(r, 'sendIcon', d.sendIcon),
      icon: _hexField(r, 'icon', d.icon),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'style': style,
        'mic': mic,
        'attach': attach,
        'send': send,
        'fill': fill,
        'text': text,
        'placeholder': placeholder,
        'border': border,
        'strip': strip,
        'shadow': shadow?.toJson(),
        'height': height,
        'radius': radius,
        'sendFill': sendFill,
        'sendIcon': sendIcon,
        'icon': icon,
      };
}

/// `chat.typing`: while the reply is coming.
class ThemeChatTyping {
  const ThemeChatTyping({this.style = 'loader', this.text = '', required this.color});

  /// `loader` (the design's loader), `dots`, `wave` or `text`.
  final String style;

  /// "" is "Typing…".
  final String text;
  final String color;

  /// The words the `text` style and the header's typing status say.
  String get words => text.trim().isEmpty ? ChatWords.defaultTyping : text;

  static ThemeChatTyping fromJson(Object? raw, ThemeChatTyping d) {
    final r = Js.asMap(raw);
    if (r == null) return d;
    return ThemeChatTyping(
      style: _wordField(r, 'style', ChatWords.typingStyles, d.style),
      text: _wordsField(r, 'text', d.text),
      color: _hexField(r, 'color', d.color),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{'style': style, 'text': text, 'color': color};
}

/// `chat.density`: the gaps and paddings of the thread.
class ThemeChatDensity {
  const ThemeChatDensity({
    this.name = 'comfortable',
    required this.gap,
    required this.groupGap,
    required this.padX,
    required this.padY,
    this.edge = 12,
  });

  /// `comfortable`, `compact` or `spacious`.
  final String name;

  /// Between rows, and between two messages of one group.
  final double gap;
  final double groupGap;

  /// Inside a bubble.
  final double padX;
  final double padY;

  /// The thread's side margins.
  final double edge;

  static ThemeChatDensity fromJson(Object? raw, ThemeChatDensity d) {
    final r = Js.asMap(raw);
    if (r == null) return d;
    return ThemeChatDensity(
      name: _wordField(r, 'name', ChatWords.densities, d.name),
      gap: _numField(r, 'gap', d.gap, min: 0),
      groupGap: _numField(r, 'groupGap', d.groupGap, min: 0),
      padX: _numField(r, 'padX', d.padX, min: 0),
      padY: _numField(r, 'padY', d.padY, min: 0),
      edge: _numField(r, 'edge', d.edge, min: 0),
    );
  }

  Map<String, Object?> toJson() =>
      <String, Object?>{'name': name, 'gap': gap, 'groupGap': groupGap, 'padX': padX, 'padY': padY, 'edge': edge};
}

/// `chat.welcome`: what a new conversation opens with.
class ThemeChatWelcome {
  const ThemeChatWelcome({this.layout = 'centered', this.starters = 'chips'});

  /// `centered`, `card`, `hero` or `minimal`.
  final String layout;

  /// `chips` or `list`.
  final String starters;

  static ThemeChatWelcome fromJson(Object? raw, ThemeChatWelcome d) {
    final r = Js.asMap(raw);
    if (r == null) return d;
    return ThemeChatWelcome(
      layout: _wordField(r, 'layout', ChatWords.welcomeLayouts, d.layout),
      starters: _wordField(r, 'starters', ChatWords.starterLooks, d.starters),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{'layout': layout, 'starters': starters};
}

/// `chat.rating`: the question asked after the agent ends the conversation.
class ThemeChatRating {
  const ThemeChatRating({this.show = false, this.style = 'thumbs', this.prompt = ''});

  final bool show;

  /// `thumbs`, `stars` or `emoji`.
  final String style;

  /// "" is "How was this chat?".
  final String prompt;

  static ThemeChatRating fromJson(Object? raw, ThemeChatRating d) {
    final r = Js.asMap(raw);
    if (r == null) return d;
    return ThemeChatRating(
      show: _boolField(r, 'show', d.show),
      style: _wordField(r, 'style', ChatWords.ratingStyles, d.style),
      prompt: _wordsField(r, 'prompt', d.prompt),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{'show': show, 'style': style, 'prompt': prompt};
}

/// `chat.escalation`: a button that calls the agent.
class ThemeChatEscalation {
  const ThemeChatEscalation({this.call = 'none'});

  /// `none`, `header` or `composer`.
  final String call;

  static ThemeChatEscalation fromJson(Object? raw, ThemeChatEscalation d) {
    final r = Js.asMap(raw);
    if (r == null) return d;
    return ThemeChatEscalation(call: _wordField(r, 'call', ChatWords.callButtons, d.call));
  }

  Map<String, Object?> toJson() => <String, Object?>{'call': call};
}

/// `chat.glass`: frosted pieces — their colour at [opacity] over the wallpaper blurred by [blur].
class ThemeChatGlass {
  const ThemeChatGlass({this.blur = 20, this.opacity = 0.72});

  final double blur;
  final double opacity;

  /// Null for `null` (solid pieces) and for anything that is not an object.
  static ThemeChatGlass? fromJson(Object? raw) {
    final r = Js.asMap(raw);
    if (r == null) return null;
    return ThemeChatGlass(blur: _num(r['blur'], 20, min: 0, max: 100), opacity: _num(r['opacity'], 0.72, min: 0, max: 1));
  }

  /// The same frosting as the design's own [ThemeGlass] — what the shared surface helper draws.
  ThemeGlass get asGlass => ThemeGlass(blur: blur, surfaceOpacity: opacity);

  Map<String, Object?> toJson() => <String, Object?>{'blur': blur, 'opacity': opacity};
}

/// Every v2 group of one chat, complete.
class ChatStyleGroups {
  const ChatStyleGroups({
    this.preset = 'classic',
    required this.header,
    required this.bubbles,
    required this.timestamps,
    required this.wallpaper,
    required this.chips,
    required this.cards,
    required this.composer,
    required this.typing,
    required this.density,
    required this.welcome,
    required this.rating,
    required this.escalation,
    this.glass,
  });

  final String preset;
  final ThemeChatHeader header;
  final ThemeChatBubbles bubbles;
  final ThemeChatTimestamps timestamps;
  final ThemeChatWallpaper wallpaper;
  final ThemeChatChips chips;
  final ThemeChatCards cards;
  final ThemeChatComposer composer;
  final ThemeChatTyping typing;
  final ThemeChatDensity density;
  final ThemeChatWelcome welcome;
  final ThemeChatRating rating;
  final ThemeChatEscalation escalation;
  final ThemeChatGlass? glass;

  /// The session's groups over [classic], field by field.
  static ChatStyleGroups fromJson(Map<String, Object?> r, ChatStyleGroups classic) {
    final preset = r['preset'];
    return ChatStyleGroups(
      preset: preset is String && preset.trim().isNotEmpty ? preset.trim() : classic.preset,
      header: ThemeChatHeader.fromJson(r['header'], classic.header),
      bubbles: ThemeChatBubbles.fromJson(r['bubbles'], classic.bubbles),
      timestamps: ThemeChatTimestamps.fromJson(r['timestamps'], classic.timestamps),
      wallpaper: ThemeChatWallpaper.fromJson(r['wallpaper'], classic.wallpaper),
      chips: ThemeChatChips.fromJson(r['chips'], classic.chips),
      cards: ThemeChatCards.fromJson(r['cards'], classic.cards),
      composer: ThemeChatComposer.fromJson(r['composer'], classic.composer),
      typing: ThemeChatTyping.fromJson(r['typing'], classic.typing),
      density: ThemeChatDensity.fromJson(r['density'], classic.density),
      welcome: ThemeChatWelcome.fromJson(r['welcome'], classic.welcome),
      rating: ThemeChatRating.fromJson(r['rating'], classic.rating),
      escalation: ThemeChatEscalation.fromJson(r['escalation'], classic.escalation),
      // Present and null is solid; an object is frosted; absent is classic (solid).
      glass: r.containsKey('glass') ? ThemeChatGlass.fromJson(r['glass']) : classic.glass,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'preset': preset,
        'header': header.toJson(),
        'bubbles': bubbles.toJson(),
        'timestamps': timestamps.toJson(),
        'wallpaper': wallpaper.toJson(),
        'chips': chips.toJson(),
        'cards': cards.toJson(),
        'composer': composer.toJson(),
        'typing': typing.toJson(),
        'density': density.toJson(),
        'welcome': welcome.toJson(),
        'rating': rating.toJson(),
        'escalation': escalation.toJson(),
        'glass': glass?.toJson(),
      };
}

/// What classic is derived from beyond the chat's own v1 tokens: the
/// design's colours, corners, outline width, spacing, card depth and v1
/// bubble style.
class ChatClassicBase {
  const ChatClassicBase({
    required this.colors,
    required this.radius,
    required this.borderWidth,
    required this.spacing,
    this.cardShadow,
    this.hard = false,
    this.bubbles = 'filled',
  });

  final ThemeColors colors;
  final ThemeRadius radius;
  final double borderWidth;
  final ThemeSpacing spacing;
  final ThemeShadow? cardShadow;

  /// The design draws a hard offset.
  final bool hard;

  /// `filled`, `outline` or `minimal` — the v1 `bubbles`.
  final String bubbles;

  /// One scheme's tokens' own base.
  factory ChatClassicBase.of(ThemeTokens t) => ChatClassicBase(
        colors: t.colors,
        radius: t.shape.radius,
        borderWidth: t.shape.borderWidth,
        spacing: t.spacing,
        cardShadow: t.elevation.card,
        hard: t.elevation.hardOffset != null,
        bubbles: t.bubbles,
      );

  /// [colors] in Graine Classic's shapes, spacing and depth — for a chat that came with nothing else.
  factory ChatClassicBase.classic(ThemeColors colors, {required bool dark}) {
    final d = dark ? _Fallback.dark : _Fallback.light;
    return ChatClassicBase(
      colors: colors,
      radius: d.shape.radius,
      borderWidth: d.shape.borderWidth,
      spacing: d.spacing,
      cardShadow: d.elevation.card,
      hard: d.elevation.hardOffset != null,
      bubbles: d.bubbles,
    );
  }
}

/// CLASSIC, DERIVED FROM THE v1 TOKENS — the table in contract/DESIGN.md
/// ("Chat window v2" → The tokens), with the same arithmetic the server's
/// resolver uses (theme.ts `resolveChat`), so a session whose design never
/// touched a v2 knob reads back exactly the groups the server would send.
abstract final class ChatClassic {
  static ChatStyleGroups derive(ThemeChat k, ChatClassicBase b) {
    final c = b.colors;
    final r = b.radius;
    final surfaceHeader = Design.normaliseHex(k.headerBackground) == Design.normaliseHex(c.surface);
    ThemeChatBubbleSide side(bool user) {
      String? color;
      String text;
      String? border;
      var bare = false;
      switch (b.bubbles) {
        case 'outline':
          color = null;
          text = c.text;
          border = user ? c.accent : c.border;
        case 'minimal':
          color = user ? c.accentSoft : null;
          text = c.text;
          bare = !user;
        default:
          color = user ? c.userBubble : c.agentBubble;
          text = user ? c.userBubbleText : c.agentBubbleText;
      }
      final under = color ?? k.background;
      // The customer's accent bubble carries its words at the accent's floor, as v1 always has.
      final floor = user && color == c.userBubble ? Design.onAccentMin : 4.5;
      return ThemeChatBubbleSide(
        color: color,
        text: text,
        textMuted: Design.quietOn(text, under, null, floor),
        border: border,
        bare: bare,
        link: Design.contrastRatio(c.accent, under) >= 4.5 ? c.accent : text,
      );
    }

    final gap = Js.round(b.spacing.gap);
    return ChatStyleGroups(
      header: ThemeChatHeader(
        style: surfaceHeader ? 'surface' : 'accent',
        fill: ThemeChatFill(color: k.headerBackground, text: k.headerText, textMuted: k.headerSubtext),
        dot: surfaceHeader ? c.success : k.headerText,
      ),
      bubbles: ThemeChatBubbles(
        radius: r.lg,
        tightRadius: math.min(r.sm, r.lg),
        user: side(true),
        agent: side(false),
      ),
      timestamps: ThemeChatTimestamps(show: k.showTimestamps ? 'always' : 'never'),
      wallpaper: ThemeChatWallpaper(
        style: k.pattern == 'dots' ? 'pattern' : 'solid',
        color: k.background,
        pattern: k.pattern,
        patternColor: k.patternColor,
        text: c.text,
        textMuted: c.textMuted,
      ),
      chips: ThemeChatChips(
        radius: math.min(r.xl, 17),
        fill: k.background,
        text: Design.ensureContrast(c.text, k.background),
        border: c.accent,
        borderWidth: math.max(1, b.borderWidth),
      ),
      cards: ThemeChatCards(
        radius: r.lg,
        shadow: b.cardShadow,
        hard: b.hard,
        buttonFill: c.accent,
        buttonText: c.onAccent,
      ),
      composer: ThemeChatComposer(
        fill: k.composerBackground,
        text: k.composerText,
        placeholder: k.composerPlaceholder,
        border: k.composerBorder,
        strip: k.background,
        radius: r.xl,
        sendFill: c.accent,
        sendIcon: c.onAccent,
        icon: Design.ensureOnBoth(c.accent, k.composerBackground, k.background, Design.onAccentMin),
      ),
      typing: ThemeChatTyping(color: c.accent),
      density: ThemeChatDensity(
        gap: gap,
        groupGap: math.max(2, Js.round(gap * 0.25)),
        padX: Js.round(b.spacing.cardPadding),
        padY: Js.round(b.spacing.cardPadding * 0.75),
      ),
      welcome: const ThemeChatWelcome(),
      rating: const ThemeChatRating(),
      escalation: const ThemeChatEscalation(),
    );
  }
}
