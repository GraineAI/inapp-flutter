// HOW BIG THE CHAT WINDOW OPENS — contract/DESIGN.md "Chat window" → Size.
//
// The brand chooses in the dashboard (Embed & Widgets → Appearance → Chat
// window → Window size), which arrives as the design's `chat.size`; the app
// may choose otherwise in GraineConfig.chatSize, and once more for one open
// with GraineChat.open. What a size LOOKS like depends on the screen: a phone
// gets a sheet or the whole screen, a tablet a panel in the corner. The rule
// and the numbers are every Graine SDK's (sdk/inapp/theme.ts: chatSizeOf,
// chatPresentation, CHAT_WINDOW). Pure, and tested by test/chat_size_test.dart.

/// How big the chat window opens.
enum GraineChatSize {
  /// The window above the bar, as it has always been.
  compact,

  /// A sheet over most of a phone; a panel in the corner of a tablet.
  large,

  /// The whole screen.
  full;

  /// The design's word for it.
  String get wire => name;

  /// The design's word for a size; null for anything else — absent, or a newer server's word.
  static GraineChatSize? fromWire(Object? raw) {
    if (raw is! String) return null;
    final word = raw.trim().toLowerCase();
    for (final s in GraineChatSize.values) {
      if (s.name == word) return s;
    }
    return null;
  }
}

/// Where a chat window goes: above the bar, up from the bottom, in the corner, or all of it.
enum ChatPresentation { window, sheet, panel, screen }

/// What closing a sheet, a panel or a screen does — what the chevron does.
enum ChatClose {
  /// Back to the call, where the agent offers both.
  backToCall,

  /// The chat was all there was: the bar closes.
  closeBar,
}

/// The rule and the numbers a bigger chat window is drawn with.
abstract final class ChatWindowLayout {
  /// A sheet's top edge sits this share of the screen's height below the top safe area.
  static const double sheetTop = 0.08;

  /// A panel: this wide, and min([panelMaxHeight], [panelHeight] × the screen's height) tall.
  static const double panelWidth = 420;
  static const double panelMaxHeight = 760;
  static const double panelHeight = 0.9;

  /// In from the screen's edges (inside the safe area).
  static const double panelInset = 24;

  /// A window whose shorter side is at least this is a tablet's.
  static const double tabletMinSide = 600;

  /// Dragged down this far, a sheet closes.
  static const double closeDrag = 80;

  /// The grab handle: a strip in the header's fill, a short bar in it.
  static const double handleStrip = 16;
  static const double handleWidth = 36;
  static const double handleHeight = 5;

  /// The app behind a sheet, dimmed.
  static const double scrimOpacity = 0.4;

  /// The size to open at: the open's own, then the app's, then the design's, else compact.
  static GraineChatSize size({GraineChatSize? open, GraineChatSize? config, GraineChatSize? token}) =>
      open ?? config ?? token ?? GraineChatSize.compact;

  /// How a size is drawn in a window this big (logical pixels).
  static ChatPresentation presentation(GraineChatSize size, double width, double height) => switch (size) {
        GraineChatSize.compact => ChatPresentation.window,
        GraineChatSize.large => (width < height ? width : height) >= tabletMinSide ? ChatPresentation.panel : ChatPresentation.sheet,
        GraineChatSize.full => ChatPresentation.screen,
      };

  /// A panel's width and height in a window this tall.
  static ({double width, double height}) panelSize(double height) {
    final h = height.isFinite ? (panelHeight * height).clamp(0, panelMaxHeight).roundToDouble() : 0.0;
    return (width: panelWidth, height: h);
  }

  /// Where the bar draws its chat: null while the customer is on the call.
  static ChatPresentation? barPresentation({
    required bool inChat,
    GraineChatSize? open,
    GraineChatSize? config,
    GraineChatSize? token,
    required double width,
    required double height,
  }) =>
      inChat ? presentation(size(open: open, config: config, token: token), width, height) : null;

  /// A drag let go (pixels, and pixels a second): does the sheet close?
  static bool dragCloses(double dy, double velocity) => dy > closeDrag || velocity > 1000;

  static ChatClose close({required bool canSwitch}) => canSwitch ? ChatClose.backToCall : ChatClose.closeBar;
}
