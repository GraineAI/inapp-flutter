import 'context.dart';
import 'js.dart';
import 'protocol.dart';

/// HOW A COMPONENT LOOKS — chosen on the component in the dashboard, carried
/// with it to the agent, drawn by the SDK. Only allowlisted keys and values
/// survive [Widgets.normaliseStyle]: an unknown preset draws Cards, never
/// nothing. Strings rather than enums on purpose: these are the wire's own
/// words, the same the dashboard and the other SDKs use.
class WidgetStyle {
  const WidgetStyle({
    this.preset,
    this.imageSize,
    this.density,
    this.button,
    this.facts,
    this.columns,
    this.surface,
    this.radius,
    this.accent,
    this.platform,
    this.select,
    this.maxSelect,
  });

  final String? preset;
  final String? imageSize;
  final String? density;
  final String? button;
  final bool? facts;
  final int? columns;
  final String? surface;
  final int? radius;
  final String? accent;
  final String? platform;
  final String? select;
  final int? maxSelect;

  /// The keys that are set, as the RN SDK's normalised object has them.
  Map<String, Object?> toMap() => <String, Object?>{
        if (preset != null) 'preset': preset,
        if (imageSize != null) 'imageSize': imageSize,
        if (density != null) 'density': density,
        if (button != null) 'button': button,
        if (facts != null) 'facts': facts,
        if (columns != null) 'columns': columns,
        if (surface != null) 'surface': surface,
        if (radius != null) 'radius': radius,
        if (accent != null) 'accent': accent,
        if (platform != null) 'platform': platform,
        if (select != null) 'select': select,
        if (maxSelect != null) 'maxSelect': maxSelect,
      };

  @override
  bool operator ==(Object other) =>
      other is WidgetStyle && deepEquals(other.toMap(), toMap());

  @override
  int get hashCode => deepHash(toMap());
}

/// The effective look: the preset's defaults, then the knobs on top.
class WidgetLook {
  const WidgetLook({
    required this.preset,
    required this.imageSize,
    required this.density,
    required this.button,
    required this.facts,
    required this.columns,
    required this.surface,
    this.radius,
    this.accent,
    required this.platform,
    required this.select,
    required this.maxSelect,
  });

  final String preset;
  final String imageSize;
  final String density;
  final String button;
  final bool facts;
  final int columns;

  /// The surface to draw on, "auto" already resolved for the kind.
  final String surface;
  final int? radius;
  final String? accent;

  /// As chosen; "auto" is resolved by the renderer, which knows the phone.
  final String platform;
  final String select;
  final int maxSelect;

  Map<String, Object?> toMap() => <String, Object?>{
        'preset': preset,
        'imageSize': imageSize,
        'density': density,
        'button': button,
        'facts': facts,
        'columns': columns,
        'surface': surface,
        if (radius != null) 'radius': radius,
        if (accent != null) 'accent': accent,
        'platform': platform,
        'select': select,
        'maxSelect': maxSelect,
      };
}

/// WHAT A PLATFORM'S DESIGN GRAMMAR CHANGES — the shapes people on that phone
/// already know. The colours stay the brand's. [radius] is used only for an
/// explicit platform; under "auto" the Appearance radius wins.
class PlatformGrammar {
  const PlatformGrammar({
    required this.radius,
    required this.chipRadius,
    required this.buttonRadius,
    required this.pillButtons,
    required this.separatorInset,
    required this.grabberWidth,
    required this.grabberHeight,
    required this.titleWeight,
    required this.padBoost,
    required this.chipOutlined,
  });

  final int radius;
  final int chipRadius;
  final int buttonRadius;
  final bool pillButtons;
  final int separatorInset;
  final int grabberWidth;
  final int grabberHeight;

  /// CSS weight: 500, 600 or 700.
  final int titleWeight;
  final int padBoost;
  final bool chipOutlined;
}

