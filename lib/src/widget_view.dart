import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'core/core.dart';
import 'graine.dart';
import 'loader_view.dart';
import 'style.dart';

/// Single-colour overrides for [GraineWidgetView]. Null keeps the dashboard's.
@immutable
class GraineWidgetTheme {
  const GraineWidgetTheme({this.surface, this.border, this.text, this.muted, this.onAccent});

  /// Behind the component.
  final Color? surface;

  /// Hairlines and chip fills.
  final Color? border;

  /// Titles and prices.
  final Color? text;

  /// Subtitles, facts, secondary labels.
  final Color? muted;

  /// Readable ON the accent.
  final Color? onAccent;
}

/// THE COMPONENT THE AGENT PUT ON SCREEN — drawn by the SDK, not by the host.
///
/// The React Native SDK's GraineWidget, drawing the same kinds the same way:
/// a product list with pictures in five looks (gallery, cards, list,
/// spotlight, compact), a plan comparison, an info card, chips for choices
/// and quick actions, calendar slots — and, for a kind this build cannot
/// draw, the agent's own fallback sentence rather than a guess. Choosing one
/// answers at once; choosing several (`select: "many"`) ticks rows and
/// answers once with every choice, named in one sentence.
///
/// While a component is on its way the dashboard's loader stands where it
/// will appear, for at least [Widgets.minLoaderMs]. After an answer the
/// choice stays as one line, with the loader until the agent replies.
///
/// Drawn inline, in the surface's own chrome (a card with Dismiss, a sheet
/// with "None of these", a screen with "Still listening"): place it where
/// the component should appear — [GraineAgentBar] mounts one above itself.
/// State comes from [components] (default: [GraineInApp.components]).
class GraineWidgetView extends StatefulWidget {
  const GraineWidgetView({
    super.key,
    this.components,
    this.accent,
    this.radius,
    this.scheme,
    this.theme,
    this.appearance,
    this.maxHeight = 460,
  });

  /// The state to draw. Default: [GraineInApp.instance]'s.
  final GraineComponents? components;

  /// #RRGGBB for buttons and badges. Default: the component's own, then the dashboard's.
  final String? accent;

  /// Corner rounding. Default: the component's own, then a pinned platform's, then the dashboard's.
  final double? radius;

  /// "light", "dark" or "auto" (the device). Default: the dashboard's theme.
  final String? scheme;
  final GraineWidgetTheme? theme;

  /// The dashboard's Appearance. Default: the session's.
  final Map<String, Object?>? appearance;

  /// The most height the component may take; its body scrolls inside.
  final double maxHeight;

  @override
  State<GraineWidgetView> createState() => _GraineWidgetViewState();
}

const Map<String, double> _heroHeight = <String, double>{'small': 100, 'medium': 140, 'large': 180};
const Map<String, double> _thumb = <String, double>{'small': 56, 'medium': 72, 'large': 96};
const Map<String, double> _listThumb = <String, double>{'small': 36, 'medium': 44, 'large': 56};

/// Everything a render needs to know about colour and shape, resolved once.
class _Skin {
  _Skin({
    required this.accent,
    required this.surface,
    required this.border,
    required this.text,
    required this.muted,
    required this.onAccent,
    required this.radius,
    required this.grammar,
    required this.loader,
    required this.loaderColor,
    required this.logoUrl,
    required this.dark,
  });

