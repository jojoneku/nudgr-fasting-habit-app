/// Mood tint for the Hub coaching line, reflecting the current state.
enum HubCoachMood { neutral, urgent, positive }

/// Pure resolver for the coaching-line mood. `urgent` wins (something needs
/// attention), then `positive` (goals met), else `neutral`. Kept out of
/// `build()` per System Rule 1.
HubCoachMood resolveHubCoachMood({
  required bool overGoal,
  required bool billImminent,
  required bool goalsMet,
}) {
  if (overGoal || billImminent) return HubCoachMood.urgent;
  if (goalsMet) return HubCoachMood.positive;
  return HubCoachMood.neutral;
}