/// WHAT THE APP DOES WHEN THE CUSTOMER TAPS, beyond telling the agent: an
/// in-app action (or a path for the one navigate handler), with arguments
/// filled from the tapped item. Empty when the component names neither.
class WidgetSelectAction {
  const WidgetSelectAction({this.path, this.action, this.args, this.say});

  final String? path;
  final String? action;
  final Map<String, String>? args;
  final String? say;

  bool get isEmpty => path == null && action == null;

  Map<String, Object?> toMap() => <String, Object?>{
        if (action != null) 'action': action,
        if (path != null) 'path': path,
        if (args != null) 'args': args,
        if (say != null) 'say': say,
      };
}

/// One tap's in-app call: the action to run and what to run it with.
class SelectCall {
  const SelectCall(this.name, this.args);
  final String name;
  final Map<String, String> args;

  @override
  bool operator ==(Object other) =>
      other is SelectCall && other.name == name && deepEquals(other.args, args);

  @override
  int get hashCode => Object.hash(name, deepHash(args));

  @override
  String toString() => 'SelectCall($name, $args)';
}

/// The component rules, one function each — ports of the RN SDK's protocol.ts.
abstract final class Widgets {
  static const List<String> presets = <String>['gallery', 'cards', 'list', 'spotlight', 'compact'];
  static const List<String> imageSizes = <String>['small', 'medium', 'large'];
  static const List<String> densities = <String>['comfortable', 'compact'];
  static const List<String> buttons = <String>['filled', 'outline', 'row'];
  static const List<String> surfaceChoices = <String>['auto', 'screen', 'sheet', 'card'];
  static const List<String> platforms = <String>['auto', 'ios', 'material', 'oneui'];
  static const List<String> selects = <String>['one', 'many'];
  static const int maxSelectDefault = 3;
  static const String defaultPreset = 'cards';

  /// The one handler an app registers so the dashboard can open any screen.
  static const String navigateAction = 'open_screen';
  static const int selectArgMax = 10;
  static const int selectValueMax = 200;

  /// Once the loader is on screen it stays this long, so it reads as loading
  /// rather than a glitch.
  static const int minLoaderMs = 450;

  /// How long a "component coming" loader may stand with nothing arriving.
  static const int pendingWidgetMs = 12000;

  /// How long the answered line says "thinking" while the agent has not started.
  static const int awaitingReplyMs = 12000;

  static const Map<String, String> _surface = <String, String>{
    'product_list': 'screen',
    'products': 'screen',
    'plan_comparison': 'sheet',
    'choices': 'sheet',
    'quick_actions': 'sheet',
    'calendar_slots': 'sheet',
    'info_card': 'card',
  };

  /// Where a component goes: "screen", "sheet" or "card". An unknown kind is
  /// a card, because what is drawn for it is one fallback sentence.
  static String surface(String? kind) =>
      _surface[(kind ?? '').trim().toLowerCase()] ?? 'card';

  static String? _pick(Object? v, List<String> allowed) {
    final s = Js.strOrEmpty(v).trim().toLowerCase();
    return allowed.contains(s) ? s : null;
  }

  static final RegExp _hex6 = RegExp(r'^#[0-9a-fA-F]{6}$');

  /// Only the keys and values the renderers read. Anything else is dropped.
  static WidgetStyle normaliseStyle(Object? raw) {
    final r = Js.asMap(raw);
    if (r == null) return const WidgetStyle();
    final c = r['columns'];
    final cn = Js.finite(c);
    final columns = (cn == 2.0 || c == '2')
        ? 2
        : (cn == 1.0 || c == '1')
            ? 1
            : null;
    final rawAccent = r['accent'];
    String? accent;
    if (rawAccent is String && _hex6.hasMatch(rawAccent.trim())) {
      accent = rawAccent.trim().toUpperCase();
    }
    final radius = Js.finite(r['radius']);
    final maxSelect = Js.finite(r['maxSelect']);
    final facts = r['facts'];
    return WidgetStyle(
      preset: _pick(r['preset'], presets),
      imageSize: _pick(r['imageSize'], imageSizes),
      density: _pick(r['density'], densities),
      button: _pick(r['button'], buttons),
      facts: facts is bool ? facts : null,
      columns: columns,
      surface: _pick(r['surface'], surfaceChoices),
      radius: radius == null ? null : Js.round(radius).clamp(0.0, 24.0).toInt(),
      accent: accent,
      platform: _pick(r['platform'], platforms),
      select: _pick(r['select'], selects),
      maxSelect: maxSelect == null ? null : Js.round(maxSelect).clamp(2.0, 8.0).toInt(),
    );
  }