  factory _Skin.resolve(BuildContext context, GraineWidgetView w, WidgetLook? look) {
    final app = GraineInApp.maybeInstance;
    final appearance = w.appearance ?? app?.session?.appearance;
    final dash = Appearance.resolve(appearance,
        accent: Appearance.defaultAccent, heading: '', origin: app?.config.baseUrl);
    final os = defaultTargetPlatform == TargetPlatform.android ? 'android' : 'ios';
    final grammar = Widgets.grammar[Widgets.resolvePlatform(look?.platform ?? 'auto', os)]!;
    final accentHex = (w.accent != null && Appearance.argb(w.accent) != null) ? w.accent! : (look?.accent ?? dash.accent);
    final radius = w.radius ??
        look?.radius?.toDouble() ??
        ((look != null && look.platform != 'auto') ? grammar.radius.toDouble() : dash.radius);
    final palette = Appearance.palette(
      w.scheme != null ? <String, Object?>{'theme': w.scheme} : appearance,
      deviceDark: deviceDark(context),
      accent: accentHex,
    );
    final loader = Loaders.resolve(appearance?['loader']);
    final accent = colorOf(accentHex) ?? colorOf(Appearance.defaultAccent)!;
    final t = w.theme;
    return _Skin(
      accent: accent,
      surface: t?.surface ?? colorOf(palette.surface)!,
      border: t?.border ?? colorOf(palette.border)!,
      text: t?.text ?? colorOf(palette.text)!,
      muted: t?.muted ?? colorOf(palette.muted)!,
      onAccent: t?.onAccent ?? colorOf(palette.onAccent)!,
      radius: radius,
      grammar: grammar,
      loader: loader,
      // The loader's own colour, else the DASHBOARD's accent — as the RN GraineLoader draws it.
      loaderColor: colorOf(loader.color) ?? colorOf(dash.accent) ?? accent,
      logoUrl: dash.logoUrl,
      dark: palette.mode == 'dark',
    );
  }

  final Color accent;
  final Color surface;
  final Color border;
  final Color text;
  final Color muted;
  final Color onAccent;
  final double radius;
  final PlatformGrammar grammar;
  final LoaderLook loader;
  final Color loaderColor;
  final String? logoUrl;
  final bool dark;

  Color tint(double a) => fade(accent, a);
  Color borderTint(double a) => fade(border, a);
}

class _GraineWidgetViewState extends State<GraineWidgetView> {
  /// Ids ticked so far, when the component lets them choose several.
  List<String> _ticked = const <String>[];
  String? _tickedFor;

  /// Which spotlight card is in view.
  int _page = 0;

  GraineComponents? get _components => widget.components ?? GraineInApp.maybeInstance?.components;

  @override
  Widget build(BuildContext context) {
    final c = _components;
    if (c == null) return const SizedBox.shrink();
    final session = GraineInApp.maybeInstance?.sessionListenable;
    return ListenableBuilder(
      listenable: session == null ? c : Listenable.merge(<Listenable>[c, session]),
      builder: (BuildContext context, Widget? _) => _draw(context, c),
    );
  }

