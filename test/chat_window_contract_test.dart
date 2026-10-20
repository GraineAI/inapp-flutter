// CHAT WINDOW v2, THE SHARED RULES (contract/DESIGN.md "Chat window v2" →
// Wire): sdk/contract/chat-window.json, generated from the React Native SDK's
// code — the agent's quick replies read from their frame, the rating and the
// quiet frame it is sent as, the rating card's width and its choices' size in
// a thread of any width, groups and whose time is drawn, the safe formatting
// and its plain words, and the smooth reveal. Every answer is reproduced here
// exactly (the rating card's numbers within 1e-6). The `fold` section runs
// against the real chat session in test/chat_window_v2_test.dart. A missing
// file FAILS. Imports ONLY lib/src/core.
import 'dart:convert';

import 'package:graine_inapp/src/core/core.dart';
import 'package:test/test.dart';

import 'contract_files.dart';

/// JSON and Dart values in one comparable shape: every number a double.
Object? canon(Object? v) {
  if (v is num) return v.toDouble();
  if (v is Map) return <String, Object?>{for (final e in v.entries) e.key.toString(): canon(e.value)};
  if (v is List) return <Object?>[for (final x in v) canon(x)];
  return v;
}

void main() {
  late Map<String, Object?> fx;
  setUpAll(() async => fx = await contractJson('contract/chat-window.json'));

  List<Map<String, Object?>> section(String name) {
    final list = (fx[name]! as List<Object?>).cast<Map<String, Object?>>();
    expect(list, isNotEmpty, reason: 'section $name is empty');
    return list;
  }

  test('every section is covered — a new one fails here until this suite checks it', () {
    const covered = <String>{
      'generatedBy', 'comment', 'limits', 'ratingEvent', 'ratingLabels', 'ratingEmoji', 'ratingThanks', 'quickReplies',
      'fold', 'rating', 'groups', 'markdown', 'reveal', 'ratingChoices', 'ratingLayout',
    };
    expect(fx.keys.toSet().difference(covered), isEmpty, reason: 'a section this suite does not check');
  });

  test('the same limits, labels, faces and words', () {
    final limits = fx['limits']! as Map<String, Object?>;
    expect(QuickReplies.max, limits['quickReplies']);
    expect(QuickReplies.labelMax, limits['quickReplyLabel']);
    expect(QuickReplies.textMax, limits['quickReplyText']);
    expect(ChatGroups.gapMs, limits['groupGapMs']);
    expect(ChatReveal.minCps, limits['revealMinCps']);
    expect(ChatReveal.catchUpMs, limits['revealCatchUpMs']);
    expect(ChatRatings.maxWidth, limits['ratingMaxWidth']);
    expect(ChatRatings.share, limits['ratingShare']);
    expect(ChatRatings.gap, limits['ratingGap']);
    expect(ChatRatings.event, fx['ratingEvent']);
    expect(<String, Object?>{for (final e in ChatRatings.labels.entries) e.key.wire: e.value}, fx['ratingLabels']);
    expect(ChatRatings.emoji, fx['ratingEmoji']);
    expect(ChatRatings.thanks, fx['ratingThanks']);
  });

  test('quickReplies: read from their frame exactly as the React Native SDK reads them', () {
    for (final c in section('quickReplies')) {
      final got = QuickReplies.read(c['frame']);
      final want = c['replies'];
      if (want == null) {
        expect(got, isNull, reason: '${c['name']}: the frame is ignored');
        continue;
      }
      expect(<Object?>[for (final r in got!) r.toJson()], want, reason: '${c['name']}');
    }
  });

  test('quickReplies arrive as a frame on the chat socket; one that is not one is no frame', () {
    for (final c in section('quickReplies')) {
      final frame = c['frame'];
      if (frame is! Map) continue;
      final parsed = ChatFrame.parse(jsonEncode(frame));
      if (c['replies'] == null) {
        expect(parsed, isNull, reason: '${c['name']}');
      } else {
        expect(parsed, isA<ChatQuickReplies>(), reason: '${c['name']}');
        expect(<Object?>[for (final r in (parsed! as ChatQuickReplies).replies) r.toJson()], c['replies']);
      }
    }
    expect(ChatFrame.parse('{"type":"conversation_end"}'), isA<ChatConversationEnd>());
  });

  test('rating: the same rating, and the same quiet frame, for every choice', () {
    for (final c in section('rating')) {
      final input = c['input']! as Map<String, Object?>;
      final rating = ChatRatings.of(input['style'], input['value']);
      expect(canon(rating.toJson()), canon(c['rating']), reason: '$input');
      expect(canon(ChatRatings.frame(rating)), canon(c['frame']), reason: '$input');
    }
  });

  test('the rating card: the same width and the same choices in a thread of every width', () {
    expect(
      canon(<String, Object?>{
        for (final e in ChatRatings.choices.entries)
          e.key.wire: <String, Object?>{'count': e.value.count, 'size': e.value.size, 'glyph': e.value.glyph},
      }),
      canon(fx['ratingChoices']),
    );
    final cases = section('ratingLayout');
    expect(cases.length, greaterThanOrEqualTo(12));
    for (final c in cases) {
      final got = ChatRatings.layout(c['style'], c['thread']! as num, c['padding']! as num);
      final name = '${c['style']} in ${c['thread']} with ${c['padding']}';
      for (final (String key, double value) in <(String, double)>[
        ('width', got.width),
        ('size', got.size),
        ('glyph', got.glyph),
        ('gap', got.gap),
      ]) {
        expect(value, closeTo((c[key]! as num).toDouble(), 1e-6), reason: '$name: $key');
      }
      expect(got.count, c['count'], reason: '$name: count');
      // Never wider than the thread or 300; the choices inside the padding wherever the thread has room for them.
      final thread = (c['thread']! as num).toDouble();
      final padding = (c['padding']! as num).toDouble();
      expect(got.width, lessThanOrEqualTo(thread < 300 ? thread : 300), reason: name);
      if (thread > 2 * padding + 100) {
        expect(got.count * got.size + (got.count - 1) * got.gap, lessThanOrEqualTo(got.width - 2 * padding + 1e-9), reason: name);
      }
    }
    // A wide thread draws v1's numbers exactly: min(300, 84%), the choices at full size.
    expect(ChatRatings.layout('emoji', 500, 14), const ChatRatingLayout(width: 300, count: 5, size: 44, glyph: 24, gap: 8));
    expect(ChatRatings.layout('thumbs', 300, 14), const ChatRatingLayout(width: 252, count: 2, size: 44, glyph: 22, gap: 8));
    // A style this build does not know is thumbs; a width that is not a number is 0.
    for (final Object? odd in <Object?>['hearts', '', null, 3]) {
      expect(ChatRatings.layout(odd, 327, 14), ChatRatings.layout('thumbs', 327, 14), reason: '$odd');
      expect(ChatRatings.layout(odd, 100, 14), ChatRatings.layout(GraineChatRatingStyle.thumbs, 100, 14), reason: '$odd');
    }
    expect(ChatRatings.layout('emoji', double.nan, 14), ChatRatings.layout('emoji', 0, 14));
    expect(ChatRatings.layout('emoji', double.infinity, 14), ChatRatings.layout('emoji', 0, 14));
    expect(ChatRatings.layout('stars', 240, double.nan), ChatRatings.layout('stars', 240, 0));
    expect(ChatRatings.layout('stars', 240, -5), ChatRatings.layout('stars', 240, 0));
  });

  test('groups: the same positions, and the same times drawn for never, group and always', () {
    for (final c in section('groups')) {
      final items = <ChatGroupItem>[
        for (final raw in (c['items']! as List<Object?>).cast<Map<String, Object?>>())
          ChatGroupItem(role: raw['role'] as String?, at: raw['at'] as num?, breaks: raw['breaks'] == true),
      ];
      final positions = ChatGroups.positions(items);
      expect(<String>[for (final p in positions) p.name], c['positions'], reason: '${c['name']}');
      final times = c['times']! as Map<String, Object?>;
      for (final show in times.keys) {
        expect(<bool>[for (final p in positions) ChatGroups.showsTime(show, p)], times[show], reason: '${c['name']} · $show');
      }
    }
  });

  test('markdown: the same blocks and the same plain words, still arriving or whole', () {
    for (final c in section('markdown')) {
      final text = c['text']! as String;
      final blocks = ChatMarkdown.parse(text, live: c['live'] == true);
      expect(canon(<Object?>[for (final b in blocks) b.toJson()]), canon(c['blocks']), reason: '"$text"${c['live'] == true ? ' (live)' : ''}');
      expect(ChatMarkdown.plain(blocks), c['plain'], reason: '"$text"');
    }
  });

  test('reveal: the same length after the same wait', () {
    for (final c in section('reveal')) {
      expect(ChatReveal.length(c['shown']! as num, c['target']! as num, c['elapsedMs']! as num), c['length'], reason: '$c');
    }
    expect(ChatReveal.slice('Hi 👍 there', 4), 'Hi 👍', reason: 'never half an emoji');
    expect(ChatReveal.slice('Hello', 99), 'Hello');
    expect(ChatReveal.slice('Hello', -3), '');
  });

  test('the fold section names only the steps the session suite drives', () {
    const known = <String>{'frame', 'send', 'drop', 'rate', 'clear'};
    for (final c in section('fold')) {
      for (final step in (c['steps']! as List<Object?>).cast<Map<String, Object?>>()) {
        expect(known.containsAll(step.keys), isTrue, reason: '${c['name']}: $step');
      }
    }
  });

  test('the pin: one line each, at most its characters, a picture only over http(s)', () {
    final pin = const GraineChatPin(
      title: '  A very long title that runs on and on past the sixty characters a pin may draw  ',
      subtitle: 'Line one\nline two',
      imageUrl: 'javascript:alert(1)',
      badge: '',
    ).cleaned!;
    expect(pin.title.runes.length, lessThanOrEqualTo(GraineChatPin.titleMax));
    expect(pin.subtitle, 'Line one line two');
    expect(pin.imageUrl, isNull);
    expect(pin.badge, isNull);
    expect(const GraineChatPin(title: '   ').cleaned, isNull, reason: 'nothing to draw');
    expect(const GraineChatPin(title: 'Case 42', subtitle: 'Opened today', badge: 'Open').spoken, 'Pinned: Case 42, Opened today, Open');
    expect(const GraineChatPin(title: 'x', imageUrl: 'https://example.com/a.png').cleaned!.imageUrl, 'https://example.com/a.png');
  });
}
