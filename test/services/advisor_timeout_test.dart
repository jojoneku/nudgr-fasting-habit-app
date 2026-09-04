import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/services/cloud_ai_coach_service.dart';

/// The advisor's transport timeout is coupled to infrastructure the app cannot
/// see, so the coupling is asserted here rather than left to a comment.
void main() {
  test('the advisor waits longer than the short ops', () {
    // The short ops sit at 30s. Collapsing the advisor back onto that constant
    // is the regression this guards: the advisor generates far more tokens and
    // would start timing out on long answers that the backend delivered fine.
    expect(CloudAiCoachService.advisorTimeoutSeconds, greaterThan(30));
  });

  test('the advisor waits longer than any gateway timeout worth setting', () {
    // It must exceed the API Gateway integration timeout. If the client gives
    // up first, the user sees a connection error while the backend is still
    // working, and the gateway's own 504 never arrives to explain what failed.
    // 120s leaves room above a gateway raised well past its 30s default; drop
    // below that only alongside a matching gateway reduction.
    expect(
        CloudAiCoachService.advisorTimeoutSeconds, greaterThanOrEqualTo(120));
  });
}
