// The design's typefaces, fetched and kept: each URL at most once in a
// process, on disk for the next launch, and nothing that is not a font —
// registered under the contract's names. A mock HTTP client stands in for
// Graine and a temporary directory for the app's cache: nothing reaches a
// network host.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:graine_inapp/graine_inapp.dart';
import 'package:graine_inapp/src/fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'contract_files.dart';

/// The first four bytes of a TrueType file, and enough after them to be one.
final Uint8List ttf = Uint8List.fromList(<int>[0, 1, 0, 0, ...List<int>.filled(60, 7)]);

void main() {
  late ResolvedDesign editorial;
  late List<Map<String, Object?>> faces;

  setUpAll(() async {
    final fx = await contractJson('contract/design.json');
    final c = (fx['cases']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .firstWhere((Map<String, Object?> c) => (c['config']! as Map<String, Object?>)['preset'] == 'editorial');
    editorial = ResolvedDesign.fromJson(c['design'])!;
    faces = (c['fontFaces']! as List<Object?>).cast<Map<String, Object?>>();
    expect(faces, hasLength(3), reason: 'Newsreader 700, Source Serif 4 at 400 and 700');
  });

  Set<String> urls() => <String>{for (final f in faces) f['url']! as String};
  Map<String, String> loaded() =>
      <String, String>{for (final f in faces) '${f['family']}|${f['weight']}': f['name']! as String};

  test('each face is fetched once, registered under its own name, and published by family and weight', () async {
    final requests = <String>[];
    final registered = <String, int>{};
    final loader = DesignFontLoader(
      client: MockClient((http.Request req) async {
        requests.add(req.url.toString());
        return http.Response.bytes(ttf, 200);
      }),
      register: (String name, Uint8List bytes) async {
        expect(bytes, ttf);
        registered[name] = bytes.length;
      },
    );
    var notified = 0;
    loader.loaded.addListener(() => notified++);
    await Future.wait(<Future<void>>[
      loader.load(editorial, origin: Design.defaultOrigin),
      loader.load(editorial, origin: Design.defaultOrigin), // at the same time: still once
    ]);
    await loader.load(editorial, origin: Design.defaultOrigin); // and again later
    expect(requests.toSet(), urls());
    expect(requests, hasLength(3));
    expect(registered.keys.toSet(), <String>{for (final f in faces) f['name']! as String});
    expect(loader.loaded.value, loaded());
    expect(notified, 3, reason: 'one redraw per face that lands');
  });

  test('kept on disk by URL: the next launch registers from the file and fetches nothing', () async {
    final dir = Directory.systemTemp.createTempSync('graine-fonts-test-');
    addTearDown(() => dir.deleteSync(recursive: true));
    await DesignFontLoader(
      client: MockClient((http.Request req) async => http.Response.bytes(ttf, 200)),
      cacheDir: dir,
      register: (String name, Uint8List bytes) async {},
    ).load(editorial);
    final kept = dir.listSync().whereType<File>().toList();
    expect(kept, hasLength(3));
    expect(kept.every((File f) => f.path.endsWith('.ttf')), isTrue, reason: 'no half-written .part left behind');

    final registered = <String>[];
    final nextLaunch = DesignFontLoader(
      client: MockClient((http.Request req) async => fail('fetched ${req.url} although it was on disk')),
      cacheDir: dir,
      register: (String name, Uint8List bytes) async => registered.add(name),
    );
    await nextLaunch.load(editorial);
    expect(registered.toSet(), <String>{for (final f in faces) f['name']! as String});
    expect(nextLaunch.loaded.value, loaded());
  });

  test('an answer that is not a font is neither kept nor registered; a broken file on disk is fetched again', () async {
    final dir = Directory.systemTemp.createTempSync('graine-fonts-test-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final registered = <String>[];
    final loader = DesignFontLoader(
      client: MockClient((http.Request req) async => http.Response('<html>Sign in to Wi-Fi</html>', 200)),
      cacheDir: dir,
      register: (String name, Uint8List bytes) async => registered.add(name),
    );
    await loader.load(editorial);
    expect(registered, isEmpty);
    expect(loader.loaded.value, isEmpty);
    expect(dir.listSync(), isEmpty, reason: 'a captive portal is not cached as a typeface');

    // A file on disk that is not a font (half a download from a crash): fetched again, properly.
    await DesignFontLoader(
      client: MockClient((http.Request req) async => http.Response.bytes(ttf, 200)),
      cacheDir: dir,
      register: (String name, Uint8List bytes) async {},
    ).load(editorial);
    final file = dir.listSync().whereType<File>().first;
    file.writeAsBytesSync(<int>[1, 2, 3]);
    var fetched = 0;
    await DesignFontLoader(
      client: MockClient((http.Request req) async {
        fetched++;
        return http.Response.bytes(ttf, 200);
      }),
      cacheDir: dir,
      register: (String name, Uint8List bytes) async {},
    ).load(editorial);
    expect(fetched, 1);
    expect(file.readAsBytesSync(), ttf);
  });

  test('a registration that fails, or a network that does, is silent — the text stays in the platform font', () async {
    final loader = DesignFontLoader(
      client: MockClient((http.Request req) async => req.url.queryParameters['f'] == 'Newsreader'
          ? throw const SocketException('offline')
          : http.Response.bytes(ttf, 200)),
      register: (String name, Uint8List bytes) async {
        if (name.endsWith('-700')) throw StateError('the platform refused it');
      },
    );
    await loader.load(editorial);
    expect(loader.loaded.value, <String, String>{'Source Serif 4|400': 'Graine-SourceSerif4-400'});
  });

  test("a family the app bundles is its own, and never fetched; system is never fetched", () async {
    final requests = <String>[];
    final loader = DesignFontLoader(
      client: MockClient((http.Request req) async {
        requests.add(req.url.queryParameters['f']!);
        return http.Response.bytes(ttf, 200);
      }),
      register: (String name, Uint8List bytes) async {},
    );
    await loader.load(editorial, bundled: const <String>['source serif 4']);
    expect(requests, <String>['Newsreader']);
    await loader.load(ResolvedDesign.fromJson(<String, Object?>{
      'config': <String, Object?>{},
      'light': <String, Object?>{'colors': <String, Object?>{}},
    }));
    expect(requests, <String>['Newsreader'], reason: 'a design in the system font fetches nothing');
  });

  test('what counts as a font: TrueType, OpenType and Apple TrueType by their first bytes', () {
    Uint8List of(List<int> head) => Uint8List.fromList(<int>[...head, ...List<int>.filled(12, 0)]);
    expect(DesignFontLoader.looksLikeFont(of(<int>[0, 1, 0, 0])), isTrue);
    expect(DesignFontLoader.looksLikeFont(of('OTTO'.codeUnits)), isTrue);
    expect(DesignFontLoader.looksLikeFont(of('true'.codeUnits)), isTrue);
    expect(DesignFontLoader.looksLikeFont(of('<htm'.codeUnits)), isFalse);
    expect(DesignFontLoader.looksLikeFont(Uint8List.fromList(<int>[0, 1, 0, 0])), isFalse, reason: 'too short');
  });
}
