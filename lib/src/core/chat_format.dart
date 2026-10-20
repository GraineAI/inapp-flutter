/// THE AGENT'S WORDS, FORMATTED AND REVEALED (contract/DESIGN.md "Chat window
/// v2" → Bubbles) — the React Native SDK's chatMarkdown, chatMarkdownText,
/// revealLength and revealSlice (protocol.ts), ported literally and pinned
/// for every SDK by sdk/contract/chat-window.json → `markdown` and `reveal`.
///
/// SAFE FORMATTING — the little Markdown the agent's words may carry, and
/// nothing else: **bold** (or __bold__), *italic* (or _italic_), `code`,
/// [links](https://…) and bare https:// links, lines starting "- ", "* " or
/// "• " (a bullet) or "1. " / "1) " (a numbered item), a "# heading" (drawn as
/// a bold line), and line breaks. Never HTML: text stays text. A link is only
/// ever http(s), mailto or tel — anything else is its label alone. While a
/// reply is still arriving (`live`), a style whose closing mark has not come
/// yet already applies to the words after it, and a lone mark at the very end
/// is not drawn — so no asterisks flash on screen. Pure Dart.
library;

import 'dart:math' as math;

/// A run of words with one look.
class ChatSpan {
  const ChatSpan(this.text, {this.bold = false, this.italic = false, this.code = false, this.link});

  final String text;
  final bool bold;
  final bool italic;
  final bool code;

  /// The address a tap opens: http(s), mailto or tel only.
  final String? link;

  bool _sameLook(ChatSpan o) => o.bold == bold && o.italic == italic && o.code == code && o.link == link;

  /// The contract's shape: `{text, bold?, italic?, code?, link?}` — a flag only when set.
  Map<String, Object?> toJson() => <String, Object?>{
        'text': text,
        if (bold) 'bold': true,
        if (italic) 'italic': true,
        if (code) 'code': true,
        if (link != null) 'link': link,
      };

  @override
  String toString() => 'ChatSpan(${toJson()})';
}

/// What a block of the agent's words is.
enum ChatBlockKind { paragraph, bullet, number }

/// One block: a paragraph, a bullet, or a numbered item ([n]).
class ChatBlock {
  const ChatBlock(this.kind, this.spans, {this.n});

  final ChatBlockKind kind;
  final List<ChatSpan> spans;

  /// A numbered item's number.
  final int? n;

  /// The contract's shape: `{kind, n?, spans}`.
  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind.name,
        if (n != null) 'n': n,
        'spans': <Object?>[for (final s in spans) s.toJson()],
      };
}

abstract final class ChatMarkdown {
  static const String _escapable = r'\`*_[]()#+-.!>~|';
  static final RegExp _linkScheme = RegExp(r'^(https?:\/\/|mailto:|tel:)', caseSensitive: false);
  static const String _urlTail = '.,!?:;\'"';
  static final RegExp _space = RegExp(r'\s');
  static final RegExp _word = RegExp(r'[\p{L}\p{N}_]', unicode: true);
  static final RegExp _bareStart = RegExp(r'^https?:\/\/', caseSensitive: false);
  static final RegExp _bareHost = RegExp(r'^https?:\/\/[^/\s]+', caseSensitive: false);
  static final RegExp _bullet = RegExp(r'^ {0,3}[-*•][ \t]+(\S.*)$');
  static final RegExp _number = RegExp(r'^ {0,3}(\d{1,3})[.)][ \t]+(\S.*)$');
  static final RegExp _heading = RegExp(r'^ {0,3}#{1,6}[ \t]+(\S.*)$');
  static final RegExp _headingClose = RegExp(r'[ \t]+#+[ \t]*$');
  static final RegExp _liveTail = RegExp(r'[*_`[]+$');

