// The Flutter widgets, driven by fakes: no WebView, no network, no platform.
// A FakeCall stands in for GraineVoice; GraineComponents runs for real on
// the test's fake clock, so the loader's minimum time is measured, not assumed.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graine_inapp/graine_inapp.dart';

const String base = 'https://www.graine.ai';

/// The call as the bar sees it, with every field settable.
class FakeCall extends ChangeNotifier implements GraineCallState {
  @override
  bool connected = false;
  @override
  bool connecting = false;
  @override
  bool muted = false;
  @override
  bool ready = true;
  @override
  bool reconnecting = false;
  @override
  bool? online;
  @override
  ConnectionQuality quality = ConnectionQuality.unknown;
  @override
  GraineConnectivity connectivity = GraineConnectivity.ready;
  @override
  List<Caption> captions = const <Caption>[];
  @override
  bool agentSpeaking = false;
  @override
  bool micDenied = false;
  @override
  Map<String, Object?> appearance = const <String, Object?>{};

  @override
  Caption? get caption => captions.isEmpty ? null : captions.last;

  int starts = 0;
  int ends = 0;
  int retries = 0;
  final List<bool> mutes = <bool>[];

  @override
  Future<void> start() async => starts++;
  @override
  void end() => ends++;
  @override
  void setMuted(bool muted) => mutes.add(muted);
  @override
  void retry() => retries++;

  void update(void Function(FakeCall c) change) {
    change(this);
    notifyListeners();
  }
}

/// A screen-sized host: the test surface is 800x600 logical pixels.
Widget host(Widget child, {EdgeInsets viewInsets = EdgeInsets.zero}) => MediaQuery(
      data: MediaQueryData(size: const Size(800, 600), viewInsets: viewInsets),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(children: <Widget>[child]),
      ),
    );

Rect barRect(WidgetTester tester) => tester.getRect(find.byKey(GraineAgentBar.barKey));

Map<String, Object?> cars({Map<String, Object?>? style}) => <String, Object?>{
      'widget_id': 'cars:1',
      'kind': 'product_list',
      if (style != null) 'style': style,
      'data': <String, Object?>{
        'title': 'Three that fit',
        'selectLabel': 'Compare',
        'items': <Object?>[
          <String, Object?>{'id': 'creta', 'title': 'Creta', 'price': '₹19.2 lakh'},
          <String, Object?>{'id': 'seltos', 'title': 'Seltos', 'price': '₹17.8 lakh'},
          <String, Object?>{'id': 'venue', 'title': 'Venue'},
        ],
      },
    };

Finder row(String id) => find.byKey(ValueKey<String>('graine-row-$id'));
const Key submitKey = ValueKey<String>('graine-many-submit');

/// Unmount, then stop the components' timers: a test must not end with one
/// pending (the loader's give-up, the bounded wait for a reply).
Future<void> done(WidgetTester tester, GraineComponents comps) async {
  await tester.pumpWidget(const SizedBox());
  comps.dispose();
}

