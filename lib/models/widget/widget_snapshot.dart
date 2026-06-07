/// Immutable, denormalized view of app state that the app pushes to the native
/// home-screen widgets via `home_widget`'s own (unscoped) prefs.
///
/// Why this exists: all app user-data is stored under a `u/$userId/` prefix that
/// only exists after login. The native widget process (and the headless isolate
/// that runs inline actions) has no userId, so it can't read the scoped prefs.
/// The app is therefore the single writer of this flat snapshot; widgets render
/// from it and never touch the scoped store. See `docs/android_widgets_spec.md`.
///
/// Every value is a primitive so it round-trips through
/// `HomeWidget.saveWidgetData<T>()`. All formatting/calculation happens in Dart
/// (the bridge); the native side only renders.
class WidgetSnapshot {
  final bool signedIn;

  // Fasting
  final bool isFasting;
  final int fastStartMillis; // epoch ms; 0 when not fasting (Chronometer base)
  final int targetMillis; // epoch ms of goal end; 0 when not fasting
  final int fastingGoalHours;
  final int currentStreak;
  final String fastPhaseLabel;

  // Food
  final int todayCalories;
  final int calorieGoal;
  final int proteinGrams;
  final int proteinGoal; // -1 when no protein goal set

  // Expense (currency-formatted in Dart)
  final String monthOutflowLabel;
  final String todayOutflowLabel;

  // Weight (unit-aware, formatted in Dart; "" when none logged)
  final String latestWeightLabel;
  final String weightDeltaLabel;

  // Quests
  final int questsDoneToday;
  final int questsTotalToday;
  final String nextQuestLabel; // "" when nothing pending
  final int nextQuestId; // -1 when nothing pending (for inline complete)
  final bool hasUrgentQuest;

  const WidgetSnapshot({
    required this.signedIn,
    required this.isFasting,
    required this.fastStartMillis,
    required this.targetMillis,
    required this.fastingGoalHours,
    required this.currentStreak,
    required this.fastPhaseLabel,
    required this.todayCalories,
    required this.calorieGoal,
    required this.proteinGrams,
    required this.proteinGoal,
    required this.monthOutflowLabel,
    required this.todayOutflowLabel,
    required this.latestWeightLabel,
    required this.weightDeltaLabel,
    required this.questsDoneToday,
    required this.questsTotalToday,
    required this.nextQuestLabel,
    required this.nextQuestId,
    required this.hasUrgentQuest,
  });

  /// Signed-out / no-data state. Every widget renders its "Sign in" empty view.
  factory WidgetSnapshot.empty() => const WidgetSnapshot(
        signedIn: false,
        isFasting: false,
        fastStartMillis: 0,
        targetMillis: 0,
        fastingGoalHours: 0,
        currentStreak: 0,
        fastPhaseLabel: '',
        todayCalories: 0,
        calorieGoal: 0,
        proteinGrams: 0,
        proteinGoal: -1,
        monthOutflowLabel: '',
        todayOutflowLabel: '',
        latestWeightLabel: '',
        weightDeltaLabel: '',
        questsDoneToday: 0,
        questsTotalToday: 0,
        nextQuestLabel: '',
        nextQuestId: -1,
        hasUrgentQuest: false,
      );

  /// Flat key→value map written to `home_widget` prefs (one `saveWidgetData`
  /// call per entry). Keys are mirrored verbatim in the native providers — keep
  /// them in sync with `*WidgetProvider.kt`.
  ///
  /// Numbers are transported as **Strings** on purpose: the home_widget plugin
  /// stores a Dart `int` via `putInt` and has no `Long` branch, so epoch-millis
  /// values (which exceed 32-bit range) fail to save and small ints can't be
  /// read back with `getLong`. Strings sidestep the codec ambiguity entirely;
  /// the Kotlin providers parse them. Bools round-trip safely as bools.
  Map<String, Object?> toWidgetData() => {
        'w_signed_in': signedIn,
        'w_is_fasting': isFasting,
        'w_fast_start_millis': '$fastStartMillis',
        'w_target_millis': '$targetMillis',
        'w_fast_goal_hours': '$fastingGoalHours',
        'w_fast_streak': '$currentStreak',
        'w_fast_phase': fastPhaseLabel,
        'w_food_cals': '$todayCalories',
        'w_food_goal': '$calorieGoal',
        'w_food_protein': '$proteinGrams',
        'w_food_protein_goal': '$proteinGoal',
        'w_expense_month': monthOutflowLabel,
        'w_expense_today': todayOutflowLabel,
        'w_weight': latestWeightLabel,
        'w_weight_delta': weightDeltaLabel,
        'w_quests_done': '$questsDoneToday',
        'w_quests_total': '$questsTotalToday',
        'w_next_quest': nextQuestLabel,
        'w_next_quest_id': '$nextQuestId',
        'w_has_urgent': hasUrgentQuest,
      };

  /// The widget-data keys, used to clear the snapshot on sign-out.
  static List<String> get dataKeys =>
      WidgetSnapshot.empty().toWidgetData().keys.toList();
}
