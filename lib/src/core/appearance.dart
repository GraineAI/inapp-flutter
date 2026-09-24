import 'dart:math' as math;

import 'js.dart';

/// The dashboard's appearance, translated for a phone: see [Appearance.resolve].
class NativeAppearance {
  const NativeAppearance({
    required this.accent,
    required this.heading,
    this.logoUrl,
    required this.radius,
  });

  /// Always a valid "#rgb" or "#rrggbb".
  final String accent;

  /// The panel heading ("Talk to our AI assistant") — NOT the assistant's name.
  final String heading;

  /// Absolute, or null when no logo is set. The dashboard stores an S3 key, not a URL.
  final String? logoUrl;

  /// Corner rounding, clamped to what the host draws.
  final double radius;
}

/// The colours a component is drawn in, as #RRGGBB.
class WidgetPalette {
  const WidgetPalette({
    required this.surface,
    required this.border,
    required this.text,
    required this.muted,
    required this.onAccent,
    required this.mode,
  });

  final String surface;
  final String border;
  final String text;
  final String muted;

  /// Readable ON the accent — chosen by luminance, so a yellow accent still has a label.
  final String onAccent;

  /// "light" or "dark", after resolving "auto" against the device.
  final String mode;
}

abstract final class Appearance {
  static const String defaultAccent = '#318CE7';
  static const String defaultOrigin = 'https://www.graine.ai';
  static const double _radiusCeiling = 48;
  static final RegExp _hex = RegExp(r'^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$');
  static final RegExp _numeric = RegExp(r'^[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?$');

  /// A number, or nothing — never a coercion (`Number(null)` is 0, and an
  /// absent radius is not a choice of square corners).
  static double? _numericValue(Object? v) {
    if (v is num) {
      final d = v.toDouble();
      return d.isFinite ? d : null;
    }
    if (v is String) {
      final t = v.trim();
      if (t.isEmpty || !_numeric.hasMatch(t)) return null;
      final d = double.parse(t);
      return d.isInfinite ? null : d;
    }
    return null;
  }

  static double _clamp(double v, double max) => v < 0 ? 0 : (v > max ? max : v);

  /// The dashboard decides; the host's values are the fallback — one rule in
  /// one direction. `accent` may arrive without its "#"; `title` is a
  /// heading; `logo` is an S3 key that becomes `<origin>/api/embed/logo?k=…`.
  static NativeAppearance resolve(
    Map<String, Object?>? appearance, {
    required String accent,
    required String heading,
    double? radius,
    double? maxRadius,
    String? origin,
  }) {
    final a = appearance ?? const <String, Object?>{};
    final max = _clamp(maxRadius ?? _radiusCeiling, _radiusCeiling);
    final rawAccent = Js.strOrEmpty(a['accent']).trim();
    final logoKey = Js.strOrEmpty(a['logo']).trim();
    var base = (origin != null && origin.isNotEmpty) ? origin : defaultOrigin;
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final title = Js.strOrEmpty(a['title']).trim();
    return NativeAppearance(
      accent: _hex.hasMatch(rawAccent)
          ? '#${rawAccent.startsWith('#') ? rawAccent.substring(1) : rawAccent}'
          : accent,
      heading: title.isEmpty ? heading : title,
      logoUrl: logoKey.isEmpty ? null : '$base/api/embed/logo?k=${encodeURIComponent(logoKey)}',
      radius: _clamp(_numericValue(a['radius']) ?? radius ?? 18, max),
    );
  }

  /// Light, dark, or "auto" — which follows the DEVICE, not the dashboard's own default.
  static bool isDark(String? theme, bool? deviceDark) {
    switch ((theme ?? 'auto').trim().toLowerCase()) {
      case 'dark':
        return true;
      case 'light':
        return false;
      default:
        return deviceDark == true;
    }
  }

  static WidgetPalette palette(Map<String, Object?>? appearance,
      {bool? deviceDark, String? accent}) {
    final theme = Js.strOrEmpty(appearance?['theme']);
    final dark = isDark(theme.isEmpty ? 'auto' : theme, deviceDark);
    final onAccent = luminance(accent ?? '') > 0.45 ? '#101318' : '#FFFFFF';
    return dark
        ? WidgetPalette(
            surface: '#17181B', border: '#2C2E33', text: '#F5F5F4', muted: '#A0A5AE',
            onAccent: onAccent, mode: 'dark')
        : WidgetPalette(
            surface: '#FFFFFF', border: '#E5E4E0', text: '#101318', muted: '#5F6672',
            onAccent: onAccent, mode: 'light');
  }

  static final RegExp _hex6 = RegExp(r'^#?([0-9a-fA-F]{6})$');

  /// WCAG relative luminance of a #rrggbb colour; 0 for anything else.
  static double luminance(String hex) {
    final m = _hex6.firstMatch(hex.trim());
    if (m == null) return 0;
    final n = int.parse(m[1]!, radix: 16);
    double ch(int c) {
      final s = c / 255.0;
      return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * ch((n >> 16) & 255) + 0.7152 * ch((n >> 8) & 255) + 0.0722 * ch(n & 255);
  }

  static final RegExp _argb = RegExp(r'^([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$');

  /// A colour as a 32-bit ARGB value: #rgb, #rrggbb or #aarrggbb, with or
  /// without the "#". Null for anything else.
  static int? argb(String? hex) {
    if (hex == null) return null;
    var h = hex.trim();
    if (h.startsWith('#')) h = h.substring(1);
    if (!_argb.hasMatch(h)) return null;
    final full = h.length == 3 ? h.split('').map((String c) => '$c$c').join() : h;
    final v = int.parse(full, radix: 16);
    return full.length == 6 ? (0xFF000000 | v) : v;
  }

  /// A #rrggbb colour at partial strength — badge and selection fills, as a
  /// 32-bit ARGB value. Slate for anything that is not a colour.
  static int tint(String? hex, double alpha) {
    final m = _hex6.firstMatch((hex ?? '').trim());
    final rgb = m != null ? int.parse(m[1]!, radix: 16) : ((120 << 16) | (140 << 8) | 170);
    final a = Js.round(alpha.clamp(0.0, 1.0) * 255).toInt();
    return (a << 24) | (rgb & 0xFFFFFF);
  }

  /// JavaScript's encodeURIComponent — which is exactly Dart's.
  static String encodeURIComponent(String s) => Uri.encodeComponent(s);
}