void main() {
  group('GraineAgentBar', () {
    testWidgets('a tap still taps; a drag moves the bar, does not tap, and reports where it went',
        (WidgetTester tester) async {
      final call = FakeCall();
      final placements = <int>[];
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false, onPlacementChange: placements.add)));
      await tester.pump();
      final rest = barRect(tester);

      await tester.tap(find.byKey(GraineAgentBar.callButtonKey));
      await tester.pump();
      expect(call.starts, 1);

      // A wobble under the 8px slop is still a tap, and moves nothing.
      await tester.drag(find.byKey(GraineAgentBar.callButtonKey), const Offset(0, -5));
      await tester.pump();
      expect(call.starts, 2);
      expect(placements, isEmpty);
      expect(barRect(tester), rest);

      // A drag that starts ON the button moves the bar and is not a tap.
      await tester.drag(find.byKey(GraineAgentBar.callButtonKey), const Offset(0, -120));
      await tester.pump();
      expect(call.starts, 2);
      expect(placements, <int>[120]);
      expect(rest.top - barRect(tester).top, closeTo(120, 0.5));

      // Dragged down past its anchor: it stops at the anchor.
      await tester.drag(find.byKey(GraineAgentBar.barKey), const Offset(0, 400));
      await tester.pump();
      expect(placements.last, 0);
      expect(barRect(tester).top, closeTo(rest.top, 0.5));

      // And never above the top margin, however far it is flung.
      await tester.drag(find.byKey(GraineAgentBar.barKey), const Offset(0, -2000));
      await tester.pump();
      expect(barRect(tester).top, closeTo(48, 0.5));
      expect(placements.last, 600 - 48 - barRect(tester).height.round() - 96);
    });

    testWidgets('a persisted offset is restored, and draggable:false pins it to the anchor', (WidgetTester tester) async {
      final call = FakeCall();
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false, initialOffset: 150)));
      await tester.pump();
      expect(barRect(tester).bottom, closeTo(600 - 96 - 150, 0.5));

      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false, draggable: false)));
      await tester.pump();
      expect(barRect(tester).bottom, closeTo(600 - 96, 0.5));
      await tester.drag(find.byKey(GraineAgentBar.barKey), const Offset(0, -100));
      await tester.pump();
      expect(barRect(tester).bottom, closeTo(600 - 96, 0.5));
    });

    testWidgets('rises above the keyboard by the inset MediaQuery reports, and never past the top margin',
        (WidgetTester tester) async {
      final call = FakeCall();
      Widget bar({bool aware = true}) => GraineAgentBar(call: call, showComponents: false, keyboardAware: aware);

      await tester.pumpWidget(host(bar()));
      await tester.pump();
      expect(barRect(tester).bottom, closeTo(600 - 96, 0.5));

      await tester.pumpWidget(host(bar(), viewInsets: const EdgeInsets.only(bottom: 300)));
      expect(barRect(tester).bottom, closeTo(600 - 96 - 300, 0.5));

      // A route that resized for the keyboard reports no inset below it: no double lift.
      await tester.pumpWidget(host(bar()));
      expect(barRect(tester).bottom, closeTo(600 - 96, 0.5));

      await tester.pumpWidget(host(bar(aware: false), viewInsets: const EdgeInsets.only(bottom: 300)));
      expect(barRect(tester).bottom, closeTo(600 - 96, 0.5));

      await tester.pumpWidget(host(bar(), viewInsets: const EdgeInsets.only(bottom: 590)));
      expect(barRect(tester).top, closeTo(48, 0.5));
    });

    testWidgets('names the network before it lets the agent take the blame', (WidgetTester tester) async {
      final call = FakeCall();
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false)));
      expect(find.text('tap to talk'), findsOneWidget);
      expect(find.byKey(GraineAgentBar.muteButtonKey), findsNothing);

      call.update((FakeCall c) => c.connected = true);
      await tester.pump();
      expect(find.text('listening'), findsOneWidget);
      expect(find.byKey(GraineAgentBar.muteButtonKey), findsOneWidget);

      call.update((FakeCall c) => c.agentSpeaking = true);
      await tester.pump();
      expect(find.text('speaking'), findsOneWidget);

      call.update((FakeCall c) => c.quality = ConnectionQuality.poor);
      await tester.pump();
      expect(find.text('weak connection'), findsOneWidget);

      call.update((FakeCall c) => c.muted = true);
      await tester.pump();
      expect(find.text('muted'), findsOneWidget);

      call.update((FakeCall c) => c.online = false);
      await tester.pump();
      expect(find.text('no connection'), findsOneWidget);

      call.update((FakeCall c) {
        c.online = true;
        c.reconnecting = true;
      });
      await tester.pump();
      expect(find.text('reconnecting…'), findsOneWidget);
      expect(find.byType(GraineLoaderView), findsOneWidget, reason: 'while it comes back, the status line is the loader');

      call.update((FakeCall c) {
        c.reconnecting = false;
        c.connected = false;
        c.connecting = true;
      });
      await tester.pump();
      expect(find.text('connecting…'), findsOneWidget);

      call.update((FakeCall c) {
        c.connecting = false;
        c.ready = false;
      });
      await tester.pump();
      expect(find.text('connecting…'), findsOneWidget, reason: 'the page is not ready yet');

      call.update((FakeCall c) {
        c.ready = true;
        c.micDenied = true;
      });
      await tester.pump();
      expect(find.text('needs microphone'), findsOneWidget);

      call.update((FakeCall c) => c.connectivity = GraineConnectivity.failed);
      await tester.pump();
      expect(find.text("couldn't load · tap to retry"), findsOneWidget);
      await tester.tap(find.byKey(GraineAgentBar.callButtonKey));
      expect(call.retries, 1);
      expect(call.starts, 0);
    });

    testWidgets('mute and hang up act on the call; the live caption sits above the bar', (WidgetTester tester) async {
      final call = FakeCall()
        ..connected = true
        ..captions = const <Caption>[Caption(Role.agent, 'Hi Asha, how can I help?')];
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false)));
      expect(find.text('Hi Asha, how can I help?'), findsOneWidget);
      expect(tester.getRect(find.text('Hi Asha, how can I help?')).bottom, lessThan(barRect(tester).top));

      await tester.tap(find.byKey(GraineAgentBar.muteButtonKey));
      expect(call.mutes, <bool>[true]);
      await tester.tap(find.byKey(GraineAgentBar.callButtonKey));
      expect(call.ends, 1);

      call.update((FakeCall c) => c.connected = false);
      await tester.pump();
      expect(find.text('Hi Asha, how can I help?'), findsNothing, reason: 'no caption outside a call');
    });

    testWidgets('the dashboard names it and colours it; a prop overrides one thing', (WidgetTester tester) async {
      final call = FakeCall()..appearance = const <String, Object?>{'title': 'Asha from Graine', 'accent': '12AB34'};
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false)));
      expect(find.text('Asha from Graine'), findsOneWidget);
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false, name: 'Riya')));
      expect(find.text('Riya'), findsOneWidget);
    });
  });

  group('GraineWidgetView', () {
    testWidgets('choosing several: the oldest gives way at the limit, and one answer names them all',
        (WidgetTester tester) async {
      final answers = <List<Object?>>[];
      final comps = GraineComponents(
        baseUrl: base,
        onAnswer: (String id, Map<String, Object?> data, String summary) => answers.add(<Object?>[id, data, summary]),
        clock: () => tester.binding.clock.now().millisecondsSinceEpoch,
      );
      comps.present(cars(style: <String, Object?>{'select': 'many', 'maxSelect': 2}));
      await tester.pumpWidget(host(GraineWidgetView(components: comps, appearance: const <String, Object?>{})));

      expect(find.text('Pick 2 more to compare'), findsOneWidget);
      await tester.tap(row('creta'));
      await tester.pump();
      expect(find.text('Pick 1 more to compare'), findsOneWidget);

      // One ticked: the button answers nothing — a comparison of one is not one.
      await tester.tap(find.byKey(submitKey));
      await tester.pump();
      expect(answers, isEmpty);

      await tester.tap(row('seltos'));
      await tester.pump();
      await tester.tap(row('venue'));
      await tester.pump();
      // The limit is two: the oldest (Creta) gave way.
      expect(find.text('Compare 2'), findsOneWidget);

      await tester.tap(find.byKey(submitKey));
      await tester.pump();
      expect(answers, hasLength(1));
      final data = answers.single[1]! as Map<String, Object?>;
      expect(answers.single[0], 'cars:1');
      expect(data['ids'], 'seltos,venue');
      expect(data['titles'], 'Seltos, Venue');
      expect(data['count'], 2);
      expect(answers.single[2], "Let's compare Seltos and Venue.");
      expect(comps.widget, isNull, reason: 'answered: the component goes');
      await done(tester, comps);
    });

    testWidgets('choosing one answers at once, and the choice stays as a line until cleared', (WidgetTester tester) async {
      final answers = <String>[];
      final reports = <String>[];
      final comps = GraineComponents(
        baseUrl: base,
        onAnswer: (String id, Map<String, Object?> data, String summary) => answers.add(summary),
        onReport: (String name, String detail, Map<String, Object?> data) => reports.add(name),
        clock: () => tester.binding.clock.now().millisecondsSinceEpoch,
      );
      comps.present(cars());
      await tester.pumpWidget(host(GraineWidgetView(components: comps, appearance: const <String, Object?>{})));
      expect(find.text('STILL LISTENING'), findsOneWidget, reason: 'a product list is a screen');

      await tester.tap(find.text('Compare').first);
      await tester.pump();
      expect(answers, <String>["I'll take a look at Creta at ₹19.2 lakh."]);
      expect(find.text('Creta'), findsOneWidget, reason: 'the answered line names the choice');
      expect(find.text('Thinking…'), findsOneWidget, reason: 'until the agent starts answering');

      await tester.pump(const Duration(milliseconds: Widgets.awaitingReplyMs));
      expect(find.text('Thinking…'), findsNothing, reason: 'the wait is bounded');
      await tester.tap(find.byKey(const ValueKey<String>('graine-clear')));
      await tester.pump();
      expect(find.text('Creta'), findsNothing);
      expect(reports, isEmpty, reason: 'clearing an answer is not closing a component');
      await done(tester, comps);
    });

    testWidgets('closing without choosing tells the agent quietly', (WidgetTester tester) async {
      final reports = <List<Object?>>[];
      final comps = GraineComponents(
        baseUrl: base,
        onReport: (String name, String detail, Map<String, Object?> data) => reports.add(<Object?>[name, data]),
        clock: () => tester.binding.clock.now().millisecondsSinceEpoch,
      );
      comps.present(<String, Object?>{
        'widget_id': 'pick:2',
        'kind': 'choices',
        'data': <String, Object?>{
          'title': 'Which suits you?',
          'options': <Object?>[
            <String, Object?>{'id': 'y', 'label': 'Yes'},
            'No',
          ],
        },
      });
      await tester.pumpWidget(host(GraineWidgetView(components: comps, appearance: const <String, Object?>{})));
      expect(find.text('None of these'), findsOneWidget, reason: 'choices is a sheet');
      await tester.tap(find.byKey(const ValueKey<String>('graine-dismiss')));
      await tester.pump();
      expect(reports.single[0], 'component_dismissed');
      final data = reports.single[1]! as Map<String, Object?>;
      expect(data['quiet'], isTrue);
      expect((data['data']! as Map<String, Object?>)['tool_name'], 'pick');
      expect(comps.closed?.id, 'pick:2');
      comps.reopen();
      await tester.pump();
      expect(find.text('Yes'), findsOneWidget);
      await done(tester, comps);
    });

    testWidgets('the loader stays at least its minimum, then the component replaces it', (WidgetTester tester) async {
      final comps = GraineComponents(baseUrl: base, clock: () => tester.binding.clock.now().millisecondsSinceEpoch);
      await tester.pumpWidget(host(GraineWidgetView(components: comps, appearance: const <String, Object?>{})));

      comps.presentPending(<String, Object?>{'widget_id': 'cars:1', 'kind': 'product_list'});
      await tester.pump();
      expect(find.text('Loading…'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100));
      comps.present(cars()); // arrives 100ms after the loader went up
      await tester.pump();
      expect(find.text('Loading…'), findsOneWidget, reason: 'a loader that flashes reads as a glitch');
      expect(find.text('Creta'), findsNothing);

      await tester.pump(const Duration(milliseconds: 349));
      expect(find.text('Creta'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('Creta'), findsOneWidget);
      expect(find.text('Loading…'), findsNothing);
      await done(tester, comps);
    });

    testWidgets('a component with no announced wait draws at once; one that never arrives gives up',
        (WidgetTester tester) async {
      final comps = GraineComponents(baseUrl: base, clock: () => tester.binding.clock.now().millisecondsSinceEpoch);
      await tester.pumpWidget(host(GraineWidgetView(components: comps, appearance: const <String, Object?>{})));
      comps.present(cars());
      await tester.pump();
      expect(find.text('Creta'), findsOneWidget);

      comps.reset();
      comps.presentPending(<String, Object?>{'widget_id': 'x', 'kind': 'info_card'});
      await tester.pump();
      expect(find.text('Loading…'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: Widgets.pendingWidgetMs));
      expect(find.text('Loading…'), findsNothing);
      await done(tester, comps);
    });

    testWidgets('a kind this build cannot draw is the agent\'s own sentence, on a card', (WidgetTester tester) async {
      final comps = GraineComponents(baseUrl: base, clock: () => tester.binding.clock.now().millisecondsSinceEpoch);
      comps.present(<String, Object?>{
        'widget_id': 'f:1',
        'kind': 'form',
        'fallback_text': 'Fill in your address',
        'style': <String, Object?>{'surface': 'screen'},
      });
      await tester.pumpWidget(host(GraineWidgetView(components: comps, appearance: const <String, Object?>{})));
      expect(find.text('Fill in your address'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('graine-surface-card')), findsOneWidget);
      await done(tester, comps);
    });

    testWidgets('calendar slots answer with the day and the time', (WidgetTester tester) async {
      final answers = <String>[];
      final comps = GraineComponents(
        baseUrl: base,
        onAnswer: (String id, Map<String, Object?> data, String summary) => answers.add(summary),
        clock: () => tester.binding.clock.now().millisecondsSinceEpoch,
      );
      comps.present(<String, Object?>{
        'widget_id': 'slots:1',
        'kind': 'calendar_slots',
        'data': <String, Object?>{
          'days': <Object?>[
            <String, Object?>{'label': 'Mon', 'slots': <Object?>['10:00', '11:00']},
          ],
        },
      });
      await tester.pumpWidget(host(GraineWidgetView(components: comps, appearance: const <String, Object?>{})));
      await tester.tap(find.byKey(const ValueKey<String>('graine-slot-Mon-11:00')));
      await tester.pump();
      expect(answers, <String>['Mon at 11:00, please.']);
      await done(tester, comps);
    });
  });
}
