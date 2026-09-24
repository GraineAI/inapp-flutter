part of 'graine.dart';

/// THE COMPONENTS THE AGENT DRAWS, as state a widget renders.
///
/// [WidgetFlow] (the core's port of the RN SDK's useGraineWidget) with its
/// deadlines turned into timers: the loader's minimum time, the give-up for
/// a component that never arrives, the bounded wait for the agent's reply.
/// [GraineInApp.components] is fed by the call; [GraineWidgetView] draws it.
///
/// A host can build one standalone — a preview, a test — with its own
/// callbacks, and feed it with [present] and [presentPending].
class GraineComponents extends ChangeNotifier {
  GraineComponents({
    required String baseUrl,
    this.onAnswer,
    this.onAction,
    this.onReport,
    int Function()? clock,
  })  : _flow = WidgetFlow(baseUrl),
        _clock = clock ?? GraineInApp._wallClock;

  factory GraineComponents._forApp(GraineInApp g) {
    final c = GraineComponents(
      baseUrl: g.config.baseUrl,
      clock: g._clock,
      onAnswer: (String id, Map<String, Object?> data, String summary) => g.voice.answerWidget(id, data, summary),
      onAction: g.executeAction,
      onReport: (String name, String detail, Map<String, Object?> data) =>
          g.voice.reportEvent(name, detail: detail, data: data),
    );
    c._app = g;
    return c;
  }

  /// The customer answered: send it to the agent (the SDK: [GraineVoice.answerWidget]).
  final void Function(String widgetId, Map<String, Object?> data, String summary)? onAnswer;

  /// Run a component's in-app action (the SDK: [GraineInApp.executeAction]).
  final Future<ActionResult> Function(String name, Map<String, Object?> args)? onAction;

  /// Tell the agent something quietly (the SDK: [GraineVoice.reportEvent]).
  final void Function(String name, String detail, Map<String, Object?> data)? onReport;

  final WidgetFlow _flow;
  final int Function() _clock;
  GraineInApp? _app;
  Timer? _timer;
  bool _wasLive = false;
  GraineWidget? _contentFor;
  WidgetContent? _content;

  /// The component on screen, or null.
  GraineWidget? get widget => _flow.widget;

  /// What [widget] reduces to — rows, chips, days — and the answer each tap sends.
  WidgetContent? get content {
    final w = _flow.widget;
    if (w == null) return null;
    if (!identical(_contentFor, w)) {
      _contentFor = w;
      _content = WidgetContent(w);
    }
    return _content;
  }

  /// How [widget] asked to look.
  WidgetLook? get look {
    final w = _flow.widget;
    return w == null ? null : Widgets.resolveLook(w.style, w.kind);
  }

  /// A component announced and still loading, or null.
  WidgetPending? get loading => _flow.loading;

  /// The last answer, kept on screen as one line.
  WidgetAnswered? get answered => _flow.answered;

  /// The customer answered and the agent has not started replying.
  bool get awaitingReply => _flow.awaitingReply;

  /// The last component closed without an answer — for a "show it again".
  GraineWidget? get closed => _flow.closed;

  /// Draw a frame received some other way — a preview, a test — exactly as
  /// if the agent had sent it.
  void present(Map<String, Object?> frame) => _onWidget(frame);

  /// Show the loader for a component on its way, as if the agent announced it.
  void presentPending(Map<String, Object?> hint) => _onPending(hint);

  /// The customer answered. The component's own in-app action (`on_select`)
  /// runs first and is not awaited; a refusal is reported to the agent.
  void answer(WidgetAnswer a) {
    final sub = _flow.submit(a.data, a.summary, _clock());
    if (sub == null) return;
    _app?.clearPendingWidget();
    final call = sub.action;
    final run = onAction;
    if (call != null && run != null) {
      unawaited(run(call.name, call.args).then<void>((ActionResult r) {
        if (r.status != ActionStatus.ok) {
          onReport?.call(
            'in_app_action_failed',
            '"${call.name}" did not run: ${r.message.isEmpty ? r.status.wire : r.message}. '
                'Do not describe a screen the customer cannot see.',
            const <String, Object?>{},
          );
        }
      }, onError: (Object _) {}));
    }
    onAnswer?.call(sub.widgetId, sub.data, sub.summary);
    _changed();
  }

  /// Close without choosing (or "Clear" the answered line). The agent is
  /// told quietly: it must not go on describing options nobody can see.
  void dismiss() {
    final report = _flow.dismiss();
    if (report != null) {
      onReport?.call(
        'component_dismissed',
        'The customer closed the component without choosing. Do not refer to options they cannot see; '
            'offer to show it again if they want it.',
        <String, Object?>{'quiet': true, 'data': report.eventData()},
      );
    }
    _app?.clearPendingWidget();
    _changed();
  }

  /// Put the last closed component back, exactly as it was.
  void reopen() {
    if (_flow.reopen()) _changed();
  }

  /// Forget everything drawn (a call ended, or a new one began).
  void reset() {
    _flow.reset();
    _changed();
  }

  void _onWidget(Map<String, Object?> frame) {
    _flow.onWidget(frame, _clock());
    _changed();
  }

  void _onPending(Map<String, Object?> hint) {
    _flow.onPending(hint, _clock());
    _changed();
  }

  void _agentStarted() {
    if (!_flow.awaitingReply) return;
    _flow.onAgentStarted();
    _changed();
  }

  /// A new call is a new conversation: the last one's card must not appear over it.
  void _onCall(bool live) {
    if (live && !_wasLive) reset();
    _wasLive = live;
  }

  /// A component nobody can answer any more is not left on screen.
  void _ended() {
    _wasLive = false;
    reset();
  }

  void _changed() {
    _schedule();
    notifyListeners();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    final at = _flow.nextDeadline();
    if (at == null) return;
    final wait = at - _clock();
    _timer = Timer(Duration(milliseconds: wait < 0 ? 0 : wait), () {
      _timer = null;
      if (_flow.tick(_clock())) notifyListeners();
      _schedule();
    });
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }
}
