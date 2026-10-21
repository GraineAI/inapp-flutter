// Several agents in one app (MULTI-AGENT.md): each asks Graine with its own
// key — its session, its chat, its bookings and its memory — while the user,
// the device and the screen are the app's; one conversation at a time across
// all of them; the views draw the agent they are handed; and the native call
// engine hears every agent's name. HTTP, the sockets and both channels are
// mocks; nothing reaches a real host.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graine_inapp/graine_inapp.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'device_mock.dart';
import 'platform_test.dart' show Connector, FakePage, FakeSocket, Server, base, jsonResponse, sessionBody;

const String mainKey = 'pk_test_main';
const String supportKey = 'pk_test_support';

/// The support agent: its own agent, its own heading, and an Identity
/// setting that names the user id where the main agent's names the email.
Map<String, Object?> supportSession() => <String, Object?>{
      ...sessionBody(field: 'user_id', appearance: const <String, Object?>{'mode': 'both', 'title': 'Ravi'}),
      'agentId': 'agent-2',
      'webcallAgentId': 'webcall-2',
    };

GraineInApp agent(WidgetTester tester, Server server,
        {required String name, required String key, Connector? connector}) =>
    GraineInApp.forTesting(
      GraineConfig(baseUrl: base, publishableKey: key, appVersion: '2.4.0'),
      httpClient: server.client,
      clock: () => tester.binding.clock.now().millisecondsSinceEpoch,
      chatConnector: connector?.call,
      install: true,
      name: name,
    );

