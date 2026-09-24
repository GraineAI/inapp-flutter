import 'context.dart';
import 'js.dart';
import 'widgets.dart';

/// A component the agent put on screen, adopted from the page's frame
/// exactly as the React Native SDK's useGraineWidget adopts it.
class GraineWidget {
  const GraineWidget({
    required this.id,
    required this.kind,
    required this.data,
    required this.fallbackText,
    required this.style,
    required this.onSelect,
  });

  final String id;

  /// "product_list", "plan_comparison", "choices", … or whatever the agent declares.
  final String kind;

  /// Root-relative pictures already resolved against the agent's origin.
  final Map<String, Object?> data;

  /// What the agent would have said instead. Drawn when the kind is unknown.
  final String fallbackText;

  /// How the dashboard asked for it to look. Already allowlisted.
  final WidgetStyle style;

  /// What the app should do on a tap, beyond telling the agent. Already allowlisted.
  final WidgetSelectAction onSelect;

  /// The page's `widget` object → a component, or null when it names no
  /// `widget_id` (a frame the SDK cannot answer is not one to draw). An `id`
  /// is accepted when there is no `widget_id`, for a host handing a frame in.
  static GraineWidget? adopt(Map<String, Object?>? raw, String baseUrl) {
    if (raw == null) return null;
    final wid = raw['widget_id'] ?? raw['id'];
    if (!Js.truthy(wid)) return null;
    final data = Js.asMap(raw['data']);
    final onSelect = raw['on_select'] ?? raw['onSelect'];
    return GraineWidget(
      id: Js.str(wid),
      kind: Js.truthy(raw['kind']) ? Js.str(raw['kind']) : '',
      data: data == null ? <String, Object?>{} : Widgets.resolveImages(data, baseUrl),
      fallbackText: Js.truthy(raw['fallback_text']) ? Js.str(raw['fallback_text']) : '',
      style: Widgets.normaliseStyle(raw['style']),
      onSelect: Widgets.normaliseSelectAction(onSelect),
    );
  }
}

/// What a tap sends: the structured payload, and the sentence that is the
/// customer's turn.
class WidgetAnswer {
  const WidgetAnswer(this.data, this.summary);
  final Map<String, Object?> data;
  final String summary;

  @override
  bool operator ==(Object other) =>
      other is WidgetAnswer && other.summary == summary && deepEquals(other.data, data);

  @override
  int get hashCode => Object.hash(summary, deepHash(data));

  @override
  String toString() => 'WidgetAnswer($data, "$summary")';
}

/// One normalised row: the shape every dashboard kind is reduced to.
class WidgetRow {
  const WidgetRow({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.price,
    required this.facts,
    required this.image,
    required this.unavailable,
    required this.selectLabel,
  });

  final String id;
  final String title;
  final String subtitle;
  final String price;
  final List<String> facts;
  final String image;
  final bool unavailable;
  final String selectLabel;
}

class WidgetChip {
  const WidgetChip(this.id, this.label);
  final String id;
  final String label;
}

class WidgetDay {
  const WidgetDay(this.label, this.slots);
  final String label;
  final List<String> slots;
}

enum _Shape { plans, card, items }

