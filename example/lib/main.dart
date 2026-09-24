// THE WHOLE INTEGRATION, end to end:
//
//   1. GraineInApp.init(...)              — once, before runApp
//   2. GraineEngine + GraineAgentBar      — once, around the navigator
//   3. setScreen / identify / registerAction — as the app runs
//
// Plus what a device check needs to see: a component area (with a button that
// previews one without asking the agent), a text field that raises the
// keyboard, and a bar whose dragged position survives a relaunch.
//
// The key below is the Android sample's (publishable keys are public by
// design: they select an agent and cannot place a call on their own). Use
// your own:  flutter run --dart-define=GRAINE_PUBLISHABLE_KEY=pk_live_…
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:graine_inapp/graine_inapp.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

// No default: this example is published with the package, and a key in it would
// be every reader's key. Run it with your own agent's.
const String publishableKey = String.fromEnvironment('GRAINE_PUBLISHABLE_KEY');
const String baseUrl = String.fromEnvironment('GRAINE_BASE_URL', defaultValue: 'https://www.graine.ai');
const String barOffsetKey = 'graine.bar.offset';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  final graine = GraineInApp.init(GraineConfig(
    baseUrl: baseUrl,
    publishableKey: publishableKey,
    variables: const <String, Object?>{'brand': 'Graine sample'},
    appVersion: '1.0.0',
    // Every bridge message and the engine page's console, in the log. Debug builds only.
    debug: kDebugMode,
    // The app holds the microphone; the SDK grants it to the engine page.
    requestMicrophone: () async => (await Permission.microphone.request()).isGranted,
  ));
  graine.identify(const <String, Object?>{'name': 'Sample Tester'});
  graine.addListener(EventLog());

  runApp(SampleApp(prefs: prefs));
}

/// Every event, to the log — a template for your own analytics.
class EventLog with GraineListener {
  void _log(String s) => debugPrint('[GraineSample] $s');
  @override
  void onSessionReady(SessionConfig session) =>
      _log('session agent=${session.webcallAgentId} transport=${session.preferredTransport.wire} page=${session.pageVersion}');
  @override
  void onConnectivity(GraineConnectivity state, int attempt, String? reason) =>
      _log('connectivity ${state.name} attempt=$attempt reason=$reason');
  @override
  void onCallState(bool connected, bool connecting) => _log('call connected=$connected connecting=$connecting');
  @override
  void onCaption(Role role, String text, bool live) => _log('caption ${role.name} live=$live: $text');
  @override
  void onQuality(ConnectionQuality quality) => _log('quality ${quality.name}');
  @override
  void onWidget(Map<String, Object?> widget) => _log('widget ${widget['kind']}');
  @override
  void onEnded() => _log('ended');
  @override
  void onMicDenied(String reason) => _log('mic denied: $reason');
  @override
  void onError(String message) => _log('ERROR $message');
}

class SampleApp extends StatelessWidget {
  const SampleApp({super.key, required this.prefs});

  final SharedPreferences prefs;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Graine sample',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF318CE7), useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF318CE7), brightness: Brightness.dark, useMaterial3: true),
      // The engine and the bar sit around the navigator, so they outlive every screen.
      builder: (BuildContext context, Widget? child) => GraineEngine(
        child: Stack(
          children: <Widget>[
            child!,
            GraineAgentBar(
              // The component area is on the screen below instead (ComponentArea).
              showComponents: false,
              initialOffset: prefs.getInt(barOffsetKey),
              onPlacementChange: (int offset) => prefs.setInt(barOffsetKey, offset),
            ),
          ],
        ),
      ),
      home: const KycScreen(),
    );
  }
}

class KycScreen extends StatefulWidget {
  const KycScreen({super.key});

