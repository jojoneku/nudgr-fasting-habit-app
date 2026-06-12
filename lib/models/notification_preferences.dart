import 'package:flutter/material.dart';

/// Stores per-feature notification opt-in preferences.
class NotificationPreferences {
  // ── Master switch ──────────────────────────────────────────────────────────
  /// Turns every app notification on/off. Enforced centrally in
  /// NotificationService (schedule/show methods no-op while off).
  final bool masterEnabled;

  // ── RPG ────────────────────────────────────────────────────────────────────
  final bool levelUpEnabled;
  final bool rankPromotionEnabled;

  // ── Nutrition ──────────────────────────────────────────────────────────────
  final bool weightReminderEnabled;
  final TimeOfDay weightReminderTime; // default 08:00
  final bool calorieGoalEnabled;

  // ── Quests ─────────────────────────────────────────────────────────────────
  final bool questNotificationsEnabled;
  final bool streakAtRiskEnabled;

  // ── Finance ────────────────────────────────────────────────────────────────
  final bool billsReminderEnabled;
  final int billsReminderDayOfMonth; // 1–28, default 1
  final bool budgetWarningEnabled;
  final int budgetWarningPercent; // 50–95, default 80

  const NotificationPreferences({
    this.masterEnabled = true,
    this.levelUpEnabled = true,
    this.rankPromotionEnabled = true,
    this.weightReminderEnabled = false,
    this.weightReminderTime = const TimeOfDay(hour: 8, minute: 0),
    this.calorieGoalEnabled = true,
    this.questNotificationsEnabled = true,
    this.streakAtRiskEnabled = true,
    this.billsReminderEnabled = true,
    this.billsReminderDayOfMonth = 1,
    this.budgetWarningEnabled = true,
    this.budgetWarningPercent = 80,
  });

  factory NotificationPreferences.defaults() => const NotificationPreferences();

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    final hourRaw = json['weightReminderHour'] as int? ?? 8;
    final minRaw = json['weightReminderMinute'] as int? ?? 0;
    return NotificationPreferences(
      masterEnabled: json['masterEnabled'] as bool? ?? true,
      levelUpEnabled: json['levelUpEnabled'] as bool? ?? true,
      rankPromotionEnabled: json['rankPromotionEnabled'] as bool? ?? true,
      weightReminderEnabled: json['weightReminderEnabled'] as bool? ?? false,
      weightReminderTime: TimeOfDay(hour: hourRaw, minute: minRaw),
      calorieGoalEnabled: json['calorieGoalEnabled'] as bool? ?? true,
      questNotificationsEnabled:
          json['questNotificationsEnabled'] as bool? ?? true,
      streakAtRiskEnabled: json['streakAtRiskEnabled'] as bool? ?? true,
      billsReminderEnabled: json['billsReminderEnabled'] as bool? ?? true,
      billsReminderDayOfMonth:
          (json['billsReminderDayOfMonth'] as int? ?? 1).clamp(1, 28),
      budgetWarningEnabled: json['budgetWarningEnabled'] as bool? ?? true,
      budgetWarningPercent:
          (json['budgetWarningPercent'] as int? ?? 80).clamp(50, 95),
    );
  }

  Map<String, dynamic> toJson() => {
        'masterEnabled': masterEnabled,
        'levelUpEnabled': levelUpEnabled,
        'rankPromotionEnabled': rankPromotionEnabled,
        'weightReminderEnabled': weightReminderEnabled,
        'weightReminderHour': weightReminderTime.hour,
        'weightReminderMinute': weightReminderTime.minute,
        'calorieGoalEnabled': calorieGoalEnabled,
        'questNotificationsEnabled': questNotificationsEnabled,
        'streakAtRiskEnabled': streakAtRiskEnabled,
        'billsReminderEnabled': billsReminderEnabled,
        'billsReminderDayOfMonth': billsReminderDayOfMonth,
        'budgetWarningEnabled': budgetWarningEnabled,
        'budgetWarningPercent': budgetWarningPercent,
      };

  NotificationPreferences copyWith({
    bool? masterEnabled,
    bool? levelUpEnabled,
    bool? rankPromotionEnabled,
    bool? weightReminderEnabled,
    TimeOfDay? weightReminderTime,
    bool? calorieGoalEnabled,
    bool? questNotificationsEnabled,
    bool? streakAtRiskEnabled,
    bool? billsReminderEnabled,
    int? billsReminderDayOfMonth,
    bool? budgetWarningEnabled,
    int? budgetWarningPercent,
  }) =>
      NotificationPreferences(
        masterEnabled: masterEnabled ?? this.masterEnabled,
        levelUpEnabled: levelUpEnabled ?? this.levelUpEnabled,
        rankPromotionEnabled: rankPromotionEnabled ?? this.rankPromotionEnabled,
        weightReminderEnabled:
            weightReminderEnabled ?? this.weightReminderEnabled,
        weightReminderTime: weightReminderTime ?? this.weightReminderTime,
        calorieGoalEnabled: calorieGoalEnabled ?? this.calorieGoalEnabled,
        questNotificationsEnabled:
            questNotificationsEnabled ?? this.questNotificationsEnabled,
        streakAtRiskEnabled: streakAtRiskEnabled ?? this.streakAtRiskEnabled,
        billsReminderEnabled: billsReminderEnabled ?? this.billsReminderEnabled,
        billsReminderDayOfMonth:
            billsReminderDayOfMonth ?? this.billsReminderDayOfMonth,
        budgetWarningEnabled: budgetWarningEnabled ?? this.budgetWarningEnabled,
        budgetWarningPercent: budgetWarningPercent ?? this.budgetWarningPercent,
      );
}
