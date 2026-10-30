/// Where the advisor sends its client events (Plan 065, phase 5): what the
/// user did with Nudgy's reply, tied to the message's trace id.
///
/// [record] is fire-and-forget. It returns at once, never throws, and never
/// waits on the network, so no event can slow down or break the chat.
///
/// Fields are counts and enum values only — never text. The server checks
/// every event against an allow-list and drops one that does not match; see
/// `_CLIENT_EVENTS` in `backend/ai-coach/lambda_function.py`.
abstract class AdvisorTelemetry {
  void record(
    String event, {
    String? traceId,
    Map<String, Object> fields = const {},
  });
}
