// THE BOOKING SHEET, DRAWN BY THE SDK — "Call me at…" with no screen of the
// app's own (BOOKING-SHEET.md), in the agent's design: the day, the time
// (Flutter's own time picker), what it is about, Book call, and one line per
// refusal. The rules and the words are the core's (core/booking.dart), the
// same on every platform.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart'
    show DefaultMaterialLocalizations, MaterialLocalizations, TimeOfDay, TimePickerEntryMode, showTimePicker;
import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter, TextInputAction;
import 'package:flutter/widgets.dart';

import 'chat_window.dart' show ChatLook;
import 'core/core.dart';
import 'graine.dart';
import 'loader_view.dart';
import 'sdk_icon.dart';
import 'style.dart';

/// OPEN THE SDK'S BOOKING SHEET — a sheet up from the bottom of a phone, a
/// centred panel on a tablet — over [context]'s navigator:
///
///     if (graine.bookingAvailable) {
///       final call = await GraineBooking.show(context, reason: 'Renewal');
///     }
///
/// [reason] fills "What's it about?", which the user may change. Completes
/// with the call booked, or null when the user closed the sheet without
/// booking. [app]: the agent to book with (the default agent unless given).
/// Opened while booking is not available, the sheet says why and does not
/// book.
abstract final class GraineBooking {
  static Future<GraineScheduledCall?> show(BuildContext context, {GraineInApp? app, String? reason}) async {
    final agent = app ?? GraineInApp.maybeInstance;
    if (agent == null) {
      debugPrint('[Graine] GraineBooking.show before GraineInApp.init: there is no agent to book with.');
      return null;
    }
    final tokens = tokensFor(context, app: agent);
    final media = MediaQuery.of(context);
    final phone = media.size.shortestSide < ChatWindowLayout.tabletMinSide;
    final motion = motionOf(context, tokens);
    final curve = curveOf(tokens);
    final scrim = tokens != null ? tokenColor(tokens.colors.scrim) : const Color(0xFF000000);
    GraineScheduledCall? booked;
    final closed = await showGeneralDialog<GraineScheduledCall>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: fade(scrim, ChatWindowLayout.scrimOpacity),
      transitionDuration: motion,
      pageBuilder: (BuildContext route, Animation<double> _, Animation<double> __) {
        void close() => Navigator.of(route).pop(booked);
        final m = MediaQuery.of(route);
        final sheet = GraineBookingSheet(
          app: agent,
          reason: reason,
          onBooked: (GraineScheduledCall call) => booked = call,
          onClose: close,
          sheet: phone,
        );
        if (phone) {
          final top = m.padding.top + ChatWindowLayout.sheetTop * m.size.height;
          return Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(constraints: BoxConstraints(maxHeight: math.max(0, m.size.height - top)), child: sheet),
          );
        }
        return Center(
          child: Padding(
            padding: EdgeInsets.only(bottom: m.viewInsets.bottom),
            child: SizedBox(
              width: math.min(ChatWindowLayout.panelWidth, math.max(0, m.size.width - 48)),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: ChatWindowLayout.panelSize(m.size.height).height),
                child: sheet,
              ),
            ),
          ),
        );
      },
      transitionBuilder: (BuildContext _, Animation<double> animation, Animation<double> __, Widget child) => phone
          ? SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                  .animate(CurvedAnimation(parent: animation, curve: curve)),
              child: child,
            )
          : FadeTransition(opacity: animation, child: child),
    );
    // Booked, then closed by a tap beside it rather than Done: still the call.
    return closed ?? booked;
  }
}

/// THE BOOKING SHEET ITSELF — for an app that presents it in its own way:
/// "Book a call", "{call name} will call you", chips from today to the last
/// bookable day, the time (Flutter's time picker, the choice clamped to what
/// the agent allows), the time zone, "What's it about? (optional)", Book
/// call — then "Booked — …" and Done. A refusal is one line under the button.
class GraineBookingSheet extends StatefulWidget {
  const GraineBookingSheet({
    super.key,
    this.app,
    this.reason,
    this.onBooked,
    this.onClose,
    this.sheet = true,
    this.now,
  });

  /// The agent to book with; the default agent unless given.
  final GraineInApp? app;

  /// Fills "What's it about?"; the user may change it. At most 120 characters.
  final String? reason;

  /// A call was booked; the sheet then says so, with Done.
  final ValueChanged<GraineScheduledCall>? onBooked;

  /// Done, or the close button. Null: no close button.
  final VoidCallback? onClose;

