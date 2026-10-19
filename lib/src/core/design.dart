/// THE DESIGN THE BRAND CHOSE, AS THE SESSION CARRIES IT — already resolved.
///
/// The dashboard saves a design (a philosophy and a few knobs); the server
/// resolves it into complete token sets for light and dark and sends both
/// beside `appearance`. This SDK never resolves a philosophy itself: it reads
/// the tokens below and draws them, exactly as the web widget and the React
/// Native, Android and iOS SDKs do (contract/DESIGN.md is the one document
/// they all follow). A new philosophy reaches the app without a release.
///
/// NOTHING IS TRUSTED. Unknown keys are ignored, never an error — a newer
/// server may send more than this build knows. A token that is missing or is
/// not what it should be draws as the look every widget had before designs
/// (Graine Classic). A `design` that is not an object at all is null, and
/// every surface keeps drawing from `appearance` as it always has.
library;

import 'appearance.dart';
import 'call_look.dart';
import 'chat_size.dart';
import 'js.dart';

/// One drop shadow: `{ y, blur, spread, opacity, color }`.
class ThemeShadow {
  const ThemeShadow({
    required this.y,
    required this.blur,
    required this.spread,
    required this.opacity,
    required this.color,
  });

  final double y;
  final double blur;
  final double spread;

  /// 0–1, applied to [color].
  final double opacity;

  /// #RRGGBB.
  final String color;

  /// Null for `null` — no shadow — and for anything that is not a shadow.
  static ThemeShadow? fromJson(Object? raw) {
    final r = Js.asMap(raw);
    if (r == null) return null;
    return ThemeShadow(
      y: _num(r['y'], 0),
      blur: _num(r['blur'], 0, min: 0),
      spread: _num(r['spread'], 0),
      opacity: _num(r['opacity'], 0, min: 0, max: 1),
      color: Design.normaliseHex(r['color']) ?? '#000000',
    );
  }

  Map<String, Object?> toJson() =>
      <String, Object?>{'y': y, 'blur': blur, 'spread': spread, 'opacity': opacity, 'color': color};
}

/// A solid offset shadow (neo-brutalist), drawn in `colors.text`.
class ThemeOffset {
  const ThemeOffset({required this.x, required this.y});

  final double x;
  final double y;

  static ThemeOffset? fromJson(Object? raw) {
    final r = Js.asMap(raw);
    if (r == null) return null;
    return ThemeOffset(x: _num(r['x'], 0), y: _num(r['y'], 0));
  }

  Map<String, Object?> toJson() => <String, Object?>{'x': x, 'y': y};
}

/// Every colour a surface uses, as #RRGGBB.
class ThemeColors {
  const ThemeColors({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.text,
    required this.textMuted,
    required this.border,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.success,
    required this.warning,
    required this.danger,
    required this.userBubble,
    required this.userBubbleText,
    required this.agentBubble,
    required this.agentBubbleText,
    required this.scrim,
  });

  /// Behind everything in the chat window.
  final String background;

  /// The voice bar, the chat header, sheets.
  final String surface;

  /// Cards, the composer field.
  final String surfaceRaised;
  final String text;

  /// Secondary text: captions, status lines.
  final String textMuted;

  /// Hairlines and outlines.
  final String border;

  /// Primary buttons, the launcher, the send button.
  final String accent;

  /// What sits on [accent].
  final String onAccent;

  /// The accent at low strength: chips, selected rows, the focus halo.
  final String accentSoft;
  final String success;
  final String warning;

  /// The end-call button.
  final String danger;
  final String userBubble;
  final String userBubbleText;
  final String agentBubble;
  final String agentBubbleText;

  /// Behind a modal sheet, at 40% opacity.
  final String scrim;

  static ThemeColors fromJson(Map<String, Object?> r, ThemeColors d) {
    String c(String key, String fallback) => Design.normaliseHex(r[key]) ?? fallback;
    return ThemeColors(
      background: c('background', d.background),
      surface: c('surface', d.surface),
      surfaceRaised: c('surfaceRaised', d.surfaceRaised),
      text: c('text', d.text),
      textMuted: c('textMuted', d.textMuted),
      border: c('border', d.border),
      accent: c('accent', d.accent),
      onAccent: c('onAccent', d.onAccent),
      accentSoft: c('accentSoft', d.accentSoft),
      success: c('success', d.success),
      warning: c('warning', d.warning),
      danger: c('danger', d.danger),
      userBubble: c('userBubble', d.userBubble),
      userBubbleText: c('userBubbleText', d.userBubbleText),
      agentBubble: c('agentBubble', d.agentBubble),
      agentBubbleText: c('agentBubbleText', d.agentBubbleText),
      scrim: c('scrim', d.scrim),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'background': background,
        'surface': surface,
        'surfaceRaised': surfaceRaised,
        'text': text,
        'textMuted': textMuted,
        'border': border,
        'accent': accent,
        'onAccent': onAccent,
        'success': success,
        'warning': warning,
        'danger': danger,
        'userBubble': userBubble,
        'userBubbleText': userBubbleText,
        'agentBubble': agentBubble,
        'agentBubbleText': agentBubbleText,
        'scrim': scrim,
        'accentSoft': accentSoft,
      };
}

/// `font.scale`: sizes in logical pixels.
class ThemeFontScale {
  const ThemeFontScale({required this.caption, required this.body, required this.title, required this.display});

  final double caption;
  final double body;
  final double title;
  final double display;

  static ThemeFontScale fromJson(Object? raw, ThemeFontScale d) {
    final r = Js.asMap(raw) ?? const <String, Object?>{};
    return ThemeFontScale(
      caption: _num(r['caption'], d.caption, min: 1),
      body: _num(r['body'], d.body, min: 1),
      title: _num(r['title'], d.title, min: 1),
      display: _num(r['display'], d.display, min: 1),
    );
  }

  Map<String, Object?> toJson() =>
      <String, Object?>{'caption': caption, 'body': body, 'title': title, 'display': display};
}

/// `font.weights`: CSS weights, 100–900.
class ThemeFontWeights {
  const ThemeFontWeights({required this.body, required this.strong, required this.title});

  final int body;
  final int strong;
  final int title;

  static ThemeFontWeights fromJson(Object? raw, ThemeFontWeights d) {
    final r = Js.asMap(raw) ?? const <String, Object?>{};
    int w(Object? v, int fallback) => _num(v, fallback.toDouble(), min: 100, max: 900).round();
    return ThemeFontWeights(body: w(r['body'], d.body), strong: w(r['strong'], d.strong), title: w(r['title'], d.title));
  }

  Map<String, Object?> toJson() => <String, Object?>{'body': body, 'strong': strong, 'title': title};
}

/// A body value and a title value — `font.letterSpacing` (em) and `font.lineHeight` (multipliers).
class ThemeFontPair {
  const ThemeFontPair({required this.body, required this.title});

  final double body;
  final double title;

  static ThemeFontPair fromJson(Object? raw, ThemeFontPair d, {double? min}) {
    final r = Js.asMap(raw) ?? const <String, Object?>{};
    return ThemeFontPair(body: _num(r['body'], d.body, min: min), title: _num(r['title'], d.title, min: min));
  }

  Map<String, Object?> toJson() => <String, Object?>{'body': body, 'title': title};
}

/// Type: families, sizes, weights, spacing.
class ThemeFont {
  const ThemeFont({
    required this.body,
    required this.heading,
    required this.scale,
    required this.weights,
    required this.letterSpacing,
    required this.lineHeight,
  });

  /// "system" — the platform's UI font — or a family name from the
  /// dashboard's list, whose faces the SDK fetches itself: see `DesignFonts`.
  final String body;
  final String heading;
  final ThemeFontScale scale;
  final ThemeFontWeights weights;

  /// In em: multiply by the size.
  final ThemeFontPair letterSpacing;
  final ThemeFontPair lineHeight;

  static ThemeFont fromJson(Object? raw, ThemeFont d) {
    final r = Js.asMap(raw) ?? const <String, Object?>{};
    String family(Object? v, String fallback) {
      final s = v is String ? v.trim() : '';
      return s.isEmpty ? fallback : s;
    }

    return ThemeFont(
      body: family(r['body'], d.body),
      heading: family(r['heading'], d.heading),
      scale: ThemeFontScale.fromJson(r['scale'], d.scale),
      weights: ThemeFontWeights.fromJson(r['weights'], d.weights),
      letterSpacing: ThemeFontPair.fromJson(r['letterSpacing'], d.letterSpacing),
      lineHeight: ThemeFontPair.fromJson(r['lineHeight'], d.lineHeight, min: 0.5),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'body': body,
        'heading': heading,
        'scale': scale.toJson(),
        'weights': weights.toJson(),
        'letterSpacing': letterSpacing.toJson(),
        'lineHeight': lineHeight.toJson(),
      };
}

/// `shape.radius`: corner radii in logical pixels.
class ThemeRadius {
  const ThemeRadius({required this.sm, required this.md, required this.lg, required this.xl});

