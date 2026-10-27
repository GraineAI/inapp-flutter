// Run before every test file in this folder: the plugin's app channel answers
// as a platform without the plugin would (device_mock.dart, noAppPlatform), so
// no test waits on a channel nobody answers. A test that plays the platform
// installs its own handler over it.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'device_mock.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  noAppPlatform();
  setUp(noAppPlatform);
  await testMain();
}