/// One kind, reduced to what the renderer draws — widget.tsx's
/// normalisation, line for line. Three dashboard kinds (product list, plan
/// comparison, info card) share one row shape; chips cover the agent's
/// `choices` and the dashboard's `quick_actions`; `calendar_slots` is days
/// and their times.
class WidgetContent {
  WidgetContent(this.widget) {
    final data = widget.data;
    final kind = widget.kind;
    if (data['options'] is List) {
      _options = Js.asList(data['options']);
    } else if (kind == 'quick_actions' && data['actions'] is List) {
      _options = Js.asList(data['actions']);
    } else {
      _options = const <Object?>[];
    }
    isQuickActions = kind == 'quick_actions' && _options.isNotEmpty;

    if (kind == 'plan_comparison' && data['plans'] is List) {
      _shape = _Shape.plans;
    } else if (kind == 'info_card' && (Js.truthy(data['title']) || Js.truthy(data['summary']))) {
      _shape = _Shape.card;
    } else {
      _shape = _Shape.items;
    }

    switch (_shape) {
      case _Shape.plans:
        selectLabel = 'Select';
      case _Shape.card:
        selectLabel = Js.or(data['actionLabel'], 'Tell me more');
      case _Shape.items:
        selectLabel = Js.or(data['selectLabel'], 'Choose');
    }

    final items = _items(data);
    rows = <WidgetRow>[
      for (var i = 0; i < items.length && i < 8; i++) _row(items[i], i),
    ];

    isProducts = rows.isNotEmpty &&
        (kind == 'product_list' ||
            kind == 'products' ||
            kind == 'plan_comparison' ||
            kind == 'info_card' ||
            _options.isEmpty);
    isChips = (kind == 'choices' || isQuickActions) && _options.isNotEmpty;
    isCalendar = kind == 'calendar_slots' && data['days'] is List && (data['days'] as List).isNotEmpty;
    drawable = isProducts || isChips || isCalendar;

    chips = <WidgetChip>[
      for (final o in _options) _chip(o),
    ];
    days = isCalendar ? _days(data) : const <WidgetDay>[];
    title = Js.truthy(data['title']) ? Js.str(data['title']) : '';
    prompt = Js.truthy(data['prompt']) ? Js.str(data['prompt']) : '';
    note = Js.truthy(data['note']) ? Js.str(data['note']) : '';
  }

  final GraineWidget widget;
  late final List<Object?> _options;
  late final _Shape _shape;
  late final bool isQuickActions;

  /// The button label, and the verb for "choose several".
  late final String selectLabel;
  late final List<WidgetRow> rows;
  late final bool isProducts;
  late final bool isChips;
  late final bool isCalendar;

  /// Something this build can draw. A kind it cannot draws the fallback
  /// sentence, on a card.
  late final bool drawable;
  late final List<WidgetChip> chips;
  late final List<WidgetDay> days;
  late final String title;
  late final String prompt;
  late final String note;

  /// The items as the kind names them, before they became rows.
  List<Map<String, Object?>> _items(Map<String, Object?> data) {
    switch (_shape) {
      case _Shape.plans:
        return <Map<String, Object?>>[
          for (final pl in Js.asList(data['plans'])) _plan(Js.asMap(pl)),
        ];
      case _Shape.card:
        return <Map<String, Object?>>[
          <String, Object?>{
            'id': 'card',
            'title': data['title'],
            'subtitle': data['category'],
            'imageUrl': data['imageUrl'],
            'facts': <Object?>[data['summary'], ..._facts(data['facts'])]
                .where(Js.truthy)
                .toList(),
          },
        ];
      case _Shape.items:
        // A bare value in `items` has no id or title of its own: JS reads
        // `it?.title ?? it?.id ?? i` on it and gets the index.
        return <Map<String, Object?>>[
          for (final it in Js.asList(data['items'])) Js.asMap(it) ?? <String, Object?>{},
        ];
    }
  }

  static Map<String, Object?> _plan(Map<String, Object?>? p) {
    final price = p?['price'];
    final suffix = p?['priceSuffix'];
    return <String, Object?>{
      'id': p?['id'],
      'title': p?['name'],
      'subtitle': p?['badge'],
      'price': Js.truthy(price) ? Js.str(price) + (suffix == null ? '' : Js.str(suffix)) : '',
      'facts': _facts(p?['facts']),
      'selectLabel': p?['selectLabel'],
    };
  }

  /// Fact rows: `{label, value}` as "label value", else the value on its own.
  static List<String> _facts(Object? v) => <String>[
        for (final f in Js.asList(v)) _fact(Js.asMap(f)),
      ];

  static String _fact(Map<String, Object?>? o) {
    final label = o?['label'];
    if (Js.truthy(label)) {
      // `${f.label} ${f.value}`: an absent value is "undefined", a null one "null".
      final value = o!.containsKey('value') ? Js.str(o['value']) : 'undefined';
      return '${Js.str(label)} $value';
    }
    return Js.strOrEmpty(o?['value']);
  }

