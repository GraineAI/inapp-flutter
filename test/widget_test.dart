// The Flutter widgets, driven by fakes: no WebView, no network, no platform.
// A FakeCall stands in for GraineVoice; GraineComponents runs for real on
// the test's fake clock, so the loader's minimum time is measured, not assumed.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graine_inapp/graine_inapp.dart';
import 'package:graine_inapp/src/sdk_icon.dart';

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

/// A call whose agent is misconfigured, as GraineVoice reports it.
class FaultyCall extends FakeCall implements GraineCallFault {
  @override
  String? error = 'This agent has no WebRTC gateway configured.';
}

/// A call that says where its connect is, as GraineVoice does.
class ProgressCall extends FakeCall implements GraineConnectProgress {
  @override
  ConnectStage? connectStage;
  @override
  bool slowConnect = false;
  @override
  bool callFailed = false;
}

/// A chat the app runs itself, handed to the bar.
class FakeChat extends ChangeNotifier implements GraineChatState {
  @override
  List<Caption> messages = const <Caption>[];
  @override
  bool connected = true;
  final List<String> sent = <String>[];

  @override
  void send(String text) {
    sent.add(text);
    messages = <Caption>[...messages, Caption(Role.customer, text)];
    notifyListeners();
  }
}

/// The SDK icon drawn inside [within].
SdkIconView iconIn(WidgetTester tester, Finder within) =>
    tester.widget<SdkIconView>(find.descendant(of: within, matching: find.byType(SdkIconView)));

