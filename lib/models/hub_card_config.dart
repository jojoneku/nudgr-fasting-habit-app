enum HubCardVisibility {
  /// Adapts based on activity (e.g. compact when dormant, expanded when active).
  auto,

  /// Always fully expanded.
  expanded,

  /// Always a 1-row compact glance summary.
  compact,

  /// Hidden from the Hub (accessible via navigation / bottom bar).
  hidden;

  static HubCardVisibility fromString(String? name) {
    if (name == null) return HubCardVisibility.auto;
    return HubCardVisibility.values.firstWhere(
      (v) => v.name == name,
      orElse: () => HubCardVisibility.auto,
    );
  }
}

class HubCardConfig {
  final HubCardVisibility visibility;

  const HubCardConfig({
    this.visibility = HubCardVisibility.auto,
  });

  Map<String, dynamic> toJson() => {
        'visibility': visibility.name,
      };

  factory HubCardConfig.fromJson(Map<String, dynamic> json) => HubCardConfig(
        visibility: HubCardVisibility.fromString(json['visibility'] as String?),
      );

  HubCardConfig copyWith({
    HubCardVisibility? visibility,
  }) =>
      HubCardConfig(
        visibility: visibility ?? this.visibility,
      );
}
