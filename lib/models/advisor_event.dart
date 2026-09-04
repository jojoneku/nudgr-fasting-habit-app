import 'advisor_reply.dart';

/// What kind of frame arrived on the advisor stream.
enum AdvisorEventKind {
  /// The stream is established and the model is working. Distinct from "still
  /// connecting", which is what lets the UI retire the spinner at the right
  /// moment rather than on first byte of anything.
  start,

  /// A run of text to append. Many per turn.
  delta,

  /// The turn finished. Carries the structured tail in [reply].
  end,

  /// The turn failed after the response had already begun.
  ///
  /// This exists because a status code cannot say it. Once the 200 and its
  /// headers are on the wire they cannot be taken back, so a failure at token
  /// 400 has to be reported in-band or not at all.
  error,
}

/// One frame of a streamed advisor turn.
///
/// The advisor used to be a single blocking call whose whole reply arrived at
/// once. It could not stay that way: the reply is generated over tens of
/// seconds, and the gateway it sat behind refused to wait more than 30 of them,
/// so a long answer was discarded after being written and billed in full.
///
/// A well-formed turn is [start], zero or more [delta], then exactly one of
/// [end] or [error]. A stream that stops without one of those two is a failure
/// the server did not survive — see [isTerminal]. Treating an
/// unterminated stream as a finished short answer is the one failure mode worth
/// naming twice, because it silently presents half an answer as the whole one.
class AdvisorEvent {
  const AdvisorEvent._(this.kind, {this.text = '', this.reply, this.message});

  const AdvisorEvent.start() : this._(AdvisorEventKind.start);

  const AdvisorEvent.delta(String text)
      : this._(AdvisorEventKind.delta, text: text);

  const AdvisorEvent.end(AdvisorReply reply)
      : this._(AdvisorEventKind.end, reply: reply);

  const AdvisorEvent.error(String message)
      : this._(AdvisorEventKind.error, message: message);

  final AdvisorEventKind kind;

  /// Text to append. Only meaningful on [AdvisorEventKind.delta].
  final String text;

  /// The finished turn. Only present on [AdvisorEventKind.end].
  ///
  /// Deliberately the same [AdvisorReply] the buffered path returns, so the
  /// tool loop's `wantsTools` / `assistantContent` contract is unchanged and
  /// one `fromJson` parses both transports.
  final AdvisorReply? reply;

  /// Why the turn failed. Only present on [AdvisorEventKind.error].
  final String? message;

  /// True for the two frames that legitimately end a turn.
  bool get isTerminal =>
      kind == AdvisorEventKind.end || kind == AdvisorEventKind.error;

  /// Parses one NDJSON frame.
  ///
  /// An unrecognised `type` is reported as an error rather than ignored: a
  /// frame this build does not understand means client and server disagree
  /// about the protocol, and carrying on would produce a reply that silently
  /// omits whatever the new frame carried.
  factory AdvisorEvent.fromJson(Map<String, Object?> json) {
    switch (json['type']) {
      case 'start':
        return const AdvisorEvent.start();
      case 'delta':
        return AdvisorEvent.delta((json['text'] as String?) ?? '');
      case 'end':
        return AdvisorEvent.end(AdvisorReply.fromJson(json));
      case 'error':
        return AdvisorEvent.error((json['message'] as String?) ??
            'The advisor stopped partway through. Try again.');
      default:
        return const AdvisorEvent.error(
            'The advisor sent a frame this app does not understand.');
    }
  }
}
