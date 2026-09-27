// The design's launcher glyph, drawn. Not exported: the launcher and the bar's
// avatar use it; an app with its own design system draws from the tokens.
import 'package:flutter/widgets.dart';

import 'core/core.dart';
import 'style.dart';

final Map<String, Path?> _paths = <String, Path?>{};

/// [d] (24×24 SVG path data) as a Path, or null when it cannot be read.
/// Parsed once per glyph: a launcher repaints far more often than the
/// design changes.
Path? glyphPath(String d) {
  if (_paths.containsKey(d)) return _paths[d];
  final commands = SvgPath.parse(d);
  Path? path;
  if (commands != null && commands.isNotEmpty) {
    path = Path();
    for (final c in commands) {
      switch (c) {
        case PathMoveTo(:final x, :final y):
          path.moveTo(x, y);
        case PathLineTo(:final x, :final y):
          path.lineTo(x, y);
        case PathCubicTo(:final x1, :final y1, :final x2, :final y2, :final x, :final y):
          path.cubicTo(x1, y1, x2, y2, x, y);
        case PathQuadTo(:final x1, :final y1, :final x, :final y):
          path.quadraticBezierTo(x1, y1, x, y);
        case PathArcTo(:final rx, :final ry, :final rotation, :final largeArc, :final sweep, :final x, :final y):
          // SVG's sweep flag is clockwise on a y-down canvas; a zero radius is a line.
          path.arcToPoint(Offset(x, y),
              radius: Radius.elliptical(rx, ry), rotation: rotation, largeArc: largeArc, clockwise: sweep);
        case PathClose():
          path.close();
      }
    }
  }
  if (_paths.length >= 32) _paths.clear();
  return _paths[d] = path;
}

/// THE BRAND'S MARK, at [size]: the design's glyph, else the logo, else the
/// first letter of the agent's name — and each one falls to the next when
/// it cannot be shown.
///
/// The glyph is painted from its path data. A glyph this build cannot read
/// is fetched as an image instead ([Design.glyphUrl], year-cached); an image
/// that fails shows the logo, and a logo that fails shows the letter.
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    required this.glyph,
    required this.colorHex,
    required this.size,
    required this.name,
    this.stroke = 2,
    this.logoUrl,
    this.origin,
  });

  /// Null: the brand chose its logo.
  final LauncherGlyph? glyph;

  /// #RRGGBB, for the glyph and the letter (never tints the logo).
  final String colorHex;
  final double size;
  final double stroke;
  final String? logoUrl;

  /// Its first letter is the last resort.
  final String name;

  /// Where glyph images come from: the SDK's baseUrl.
  final String? origin;

  /// The painted glyph, for a test to find.
  static const Key glyphKey = ValueKey<String>('graine-glyph');

  @override
  Widget build(BuildContext context) {
    final color = tokenColor(colorHex);
    final g = glyph;
    if (g == null) return _logo(color);
    final path = g.path.isEmpty ? null : glyphPath(g.path);
    if (path != null) {
      return SizedBox(
        key: glyphKey,
        width: size,
        height: size,
        child: CustomPaint(painter: _GlyphPainter(path: path, stroke: g.stroke, strokeWidth: stroke, color: color)),
      );
    }
    if (g.id.isEmpty) return _logo(color);
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2;
    return Image.network(
      Design.glyphUrl(origin, g.id, colorHex, size * dpr, stroke),
      width: size,
      height: size,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
      errorBuilder: (BuildContext c, Object e, StackTrace? s) => _logo(color),
    );
  }

  Widget _logo(Color color) {
    final url = logoUrl;
    if (url == null || url.isEmpty) return _letter(color);
    return Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
      errorBuilder: (BuildContext c, Object e, StackTrace? s) => _letter(color),
    );
  }

  Widget _letter(Color color) {
    final t = name.trim();
    final letter = t.isEmpty ? '✦' : String.fromCharCodes(t.runes.take(1)).toUpperCase();
    return SizedBox(
      width: size,
      height: size,
      child: Center(child: Text(letter, style: textStyle(color, size * 0.9, weight: 700, height: 1))),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter({required this.path, required this.stroke, required this.strokeWidth, required this.color});

  final Path path;
  final bool stroke;
  final double strokeWidth;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // The glyph's own 24×24 box, scaled to fit; the stroke scales with it.
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(
      path,
      Paint()
        ..isAntiAlias = true
        ..color = color
        ..style = stroke ? PaintingStyle.stroke : PaintingStyle.fill
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      !identical(old.path, path) || old.stroke != stroke || old.strokeWidth != strokeWidth || old.color != color;
}
