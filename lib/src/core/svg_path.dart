/// SVG PATH DATA, READ INTO ABSOLUTE DRAWING COMMANDS — so the launcher glyph
/// (24×24 path data from the session) is painted, not fetched.
///
/// The whole of the path grammar a glyph can use: M L H V C S Q T A Z, upper
/// case absolute and lower case relative, implicit repeats (pairs after an M
/// are lines), numbers packed the way minifiers pack them ("-.5.5", "1e-3")
/// and arc flags with no separator ("a1 1 0 011 1"). H and V become lines;
/// S and T become curves with their reflected control point. Pure Dart: the
/// widget layer turns [PathCommand]s into a `dart:ui` Path.
///
/// Anything malformed is null, never an exception: the launcher then shows
/// the glyph as an image, or the brand's logo.
library;

/// One absolute drawing command.
sealed class PathCommand {
  const PathCommand();
}

class PathMoveTo extends PathCommand {
  const PathMoveTo(this.x, this.y);
  final double x;
  final double y;

  @override
  bool operator ==(Object other) => other is PathMoveTo && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash('M', x, y);
  @override
  String toString() => 'M $x $y';
}

class PathLineTo extends PathCommand {
  const PathLineTo(this.x, this.y);
  final double x;
  final double y;

  @override
  bool operator ==(Object other) => other is PathLineTo && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash('L', x, y);
  @override
  String toString() => 'L $x $y';
}

class PathCubicTo extends PathCommand {
  const PathCubicTo(this.x1, this.y1, this.x2, this.y2, this.x, this.y);
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      other is PathCubicTo &&
      other.x1 == x1 &&
      other.y1 == y1 &&
      other.x2 == x2 &&
      other.y2 == y2 &&
      other.x == x &&
      other.y == y;
  @override
  int get hashCode => Object.hash('C', x1, y1, x2, y2, x, y);
  @override
  String toString() => 'C $x1 $y1 $x2 $y2 $x $y';
}

class PathQuadTo extends PathCommand {
  const PathQuadTo(this.x1, this.y1, this.x, this.y);
  final double x1;
  final double y1;
  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      other is PathQuadTo && other.x1 == x1 && other.y1 == y1 && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash('Q', x1, y1, x, y);
  @override
  String toString() => 'Q $x1 $y1 $x $y';
}

/// An elliptical arc to ([x], [y]). [rotation] is in degrees; [sweep] is
/// SVG's sweep flag — clockwise on a y-down canvas.
class PathArcTo extends PathCommand {
  const PathArcTo(this.rx, this.ry, this.rotation, this.largeArc, this.sweep, this.x, this.y);
  final double rx;
  final double ry;
  final double rotation;
  final bool largeArc;
  final bool sweep;
  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      other is PathArcTo &&
      other.rx == rx &&
      other.ry == ry &&
      other.rotation == rotation &&
      other.largeArc == largeArc &&
      other.sweep == sweep &&
      other.x == x &&
      other.y == y;
  @override
  int get hashCode => Object.hash('A', rx, ry, rotation, largeArc, sweep, x, y);
  @override
  String toString() => 'A $rx $ry $rotation ${largeArc ? 1 : 0} ${sweep ? 1 : 0} $x $y';
}

class PathClose extends PathCommand {
  const PathClose();

  @override
  bool operator ==(Object other) => other is PathClose;
  @override
  int get hashCode => 'Z'.hashCode;
  @override
  String toString() => 'Z';
}

abstract final class SvgPath {
  /// [d] as absolute commands, or null when it is not path data. An empty
  /// string is an empty path.
  static List<PathCommand>? parse(String d) {
    try {
      return _Parser(d).run();
    } on FormatException {
      return null;
    }
  }
}

class _Parser {
  _Parser(this.s);

  final String s;
  int i = 0;

  // The pen, where the subpath began, and the last control points (for S and T).
  double cx = 0, cy = 0, sx = 0, sy = 0;
  double? lastCubicX, lastCubicY, lastQuadX, lastQuadY;

  final List<PathCommand> out = <PathCommand>[];

