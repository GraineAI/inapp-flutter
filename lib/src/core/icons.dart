/// THE SDK'S OWN ICONS — the microphone, hang up, send, chat, call, chevron
/// and close the bar draws, and the call screen's loudspeaker — as 24×24 path
/// data, the very strings the
/// dashboard's Garage draws and every other SDK paints (contract/DESIGN.md,
/// "Icons"; the tests hold them to contract/design.json → `icons`).
///
/// Each is a closed `body` a fill can sit in, plus `lines` that are only ever
/// stroked — filling a microphone's stand would draw a half-moon. How they
/// are drawn is the design's `icons.style` at `icons.stroke`: see
/// [SdkIcons.treatment]. Pure: the widget layer paints them.
library;

import 'dart:math' as math;

/// One icon: a closed [body] (may be filled) and [lines] (only stroked).
class SdkIcon {
  const SdkIcon({this.body, this.lines});

  final String? body;
  final String? lines;

  Map<String, Object?> toJson() => <String, Object?>{
        if (body != null) 'body': body,
        if (lines != null) 'lines': lines,
      };
}

/// How one icon style strokes and fills: [SdkIcons.treatment].
class IconTreatment {
  const IconTreatment({
    required this.fillBody,
    required this.bodyFillOpacity,
    required this.bodyStroke,
    required this.lineStroke,
    required this.square,
  });

  /// Whether the body is filled (it is always stroked too).
  final bool fillBody;

  /// The body's fill, as a fraction of the icon's colour.
  final double bodyFillOpacity;

  /// Stroke widths, in the icon's own 24-unit box.
  final double bodyStroke;
  final double lineStroke;

  /// Square caps and mitred joins (`sharp`); otherwise round caps and joins.
  final bool square;

  @override
  bool operator ==(Object other) =>
      other is IconTreatment &&
      other.fillBody == fillBody &&
      other.bodyFillOpacity == bodyFillOpacity &&
      other.bodyStroke == bodyStroke &&
      other.lineStroke == lineStroke &&
      other.square == square;

  @override
  int get hashCode => Object.hash(fillBody, bodyFillOpacity, bodyStroke, lineStroke, square);

  @override
  String toString() =>
      'IconTreatment(fill: $fillBody@$bodyFillOpacity, body: $bodyStroke, lines: $lineStroke, square: $square)';
}

abstract final class SdkIcons {
  static const SdkIcon mic = SdkIcon(
    body: 'M12 2.5a3.5 3.5 0 0 0-3.5 3.5v6a3.5 3.5 0 0 0 7 0V6A3.5 3.5 0 0 0 12 2.5z',
    lines: 'M18.5 11.5a6.5 6.5 0 0 1-13 0M12 18v3.5',
  );
  static const SdkIcon micOff = SdkIcon(
    body: 'M12 2.5a3.5 3.5 0 0 0-3.5 3.5v6a3.5 3.5 0 0 0 7 0V6A3.5 3.5 0 0 0 12 2.5z',
    lines: 'M18.5 11.5a6.5 6.5 0 0 1-13 0M12 18v3.5M4 4l16 16',
  );
  static const SdkIcon end = SdkIcon(
    body: 'M4.2 14.6c4.6-4.1 11-4.1 15.6 0 .6.5.6 1.4.1 2l-1.3 1.4c-.4.5-1.1.6-1.7.3l-2.2-1.2c-.5-.3-.8-.8-.7-1.4'
        'l.2-1.3a11 11 0 0 0-4.4 0l.2 1.3c.1.6-.2 1.1-.7 1.4l-2.2 1.2c-.6.3-1.3.2-1.7-.3L4.1 16.6c-.5-.6-.5-1.5.1-2z',
  );
  static const SdkIcon send = SdkIcon(body: 'M4 12 20 4l-4 16-4.5-6.5L4 12z', lines: 'M11.5 13.5 20 4');
  static const SdkIcon chat = SdkIcon(body: 'M20 12a8 8 0 0 1-11.6 7.1L4 20l1-4.2A8 8 0 1 1 20 12z');
  static const SdkIcon call = SdkIcon(
    lines: 'M13.832 16.568a1 1 0 0 0 1.213 -0.303l0.355 -0.465A2 2 0 0 1 17 15h3a2 2 0 0 1 2 2v3a2 2 0 0 1 -2 2'
        'A18 18 0 0 1 2 4a2 2 0 0 1 2 -2h3a2 2 0 0 1 2 2v3a2 2 0 0 1 -0.8 1.6l-0.468 0.351a1 1 0 0 0 -0.292 1.233'
        'a14 14 0 0 0 6.392 6.384',
  );

  /// Points UP as drawn; the chat header turns it 180°.
  static const SdkIcon chevron = SdkIcon(lines: 'M6 15l6-6 6 6');
  static const SdkIcon close = SdkIcon(lines: 'M6 6l12 12M18 6 6 18');

  /// "New conversation" in a chat window's header: a page and a pen.
  static const SdkIcon compose =
      SdkIcon(lines: 'M12 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7M18.4 2.6a2.1 2.1 0 0 1 3 3L12 15l-4 1 1-4z');