  final double sm;
  final double md;
  final double lg;
  final double xl;

  static ThemeRadius fromJson(Object? raw, ThemeRadius d) {
    final r = Js.asMap(raw) ?? const <String, Object?>{};
    return ThemeRadius(
      sm: _num(r['sm'], d.sm, min: 0),
      md: _num(r['md'], d.md, min: 0),
      lg: _num(r['lg'], d.lg, min: 0),
      xl: _num(r['xl'], d.xl, min: 0),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{'sm': sm, 'md': md, 'lg': lg, 'xl': xl};
}

class ThemeShape {
  const ThemeShape({required this.radius, required this.borderWidth, required this.launcher});

  final ThemeRadius radius;

  /// The width of every outline.
  final double borderWidth;

  /// One of [Design.launcherShapes].
  final String launcher;

  static ThemeShape fromJson(Object? raw, ThemeShape d) {
    final r = Js.asMap(raw) ?? const <String, Object?>{};
    return ThemeShape(
      radius: ThemeRadius.fromJson(r['radius'], d.radius),
      borderWidth: _num(r['borderWidth'], d.borderWidth, min: 0),
      launcher: _pick(r['launcher'], Design.launcherShapes) ?? d.launcher,
    );
  }

  Map<String, Object?> toJson() =>
      <String, Object?>{'radius': radius.toJson(), 'borderWidth': borderWidth, 'launcher': launcher};
}

class ThemeSpacing {
  const ThemeSpacing({required this.unit, required this.cardPadding, required this.gap});

  final double unit;

  /// Inside cards.
  final double cardPadding;

  /// Between items.
  final double gap;

  static ThemeSpacing fromJson(Object? raw, ThemeSpacing d) {
    final r = Js.asMap(raw) ?? const <String, Object?>{};
    return ThemeSpacing(
      unit: _num(r['unit'], d.unit, min: 0),
      cardPadding: _num(r['cardPadding'], d.cardPadding, min: 0),
      gap: _num(r['gap'], d.gap, min: 0),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{'unit': unit, 'cardPadding': cardPadding, 'gap': gap};
}

/// Depth. Each shadow is null for none; [hardOffset] replaces them when set.
class ThemeElevation {
  const ThemeElevation({this.card, this.floating, this.hardOffset});

  final ThemeShadow? card;
  final ThemeShadow? floating;
  final ThemeOffset? hardOffset;

  /// A key that is ABSENT keeps the fallback's value; one that is present —
  /// `null` included — is the design's word.
  static ThemeElevation fromJson(Object? raw, ThemeElevation d) {
    final r = Js.asMap(raw);
    if (r == null) return d;
    return ThemeElevation(
      card: r.containsKey('card') ? ThemeShadow.fromJson(r['card']) : d.card,
      floating: r.containsKey('floating') ? ThemeShadow.fromJson(r['floating']) : d.floating,
      hardOffset: r.containsKey('hardOffset') ? ThemeOffset.fromJson(r['hardOffset']) : d.hardOffset,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'card': card?.toJson(),
        'floating': floating?.toJson(),
        'hardOffset': hardOffset?.toJson(),
      };
}

class ThemeMotion {
  const ThemeMotion({required this.durationMs, required this.easing, required this.bounce});

  /// 0 means no transitions at all. The platform's reduce-motion setting
  /// always wins over this.
  final int durationMs;

  /// One of [Design.easings].
  final String easing;

  /// 0 (none) upward: how far a spring overshoots.
  final double bounce;

  static ThemeMotion fromJson(Object? raw, ThemeMotion d) {
    final r = Js.asMap(raw) ?? const <String, Object?>{};
    return ThemeMotion(
      durationMs: _num(r['durationMs'], d.durationMs.toDouble(), min: 0, max: 5000).round(),
      easing: _pick(r['easing'], Design.easings) ?? d.easing,
      bounce: _num(r['bounce'], d.bounce, min: 0, max: 1),
    );
  }

  /// No transition: a zero duration, or the easing that says so.
  bool get none => durationMs <= 0 || easing == 'none';

  Map<String, Object?> toJson() => <String, Object?>{'durationMs': durationMs, 'easing': easing, 'bounce': bounce};
}

/// A launcher glyph: 24×24 SVG path data. [stroke] glyphs are drawn with
/// `icons.stroke`; the rest are filled.
class LauncherGlyph {
  const LauncherGlyph({required this.id, required this.path, required this.stroke});

  final String id;
  final String path;
  final bool stroke;

  static LauncherGlyph? fromJson(Object? raw) {
    final r = Js.asMap(raw);
    if (r == null) return null;
    final id = r['id'] is String ? (r['id']! as String).trim() : '';
    final path = r['path'] is String ? (r['path']! as String).trim() : '';
    if (id.isEmpty && path.isEmpty) return null;
    return LauncherGlyph(id: id, path: path, stroke: r['stroke'] is bool ? r['stroke']! as bool : true);
  }

  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'path': path, 'stroke': stroke};
}

class ThemeIcons {
  const ThemeIcons({required this.style, required this.stroke, this.launcher});

  /// One of [Design.iconStyles].
  final String style;

  /// Stroke width, in the glyph's own 24-unit box.
  final double stroke;

  /// Null: the launcher shows the brand's logo.
  final LauncherGlyph? launcher;

  static ThemeIcons fromJson(Object? raw, ThemeIcons d) {
    final r = Js.asMap(raw);
    if (r == null) return d;
    return ThemeIcons(
      style: _pick(r['style'], Design.iconStyles) ?? d.style,
      stroke: _num(r['stroke'], d.stroke, min: 0.25, max: 8),
      launcher: r.containsKey('launcher') ? LauncherGlyph.fromJson(r['launcher']) : d.launcher,
    );
  }

  Map<String, Object?> toJson() =>
      <String, Object?>{'style': style, 'stroke': stroke, 'launcher': launcher?.toJson()};
}

/// Translucent, blurred surfaces.
class ThemeGlass {
  const ThemeGlass({required this.blur, required this.surfaceOpacity});

  /// How much of what is behind shows through blurred — a standard
  /// deviation, as CSS's `blur()` takes it.
  final double blur;

  /// `colors.surface` at this opacity, 0–1.
  final double surfaceOpacity;

  static ThemeGlass? fromJson(Object? raw) {
    final r = Js.asMap(raw);
    if (r == null) return null;
    return ThemeGlass(blur: _num(r['blur'], 20, min: 0, max: 100), surfaceOpacity: _num(r['surfaceOpacity'], 0.72, min: 0, max: 1));
  }

  Map<String, Object?> toJson() => <String, Object?>{'blur': blur, 'surfaceOpacity': surfaceOpacity};
}

/// THE CHAT WINDOW'S TOKENS (contract §7, `ThemeTokens.chat`): the brand's
/// words — or "" for the default named on each — and colours already checked
/// against what they sit on.
class ThemeChat {
  const ThemeChat({
    this.title = '',
    this.subtitle = '',
    this.avatar = 'logo',
    this.placeholder = '',
    this.showTimestamps = false,
    this.suggestions = const <String>[],
    required this.background,
    this.pattern = 'none',
    required this.patternColor,
    required this.headerBackground,
    required this.headerText,
    required this.headerSubtext,
    required this.composerBackground,
    required this.composerText,
    required this.composerPlaceholder,
    required this.composerBorder,
    this.size = GraineChatSize.compact,
    this.showUpcomingCalls = true,
    this.upcomingTitle = '',
    this.showHistory = true,
    this.newConversation = true,
  });

  static const List<String> avatars = <String>['logo', 'glyph', 'none'];
  static const List<String> patterns = <String>['none', 'dots'];

  /// The most conversation starters a chat shows.
  static const int maxSuggestions = 4;

  /// The header's title; "" is the dashboard's heading.
  final String title;

  /// Under the title while online; "" is "Online".
  final String subtitle;

  /// What stands for the agent in the header: `logo`, `glyph` or `none`.
  final String avatar;

  /// The composer's placeholder; "" is "Message…".
  final String placeholder;
  final bool showTimestamps;

  /// Conversation starters for a new chat, at most [maxSuggestions].
  final List<String> suggestions;

  /// Behind the messages and the composer strip.
  final String background;

  /// `dots`: a dot pattern in [patternColor] over [background].
  final String pattern;
  final String patternColor;
  final String headerBackground;
  final String headerText;
  final String headerSubtext;
  final String composerBackground;
  final String composerText;
  final String composerPlaceholder;
  final String composerBorder;

  /// How big the window opens (Window size in the dashboard): compact unless the design says otherwise.
  final GraineChatSize size;

  /// The card of the user's booked calls at the top of the chat (Booked calls in the dashboard).
  final bool showUpcomingCalls;

  /// That card's title; "" is "Upcoming call" / "Upcoming calls".
  final String upcomingTitle;

  /// The conversation kept from before, on screen (Earlier messages). Off, the agent still has it.
  final bool showHistory;

  /// The header's compose control (New conversation button). Off,
  /// `GraineChatSession.newConversation()` still works.
  final bool newConversation;

  /// WHAT AN OLDER SERVER'S CHAT LOOKS LIKE — the window as it was drawn
  /// before these tokens: the page, the surface header, the raised composer,
  /// and the launcher's mark (its glyph when the design has one).
  factory ThemeChat.fallback(ThemeColors c, {required bool dark, required bool hasGlyph}) => ThemeChat(
        avatar: hasGlyph ? 'glyph' : 'logo',
        background: c.background,
        patternColor: Design.mixHex(c.background, c.text, dark ? 0.14 : 0.1),
        headerBackground: c.surface,
        headerText: c.text,
        headerSubtext: c.textMuted,
        composerBackground: c.surfaceRaised,
        composerText: c.text,
        composerPlaceholder: c.textMuted,
        composerBorder: c.border,
      );

  static ThemeChat fromJson(Map<String, Object?> r, ThemeChat d) {
    String words(Object? v, String fallback) => v is String ? v : fallback;
    String c(String key, String fallback) => Design.normaliseHex(r[key]) ?? fallback;
    final raw = r['suggestions'];
    return ThemeChat(
      title: words(r['title'], d.title),
      subtitle: words(r['subtitle'], d.subtitle),
      avatar: _pick(r['avatar'], avatars) ?? d.avatar,
      placeholder: words(r['placeholder'], d.placeholder),
      showTimestamps: r['showTimestamps'] is bool ? r['showTimestamps']! as bool : d.showTimestamps,
      suggestions: raw is List
          ? <String>[
              for (final s in raw)
                if (s is String && s.trim().isNotEmpty) s,
            ].take(maxSuggestions).toList()
          : d.suggestions,
      background: c('background', d.background),
      pattern: _pick(r['pattern'], patterns) ?? d.pattern,
      patternColor: c('patternColor', d.patternColor),
      headerBackground: c('headerBackground', d.headerBackground),
      headerText: c('headerText', d.headerText),
      headerSubtext: c('headerSubtext', d.headerSubtext),
      composerBackground: c('composerBackground', d.composerBackground),
      composerText: c('composerText', d.composerText),
      composerPlaceholder: c('composerPlaceholder', d.composerPlaceholder),
      composerBorder: c('composerBorder', d.composerBorder),
      // Absent (an older server) or a word this build does not know: the compact window.
      size: GraineChatSize.fromWire(r['size']) ?? d.size,
      // The pieces the brand can leave out: absent, or anything but a boolean, is on.
      showUpcomingCalls: r['showUpcomingCalls'] is bool ? r['showUpcomingCalls']! as bool : d.showUpcomingCalls,
      upcomingTitle: r['upcomingTitle'] is String ? (r['upcomingTitle']! as String).trim() : d.upcomingTitle,
      showHistory: r['showHistory'] is bool ? r['showHistory']! as bool : d.showHistory,
      newConversation: r['newConversation'] is bool ? r['newConversation']! as bool : d.newConversation,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'title': title,
        'subtitle': subtitle,
        'avatar': avatar,
        'placeholder': placeholder,
        'showTimestamps': showTimestamps,
        'suggestions': List<String>.of(suggestions),
        'background': background,
        'pattern': pattern,
        'patternColor': patternColor,
        'headerBackground': headerBackground,
        'headerText': headerText,
        'headerSubtext': headerSubtext,
        'composerBackground': composerBackground,
        'composerText': composerText,
        'composerPlaceholder': composerPlaceholder,
        'composerBorder': composerBorder,
        'size': size.wire,
        'showUpcomingCalls': showUpcomingCalls,
        'upcomingTitle': upcomingTitle,
        'showHistory': showHistory,
        'newConversation': newConversation,
      };
}

/// The words a call screen says at each moment.
class ThemeCallStatusText {
  const ThemeCallStatusText({
    this.ringing = 'Incoming call',
    this.scheduled = 'Scheduled call',
    this.connecting = 'Connecting…',
    this.ended = 'Call ended',
    this.missed = 'Missed call',
    this.servedOutgoing,
    this.servedReconnecting,
  });

  /// Another ring.
  final String ringing;

  /// A ring Graine placed for a time the user (or the agent) booked.
  final String scheduled;
  final String connecting;
  final String ended;
  final String missed;

  /// The words for a call the customer placed, and for a connected call
  /// recovering its connection, as the session carried them; null from a
  /// server that predates them. Draw [outgoing] and [reconnecting].
  final String? servedOutgoing;
  final String? servedReconnecting;

  /// A call the customer placed, before it is through: the connecting words unless the brand wrote its own.
  String get outgoing => servedOutgoing ?? connecting;

  /// A connected call recovering its connection.
  String get reconnecting => servedReconnecting ?? 'Reconnecting…';

  static ThemeCallStatusText fromJson(Object? raw, ThemeCallStatusText d) {
    final r = Js.asMap(raw) ?? const <String, Object?>{};
    String w(Object? v, String fallback) => v is String && v.trim().isNotEmpty ? v : fallback;
    String? said(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
    return ThemeCallStatusText(
      ringing: w(r['ringing'], d.ringing),
      scheduled: w(r['scheduled'], d.scheduled),
      connecting: w(r['connecting'], d.connecting),
      ended: w(r['ended'], d.ended),
      missed: w(r['missed'], d.missed),
      servedOutgoing: said(r['outgoing']),
      servedReconnecting: said(r['reconnecting']),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'ringing': ringing,
        'scheduled': scheduled,
        'connecting': connecting,
        'ended': ended,
        'missed': missed,
        if (servedOutgoing != null) 'outgoing': servedOutgoing,
        if (servedReconnecting != null) 'reconnecting': servedReconnecting,
      };
}

/// One colour of a call screen's backdrop, at a position 0–1 along it.
class ThemeCallStop {
  const ThemeCallStop(this.color, this.at);

  final String color;
  final double at;

  Map<String, Object?> toJson() => <String, Object?>{'color': color, 'at': at};
}

/// THE CALL SCREEN'S FILL (contract/DESIGN.md "Call screen" → Backdrop):
/// one colour, a linear or radial gradient, a mesh of glows, or the avatar
/// blurred under a scrim of the stops.
class ThemeCallBackdrop {
  const ThemeCallBackdrop({
    required this.type,
    required this.stops,
    this.angle = 180,
    this.motion = 'none',
    this.intensity = 0.5,
    this.scrim = 1,
  });

  static const List<String> types = <String>['solid', 'linear', 'radial', 'mesh', 'blurred-avatar'];
  static const List<String> motions = <String>['none', 'drift', 'breathe'];

  /// One of [types].
  final String type;

  /// One for `solid`, 2–5 otherwise, in order of `at`.
  final List<ThemeCallStop> stops;

  /// A linear gradient's direction (and a blurred avatar's scrim's), degrees as CSS reads them: 180 runs top to bottom.
  final double angle;

  /// One of [motions].
  final String motion;
  final double intensity;

  /// `blurred-avatar`: the stops' opacity over the blurred avatar. 1 for every other type.
  final double scrim;

  /// The flat fill an older server describes: one colour, or a gradient from top to bottom.
  factory ThemeCallBackdrop.flat(String background, String? backgroundTo) => ThemeCallBackdrop(
        type: backgroundTo == null ? 'solid' : 'linear',
        stops: backgroundTo == null
            ? <ThemeCallStop>[ThemeCallStop(background, 0)]
            : <ThemeCallStop>[ThemeCallStop(background, 0), ThemeCallStop(backgroundTo, 1)],
      );

  static ThemeCallBackdrop fromJson(Object? raw, ThemeCallBackdrop d) {
    final r = Js.asMap(raw);
    if (r == null) return d;
    final stops = <ThemeCallStop>[];
    final list = r['stops'];
    if (list is List) {
      for (final s in list) {
        final m = Js.asMap(s);
        final color = Design.normaliseHex(m?['color']);
        final at = Js.finite(m?['at']);
        if (color != null && at != null) stops.add(ThemeCallStop(color, at));
      }
    }
    return ThemeCallBackdrop(
      type: _word(r, 'type', types, d.type),
      stops: stops.isEmpty ? d.stops : stops,
      angle: Js.finite(r['angle']) ?? d.angle,
      motion: _word(r, 'motion', motions, d.motion),
      intensity: Js.finite(r['intensity']) ?? d.intensity,
      scrim: Js.finite(r['scrim']) ?? d.scrim,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'type': type,
        'stops': <Object?>[for (final s in stops) s.toJson()],
        'angle': angle,
        'motion': motion,
        'intensity': intensity,
        'scrim': scrim,
      };
}

/// One call button's colours.
class ThemeCallAction {
  const ThemeCallAction({
    required this.fill,
    this.fillAlpha = 1,
    required this.icon,
    this.stroke,
    required this.activeFill,
    required this.activeIcon,
  });

  /// The buttons, by name: `close` is the missed call's Close.
  static const List<String> names = <String>['answer', 'decline', 'end', 'callback', 'mute', 'speaker', 'chat', 'close'];

  final String fill;

  /// Below 1: glass — [fill] at this opacity over the backdrop, blurred where the platform can. 0: an outline's empty middle.
  final double fillAlpha;
  final String icon;

  /// An outline in this colour, 1.5 wide; null: none.
  final String? stroke;

  /// Mute and speaker while on (the rest: the same as [fill] / [icon]). Always opaque.
  final String activeFill;
  final String activeIcon;

  /// A filled button in one colour, as an older server's flat tokens describe it.
  factory ThemeCallAction.flat(String fill, String icon, [String? activeFill, String? activeIcon]) =>
      ThemeCallAction(fill: fill, icon: icon, activeFill: activeFill ?? fill, activeIcon: activeIcon ?? icon);

  static ThemeCallAction fromJson(Object? raw, ThemeCallAction d) {
    final r = Js.asMap(raw);
    if (r == null) return d;
    String c(String key, String fallback) => Design.normaliseHex(r[key]) ?? fallback;
    return ThemeCallAction(
      fill: c('fill', d.fill),
      fillAlpha: Js.finite(r['fillAlpha']) ?? d.fillAlpha,
      icon: c('icon', d.icon),
      // Null is an answer (no outline); a colour that is not one is this build's.
      stroke: r.containsKey('stroke') ? (r['stroke'] == null ? null : Design.normaliseHex(r['stroke']) ?? d.stroke) : d.stroke,
      activeFill: c('activeFill', d.activeFill),
      activeIcon: c('activeIcon', d.activeIcon),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'fill': fill,
        'fillAlpha': fillAlpha,
        'icon': icon,
        'stroke': stroke,
        'activeFill': activeFill,
        'activeIcon': activeIcon,
      };
}

/// WHAT CHANGES FROM ONE MOMENT OF A CALL TO ANOTHER: everything drawn in a
/// colour. The screen's own look is [ThemeCall.look]; a moment with its own is
/// in [ThemeCall.states].
class ThemeCallLook {
  const ThemeCallLook({
    required this.backdrop,
    required this.ink,
    required this.text,
    required this.textMuted,
    required this.avatarRingColor,
    required this.actions,
    required this.visualizerColor,
    required this.captionFill,
    required this.captionFillAlpha,
  });

  final ThemeCallBackdrop backdrop;

  /// "light" or "dark": whether [text] is light. The status bar's icons follow it.
  final String ink;
  final String text;
  final String textMuted;
  final String avatarRingColor;

  /// Every button's colours, by [ThemeCallAction.names].
  final Map<String, ThemeCallAction> actions;
  final String visualizerColor;

  /// Behind a card, subtitle or bubble caption: [captionFill] at [captionFillAlpha] (0 for plain).
  final String captionFill;
  final double captionFillAlpha;

  /// [raw] read against [d], key for key.
  static ThemeCallLook fromJson(Object? raw, ThemeCallLook d) {
    final r = Js.asMap(raw);
    if (r == null) return d;
    String c(String key, String fallback) => Design.normaliseHex(r[key]) ?? fallback;
    return ThemeCallLook(
      backdrop: ThemeCallBackdrop.fromJson(r['backdrop'], d.backdrop),
      ink: _word(r, 'ink', ThemeCall.inks, d.ink),
      text: c('text', d.text),
      textMuted: c('textMuted', d.textMuted),
      avatarRingColor: c('avatarRingColor', d.avatarRingColor),
      actions: _actions(r['actions'], d.actions),
      visualizerColor: c('visualizerColor', d.visualizerColor),
      captionFill: c('captionFill', d.captionFill),
      captionFillAlpha: Js.finite(r['captionFillAlpha']) ?? d.captionFillAlpha,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'backdrop': backdrop.toJson(),
        'ink': ink,
        'text': text,
        'textMuted': textMuted,
        'avatarRingColor': avatarRingColor,
        'actions': <String, Object?>{for (final e in actions.entries) e.key: e.value.toJson()},
        'visualizerColor': visualizerColor,
        'captionFill': captionFill,
        'captionFillAlpha': captionFillAlpha,
      };
}

/// Every button of [raw] read against [d]'s; a button the server left out is this build's.
Map<String, ThemeCallAction> _actions(Object? raw, Map<String, ThemeCallAction> d) {
  final r = Js.asMap(raw);
  if (r == null) return d;
  return <String, ThemeCallAction>{
    for (final name in ThemeCallAction.names)
      if (d[name] != null) name: ThemeCallAction.fromJson(r[name], d[name]!),
  };
}

/// A word of [allowed] at [key]: absent, [fallback]; one this build does not
/// know (a newer server's), the first listed — the contract's rule.
String _word(Map<String, Object?> r, String key, List<String> allowed, String fallback) {
  if (!r.containsKey(key) || r[key] == null) return fallback;
  return _pick(r[key], allowed) ?? allowed.first;
}

/// THE CALL SCREEN'S TOKENS (contract §7, `ThemeTokens.call`) — the flat
/// colours, words and buttons every SDK has drawn, and the look (version 2,
/// contract/DESIGN.md "Call screen" → "The look"): the backdrop, layout,
/// avatar ring, the buttons' style, the voice, the caption's style, the type
/// and a look per moment. The SDK's own call screens — on Android its call
/// activity, on iOS its call view, both drawn natively from these tokens —
/// draw every moment themselves, so `GraineCallScreen.sdk` needs nothing from
/// the app. These, with [CallLook]'s rules, are for a screen an app draws
/// itself (`GraineCallScreen.app`).
class ThemeCall {
  const ThemeCall({
    required this.background,
    this.backgroundTo,
    required this.text,
    required this.textMuted,
    this.avatar = 'logo',
    this.avatarShape = 'circle',
    required this.avatarFill,
    required this.avatarText,
    required this.buttonFill,
    required this.buttonIcon,
    required this.buttonActiveFill,
    required this.buttonActiveIcon,
    required this.endFill,
    required this.endIcon,
    this.endShape = 'round',
    required this.acceptFill,
    required this.acceptIcon,
    required this.declineFill,
    required this.declineIcon,
    required this.callbackFill,
    required this.callbackIcon,
    this.captions = true,
    this.timer = true,
    this.controls = defaultControls,
    this.ringtone = 'system',
    this.statusText = const ThemeCallStatusText(),
    this.titleWeight = 600,
    this.bodyWeight = 400,
    this.servedPreset,
    this.servedLayout,
    this.servedBackdrop,
    this.servedInk,
    this.servedAvatarSize,
    this.servedRings,
    this.servedAvatarRingColor,
    this.servedButtonStyle,
    this.servedButtonShape,
    this.servedButtonSize,
    this.servedButtonLabels,
    this.servedActions,
    this.servedVisualizer,
    this.servedVisualizerColor,
    this.servedVisualizerSensitivity,
    this.servedCaptionStyle,
    this.servedCaptionPosition,
    this.servedCaptionFill,
    this.servedCaptionFillAlpha,
    this.servedNameSize,
    this.servedNameWeight,
    this.servedStatusSize,
    this.servedStatusWeight,
    this.servedStates,
  });

  static const List<String> avatars = <String>['logo', 'glyph', 'initials'];
  static const List<String> avatarShapes = <String>['circle', 'squircle', 'rounded-square'];
  static const List<String> endShapes = <String>['round', 'pill'];
  static const List<String> ringtones = <String>['system', 'graine', 'soft'];
  static const List<String> allControls = <String>['mute', 'speaker', 'chat', 'end'];
  static const List<String> defaultControls = <String>['mute', 'speaker', 'chat', 'end'];

  // The look's words (version 2). A word this build does not know is drawn as the first listed.
  static const List<String> presets = <String>['classic', 'aurora', 'midnight', 'glass', 'orbit', 'daylight', 'bloom', 'studio', 'minimal', 'mono'];
  static const List<String> layouts = <String>['classic', 'full-bleed', 'card', 'orb', 'minimal'];
  static const List<String> inks = <String>['light', 'dark'];
  static const List<String> ringKinds = <String>['none', 'pulse', 'ripple', 'glow'];
  static const List<String> buttonStyles = <String>['solid', 'glass', 'outline'];
  static const List<String> buttonShapes = <String>['circle', 'squircle', 'pill'];
  static const List<String> buttonLabelModes = <String>['below', 'none'];
  static const List<String> visualizers = <String>['none', 'bars', 'wave', 'orb'];
  static const List<String> captionStyles = <String>['plain', 'card', 'subtitle', 'bubble'];
  static const List<String> captionPositions = <String>['middle', 'bottom'];

  /// The eight moments a call screen shows ([CallLook.moment]).
  static const List<String> moments = <String>['incoming', 'scheduled', 'outgoing', 'connecting', 'connected', 'reconnecting', 'ended', 'missed'];

  /// The fill, or a gradient's top.
  final String background;

  /// A gradient's bottom; null for one solid fill.
  final String? backgroundTo;
  final String text;
  final String textMuted;
  final String avatar;
  final String avatarShape;
  final String avatarFill;
  final String avatarText;
  final String buttonFill;
  final String buttonIcon;
  final String buttonActiveFill;
  final String buttonActiveIcon;
  final String endFill;
  final String endIcon;
  final String endShape;
  final String acceptFill;
  final String acceptIcon;
  final String declineFill;
  final String declineIcon;

  /// "Call back", on a missed call.
  final String callbackFill;
  final String callbackIcon;

  /// Show the line being said.
  final bool captions;

  /// Show the call's running time.
  final bool timer;

  /// The in-call buttons, in order; `end` is always among them.
  final List<String> controls;
  final String ringtone;
  final ThemeCallStatusText statusText;

  /// The design's title and body weights: the name and the status line's, when the session does not say.
  final double titleWeight;
  final double bodyWeight;

  // ── The look (version 2) as the session carried it; null where it said
  // nothing (an older server). Draw from the getters below, which fill each
  // one in exactly as contract/DESIGN.md "An older server" says.

  final String? servedPreset;
  final String? servedLayout;
  final ThemeCallBackdrop? servedBackdrop;
  final String? servedInk;
  final double? servedAvatarSize;
  final Map<String, String>? servedRings;
  final String? servedAvatarRingColor;
  final String? servedButtonStyle;
  final String? servedButtonShape;
  final double? servedButtonSize;
  final String? servedButtonLabels;
  final Map<String, ThemeCallAction>? servedActions;
  final String? servedVisualizer;
  final String? servedVisualizerColor;
  final double? servedVisualizerSensitivity;
  final String? servedCaptionStyle;
  final String? servedCaptionPosition;
  final String? servedCaptionFill;
  final double? servedCaptionFillAlpha;
  final double? servedNameSize;
  final double? servedNameWeight;
  final double? servedStatusSize;
  final double? servedStatusWeight;
  final Map<String, ThemeCallLook>? servedStates;

  /// The preset the look was resolved from; "classic" is the screen as it has always been.
  String get preset => servedPreset ?? 'classic';

  /// How the screen is laid out: one of [layouts] ([CallLook.layouts] has the numbers).
  String get layout => servedLayout ?? 'classic';

  /// The fill: the session's, else the flat one.
  ThemeCallBackdrop get backdrop => servedBackdrop ?? ThemeCallBackdrop.flat(background, backgroundTo);

  /// "light" when [text] is light.
  String get ink => servedInk ?? (Appearance.luminance(text) > 0.5 ? 'light' : 'dark');
  double get avatarSize => servedAvatarSize ?? 112;

  /// The ring the avatar wears in each moment: a ring only while it rings, unless the session says otherwise.
  Map<String, String> get rings =>
      servedRings ?? <String, String>{for (final m in moments) m: m == 'incoming' || m == 'scheduled' ? 'pulse' : 'none'};
  String get avatarRingColor => servedAvatarRingColor ?? textMuted;
  String get buttonStyle => servedButtonStyle ?? 'solid';
  String get buttonShape => servedButtonShape ?? 'circle';

  /// The in-call buttons' size; the ring's and the missed call's are [CallLook.buttonSizes]' big one.
  double get buttonSize => servedButtonSize ?? 64;
  String get buttonLabels => servedButtonLabels ?? 'below';

  /// Every button's colours: the session's, else the flat ones.
  Map<String, ThemeCallAction> get actions => servedActions ?? flatActions;
  String get visualizer => servedVisualizer ?? 'none';
  String get visualizerColor => servedVisualizerColor ?? text;
  double get visualizerSensitivity => servedVisualizerSensitivity ?? 0.5;
  String get captionStyle => servedCaptionStyle ?? 'plain';
  String get captionPosition => servedCaptionPosition ?? 'middle';
  String get captionFill => servedCaptionFill ?? (ink == 'light' ? '#000000' : '#FFFFFF');
  double get captionFillAlpha => servedCaptionFillAlpha ?? 0;
  double get nameSize => servedNameSize ?? (CallLook.layouts[layout]?.nameSize ?? 28);
  double get nameWeight => servedNameWeight ?? titleWeight;
  double get statusSize => servedStatusSize ?? 16;
  double get statusWeight => servedStatusWeight ?? bodyWeight;

  /// A moment's own look where it differs from the screen's; a moment not listed is drawn in [look].
  Map<String, ThemeCallLook> get states => servedStates ?? const <String, ThemeCallLook>{};

  /// The screen's own look.
  ThemeCallLook get look => ThemeCallLook(
        backdrop: backdrop,
        ink: ink,
        text: text,
        textMuted: textMuted,
        avatarRingColor: avatarRingColor,
        actions: actions,
        visualizerColor: visualizerColor,
        captionFill: captionFill,
        captionFillAlpha: captionFillAlpha,
      );

  /// The buttons as the flat colours describe them.
  Map<String, ThemeCallAction> get flatActions {
    final neutral = ThemeCallAction.flat(buttonFill, buttonIcon, buttonActiveFill, buttonActiveIcon);
    return <String, ThemeCallAction>{
      'answer': ThemeCallAction.flat(acceptFill, acceptIcon),
      'decline': ThemeCallAction.flat(declineFill, declineIcon),
      'end': ThemeCallAction.flat(endFill, endIcon),
      'callback': ThemeCallAction.flat(callbackFill, callbackIcon),
      'mute': neutral,
      'speaker': neutral,
      'chat': neutral,
      'close': neutral,
    };
  }

  /// WHAT AN OLDER SERVER'S CALL SCREEN LOOKS LIKE — the fixed dark screen
  /// the native SDKs drew before these tokens.
  factory ThemeCall.fallback(ThemeColors c, {ThemeFontWeights? weights}) => ThemeCall(
        background: '#0F1115',
        text: '#FFFFFF',
        textMuted: '#A3A8B3',
        avatarFill: c.accent,
        avatarText: c.onAccent,
        buttonFill: '#2A2D35',
        buttonIcon: '#FFFFFF',
        buttonActiveFill: '#FFFFFF',
        buttonActiveIcon: '#0F1115',
        endFill: '#E5484D',
        endIcon: '#FFFFFF',
        acceptFill: '#1FAD5B',
        acceptIcon: '#FFFFFF',
        declineFill: '#E5484D',
        declineIcon: '#FFFFFF',
        callbackFill: c.accent,
        callbackIcon: c.onAccent,
        titleWeight: (weights?.title ?? 600).toDouble(),
        bodyWeight: (weights?.body ?? 400).toDouble(),
      );

  static ThemeCall fromJson(Map<String, Object?> r, ThemeCall d, {ThemeFontWeights? weights}) {
    String c(String key, String fallback) => Design.normaliseHex(r[key]) ?? fallback;
    final rawControls = r['controls'];
    var controls = d.controls;
    if (rawControls is List) {
      final list = <String>[];
      for (final x in rawControls) {
        final k = _pick(x, allControls);
        if (k != null && !list.contains(k)) list.add(k);
      }
      if (list.isNotEmpty) {
        if (!list.contains('end')) list.add('end'); // always a way to hang up
        controls = list;
      }
    }
    final flat = ThemeCall(
      background: c('background', d.background),
      backgroundTo: r.containsKey('backgroundTo') ? Design.normaliseHex(r['backgroundTo']) : d.backgroundTo,
      text: c('text', d.text),
      textMuted: c('textMuted', d.textMuted),
      avatar: _pick(r['avatar'], avatars) ?? d.avatar,
      avatarShape: _pick(r['avatarShape'], avatarShapes) ?? d.avatarShape,
      avatarFill: c('avatarFill', d.avatarFill),
      avatarText: c('avatarText', d.avatarText),
      buttonFill: c('buttonFill', d.buttonFill),
      buttonIcon: c('buttonIcon', d.buttonIcon),
      buttonActiveFill: c('buttonActiveFill', d.buttonActiveFill),
      buttonActiveIcon: c('buttonActiveIcon', d.buttonActiveIcon),
      endFill: c('endFill', d.endFill),
      endIcon: c('endIcon', d.endIcon),
      endShape: _pick(r['endShape'], endShapes) ?? d.endShape,
      acceptFill: c('acceptFill', d.acceptFill),
      acceptIcon: c('acceptIcon', d.acceptIcon),
      declineFill: c('declineFill', d.declineFill),
      declineIcon: c('declineIcon', d.declineIcon),
      callbackFill: c('callbackFill', d.callbackFill),
      callbackIcon: c('callbackIcon', d.callbackIcon),
      captions: r['captions'] is bool ? r['captions']! as bool : d.captions,
      timer: r['timer'] is bool ? r['timer']! as bool : d.timer,
      controls: controls,
      ringtone: _pick(r['ringtone'], ringtones) ?? d.ringtone,
      statusText: ThemeCallStatusText.fromJson(r['statusText'], d.statusText),
      titleWeight: weights?.title.toDouble() ?? d.titleWeight,
      bodyWeight: weights?.body.toDouble() ?? d.bodyWeight,
    );
    return flat._withLook(r);
  }

  /// These flat tokens with the look [r] carries, each key read against what this build derives for it.
  ThemeCall _withLook(Map<String, Object?> r) {
    String? word(String key, List<String> allowed, String own) => r.containsKey(key) ? _word(r, key, allowed, own) : null;
    String? color(String key) => r.containsKey(key) ? Design.normaliseHex(r[key]) : null;
    double? number(String key) => Js.finite(r[key]);
    final backdrop = r.containsKey('backdrop') ? ThemeCallBackdrop.fromJson(r['backdrop'], this.backdrop) : null;
    Map<String, String>? rings;
    final rawRings = Js.asMap(r['rings']);
    if (rawRings != null) {
      final own = this.rings;
      rings = <String, String>{for (final m in moments) m: _word(rawRings, m, ringKinds, own[m]!)};
    }
    final actions = r.containsKey('actions') ? _actions(r['actions'], flatActions) : null;
    final read = _copy(
      preset: word('preset', presets, preset),
      layout: word('layout', layouts, layout),
      backdrop: backdrop,
      ink: word('ink', inks, ink),
      avatarSize: number('avatarSize'),
      rings: rings,
      avatarRingColor: color('avatarRingColor'),
      buttonStyle: word('buttonStyle', buttonStyles, buttonStyle),
      buttonShape: word('buttonShape', buttonShapes, buttonShape),
      buttonSize: number('buttonSize'),
      buttonLabels: word('buttonLabels', buttonLabelModes, buttonLabels),
      actions: actions,
      visualizer: word('visualizer', visualizers, visualizer),
      visualizerColor: color('visualizerColor'),
      visualizerSensitivity: number('visualizerSensitivity'),
      captionStyle: word('captionStyle', captionStyles, captionStyle),
      captionPosition: word('captionPosition', captionPositions, captionPosition),
      captionFill: color('captionFill'),
      captionFillAlpha: number('captionFillAlpha'),
      nameSize: number('nameSize'),
      nameWeight: number('nameWeight'),
      statusSize: number('statusSize'),
      statusWeight: number('statusWeight'),
    );
    // The moments' own looks: exactly the moments the session sent, each read against the screen's.
    final rawStates = Js.asMap(r['states']);
    if (rawStates == null) return read;
    final screen = read.look;
    return read._copy(states: <String, ThemeCallLook>{
      for (final m in moments)
        if (Js.asMap(rawStates[m]) != null) m: ThemeCallLook.fromJson(rawStates[m], screen),
    });
  }

  ThemeCall _copy({
    String? preset, String? layout, ThemeCallBackdrop? backdrop, String? ink, double? avatarSize, Map<String, String>? rings,
    String? avatarRingColor, String? buttonStyle, String? buttonShape, double? buttonSize, String? buttonLabels,
    Map<String, ThemeCallAction>? actions, String? visualizer, String? visualizerColor, double? visualizerSensitivity,
    String? captionStyle, String? captionPosition, String? captionFill, double? captionFillAlpha, double? nameSize,
    double? nameWeight, double? statusSize, double? statusWeight, Map<String, ThemeCallLook>? states,
  }) =>
      ThemeCall(
        background: background, backgroundTo: backgroundTo, text: text, textMuted: textMuted, avatar: avatar,
        avatarShape: avatarShape, avatarFill: avatarFill, avatarText: avatarText, buttonFill: buttonFill,
        buttonIcon: buttonIcon, buttonActiveFill: buttonActiveFill, buttonActiveIcon: buttonActiveIcon, endFill: endFill,
        endIcon: endIcon, endShape: endShape, acceptFill: acceptFill, acceptIcon: acceptIcon, declineFill: declineFill,
        declineIcon: declineIcon, callbackFill: callbackFill, callbackIcon: callbackIcon, captions: captions, timer: timer,
        controls: controls, ringtone: ringtone, statusText: statusText, titleWeight: titleWeight, bodyWeight: bodyWeight,
        servedPreset: preset ?? servedPreset,
        servedLayout: layout ?? servedLayout,
        servedBackdrop: backdrop ?? servedBackdrop,
        servedInk: ink ?? servedInk,
        servedAvatarSize: avatarSize ?? servedAvatarSize,
        servedRings: rings ?? servedRings,
        servedAvatarRingColor: avatarRingColor ?? servedAvatarRingColor,
        servedButtonStyle: buttonStyle ?? servedButtonStyle,
        servedButtonShape: buttonShape ?? servedButtonShape,
        servedButtonSize: buttonSize ?? servedButtonSize,
        servedButtonLabels: buttonLabels ?? servedButtonLabels,
        servedActions: actions ?? servedActions,
        servedVisualizer: visualizer ?? servedVisualizer,
        servedVisualizerColor: visualizerColor ?? servedVisualizerColor,
        servedVisualizerSensitivity: visualizerSensitivity ?? servedVisualizerSensitivity,
        servedCaptionStyle: captionStyle ?? servedCaptionStyle,
        servedCaptionPosition: captionPosition ?? servedCaptionPosition,
        servedCaptionFill: captionFill ?? servedCaptionFill,
        servedCaptionFillAlpha: captionFillAlpha ?? servedCaptionFillAlpha,
        servedNameSize: nameSize ?? servedNameSize,
        servedNameWeight: nameWeight ?? servedNameWeight,
        servedStatusSize: statusSize ?? servedStatusSize,
        servedStatusWeight: statusWeight ?? servedStatusWeight,
        servedStates: states ?? servedStates,
      );

  /// The tokens as the session carried them: the flat ones, and the look's keys the session sent.
  Map<String, Object?> toJson() => <String, Object?>{
        'background': background,
        'backgroundTo': backgroundTo,
        'text': text,
        'textMuted': textMuted,
        'avatar': avatar,
        'avatarShape': avatarShape,
        'avatarFill': avatarFill,
        'avatarText': avatarText,
        'buttonFill': buttonFill,
        'buttonIcon': buttonIcon,
        'buttonActiveFill': buttonActiveFill,
        'buttonActiveIcon': buttonActiveIcon,
        'endFill': endFill,
        'endIcon': endIcon,
        'endShape': endShape,
        'acceptFill': acceptFill,
        'acceptIcon': acceptIcon,
        'declineFill': declineFill,
        'declineIcon': declineIcon,
        'callbackFill': callbackFill,
        'callbackIcon': callbackIcon,
        'captions': captions,
        'timer': timer,
        'controls': List<String>.of(controls),
        'ringtone': ringtone,
        'statusText': statusText.toJson(),
        if (servedPreset != null) 'preset': servedPreset,
        if (servedLayout != null) 'layout': servedLayout,
        if (servedBackdrop != null) 'backdrop': servedBackdrop!.toJson(),
        if (servedInk != null) 'ink': servedInk,
        if (servedAvatarSize != null) 'avatarSize': servedAvatarSize,
        if (servedRings != null) 'rings': Map<String, Object?>.of(servedRings!),
        if (servedAvatarRingColor != null) 'avatarRingColor': servedAvatarRingColor,
        if (servedButtonStyle != null) 'buttonStyle': servedButtonStyle,
        if (servedButtonShape != null) 'buttonShape': servedButtonShape,
        if (servedButtonSize != null) 'buttonSize': servedButtonSize,
        if (servedButtonLabels != null) 'buttonLabels': servedButtonLabels,
        if (servedActions != null) 'actions': <String, Object?>{for (final e in servedActions!.entries) e.key: e.value.toJson()},
        if (servedVisualizer != null) 'visualizer': servedVisualizer,
        if (servedVisualizerColor != null) 'visualizerColor': servedVisualizerColor,
        if (servedVisualizerSensitivity != null) 'visualizerSensitivity': servedVisualizerSensitivity,
        if (servedCaptionStyle != null) 'captionStyle': servedCaptionStyle,
        if (servedCaptionPosition != null) 'captionPosition': servedCaptionPosition,
        if (servedCaptionFill != null) 'captionFill': servedCaptionFill,
        if (servedCaptionFillAlpha != null) 'captionFillAlpha': servedCaptionFillAlpha,
        if (servedNameSize != null) 'nameSize': servedNameSize,
        if (servedNameWeight != null) 'nameWeight': servedNameWeight,
        if (servedStatusSize != null) 'statusSize': servedStatusSize,
        if (servedStatusWeight != null) 'statusWeight': servedStatusWeight,
        if (servedStates != null) 'states': <String, Object?>{for (final e in servedStates!.entries) e.key: e.value.toJson()},
      };
}

/// One note of a ring: a frequency (0 is a rest) for a duration.
class RingNote {
  const RingNote(this.hz, this.ms);

  final double hz;
  final int ms;

  Map<String, Object?> toJson() => <String, Object?>{'hz': hz, 'ms': ms};
}

/// A RING EVERY SDK PLAYS THE SAME (contract/DESIGN.md → `ringtones`): the
/// notes once, then [pauseMs] of silence, until the call is answered, declined
/// or stops ringing — each note a [wave] at [gain] (0–1 of full scale), with a
/// 10 ms rise and a 40 ms fall inside it. `call.ringtone` "system" is the
/// phone's own ring. For an app drawing its own call screen
/// (`GraineCallScreen.app`): the SDK's call screens play these themselves.
class Ringtone {
  const Ringtone({required this.label, required this.wave, required this.gain, required this.notes, required this.pauseMs});

  final String label;

  /// `sine` or `triangle`.
  final String wave;
  final double gain;
  final List<RingNote> notes;
  final int pauseMs;

  /// The rings by their `call.ringtone` names.
  static const Map<String, Ringtone> all = <String, Ringtone>{
    // Two rising notes, twice: E5 → B5.
    'graine': Ringtone(
      label: 'Graine',
      wave: 'sine',
      gain: 0.5,
      notes: <RingNote>[RingNote(659.25, 150), RingNote(987.77, 230), RingNote(0, 110), RingNote(659.25, 150), RingNote(987.77, 230)],
      pauseMs: 1500,
    ),
    // A low, rounded pair: C5 → G5, slower and quieter.
    'soft': Ringtone(
      label: 'Soft',
      wave: 'triangle',
      gain: 0.35,
      notes: <RingNote>[RingNote(523.25, 420), RingNote(783.99, 560)],
      pauseMs: 2000,
    ),
  };

  Map<String, Object?> toJson() => <String, Object?>{
        'label': label,
        'wave': wave,
        'gain': gain,
        'notes': <Object?>[for (final n in notes) n.toJson()],
        'pauseMs': pauseMs,
      };
}

/// EVERYTHING A RENDERER NEEDS for one scheme, as flat numbers and #RRGGBB
/// strings — the `ThemeTokens` of contract/DESIGN.md, key for key.
class ThemeTokens {
  const ThemeTokens({
    this.v = 1,
    required this.preset,
    required this.scheme,
    required this.colors,
    required this.font,
    required this.shape,
    required this.spacing,
    required this.elevation,
    required this.motion,
    required this.icons,
    this.glass,
    required this.bubbles,
    this.chrome = 'none',
    this.servedChat,
    this.servedCall,
  });

  final int v;
  final String preset;

  /// "light" or "dark".
  final String scheme;
  final ThemeColors colors;
  final ThemeFont font;
  final ThemeShape shape;
  final ThemeSpacing spacing;
  final ThemeElevation elevation;
  final ThemeMotion motion;
  final ThemeIcons icons;

  /// Null: opaque surfaces.
  final ThemeGlass? glass;

  /// One of [Design.bubbleStyles].
  final String bubbles;

  /// One of [Design.chromes]: "window" opens the chat window, the caption
  /// card and every component card as desktop windows (`WindowChrome` has
  /// the numbers); "none" — and an older server that never says — is a
  /// plain surface.
  final String chrome;

  /// The chat window's tokens exactly as the session carried them; null from
  /// a server that predates them. Draw from [chat].
  final ThemeChat? servedChat;

  /// The call screen's tokens exactly as the session carried them; null from
  /// a server that predates them. Draw from [call].
  final ThemeCall? servedCall;

  bool get dark => scheme == 'dark';

  /// The design opens its surfaces as desktop windows.
  bool get window => chrome == 'window';

  /// The chat window's tokens — the session's, else the window as it was
  /// drawn before they existed.
  ThemeChat get chat =>
      servedChat ?? ThemeChat.fallback(colors, dark: dark, hasGlyph: icons.launcher != null);

  /// The call screen's tokens — the session's, else the fixed dark screen (and its look, derived).
  ThemeCall get call => servedCall ?? ThemeCall.fallback(colors, weights: font.weights);

  /// One scheme's tokens. [scheme] is the slot they arrived in, used when the
  /// tokens do not say. Null when [raw] is not an object with a `colors` object
  /// in it — too little to call a design.
  static ThemeTokens? fromJson(Object? raw, {String scheme = 'light'}) {
    final r = Js.asMap(raw);
    if (r == null || Js.asMap(r['colors']) == null) return null;
    final slot = scheme == 'dark' ? 'dark' : 'light';
    final said = _pick(r['scheme'], const <String>['light', 'dark']) ?? slot;
    final d = said == 'dark' ? _Fallback.dark : _Fallback.light;
    final preset = r['preset'] is String ? (r['preset']! as String).trim() : '';
    final v = Js.finite(r['v']);
    final colors = ThemeColors.fromJson(Js.asMap(r['colors'])!, d.colors);
    final icons = ThemeIcons.fromJson(r['icons'], d.icons);
    final chat = Js.asMap(r['chat']);
    final call = Js.asMap(r['call']);
    final font = ThemeFont.fromJson(r['font'], d.font);
    return ThemeTokens(
      v: v == null ? 1 : v.round(),
      preset: preset.isEmpty ? d.preset : preset,
      scheme: said,
      colors: colors,
      font: font,
      shape: ThemeShape.fromJson(r['shape'], d.shape),
      spacing: ThemeSpacing.fromJson(r['spacing'], d.spacing),
      elevation: ThemeElevation.fromJson(r['elevation'], d.elevation),
      motion: ThemeMotion.fromJson(r['motion'], d.motion),
      icons: icons,
      glass: r.containsKey('glass') ? ThemeGlass.fromJson(r['glass']) : d.glass,
      bubbles: _pick(r['bubbles'], Design.bubbleStyles) ?? d.bubbles,
      chrome: _pick(r['chrome'], Design.chromes) ?? d.chrome,
      servedChat: chat == null
          ? null
          : ThemeChat.fromJson(chat, ThemeChat.fallback(colors, dark: said == 'dark', hasGlyph: icons.launcher != null)),
      servedCall: call == null
          ? null
          : ThemeCall.fromJson(call, ThemeCall.fallback(colors, weights: font.weights), weights: font.weights),
    );
  }

  /// The tokens as the session carries them — what [fromJson] read, key for key.
  Map<String, Object?> toJson() => <String, Object?>{
        'v': v,
        'preset': preset,
        'scheme': scheme,
        'colors': colors.toJson(),
        'font': font.toJson(),
        'shape': shape.toJson(),
        'spacing': spacing.toJson(),
        'elevation': elevation.toJson(),
        'motion': motion.toJson(),
        'icons': icons.toJson(),
        'glass': glass?.toJson(),
        'bubbles': bubbles,
        'chrome': chrome,
        // Only what was served: an older session read back is what it said.
        if (servedChat != null) 'chat': servedChat!.toJson(),
        if (servedCall != null) 'call': servedCall!.toJson(),
      };
}

/// THE SESSION'S `design`: the brand's config and both token sets.
class ResolvedDesign {
  const ResolvedDesign({required this.config, required this.light, required this.dark});

  /// As served. Only `scheme` is read here; the rest is the dashboard's
  /// record of what was chosen, already applied to the tokens.
  final Map<String, Object?> config;
  final ThemeTokens light;
  final ThemeTokens dark;

  /// "light" or "dark" when the brand fixed one; "auto" (the device) otherwise.
  String get scheme => _pick(config['scheme'], Design.schemes) ?? 'auto';

  /// WHICH SET TO DRAW. The brand's fixed scheme; else the device's — light
  /// when the device has not said ([deviceDark] null). A host's own [scheme]
  /// ("light", "dark" or "auto") wins over the brand's, as a widget's prop
  /// overrides the dashboard everywhere else.
  ThemeTokens pick({bool? deviceDark, String? scheme}) {
    final s = _pick(scheme, Design.schemes) ?? this.scheme;
    if (s == 'light') return light;
    if (s == 'dark') return dark;
    return deviceDark == true ? dark : light;
  }

  /// Null for anything that is not a design — an older server sends none,
  /// and the SDK then draws from `appearance` as before. When only one set
  /// is readable it stands in for both.
  static ResolvedDesign? fromJson(Object? raw) {
    final r = Js.asMap(raw);
    if (r == null) return null;
    final light = ThemeTokens.fromJson(r['light'], scheme: 'light');
    final dark = ThemeTokens.fromJson(r['dark'], scheme: 'dark');
    if (light == null && dark == null) return null;
    return ResolvedDesign(
      config: Js.asMap(r['config']) ?? <String, Object?>{},
      light: light ?? dark!,
      dark: dark ?? light!,
    );
  }

  Map<String, Object?> toJson() =>
      <String, Object?>{'config': config, 'light': light.toJson(), 'dark': dark.toJson()};
}

/// The rules every renderer shares: allowlists, colour, fonts, the launcher's
/// geometry and the glyph image URL.
abstract final class Design {
  static const List<String> schemes = <String>['auto', 'light', 'dark'];
  static const List<String> launcherShapes = <String>['circle', 'squircle', 'rounded-square', 'square', 'pill'];
  static const List<String> bubbleStyles = <String>['filled', 'outline', 'minimal'];
  static const List<String> iconStyles = <String>['outline', 'filled', 'duotone', 'sharp'];
  static const List<String> easings = <String>['standard', 'emphasized', 'spring', 'linear', 'none'];

  /// How a surface that holds content is framed: a plain surface, or a
  /// desktop window (contract/DESIGN.md, "Window chrome").
  static const List<String> chromes = <String>['none', 'window'];

  /// The launcher: 56 × 56 (a pill is 56 high and as wide as its label).
  static const double launcherSize = 56;

  /// The launcher's glyph or logo, as a fraction of its height.
  static const double launcherGlyphScale = 0.46;

  /// A squircle's corners, as a fraction of its size.
  static const double squircleScale = 0.3;

  /// Bumped whenever a glyph's path data changes, so a year-cached image can
  /// never show an old drawing under a new id. The same number as the React
  /// Native SDK's GLYPH_ASSET_VERSION.
  static const int glyphAssetVersion = 2;

  static const String defaultOrigin = 'https://www.graine.ai';

  static final RegExp _hex6 = RegExp(r'^#?([0-9a-fA-F]{6})$');
  static final RegExp _hex3 = RegExp(r'^#?([0-9a-fA-F]{3})$');

  /// "#RRGGBB" for anything that is a hex colour (#rgb, #rrggbb, with or
  /// without the "#"), else null.
  static String? normaliseHex(Object? value) {
    final s = Js.strOrEmpty(value).trim();
    final six = _hex6.firstMatch(s);
    if (six != null) return '#${six[1]!.toUpperCase()}';
    final three = _hex3.firstMatch(s);
    if (three != null) return '#${three[1]!.split('').map((String c) => '$c$c').join().toUpperCase()}';
    return null;
  }

  /// [a] a fraction [t] of the way to [b], channel by channel, as #RRGGBB —
  /// the design system's mixHex. A colour that does not read is black.
  static String mixHex(String a, String b, double t) {
    int ch(String hex, int i) => int.parse((normaliseHex(hex) ?? '#000000').substring(1 + i * 2, 3 + i * 2), radix: 16);
    final k = t.clamp(0.0, 1.0);
    final out = StringBuffer('#');
    for (var i = 0; i < 3; i++) {
      final v = Js.round(ch(a, i) + (ch(b, i) - ch(a, i)) * k).toInt().clamp(0, 255);
      out.write(v.toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    return out.toString();
  }

  /// THE APP'S OWN COPY OF A FAMILY, or null.
  ///
  /// "system" always means the platform's font. Any other family is the
  /// app's when it says it bundles it ([available], matched without regard
  /// to case, answered in the app's own spelling) — and that copy wins over
  /// the faces the SDK fetches (`DesignFonts`). Null otherwise.
  static String? fontFamily(String? family, Iterable<String> available) {
    final want = (family ?? '').trim().toLowerCase();
    if (want.isEmpty || want == 'system') return null;
    for (final f in available) {
      if (f.trim().toLowerCase() == want) return f.trim();
    }
    return null;
  }

  /// The launcher's corner radius at [height]: `circle` and `pill` fully
  /// round, `squircle` 30% of the size, `rounded-square` `radius.lg`, `square`
  /// `radius.sm` — never more than half the height.
  static double launcherRadius(String shape, ThemeRadius radius, double height) {
    final half = height / 2;
    double capped(double r) => r < 0 ? 0 : (r > half ? half : r);
    switch (shape) {
      case 'squircle':
        return capped(height * squircleScale);
      case 'rounded-square':
        return capped(radius.lg);
      case 'square':
        return capped(radius.sm);
      default: // circle, pill
        return half;
    }
  }

  /// WHERE AN APP FETCHES A LAUNCHER GLYPH AS AN IMAGE — built exactly as the
  /// React Native SDK's glyphUrl(): the id lower-cased, the colour upper-case
  /// hex without its "#", the size clamped to 16–512 PHYSICAL pixels (logical
  /// size × the screen's scale, so the image is sharp on every density), the
  /// stroke clamped to 0.5–4 in quarter steps, `v` the asset version.
  static String glyphUrl(String? origin, String id, String color, num sizePx, [num stroke = 2]) {
    final i = id.trim().toLowerCase();
    final c = normaliseHex(color) ?? '#FFFFFF';
    // `Number(x) || fallback`: zero and NaN take the fallback, as they do there.
    final rawSize = sizePx.toDouble();
    final wantSize = (rawSize == 0 || rawSize.isNaN) ? 96.0 : rawSize;
    final size = Js.round(wantSize.clamp(16.0, 512.0));
    final rawStroke = stroke.toDouble();
    final wantStroke = (rawStroke == 0 || rawStroke.isNaN) ? 2.0 : rawStroke;
    final w = Js.round(wantStroke.clamp(0.5, 4.0) * 4) / 4;
    var base = (origin == null || origin.isEmpty) ? defaultOrigin : origin;
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return '$base/api/embed/glyph?id=${Uri.encodeComponent(i)}&c=${c.substring(1)}'
        '&s=${Js.number(size)}&w=${Js.number(w)}&v=$glyphAssetVersion';
  }
}

// ── parsing helpers ─────────────────────────────────────────────────────────

/// A finite number from JSON, clamped; [fallback] for anything else.
double _num(Object? v, double fallback, {double? min, double? max}) {
  final d = Js.finite(v);
  if (d == null) return fallback;
  if (min != null && d < min) return min;
  if (max != null && d > max) return max;
  return d;
}

String? _pick(Object? v, List<String> allowed) {
  final s = Js.strOrEmpty(v).trim().toLowerCase();
  return allowed.contains(s) ? s : null;
}

/// WHAT AN UNREADABLE TOKEN DRAWS: Graine Classic, the look every widget had
/// before designs — the same palettes the SDK draws with no design at all.
abstract final class _Fallback {
  static const ThemeFont _font = ThemeFont(
    body: 'system',
    heading: 'system',
    scale: ThemeFontScale(caption: 12, body: 15, title: 17, display: 22),
    weights: ThemeFontWeights(body: 400, strong: 600, title: 600),
    letterSpacing: ThemeFontPair(body: 0, title: -0.01),
    lineHeight: ThemeFontPair(body: 1.45, title: 1.25),
  );
  static const ThemeShape _shape =
      ThemeShape(radius: ThemeRadius(sm: 8, md: 12, lg: 18, xl: 24), borderWidth: 1, launcher: 'circle');
  static const ThemeSpacing _spacing = ThemeSpacing(unit: 4, cardPadding: 14, gap: 10);
  static const ThemeShadow _floating = ThemeShadow(y: 8, blur: 24, spread: 0, opacity: 0.16, color: '#000000');
  static const ThemeMotion _motion = ThemeMotion(durationMs: 200, easing: 'standard', bounce: 0);
  // The classic glyph by id alone: its path data lives in the design system,
  // and a copy here would go stale. With no path, the launcher shows it as an
  // image, which the glyph endpoint always draws current.
  static const ThemeIcons _icons = ThemeIcons(
    style: 'outline',
    stroke: 2,
    launcher: LauncherGlyph(id: 'waveform', path: '', stroke: true),
  );

  static const ThemeTokens light = ThemeTokens(
    preset: 'graine-classic',
    scheme: 'light',
    colors: ThemeColors(
      background: '#F7F7F5', surface: '#FFFFFF', surfaceRaised: '#FFFFFF', text: '#101318', textMuted: '#5F6672',
      border: '#E5E4E0', accent: '#318CE7', onAccent: '#FFFFFF', accentSoft: '#E6F1FC', success: '#16A34A',
      warning: '#B45309', danger: '#DC2626', userBubble: '#318CE7', userBubbleText: '#FFFFFF',
      agentBubble: '#F1F1EF', agentBubbleText: '#101318', scrim: '#000000',
    ),
    font: _font,
    shape: _shape,
    spacing: _spacing,
    elevation: ThemeElevation(
      card: ThemeShadow(y: 2, blur: 8, spread: 0, opacity: 0.08, color: '#000000'),
      floating: _floating,
    ),
    motion: _motion,
    icons: _icons,
    bubbles: 'filled',
  );

  static const ThemeTokens dark = ThemeTokens(
    preset: 'graine-classic',
    scheme: 'dark',
    colors: ThemeColors(
      background: '#0E0F11', surface: '#17181B', surfaceRaised: '#1F2024', text: '#F5F5F4', textMuted: '#A0A5AE',
      border: '#2C2E33', accent: '#318CE7', onAccent: '#FFFFFF', accentSoft: '#1D3248', success: '#22C55E',
      warning: '#F59E0B', danger: '#F87171', userBubble: '#318CE7', userBubbleText: '#FFFFFF',
      agentBubble: '#23252A', agentBubbleText: '#F5F5F4', scrim: '#000000',
    ),
    font: _font,
    shape: _shape,
    spacing: _spacing,
    elevation: ThemeElevation(
      card: ThemeShadow(y: 2, blur: 8, spread: 0, opacity: 0.16, color: '#000000'),
      floating: _floating,
    ),
    motion: _motion,
    icons: _icons,
    bubbles: 'filled',
  );
}
