/// Which metric a Hub hero ring slot displays.
enum HubHeroSlot { fast, food, move, macros, finance }

/// Default hero configuration (fasting users).
const List<HubHeroSlot> kDefaultHeroSlots = [
  HubHeroSlot.fast,
  HubHeroSlot.food,
  HubHeroSlot.move,
];

/// Hero configuration for users who do not fast — slot 1 shows the macro-split
/// ring instead of the Fast countdown.
const List<HubHeroSlot> kNonFasterHeroSlots = [
  HubHeroSlot.macros,
  HubHeroSlot.food,
  HubHeroSlot.move,
];

/// Resolves the three hero slots. An explicit user configuration wins;
/// otherwise slot 1 defaults to the macro-split ring for non-fasters,
/// and food adapts to finance if food logging is inactive while treasury is used.
List<HubHeroSlot> resolveHeroSlots({
  required List<HubHeroSlot>? configured,
  required bool hasEverFasted,
  bool hasFoodLogs = true,
  bool hasTreasury = false,
}) {
  if (configured != null && configured.length == 3) return configured;
  if (!hasFoodLogs && hasTreasury) {
    return hasEverFasted
        ? const [HubHeroSlot.fast, HubHeroSlot.finance, HubHeroSlot.move]
        : const [HubHeroSlot.macros, HubHeroSlot.finance, HubHeroSlot.move];
  }
  return hasEverFasted ? kDefaultHeroSlots : kNonFasterHeroSlots;
}

/// Parses an enum name back to a [HubHeroSlot], or null if unrecognised.
HubHeroSlot? heroSlotFromName(String name) {
  for (final s in HubHeroSlot.values) {
    if (s.name == name) return s;
  }
  return null;
}
