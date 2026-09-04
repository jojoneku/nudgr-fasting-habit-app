import 'dart:convert';

import '../models/advisor_event.dart';

/// The advisor stream was not well-formed.
///
/// Separate from `AiCoachException` so this file stays free of service
/// dependencies; the service maps it to the message the user reads.
class AdvisorFrameException implements Exception {
  const AdvisorFrameException(this.reason);

  /// One of [unreadableFrame] or [noTerminator]. Distinguished because they
  /// mean different things: the first is a protocol disagreement, the second is
  /// a turn that died in flight with real text already on screen.
  final AdvisorFrameFailure reason;

  @override
  String toString() => 'AdvisorFrameException($reason)';
}

enum AdvisorFrameFailure {
  /// A line arrived that was not JSON.
  unreadableFrame,

  /// The stream ended without `end` or `error`.
  noTerminator,
}

/// Parses an NDJSON advisor stream into [AdvisorEvent]s.
///
/// Framing is the whole job here, and it is easy to get subtly wrong. A network
/// chunk splits wherever the network feels like it: mid-object, immediately
/// after a newline, or halfway through a multi-byte character. So bytes are
/// decoded through [utf8.decoder] — which holds a partial code point back until
/// it completes, rather than emitting a replacement character — and a line is
/// only parsed once its terminating newline has actually arrived.
///
/// Ends after the first terminal frame, ignoring anything that follows it, and
/// throws [AdvisorFrameException] when the stream ends without one. That last
/// case must never be mistaken for a short answer: the accumulated text is
/// real, but the turn is not finished, and reporting it as finished is how half
/// a reply gets presented as the whole reply.
Stream<AdvisorEvent> parseAdvisorFrames(Stream<List<int>> bytes) async* {
  var buffer = '';
  var sawTerminal = false;

  await for (final chunk in bytes.transform(utf8.decoder)) {
    buffer += chunk;
    while (true) {
      final newline = buffer.indexOf('\n');
      if (newline < 0) break;
      final line = buffer.substring(0, newline).trim();
      buffer = buffer.substring(newline + 1);
      if (line.isEmpty) continue;

      final AdvisorEvent event;
      try {
        event = AdvisorEvent.fromJson(jsonDecode(line) as Map<String, Object?>);
      } catch (_) {
        throw const AdvisorFrameException(AdvisorFrameFailure.unreadableFrame);
      }
      yield event;
      if (event.isTerminal) {
        sawTerminal = true;
        return;
      }
    }
  }

  // A trailing frame with no newline after it. The server always terminates
  // frames, so this only happens if the connection was cut mid-frame — but
  // parsing what is there beats discarding a complete terminator over a
  // missing byte.
  final rest = buffer.trim();
  if (!sawTerminal && rest.isNotEmpty) {
    try {
      final event =
          AdvisorEvent.fromJson(jsonDecode(rest) as Map<String, Object?>);
      yield event;
      if (event.isTerminal) return;
    } catch (_) {
      // Fall through: an unparseable tail is a cut-off stream, which the
      // no-terminator failure below describes more accurately.
    }
  }

  throw const AdvisorFrameException(AdvisorFrameFailure.noTerminator);
}