/// Forget every agent, and let a hang-up's last timer run.
Future<void> done(WidgetTester tester) async {
  GraineInApp.resetForTesting();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Open [g]'s chat and wait for it to connect.
Future<FakeSocket> chatWith(WidgetTester tester, GraineInApp g, Connector c) async {
  g.chat.open();
  await tester.pump();
  await tester.pump();
  expect(g.chat.connected, isTrue, reason: "${g.name}'s chat did not connect");
  return c.last;
}

/// The names of the recent events in the last context frame [s] was sent.
List<String> recentEvents(FakeSocket s) {
  final frame = s.sent.lastWhere((Map<String, Object?> m) => m['type'] == 'app_context');
  final events = (frame['context']! as Map<String, Object?>)['recent_events'] as List<Object?>?;
  return <String>[for (final e in events ?? const <Object?>[]) (e! as Map<String, Object?>)['name']! as String];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DeviceMock device;
  setUp(() {
    device = DeviceMock()..install();
  });
  tearDown(() {
    // A test that failed half-way leaves nothing for the next one.
    GraineInApp.resetForTesting();
    DeviceMock.uninstall();
  });

  group('the agents', () {
    testWidgets('agents by name beside the default one; a name configured again is that agent, unchanged',
        (WidgetTester tester) async {
      final main = agent(tester, Server(), name: 'default', key: mainKey);
      final support = agent(tester, Server(session: supportSession()), name: 'support', key: supportKey);
      expect(GraineInApp.instance, same(main));
      expect(GraineInApp.maybeInstance, same(main));
      expect(GraineInApp.named('support'), same(support));
      expect(GraineInApp.named('  support '), same(support), reason: 'a name is trimmed');
      expect(GraineInApp.named(''), same(main), reason: 'no name is the default agent');
      expect(GraineInApp.named('sales'), isNull);
      expect(GraineInApp.all.keys, <String>['default', 'support'], reason: 'in the order configured');
      expect(() => GraineInApp.all['sales'] = main, throwsUnsupportedError);
      expect(main.name, GraineInApp.defaultName);
      expect(support.name, 'support');
      expect(GraineInApp.init(const GraineConfig(baseUrl: base, publishableKey: 'pk_test_other'), name: 'support'),
          same(support));
      expect(support.config.publishableKey, supportKey);
      expect(GraineInApp.init(const GraineConfig(baseUrl: base, publishableKey: 'pk_test_other')), same(main));
      await done(tester);
      expect(GraineInApp.maybeInstance, isNull);

      // An app that only named its agents: the first one configured stands in for the default.
      final sales = agent(tester, Server(), name: 'sales', key: 'pk_test_sales');
      agent(tester, Server(), name: 'care', key: 'pk_test_care');
      expect(GraineInApp.instance, same(sales));
      await done(tester);
    });

    testWidgets('each agent asks Graine with its own key, and its chat keeps its own turns', (WidgetTester tester) async {
      final mainServer = Server();
      final supportServer = Server(session: supportSession());
      final mainSockets = Connector();
      final supportSockets = Connector();
      final main = agent(tester, mainServer, name: 'default', key: mainKey, connector: mainSockets);
      final support = agent(tester, supportServer, name: 'support', key: supportKey, connector: supportSockets);
      await main.loadSession();
      await support.loadSession();
      expect(mainServer.bodies('/api/embed/session').single['publishableKey'], mainKey);
      expect(supportServer.bodies('/api/embed/session').single['publishableKey'], supportKey);
      expect(main.session?.agentId, 'agent-1');
      expect(support.session?.agentId, 'agent-2');

      final first = await chatWith(tester, main, mainSockets);
      expect(mainServer.bodies('/api/embed/ticket').single['publishableKey'], mainKey);
      first.say(<String, Object?>{'type': 'text', 'data': 'Hello from the main agent.<end_of_stream>'});
      await tester.pump();
      expect(main.chat.turns.map((GraineChatTurn t) => t.text), <String>['Hello from the main agent.']);
      expect(support.chat.turns, isEmpty, reason: "one agent's words never reach another's chat");

      final second = await chatWith(tester, support, supportSockets);
      expect(supportServer.bodies('/api/embed/ticket').single['publishableKey'], supportKey);
      expect(mainServer.bodies('/api/embed/ticket'), hasLength(1), reason: 'the support chat was never minted with the main key');
      expect(main.chat.isOpen, isFalse, reason: 'one conversation at a time: one chat opening closes the other');
      expect(first.types.last, 'stop');
      second.say(<String, Object?>{'type': 'text', 'data': 'Support here.<end_of_stream>'});
      await tester.pump();
      expect(support.chat.turns.map((GraineChatTurn t) => t.text), <String>['Support here.']);
      expect(main.chat.turns.map((GraineChatTurn t) => t.text), <String>['Hello from the main agent.']);
      await done(tester);
    });

    testWidgets('identify on one agent identifies the user for every agent; identify(null) signs out of each',
        (WidgetTester tester) async {
      final mainServer = Server(); // the email identifies the user
      final supportServer = Server(session: supportSession()); // the user id does
      final main = agent(tester, mainServer, name: 'default', key: mainKey);
      final support = agent(tester, supportServer, name: 'support', key: supportKey);
      await main.loadSession();
      await support.loadSession();
      final mainPage = FakePage();
      final supportPage = FakePage();
      main.voice.attach(mainPage);
      support.voice.attach(supportPage);
      await tester.pump();
      mainPage.say(<String, Object?>{'type': 'graine:ready'});
      supportPage.say(<String, Object?>{'type': 'graine:ready'});
      await tester.pump();

      support.identify(<String, Object?>{'name': 'Asha', 'email': 'asha@example.com', 'user_id': 'U-42'});
      await tester.pump();
      expect(mainPage.ofType('graine:identity').last['value'], 'asha@example.com',
          reason: "identified through support, read by the main agent's own setting");
      expect(supportPage.ofType('graine:identity').last['value'], 'U-42');
      final mainVars = mainPage.ofType('graine:variables').last['variables']! as Map<String, Object?>;
      final supportVars = supportPage.ofType('graine:variables').last['variables']! as Map<String, Object?>;
      expect(mainVars['name'], 'Asha');
      expect(supportVars['name'], 'Asha');
      expect(mainVars.containsKey('email'), isFalse, reason: "each agent's identifying trait is never its variable");
      expect(supportVars.containsKey('user_id'), isFalse);

      main.identify(null);
      await tester.pump();
      await tester.pump();
      final mainOut = mainServer.bodies('/api/embed/identity/signout').single;
      final supportOut = supportServer.bodies('/api/embed/identity/signout').single;
      expect(mainOut['publishableKey'], mainKey);
      expect(mainOut['identity'], <String, Object?>{'value': 'asha@example.com'});
      expect(supportOut['publishableKey'], supportKey, reason: 'signed out everywhere, each workspace with its own key');
      expect(supportOut['identity'], <String, Object?>{'value': 'U-42'});
      expect(mainPage.ofType('graine:identity').last['value'], isNull);
      expect(supportPage.ofType('graine:identity').last['value'], isNull);
      await done(tester);
    });

    testWidgets("the memory choice is the user's for every agent, and the device is one", (WidgetTester tester) async {
      final main = agent(tester, Server(), name: 'default', key: mainKey);
      final support = agent(tester, Server(session: supportSession()), name: 'support', key: supportKey);
      await main.loadSession();
      await support.loadSession();
      main.identify(<String, Object?>{'email': 'asha@example.com', 'user_id': 'U-42'});
      support.setMemory(false);
      await tester.pump();
      expect(await main.memoryEnabled(), isFalse);
      expect(await support.memoryEnabled(), isFalse);
      expect(device.prefs['memory'], <String, Object?>{
        Identity.memoryKey('email', 'asha@example.com'): false,
        Identity.memoryKey('user_id', 'U-42'): false,
      }, reason: "kept under each agent's fingerprint of the same user");
      expect(await support.installId, await main.installId);
      expect(device.calls.where((MethodCall c) => c.method == 'installId'), hasLength(1), reason: 'read once for the app');
      await done(tester);
    });

    testWidgets('an agent configured after the user was identified knows them', (WidgetTester tester) async {
      final main = agent(tester, Server(), name: 'default', key: mainKey);
      main.identify(<String, Object?>{'name': 'Asha', 'user_id': 'U-42'}, memory: false);
      final supportServer = Server(session: supportSession());
      final support = agent(tester, supportServer, name: 'support', key: supportKey);
      await support.loadSession();
      expect(await support.memoryEnabled(), isFalse);
      expect(support.currentVariables()['name'], 'Asha');
      await support.scheduledCalls();
      expect(supportServer.bodies('/api/embed/calls/list').single['identity'], <String, Object?>{'value': 'U-42'});
      await done(tester);
    });

    testWidgets('scheduling and memory requests go to the agent they are made on, with its key',
        (WidgetTester tester) async {
      final mainServer = Server();
      final supportServer = Server(session: supportSession());
      supportServer.routes['/api/embed/calls/schedule'] = (Map<String, Object?> body) => jsonResponse(<String, Object?>{
            'call': <String, Object?>{'id': 'sc_9', 'at': body['at'], 'status': 'scheduled', 'source': 'sdk'},
          }, 201);
      mainServer.routes['/api/embed/memory/forget'] = (Map<String, Object?> _) => jsonResponse(<String, Object?>{'deleted': 2});
      final main = agent(tester, mainServer, name: 'default', key: mainKey);
      final support = agent(tester, supportServer, name: 'support', key: supportKey);
      final mainChat = main.chat;
      final supportChat = support.chat;
      main.identify(<String, Object?>{'email': 'asha@example.com', 'user_id': 'U-42'});
      final soon = tester.binding.clock.now().toUtc().add(const Duration(hours: 3));
      final at = DateTime.utc(soon.year, soon.month, soon.day, soon.hour, soon.minute, soon.second);

      final call = await support.scheduleCall(at: at, reason: 'Refund follow-up');
      expect(call.id, 'sc_9');
      final booked = supportServer.bodies('/api/embed/calls/schedule').single;
      expect(booked['publishableKey'], supportKey);
      expect(booked['identity'], <String, Object?>{'value': 'U-42'}, reason: "the user as support's setting names them");
      expect(mainServer.bodies('/api/embed/calls/schedule'), isEmpty);
      expect(supportChat.upcomingCalls.map((GraineScheduledCall c) => c.id), <String>['sc_9']);
      expect(mainChat.upcomingCalls, isEmpty, reason: "a booking with support is not on the main agent's card");

      expect(await main.forgetMemory(), 2);
      expect(mainServer.bodies('/api/embed/memory/forget').single['publishableKey'], mainKey);
      expect(supportServer.bodies('/api/embed/memory/forget'), isEmpty);
      await support.scheduledCalls();
      expect(supportServer.bodies('/api/embed/calls/list').single['publishableKey'], supportKey);
      expect(mainServer.bodies('/api/embed/calls/list'), isEmpty);
      await done(tester);
    });

    testWidgets("the screen is the app's: the agent in conversation hears it, with its own actions",
        (WidgetTester tester) async {
      final mainSockets = Connector();
      final supportSockets = Connector();
      final main = agent(tester, Server(), name: 'default', key: mainKey, connector: mainSockets);
      final support =
          agent(tester, Server(session: supportSession()), name: 'support', key: supportKey, connector: supportSockets);
      main.registerAction('open_plans', (Map<String, Object?> _) => null);
      support.registerAction('raise_ticket', (Map<String, Object?> _) => null);
      final s = await chatWith(tester, support, supportSockets);

      main.setScreen(const GraineScreen('help', availableActions: <String>['open_plans', 'raise_ticket']));
      final frame = s.sent.lastWhere((Map<String, Object?> m) => m['type'] == 'app_context');
      expect((frame['context']! as Map<String, Object?>)['screen'], 'help',
          reason: 'set through the main agent, heard at once by the agent in conversation');
      expect(frame['available_actions'], <String>['raise_ticket'], reason: "the stated actions this agent handles");
      main.track('faq_opened');
      await tester.pump(const Duration(milliseconds: 450));
      expect(recentEvents(s), <String>['faq_opened']);
      expect(mainSockets.sockets, isEmpty, reason: 'no conversation with the main agent: nothing goes to it');

      // An agent configured after the screen was set takes it on.
      final salesSockets = Connector();
      final sales = agent(tester, Server(), name: 'sales', key: 'pk_test_sales', connector: salesSockets);
      await chatWith(tester, sales, salesSockets);
      final opening = salesSockets.last.sent.firstWhere((Map<String, Object?> m) => m['type'] == 'app_context');
      expect((opening['context']! as Map<String, Object?>)['screen'], 'help');
      await done(tester);
    });

    testWidgets('one conversation at a time across agents: a call with one ends a chat with another, and back',
        (WidgetTester tester) async {
      final mainSockets = Connector();
      final main = agent(tester, Server(), name: 'default', key: mainKey, connector: mainSockets);
      final support = agent(tester, Server(session: supportSession()), name: 'support', key: supportKey);
      final chat = await chatWith(tester, main, mainSockets);
      final page = FakePage();
      support.voice.attach(page);
      await tester.pump();
      page.say(<String, Object?>{'type': 'graine:ready'});
      await tester.pump();

      await support.voice.start();
      expect(main.chat.isOpen, isFalse, reason: "a call with support ends the chat with the main agent");
      expect(chat.types.last, 'stop');
      await tester.pump();
      page.say(<String, Object?>{'type': 'graine:call', 'connected': true, 'connecting': false});
      expect(support.voice.connected, isTrue);

      main.chat.open();
      expect(page.ofType('graine:end-call'), hasLength(1), reason: "opening the main agent's chat ends support's call");
      page.say(<String, Object?>{'type': 'graine:ended'});
      await tester.pump();
      await tester.pump();
      expect(main.chat.connected, isTrue);
      expect(support.voice.connected, isFalse);
      await done(tester);
    });

    testWidgets('GraineChat(app:) and GraineAgentBar(app:) draw the agent they are handed', (WidgetTester tester) async {
      final mainSockets = Connector();
      final supportSockets = Connector();
      final main = agent(tester, Server(), name: 'default', key: mainKey, connector: mainSockets);
      final support =
          agent(tester, Server(session: supportSession()), name: 'support', key: supportKey, connector: supportSockets);
      await main.loadSession();
      await support.loadSession();
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(400, 800)),
        child: Directionality(textDirection: TextDirection.ltr, child: GraineChat(app: support)),
      ));
      await tester.pump();
      await tester.pump();
      expect(support.chat.connected, isTrue);
      expect(mainSockets.sockets, isEmpty, reason: "the main agent's chat is never opened");
      expect(find.text('Ravi'), findsOneWidget, reason: "support's heading");
      expect(find.text('Asha'), findsNothing);
      supportSockets.last.say(<String, Object?>{'type': 'text', 'data': 'Support here.<end_of_stream>'});
      await tester.pump();
      await tester.pump(); // the frame lands after this frame was built
      expect(find.text('Support here.'), findsOneWidget);

      // A chat handed over from an agent draws that agent too.
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(400, 800)),
        child: Directionality(textDirection: TextDirection.ltr, child: GraineChat(chat: support.chat)),
      ));
      expect(find.text('Ravi'), findsOneWidget);

      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(800, 600)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(children: <Widget>[GraineAgentBar(app: support, showComponents: false)]),
        ),
      ));
      await tester.pump();
      expect(find.text('Ravi'), findsOneWidget, reason: "the bar talks to support");
      expect(find.text('Asha'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await done(tester);
    });

    testWidgets('nested engines, one per agent: a tap is one tap, told to every agent', (WidgetTester tester) async {
      final mainSockets = Connector();
      final supportSockets = Connector();
      final main = agent(tester, Server(), name: 'default', key: mainKey, connector: mainSockets);
      final support =
          agent(tester, Server(session: supportSession()), name: 'support', key: supportKey, connector: supportSockets);
      main.setScreen(const GraineScreen('plans'));
      final s = await chatWith(tester, main, mainSockets);
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: GraineEngine(app: support, child: const GraineEngine(child: SizedBox.expand())),
      ));
      await tester.tapAt(const Offset(300, 300));
      await tester.pump(const Duration(milliseconds: 450));
      expect(recentEvents(s), <String>['tap:screen'], reason: 'both engines saw the touch; it is one tap');

      final later = await chatWith(tester, support, supportSockets);
      expect(recentEvents(later), <String>['tap:screen'], reason: 'the agent beside it heard the same tap, once');
      await tester.pumpWidget(const SizedBox());
      await done(tester);
    });
  });

  group('the native call engine', () {
    const MethodChannel channel = MethodChannel('ai.graine.inapp/calls');
    const EventChannel events = EventChannel('ai.graine.inapp/calls/events');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    MockStreamHandlerEventSink? sink;

    List<Object?> argsOf(String method) =>
        calls.where((MethodCall c) => c.method == method).map((MethodCall c) => c.arguments).toList();

    void emit(String event, Map<String, Object?> data) =>
        sink!.success(<String, Object?>{'event': event, 'data': data});

    GraineInApp make(String name, String key) => GraineInApp.forTesting(
          GraineConfig(baseUrl: base, publishableKey: key, appVersion: '2.4.0'),
          httpClient: MockClient((http.Request _) async => http.Response('{}', 404)),
          install: true,
          name: name,
        );

    const options = GraineCallsOptions(publishableKey: mainKey, displayName: 'Acme');

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      calls.clear();
      sink = null;
      messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
        calls.add(call);
        switch (call.method) {
          case 'snapshot':
            return <String, Object?>{'state': 'idle'};
          case 'startCall':
            return 'call_1';
          case 'handlePush':
            return true;
        }
        return null;
      });
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(onListen: (Object? _, MockStreamHandlerEventSink s) => sink = s),
      );
      GraineCalls.instance.resetForTesting();
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockStreamHandler(events, null);
      GraineInApp.resetForTesting();
      GraineCalls.instance.resetForTesting();
    });

    test('configure hands the engine every named agent; one agent configures exactly as before', () async {
      make('default', mainKey);
      await GraineCalls.instance.configure(options);
      expect(argsOf('configure').single, options.toMap(), reason: 'a one-agent app sends what it always sent');

      make('support', supportKey);
      await pumpEventQueue();
      expect(argsOf('configure'), hasLength(2), reason: 'an agent configured later reaches the engine then');
      expect(argsOf('configure').last, <String, Object?>{
        ...options.toMap(),
        'agents': <String, Object?>{
          'support': <String, Object?>{'publishableKey': supportKey, 'baseUrl': base},
        },
      });

      // Configured again with the agents it knows: the same list, no more news.
      await GraineCalls.instance.configure(options);
      expect((argsOf('configure').last! as Map<Object?, Object?>)['agents'], hasLength(1));
      expect(argsOf('configure'), hasLength(3));
    });

    test("the app's speakerByDefault rides every configure — also the one an agent configured later sends", () async {
      make('default', mainKey);
      GraineCalls.instance.speakerByDefault = false;
      await GraineCalls.instance.configure(options);
      expect((argsOf('configure').single! as Map<Object?, Object?>)['speakerByDefault'], isFalse);
      make('support', supportKey);
      await pumpEventQueue();
      expect(argsOf('configure'), hasLength(2));
      expect((argsOf('configure').last! as Map<Object?, Object?>)['speakerByDefault'], isFalse,
          reason: 'a configure without it would put calls back on the loudspeaker');
    });

    test('the agents reach the engine as a map by name — the shape both native hosts read', () async {
      make('default', mainKey);
      make('support', supportKey);
      make('sales', 'pk_test_sales');
      await GraineCalls.instance.configure(options);
      final agents = (argsOf('configure').single! as Map<Object?, Object?>)['agents'];
      expect(agents, isA<Map<Object?, Object?>>(), reason: 'a list makes the iOS host refuse the whole configure');
      expect(agents, <String, Object?>{
        'support': <String, Object?>{'publishableKey': supportKey, 'baseUrl': base},
        'sales': <String, Object?>{'publishableKey': 'pk_test_sales', 'baseUrl': base},
      }, reason: 'by name, each with its key and host — nothing the hosts do not read');
      expect((agents! as Map<Object?, Object?>).containsKey('default'), isFalse,
          reason: 'the default agent is the top-level key');
    });

    test("an app that named every agent: the one with the options' key is the engine's default", () async {
      make('support', supportKey);
      make('sales', 'pk_test_sales');
      final incoming = <GraineIncomingCall>[];
      GraineCalls.instance.incomingCalls.listen(incoming.add);
      await GraineCalls.instance.configure(const GraineCallsOptions(publishableKey: supportKey, displayName: 'Acme'));
      expect((argsOf('configure').single! as Map<Object?, Object?>)['agents'], <String, Object?>{
        'sales': <String, Object?>{'publishableKey': 'pk_test_sales', 'baseUrl': base},
      }, reason: "support's key is the top-level key: listed again it would be a second engine agent");
      await GraineCalls.instance.startCall(reason: 'help', agent: 'support');
      expect((argsOf('startCall').last! as Map<Object?, Object?>).containsKey('agent'), isFalse,
          reason: "the engine's default agent");
      await GraineCalls.instance.startCall(reason: 'upgrade', agent: 'sales');
      expect((argsOf('startCall').last! as Map<Object?, Object?>)['agent'], 'sales');
      // prepareCall names the agent as startCall does: the engine's default goes unnamed.
      await GraineCalls.instance.prepareCall(reason: 'help', agent: 'support');
      expect((argsOf('prepareCall').last! as Map<Object?, Object?>).containsKey('agent'), isFalse);
      await GraineCalls.instance.prepareCall(reason: 'upgrade', agent: ' sales ');
      expect((argsOf('prepareCall').last! as Map<Object?, Object?>)['agent'], 'sales');
      emit('state', <String, Object?>{'state': 'ringing', 'callId': 'h1', 'direction': 'incoming', 'agent': 'default'});
      emit('incoming', <String, Object?>{'callId': 'h1', 'agent': 'default'});
      await pumpEventQueue();
      expect(GraineCalls.instance.value.agent, 'support', reason: "the engine's default is the app's support agent");
      expect(incoming.single.agent, 'support');
    });

    test("startCall names the agent; the engine holds that agent's variables and actions for the call", () async {
      final main = make('default', mainKey);
      final support = make('support', supportKey);
      main.registerAction('open_plans', (Map<String, Object?> _) => null);
      support.registerAction('raise_ticket', (Map<String, Object?> _) => const ActionResult.ok('Ticket raised.'));
      main.setVariables(<String, Object?>{'desk': 'sales'});
      support.setVariables(<String, Object?>{'desk': 'support'});
      await GraineCalls.instance.configure(options);
      GraineCalls.instance.attach(main);
      expect(argsOf('setActions').last, <String>['open_plans']);
      expect((argsOf('setVariables').last! as Map<Object?, Object?>)['desk'], 'sales');

      final id = await GraineCalls.instance.startCall(reason: 'refund', agent: ' support ');
      expect(id, 'call_1');
      final placed = argsOf('startCall').single! as Map<Object?, Object?>;
      expect(placed['agent'], 'support');
      expect(placed['reason'], 'refund');
      final order = calls.map((MethodCall c) => c.method).toList();
      expect(order.lastIndexOf('setActions'), lessThan(order.indexOf('startCall')),
          reason: "the engine has support's actions before it calls support");
      expect(argsOf('setActions').last, <String>['raise_ticket']);
      expect((argsOf('setVariables').last! as Map<Object?, Object?>)['desk'], 'support');

      emit('state', <String, Object?>{'state': 'connecting', 'callId': 'call_1', 'direction': 'outgoing', 'agent': 'support'});
      await pumpEventQueue();
      expect(GraineCalls.instance.value.agent, 'support');
      emit('action', <String, Object?>{
        'requestId': 'r1',
        'name': 'raise_ticket',
        'agent': 'support',
        'arguments': <String, Object?>{},
      });
      await pumpEventQueue();
      expect(((argsOf('resolveAction').single! as Map<Object?, Object?>)['result']! as Map<Object?, Object?>)['message'],
          'Ticket raised.', reason: "support's action runs in support's handler");

      emit('state', <String, Object?>{'state': 'ended', 'callId': 'call_1', 'agent': 'support'});
      await pumpEventQueue();
      expect(argsOf('setActions').last, <String>['open_plans'], reason: "after the call, the attached agent's again");
      expect((argsOf('setVariables').last! as Map<Object?, Object?>)['desk'], 'sales');

      // No agent named: the default, and nothing about agents on the channel.
      await GraineCalls.instance.startCall(reason: 'plans');
      expect((argsOf('startCall').last! as Map<Object?, Object?>).containsKey('agent'), isFalse);
    });

    test('the ring and the outcome say which agent; the push reaches the engine as it came', () async {
      make('default', mainKey);
      make('support', supportKey);
      final incoming = <GraineIncomingCall>[];
      final outcomes = <GraineCallOutcome>[];
      GraineCalls.instance.incomingCalls.listen(incoming.add);
      GraineCalls.instance.outcomes.listen(outcomes.add);
      await GraineCalls.instance.configure(options);
      expect(await GraineCalls.instance.handlePush(<String, Object?>{'type': 'graine_call', 'agent_id': 'agent-2'}), isTrue);
      expect((argsOf('handlePush').single! as Map<Object?, Object?>)['agent_id'], 'agent-2',
          reason: 'the engine matches the push to an agent');
      emit('incoming', <String, Object?>{'callId': 'h1', 'hosted': true, 'agent': 'support'});
      emit('outcome', <String, Object?>{'callId': 'h1', 'outcome': 'answered', 'hosted': true, 'agent': 'support'});
      emit('incoming', <String, Object?>{'callId': 'h2'});
      await pumpEventQueue();
      expect(incoming.first.agent, 'support');
      expect(outcomes.single.agent, 'support');
      expect(incoming.last.agent, isNull, reason: 'an engine that does not say: the default agent');
    });

    test("a native call takes the line from any agent's WebView call", () async {
      make('default', mainKey);
      final support = make('support', supportKey);
      support.voice.attach(FakePage());
      await support.voice.start();
      expect(support.voice.connecting, isTrue);
      await GraineCalls.instance.configure(options);
      emit('state', <String, Object?>{'state': 'ringing', 'callId': 'h1', 'direction': 'incoming', 'agent': 'support'});
      await pumpEventQueue();
      expect(support.voice.connecting, isFalse);
    });

    test('who the user is reaches the engine once, however many agents hear it', () async {
      final main = make('default', mainKey);
      make('support', supportKey);
      await GraineCalls.instance.configure(options);
      await pumpEventQueue();
      calls.clear();
      main.identify(<String, Object?>{'email': 'asha@example.com'});
      await pumpEventQueue();
      expect(argsOf('setIdentity'), <Object?>[
        <String, Object?>{'email': 'asha@example.com'},
      ]);
      expect(argsOf('setMemory'), <Object?>[true]);
    });
  });
}
