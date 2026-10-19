/// THE CALL SCREEN'S RULES (contract/DESIGN.md "Call screen" → "The look") —
/// for an app that draws its own call screen (`GraineCallScreen.app`).
///
/// The SDK's own call screens are native and draw all of this themselves.
/// These are the same rules, line for line with the design system's
/// (sdk/inapp/theme.ts) and pinned by sdk/contract/design.json →
/// `callScreen` and `callVectors`: which moment a call is in, which look it
/// draws, the status words, the backdrop's geometry over time, the buttons'
/// boxes and the voice's level. Pure Dart: no widgets, no platform.
library;

import 'dart:math' as math;

import 'design.dart';
import 'js.dart';

/// How a layout places the screen, inside the safe area, 24 in from each side.
class CallLayoutSpec {
  const CallLayoutSpec({
    required this.align,
    required this.top,
    required this.avatar,
    required this.nameGap,
    required this.nameFirst,
    required this.nameSize,
    required this.nameLines,
    required this.card,
  });

  /// "center", or "start": against the leading edge.
  final String align;

  /// The first thing's top edge below the safe area's top.
  final double top;

  /// The avatar at this share of `avatarSize`; 0: no avatar.
  final double avatar;

  /// From the avatar's bottom to the name's top.
  final double nameGap;

  /// The name and status first, the avatar (in its orb) centred in the space below them.
  final bool nameFirst;

  /// The name's size when the design gives none, and the lines it may take.
  final double nameSize;
  final int nameLines;

  /// The avatar, name, status, voice and a middle caption gathered on one card.
  final bool card;

  Map<String, Object?> toJson() => <String, Object?>{
        'align': align,
        'top': top,
        'avatar': avatar,
        'nameGap': nameGap,
        'nameFirst': nameFirst,
        'nameSize': nameSize,
        'nameLines': nameLines,
        'card': card,
      };
}

/// A linear gradient's line, in points: from (x0, y0) to (x1, y1).
class CallGradientLine {
  const CallGradientLine(this.x0, this.y0, this.x1, this.y1);

  final double x0;
  final double y0;
  final double x1;
  final double y1;

  Map<String, Object?> toJson() => <String, Object?>{'x0': x0, 'y0': y0, 'x1': x1, 'y1': y1};
}

/// One of a mesh's glows: its centre in shares of the screen, and its colour.
class CallMeshGlow {
  const CallMeshGlow(this.u, this.v, this.color);

  final double u;
  final double v;
  final String color;

  Map<String, Object?> toJson() => <String, Object?>{'u': u, 'v': v, 'color': color};
}

/// Where a backdrop's moving parts are at one moment ([CallLook.backdropFrame]).
class CallBackdropFrame {
  const CallBackdropFrame({
    required this.line,
    required this.cx,
    required this.cy,
    required this.r,
    required this.mesh,
    required this.dx,
    required this.dy,
    required this.scale,
  });

  /// linear, and the blurred avatar's scrim: the gradient line, in points.
  final CallGradientLine line;

  /// radial: the centre and the radius, in points.
  final double cx;
  final double cy;
  final double r;

  /// mesh: each glow (TL, TR, BR, BL, then the centre's for a fifth stop).
  final List<CallMeshGlow> mesh;

  /// blurred-avatar: the blurred avatar's offset in points and its scale.
  final double dx;
  final double dy;
  final double scale;

  Map<String, Object?> toJson() => <String, Object?>{
        'line': line.toJson(),
        'radial': <String, Object?>{'cx': cx, 'cy': cy, 'r': r},
        'mesh': <Object?>[for (final g in mesh) g.toJson()],
        'avatar': <String, Object?>{'dx': dx, 'dy': dy, 'scale': scale},
      };
}

/// A button's box: [height] high, [width] wide, corners [radius] (continuous on iOS when [continuous]).
class CallButtonFrame {
  const CallButtonFrame(this.width, this.height, this.radius, this.continuous);

