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

  bool get dark => scheme == 'dark';

  /// The design opens its surfaces as desktop windows.
  bool get window => chrome == 'window';

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
    return ThemeTokens(
      v: v == null ? 1 : v.round(),
      preset: preset.isEmpty ? d.preset : preset,
      scheme: said,
      colors: ThemeColors.fromJson(Js.asMap(r['colors'])!, d.colors),
      font: ThemeFont.fromJson(r['font'], d.font),
      shape: ThemeShape.fromJson(r['shape'], d.shape),
      spacing: ThemeSpacing.fromJson(r['spacing'], d.spacing),
      elevation: ThemeElevation.fromJson(r['elevation'], d.elevation),
      motion: ThemeMotion.fromJson(r['motion'], d.motion),
      icons: ThemeIcons.fromJson(r['icons'], d.icons),
      glass: r.containsKey('glass') ? ThemeGlass.fromJson(r['glass']) : d.glass,
      bubbles: _pick(r['bubbles'], Design.bubbleStyles) ?? d.bubbles,
      chrome: _pick(r['chrome'], Design.chromes) ?? d.chrome,
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