  static const Map<String, (String, String)> _presetDefaults = <String, (String, String)>{
    'gallery': ('large', 'filled'),
    'cards': ('medium', 'filled'),
    'list': ('small', 'row'),
    'spotlight': ('large', 'filled'),
    'compact': ('small', 'outline'),
  };

  static WidgetLook resolveLook(WidgetStyle? style, String? kind) {
    final s = style ?? const WidgetStyle();
    final preset = (s.preset != null && presets.contains(s.preset)) ? s.preset! : defaultPreset;
    final d = _presetDefaults[preset]!;
    return WidgetLook(
      preset: preset,
      imageSize: s.imageSize ?? d.$1,
      density: s.density ?? 'comfortable',
      button: s.button ?? d.$2,
      facts: s.facts ?? true,
      columns: ((preset == 'gallery' || preset == 'cards') && s.columns == 2) ? 2 : 1,
      surface: (s.surface != null && s.surface != 'auto') ? s.surface! : surface(kind),
      radius: s.radius,
      accent: s.accent,
      platform: s.platform ?? 'auto',
      select: s.select ?? 'one',
      maxSelect: s.maxSelect ?? maxSelectDefault,
    );
  }

  static const Map<String, PlatformGrammar> grammar = <String, PlatformGrammar>{
    'ios': PlatformGrammar(
        radius: 12, chipRadius: 8, buttonRadius: 12, pillButtons: false, separatorInset: 16,
        grabberWidth: 36, grabberHeight: 5, titleWeight: 600, padBoost: 0, chipOutlined: false),
    'material': PlatformGrammar(
        radius: 16, chipRadius: 8, buttonRadius: 20, pillButtons: true, separatorInset: 0,
        grabberWidth: 32, grabberHeight: 4, titleWeight: 500, padBoost: 0, chipOutlined: true),
    'oneui': PlatformGrammar(
        radius: 26, chipRadius: 999, buttonRadius: 999, pillButtons: true, separatorInset: 0,
        grabberWidth: 40, grabberHeight: 4, titleWeight: 700, padBoost: 2, chipOutlined: false),
  };

  static final RegExp _samsung = RegExp('samsung', caseSensitive: false);

  /// "auto" → the phone's own grammar: Material on Android, One UI on a
  /// Samsung, Apple's on iOS (and on anything unknown).
  static String resolvePlatform(String? platform, String? os, [String? manufacturer]) {
    if (platform != null && platform != 'auto') return platform;
    if (os == 'android') return _samsung.hasMatch(manufacturer ?? '') ? 'oneui' : 'material';
    return 'ios';
  }

  /// The sentence the agent hears when several were chosen — and the user's
  /// own bubble in a text chat: the button's label as written, then the names
  /// ("Taken: Morning and Evening"). Never the label read as a verb. No label:
  /// the names alone.
  static String manySummary(List<String> titles, [String label = 'Compare']) {
    final names = titles.map((String t) => t.trim()).where((String t) => t.isNotEmpty).toList();
    if (names.isEmpty) return '';
    final list = names.length == 1
        ? names.first
        : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
    final lead = label.trim();
    return lead.isEmpty ? list : '$lead: $list';
  }

  static final RegExp _actionName = RegExp(r'^[a-z][a-z0-9_]{0,63}$');

  static String _take(String s, int n) => s.length <= n ? s : s.substring(0, n);

