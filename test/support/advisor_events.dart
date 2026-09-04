import 'package:intermittent_fasting/models/advisor_event.dart';
import 'package:intermittent_fasting/models/advisor_reply.dart';

/// Turns an [AdvisorReply] into the event sequence the real transport emits.
///
/// Tests used to hand the presenter a finished reply, which the streaming
/// transport never does. Stubbing `Stream.value(AdvisorEvent.end(reply))`
/// instead would still pass while skipping delta accumulation entirely — so
/// the prose is deliberately split across several deltas here. A presenter that
/// renders only the terminal event, or drops everything but the last chunk,
/// fails against this helper the way it would fail against production.
Stream<AdvisorEvent> advisorStreamOf(AdvisorReply reply) async* {
  yield const AdvisorEvent.start();
  for (final chunk in _inChunks(reply.text)) {
    yield AdvisorEvent.delta(chunk);
  }
  yield AdvisorEvent.end(reply);
}

/// A stream that yields some prose and then dies without a terminal event —
/// the "cut off mid-answer" case.
Stream<AdvisorEvent> advisorStreamCutOff(String partial) async* {
  yield const AdvisorEvent.start();
  for (final chunk in _inChunks(partial)) {
    yield AdvisorEvent.delta(chunk);
  }
}

/// A stream that fails in-band after delivering some prose.
Stream<AdvisorEvent> advisorStreamErroring(String partial, String message) =>
    (() async* {
      yield const AdvisorEvent.start();
      for (final chunk in _inChunks(partial)) {
        yield AdvisorEvent.delta(chunk);
      }
      yield AdvisorEvent.error(message);
    })();

/// Splits text into a handful of pieces, mid-word where it lands that way.
Iterable<String> _inChunks(String text, {int pieces = 3}) {
  if (text.isEmpty) return const [];
  final size = (text.length / pieces).ceil();
  return [
    for (var i = 0; i < text.length; i += size)
      text.substring(i, (i + size).clamp(0, text.length)),
  ];
}
