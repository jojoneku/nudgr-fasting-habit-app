import 'package:flutter/material.dart';

/// Stores per-feature notification opt-in preferences.
class NotificationPreferences {
  // ── RPG ────────────────────────────────────────────────────────────────────
  final bool levelUpEnabled;
  final bool rankPromotionEnabled;

  // ── Nutrition ──────────────────────────────────────────────────────────────
  final bool weightReminderEnabled;
  final TimeOfDay weightReminderTime; // default 08:00
  final bool calorieGoalEnabled;

  // ── Finance ────────────────────────────────────────────────────────────────
  final bool billsReminderEnabled;
  final int billsReminderDayOfMonth; // 1–28, default 1
  final bool budgetWarningEnabled;
  final int budgetWarningPercent; // 50–95, default 80

  const NotificationPreferences({
    this.levelUpEnabled = true,
    this.rankPromotionEnabled = true,
    this.weightReminderEnabled = false,
    this.weightReminderTime = const TimeOfDay(hour: 8, minute: 0),
    this.calorieGoalEnabled = true,
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
      levelUpEnabled: json['levelUpEnabled'] as bool? ?? true,
      rankPromotionEnabled: json['rankPromotionEnabled'] as bool? ?? true,
      weightReminderEnabled: json['weightReminderEnabled'] as bool? ?? false,
      weightReminderTime: TimeOfDay(hour: hourRaw, minute: minRaw),
      calorieGoalEnabled: json['calorieGoalEnabled'] as bool? ?? true,
      billsReminderEnabled: json['billsReminderEnabled'] as bool? ?? true,
      billsReminderDayOfMonth:
          (json['billsReminderDayOfMonth'] as int? ?? 1).clamp(1, 28),
      budgetWarningEnabled: json['budgetWarningEnabled'] as bool? ?? true,
      budgetWarningPercent:
          (json['budgetWarningPercent'] as int? ?? 80).clamp(50, 95),
    );
  }

  Map<String, dynamic> toJson() => {
        'levelUpEnabled': levelUpEnabled,
        'rankPromotionEnabled': rankPromotionEnabled,
        'weightReminderEnabled': weightReminderEnabled,
        'weightReminderHour': weightReminderTime.hour,
        'weightReminderMinute': weightReminderTime.minute,
        'calorieGoalEnabled': calorieGoalEnabled,
        'billsReminderEnabled': billsReminderEnabled,
        'billsReminderDayOfMonth': billsReminderDayOfMonth,
        'budgetWarningEnabled': budgetWarningEnabled,
        'budgetWarningPercent': budgetWarningPercent,
      };

  NotificationPreferences copyWith({
    bool? levelUpEnabled,
    bool? rankPromotionEnabled,
    bool? weightReminderEnabled,
    TimeOfDay? weightReminderTime,
    bool? calorieGoalEnabled,
    bool? billsReminderEnabled,
    int? billsReminderDayOfMonth,
    bool? budgetWarningEnabled,
    int? budgetWarningPercent,
  }) =>
      NotificationPreferences(
        levelUpEnabled: levelUpEnabled ?? this.levelUpEnabled,
        rankPromotionEnabled: rankPromotionEnabled ?? this.rankPromotionEnabled,
        weightReminderEnabled:
            weightReminderEnabled ?? this.weightReminderEnabled,
        weightReminderTime: weightReminderTime ?? this.weightReminderTime,
        calorieGoalEnabled: calorieGoalEnabled ?? this.calorieGoalEnabled,
        billsReminderEnabled: billsReminderEnabled ?? this.billsReminderEnabled,
        billsReminderDayOfMonth:
            billsReminderDayOfMonth ?? this.billsReminderDayOfMonth,
        budgetWarningEnabled: budgetWarningEnabled ?? this.budgetWarningEnabled,
        budgetWarningPercent: budgetWarningPercent ?? this.budgetWarningPercent,
      );
}
