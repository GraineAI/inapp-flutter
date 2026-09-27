import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'core/core.dart';
import 'style.dart';

/// HOW WAITING LOOKS, drawn from the dashboard's Appearance → loader.
///
/// The same five kinds as the React Native and Android SDKs — dots, pulse,
/// ring, bars, and the brand's own logo breathing ("mark", which is the
/// pulse when no logo is uploaded) — at the configured size and speed, in
/// the accent unless a colour was chosen. Painted, not assets: nothing to
/// add to a host's dependency tree. Still when the platform asks for reduced
/// motion.
class GraineLoaderView extends StatefulWidget {
  const GraineLoaderView({
    super.key,
    required this.look,
    required this.color,
    this.trackColor = const Color(0x332C2E33),
    this.size,
    this.label,
    this.labelColor = const Color(0xFF5F6672),
    this.labelStyle,
    this.stacked = false,
    this.logoUrl,
  });

  /// From [Loaders.resolve].
  final LoaderLook look;
  final Color color;

  /// The ring's unlit part.
  final Color trackColor;

  /// Overrides the look's size — the bar's status line wants a small one.
  final double? size;

  /// The words for this moment; null for the mark alone.
  final String? label;
  final Color labelColor;

  /// The words' type, whole — the voice bar sets them in the design's face.
  /// Null: [labelColor], semibold, sized to the mark.
  final TextStyle? labelStyle;

  /// The label under the mark rather than beside it.
  final bool stacked;
  final String? logoUrl;

  @override
  State<GraineLoaderView> createState() => _GraineLoaderViewState();
}

class _GraineLoaderViewState extends State<GraineLoaderView> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.look.periodMs),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(GraineLoaderView old) {
    super.didUpdateWidget(old);
    if (old.look.periodMs != widget.look.periodMs) {
      _t.duration = Duration(milliseconds: widget.look.periodMs);
    }
    _sync();
  }

  void _sync() {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _t.stop();
      _t.value = 0.25;
    } else if (!_t.isAnimating) {
      _t.repeat();
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final px = widget.size ?? widget.look.px.toDouble();
    final kind = widget.look.kind;
    final logo = widget.logoUrl;
    Widget mark;
    if (kind == 'mark' && logo != null && logo.isNotEmpty) {
      mark = AnimatedBuilder(
        animation: _t,
        builder: (BuildContext context, Widget? child) =>
            Opacity(opacity: _lerp(const <double>[0, 0.5, 1], const <double>[1, 0.45, 1], _t.value), child: child),
        child: Image.network(logo,
            width: px,
            height: px,
            fit: BoxFit.contain,
            errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                _painted('pulse', px)),
      );
    } else {
      mark = _painted(kind, px);
    }
    final label = widget.label;
    return Semantics(
      label: (label == null || label.isEmpty) ? 'Loading' : label,
      child: ExcludeSemantics(
        child: Flex(
          direction: widget.stacked ? Axis.vertical : Axis.horizontal,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            mark,
            if (label != null && label.isNotEmpty) ...<Widget>[
              SizedBox(width: widget.stacked ? 0 : 10, height: widget.stacked ? 8 : 0),
              if (widget.stacked)
                Text(label, style: _labelStyle(px))
              else
                // Beside the mark on a narrow line (the bar's status), long
                // words end in an ellipsis rather than overflowing it.
                Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _labelStyle(px))),
            ],
          ],
        ),
      ),
    );
  }

  TextStyle _labelStyle(double px) =>
      widget.labelStyle ??
      TextStyle(
        color: widget.labelColor,
        fontSize: math.max(12, (px * 0.65).roundToDouble()),
        fontWeight: FontWeight.w600,
        decoration: TextDecoration.none,
      );

  Widget _painted(String kind, double px) {
    final w = _width(kind, px);
    return SizedBox(
      width: w,
      height: px,
      child: CustomPaint(
        painter: _LoaderPainter(kind: kind, size: px, color: widget.color, track: widget.trackColor, t: _t),
      ),
    );
  }

  static double _width(String kind, double s) {
    switch (kind) {
      case 'dots':
        final d = math.max(4.0, (s * 0.32).roundToDouble());
        return d * 3 + (d * 0.7).roundToDouble() * 2;
      case 'bars':
        final b = math.max(3.0, (s * 0.18).roundToDouble());
        return b * 3 + (b * 0.8).roundToDouble() * 2;
      default:
        return s;
    }
  }
}

/// Linear interpolation between keyframes, as Animated.interpolate does it.
double _lerp(List<double> input, List<double> output, double t) {
  for (var i = 1; i < input.length; i++) {
    if (t <= input[i]) {
      final f = (t - input[i - 1]) / (input[i] - input[i - 1]);
      return output[i - 1] + (output[i] - output[i - 1]) * f;
    }
  }
  return output.last;
}

class _LoaderPainter extends CustomPainter {
  _LoaderPainter({required this.kind, required this.size, required this.color, required this.track, required this.t})
      : super(repaint: t);

  final String kind;
  final double size;
  final Color color;
  final Color track;
  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size box) {
    final v = t.value;
    final cy = box.height / 2;
    final paint = Paint()
      ..isAntiAlias = true
      ..color = color;
    switch (kind) {
      case 'dots':
        final d = math.max(4.0, (size * 0.32).roundToDouble());
        final gap = (d * 0.7).roundToDouble();
        const lit = <double>[0, 0.33, 0.66, 1];
        const curves = <List<double>>[
          <double>[1, .3, .3, 1],
          <double>[.3, 1, .3, .3],
          <double>[.3, .3, 1, .3],
        ];
        for (var i = 0; i < 3; i++) {
          paint.color = fade(color, _lerp(lit, curves[i], v));
          canvas.drawCircle(Offset(i * (d + gap) + d / 2, cy), d / 2, paint);
        }
      case 'ring':
        final w = math.max(2.0, (size * 0.14).roundToDouble());
        final rect = Rect.fromLTWH(w / 2, cy - size / 2 + w / 2, size - w, size - w);
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..color = track;
        canvas.drawOval(rect, paint);
        paint.color = color;
        // The top quarter of the border, turning — the RN ring is a border with a coloured top.
        canvas.drawArc(rect, (-135 + 360 * v) * math.pi / 180, math.pi / 2, false, paint);
      case 'bars':
        final bw = math.max(3.0, (size * 0.18).roundToDouble());
        final gap = (bw * 0.8).roundToDouble();
        for (var i = 0; i < 3; i++) {
          final scale = _lerp(const <double>[0, 0.5, 1], i == 1 ? const <double>[.4, 1, .4] : const <double>[1, .4, 1], v);
          final h = size * scale;
          final x = i * (bw + gap);
          canvas.drawRRect(
              RRect.fromRectAndRadius(Rect.fromLTWH(x, cy - h / 2, bw, h), Radius.circular(bw / 2)), paint);
        }
      default: // pulse, and a mark with no logo
        final r = size / 2;
        paint.color = fade(color, _lerp(const <double>[0, 1], const <double>[0.35, 0], v));
        canvas.drawCircle(Offset(size / 2, cy), r * _lerp(const <double>[0, 1], const <double>[0.43, 1], v), paint);
        paint.color = color;
        canvas.drawCircle(Offset(size / 2, cy), (size * 0.5).roundToDouble() / 2, paint);
    }
  }

  @override
  bool shouldRepaint(_LoaderPainter old) =>
      old.kind != kind || old.size != size || old.color != color || old.track != track;
}