  Widget _draw(BuildContext context, GraineComponents c) {
    final w = c.widget;
    final content = c.content;
    final look = c.look;
    if (w?.id != _tickedFor) {
      // A new component starts with nothing ticked.
      _ticked = const <String>[];
      _tickedFor = w?.id;
      _page = 0;
    }
    final s = _Skin.resolve(context, widget, look);
    final children = <Widget>[];
    final answered = c.answered;
    if (answered != null) {
      final line = _answeredLine(c, answered, s);
      if (line != null) children.add(line);
    }
    if (w != null && content != null && look != null) {
      children.add(Flexible(child: _component(c, w, content, look, s)));
    } else {
      final pending = c.loading;
      if (pending != null) children.add(_pending(c, pending, s));
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return DefaultTextStyle(
      style: textStyle(s.text, 14),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  // ── the answered line ────────────────────────────────────────────────────

  Widget? _answeredLine(GraineComponents c, WidgetAnswered a, _Skin s) {
    final line = WidgetContent.answeredLine(a.data);
    if (line.title.isEmpty && line.detail.isEmpty) return null;
    final awaiting = c.awaitingReply;
    final second = awaiting ? s.loader.text.thinking : (line.title.isNotEmpty && line.detail.isNotEmpty ? line.detail : null);
    return Container(
      key: const ValueKey<String>('graine-answered'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(s.radius),
        border: Border.all(color: s.border),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: s.tint(0.18), shape: BoxShape.circle),
            // Waiting, then done: a tick before the agent has said anything reads as "handled".
            child: awaiting
                ? GraineLoaderView(look: s.loader, color: s.loaderColor, trackColor: s.border, size: 14, logoUrl: s.logoUrl)
                : Text('✓', style: textStyle(s.accent, 14, weight: 800)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(line.title.isNotEmpty ? line.title : line.detail,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: textStyle(s.text, 13.5, weight: 700)),
                if (second != null)
                  Text(second, maxLines: 1, overflow: TextOverflow.ellipsis, style: textStyle(s.muted, 11.5, weight: 600)),
              ],
            ),
          ),
          if (!awaiting)
            Tap(
              key: const ValueKey<String>('graine-clear'),
              label: 'Clear what I chose',
              onTap: c.dismiss,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Center(widthFactor: 1, child: Text('Clear', style: textStyle(s.muted, 12, weight: 700))),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── a component on its way ───────────────────────────────────────────────

  Widget _pending(GraineComponents c, WidgetPending pending, _Skin s) {
    // The surface the COMPONENT will take, so the wait and the thing it becomes share a shape.
    final surface = Widgets.surface(pending.kind);
    final double? size = surface == 'screen' ? 34 : (surface == 'sheet' ? 26 : null);
    final loader = GraineLoaderView(
      look: s.loader,
      color: s.loaderColor,
      trackColor: s.border,
      labelColor: s.muted,
      label: s.loader.text.component,
      size: size,
      stacked: surface != 'card',
      logoUrl: s.logoUrl,
    );
    return Container(
      key: const ValueKey<String>('graine-pending'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: surface == 'card' ? 14 : 24),
      decoration: _boxDecoration(s),
      child: Stack(
        children: <Widget>[
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Center(child: loader),
              if (s.loader.skeleton) ...<Widget>[const SizedBox(height: 16), _bones(s, surface == 'screen' ? 3 : 2)],
            ],
          ),
          // A way out, always: a component that never arrives must not trap anyone.
          if (surface != 'card')
            Positioned(top: -12, right: -4, child: _closeButton(c, s, size: 32)),
        ],
      ),
    );
  }

  Widget _bones(_Skin s, int rows) {
    Widget bone(double? w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: s.borderTint(0.6), borderRadius: BorderRadius.circular(8)),
        );
    return ExcludeSemantics(
      child: Opacity(
        opacity: 0.55,
        child: Column(
          children: <Widget>[
            for (var i = 0; i < rows; i++)
              Container(
                margin: EdgeInsets.only(bottom: i == rows - 1 ? 0 : 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(math.max(10, s.radius - 6)),
                  border: Border.all(color: s.border),
                ),
                child: Row(
                  children: <Widget>[
                    bone(72, 72),
                    const SizedBox(width: 10),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (BuildContext context, BoxConstraints box) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            bone(box.maxWidth * 0.7, 12),
                            const SizedBox(height: 8),
                            bone(box.maxWidth * 0.4, 12),
                            const SizedBox(height: 8),
                            bone(box.maxWidth * 0.55, 10),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── the component ────────────────────────────────────────────────────────

  BoxDecoration _boxDecoration(_Skin s, {BorderRadius? radius}) => BoxDecoration(
        color: s.surface,
        borderRadius: radius ?? BorderRadius.circular(s.radius),
        border: Border.all(color: s.border),
        boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x2E000000), blurRadius: 12, offset: Offset(0, 4))],
      );

  Widget _closeButton(GraineComponents c, _Skin s, {double size = 44}) => Tap(
        key: const ValueKey<String>('graine-close'),
        label: 'Close and keep talking',
        onTap: c.dismiss,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: s.borderTint(0.4), shape: BoxShape.circle),
          child: Text('×', style: textStyle(s.text, 20, weight: 600, height: 1)),
        ),
      );

  Widget _component(GraineComponents c, GraineWidget w, WidgetContent content, WidgetLook look, _Skin s) {
    final surface = content.surface(look);
    final many = content.many(look);
    final body = SingleChildScrollView(child: _body(c, w, content, look, s, many));
    final title = content.title;
    final prompt = content.prompt;

    if (surface == 'screen') {
      // The component IS the screen. The agent is still on the call; saying so is
      // the difference between a screen it opened and a screen that replaced it.
      return Container(
        key: const ValueKey<String>('graine-surface-screen'),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: _boxDecoration(s),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Row(
                children: <Widget>[
                  _closeButton(c, s, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (title.isNotEmpty)
                          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: textStyle(s.text, 18, weight: 800)),
                        if (prompt.isNotEmpty)
                          Text(prompt,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: textStyle(s.muted, 12.5, weight: 600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Flexible(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: body)),
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: s.border))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text('STILL LISTENING', style: textStyle(s.muted, 10.5, weight: 800, letterSpacing: 0.4)),
                  const SizedBox(height: 2),
                  Text(prompt.isNotEmpty ? prompt : 'Tap one, or just say it.',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: textStyle(s.text, 13.5)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (surface == 'sheet') {
      // A choice to finish. Not answering is an answer: "None of these" is always there.
      final top = Radius.circular(math.max(20, s.radius));
      return Container(
        key: const ValueKey<String>('graine-surface-sheet'),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
        decoration: _boxDecoration(s, radius: BorderRadius.only(topLeft: top, topRight: top,
            bottomLeft: Radius.circular(s.radius), bottomRight: Radius.circular(s.radius))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: s.grammar.grabberWidth.toDouble(),
                height: s.grammar.grabberHeight.toDouble(),
                decoration: BoxDecoration(color: s.border, borderRadius: BorderRadius.circular(999)),
              ),
            ),
            const SizedBox(height: 14),
            if (title.isNotEmpty) Text(title, style: textStyle(s.text, 18, weight: 800)),
            if (prompt.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(prompt, style: textStyle(s.muted, 13, height: 18 / 13)),
            ],
            const SizedBox(height: 14),
            Flexible(child: body),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Tap(
                key: const ValueKey<String>('graine-dismiss'),
                label: 'None of these',
                onTap: c.dismiss,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(color: s.borderTint(0.4), borderRadius: BorderRadius.circular(999)),
                  child: Center(widthFactor: 1, child: Text('None of these', style: textStyle(s.text, 13.5, weight: 700))),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // A card: never covers the app. The smallest interruption, for what deserves the smallest one.
    return Container(
      key: const ValueKey<String>('graine-surface-card'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      decoration: _boxDecoration(s),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (title.isNotEmpty) ...<Widget>[
            Text(title, style: textStyle(s.text, 14.5, weight: 800)),
            const SizedBox(height: 2),
          ],
          if (prompt.isNotEmpty) ...<Widget>[
            Text(prompt, style: textStyle(s.muted, 12.5, height: 17 / 12.5)),
            const SizedBox(height: 8),
          ] else
            const SizedBox(height: 6),
          Flexible(child: body),
          Align(
            alignment: Alignment.centerRight,
            child: Tap(
              key: const ValueKey<String>('graine-dismiss'),
              label: 'Dismiss',
              onTap: c.dismiss,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Center(widthFactor: 1, child: Text('Dismiss', style: textStyle(s.muted, 12.5, weight: 600))),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(GraineComponents c, GraineWidget w, WidgetContent content, WidgetLook look, _Skin s, bool many) {
    if (content.isCalendar) return _calendar(c, content, s);
    if (content.isProducts) return _products(c, content, look, s, many);
    if (content.isChips) return _chips(c, content, s);
    // A kind this build does not draw: the sentence the agent would have said instead.
    return Text(
      w.fallbackText.isNotEmpty ? w.fallbackText : 'The assistant has something to show you.',
      style: textStyle(s.text, 14, height: 20 / 14),
    );
  }

  Widget _calendar(GraineComponents c, WidgetContent content, _Skin s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (content.note.isNotEmpty) ...<Widget>[
          Text(content.note, style: textStyle(s.muted, 12.5, height: 18 / 12.5)),
          const SizedBox(height: 12),
        ],
        for (final day in content.days) ...<Widget>[
          Text(day.label, style: textStyle(s.text, 13, weight: 700)),
          const SizedBox(height: 7),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final slot in day.slots)
                Tap(
                  key: ValueKey<String>('graine-slot-${day.label}-$slot'),
                  label: '${day.label} at $slot',
                  onTap: () => c.answer(content.pickSlot(day, slot)),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(border: Border.all(color: s.border), borderRadius: BorderRadius.circular(11)),
                    child: Center(widthFactor: 1, child: Text(slot, style: textStyle(s.text, 13.5, weight: 600))),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _chips(GraineComponents c, WidgetContent content, _Skin s) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final chip in content.chips)
          Tap(
            key: ValueKey<String>('graine-chip-${chip.id}'),
            label: chip.label,
            onTap: () => c.answer(content.pickChip(chip)),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(color: s.accent, borderRadius: BorderRadius.circular(999)),
              child: Center(widthFactor: 1, child: Text(chip.label, style: textStyle(s.onAccent, 13.5, weight: 700))),
            ),
          ),
      ],
    );
  }

  Widget _products(GraineComponents c, WidgetContent content, WidgetLook look, _Skin s, bool many) {
    final gap = look.density == 'compact' ? 6.0 : 10.0;
    Widget draw(int i, String variant) {
      final row = content.rows[i];
      return _row(
        row: row,
        variant: variant,
        look: look,
        s: s,
        picked: many ? _ticked.contains(row.id) : null,
        onPick: () {
          if (many) {
            setState(() => _ticked = WidgetContent.toggle(_ticked, row.id, look.maxSelect));
          } else {
            c.answer(content.pick(i));
          }
        },
      );
    }

    final count = content.rows.length;
    Widget list;
    if (look.preset == 'spotlight') {
      list = _spotlight(count, gap, s, draw);
    } else if (look.columns == 2) {
      // A grid of picture-on-top tiles, for Gallery and Cards only.
      list = LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final tile = (box.maxWidth - gap) / 2;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: <Widget>[for (var i = 0; i < count; i++) SizedBox(width: tile, child: draw(i, 'hero'))],
          );
        },
      );
    } else {
      final variant = switch (look.preset) {
        'gallery' => 'hero',
        'list' => 'list',
        'compact' => 'compact',
        _ => 'row',
      };
      list = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < count; i++) ...<Widget>[
            if (i > 0 && variant != 'list') SizedBox(height: gap),
            draw(i, variant),
          ],
        ],
      );
    }
    if (!many) return list;

    // ONE BUTTON, ONE TURN. Disabled below two: a comparison of one is the
    // single-tap case wearing a different control.
    final chosen = _ticked.where((String id) => content.rows.any((WidgetRow r) => r.id == id)).length;
    final ready = chosen >= 2;
    final label = content.manyButtonLabel(chosen);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        list,
        const SizedBox(height: 12),
        Tap(
          key: const ValueKey<String>('graine-many-submit'),
          label: label,
          enabled: ready,
          onTap: () {
            final a = content.pickMany(_ticked);
            setState(() => _ticked = const <String>[]);
            c.answer(a);
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ready ? s.accent : s.borderTint(0.5),
              borderRadius: BorderRadius.circular(s.grammar.pillButtons ? 999 : s.grammar.buttonRadius.toDouble()),
            ),
            child: Text(label, style: textStyle(ready ? s.onAccent : s.muted, 14.5, weight: 700)),
          ),
        ),
      ],
    );
  }

  /// One card in view, swipe for the next, dots for where you are. The card is
  /// 86% of the width so the next one's edge shows — that edge says "there are more".
  Widget _spotlight(int count, double gap, _Skin s, Widget Function(int, String) draw) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final cardW = (box.maxWidth * 0.86).roundToDouble();
        final step = cardW + gap;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            NotificationListener<ScrollNotification>(
              onNotification: (ScrollNotification n) {
                final int p = math.min(math.max(0, (n.metrics.pixels / step).round()), math.max(0, count - 1));
                if (p != _page) setState(() => _page = p);
                return false;
              },
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (var i = 0; i < count; i++)
                      Padding(
                        padding: EdgeInsets.only(right: i == count - 1 ? 24 : gap),
                        child: SizedBox(width: cardW, child: draw(i, 'hero')),
                      ),
                  ],
                ),
              ),
            ),
            if (count > 1)
              Semantics(
                label: '${math.min(_page + 1, count)} of $count',
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      for (var i = 0; i < count; i++)
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2.5),
                          width: i == _page ? 14 : 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: i == _page ? s.accent : s.border,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// ONE ROW, FOUR SHAPES. The preset picks the shape; the knobs size it.
  ///
  ///   hero     picture on top, full-width button — Gallery and Spotlight
  ///   row      thumbnail left, pill button — Cards
  ///   list     dense, the row is the button — List
  ///   compact  no picture at all, outline button — Compact
  Widget _row({
    required WidgetRow row,
    required String variant,
    required WidgetLook look,
    required _Skin s,
    required bool? picked,
    required VoidCallback onPick,
  }) {
    final many = picked != null;
    final r = math.max(10.0, s.radius - 6);
    final tight = look.density == 'compact';
    final double pad = (variant == 'list' ? (tight ? 6.0 : 9.0) : (tight ? 7.0 : 10.0)) + s.grammar.padBoost;
    final gap = tight ? 6.0 : 10.0;
    // Choosing several: the ROW toggles, always — a per-row button beside a tick
    // is two controls for one decision.
    final rowIsButton = many || look.button == 'row';
    final outline = look.button == 'outline';
    final label = row.unavailable ? 'Unavailable' : row.selectLabel;
    final a11y = '${row.selectLabel}: ${row.title}';
    final isList = variant == 'list';

    Widget? badge() => row.subtitle.isEmpty
        ? null
        : Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: s.tint(0.15), borderRadius: BorderRadius.circular(999)),
              child: Text(row.subtitle.toUpperCase(), style: textStyle(s.accent, 10.5, weight: 800, letterSpacing: 0.4)),
            ),
          );

    Widget titleLine(bool big) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Text(row.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle(s.text, big ? 16.5 : (isList ? 13.5 : 14.5), weight: s.grammar.titleWeight)),
            ),
            if (row.price.isNotEmpty) ...<Widget>[
              const SizedBox(width: 8),
              Text(row.price, style: textStyle(s.text, big ? 17 : (isList ? 13.5 : 14.5), weight: 800)),
            ],
          ],
        );

    Widget? facts() {
      if (!look.facts || row.facts.isEmpty) return null;
      final shown = isList ? row.facts.take(2) : row.facts;
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: <Widget>[
          for (final f in shown)
            Container(
              padding: EdgeInsets.symmetric(horizontal: isList ? 6 : 8, vertical: isList ? 2 : 4),
              decoration: BoxDecoration(
                color: s.grammar.chipOutlined ? null : s.borderTint(0.35),
                border: s.grammar.chipOutlined ? Border.all(color: s.border) : null,
                borderRadius: BorderRadius.circular(s.grammar.chipRadius.toDouble()),
              ),
              child: Text(f, style: textStyle(s.muted, isList ? 10.5 : 11.5, weight: 600)),
            ),
        ],
      );
    }

    Widget tick() => Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: picked == true ? s.accent : null,
            shape: BoxShape.circle,
            border: picked == true ? null : Border.all(color: s.border, width: 1.5),
          ),
          child: picked == true ? Text('✓', style: textStyle(s.onAccent, 12, weight: 800, height: 1)) : null,
        );

    Widget button(bool wide) {
      final quiet = row.unavailable || outline;
      return Tap(
        label: a11y,
        enabled: !row.unavailable,
        onTap: onPick,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          margin: EdgeInsets.only(top: wide ? 8 : 0),
          padding: EdgeInsets.symmetric(horizontal: wide ? 12 : 14),
          alignment: wide ? Alignment.center : null,
          decoration: BoxDecoration(
            color: quiet ? null : s.accent,
            border: quiet ? Border.all(color: row.unavailable ? s.border : s.accent, width: 1.5) : null,
            borderRadius: BorderRadius.circular(
                wide ? s.grammar.buttonRadius.toDouble() : (s.grammar.pillButtons ? 999 : s.grammar.buttonRadius.toDouble())),
          ),
          child: Center(
            widthFactor: wide ? null : 1,
            child: Text(label,
                style: textStyle(row.unavailable ? s.muted : (outline ? s.accent : s.onAccent), wide ? 14 : 12.5, weight: 700)),
          ),
        ),
      );
    }

    Widget? image(double w, double h) => row.image.isEmpty
        ? null
        : ClipRRect(
            borderRadius: BorderRadius.circular(math.max(8, s.radius - 8)),
            child: Container(
              width: w,
              height: h,
              color: s.border,
              child: Image.network(
                row.image,
                width: w,
                height: h,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                errorBuilder: (BuildContext c, Object e, StackTrace? st) => const SizedBox.shrink(),
              ),
            ),
          );

    BoxDecoration framed() => BoxDecoration(
          borderRadius: BorderRadius.circular(r),
          border: Border.all(color: picked == true ? s.accent : s.border, width: picked == true ? 2 : 1),
        );

    Widget wrap(Widget child) => KeyedSubtree(
          key: ValueKey<String>('graine-row-${row.id}'),
          child: Opacity(
            opacity: row.unavailable ? 0.55 : 1,
            child: rowIsButton
                ? Tap(label: a11y, enabled: !row.unavailable, onTap: onPick, child: child)
                : child,
          ),
        );

    List<Widget> column(List<Widget?> parts, double spacing) {
      final out = <Widget>[];
      for (final p in parts) {
        if (p == null) continue;
        if (out.isNotEmpty) out.add(SizedBox(height: spacing));
        out.add(p);
      }
      return out;
    }

    switch (variant) {
      case 'hero':
        return wrap(Container(
          padding: EdgeInsets.all(pad),
          decoration: framed(),
          child: Stack(
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: column(<Widget?>[
                  image(double.infinity, _heroHeight[look.imageSize] ?? 140),
                  badge(),
                  titleLine(true),
                  facts(),
                  (many || rowIsButton) ? null : button(true),
                ], 3),
              ),
              if (many) Positioned(top: 6, right: 6, child: tick()),
            ],
          ),
        ));
      case 'list':
        final t = _listThumb[look.imageSize] ?? 44;
        return wrap(Container(
          constraints: const BoxConstraints(minHeight: 44),
          margin: EdgeInsets.only(left: s.grammar.separatorInset.toDouble()),
          padding: EdgeInsets.symmetric(vertical: pad, horizontal: 2),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: s.border))),
          child: Row(
            children: <Widget>[
              if (image(t, t) != null) ...<Widget>[image(t, t)!, SizedBox(width: gap)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: column(<Widget?>[titleLine(false), facts()], 2),
                ),
              ),
              SizedBox(width: gap),
              if (many)
                tick()
              else if (rowIsButton)
                Padding(padding: const EdgeInsets.only(left: 4), child: Text('›', style: textStyle(s.muted, 22, weight: 600)))
              else
                button(false),
            ],
          ),
        ));
      case 'compact':
        return wrap(Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: EdgeInsets.symmetric(vertical: pad, horizontal: pad + 2),
          decoration: framed(),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: column(<Widget?>[badge(), titleLine(false), facts()], 2),
                ),
              ),
              if (many) ...<Widget>[SizedBox(width: gap), tick()] else if (!rowIsButton) ...<Widget>[
                SizedBox(width: gap),
                button(false),
              ],
            ],
          ),
        ));
      default: // row — Cards, what a component with no chosen look draws
        final t = _thumb[look.imageSize] ?? 72;
        return wrap(Container(
          padding: EdgeInsets.all(pad),
          decoration: framed(),
          child: Row(
            children: <Widget>[
              if (image(t, t) != null) ...<Widget>[image(t, t)!, SizedBox(width: gap)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: column(<Widget?>[badge(), titleLine(false), facts()], 3),
                ),
              ),
              if (many) ...<Widget>[SizedBox(width: gap), tick()] else if (!rowIsButton) ...<Widget>[
                SizedBox(width: gap),
                button(false),
              ],
            ],
          ),
        ));
    }
  }
}