  final double width;
  final double height;
  final double radius;
  final bool continuous;

  Map<String, Object?> toJson() => <String, Object?>{'width': width, 'height': height, 'radius': radius, 'continuous': continuous};
}

/// The buttons' sizes: the call's, the ring's and the missed call's, and the icon in them.
class CallButtonSizes {
  const CallButtonSizes(this.button, this.big, this.icon);

  final double button;
  final double big;
  final double icon;

  Map<String, Object?> toJson() => <String, Object?>{'button': button, 'big': big, 'icon': icon};
}

/// THE RULES, as the design system states them.
abstract final class CallLook {
  /// Each layout's numbers (contract/DESIGN.md "Call screen" → Layouts).
  static const Map<String, CallLayoutSpec> layouts = <String, CallLayoutSpec>{
    'classic': CallLayoutSpec(align: 'center', top: 72, avatar: 1, nameGap: 20, nameFirst: false, nameSize: 28, nameLines: 1, card: false),
    'full-bleed': CallLayoutSpec(align: 'start', top: 32, avatar: 0.5, nameGap: 24, nameFirst: false, nameSize: 40, nameLines: 2, card: false),
    'card': CallLayoutSpec(align: 'center', top: 48, avatar: 0.8, nameGap: 16, nameFirst: false, nameSize: 24, nameLines: 1, card: true),
    'orb': CallLayoutSpec(align: 'center', top: 40, avatar: 0.75, nameGap: 0, nameFirst: true, nameSize: 24, nameLines: 1, card: false),
    'minimal': CallLayoutSpec(align: 'center', top: 120, avatar: 0, nameGap: 0, nameFirst: false, nameSize: 34, nameLines: 2, card: false),
  };

  /// The screen's other numbers — points, milliseconds, shares.
  static const Map<String, double> screen = <String, double>{
    'side': 24,
    'statusGap': 6,
    'visualizerGap': 16,
    'visualizerHeight': 28,
    'captionGap': 36,
    'captionAboveButtons': 24,
    'buttonsBottom': 56,
    'labelGap': 8,
    'labelSize': 13,
    'cardPadding': 24,
    'cardRadius': 28,
    'cardMinAlpha': 0.16,
    'orbScale': 2,
    'speakingScale': 1.06,
    'endedAlpha': 0.4,
    'endedCloseMs': 1000,
    'missedCloseMs': 30000,
    'bigButton': 9 / 8,
    'icon': 30 / 64,
  };

  /// The rings, as every SDK animates them.
  static const Map<String, Map<String, double>> rings = <String, Map<String, double>>{
    'pulse': <String, double>{'periodMs': 1600, 'scale': 1.35, 'alpha': 0.6, 'width': 2, 'count': 1},
    'ripple': <String, double>{'periodMs': 2400, 'scale': 1.6, 'alpha': 0.5, 'width': 1.5, 'count': 3},
    'glow': <String, double>{'periodMs': 2000, 'reach': 1.45, 'alphaLow': 0.35, 'alphaHigh': 0.7, 'breathe': 1.08},
  };

  /// The voice, as every SDK draws it.
  static const Map<String, Object> visualizer = <String, Object>{
    'bars': <String, Object>{'count': 5, 'width': 4, 'gap': 4, 'rest': 4, 'max': 28, 'weights': <double>[0.5, 0.8, 1, 0.8, 0.5], 'wobbleMs': 600},
    'wave': <String, Object>{'width': 160, 'stroke': 2, 'amplitude': 12, 'cycles': 1.5, 'periodMs': 900, 'restAlpha': 0.4},
    'orb': <String, Object>{'rest': 1.6, 'gain': 0.5, 'layoutRest': 2, 'layoutGain': 0.4, 'inner': 0.72, 'outerAlpha': 0.35, 'innerAlpha': 0.5},
    'attackMs': 60,
    'releaseMs': 240,
  };

