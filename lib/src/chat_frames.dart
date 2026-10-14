// THE BIGGER CHAT WINDOWS — contract/DESIGN.md "Chat window" → Size: the
// frames a sheet, a tablet's panel and a full screen put around the chat
// window. Not exported: GraineAgentBar draws them over the app, and
// GraineChat.open presents them on a screen with no bar.
import 'package:flutter/widgets.dart';

import 'chat_window.dart';
import 'core/core.dart';
import 'style.dart';

/// The chevron of a [ChatFrameScope]'s chat leads its header — a full screen's close.
class ChatFrameScope extends StatelessWidget {
  const ChatFrameScope({super.key, this.leadingChevron = false, required this.child});

  final bool leadingChevron;
  final Widget child;

  /// Whether a chat under [context] leads with its chevron.
  static bool leads(BuildContext context) => context.findAncestorWidgetOfExactType<ChatFrameScope>()?.leadingChevron ?? false;

  @override
  Widget build(BuildContext context) => child;
}

/// A SHEET up from the bottom: the chat's background, corners `radius.xl` at
/// the top only, the floating shadow (none with a hard offset), and a grab
/// handle along its top — a strip in the header's fill (the title bar's with
/// window chrome), a 36 × 5 bar in the header's quieter colour at half
/// strength. Dragging the handle or the header down past 80 points, or
/// flinging it, calls [onClose]; a shorter drag settles back. The thread
/// under it scrolls as ever.
class ChatSheetFrame extends StatefulWidget {
  const ChatSheetFrame({
    super.key,
    required this.look,
    required this.onClose,
    required this.child,
    this.motion = Duration.zero,
    this.shadows,
  });

  final ChatLook look;

  /// The floating shadow — null with a hard offset, which has nowhere to show at the screen's edges.
  final List<BoxShadow>? shadows;
  final VoidCallback onClose;
  final Widget child;

  /// How long settling back takes: the design's pace, zero for none.
  final Duration motion;

  static const Key sheetKey = ValueKey<String>('graine-chat-sheet');
  static const Key handleKey = ValueKey<String>('graine-chat-sheet-handle');

  @override
  State<ChatSheetFrame> createState() => _ChatSheetFrameState();
}

class _ChatSheetFrameState extends State<ChatSheetFrame> {
  double _pull = 0;
  bool _pulling = false;

  /// Only a drag that starts on the handle or the header pulls the sheet.
  static const double _dragZone = ChatWindowLayout.handleStrip + 50;

  void _start(DragStartDetails d) => _pulling = d.localPosition.dy <= _dragZone;

  void _update(DragUpdateDetails d) {
    if (!_pulling) return;
    setState(() => _pull = (_pull + d.delta.dy).clamp(0, double.infinity).toDouble());
  }

  void _end(DragEndDetails d) {
    if (!_pulling) return;
    _pulling = false;
    if (ChatWindowLayout.dragCloses(_pull, d.primaryVelocity ?? 0)) {
      widget.onClose();
      return;
    }
    setState(() => _pull = 0);
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.look;
    final chrome = l.chrome;
    final strip = chrome != null ? chrome.fill : l.header;
    final bar = fade(chrome != null ? l.muted : l.chevron, 0.5);
    final top = Radius.circular(l.xl);
    return AnimatedContainer(
      key: ChatSheetFrame.sheetKey,
      duration: _pulling ? Duration.zero : widget.motion,
      transform: Matrix4.translationValues(0, _pull, 0),
      decoration: BoxDecoration(
        color: l.background,
        borderRadius: BorderRadius.vertical(top: top),
        boxShadow: widget.shadows,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(top: top),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: _start,
          onVerticalDragUpdate: _update,
          onVerticalDragEnd: _end,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ExcludeSemantics(
                child: Container(
                  key: ChatSheetFrame.handleKey,
                  height: ChatWindowLayout.handleStrip,
                  color: strip,
                  alignment: Alignment.center,
                  child: Container(
                    width: ChatWindowLayout.handleWidth,
                    height: ChatWindowLayout.handleHeight,
                    decoration: BoxDecoration(color: bar, borderRadius: BorderRadius.circular(ChatWindowLayout.handleHeight / 2)),
                  ),
                ),
              ),
              Expanded(child: widget.child),
            ],
          ),
        ),
      ),
    );
  }
}

/// WHERE A BIGGER CHAT WINDOW SITS on a screen this big ([media]): a sheet's
/// top 8% of the screen below the status bar, full width, to the bottom
/// edge; a tablet's panel 420 wide and min(760, 90%) tall in the bottom right
/// corner, 24 in from the safe area (and above the keyboard); a full screen
/// all of it, the header's fill behind the status bar. [window] is the chat
/// window filling it; [onClose] is what closing does.
Widget chatOverScreen({
  required ChatPresentation presentation,
  required MediaQueryData media,
  required ChatLook look,
  required Color scrim,
  required VoidCallback onClose,
  required Widget window,
  Duration motion = Duration.zero,
  List<BoxShadow>? sheetShadows,
}) {
  final keyboard = media.viewInsets.bottom;
  switch (presentation) {
    case ChatPresentation.sheet:
      final top = media.padding.top + ChatWindowLayout.sheetTop * media.size.height;
      return Stack(
        key: chatOverScreenKey,
        children: <Widget>[
          Positioned.fill(
            child: Semantics(
              label: 'Close the chat',
              button: true,
              child: GestureDetector(
                onTap: onClose,
                child: ColoredBox(color: fade(scrim, ChatWindowLayout.scrimOpacity)),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            top: top,
            child: ChatSheetFrame(
              look: look,
              onClose: onClose,
              motion: motion,
              shadows: sheetShadows,
              // The composer above the keyboard, else above the home indicator.
              child: Padding(padding: EdgeInsets.only(bottom: keyboard > 0 ? keyboard : media.padding.bottom), child: window),
            ),
          ),
        ],
      );
    case ChatPresentation.panel:
      final panel = ChatWindowLayout.panelSize(media.size.height);
      final inset = ChatWindowLayout.panelInset;
      final room = (media.size.height - media.padding.top - media.padding.bottom - 2 * inset - keyboard).clamp(0, double.infinity);
      return Align(
        key: chatOverScreenKey,
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: EdgeInsets.only(right: inset + media.padding.right, bottom: inset + (keyboard > media.padding.bottom ? keyboard : media.padding.bottom)),
          child: SizedBox(key: chatPanelKey, width: panel.width, height: panel.height < room ? panel.height : room.toDouble(), child: window),
        ),
      );
    case ChatPresentation.screen:
    case ChatPresentation.window:
      return ColoredBox(
        key: chatOverScreenKey,
        color: look.background,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // The status bar, in the header's fill (the title bar's with window chrome).
            if (media.padding.top > 0) Container(height: media.padding.top, color: look.chrome?.fill ?? look.header),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: media.padding.left, right: media.padding.right),
                child: window,
              ),
            ),
            // Clear of the keyboard, else of the home indicator.
            SizedBox(height: keyboard > 0 ? keyboard : media.padding.bottom),
          ],
        ),
      );
  }
}

/// The layer a bigger chat window is drawn in, and a tablet's panel in it (tests).
const Key chatOverScreenKey = ValueKey<String>('graine-chat-over-screen');
const Key chatPanelKey = ValueKey<String>('graine-chat-panel');