  static WidgetSelectAction normaliseSelectAction(Object? raw) {
    final r = Js.asMap(raw);
    if (r == null) return const WidgetSelectAction();
    final nameRaw = Js.strOrEmpty(r['action']).trim().toLowerCase();
    final name = _actionName.hasMatch(nameRaw) ? nameRaw : null;
    final p = r['path'];
    String? path;
    if (p is String) {
      final t = _take(p.trim(), selectValueMax);
      if (t.isNotEmpty) path = t;
    }
    Map<String, String>? args;
    final a = Js.asMap(r['args']);
    if (a != null) {
      final out = <String, String>{};
      a.forEach((String k, Object? v) {
        final key = k.trim();
        if (key.isEmpty || out.length >= selectArgMax) return;
        // `typeof v === "object"` — null, arrays and objects are not arguments.
        if (v == null || v is Map || v is List) return;
        out[key] = _take(Js.str(v), selectValueMax);
      });
      if (out.isNotEmpty) args = out;
    }
    final sy = r['say'];
    String? say;
    if (sy is String) {
      final t = _take(sy.trim(), selectValueMax);
      if (t.isNotEmpty) say = t;
    }
    // Arguments alone are nothing: a half-configured component must not look configured.
    return (name != null || path != null)
        ? WidgetSelectAction(path: path, action: name, args: args, say: say)
        : const WidgetSelectAction();
  }

  static final RegExp _placeholder = RegExp(r'\{([a-zA-Z_][a-zA-Z0-9_]*)\}');

  /// Fill {id}/{title}/… from the tapped item. An unknown placeholder becomes
  /// empty, never literal.
  static String fillSelectTemplate(String template, Map<String, Object?> item) =>
      template.replaceAllMapped(_placeholder, (Match m) => Js.strOrEmpty(item[m[1]]));

  static Map<String, String> fillSelectArgs(Map<String, String>? args, Map<String, Object?> item) =>
      <String, String>{
        if (args != null)
          for (final e in args.entries) e.key: fillSelectTemplate(e.value, item),
      };

  /// The action to run for one tap: an explicit action wins, a path goes to
  /// [navigateAction], and the path travels as an argument either way.
  static SelectCall? selectCall(WidgetSelectAction? onSelect, Map<String, Object?> item) {
    final s = onSelect;
    if (s == null || (s.action == null && s.path == null)) return null;
    final args = fillSelectArgs(s.args, item);
    if (s.path != null) args['path'] = fillSelectTemplate(s.path!, item);
    return SelectCall(s.action ?? navigateAction, args);
  }

  static final RegExp _imageKey = RegExp(
    r'^(image|imageurl|image_url|icon|iconurl|icon_url|logo|logourl|logo_url|photo|photourl|photo_url|thumbnail|thumbnailurl|thumbnail_url)$',
    caseSensitive: false,
  );

  static Object? _resolveOne(Object? value, String base) {
    if (value is! String || !value.startsWith('/') || value.startsWith('//')) return value;
    return Protocol.trimTrailingSlashes(base) + value;
  }

  /// A root-relative picture ("/samples/car.png") is resolved against the
  /// agent's origin — the one place it could have come from. Only keys that
  /// name an image, top level and one level into a list; a copy, not an edit.
  static Map<String, Object?> resolveImages(Map<String, Object?> data, String baseUrl) {
    if (baseUrl.isEmpty) return data;
    final out = <String, Object?>{};
    data.forEach((String k, Object? v) {
      if (_imageKey.hasMatch(k)) {
        out[k] = _resolveOne(v, baseUrl);
      } else if (v is List) {
        out[k] = <Object?>[
          for (final row in v)
            if (row is Map)
              <String, Object?>{
                for (final e in row.entries)
                  e.key.toString(): _imageKey.hasMatch(e.key.toString())
                      ? _resolveOne(e.value, baseUrl)
                      : e.value,
              }
            else
              row,
        ];
      } else {
        out[k] = v;
      }
    });
    return out;
  }
}
