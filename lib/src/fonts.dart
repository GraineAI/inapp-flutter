// The design's typefaces, fetched and registered by the SDK itself. Not
// exported: GraineInApp owns one loader and publishes what it has loaded as
// GraineInApp.fontFaces; the widgets draw from that.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'core/core.dart';

/// Registers one downloaded face with the platform under [name]. The default
/// is Flutter's [FontLoader]; a test hands in its own.
typedef FontRegistrar = Future<void> Function(String name, Uint8List bytes);

/// The platform registration: one [FontLoader] per face, under the face's own
/// family name — `Graine-DMSans-700` holds DM Sans Bold and nothing else, so
/// text set in it is bold without asking for bold (contract/DESIGN.md, "Fonts").
Future<void> registerWithFontLoader(String name, Uint8List bytes) async {
  final loader = FontLoader(name)..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  await loader.load();
}

/// Where downloaded faces are kept between launches, or null when this
/// platform has no file system the SDK can use. The app's own cache
/// directory — Android's cache dir, iOS's Library/Caches — which the OS may
/// clear under pressure and the SDK then refills; never a place that is
/// backed up or synced.
Directory? defaultFontCacheDir() {
  try {
    final tmp = Directory.systemTemp;
    if (Platform.isIOS) {
      // tmp/ is purged whenever iOS likes; Library/Caches, beside it in the
      // app's container, is where a year-long cache belongs.
      final caches = Directory('${tmp.parent.path}/Library/Caches');
      if (caches.existsSync()) return Directory('${caches.path}/graine-fonts');
    }
    return Directory('${tmp.path}/graine-fonts');
  } catch (_) {
    return null; // no dart:io file system here: memory only
  }
}

/// THE DESIGN'S TYPEFACES, FETCHED BY THE SDK.
///
/// A brand picks a typeface in the dashboard and expects the phone to draw
/// it. Until 0.3.0 a design's family reached a Flutter app only if the app
/// happened to bundle that exact family and listed it in [GraineConfig.fonts]
/// — in practice never — so the brand saw its typeface change nowhere.
///
/// Now the SDK decides everything: which faces the design draws with
/// ([DesignFonts.facesForDesign]), where Graine serves each one
/// (`/api/embed/font`, on the session's own origin, so an app talks to nobody
/// it did not already talk to), and when to redraw with them. Each face is
/// fetched at most once — kept on disk by its URL (which carries the asset
/// version) and in memory for the process — and registered once.
///
/// Nothing here can reach a customer as a failure: a face that does not
/// arrive, or is not a font, is simply never used, and the text stays in the
/// platform's font at the weight the design asked for.
class DesignFontLoader {
  DesignFontLoader({
    required http.Client client,
    Directory? cacheDir,
    FontRegistrar? register,
    this.debug = false,
  })  : _client = client,
        _cacheDir = cacheDir,
        _register = register ?? registerWithFontLoader;

  final http.Client _client;
  final Directory? _cacheDir;
  final FontRegistrar _register;

  /// Log each failure with the "[Graine]" prefix.
  final bool debug;

  final ValueNotifier<Map<String, String>> _loaded = ValueNotifier<Map<String, String>>(const <String, String>{});

  /// `family|weight` → the family name the face is registered under, for
  /// every face that has loaded. Empty until one does.
  ValueListenable<Map<String, String>> get loaded => _loaded;

  /// Every face asked for, by URL — loading, loaded, or failed. A URL is
  /// fetched at most once in a process; one that failed is tried again on
  /// the next launch, not on the next rebuild of a widget.
  final Map<String, Future<void>> _asked = <String, Future<void>>{};

  /// Fetch and register every face [design] draws with, light and dark,
  /// that is not already on its way. Families the app bundles itself
  /// ([bundled], [GraineConfig.fonts]) win and are never fetched. Returns
  /// when every face asked for has landed or failed.
  Future<void> load(ResolvedDesign? design, {String? origin, Iterable<String> bundled = const <String>[]}) {
    if (design == null) return Future<void>.value();
    final waits = <Future<void>>[];
    for (final face in DesignFonts.facesForDesign(design, origin: origin)) {
      if (Design.fontFamily(face.family, bundled) != null) continue;
      waits.add(_asked.putIfAbsent(face.url, () => _loadFace(face)));
    }
    return Future.wait(waits).then((_) {});
  }

  Future<void> _loadFace(DesignFontFace face) async {
    try {
      final bytes = await _bytes(face.url);
      if (bytes == null) return;
      await _register(face.name, bytes);
      _loaded.value = <String, String>{..._loaded.value, face.key: face.name};
    } catch (e) {
      // Drawn in the platform's font, as the contract promises. Loud for the
      // developer (with debug on), invisible to the customer.
      if (debug) debugPrint('[Graine] could not load ${face.name}: $e');
    }
  }

  /// The face's file: from disk when an earlier launch kept it, else from
  /// the network, kept for the next launch.
  Future<Uint8List?> _bytes(String url) async {
    final file = _fileFor(url);
    if (file != null) {
      try {
        if (file.existsSync()) {
          final kept = await file.readAsBytes();
          if (looksLikeFont(kept)) return kept;
          file.deleteSync(); // half a file, or not a font: fetch it properly
        }
      } catch (_) {
        // An unreadable cache is an empty one.
      }
    }
    final res = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    final bytes = res.bodyBytes;
    // Only a font is kept or registered: an error page cached as a TTF would
    // stand in for the brand's typeface for a year.
    if (res.statusCode != 200 || !looksLikeFont(bytes)) {
      if (debug) debugPrint('[Graine] $url answered ${res.statusCode}, not a font');
      return null;
    }
    if (file != null) {
      try {
        await file.parent.create(recursive: true);
        // Written aside and renamed, so a launch that dies mid-write never
        // finds half a font under the real name.
        final part = File('${file.path}.part');
        await part.writeAsBytes(bytes, flush: true);
        await part.rename(file.path);
      } catch (_) {
        // Not kept on disk; it is still drawn, and fetched again next launch.
      }
    }
    return bytes;
  }

  /// One file per URL, named by the URL itself: the URL carries the family,
  /// the weight and the asset version, so a changed file is a new name.
  File? _fileFor(String url) {
    final dir = _cacheDir;
    if (dir == null) return null;
    final name = base64Url.encode(utf8.encode(url)).replaceAll('=', '');
    return File('${dir.path}/$name.ttf');
  }

  /// A TrueType or OpenType file, by its first four bytes: 00 01 00 00, "OTTO" or "true".
  static bool looksLikeFont(Uint8List b) {
    if (b.length < 12) return false;
    final tag = (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
    return tag == 0x00010000 || tag == 0x4F54544F /* OTTO */ || tag == 0x74727565 /* true */;
  }
}
