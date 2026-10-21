/// Graine's in-app voice agent for Flutter.
///
/// The call runs in a page Graine hosts, inside a WebView this package owns
/// ([GraineEngine], one invisible pixel), so every audio-path fix reaches the
/// app without a release. Dart handles the session, prompt variables, screen
/// context, in-app actions, lifecycle and UI.
///
///     GraineInApp.init(const GraineConfig(baseUrl: 'https://www.graine.ai', publishableKey: 'pk_live_…'));
///     runApp(MaterialApp(
///       builder: (context, child) => GraineEngine(
///         child: Stack(children: [child!, const GraineAgentBar()]),
///       ),
///       home: const HomeScreen(),
///     ));
library;

export 'src/agent_bar.dart' show GraineAgentBar;
export 'src/booking_sheet.dart' show GraineBooking, GraineBookingSheet;
export 'src/chat_view.dart' show GraineChat;
export 'src/core/core.dart'
    hide Js, SocketTrace, SvgPath, PathCommand, PathMoveTo, PathLineTo, PathCubicTo, PathQuadTo, PathArcTo, PathClose,
        ChatPresentation, ChatClose, ChatWindowLayout, ChatMarks, BookingClock, ChatCloseDelay, PastSessionsWire,
        PastSessionsPage;
export 'src/engine.dart' show GraineEngine, WebViewEnginePage;
export 'src/graine.dart' hide ChatWindows, ChatSocketCloseCode;
export 'src/launcher.dart' show GraineLauncher;
export 'src/loader_view.dart' show GraineLoaderView;
export 'src/transcript_view.dart' show GraineTranscriptView;
export 'src/widget_view.dart' show GraineWidgetTheme, GraineWidgetView;
