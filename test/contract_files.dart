// Finding the shared contract: sdk/contract/*.json in the repository, or
// contract/*.json beside the package when it is exported on its own. Used by
// the contract tests and by the widget tests that draw real sessions' designs.
// Imports only Dart and package:test, so the pure tests stay pure.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

/// Where this package really lives — through the symlinks of a harness, if
/// the tests are being run from one — found from the core library itself.
Future<Directory?> packageRoot() async {
  try {
    final uri = await Isolate.resolvePackageUri(Uri.parse('package:graine_inapp/src/core/core.dart'));
    if (uri == null || uri.scheme != 'file') return null;
    final core = File(File.fromUri(uri).resolveSymbolicLinksSync());
    return core.parent.parent.parent.parent; // core → src → lib → package root
  } catch (_) {
    return null; // a test runner that cannot resolve packages: the working directory still works
  }
}

/// [relative] from the repository's `sdk/` directory, or a failed test.
Future<File> requireFile(String relative) async {
  final f = await findUp(relative);
  if (f == null) {
    fail('sdk/$relative not found. Run the tests from inside the repository checkout — '
        'this contract is never skipped.');
  }
  return f;
}

/// Walk up from the package (and from the working directory) until
/// `sdk/<relative>` or `<relative>` exists.
Future<File?> findUp(String relative) async {
  final starts = <Directory>[];
  final root = await packageRoot();
  if (root != null) starts.add(root);
  starts.add(Directory.current.absolute);
  for (final start in starts) {
    Directory? dir = start;
    while (dir != null) {
      for (final candidate in <String>['${dir.path}/sdk/$relative', '${dir.path}/$relative']) {
        final f = File(candidate);
        if (f.existsSync()) return f;
      }
      final parent = dir.parent;
      dir = parent.path == dir.path ? null : parent;
    }
  }
  return null;
}

/// A contract JSON file, decoded, or a failed test.
Future<Map<String, Object?>> contractJson(String relative) async =>
    jsonDecode((await requireFile(relative)).readAsStringSync()) as Map<String, Object?>;