  /// THE BLOCKS OF AN AGENT'S WORDS, formatted. Never throws; plain words are one paragraph.
  static List<ChatBlock> parse(String? text, {bool live = false}) {
    var source = (text ?? '').replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    // A lone mark at the very end of a reply still arriving is the start of something not yet here.
    if (live) source = source.replaceFirst(_liveTail, '');
    final blocks = <ChatBlock>[];
    var para = <String>[];
    void endPara() {
      if (para.isNotEmpty) {
        final spans = _merge(_inline(para.join('\n'), false, false, live));
        if (spans.isNotEmpty) blocks.add(ChatBlock(ChatBlockKind.paragraph, spans));
      }
      para = <String>[];
    }

    for (final line in source.split('\n')) {
      if (line.trim().isEmpty) {
        endPara();
        continue;
      }
      final bullet = _bullet.firstMatch(line);
      if (bullet != null) {
        endPara();
        final spans = _merge(_inline(bullet[1]!.trimRight(), false, false, live));
        if (spans.isNotEmpty) blocks.add(ChatBlock(ChatBlockKind.bullet, spans));
        continue;
      }
      final number = _number.firstMatch(line);
      if (number != null) {
        endPara();
        final spans = _merge(_inline(number[2]!.trimRight(), false, false, live));
        if (spans.isNotEmpty) blocks.add(ChatBlock(ChatBlockKind.number, spans, n: int.parse(number[1]!)));
        continue;
      }
      final heading = _heading.firstMatch(line);
      if (heading != null) {
        endPara();
        final spans = _merge(_inline(heading[1]!.replaceFirst(_headingClose, '').trimRight(), true, false, live));
        if (spans.isNotEmpty) blocks.add(ChatBlock(ChatBlockKind.paragraph, spans));
        continue;
      }
      para.add(line.trim());
    }
    endPara();
    return blocks;
  }

  /// THE PLAIN WORDS of formatted blocks — what a long-press copies and a
  /// screen reader reads: one line per block, bullets as "• ", items as "1. ".
  static String plain(List<ChatBlock> blocks) => blocks.map((ChatBlock b) {
        final words = b.spans.map((ChatSpan s) => s.text).join();
        return switch (b.kind) {
          ChatBlockKind.bullet => '• $words',
          ChatBlockKind.number => '${b.n}. $words',
          ChatBlockKind.paragraph => words,
        };
      }).join('\n');

  // ── inline ────────────────────────────────────────────────────────────────

  /// [text]'s code unit at [i] as a string, or null past either end — JavaScript's `text[i]`.
  static String? _at(String text, int i) => i < 0 || i >= text.length ? null : text[i];

  static bool _isSpace(String? c) => c == null || _space.hasMatch(c);
  static bool _isWord(String? c) => c != null && _word.hasMatch(c);

  /// `text.slice(a, b)` — clamped, as JavaScript's is.
  static String _slice(String text, int a, [int? b]) {
    final n = text.length;
    final s = a.clamp(0, n);
    final e = (b ?? n).clamp(s, n);
    return text.substring(s, e);
  }

  /// `text.indexOf(c, from)`, -1 when absent or [from] is past the end.
  static int _indexOf(String text, String c, int from) => from > text.length ? -1 : text.indexOf(c, from);