  @override
  State<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends State<KycScreen> {
  final TextEditingController _pan = TextEditingController();
  late final void Function() _unregister;

  @override
  void initState() {
    super.initState();
    // Something the agent may do. Declare it on the agent in the dashboard too.
    _unregister = GraineInApp.instance.registerAction('fill_pan', (Map<String, Object?> args) {
      final value = args['pan'];
      if (value is! String || value.isEmpty) return const ActionResult.refused('No PAN was given.');
      setState(() => _pan.text = value);
      _report();
      return const ActionResult.ok('Filled in the PAN.');
    });
    _report();
  }

  @override
  void dispose() {
    _unregister();
    _pan.dispose();
    super.dispose();
  }

  bool get _valid => RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(_pan.text);

  /// What the customer is looking at — every meaningful change.
  void _report() {
    final text = _pan.text;
    GraineInApp.instance.setScreen(GraineScreen(
      'kyc_documents',
      title: 'Upload your documents',
      journey: const GraineJourney('KYC', step: 2, of: 4, next: 'Selfie check'),
      fields: <GraineField>[
        GraineField(
          'pan',
          label: 'PAN',
          value: text,
          status: text.isEmpty ? FieldStatus.empty : (_valid ? FieldStatus.filled : FieldStatus.invalid),
          error: text.isNotEmpty && !_valid ? 'That is not a valid PAN' : null,
        ),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final voice = GraineInApp.instance.voice;
    return Scaffold(
      appBar: AppBar(title: const Text('KYC · step 2 of 4')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 200),
        children: <Widget>[
          Text('Upload your PAN', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          // Focus this: the bar rises above the keyboard.
          TextField(
            controller: _pan,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'PAN',
              border: const OutlineInputBorder(),
              errorText: _pan.text.isNotEmpty && !_valid ? 'That is not a valid PAN' : null,
            ),
            onChanged: (String _) {
              setState(() {});
              _report();
            },
          ),
          const SizedBox(height: 24),
          ListenableBuilder(
            listenable: voice,
            builder: (BuildContext context, Widget? _) => Text(
              'Engine: ${voice.connectivity.name}${voice.ready ? ' · ready' : ''}'
              ' · call: ${voice.connected ? 'live' : (voice.connecting ? 'connecting' : 'idle')}'
              ' · quality: ${voice.quality.name}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 24),
          Text('Component area', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const ComponentArea(),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton(onPressed: _previewCars, child: const Text('Preview: compare cars')),
              OutlinedButton(onPressed: _previewChoices, child: const Text('Preview: choices')),
              OutlinedButton(onPressed: _previewLoading, child: const Text('Preview: loading')),
            ],
          ),
        ],
      ),
    );
  }

  // Previews draw exactly as if the agent had sent them; an answer to one goes
  // to a live call when there is one, and nowhere otherwise.
  void _previewCars() => GraineInApp.instance.components.present(<String, Object?>{
        'widget_id': 'car_showcase:preview',
        'kind': 'product_list',
        'style': <String, Object?>{'preset': 'cards', 'select': 'many', 'maxSelect': 2},
        'data': <String, Object?>{
          'title': 'Three that fit your budget',
          'prompt': 'Tick two to compare.',
          'selectLabel': 'Compare',
          'items': <Object?>[
            <String, Object?>{'id': 'creta', 'title': 'Creta', 'price': '₹19.2 lakh', 'facts': <Object?>['6 airbags', 'Automatic']},
            <String, Object?>{'id': 'seltos', 'title': 'Seltos', 'price': '₹17.8 lakh', 'subtitle': 'Best value'},
            <String, Object?>{'id': 'venue', 'title': 'Venue', 'price': '₹12.1 lakh'},
          ],
        },
      });

  void _previewChoices() => GraineInApp.instance.components.present(<String, Object?>{
        'widget_id': 'choices:preview',
        'kind': 'choices',
        'data': <String, Object?>{
          'title': 'How would you like to verify?',
          'options': <Object?>['Aadhaar OTP', 'DigiLocker', 'Upload a photo'],
        },
      });

  void _previewLoading() {
    final c = GraineInApp.instance.components;
    c.presentPending(<String, Object?>{'widget_id': 'car_showcase:preview', 'kind': 'product_list'});
    Future<void>.delayed(const Duration(seconds: 2), _previewCars);
  }
}

/// Where the agent's components appear on this screen.
class ComponentArea extends StatelessWidget {
  const ComponentArea({super.key});

  @override
  Widget build(BuildContext context) {
    return const GraineWidgetView(maxHeight: 520);
  }
}