  WidgetRow _row(Map<String, Object?> it, int i) {
    String s(Object? v) => Js.truthy(v) ? Js.str(v) : '';
    final facts = it['facts'];
    return WidgetRow(
      id: Js.str(Js.firstDefined(<Object?>[it['id'], it['title']]) ?? i),
      title: Js.str(Js.firstDefined(<Object?>[it['title'], it['id']]) ?? i),
      subtitle: s(it['subtitle']),
      price: s(it['price']),
      facts: facts is List ? facts.map(Js.str).take(3).toList() : const <String>[],
      image: s(it['imageUrl']),
      unavailable: it['unavailable'] == true,
      selectLabel: Js.truthy(it['selectLabel']) ? Js.str(it['selectLabel']) : selectLabel,
    );
  }

  static WidgetChip _chip(Object? o) {
    final obj = Js.asMap(o);
    final label = Js.strOrEmpty(Js.firstDefined(<Object?>[obj?['label'], obj?['title']]) ?? o);
    return WidgetChip(Js.str(Js.firstDefined(<Object?>[obj?['id']]) ?? label), label);
  }

  static List<WidgetDay> _days(Map<String, Object?> data) {
    final out = <WidgetDay>[];
    final list = Js.asList(data['days']);
    for (var di = 0; di < list.length && di < 4; di++) {
      final o = Js.asMap(list[di]);
      final label = Js.str(Js.firstDefined(<Object?>[o?['label'], o?['id']]) ?? 'Day ${di + 1}');
      final slots = o?['slots'] is List ? (o!['slots'] as List).map(Js.str).toList() : <String>[];
      if (slots.isEmpty) continue;
      out.add(WidgetDay(label, slots.take(8).toList()));
    }
    return out;
  }

  /// The surface actually drawn: an undrawable kind takes over nothing.
  String surface(WidgetLook look) => drawable ? look.surface : 'card';

  /// Choosing several applies only where there is something to tick.
  bool many(WidgetLook look) => look.select == 'many' && drawable;

  /// The payload for one row, per kind — what the runtime's resultToText reads.
  Map<String, Object?> _toSubmit(WidgetRow r) {
    switch (_shape) {
      case _Shape.plans:
        return <String, Object?>{'id': r.id, 'name': r.title, 'price': r.price};
      case _Shape.card:
        return <String, Object?>{'action': Js.or(widget.data['actionLabel'], 'Tell me more')};
      case _Shape.items:
        return <String, Object?>{'id': r.id, 'title': r.title, 'price': r.price};
    }
  }

  /// One row tapped.
  WidgetAnswer pick(int index) {
    final r = rows[index];
    final at = r.price.isNotEmpty ? ' at ${r.price}' : '';
    final String summary;
    switch (_shape) {
      case _Shape.plans:
        summary = "I'll take ${r.title}$at.";
      case _Shape.card:
        summary = Js.or(widget.data['actionLabel'], 'Tell me more about this.');
      case _Shape.items:
        summary = "I'll take a look at ${r.title}$at.";
    }
    return WidgetAnswer(_toSubmit(r), summary);
  }

  /// Several at once, as ONE answer: every item, the flattened ids and titles
  /// an in-app action's arguments usually want, and one sentence that names
  /// them the way a person would.
  WidgetAnswer pickMany(List<String> ids) {
    final chosen = <WidgetRow>[];
    for (final id in ids) {
      for (final r in rows) {
        if (r.id == id) {
          chosen.add(r);
          break;
        }
      }
    }
    final titles = chosen.map((WidgetRow r) => r.title).where((String t) => t.isNotEmpty).toList();
    return WidgetAnswer(
      <String, Object?>{
        'items': <Object?>[for (final r in chosen) _toSubmit(r)],
        'ids': chosen.map((WidgetRow r) => r.id).join(','),
        'titles': titles.join(', '),
        'count': chosen.length,
      },
      Widgets.manySummary(titles, selectLabel.toLowerCase()),
    );
  }

  /// A chip tapped. Both shapes' keys, so the agent hears a sentence either way.
  WidgetAnswer pickChip(WidgetChip chip) => WidgetAnswer(
        isQuickActions
            ? <String, Object?>{'id': chip.id, 'label': chip.label}
            : <String, Object?>{'chosen': chip.id, 'label': chip.label},
        "I'll go with ${chip.label}.",
      );

  /// A time tapped: the day and the slot, which is what
  /// resultToText("calendar_slots") reads.
  WidgetAnswer pickSlot(WidgetDay day, String slot) => WidgetAnswer(
        <String, Object?>{'day': day.label, 'slot': slot},
        '${day.label} at $slot, please.',
      );