  /// The call screen's loudspeaker, for an app drawing its own call screen.
  static const SdkIcon speaker =
      SdkIcon(body: 'M4 9.5h3.5L12 5.5v13l-4.5-4H4z', lines: 'M15.5 9a4 4 0 0 1 0 6M18 6.5a7.5 7.5 0 0 1 0 11');

  // The chat window v2's own (contract/DESIGN.md "Chat window v2").

  /// The composer's paperclip, where the app handles attachments.
  static const SdkIcon attach = SdkIcon(
    lines: 'M21.44 11.05l-9.19 9.19a6 6 0 0 1-8.49-8.49l8.57-8.57A4 4 0 1 1 18 8.84l-8.59 8.57a2 2 0 0 1-2.83-2.83l8.49-8.48',
  );

  /// The rating's thumbs.
  static const SdkIcon thumbUp = SdkIcon(
    body: 'M15 5.88L14 10h5.83a2 2 0 0 1 1.92 2.56l-2.33 8A2 2 0 0 1 17.5 22H4a2 2 0 0 1-2-2v-8a2 2 0 0 1 2-2h2.76'
        'a2 2 0 0 0 1.79-1.11L12 2a3.13 3.13 0 0 1 3 3.88z',
    lines: 'M7 10v12',
  );
  static const SdkIcon thumbDown = SdkIcon(
    body: 'M9 18.12L10 14H4.17a2 2 0 0 1-1.92-2.56l2.33-8A2 2 0 0 1 6.5 2H20a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-2.76'
        'a2 2 0 0 0-1.79 1.11L12 22a3.13 3.13 0 0 1-3-3.88z',
    lines: 'M17 14V2',
  );

  /// The rating's stars: filled up to the choice, stroked after it.
  static const SdkIcon star = SdkIcon(
    body: 'M11.525 2.295a0.53 0.53 0 0 1 0.95 0l2.31 4.679a2.123 2.123 0 0 0 1.595 1.16l5.166 0.756a0.53 0.53 0 0 1 '
        '0.294 0.904l-3.736 3.638a2.123 2.123 0 0 0 -0.611 1.878l0.882 5.14a0.53 0.53 0 0 1 -0.771 0.56l-4.618 -2.428'
        'a2.122 2.122 0 0 0 -1.973 0L6.396 21.01a0.53 0.53 0 0 1 -0.77 -0.56l0.881 -5.139a2.122 2.122 0 0 0 -0.611 '
        '-1.879L2.16 9.795a0.53 0.53 0 0 1 0.294 -0.906l5.165 -0.755a2.122 2.122 0 0 0 1.597 -1.16z',
  );

  /// The scroll-to-latest pill.
  static const SdkIcon arrowDown = SdkIcon(lines: 'M12 5v14M19 12l-7 7-7-7');

  /// A message's delivery: sent, waiting, not sent.
  static const SdkIcon check = SdkIcon(lines: 'M20 6L9 17l-5-5');
  static const SdkIcon clock = SdkIcon(body: 'M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18z', lines: 'M12 7.5V12l3 2');
  static const SdkIcon alert = SdkIcon(body: 'M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18z', lines: 'M12 7.5v5M12 16.25v0.01');

  /// Try again.
  static const SdkIcon retry =
      SdkIcon(lines: 'M3 12a9 9 0 0 1 15.36-6.36L21 8M21 3v5h-5M21 12a9 9 0 0 1-15.36 6.36L3 16M3 21v-5h5');

  /// The whole set, by the names the contract uses.
  static const Map<String, SdkIcon> all = <String, SdkIcon>{
    'mic': mic,
    'micOff': micOff,
    'end': end,
    'send': send,
    'chat': chat,
    'call': call,
    'chevron': chevron,
    'close': close,
    'compose': compose,
    'speaker': speaker,
    'attach': attach,
    'thumbUp': thumbUp,
    'thumbDown': thumbDown,
    'star': star,
    'arrowDown': arrowDown,
    'check': check,
    'clock': clock,
    'alert': alert,
    'retry': retry,
  };

  /// HOW [style] DRAWS AN ICON AT [stroke] (contract/DESIGN.md, "Icons"):
  ///
  ///  - `outline` — stroked, round caps and joins;
  ///  - `sharp` — stroked, square caps, mitred joins;
  ///  - `filled` — the body filled, stroked at 0.75 × the stroke (at least 1);
  ///  - `duotone` — the body filled at 28%, then stroked.
  ///
  /// A style this build does not know is drawn as `outline`.
  static IconTreatment treatment(String style, double stroke) {
    switch (style) {
      case 'sharp':
        return IconTreatment(fillBody: false, bodyFillOpacity: 0, bodyStroke: stroke, lineStroke: stroke, square: true);
      case 'filled':
        return IconTreatment(
            fillBody: true,
            bodyFillOpacity: 1,
            bodyStroke: math.max(1, stroke * 0.75),
            lineStroke: stroke,
            square: false);
      case 'duotone':
        return IconTreatment(
            fillBody: true, bodyFillOpacity: 0.28, bodyStroke: stroke, lineStroke: stroke, square: false);
      default: // outline
        return IconTreatment(
            fillBody: false, bodyFillOpacity: 0, bodyStroke: stroke, lineStroke: stroke, square: false);
    }
  }
}
