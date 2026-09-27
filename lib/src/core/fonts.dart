/// THE DESIGN'S TYPEFACES — which faces a design draws with, and where Graine
/// serves each one (contract/DESIGN.md, "Fonts").
///
/// A brand picks a typeface in the dashboard and expects the phone to draw
/// it, with nothing in the app naming a font. So the SDK works out, from the
/// session's tokens alone, exactly which faces the design uses — the body
/// family at its body and strong weights, the heading family at its title
/// and strong weights, in light and in dark — and the nearest weight each
/// family really has. The same answer the React Native SDK gives for every
/// design in contract/design.json, face for face.
///
/// Pure: the widget layer fetches the files and registers them.
library;

import 'design.dart';

/// One face of one family, as the SDK registers it.
class DesignFontFace {
  const DesignFontFace({required this.family, required this.weight, required this.name, required this.url});

  /// The family as the dashboard spells it ("IBM Plex Sans").
  final String family;

  /// The weight the family really has, nearest the one the design asked for.
  final int weight;

  /// The family name it is registered under: `Graine-IBMPlexSans-600`.
  final String name;

  /// Where Graine serves the TTF.
  final String url;

  /// `family|weight` — what a loaded face is looked up by.
  String get key => DesignFonts.key(family, weight);

  Map<String, Object?> toJson() => <String, Object?>{'family': family, 'weight': weight, 'name': name, 'url': url};

  @override
  bool operator ==(Object other) =>
      other is DesignFontFace &&
      other.family == family &&
      other.weight == weight &&
      other.name == name &&
      other.url == url;

  @override
  int get hashCode => Object.hash(family, weight, name, url);

  @override
  String toString() => 'DesignFontFace($name, $url)';
}

abstract final class DesignFonts {
  /// Bumped when a file behind /api/embed/font changes, so no cache — the
  /// server's year-long one or this SDK's own on disk — keeps the old one.
  /// The same number as the React Native SDK's FONT_ASSET_VERSION.
  static const int assetVersion = 1;

  /// EVERY FAMILY THE DASHBOARD OFFERS, and the weights each really has.
  ///
  /// A family missing here is one this build has no files for: it is drawn
  /// in the system font, never fetched. The tests hold this table to
  /// contract/design.json → `fontWeights`, so it cannot drift from the files
  /// the server serves.
  static const Map<String, List<int>> weights = <String, List<int>>{
    'Inter': <int>[100, 200, 300, 400, 500, 600, 700, 800, 900],
    'Roboto': <int>[100, 200, 300, 400, 500, 600, 700, 800, 900],
    'Geist': <int>[100, 200, 300, 400, 500, 600, 700, 800, 900],
    'IBM Plex Sans': <int>[100, 200, 300, 400, 500, 600, 700],
    'IBM Plex Sans Devanagari': <int>[100, 200, 300, 400, 500, 600, 700],
    'DM Sans': <int>[100, 200, 300, 400, 500, 600, 700, 800, 900],
    'Noto Sans': <int>[100, 200, 300, 400, 500, 600, 700, 800, 900],
    'Noto Sans Devanagari': <int>[100, 200, 300, 400, 500, 600, 700, 800, 900],
    'Noto Sans Tamil': <int>[100, 200, 300, 400, 500, 600, 700, 800, 900],
    'Mukta': <int>[200, 300, 400, 500, 600, 700, 800],
    'Hind': <int>[300, 400, 500, 600, 700],
    'Anek Devanagari': <int>[100, 200, 300, 400, 500, 600, 700, 800],
    'Poppins': <int>[100, 200, 300, 400, 500, 600, 700, 800, 900],
    'Baloo 2': <int>[400, 500, 600, 700, 800],
    'Nunito': <int>[200, 300, 400, 500, 600, 700, 800, 900],
    'Atkinson Hyperlegible Next': <int>[200, 300, 400, 500, 600, 700, 800],
    'Source Serif 4': <int>[200, 300, 400, 500, 600, 700, 800, 900],
    'Newsreader': <int>[200, 300, 400, 500, 600, 700, 800],
    'Fraunces': <int>[100, 200, 300, 400, 500, 600, 700, 800, 900],
    'Playfair Display': <int>[400, 500, 600, 700, 800, 900],
    'Tiro Devanagari Hindi': <int>[400],
    'Noto Serif Devanagari': <int>[100, 200, 300, 400, 500, 600, 700, 800, 900],
    'Martel': <int>[200, 300, 400, 600, 700, 800, 900],
    'JetBrains Mono': <int>[100, 200, 300, 400, 500, 600, 700, 800],
  };