  /// Ticking one row while choosing several: the oldest gives way at the cap.
  static List<String> toggle(List<String> ticked, String id, int maxSelect) {
    if (ticked.contains(id)) return ticked.where((String x) => x != id).toList();
    if (ticked.length >= maxSelect) return <String>[...ticked.skip(1), id];
    return <String>[...ticked, id];
  }

  /// The one button under a multi-select list. Below two it says how many more.
  String manyButtonLabel(int chosen) => chosen < 2
      ? 'Pick ${2 - chosen} more to ${selectLabel.toLowerCase()}'
      : '$selectLabel $chosen';

  /// The line that stays on screen after an answer, as the RN AnsweredLine
  /// reads the answer's data: a title (name, title, label or slot) and a
  /// detail (price · day). Both empty means there is no line to draw.
  static ({String title, String detail}) answeredLine(Map<String, Object?> data) {
    var title = '';
    for (final k in const <String>['name', 'title', 'label', 'slot']) {
      if (Js.truthy(data[k])) {
        title = Js.str(data[k]).trim();
        break;
      }
    }
    final detail = <String>[
      for (final k in const <String>['price', 'day'])
        if (Js.truthy(data[k])) Js.str(data[k]),
    ].join(' · ');
    return (title: title, detail: detail);
  }
}

/// A component announced and still loading.
class WidgetPending {
  const WidgetPending(this.id, this.kind);
  final String id;
  final String kind;

  @override
  bool operator ==(Object other) =>
      other is WidgetPending && other.id == id && other.kind == kind;

  @override
  int get hashCode => Object.hash(id, kind);
}

/// The customer's answer, kept on screen as one line.
class WidgetAnswered {
  const WidgetAnswered(this.widget, this.data, this.summary);
  final GraineWidget widget;
  final Map<String, Object?> data;
  final String summary;
}

/// What to put on the wire for an answer, and the app's own action to run first.
class WidgetSubmission {
  const WidgetSubmission(this.widgetId, this.data, this.summary, this.action);
  final String widgetId;
  final Map<String, Object?> data;
  final String summary;
  final SelectCall? action;
}

/// The data of the quiet `component_dismissed` event, exactly as the RN SDK sends it.
class WidgetDismissal {
  const WidgetDismissal(this.toolName, this.kind, this.title);
  final String toolName;
  final String kind;
  final String title;

  Map<String, Object?> eventData() => <String, Object?>{
        'tool_name': toolName,
        'kind': kind,
        'title': title,
        'answered': false,
      };
}

/// useGraineWidget, as a state machine with time passed in.
///
///   pending   the agent called for a component; its content is loading. A
///             loader stands where it will appear, for at most
///             [Widgets.pendingWidgetMs].
///   held      it arrived within [Widgets.minLoaderMs] of the loader going
///             up, so the loader finishes being seen first. Closing now
///             cancels it.
///   shown     [widget].
///   answered  a tap went to the agent; the choice stays as one line, saying
///             "thinking" until the agent starts ([onAgentStarted]) or
///             [Widgets.awaitingReplyMs] passes.
///   closed    dismissed without choosing: kept in [closed] for [reopen].
///
/// The owner calls [tick] at [nextDeadline]; nothing here owns a timer.
class WidgetFlow {
  WidgetFlow(this.baseUrl);

  final String baseUrl;

  GraineWidget? _widget;
  WidgetAnswered? _answered;
  WidgetPending? _loading;
  bool _awaitingReply = false;
  GraineWidget? _closed;

  int? _shownAt;
  int? _loadingUntil;
  GraineWidget? _held;
  int? _heldUntil;
  int? _awaitingUntil;

  GraineWidget? get widget => _widget;
  WidgetAnswered? get answered => _answered;
  WidgetPending? get loading => _loading;
  bool get awaitingReply => _awaitingReply;
  GraineWidget? get closed => _closed;

  /// A component drawn while nothing was listening, picked up on mount.
  void seed(Map<String, Object?>? raw) {
    final w = GraineWidget.adopt(raw, baseUrl);
    if (w == null) return;
    if (_widget?.id != w.id) _widget = w;
  }

