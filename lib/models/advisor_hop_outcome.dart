import '../services/ai_coach_service.dart';
import 'advisor_reply.dart';

/// What came of one attempt at an advisor hop.
///
/// A hop used to answer with `AdvisorReply?` and settle the UI itself on the
/// way out. That stopped working once attempts could be retried: an attempt
/// that has already written an error to the screen cannot be retried
/// invisibly, and a null tells the caller nothing about whether trying again
/// is worth it.
///
/// So an attempt reports three things and decides nothing: what it got, why it
/// failed, and how much prose arrived before it did.
class AdvisorHopOutcome {
  /// The hop finished and produced a turn.
  const AdvisorHopOutcome.done(AdvisorReply this.reply)
      : partial = '',
        failure = null;

  /// The hop failed. [partial] is the prose that arrived first, which the
  /// caller keeps on screen rather than discarding.
  const AdvisorHopOutcome.failed(this.partial, AiCoachException this.failure)
      : reply = null;

  /// The sheet went away mid-attempt. Not a failure — there is nobody left to
  /// tell, and retrying would update a presenter that is on its way out.
  const AdvisorHopOutcome.abandoned()
      : reply = null,
        failure = null,
        partial = '';

  /// The finished turn, when there is one.
  final AdvisorReply? reply;

  /// Why the attempt failed, when it did. Carries the retryability the caller
  /// needs in order to decide whether to try again.
  final AiCoachException? failure;

  /// Prose delivered before the failure.
  final String partial;

  /// True when the sheet was dismissed mid-attempt.
  bool get wasAbandoned => reply == null && failure == null;
}
