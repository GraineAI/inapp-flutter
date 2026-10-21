import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'agent_bar.dart' show openChatInBar;
import 'booking_sheet.dart';
import 'chat_frames.dart';
import 'chat_window.dart';
import 'core/core.dart';
import 'graine.dart';
import 'style.dart';
import 'widget_view.dart';

/// A FULL-SCREEN CHAT WITH THE AGENT — for a route of its own, a tab, a
/// sheet: the chat window of the voice bar, filling the space it is given,
/// drawn from the brand's design and nothing else.
///
///     Navigator.of(context).push(PageRouteBuilder<void>(
///       pageBuilder: (context, _, __) => GraineChat(onClose: () => Navigator.of(context).pop()),
///     ));
///
/// It opens the chat while it is on screen. When it goes, the conversation
/// is kept — opening the chat again goes on with it, nothing on screen
/// changing — until it has been idle for 5 minutes, no message either way,
/// and then closes. It draws the components the agent shows above the
/// composer, keeps clear of the status bar, the home indicator and the
/// keyboard, and says "Connecting…" while it connects.
///
/// In an app with several agents, hand it the one this screen talks to:
/// `GraineChat(app: GraineInApp.named('support'))`.
class GraineChat extends StatefulWidget {
  const GraineChat({
    super.key,
    this.chat,
    this.components,
    this.design,
    this.scheme,
    this.accent,
    this.name,
    this.onClose,
    this.showComponents = true,
    this.app,
  });

  /// The chat to draw. Default: [app]'s ([GraineInApp.chat]).
  final GraineChatState? chat;

  /// The components to draw above the composer. Default: [app]'s.
  final GraineComponents? components;

  /// The agent this chat is with: its chat, components, session and design.
  /// Default: the agent [chat] belongs to, else the default agent
  /// ([GraineInApp.instance]).
  final GraineInApp? app;

  /// The design to draw. Default: the session's.
  final ResolvedDesign? design;

  /// "light", "dark" or "auto". Default: the design's, else the dashboard's theme.
  final String? scheme;

  /// #RRGGBB over the design's accent.
  final String? accent;

  /// The heading. Default: the dashboard's heading, else "Assistant".
  final String? name;

  /// The chevron in the header — usually a pop. Null: no chevron.
  final VoidCallback? onClose;

  /// Draw the components the agent shows.
  final bool showComponents;

  /// The whole screen.
  static const Key screenKey = ValueKey<String>('graine-chat-screen');