  static List<ChatSpan> _inline(String text, bool bold, bool italic, bool live) {
    final spans = <ChatSpan>[];
    var buf = StringBuffer();
    void flush() {
      if (buf.isNotEmpty) spans.add(ChatSpan(buf.toString(), bold: bold, italic: italic));
      buf = StringBuffer();
    }

    final n = text.length;
    var i = 0;
    while (i < n) {
      final c = text[i];
      // An escaped mark is the mark itself.
      if (c == r'\' && i + 1 < n && _escapable.contains(text[i + 1])) {
        buf.write(text[i + 1]);
        i += 2;
        continue;
      }
      // `code`, on one line, nothing styled inside it.
      if (c == '`') {
        final j = _indexOf(text, '`', i + 1);
        final int end;
        if (j > i + 1 && !_slice(text, i + 1, j).contains('\n')) {
          end = j;
        } else if (live && j < 0 && i + 1 < n && !_slice(text, i + 1).contains('\n')) {
          end = n;
        } else {
          end = -1;
        }
        if (end > 0) {
          flush();
          spans.add(ChatSpan(_slice(text, i + 1, end), bold: bold, italic: italic, code: true));
          i = end == n ? n : end + 1;
          continue;
        }
      }
      // [label](address)
      if (c == '[') {
        final close = _indexOf(text, ']', i + 1);
        if (close > i + 1 && _at(text, close + 1) == '(' && !_slice(text, i + 1, close).contains('\n')) {
          // The address runs to the bracket that closes it — (balanced) brackets inside it are its own.
          var end = -1;
          for (var j = close + 2, depth = 0; j < n && !_space.hasMatch(text[j]); j++) {
            if (text[j] == '(') {
              depth++;
            } else if (text[j] == ')') {
              if (depth == 0) {
                end = j;
                break;
              }
              depth--;
            }
          }
          final url = end > close + 2 ? _slice(text, close + 2, end) : '';
          if (url.isNotEmpty && !_space.hasMatch(url)) {
            flush();
            final label = _slice(text, i + 1, close);
            spans.add(ChatSpan(label, bold: bold, italic: italic, link: _linkScheme.hasMatch(url) ? url : null));
            i = end + 1;
            continue;
          }
        }
      }
      // A bare http(s) address.
      if ((c == 'h' || c == 'H') && !_isWord(_at(text, i - 1)) && _bareStart.hasMatch(_slice(text, i, i + 8))) {
        var j = i;
        while (j < n && !_space.hasMatch(text[j])) {
          j++;
        }
        var url = _slice(text, i, j);
        while (url.isNotEmpty &&
            (_urlTail.contains(url[url.length - 1]) || (url.endsWith(')') && !url.contains('(')))) {
          url = url.substring(0, url.length - 1);
        }
        if (_bareHost.hasMatch(url)) {
          flush();
          spans.add(ChatSpan(url, bold: bold, italic: italic, link: url));
          i += url.length;
          continue;
        }
      }
      // **bold** / __bold__
      if ((c == '*' || c == '_') && _at(text, i + 1) == c) {
        final mark = '$c$c';
        // Never inside a word (2**3, snake__case): a mark opens after a non-word and closes before one.
        final opens = !_isSpace(_at(text, i + 2)) && _at(text, i + 2) != c && !_isWord(_at(text, i - 1));
        if (opens) {
          var j = i + 2;
          var found = -1;
          while (j < n - 1) {
            if (text[j] == '\n') break;
            if (text[j] == c && text[j + 1] == c && !_isSpace(_at(text, j - 1)) && !_isWord(_at(text, j + 2))) {
              found = j;
              break;
            }
            j++;
          }
          final end = found >= 0 ? found : (live && !_slice(text, i + 2).contains('\n') ? n : -1);
          if (end > i + 2) {
            flush();
            spans.addAll(_inline(_slice(text, i + 2, end), true, italic, live && found < 0));
            i = end == n ? n : end + 2;
            continue;
          }
        }
        buf.write(mark);
        i += 2;
        continue;
      }
      // *italic* / _italic_
      if (c == '*' || c == '_') {
        final opens = !_isSpace(_at(text, i + 1)) && !_isWord(_at(text, i - 1));
        if (opens) {
          var j = i + 1;
          var found = -1;
          while (j < n) {
            if (text[j] == '\n') break;
            if (text[j] == c) {
              if (_at(text, j + 1) == c) {
                j += 2;
                continue;
              }
              if (!_isSpace(_at(text, j - 1)) && !_isWord(_at(text, j + 1))) {
                found = j;
                break;
              }
            }
            j++;
          }
          final end = found >= 0 ? found : (live && !_slice(text, i + 1).contains('\n') ? n : -1);
          if (end > i + 1) {
            flush();
            spans.addAll(_inline(_slice(text, i + 1, end), bold, true, live && found < 0));
            i = end == n ? n : end + 1;
            continue;
          }
        }
      }
      buf.write(c);
      i++;
    }
    flush();
    return spans;
  }

  /// Spans side by side with the same look are one span; empty ones go.
  static List<ChatSpan> _merge(List<ChatSpan> spans) {
    final out = <ChatSpan>[];
    for (final s in spans) {
      if (s.text.isEmpty) continue;
      if (out.isNotEmpty && out.last._sameLook(s)) {
        final last = out.removeLast();
        out.add(ChatSpan(last.text + s.text, bold: s.bold, italic: s.italic, code: s.code, link: s.link));
      } else {
        out.add(s);
      }
    }
    return out;
  }
}

/// A REPLY STILL ARRIVING, REVEALED SMOOTHLY rather than in the bursts the
/// network delivers it in: at least 90 characters a second, faster when
/// behind, never more than about 0.6 s behind what has arrived. Under the
/// OS's reduce-motion setting, or a design with no motion, it is drawn as it
/// arrives; a finished turn is drawn whole.
abstract final class ChatReveal {
  static const int minCps = 90;
  static const int catchUpMs = 600;

  /// How much of a streaming reply to show after [elapsedMs] more, from [shown] toward [target] characters.
  static int length(num shown, num target, num elapsedMs) {
    final goal = math.max(0, target.floor());
    final now = math.max(0, math.min(goal, shown.floor()));
    if (now >= goal || !(elapsedMs > 0)) return now;
    final cps = math.max(minCps.toDouble(), ((goal - now) * 1000) / catchUpMs);
    return math.min(goal, now + math.max(1, ((cps * elapsedMs) / 1000).floor()));
  }

  /// The first [length] UTF-16 units of [text], never splitting a surrogate pair (an emoji drawn half).
  static String slice(String text, num length) {
    var n = math.max(0, math.min(text.length, length.floor()));
    if (n > 0 && n < text.length) {
      final c = text.codeUnitAt(n - 1);
      if (c >= 0xd800 && c <= 0xdbff) n += 1;
    }
    return text.substring(0, n);
  }
}