  /// A component is on its way.
  void onPending(Map<String, Object?>? hint, int now) {
    _shownAt = now;
    _loading = WidgetPending(Js.strOrEmpty(hint?['widget_id']), Js.strOrEmpty(hint?['kind']));
    _loadingUntil = now + Widgets.pendingWidgetMs;
  }

  /// The agent drew one. True when it is on screen now (false: held, or not a component).
  bool onWidget(Map<String, Object?>? raw, int now) {
    // Any component the agent draws is the agent answering.
    onAgentStarted();
    final next = GraineWidget.adopt(raw, baseUrl);
    if (next == null) return false;
    _loadingUntil = null;
    final seen = _shownAt == null ? Widgets.minLoaderMs : now - _shownAt!;
    if (seen >= Widgets.minLoaderMs) {
      _show(next);
      return true;
    }
    _held = next;
    _heldUntil = now + (Widgets.minLoaderMs - seen);
    return false;
  }

  void _show(GraineWidget next) {
    _shownAt = null;
    _held = null;
    _heldUntil = null;
    _loading = null;
    _loadingUntil = null;
    _closed = null;
    _widget = next;
    // A new question replaces the last answer, or stale lines stack up.
    _answered = null;
  }

  /// The agent started speaking (a caption, a component): stop saying we are waiting.
  void onAgentStarted() {
    _awaitingReply = false;
    _awaitingUntil = null;
  }

  /// The customer answered. [summary] is replaced by the component's own
  /// `say` when it runs an in-app action; the action itself is the caller's
  /// to run, first, without waiting on it.
  WidgetSubmission? submit(Map<String, Object?> data, String summary, int now) {
    final w = _widget;
    if (w == null) return null;
    final item = <String, Object?>{...data, 'summary': summary};
    final call = Widgets.selectCall(w.onSelect, item);
    final say = w.onSelect.say;
    final said = (call != null && say != null) ? Widgets.fillSelectTemplate(say, item) : summary;
    _widget = null;
    _answered = WidgetAnswered(w, data, said);
    _awaitingReply = true;
    _awaitingUntil = now + Widgets.awaitingReplyMs;
    return WidgetSubmission(w.id, data, said, call);
  }

  /// Closed without choosing — or "Clear" on the answered line. Returns what
  /// to tell the agent when a component was actually on screen; null when
  /// there was nothing to report.
  WidgetDismissal? dismiss() {
    _held = null;
    _heldUntil = null;
    _shownAt = null;
    final w = _widget;
    final report = w == null
        ? null
        : WidgetDismissal(w.id.split(':').first, w.kind, Js.strOrEmpty(w.data['title']));
    _closed = w;
    _widget = null;
    _answered = null;
    _loading = null;
    _loadingUntil = null;
    _awaitingReply = false;
    _awaitingUntil = null;
    return report;
  }

  /// Put the last closed component back, exactly as it was. No tool call, no second fetch.
  bool reopen() {
    final c = _closed;
    if (c == null) return false;
    _widget = c;
    _closed = null;
    _answered = null;
    return true;
  }

  /// A call ended, or a new one began: nothing from the last one belongs on screen.
  void reset() {
    _widget = null;
    _answered = null;
    _loading = null;
    _closed = null;
    _awaitingReply = false;
    _shownAt = null;
    _loadingUntil = null;
    _held = null;
    _heldUntil = null;
    _awaitingUntil = null;
  }

  /// Apply every deadline that has passed. True when anything visible changed.
  bool tick(int now) {
    var changed = false;
    final heldUntil = _heldUntil;
    if (heldUntil != null && now >= heldUntil) {
      final h = _held;
      if (h != null) _show(h);
      _heldUntil = null;
      changed = true;
    }
    final loadingUntil = _loadingUntil;
    if (loadingUntil != null && now >= loadingUntil) {
      _loading = null;
      _loadingUntil = null;
      changed = true;
    }
    final awaitingUntil = _awaitingUntil;
    if (awaitingUntil != null && now >= awaitingUntil) {
      _awaitingReply = false;
      _awaitingUntil = null;
      changed = true;
    }
    return changed;
  }

  /// When [tick] next has something to do, or null.
  int? nextDeadline() {
    int? best;
    for (final t in <int?>[_heldUntil, _loadingUntil, _awaitingUntil]) {
      if (t != null && (best == null || t < best)) best = t;
    }
    return best;
  }
}
