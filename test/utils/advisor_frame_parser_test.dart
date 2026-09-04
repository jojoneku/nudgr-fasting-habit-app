import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/advisor_event.dart';
import 'package:intermittent_fasting/utils/advisor_frame_parser.dart';

/// Chunk-boundary handling for the advisor stream.
///
/// The network splits a response wherever it likes, so every test here feeds
/// the SAME bytes in a different, deliberately awkward shape and asserts the
/// result does not change. A parser that passes only the tidy case works right
/// up until production traffic, which is the point of the split-by-byte cases.
void main() {
  const frames = '{"type":"start"}\n'
      '{"type":"delta","text":"You are at "}\n'
      '{"type":"delta","text":"4,120 of 6,000."}\n'
      '{"type":"end","response":"You are at 4,120 of 6,000.",'
      '"truncated":false,"tool_calls":[],"assistant_content":[]}\n';

  Stream<List<int>> chunked(String text, {required int size}) async* {
    final bytes = utf8.encode(text);
    for (var i = 0; i < bytes.length; i += size) {
      yield bytes.sublist(i, (i + size).clamp(0, bytes.length));
    }
  }

  Future<List<AdvisorEvent>> collect(Stream<List<int>> bytes) =>
      parseAdvisorFrames(bytes).toList();

  String textOf(List<AdvisorEvent> events) => events
      .where((e) => e.kind == AdvisorEventKind.delta)
      .map((e) => e.text)
      .join();

  group('framing is independent of how the bytes arrive', () {
    test('one chunk per frame', () async {
      final events = await collect(Stream.fromIterable(frames
          .split('\n')
          .where((l) => l.isNotEmpty)
          .map((l) => utf8.encode('$l\n'))));
      expect(events.map((e) => e.kind), [
        AdvisorEventKind.start,
        AdvisorEventKind.delta,
        AdvisorEventKind.delta,
        AdvisorEventKind.end,
      ]);
      expect(textOf(events), 'You are at 4,120 of 6,000.');
    });

    test('the whole response in one chunk', () async {
      final events = await collect(Stream.value(utf8.encode(frames)));
      expect(events.last.kind, AdvisorEventKind.end);
      expect(textOf(events), 'You are at 4,120 of 6,000.');
    });

    test('one byte at a time — every boundary is a split', () async {
      final events = await collect(chunked(frames, size: 1));
      expect(events.last.kind, AdvisorEventKind.end);
      expect(textOf(events), 'You are at 4,120 of 6,000.');
      expect(events.last.reply!.text, 'You are at 4,120 of 6,000.');
    });

    test('awkward chunk sizes all agree', () async {
      for (final size in [2, 3, 7, 13, 31, 64, 127]) {
        final events = await collect(chunked(frames, size: size));
        expect(textOf(events), 'You are at 4,120 of 6,000.',
            reason: 'chunk size $size');
        expect(events.last.kind, AdvisorEventKind.end,
            reason: 'chunk size $size');
      }
    });

    test('a split immediately after a newline', () async {
      final cut = frames.indexOf('\n') + 1;
      final events = await collect(Stream.fromIterable([
        utf8.encode(frames.substring(0, cut)),
        utf8.encode(frames.substring(cut)),
      ]));
      expect(events.first.kind, AdvisorEventKind.start);
      expect(events.last.kind, AdvisorEventKind.end);
    });

    test('a blank line between frames is skipped', () async {
      final events = await collect(Stream.value(
          utf8.encode('{"type":"start"}\n\n{"type":"end","response":"ok"}\n')));
      expect(events.map((e) => e.kind),
          [AdvisorEventKind.start, AdvisorEventKind.end]);
    });
  });

  group('multi-byte characters survive a split mid-character', () {
    // The peso sign and an em dash are three bytes each in UTF-8; the advisor
    // emits both constantly. Splitting inside one and decoding naively yields a
    // replacement character, so the user would read a corrupted figure.
    const money = '{"type":"start"}\n'
        '{"type":"delta","text":"₱40,000 — that is the DP"}\n'
        '{"type":"end","response":"₱40,000 — that is the DP"}\n';

    test('one byte at a time', () async {
      final events = await collect(chunked(money, size: 1));
      expect(textOf(events), '₱40,000 — that is the DP');
      expect(textOf(events), isNot(contains('�')));
    });

    test('split exactly inside the peso sign', () async {
      final bytes = utf8.encode(money);
      final pesoAt = bytes.indexOf(0xE2); // first byte of ₱ (E2 82 B1)
      expect(pesoAt, greaterThan(0));
      final events = await collect(Stream.fromIterable([
        bytes.sublist(0, pesoAt + 1), // cuts the character in half
        bytes.sublist(pesoAt + 1),
      ]));
      expect(textOf(events), '₱40,000 — that is the DP');
      expect(textOf(events), isNot(contains('�')));
    });

    test('emoji (a surrogate pair) survives too', () async {
      const withEmoji = '{"type":"start"}\n'
          '{"type":"delta","text":"nice work 🎉"}\n'
          '{"type":"end","response":"nice work 🎉"}\n';
      final events = await collect(chunked(withEmoji, size: 1));
      expect(textOf(events), 'nice work 🎉');
    });
  });

  group('a stream without a terminator is a failure, not a short answer', () {
    test('deltas then silence throws noTerminator', () async {
      expect(
        () => collect(Stream.value(utf8.encode('{"type":"start"}\n'
            '{"type":"delta","text":"half an answ"}\n'))),
        throwsA(isA<AdvisorFrameException>().having(
            (e) => e.reason, 'reason', AdvisorFrameFailure.noTerminator)),
      );
    });

    test('an empty stream throws noTerminator', () async {
      expect(
        () => collect(const Stream<List<int>>.empty()),
        throwsA(isA<AdvisorFrameException>().having(
            (e) => e.reason, 'reason', AdvisorFrameFailure.noTerminator)),
      );
    });

    test('a terminator missing only its trailing newline still counts',
        () async {
      // Losing a whole turn over one absent byte would be its own bug.
      final events = await collect(Stream.value(
          utf8.encode('{"type":"start"}\n{"type":"end","response":"done"}')));
      expect(events.last.kind, AdvisorEventKind.end);
      expect(events.last.reply!.text, 'done');
    });

    test('a truncated final frame throws rather than half-parsing', () async {
      expect(
        () => collect(Stream.value(
            utf8.encode('{"type":"start"}\n{"type":"end","respo'))),
        throwsA(isA<AdvisorFrameException>().having(
            (e) => e.reason, 'reason', AdvisorFrameFailure.noTerminator)),
      );
    });
  });

  group('malformed frames', () {
    test('a non-JSON line throws unreadableFrame', () async {
      expect(
        () => collect(Stream.value(
            utf8.encode('{"type":"start"}\n<html>502 Bad Gateway</html>\n'))),
        throwsA(isA<AdvisorFrameException>().having(
            (e) => e.reason, 'reason', AdvisorFrameFailure.unreadableFrame)),
      );
    });

    test('an error frame terminates the turn cleanly', () async {
      final events = await collect(Stream.value(
          utf8.encode('{"type":"start"}\n{"type":"delta","text":"partial"}\n'
              '{"type":"error","message":"Bedrock fell over."}\n')));
      expect(events.last.kind, AdvisorEventKind.error);
      expect(events.last.message, 'Bedrock fell over.');
      // The text that did arrive is still delivered, so the caller can keep it.
      expect(textOf(events), 'partial');
    });

    test('frames after the terminator are ignored', () async {
      final events = await collect(Stream.value(
          utf8.encode('{"type":"start"}\n{"type":"end","response":"done"}\n'
              '{"type":"delta","text":"should never be read"}\n')));
      expect(events, hasLength(2));
      expect(events.last.kind, AdvisorEventKind.end);
    });
  });
}
