enum AiCoachEntryPoint { nutrition, fasting, stats, treasury, general }

/// Snapshot of app state passed to the AI model as context.
/// All fields are optional — populate only what's relevant for the entry point.
class AiCoachContext {
  final AiCoachEntryPoint entryPoint;

  // ── Nutrition ──────────────────────────────────────────────────────────────
  final int? todayCalories;
  final int? calorieGoal;
  final double? todayProtein;
  final double? todayCarbs;
  final double? todayFat;

  // ── Fasting ────────────────────────────────────────────────────────────────
  final bool isFasting;
  final int? elapsedFastMinutes;
  final int? fastingGoalHours;
  final int fastingStreak;

  // ── RPG ───────────────────────────────────────────────────────────────────
  final int playerLevel;
  final int playerXp;
  final int playerHp;

  // ── Finance ───────────────────────────────────────────────────────────────
  final double? monthBudget;
  final double? monthSpent;

  const AiCoachContext({
    required this.entryPoint,
    this.todayCalories,
    this.calorieGoal,
    this.todayProtein,
    this.todayCarbs,
    this.todayFat,
    this.isFasting = false,
    this.elapsedFastMinutes,
    this.fastingGoalHours,
    this.fastingStreak = 0,
    this.playerLevel = 1,
    this.playerXp = 0,
    this.playerHp = 100,
    this.monthBudget,
    this.monthSpent,
  });

  /// Human-readable summary injected into the model system prompt.
  String toPromptSummary() {
    final buf = StringBuffer();

    buf.writeln('=== Player Status ===');
    buf.writeln('Level $playerLevel | XP $playerXp | HP $playerHp');
    buf.writeln('Fasting streak: $fastingStreak days');

    if (isFasting && elapsedFastMinutes != null) {
      final h = elapsedFastMinutes! ~/ 60;
      final m = elapsedFastMinutes! % 60;
      buf.writeln(
          'Currently fasting: ${h}h ${m}m / ${fastingGoalHours ?? 16}h goal');
    } else {
      buf.writeln('Not currently fasting.');
    }

    if (todayCalories != null) {
      buf.writeln('=== Today\'s Nutrition ===\n'
          'Calories: $todayCalories / ${calorieGoal ?? '?'} kcal\n'
          'Protein: ${todayProtein?.toStringAsFixed(1) ?? '?'}g | '
          'Carbs: ${todayCarbs?.toStringAsFixed(1) ?? '?'}g | '
          'Fat: ${todayFat?.toStringAsFixed(1) ?? '?'}g');
    }

    if (monthBudget != null && monthSpent != null) {
      buf.writeln('=== Finance ===\n'
          'Budget: ₱${monthBudget!.toStringAsFixed(0)} | '
          'Spent: ₱${monthSpent!.toStringAsFixed(0)}');
    }

    return buf.toString().trim();
  }
}