  /// OPEN THE CHAT, at [size] for this open — over the app's
  /// ([GraineConfig.chatSize]) and the dashboard's (Embed & Widgets →
  /// Appearance → Chat window → Window size). Completes when the chat window
  /// closes.
  ///
  ///     await GraineChat.open(context, size: GraineChatSize.full);
  ///
  /// With [app]'s [GraineAgentBar] on screen, the bar moves to the chat (where
  /// the agent offers one) and draws it at that size. With none, it opens on
  /// [context]'s navigator: `large` as a sheet over most of a phone (a panel
  /// in a tablet's corner), `full` as a screen of its own — and `compact`,
  /// which rides on the bar, as `large`.
  static Future<void> open(BuildContext context, {GraineInApp? app, GraineChatSize? size}) async {
    final agent = app ?? GraineInApp.maybeInstance;
    final inBar = openChatInBar(agent, size);
    if (inBar != null) return inBar;
    final tokens = tokensFor(context, app: agent);
    final media = MediaQuery.of(context);
    var chosen = ChatWindowLayout.size(open: size, config: agent?.config.chatSize, token: tokens?.chat.size);
    if (chosen == GraineChatSize.compact) chosen = GraineChatSize.large;
    final presentation = ChatWindowLayout.presentation(chosen, media.size.width, media.size.height);
    final motion = motionOf(context, tokens);
    final curve = curveOf(tokens);
    final navigator = Navigator.of(context);
    Widget slideUp(Animation<double> animation, Widget child) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: animation, curve: curve)),
          child: child,
        );

    if (presentation == ChatPresentation.screen) {
      return navigator.push<void>(PageRouteBuilder<void>(
        transitionDuration: motion,
        reverseTransitionDuration: motion,
        pageBuilder: (BuildContext route, Animation<double> _, Animation<double> __) => ChatFrameScope(
          leadingChevron: true,
          child: GraineChat(app: agent, onClose: () => Navigator.of(route).pop()),
        ),
        transitionsBuilder: (BuildContext _, Animation<double> animation, Animation<double> __, Widget child) =>
            slideUp(animation, child),
      ));
    }

    final look = tokens != null
        ? ChatLook.design(tokens)
        : ChatLook.appearance(
            dark: deviceDark(context),
            accent: colorOf(Appearance.defaultAccent)!,
            radius: 18,
            shadows: const <BoxShadow>[],
            accentHex: Appearance.defaultAccent,
          );
    final sheet = presentation == ChatPresentation.sheet;
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close the chat',
      // The app dimmed behind a sheet; a tablet's panel leaves it as it is.
      barrierColor: sheet
          ? fade(tokens != null ? tokenColor(tokens.colors.scrim) : const Color(0xFF000000), ChatWindowLayout.scrimOpacity)
          : const Color(0x00000000),
      transitionDuration: motion,
      pageBuilder: (BuildContext route, Animation<double> _, Animation<double> __) {
        void close() => Navigator.of(route).pop();
        final m = MediaQuery.of(route);
        final chat = MediaQuery.removePadding(
          context: route,
          removeTop: true,
          child: GraineChat(app: agent, onClose: close),
        );
        if (sheet) {
          final top = m.padding.top + ChatWindowLayout.sheetTop * m.size.height;
          return Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: m.size.height - top,
              child: ChatSheetFrame(
                look: look,
                onClose: close,
                motion: motion,
                shadows: tokens == null || tokens.elevation.hardOffset == null ? look.shadows : null,
                child: chat,
              ),
            ),
          );
        }
        final panel = ChatWindowLayout.panelSize(m.size.height);
        const inset = ChatWindowLayout.panelInset;
        return Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: EdgeInsets.only(right: inset + m.padding.right, bottom: inset + m.padding.bottom),
            child: Container(
              key: chatPanelKey,
              width: panel.width,
              height: panel.height,
              decoration: BoxDecoration(
                color: look.background,
                border: look.borderWidth > 0 ? Border.all(color: look.border, width: look.borderWidth) : null,
                borderRadius: BorderRadius.circular(look.xl),
                boxShadow: look.shadows,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(look.xl),
                child: MediaQuery.removePadding(context: route, removeBottom: true, child: chat),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (BuildContext _, Animation<double> animation, Animation<double> __, Widget child) =>
          sheet ? slideUp(animation, child) : FadeTransition(opacity: animation, child: child),
    );
  }

  @override
  State<GraineChat> createState() => _GraineChatState();
}

class _GraineChatState extends State<GraineChat> {
  /// The chat this screen shows.
  GraineChatConnection? _opened;

  /// The chat this screen has told it is on screen ([ChatWindows.shown]).
  GraineChatConnection? _told;

  /// The agent this screen talks to: the one it was handed, else the one its
  /// chat belongs to, else the default agent.
  GraineInApp? get _app {
    final chat = widget.chat;
    return widget.app ?? (chat is GraineChatSession ? chat.app : null) ?? GraineInApp.maybeInstance;
  }

  GraineChatState? get _chat => widget.chat ?? _app?.chat;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(GraineChat old) {
    super.didUpdateWidget(old);
    _sync();
  }

  /// Open the chat this screen shows (after the frame: opening notifies).
  void _sync() {
    final chat = _chat;
    GraineChatConnection? wanted;
    if (chat is GraineChatConnection) wanted = chat as GraineChatConnection;
    if (identical(wanted, _opened)) return;
    _opened = wanted;
    SchedulerBinding.instance.addPostFrameCallback((Duration _) {
      if (mounted) _tell(_opened);
    });
  }

  /// Tell the chats what this screen shows now: the one it showed has left
  /// it (the SDK's own is kept until it goes idle), the one it shows came.
  void _tell(GraineChatConnection? next) {
    if (identical(next, _told)) return;
    final before = _told;
    _told = next;
    if (before != null) ChatWindows.left(before);
    if (next != null) ChatWindows.shown(next);
  }