  static bool _isSeparator(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0C || c == 0x2C;
  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  void _skip() {
    while (i < s.length && _isSeparator(s.codeUnitAt(i))) {
      i++;
    }
  }

  /// Whether a number starts here (after separators) — how an implicit repeat is spotted.
  bool _numberAhead() {
    _skip();
    if (i >= s.length) return false;
    final c = s.codeUnitAt(i);
    return _isDigit(c) || c == 0x2D /* - */ || c == 0x2B /* + */ || c == 0x2E /* . */;
  }

  double _number() {
    _skip();
    final start = i;
    if (i < s.length && (s.codeUnitAt(i) == 0x2D || s.codeUnitAt(i) == 0x2B)) i++;
    var digits = 0;
    while (i < s.length && _isDigit(s.codeUnitAt(i))) {
      i++;
      digits++;
    }
    if (i < s.length && s.codeUnitAt(i) == 0x2E) {
      i++;
      while (i < s.length && _isDigit(s.codeUnitAt(i))) {
        i++;
        digits++;
      }
    }
    if (digits == 0) throw FormatException('expected a number', s, start);
    if (i < s.length && (s.codeUnitAt(i) == 0x65 || s.codeUnitAt(i) == 0x45)) {
      // An exponent only if digits follow it; otherwise the "e" is not ours.
      var j = i + 1;
      if (j < s.length && (s.codeUnitAt(j) == 0x2D || s.codeUnitAt(j) == 0x2B)) j++;
      if (j < s.length && _isDigit(s.codeUnitAt(j))) {
        i = j;
        while (i < s.length && _isDigit(s.codeUnitAt(i))) {
          i++;
        }
      }
    }
    final v = double.parse(s.substring(start, i));
    if (!v.isFinite) throw FormatException('not a finite number', s, start);
    return v;
  }

  /// An arc flag: one character, 0 or 1, separator or not.
  bool _flag() {
    _skip();
    if (i >= s.length) throw FormatException('expected a flag', s, i);
    final c = s.codeUnitAt(i);
    if (c != 0x30 && c != 0x31) throw FormatException('expected 0 or 1', s, i);
    i++;
    return c == 0x31;
  }

  List<PathCommand> run() {
    _skip();
    if (i >= s.length) return out;
    var first = true;
    while (true) {
      _skip();
      if (i >= s.length) break;
      final cmd = s[i];
      if (!'MmLlHhVvCcSsQqTtAaZz'.contains(cmd)) throw FormatException('unknown command', s, i);
      if (first && cmd != 'M' && cmd != 'm') throw FormatException('path must start with M', s, i);
      first = false;
      i++;
      _command(cmd);
    }
    return out;
  }

  void _command(String cmd) {
    final rel = cmd.toLowerCase() == cmd;
    final c = cmd.toUpperCase();
    if (c == 'Z') {
      out.add(const PathClose());
      cx = sx;
      cy = sy;
      _clearControls();
      return;
    }
    var once = true;
    // Arguments repeat until the next command letter.
    while (once || _numberAhead()) {
      once = false;
      switch (c) {
        case 'M':
          var x = _number(), y = _number();
          if (rel) {
            x += cx;
            y += cy;
          }
          out.add(PathMoveTo(x, y));
          cx = sx = x;
          cy = sy = y;
          _clearControls();
          // Pairs after a moveto are linetos, relative if the M was.
          while (_numberAhead()) {
            var lx = _number(), ly = _number();
            if (rel) {
              lx += cx;
              ly += cy;
            }
            _line(lx, ly);
          }
        case 'L':
          var x = _number(), y = _number();
          if (rel) {
            x += cx;
            y += cy;
          }
          _line(x, y);
        case 'H':
          var x = _number();
          if (rel) x += cx;
          _line(x, cy);
        case 'V':
          var y = _number();
          if (rel) y += cy;
          _line(cx, y);
        case 'C':
          var x1 = _number(), y1 = _number(), x2 = _number(), y2 = _number(), x = _number(), y = _number();
          if (rel) {
            x1 += cx;
            y1 += cy;
            x2 += cx;
            y2 += cy;
            x += cx;
            y += cy;
          }
          _cubic(x1, y1, x2, y2, x, y);
        case 'S':
          var x2 = _number(), y2 = _number(), x = _number(), y = _number();
          if (rel) {
            x2 += cx;
            y2 += cy;
            x += cx;
            y += cy;
          }
          // The first control point mirrors the last curve's second, or is the pen.
          final x1 = lastCubicX == null ? cx : 2 * cx - lastCubicX!;
          final y1 = lastCubicY == null ? cy : 2 * cy - lastCubicY!;
          _cubic(x1, y1, x2, y2, x, y);
        case 'Q':
          var x1 = _number(), y1 = _number(), x = _number(), y = _number();
          if (rel) {
            x1 += cx;
            y1 += cy;
            x += cx;
            y += cy;
          }
          _quad(x1, y1, x, y);
        case 'T':
          var x = _number(), y = _number();
          if (rel) {
            x += cx;
            y += cy;
          }
          final x1 = lastQuadX == null ? cx : 2 * cx - lastQuadX!;
          final y1 = lastQuadY == null ? cy : 2 * cy - lastQuadY!;
          _quad(x1, y1, x, y);
        case 'A':
          final rx = _number().abs(), ry = _number().abs(), rotation = _number();
          final large = _flag(), sweep = _flag();
          var x = _number(), y = _number();
          if (rel) {
            x += cx;
            y += cy;
          }
          out.add(PathArcTo(rx, ry, rotation, large, sweep, x, y));
          cx = x;
          cy = y;
          _clearControls();
      }
    }
  }

  void _line(double x, double y) {
    out.add(PathLineTo(x, y));
    cx = x;
    cy = y;
    _clearControls();
  }

  void _cubic(double x1, double y1, double x2, double y2, double x, double y) {
    out.add(PathCubicTo(x1, y1, x2, y2, x, y));
    cx = x;
    cy = y;
    lastCubicX = x2;
    lastCubicY = y2;
    lastQuadX = lastQuadY = null;
  }

  void _quad(double x1, double y1, double x, double y) {
    out.add(PathQuadTo(x1, y1, x, y));
    cx = x;
    cy = y;
    lastQuadX = x1;
    lastQuadY = y1;
    lastCubicX = lastCubicY = null;
  }

  void _clearControls() {
    lastCubicX = lastCubicY = lastQuadX = lastQuadY = null;
  }
}
