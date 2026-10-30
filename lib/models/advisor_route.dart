/// Which model a Nudgy conversation runs on (Plan 065, phase 5).
///
/// Decided once, when the conversation's first advisor message is sent, and
/// sent as `route` on every request of that conversation. The Lambda reads it
/// only while its `ADVISOR_HAIKU_ROUTING` flag is on; with the flag off every
/// request runs on the advisor model, whatever the route says.
enum AdvisorRoute {
  /// Lookup-only conversations: the cheaper routing model (Haiku).
  haiku,

  /// Everything else: the advisor model (Sonnet).
  sonnet;

  /// The value sent to the Lambda and stored with the conversation.
  String get wireName => name;

  /// Null for a missing or unknown value.
  static AdvisorRoute? fromWire(Object? value) {
    for (final r in values) {
      if (r.wireName == value) return r;
    }
    return null;
  }
}