  @override
  void dispose() {
    _opened = null;
    _tell(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = _chat;
    if (chat == null) return const SizedBox.shrink();
    final app = _app;
    if (widget.design != null) app?.loadDesignFonts(widget.design);
    return ListenableBuilder(
      listenable: surfaceListenable(<Listenable?>[chat], app: app),
      builder: (BuildContext context, Widget? _) => _build(context, chat),
    );
  }

  Widget _build(BuildContext context, GraineChatState chat) {
    final app = _app;
    final appearance = app?.session?.appearance ?? const <String, Object?>{};
    final dash = Appearance.resolve(appearance,
        accent: Appearance.defaultAccent, heading: 'Assistant', origin: app?.config.baseUrl);
    final ownAccent = (widget.accent != null && Appearance.argb(widget.accent) != null) ? colorOf(widget.accent) : null;
    final tokens = tokensFor(context, design: widget.design, scheme: widget.scheme, app: app);
    final ChatLook look;
    if (tokens != null) {
      look = ChatLook.design(tokens, accent: ownAccent);
    } else {
      final theme = widget.scheme ?? Js.strOrEmpty(appearance['theme']);
      look = ChatLook.appearance(
        dark: Appearance.isDark(theme.isEmpty ? 'auto' : theme, deviceDark(context)),
        accent: ownAccent ?? colorOf(dash.accent) ?? colorOf(Appearance.defaultAccent)!,
        radius: dash.radius,
        shadows: const <BoxShadow>[],
        accentHex: ownAccent != null ? widget.accent : dash.accent,
      );
    }
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final components = widget.showComponents ? (widget.components ?? app?.components) : null;
    final typing = switch (chat) { GraineChatTyping(:final agentTyping) => agentTyping, _ => false };
    // The chat window v2's pieces, from the SDK's own chat. No call button here: with no voice bar
    // on screen there is nothing to carry a call started from this chat.
    final session = chat is GraineChatSession ? chat : null;
    final loader = Loaders.resolve(appearance['loader']);
    return DefaultTextStyle(
      style: textStyle(look.text, 14),
      child: ColoredBox(
        key: GraineChat.screenKey,
        color: look.background,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // The status bar, in the header's colour.
            if (media.padding.top > 0) Container(height: media.padding.top, color: look.header),
            Expanded(
              child: ChatWindow(
                look: look,
                heading: widget.name ?? dash.heading,
                messages: chat.messages,
                turns: chat is GraineChatSession ? chat.turns : null,
                marks: session == null ? const <String>{} : ChatWindows.marks(session),
                // After the agent ended the conversation the chat is idle, not connecting.
                online: chat.connected || ((session?.ended ?? false) && !(session?.connecting ?? false)),
                disconnected: session != null && ChatWindows.disconnected(session),
                typing: typing,
                onSend: chat.send,
                connectingText: loader.text.connecting,
                loader: loader,
                loaderColor: colorOf(loader.color) ?? look.accent,
                pin: session?.pinned,
                quickReplies: session?.quickReplies ?? const <GraineQuickReply>[],
                onQuickReply: session?.sendQuickReply,
                ended: session?.ended ?? false,
                rating: session?.rating,
                onRate: session == null ? null : (GraineChatRatingStyle style, int value) => session.rate(style, value),
                onAttach: session?.onAttach,
                reconnecting: session?.reconnecting ?? false,
                offline: session != null && !session.connected && !session.connecting,
                onRetry: session?.retry,
                onOpenLink: session == null ? null : (Uri uri) => session.onOpenLink?.call(uri),
                upcoming: chat is GraineChatSession ? chat.upcomingCalls : const <GraineScheduledCall>[],
                cancelStateOf: chat is GraineChatSession ? chat.cancelStateOf : null,
                onCancelUpcoming: chat is GraineChatSession ? (String id) => chat.cancelUpcoming(id) : null,
                // Booking from the chat: "Book a call" in the card, the SDK's sheet over the app.
                bookingAvailable: app?.bookingAvailable ?? false,
                onBook: app == null ? null : () => unawaited(GraineBooking.show(context, app: app)),
                // A refusal leaves the conversation as it was; nothing to say over it.
                onNewConversation: chat is GraineChatSession ? () => chat.newConversation().catchError((Object _) {}) : null,
                // The call's name, else the chat's title, else the heading (Booking.callName).
                callName: app?.session?.calls?.callName,
                onCollapse: widget.onClose,
                // A full screen of the chat's own (GraineChat.open) leads with its chevron.
                leadingChevron: ChatFrameScope.leads(context),
                logoUrl: dash.logoUrl,
                logoPlate: dash.logoPlate,
                origin: app?.config.baseUrl,
                fill: true,
                below: components == null
                    ? null
                    : GraineWidgetView(
                        components: components,
                        app: app,
                        accent: widget.accent,
                        scheme: widget.scheme,
                        appearance: appearance,
                        design: widget.design,
                        maxHeight: math.max(160, (media.size.height - keyboard) * 0.5),
                      ),
              ),
            ),
            // Clear of the keyboard, else of the home indicator.
            SizedBox(height: keyboard > 0 ? keyboard : media.padding.bottom),
          ],
        ),
      ),
    );
  }
}