  /// Drawn as a sheet (top corners and a grab handle) — else a panel, all corners.
  final bool sheet;

  /// The time now (tests).
  final DateTime Function()? now;

  static const Key sheetKey = ValueKey<String>('graine-booking-sheet');
  static Key dayKey(String day) => ValueKey<String>('graine-booking-day-$day');
  static const Key timeKey = ValueKey<String>('graine-booking-time');
  static const Key zoneKey = ValueKey<String>('graine-booking-zone');
  static const Key aboutKey = ValueKey<String>('graine-booking-about');
  static const Key bookKey = ValueKey<String>('graine-booking-book');
  static const Key lineKey = ValueKey<String>('graine-booking-line');
  static const Key doneKey = ValueKey<String>('graine-booking-done');
  static const Key closeKey = ValueKey<String>('graine-booking-close');

  @override
  State<GraineBookingSheet> createState() => _GraineBookingSheetState();
}

enum _Phase { form, booking, booked }

class _GraineBookingSheetState extends State<GraineBookingSheet> {
  late final TextEditingController _about;
  final FocusNode _aboutFocus = FocusNode(debugLabel: 'graine-booking-about');
  Timer? _tick;
  String? _dayKey;
  DateTime? _picked;
  _Phase _phase = _Phase.form;
  String? _failure;
  GraineScheduledCall? _booked;
  bool _loading = false;

  GraineInApp? get _app => widget.app ?? GraineInApp.maybeInstance;

  /// The clock: a test's, else the device's.
  DateTime _clock() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    final why = widget.reason?.trim() ?? '';
    _about = TextEditingController(text: why.length > Booking.reasonMax ? why.substring(0, Booking.reasonMax) : why);
    // The time moves on while the sheet is open: what was bookable a minute ago may not be.
    _tick = Timer.periodic(const Duration(seconds: 30), (Timer _) {
      if (mounted) setState(() {});
    });
    final app = _app;
    if (app != null && app.session == null) {
      _loading = true;
      unawaited(app.loadSession().whenComplete(() {
        if (mounted) setState(() => _loading = false);
      }));
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _about.dispose();
    _aboutFocus.dispose();
    super.dispose();
  }

  Future<void> _book(GraineInApp app, DateTime at) async {
    setState(() {
      _failure = null;
      _phase = _Phase.booking;
    });
    final why = _about.text.trim();
    try {
      final call = await app.scheduleCall(at: at, reason: why.isEmpty ? null : why);
      if (!mounted) return;
      setState(() {
        _booked = call;
        _phase = _Phase.booked;
      });
      widget.onBooked?.call(call);
    } catch (e) {
      if (!mounted) return;
      final code = e is GraineException ? e.code : null;
      setState(() {
        _phase = _Phase.form;
        _failure = Booking.errorLine(code, app.schedulingRules);
        // Too soon by now: the offer moves on to the new earliest (the days are
        // read from the clock on every build), ready to book again.
        if (code == GraineErrorCode.tooSoon) {
          _dayKey = null;
          _picked = null;
        }
      });
    }
  }

  Future<void> _pickTime(BuildContext context, BookingDay day, DateTime at) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(at),
      initialEntryMode: TimePickerEntryMode.dial,
      // An app with no MaterialApp still gets the picker's words.
      builder: (BuildContext c, Widget? child) =>
          Localizations.of<MaterialLocalizations>(c, MaterialLocalizations) != null
              ? child!
              : Localizations.override(
                  context: c,
                  delegates: const <LocalizationsDelegate<Object?>>[DefaultMaterialLocalizations.delegate],
                  child: child!,
                ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _picked = Booking.onDay(day, picked.hour, picked.minute);
      _failure = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = _app;
    final listenables = <Listenable>[
      if (app != null) app.sessionListenable,
      if (app != null) app.bookingListenable,
    ];
    final body = listenables.isEmpty
        ? _build(context, app)
        : ListenableBuilder(listenable: Listenable.merge(listenables), builder: (BuildContext c, Widget? _) => _build(c, app));
    // showTimePicker needs Material's words; an app with no MaterialApp has none.
    if (Localizations.of<MaterialLocalizations>(context, MaterialLocalizations) != null) return body;
    return Localizations.override(
      context: context,
      delegates: const <LocalizationsDelegate<Object?>>[DefaultMaterialLocalizations.delegate],
      child: body,
    );
  }