  /// How a backdrop moves.
  static const Map<String, Object> motion = <String, Object>{
    'driftMs': <String, Object>{'linear': 14000, 'radial': 16000, 'avatar': 18000, 'mesh': <int>[17000, 19000, 23000, 29000, 31000]},
    'breatheMs': 7000,
    'idleMs': 10000,
    'settleMs': 600,
    'blur': 48,
    'meshPixels': <String, Object>{'cols': 32, 'rows': 64},
  };

  /// The ranges the look's numbers are clamped to.
  static const Map<String, Map<String, double>> limits = <String, Map<String, double>>{
    'avatarSize': <String, double>{'min': 72, 'max': 160, 'own': 112},
    'buttonSize': <String, double>{'min': 52, 'max': 80, 'own': 64},
    'nameSize': <String, double>{'min': 20, 'max': 44},
    'statusSize': <String, double>{'min': 12, 'max': 20, 'own': 16},
    'stops': <String, double>{'min': 2, 'max': 5},
  };

  /// The preset the dashboard recommends.
  static const String recommended = 'aurora';

  /// Where a mesh's glows sit (TL, TR, BR, BL, and the centre's for a fifth stop), in shares of the screen.
  static const List<List<double>> _meshAnchors = <List<double>>[
    <double>[0.15, 0.12], <double>[0.85, 0.2], <double>[0.8, 0.85], <double>[0.18, 0.78], <double>[0.5, 0.48],
  ];
  static const List<double> _meshDriftMs = <double>[17000, 19000, 23000, 29000, 31000];

  /// THE MOMENT A CALL SCREEN SHOWS, from the call's state: `missed` first;
  /// then a ring (`scheduled` when Graine rang it at a booked time); a call not
  /// through yet (`outgoing` when the customer placed it); on the call
  /// (`reconnecting` while it recovers its connection); else `ended`.
  static String moment({
    required String state,
    String? direction,
    bool hosted = false,
    bool missed = false,
    bool reconnecting = false,
  }) {
    if (missed) return 'missed';
    switch (state) {
      case 'ringing':
        return hosted ? 'scheduled' : 'incoming';
      case 'connecting':
        return direction == 'outgoing' ? 'outgoing' : 'connecting';
      case 'active':
        return reconnecting ? 'reconnecting' : 'connected';
      default:
        return 'ended';
    }
  }

  /// What a moment is drawn in: its own look, else the screen's.
  static ThemeCallLook lookFor(ThemeCall call, String moment) => call.states[moment] ?? call.look;

  /// [ms] as the timer shows it: 4:07, or 1:02:09 past an hour.
  static String elapsed(double ms) {
    final s = (math.max(0, ms) / 1000).floor();
    String two(int n) => n.toString().padLeft(2, '0');
    return s >= 3600 ? '${s ~/ 3600}:${two((s ~/ 60) % 60)}:${two(s % 60)}' : '${s ~/ 60}:${two(s % 60)}';
  }

  /// The status line for a moment: the brand's words for each moment; "Call
  /// failed" or "Declined" for a call that ended badly; on the call, the timer
  /// (" · Muted" while muted), else "Muted", "Speaking", "Listening".
  static String statusWords(
    ThemeCall call,
    String moment, {
    double? elapsedMs,
    bool muted = false,
    bool speaking = false,
    String ending = 'normal',
  }) {
    final st = call.statusText;
    switch (moment) {
      case 'missed':
        return st.missed;
      case 'ended':
        return ending == 'failed' ? 'Call failed' : ending == 'declined' ? 'Declined' : st.ended;
      case 'scheduled':
        return st.scheduled;
      case 'incoming':
        return st.ringing;
      case 'outgoing':
        return st.outgoing;
      case 'connecting':
        return st.connecting;
      case 'reconnecting':
        return st.reconnecting;
      default:
        if (call.timer) return elapsed(elapsedMs ?? 0) + (muted ? ' · Muted' : '');
        return muted ? 'Muted' : speaking ? 'Speaking' : 'Listening';
    }
  }

