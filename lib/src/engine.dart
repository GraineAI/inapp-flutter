import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'core/core.dart';
import 'graine.dart';

/// THE AUDIO ENGINE — the hosted page, in a WebView one pixel big.
///
/// Place it ONCE, near the root, so it outlives every screen: the agent's
/// job is to move the customer between screens, and an engine mounted inside
/// one would end the call on the very navigation that proves the feature.
///
///     MaterialApp(
///       builder: (context, child) => GraineEngine(child: child!),
///       ...
///     )
///
/// With a [child], the engine is stacked under it; without one it is just
/// the 1x1 box, for a host that places it in its own Stack.
///
/// One pixel and 1% opacity rather than removed or invisible: a platform
/// view that is not composited can have its media suspended by the OS,
/// which would kill the call the moment your own UI hid it.
class GraineEngine extends StatefulWidget {
  const GraineEngine({super.key, this.child, this.voice});

  final Widget? child;

  /// The call to attach. Default: [GraineInApp.instance]'s.
  final GraineVoice? voice;

  @override
  State<GraineEngine> createState() => _GraineEngineState();
}

class _GraineEngineState extends State<GraineEngine> {
  WebViewEnginePage? _page;
  GraineVoice? _voice;

  @override
  void initState() {
    super.initState();
    // No platform implementation (a widget test of the host app): draw the
    // box, attach nothing.
    if (WebViewPlatform.instance == null) return;
    final voice = widget.voice ?? GraineInApp.instance.voice;
    final page = WebViewEnginePage(baseUrl: voice.config.baseUrl, debug: voice.config.debug);
    _voice = voice;
    _page = page;
    voice.attach(page);
  }

  @override
  void dispose() {
    final page = _page;
    if (page != null) _voice?.detachPage(page);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final Widget engine = SizedBox(
      width: 1,
      height: 1,
      child: page == null
          ? null
          : IgnorePointer(
              child: ExcludeSemantics(
                child: Opacity(opacity: 0.01, child: WebViewWidget(controller: page.controller)),
              ),
            ),
    );
    final child = widget.child;
    if (child == null) return engine;
    return Stack(
      alignment: Alignment.topLeft,
      fit: StackFit.passthrough,
      children: <Widget>[
        child,
        Positioned(left: 0, bottom: 0, width: 1, height: 1, child: engine),
      ],
    );
  }
}

/// The engine page in a `webview_flutter` WebView: JavaScript on, media
/// without a gesture (nothing on a 1x1 view can be tapped), the bridge the
/// page looks for (`window.ReactNativeWebView`), and the microphone granted
/// to the page only when the app holds it.
class WebViewEnginePage implements GraineEnginePage {
  WebViewEnginePage({required String baseUrl, bool debug = false})
      : _base = Uri.tryParse(baseUrl),
        _debug = debug {
    final PlatformWebViewControllerCreationParams params = WebViewPlatform.instance is WebKitWebViewPlatform
        ? WebKitWebViewControllerCreationParams(
            // iOS: inline, and no gesture — the agent speaks first.
            allowsInlineMediaPlayback: true,
            mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
          )
        : const PlatformWebViewControllerCreationParams();
    controller = WebViewController.fromPlatformCreationParams(params);
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (String _) => _sink?.pageStarted(),
        onProgress: (int p) => _sink?.progress(p),
        onPageFinished: (String _) => _sink?.pageFinished(),
        onWebResourceError: _onError,
        onHttpError: _onHttpError,
        onNavigationRequest: _onNavigation,
      ))
      ..addJavaScriptChannel(Protocol.bridgeName,
          onMessageReceived: (JavaScriptMessage m) => _sink?.message(m.message));
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      // In debug, the engine is inspectable at chrome://inspect like any page.
      if (debug) AndroidWebViewController.enableDebugging(true);
      platform.setMediaPlaybackRequiresUserGesture(false);
      platform.setOnPlatformPermissionRequest(_onPermission);
    } else if (platform is WebKitWebViewController) {
      platform.setOnPlatformPermissionRequest(_onPermission);
      if (debug) platform.setInspectable(true);
    }
    if (debug) {
      controller.setOnConsoleMessage((JavaScriptConsoleMessage m) {
        debugPrint('[Graine] page console ${m.level.name}: ${m.message}');
      });
    }
  }

  /// The WebView's controller, for [WebViewWidget].
  late final WebViewController controller;

  final Uri? _base;
  final bool _debug;
  GraineEngineSink? _sink;
  String? _enginePath;
  bool _disposed = false;

  @override
  void bind(GraineEngineSink sink) => _sink = sink;

  @override
  void load(String url) {
    if (_disposed) return;
    _enginePath = Uri.tryParse(url)?.path;
    controller.loadRequest(Uri.parse(url));
  }

  @override
  void reload() {
    if (_disposed) return;
    controller.reload();
  }

  @override
  void run(String javaScript) {
    if (_disposed) return;
    controller.runJavaScript(javaScript).catchError((Object e) {
      // Posting into a page that is still loading is not a failure worth a crash.
      if (_debug) debugPrint('[Graine] could not deliver to the page: $e');
    });
  }

  /// Tear the page down now — its socket and its microphone go with it —
  /// rather than whenever the WebView is collected.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _sink = null;
    controller.loadRequest(Uri.parse('about:blank')).catchError((Object _) {});
  }

  void _onError(WebResourceError e) {
    // A subresource failing (a favicon, an analytics beacon) is not the page failing.
    if (e.isForMainFrame == false) return;
    // iOS NSURLErrorCancelled: one navigation replaced by another — our own reload.
    if (e.errorCode == -999) return;
    final gone = e.errorType == WebResourceErrorType.webContentProcessTerminated;
    _sink?.mainFrameError(gone ? 'render-process-gone' : 'load-error:${e.errorCode}');
  }

  void _onHttpError(HttpResponseError e) {
    // Android reports every resource with its URL; only the engine page's own
    // document counts. iOS reports navigation responses only, with no URL.
    final uri = e.request?.uri;
    if (uri != null && uri.path != _enginePath) return;
    _sink?.mainFrameError('http-${e.response?.statusCode}');
  }

  /// The engine never leaves Graine's origin; anything else is not loaded.
  NavigationDecision _onNavigation(NavigationRequest r) {
    if (_disposed || !r.isMainFrame) return NavigationDecision.navigate;
    final target = Uri.tryParse(r.url);
    final base = _base;
    final same = target != null && base != null && target.scheme == base.scheme && target.host == base.host;
    return same ? NavigationDecision.navigate : NavigationDecision.prevent;
  }

  void _onPermission(PlatformWebViewPermissionRequest request) {
    final types = request.types;
    final wantsMic = types.contains(WebViewPermissionResourceType.microphone);
    final grant = wantsMic && (_sink?.microphoneRequested(onlyMicrophone: types.length == 1) ?? false);
    if (grant) {
      request.grant();
    } else {
      request.deny();
    }
  }
}