  Widget _build(BuildContext context, GraineInApp? app) {
    final tokens = tokensFor(context, app: app);
    final appearance = app?.session?.appearance ?? const <String, Object?>{};
    final dash = Appearance.resolve(appearance, accent: Appearance.defaultAccent, heading: 'Assistant', origin: app?.config.baseUrl);
    final l = tokens != null
        ? ChatLook.design(tokens)
        : ChatLook.appearance(
            dark: deviceDark(context),
            accent: colorOf(dash.accent) ?? colorOf(Appearance.defaultAccent)!,
            radius: dash.radius,
            shadows: const <BoxShadow>[BoxShadow(color: Color(0x29000000), blurRadius: 24, offset: Offset(0, 8))],
          );
    final danger = tokens != null ? tokenColor(tokens.colors.danger) : const Color(0xFFDC2626);
    final h24 = MediaQuery.maybeAlwaysUse24HourFormatOf(context) ?? false;
    final rules = app?.schedulingRules ?? const GraineSchedulingRules();
    final now = _clock();
    final days = Booking.days(Booking.bounds(rules, now), now);
    BookingDay? chosen() {
      for (final d in days) {
        if (d.key == _dayKey) return d;
      }
      return days.isEmpty ? null : days.first;
    }

    final day = chosen();
    final picked = _picked;
    final at = day == null
        ? null
        : (picked != null && !picked.isBefore(day.first) && !picked.isAfter(day.last) ? picked : day.first);
    final ready = app != null && app.session != null;
    final blocker = app == null ? GraineErrorCode.schedulingOff : (ready ? app.bookingBlocker : null);
    final line = _failure ??
        (blocker != null ? Booking.errorLine(blocker, rules) : null) ??
        (ready && !_loading && days.isEmpty ? Booking.errorLine(GraineErrorCode.schedulingOff, rules) : null);
    final canBook = ready && blocker == null && at != null && _phase == _Phase.form;
    final callName = Booking.callName(<String?>[app?.session?.calls?.callName, l.title, dash.heading]);
    final media = MediaQuery.of(context);
    final bottom = math.max(media.viewInsets.bottom, widget.sheet ? media.padding.bottom : 0.0);
    final pad = math.max(16.0, l.pad);
    final radius = widget.sheet
        ? BorderRadius.vertical(top: Radius.circular(l.xl))
        : BorderRadius.circular(l.xl);

    Widget label(String words) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(words, style: l.cardTitleStyle),
        );

