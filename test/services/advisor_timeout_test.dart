import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/services/cloud_ai_coach_service.dart';

/// The advisor's transport timeout is coupled to infrastructure the app cannot
/// see, so the coupling is asserted here rather than left to a comment.
///
/// What it is coupled TO changed. This used to be about outlasting the API
/// Gateway integration timeout, on the theory that the gateway would raise its
/// 30s ceiling one day. It cannot: an HTTP API's maximum integration timeout is
/// 30 seconds and AWS lists it as not increasable, which is why the advisor
/// moved to a streaming Function URL with no gateway in front of it at all.
///
/// So the number the client must now outlast is the FUNCTION's own budget —
/// currently 45s on `food-coach-handler`. A streamed turn is allowed to run to
/// that budget, and if the client gave up first the user would see a connection
/// error while the backend was still writing them an answer.
void main() {
  test('the advisor waits longer than the short ops', () {
    // The short ops sit at 30s. Collapsing the advisor back onto that constant
    // is the regression this guards: the advisor generates far more tokens and
    // would start timing out on long answers the backend delivered fine.
    expect(CloudAiCoachService.advisorTimeoutSeconds, greaterThan(30));
  });

  test('the advisor outlasts the function budget it is waiting on', () {
    // Must exceed the Lambda timeout (45s), with room to spare: the timeout
    // applies per-chunk on the streamed path, but the buffered fallback still
    // waits for a whole reply, and that path is bounded by the function.
    //
    // 120s leaves headroom for a function budget raised toward the 15-minute
    // ceiling streaming permits. Drop below that only alongside a matching
    // reduction in the function's own timeout.
    expect(
        CloudAiCoachService.advisorTimeoutSeconds, greaterThanOrEqualTo(120));
  });
}
