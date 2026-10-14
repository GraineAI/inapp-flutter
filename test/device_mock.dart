// The plugin's device channel, as a test's platform side: the install id the
// native SDK keeps, the IANA zone, and the package's preferences (kept here,
// so a test can read what was written and start the next "launch" from it).
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const MethodChannel deviceChannel = MethodChannel('ai.graine.inapp/device');

/// The install id every mocked device reports.
const String testInstallId = '3f2504e0-4f89-11d3-9a0c-0305e82c3301';

class DeviceMock {
  DeviceMock({this.installId = testInstallId, this.timezone = 'Asia/Kolkata', Map<String, Object?>? prefs})
      : prefs = prefs ?? <String, Object?>{};

  String? installId;
  String? timezone;
  Map<String, Object?> prefs;
  final List<MethodCall> calls = <MethodCall>[];

  /// Answer the device channel from now on.
  void install() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(deviceChannel,
        (MethodCall call) async {
      calls.add(call);
      switch (call.method) {
        case 'installId':
          return installId;
        case 'timezone':
          return timezone;
        case 'readPrefs':
          return jsonEncode(prefs);
        case 'writePrefs':
          prefs = (jsonDecode(call.arguments! as String) as Map<String, Object?>);
          return null;
      }
      return null;
    });
  }

  static void uninstall() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(deviceChannel, null);
}