  /// The buttons' sizes: the call's, the ring's and the missed call's (9/8 of it), and the icon in them.
  static CallButtonSizes buttonSizes(double buttonSize) =>
      CallButtonSizes(buttonSize, Js.round(buttonSize * 9 / 8), Js.round(buttonSize * 30 / 64));

  /// A button's box ([share] is the width the row gives it): a circle; a
  /// squircle's continuous corners at 30%; a pill up to 1.5 × its height
  /// wide, its corners at 30% while a toggle is on; End with `endShape` "pill"
  /// as wide as its share less 8, in every shape.
  static CallButtonFrame buttonFrame({
    required String shape,
    required double size,
    required double share,
    bool end = false,
    String? endShape,
    bool on = false,
  }) {
    if (end && endShape == 'pill') return CallButtonFrame(math.max(size, Js.round(share - 8)), size, size / 2, false);
    if (shape == 'squircle') return CallButtonFrame(size, size, _r2(size * 0.3), true);
    if (shape == 'pill') {
      final width = math.max(size, math.min(Js.round(share - 8), Js.round(size * 1.5)));
      return CallButtonFrame(width, size, on ? _r2(size * 0.3) : size / 2, on);
    }
    return CallButtonFrame(size, size, size / 2, false);
  }

  /// A linear gradient's line across a [w] × [h] screen for an [angle] read as
  /// CSS reads it (0 runs bottom to top, 90 left to right, 180 top to bottom):
  /// through the centre, long enough that the end stops reach the corners.
  static CallGradientLine gradientLine(double angle, double w, double h) {
    final a = angle * math.pi / 180;
    final dx = math.sin(a);
    final dy = -math.cos(a);
    final len = (w * math.sin(a)).abs() + (h * math.cos(a)).abs();
    return CallGradientLine(
      _r2(w / 2 - dx * len / 2),
      _r2(h / 2 - dy * len / 2),
      _r2(w / 2 + dx * len / 2),
      _r2(h / 2 + dy * len / 2),
    );
  }

  /// The backdrop at [t] ms after it began moving, on a [w] × [h] screen; at
  /// rest at t = 0 or with motion "none". Drift sways a linear gradient's
  /// angle, circles a radial's centre and the mesh's glows, and slides the
  /// blurred avatar; breathe grows and shrinks each about the centre.
  static CallBackdropFrame backdropFrame(ThemeCallBackdrop b, double w, double h, [double t = 0]) {
    final k = b.intensity.clamp(0.0, 1.0).toDouble();
    final drift = b.motion == 'drift';
    final breathe = b.motion == 'breathe' ? 1 + (0.05 + 0.12 * k) * math.sin(2 * math.pi * t / 7000) : 1.0;
    final sway = drift ? (6 + 18 * k) * math.sin(2 * math.pi * t / 14000) : 0.0;
    final base = gradientLine(b.angle + sway, w, h);
    final cxl = w / 2;
    final cyl = h / 2;
    final line = CallGradientLine(
      _r2(cxl + (base.x0 - cxl) * breathe),
      _r2(cyl + (base.y0 - cyl) * breathe),
      _r2(cxl + (base.x1 - cxl) * breathe),
      _r2(cyl + (base.y1 - cyl) * breathe),
    );
    double orbit(double period, [double phase = 0]) => 2 * math.pi * t / period + phase;
    final ra = drift ? (0.03 + 0.06 * k) * w : 0.0;
    final colors = <String>[for (final s in b.stops) s.color];
    final n = colors.length;
    final anchors = n >= 5 ? _meshAnchors : _meshAnchors.sublist(0, 4);
    final ma = drift ? 0.05 + 0.1 * k : 0.0;
    final mesh = <CallMeshGlow>[];
    for (var i = 0; i < anchors.length; i++) {
      final a = orbit(_meshDriftMs[i], i * math.pi / 2.5);
      mesh.add(CallMeshGlow(
        _r3(0.5 + (anchors[i][0] + ma * math.cos(a) - 0.5) * breathe),
        _r3(0.5 + (anchors[i][1] + ma * math.sin(a) - 0.5) * breathe),
        n == 0 ? '#000000' : colors[i % n],
      ));
    }
    final aa = drift ? (0.02 + 0.05 * k) * w : 0.0;
    return CallBackdropFrame(
      line: line,
      cx: _r2(0.5 * w + ra * math.cos(orbit(16000))),
      cy: _r2(0.28 * h + ra * math.sin(orbit(16000))),
      r: _r2((0.35 + 0.4 * k) * _hypot(w, h) * breathe),
      mesh: mesh,
      dx: _r2(aa * math.cos(orbit(18000))),
      dy: _r2(aa * math.sin(orbit(18000))),
      scale: _r3(b.motion == 'breathe' ? 1 + (0.04 + 0.08 * k) * math.sin(2 * math.pi * t / 7000) : 1),
    );
  }

