import 'js.dart';

/// Words for each moment a customer waits. Null means "use the default".
class LoaderText {
  const LoaderText({this.connecting, this.reconnecting, this.thinking, this.component});

  final String? connecting;
  final String? reconnecting;
  final String? thinking;
  final String? component;

  String? forMoment(String moment) {
    switch (moment) {
      case 'connecting':
        return connecting;
      case 'reconnecting':
        return reconnecting;
      case 'thinking':
        return thinking;
      case 'component':
        return component;
      default:
        return null;
    }
  }

  bool get isEmpty =>
      connecting == null && reconnecting == null && thinking == null && component == null;

  Map<String, Object?> toMap() => <String, Object?>{
        if (connecting != null) 'connecting': connecting,
        if (reconnecting != null) 'reconnecting': reconnecting,
        if (thinking != null) 'thinking': thinking,
        if (component != null) 'component': component,
      };
}

/// HOW WAITING LOOKS, as chosen in Embed & Widgets → Appearance. Allowlisted.
class LoaderStyle {
  const LoaderStyle({this.kind, this.color, this.size, this.speed, this.text, this.skeleton});

  final String? kind;

  /// "accent" or #RRGGBB.
  final String? color;
  final String? size;
  final String? speed;
  final LoaderText? text;
  final bool? skeleton;

  Map<String, Object?> toMap() => <String, Object?>{
        if (kind != null) 'kind': kind,
        if (color != null) 'color': color,
        if (size != null) 'size': size,
        if (speed != null) 'speed': speed,
        if (text != null) 'text': text!.toMap(),
        if (skeleton != null) 'skeleton': skeleton,
      };
}

/// The effective loader: numbers a renderer can use directly.
class LoaderLook {
  const LoaderLook({
    required this.kind,
    this.color,
    required this.px,
    required this.periodMs,
    required this.text,
    required this.skeleton,
  });

  final String kind;

  /// Null means "use the accent".
  final String? color;

  /// The mark's size, in logical pixels.
  final int px;

  /// One animation cycle.
  final int periodMs;

  /// Every moment filled in.
  final LoaderText text;
  final bool skeleton;
}

abstract final class Loaders {
  static const List<String> kinds = <String>['dots', 'pulse', 'ring', 'bars', 'mark'];
  static const List<String> sizes = <String>['small', 'medium', 'large'];
  static const List<String> speeds = <String>['calm', 'normal', 'quick'];
  static const List<String> moments = <String>['connecting', 'reconnecting', 'thinking', 'component'];
  static const String defaultKind = 'dots';
  static const int textMax = 40;
  static const LoaderText defaultText = LoaderText(
    connecting: 'Connecting…',
    reconnecting: 'Reconnecting…',
    thinking: 'Thinking…',
    component: 'Loading…',
  );
  static const Map<String, int> _px = <String, int>{'small': 14, 'medium': 20, 'large': 28};
  static const Map<String, int> _period = <String, int>{'calm': 1600, 'normal': 1100, 'quick': 700};

  static final RegExp _hex6 = RegExp(r'^#[0-9a-fA-F]{6}$');

  static String? _pick(Object? v, List<String> allowed) {
    final s = Js.strOrEmpty(v).trim().toLowerCase();
    return allowed.contains(s) ? s : null;
  }

  static LoaderStyle normalise(Object? raw) {
    final r = Js.asMap(raw);
    if (r == null) return const LoaderStyle();
    String? color;
    final c = r['color'];
    if (c is String) {
      final t = c.trim();
      if (t.toLowerCase() == 'accent') {
        color = 'accent';
      } else if (_hex6.hasMatch(t)) {
        color = t.toUpperCase();
      }
    }
    LoaderText? text;
    final t = Js.asMap(r['text']);
    if (t != null) {
      String? word(String m) {
        final v = t[m];
        if (v is! String) return null;
        var w = v.trim();
        if (w.length > textMax) w = w.substring(0, textMax);
        return w.isEmpty ? null : w;
      }

      final lt = LoaderText(
        connecting: word('connecting'),
        reconnecting: word('reconnecting'),
        thinking: word('thinking'),
        component: word('component'),
      );
      if (!lt.isEmpty) text = lt;
    }
    final sk = r['skeleton'];
    return LoaderStyle(
      kind: _pick(r['kind'], kinds),
      color: color,
      size: _pick(r['size'], sizes),
      speed: _pick(r['speed'], speeds),
      text: text,
      skeleton: sk is bool ? sk : null,
    );
  }

  /// The look for a raw `appearance.loader` value (anything; junk resolves to the default).
  static LoaderLook resolve(Object? raw) => resolveStyle(normalise(raw));

  static LoaderLook resolveStyle(LoaderStyle s) => LoaderLook(
        kind: s.kind ?? defaultKind,
        color: s.color == 'accent' ? null : s.color,
        px: _px[s.size ?? 'medium']!,
        periodMs: _period[s.speed ?? 'normal']!,
        text: LoaderText(
          connecting: s.text?.connecting ?? defaultText.connecting,
          reconnecting: s.text?.reconnecting ?? defaultText.reconnecting,
          thinking: s.text?.thinking ?? defaultText.thinking,
          component: s.text?.component ?? defaultText.component,
        ),
        skeleton: s.skeleton ?? false,
      );
}
