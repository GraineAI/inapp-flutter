// The SDK's own icons, painted. Not exported: the bar and the chat window
// draw them; an app with its own design system draws from the tokens.
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'core/core.dart';
import 'glyph.dart';
import 'style.dart';

/// ONE OF THE SDK'S ICONS ([SdkIcons]) in the design's icon style —
/// contract/DESIGN.md, "Icons": `outline` (round caps and joins), `sharp`
/// (square caps, mitred joins), `filled` (the body filled, stroked at 0.75 ×
/// the stroke, at least 1) or `duotone` (the body filled at 28%, then
/// stroked). Painted from the same 24×24 path data the dashboard draws, so
/// the customer's phone shows the drawing the brand chose — never an emoji,
/// which every platform draws differently and none in the brand's colour.
class SdkIconView extends StatelessWidget {
  const SdkIconView(
    this.name, {
    super.key,
    required this.color,
    this.size = 18,
    this.style = 'outline',
    this.stroke = 2,
    this.turned = false,
  });

  /// A key of [SdkIcons.all]: mic, micOff, end, send, chat, call, chevron, close.
  final String name;
  final Color color;
  final double size;

  /// `icons.style`.
  final String style;

  /// `icons.stroke`, in the icon's own 24-unit box.
  final double stroke;

  /// Turned 180° — the chat header's chevron, which is drawn pointing up.
  final bool turned;

  @override
  Widget build(BuildContext context) {
    final icon = SdkIcons.all[name];
    Widget painted = SizedBox(
      width: size,
      height: size,
      child: icon == null
          ? null
          : CustomPaint(
              painter: SdkIconPainter(icon: icon, color: color, treatment: SdkIcons.treatment(style, stroke)),
            ),
    );
    if (turned) painted = Transform.rotate(angle: math.pi, child: painted);
    return ExcludeSemantics(child: painted);
  }
}

class SdkIconPainter extends CustomPainter {
  SdkIconPainter({required this.icon, required this.color, required this.treatment});

  final SdkIcon icon;
  final Color color;
  final IconTreatment treatment;

  @override
  void paint(Canvas canvas, Size size) {
    // The icon's own 24×24 box, scaled to fit; strokes scale with it.
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final cap = treatment.square ? StrokeCap.square : StrokeCap.round;
    final join = treatment.square ? StrokeJoin.miter : StrokeJoin.round;
    Paint stroke(double width) => Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..color = color
      ..strokeWidth = width
      ..strokeCap = cap
      ..strokeJoin = join;
    final body = icon.body == null ? null : glyphPath(icon.body!);
    if (body != null) {
      if (treatment.fillBody) {
        canvas.drawPath(
          body,
          Paint()
            ..isAntiAlias = true
            ..style = PaintingStyle.fill
            ..color = fade(color, treatment.bodyFillOpacity),
        );
      }
      canvas.drawPath(body, stroke(treatment.bodyStroke));
    }
    final lines = icon.lines == null ? null : glyphPath(icon.lines!);
    if (lines != null) canvas.drawPath(lines, stroke(treatment.lineStroke));
    canvas.restore();
  }

  @override
  bool shouldRepaint(SdkIconPainter old) => old.icon != icon || old.color != color || old.treatment != treatment;
}