double opacityOf(WidgetTester tester, Finder button) =>
    tester.widget<Opacity>(find.descendant(of: button, matching: find.byType(Opacity)).first).opacity;

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

    testWidgets("says the contract's words, in the contract's order: each rung beats the ones below it",
        (WidgetTester tester) async {
      final call = FakeCall();
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false)));
      expect(find.text('Tap to talk'), findsOneWidget);
      expect(find.byKey(GraineAgentBar.muteButtonKey), findsNothing);
      expect(find.byKey(GraineAgentBar.meterKey), findsNothing);

      call.update((FakeCall c) => c.connected = true);
      await tester.pump();
      expect(find.text('Listening'), findsOneWidget);
      expect(find.byKey(GraineAgentBar.meterKey), findsOneWidget, reason: 'the meter beside "Listening"');
      expect(find.byKey(GraineAgentBar.muteButtonKey), findsOneWidget);

      call.update((FakeCall c) => c.quality = ConnectionQuality.poor);
      await tester.pump();
      expect(find.text('Weak connection'), findsOneWidget);
      expect(find.byKey(GraineAgentBar.meterKey), findsNothing);

      call.update((FakeCall c) => c.agentSpeaking = true);
      await tester.pump();
      expect(find.text('Speaking'), findsOneWidget, reason: "the agent's line beats a weak network");
      expect(find.byKey(GraineAgentBar.meterKey), findsOneWidget);

      call.update((FakeCall c) => c.muted = true);
      await tester.pump();
      expect(find.text('Muted'), findsOneWidget);

      call.update((FakeCall c) {
        c.connected = false;
        c.muted = false;
        c.agentSpeaking = false;
        c.quality = ConnectionQuality.unknown;
        c.connecting = true;
      });
      await tester.pump();
      expect(find.text('Connecting…'), findsOneWidget);
      expect(find.byType(GraineLoaderView), findsOneWidget, reason: 'while it comes up, the status line is the loader');

      call.update((FakeCall c) {
        c.connecting = false;
        c.ready = false;
      });
      await tester.pump();
      expect(find.text('Connecting…'), findsOneWidget, reason: 'the page is not ready yet');

      call.update((FakeCall c) => c.connectivity = GraineConnectivity.failed);
      await tester.pump();
      expect(find.text('Couldn’t load · tap to retry'), findsOneWidget);
      await tester.tap(find.byKey(GraineAgentBar.callButtonKey));
      expect(call.retries, 1, reason: 'after a failed load the microphone retries');
      expect(call.starts, 0);

      call.update((FakeCall c) => c.micDenied = true);
      await tester.pump();
      expect(find.text('Needs microphone'), findsOneWidget);

      call.update((FakeCall c) {
        c.connectivity = GraineConnectivity.ready;
        c.ready = true;
        c.reconnecting = true;
      });
      await tester.pump();
      expect(find.text('Reconnecting…'), findsOneWidget);
      expect(find.byType(GraineLoaderView), findsOneWidget);

      call.update((FakeCall c) => c.online = false);
      await tester.pump();
      expect(find.text('No connection'), findsOneWidget, reason: 'the network is named before anything else');
    });

    testWidgets("while the agent works out its answer: the loader with the dashboard's thinking words, not the meter",
        (WidgetTester tester) async {
      final call = FakeCall()
        ..connected = true
        ..captions = const <Caption>[Caption(Role.customer, 'Which one is cheaper?')];
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false)));
      expect(find.text('Thinking…'), findsOneWidget);
      expect(find.byType(GraineLoaderView), findsOneWidget);
      expect(find.byKey(GraineAgentBar.meterKey), findsNothing);

      // The brand's own words for the moment, from Appearance → Loading.
      call.update((FakeCall c) => c.appearance = const <String, Object?>{
            'loader': <String, Object?>{
              'text': <String, Object?>{'thinking': 'One moment'},
            },
          });
      await tester.pump();
      expect(find.text('One moment'), findsOneWidget);

      // Muted outranks it; the agent's answer arriving ends it.
      call.update((FakeCall c) => c.muted = true);
      await tester.pump();
      expect(find.text('Muted'), findsOneWidget);
      call.update((FakeCall c) {
        c.muted = false;
        c.captions = const <Caption>[
          Caption(Role.customer, 'Which one is cheaper?'),
          Caption(Role.agent, 'The Seltos', live: true),
        ];
      });
      await tester.pump();
      expect(find.text('Speaking'), findsOneWidget);
      expect(find.byType(GraineLoaderView), findsNothing);
      expect(find.byKey(GraineAgentBar.meterKey), findsOneWidget);
    });

    testWidgets('a slow connect says what is happening, in the loader, instead of spinning on one word',
        (WidgetTester tester) async {
      final call = ProgressCall()..connecting = true;
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false)));
      Future<void> says(String words, void Function(ProgressCall c) change, {String? reason}) async {
        change(call);
        call.notifyListeners();
        await tester.pump();
        expect(find.text(words), findsOneWidget, reason: reason);
        expect(find.byType(GraineLoaderView), findsOneWidget, reason: 'a connect is drawn as the loader');
      }

      // The React Native voice bar's cases, word for word.
      await says('Connecting…', (ProgressCall c) {});
      await says('Still connecting…', (ProgressCall c) => c.slowConnect = true);
      await says('Reconnecting…', (ProgressCall c) => c.connectStage = ConnectStage.retrying,
          reason: 'a retry outranks the slow clock');
      await says('Reconnecting…', (ProgressCall c) {
        c.slowConnect = false;
        c.connectStage = ConnectStage.switching;
      });
      await says('Still connecting…', (ProgressCall c) {
        c.connectStage = ConnectStage.dialling;
        c.slowConnect = true;
      });
      await says('Still connecting…', (ProgressCall c) {
        c.connecting = false;
        c.ready = false;
      }, reason: 'a page the customer is waiting on is a connect too');
      expect(
          tester.getSemantics(find.byKey(GraineAgentBar.statusKey)).value, 'Still connecting…');
    });

    testWidgets("a retry and a slow connect speak in the brand's loader words, and never replace them",
        (WidgetTester tester) async {
      const connecting = 'जुड़ रहा है…';
      const reconnecting = 'फिर से जोड़ रहे हैं…';
      final call = ProgressCall()
        ..connecting = true
        ..slowConnect = true
        ..appearance = const <String, Object?>{
          'loader': <String, Object?>{
            'text': <String, Object?>{'connecting': connecting, 'reconnecting': reconnecting},
          },
        };
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false)));
      expect(find.text(connecting), findsOneWidget, reason: "the brand's wording was replaced");
      expect(find.text('Still connecting…'), findsNothing);
      call.update((FakeCall c) => (c as ProgressCall).connectStage = ConnectStage.retrying);
      await tester.pump();
      expect(find.text(reconnecting), findsOneWidget, reason: "a retry is the reconnecting moment, in the brand's words");
      expect(find.text('Reconnecting…'), findsNothing);
    });

    testWidgets('a call nothing could carry says so, and the microphone starts a new one', (WidgetTester tester) async {
      final call = ProgressCall()..callFailed = true;
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false)));
      expect(find.text('Couldn’t connect · tap to retry'), findsOneWidget, reason: 'a curly apostrophe');
      expect(find.byType(GraineLoaderView), findsNothing, reason: 'no longer connecting');
      final mic = find.byKey(GraineAgentBar.callButtonKey);
      expect(opacityOf(tester, mic), 1, reason: 'the microphone can act');
      expect(tester.getSemantics(mic).label, 'Try again');
      await tester.tap(mic);
      expect(call.starts, 1, reason: 'a new call, not a page reload');
      expect(call.retries, 0);
      // A failed load still outranks it, and still reloads.
      call.update((FakeCall c) => c.connectivity = GraineConnectivity.failed);
      await tester.pump();
      expect(find.text('Couldn’t load · tap to retry'), findsOneWidget);
    });

    testWidgets('a host call that does not report progress draws exactly as before', (WidgetTester tester) async {
      final call = FakeCall()..connecting = true;
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false)));
      expect(find.text('Connecting…'), findsOneWidget);
    });

    testWidgets('the microphone starts a call, mutes one, and cannot act while it cannot', (WidgetTester tester) async {
      final call = FakeCall();
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false)));
      final mic = find.byKey(GraineAgentBar.callButtonKey);
      expect(iconIn(tester, mic).name, 'mic');
      expect(opacityOf(tester, mic), 1);
      await tester.tap(mic);
      expect(call.starts, 1, reason: 'off a call, the microphone starts one');

      // Placing, not ready, refused: at 40% and deaf.
      for (final blocked in <void Function(FakeCall c)>[
        (FakeCall c) => c.connecting = true,
        (FakeCall c) => c.ready = false,
        (FakeCall c) => c.micDenied = true,
      ]) {
        call.update((FakeCall c) {
          c.connecting = false;
          c.ready = true;
          c.micDenied = false;
          blocked(c);
        });
        await tester.pump();
        expect(opacityOf(tester, mic), 0.4);
        await tester.tap(mic, warnIfMissed: false);
        expect(call.starts, 1);
      }

      call.update((FakeCall c) {
        c.micDenied = false;
        c.connected = true;
      });
      await tester.pump();
      final mute = find.byKey(GraineAgentBar.muteButtonKey);
      await tester.tap(mute);
      expect(call.mutes, <bool>[true]);
      call.update((FakeCall c) => c.muted = true);
      await tester.pump();
      expect(iconIn(tester, mute).name, 'micOff');
      expect(iconIn(tester, mute).color, const Color(0xFFFFFFFF));
    });

    testWidgets('the end button hangs up on a call and closes off one; the app hears both', (WidgetTester tester) async {
      var closed = 0;
      final call = FakeCall()..connected = true;
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false, onClose: () => closed++)));
      expect(iconIn(tester, find.byKey(GraineAgentBar.callButtonKey)).name, 'end');
      await tester.tap(find.byKey(GraineAgentBar.callButtonKey));
      expect(call.ends, 1);
      expect(closed, 1);

      call.update((FakeCall c) => c.connected = false);
      await tester.pump();
      final close = find.byKey(GraineAgentBar.closeButtonKey);
      expect(iconIn(tester, close).name, 'close');
      await tester.tap(close);
      expect(closed, 2);
      expect(call.ends, 2, reason: 'a call being placed is cancelled; nothing placed, nothing lost');
    });

    testWidgets('a misconfigured agent says "Unavailable" and its microphone cannot act', (WidgetTester tester) async {
      final call = FaultyCall();
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false)));
      expect(find.text('Unavailable'), findsOneWidget);
      expect(opacityOf(tester, find.byKey(GraineAgentBar.callButtonKey)), 0.4);
      call.update((FakeCall c) => (c as FaultyCall).error = null);
      await tester.pump();
      expect(find.text('Tap to talk'), findsOneWidget);
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

    testWidgets("the customer's own lines carry YOU; two lines at most; captions can be turned off",
        (WidgetTester tester) async {
      final call = FakeCall()
        ..connected = true
        ..captions = const <Caption>[Caption(Role.customer, 'Take me to privacy settings', live: true)];
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false)));
      expect(find.text('YOU'), findsOneWidget);
      final line = tester.widget<Text>(find.text('Take me to privacy settings'));
      expect(line.maxLines, 2);
      expect(
          tester.widget<Opacity>(find.ancestor(of: find.text('Take me to privacy settings'), matching: find.byType(Opacity)).first).opacity,
          0.75,
          reason: 'still arriving');

      call.update((FakeCall c) => c.captions = const <Caption>[Caption(Role.agent, 'Opening privacy settings.')]);
      await tester.pump();
      expect(find.text('YOU'), findsNothing);

      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false, showCaptions: false)));
      expect(find.byKey(GraineAgentBar.captionKey), findsNothing);
    });

    testWidgets('no chat: the bar is the call alone, whatever the dashboard offers', (WidgetTester tester) async {
      final call = FakeCall()..appearance = const <String, Object?>{'mode': 'both'};
      await tester.pumpWidget(host(GraineAgentBar(call: call, showComponents: false)));
      expect(find.byKey(GraineAgentBar.switchButtonKey), findsNothing);
      expect(find.byKey(GraineAgentBar.callButtonKey), findsOneWidget);
    });

    testWidgets('call and chat: the switch ends the call and opens the chat window; the chevron comes back',
        (WidgetTester tester) async {
      final surfaces = <AgentSurface>[];
      final call = FakeCall()
        ..connected = true
        ..appearance = const <String, Object?>{'mode': 'both', 'title': 'Asha'};
      final chat = FakeChat();
      await tester.pumpWidget(host(GraineAgentBar(
          call: call, chat: chat, showComponents: false, onSurfaceChange: surfaces.add)));
      final toChat = find.byKey(GraineAgentBar.switchButtonKey);
      expect(iconIn(tester, toChat).name, 'chat');
      expect(find.byKey(GraineAgentBar.chatKey), findsNothing);

      await tester.tap(toChat);
      await tester.pump();
      expect(call.ends, 1, reason: 'one conversation at a time: the call ends');
      call.update((FakeCall c) => c.connected = false); // and the page confirms it
      await tester.pump();
      expect(surfaces, <AgentSurface>[AgentSurface.chat]);
      expect(find.byKey(GraineAgentBar.chatKey), findsOneWidget);
      expect(find.text('Online'), findsNWidgets(2), reason: 'the header and the status line');
      expect(find.byWidgetPredicate((Widget w) => w is SdkIconView && w.name == 'mic'), findsNothing,
          reason: 'no microphone in the chat');
      expect(find.byKey(GraineAgentBar.closeButtonKey), findsOneWidget);
      expect(iconIn(tester, find.byKey(GraineAgentBar.switchButtonKey)).name, 'call');
      expect(find.text('Asha can see what you’re looking at — ask it anything.'), findsOneWidget);

      await tester.enterText(find.byType(EditableText), 'Show me the Creta');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('graine-chat-send')));
      await tester.pump();
      expect(chat.sent, <String>['Show me the Creta']);
      expect(find.text('Show me the Creta'), findsOneWidget, reason: 'the message, as a bubble');

      // Send from the keyboard too; an empty field sends nothing.
      await tester.enterText(find.byType(EditableText), 'And the price?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'graine-chat-composer',
          reason: 'the keyboard stays up for the next message');
      await tester.tap(find.byKey(const ValueKey<String>('graine-chat-send')));
      expect(chat.sent, <String>['Show me the Creta', 'And the price?']);

      chat
        ..connected = false
        ..notifyListeners();
      await tester.pump();
      expect(find.text('Connecting…'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey<String>('graine-chat-collapse')));
      await tester.pump();
      expect(find.byKey(GraineAgentBar.chatKey), findsNothing);
      expect(surfaces, <AgentSurface>[AgentSurface.chat, AgentSurface.voice]);
    });

    testWidgets('an agent that is only a chat opens in the chat, with no switch and no microphone',
        (WidgetTester tester) async {
      var closed = 0;
      final call = FakeCall()..appearance = const <String, Object?>{'mode': 'chat'};
      await tester.pumpWidget(host(GraineAgentBar(
          call: call, chat: FakeChat(), showComponents: false, surface: AgentSurface.voice, onClose: () => closed++)));
      expect(find.byKey(GraineAgentBar.chatKey), findsOneWidget);
      expect(find.byKey(GraineAgentBar.switchButtonKey), findsNothing);
      expect(find.byKey(GraineAgentBar.callButtonKey), findsNothing);
      await tester.tap(find.byKey(const ValueKey<String>('graine-chat-collapse')));
      expect(closed, 1, reason: 'the chevron closes a chat-only agent');
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
