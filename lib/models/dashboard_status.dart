enum GoalStatusLabel {
  onTrack,
  tooHigh,
  tooAggressive,
  notEnoughSurplus,
  lowProtein,
  possibleRecomp,
  needsMoreData,
}

enum WeightTrendDirection { down, stable, up, insufficient }

enum MeasurementTrendDirection { down, stable, up, insufficient }

class DashboardStatus {
  final GoalStatusLabel label;
  final String headline;
  final String detail;
  const DashboardStatus({
    required this.label,
    required this.headline,
    required this.detail,
  });
}