    Widget primary(Key key, String words, VoidCallback? onTap, {bool busy = false}) => Tap(
          key: key,
          label: words,
          enabled: onTap != null,
          onTap: onTap,
          child: Opacity(
            opacity: onTap == null && !busy ? 0.4 : 1,
            child: Container(
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: l.accent,
                borderRadius: BorderRadius.circular(l.xl),
                border: tokens?.elevation.hardOffset != null ? Border.all(color: l.text, width: math.max(1, l.borderWidth)) : null,
              ),
              child: busy
                  ? GraineLoaderView(look: Loaders.resolve(appearance['loader']), color: l.onAccent, trackColor: fade(l.onAccent, 0.3), size: 18)
                  : Text(words, style: l.rowTimeStyle.copyWith(color: l.onAccent, fontSize: l.bodyStyle.fontSize)),
            ),
          ),
        );

    final header = Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Semantics(header: true, child: Text(Booking.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: l.emptyTitleStyle)),
                const SizedBox(height: 2),
                Text(Booking.subtitle(callName), maxLines: 1, overflow: TextOverflow.ellipsis, style: l.emptySubtitleStyle),
              ],
            ),
          ),
          if (widget.onClose != null)
            Tap(
              key: GraineBookingSheet.closeKey,
              label: 'Close',
              onTap: widget.onClose,
              child: SizedBox(
                width: 32,
                height: 32,
                child: Center(child: SdkIconView('close', color: l.muted, size: 18, style: l.iconStyle, stroke: l.iconStroke)),
              ),
            ),
        ],
      ),
    );

    final List<Widget> content;
    if (_phase == _Phase.booked) {
      content = <Widget>[
        Center(
          child: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: l.accent, shape: BoxShape.circle),
            child: SdkIconView('call', color: l.onAccent, size: 22, style: l.iconStyle, stroke: l.iconStroke),
          ),
        ),
        const SizedBox(height: 14),
        Semantics(
          liveRegion: true,
          child: Text(Booking.doneLine(callName, _booked?.at?.toLocal() ?? at, h24: h24),
              textAlign: TextAlign.center, style: l.rowTimeStyle.copyWith(fontSize: l.bodyStyle.fontSize, height: 1.35)),
        ),
        const SizedBox(height: 20),
        primary(GraineBookingSheet.doneKey, Booking.done, widget.onClose ?? () {}),
      ];
    } else {
      content = <Widget>[
        label('Day'),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              for (var i = 0; i < days.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: 8),
                _chip(l, days[i], selected: days[i].key == day?.key, onTap: () => setState(() {
                      _dayKey = days[i].key;
                      _picked = null;
                      _failure = null;
                    })),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        label('Time'),
        Builder(
          builder: (BuildContext inner) => Tap(
            key: GraineBookingSheet.timeKey,
            label: at == null ? 'Time' : 'Time, ${ChatTime.clock(at, h24: h24)}',
            enabled: day != null && at != null && _phase == _Phase.form,
            onTap: day == null || at == null ? null : () => unawaited(_pickTime(inner, day, at)),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: l.raised,
                border: l.borderWidth > 0 ? Border.all(color: l.composerBorder, width: l.borderWidth) : null,
                borderRadius: BorderRadius.circular(l.xl),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text(at == null ? '' : ChatTime.clock(at, h24: h24), style: l.inputStyle)),
                  SdkIconView('chevron', color: l.muted, size: 16, style: l.iconStyle, stroke: l.iconStroke),
                ],
              ),
            ),
          ),
        ),
        if (at != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(Booking.zoneLine(at, app?.deviceTimezone, h24: h24), key: GraineBookingSheet.zoneKey, style: l.rowNameStyle),
        ],
        const SizedBox(height: 16),
        label(Booking.about),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _aboutFocus.requestFocus,
          child: Container(
            key: GraineBookingSheet.aboutKey,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: l.raised,
              border: l.borderWidth > 0 ? Border.all(color: l.composerBorder, width: l.borderWidth) : null,
              borderRadius: BorderRadius.circular(l.xl),
            ),
            // EditableText, not a Material TextField: the sheet may open where no Material is.
            child: EditableText(
              controller: _about,
              focusNode: _aboutFocus,
              style: l.inputStyle,
              cursorColor: l.accent,
              backgroundCursorColor: l.muted,
              maxLines: 1,
              textInputAction: TextInputAction.done,
              inputFormatters: <LengthLimitingTextInputFormatter>[LengthLimitingTextInputFormatter(Booking.reasonMax)],
            ),
          ),
        ),
        const SizedBox(height: 20),
        primary(GraineBookingSheet.bookKey, Booking.book,
            canBook ? () => unawaited(_book(app, at)) : null,
            busy: _phase == _Phase.booking),
        if (line != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Semantics(
              liveRegion: true,
              child: Text(line, key: GraineBookingSheet.lineKey, textAlign: TextAlign.center, style: l.cancelStyle.copyWith(color: danger)),
            ),
          ),
      ];
    }

    return Container(
      key: GraineBookingSheet.sheetKey,
      decoration: BoxDecoration(
        color: l.cardBody,
        borderRadius: radius,
        border: !widget.sheet && l.borderWidth > 0 ? Border.all(color: l.border, width: l.borderWidth) : null,
        boxShadow: tokens?.elevation.hardOffset != null && widget.sheet ? null : l.shadows,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: DefaultTextStyle(
          style: textStyle(l.text, 14),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(pad, widget.sheet ? 0 : pad, pad, pad + bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (widget.sheet)
                  SizedBox(
                    height: ChatWindowLayout.handleStrip,
                    child: Center(
                      child: Container(
                        width: ChatWindowLayout.handleWidth,
                        height: ChatWindowLayout.handleHeight,
                        decoration: BoxDecoration(color: fade(l.muted, 0.5), borderRadius: BorderRadius.circular(3)),
                      ),
                    ),
                  ),
                if (widget.sheet) const SizedBox(height: 4),
                header,
                ...content,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(ChatLook l, BookingDay d, {required bool selected, required VoidCallback onTap}) => Tap(
        key: GraineBookingSheet.dayKey(d.key),
        label: d.label,
        enabled: _phase == _Phase.form,
        onTap: onTap,
        child: Semantics(
          selected: selected,
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? l.soft : l.cardFill,
              border: Border.all(color: selected ? l.accent : l.border, width: math.max(1, l.borderWidth)),
              borderRadius: BorderRadius.circular(math.min(l.xl, 17)),
            ),
            child: Text(d.label, maxLines: 1, style: l.starterStyle),
          ),
        ),
      );
}