  /// A mesh's colour at (u, v), shares of the screen: every glow weighted by
  /// max(0, 0.9 − its distance)⁴ and averaged. Fill a small bitmap with this
  /// (at least 32 × 64, at each pixel's centre) and draw it scaled up smoothly.
  static String meshColor(List<CallMeshGlow> glows, double u, double v) {
    var r = 0.0;
    var g = 0.0;
    var bl = 0.0;
    var sum = 0.0;
    for (final glow in glows) {
      final w = math.pow(math.max(0, 0.9 - _hypot(u - glow.u, v - glow.v)), 4).toDouble();
      final c = _rgb(glow.color);
      r += c[0] * w;
      g += c[1] * w;
      bl += c[2] * w;
      sum += w;
    }
    if (sum < 1e-9) {
      final all = <List<int>>[for (final x in glows) _rgb(x.color)];
      final count = math.max(1, all.length);
      double avg(int i) => all.fold<double>(0, (double s, List<int> c) => s + c[i]) / count;
      return _hex(avg(0), avg(1), avg(2));
    }
    return _hex(r / sum, g / sum, bl / sum);
  }

  /// The agent's voice as the visualiser draws it, 0–1, from the call's
  /// inbound audio level (0–1, as WebRTC reports `audioLevel`): its loudness
  /// in dB between a floor — −30 dB at [sensitivity] 0, −60 at 1 — and −6 dB.
  static double voiceLevel(double raw, [double sensitivity = 0.5]) {
    if (!(raw > 0)) return 0;
    final db = 20 * math.log(math.min(1, raw)) / math.ln10;
    final floor = -(30 + 30 * sensitivity.clamp(0.0, 1.0));
    return _r3(((db - floor) / (-6 - floor)).clamp(0.0, 1.0).toDouble());
  }

  /// The voice where the call reports only that the agent is speaking: a
  /// speech-like movement [t] ms into it, between 0.15 and 0.95.
  static double speakingLevel(double t) {
    final s = t / 1000;
    return _r3(math.max(0.15, math.min(0.95, 0.55 + 0.3 * math.sin(2 * math.pi * s / 0.53) * math.sin(2 * math.pi * s / 1.7))));
  }

  // JavaScript's rounding (half toward +∞), to two and three places, never -0.
  static double _r2(double v) => Js.round(v * 100) / 100 + 0.0;
  static double _r3(double v) => Js.round(v * 1000) / 1000 + 0.0;

  static double _hypot(double x, double y) => math.sqrt(x * x + y * y);

  static List<int> _rgb(String hex) {
    final n = int.parse((Design.normaliseHex(hex) ?? '#000000').substring(1), radix: 16);
    return <int>[(n >> 16) & 255, (n >> 8) & 255, n & 255];
  }

  static String _hex(double r, double g, double b) {
    String c(double v) => Js.round(v).toInt().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    return '#${c(r)}${c(g)}${c(b)}'.toUpperCase();
  }
}