  static final RegExp _notLetterOrDigit = RegExp('[^A-Za-z0-9]');

  /// `family|weight`.
  static String key(String family, int weight) => '$family|$weight';

  /// The weight [available] has nearest [want]; on a tie, the heavier —
  /// a 500 asked of a family with 400 and 600 is drawn at 600. Null when
  /// there is none.
  static int? nearestWeight(List<int> available, int want) {
    if (available.isEmpty) return null;
    var best = available.first;
    for (final w in available) {
      final d = (w - want).abs();
      final bd = (best - want).abs();
      if (d < bd || (d == bd && w > best)) best = w;
    }
    return best;
  }

  /// The family as this build spells it — matched as written, then without
  /// regard to case — or null for "system", an empty value, or a family this
  /// build has no files for.
  static String? canonicalFamily(String? family) {
    final want = (family ?? '').trim();
    if (want.isEmpty || want.toLowerCase() == 'system') return null;
    if (weights.containsKey(want)) return want;
    final lower = want.toLowerCase();
    for (final k in weights.keys) {
      if (k.toLowerCase() == lower) return k;
    }
    return null;
  }

  /// The name a face is registered under: `Graine-` + the family with only
  /// its letters and digits + `-` + the weight. Every SDK uses the same one.
  static String faceName(String family, int weight) => 'Graine-${family.replaceAll(_notLetterOrDigit, '')}-$weight';

  /// Where Graine serves one face: `<origin>/api/embed/font?f=<family>&w=<weight>&v=<version>`
  /// — the family encoded as JavaScript's encodeURIComponent does it, which
  /// is exactly Dart's [Uri.encodeComponent].
  static String url(String? origin, String family, int weight) {
    var base = (origin == null || origin.trim().isEmpty) ? Design.defaultOrigin : origin.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return '$base/api/embed/font?f=${Uri.encodeComponent(family)}&w=$weight&v=$assetVersion';
  }

  /// THE FACE TO DRAW [family] AT [weight] WITH, or null when the family is
  /// the system font or one this build has no files for.
  static DesignFontFace? faceFor(String? family, int weight, {String? origin}) {
    final canonical = canonicalFamily(family);
    if (canonical == null) return null;
    final w = nearestWeight(weights[canonical]!, weight);
    if (w == null) return null;
    return DesignFontFace(family: canonical, weight: w, name: faceName(canonical, w), url: url(origin, canonical, w));
  }

  /// The faces one token set draws with: the body family at `weights.body`
  /// and `weights.strong`, the heading family at `weights.title` and
  /// `weights.strong` — each once.
  static List<DesignFontFace> facesFor(ThemeTokens t, {String? origin}) {
    final out = <String, DesignFontFace>{};
    void add(String family, int weight) {
      final f = faceFor(family, weight, origin: origin);
      if (f != null) out.putIfAbsent(f.key, () => f);
    }

    final f = t.font;
    add(f.body, f.weights.body);
    add(f.body, f.weights.strong);
    add(f.heading, f.weights.title);
    add(f.heading, f.weights.strong);
    return out.values.toList();
  }

  /// Every face a design can draw with, in either scheme — what the SDK
  /// fetches when a session carries it, so a switch to dark never waits.
  static List<DesignFontFace> facesForDesign(ResolvedDesign design, {String? origin}) {
    final out = <String, DesignFontFace>{};
    for (final t in <ThemeTokens>[design.light, design.dark]) {
      for (final f in facesFor(t, origin: origin)) {
        out.putIfAbsent(f.key, () => f);
      }
    }
    return out.values.toList();
  }
}
