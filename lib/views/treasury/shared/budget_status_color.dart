import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/utils/budget_status.dart';

/// The color for a [BudgetStatus], shared by the mobile and web Budget pages
/// and both Dashboard Budget health cards. Over and Watch use the warning
/// tone (`appColors.bills`), not red: a budget past its line needs attention,
/// not an error state. Funded uses the Treasury accent. Every status also has
/// a text label, so color is never the only signal.
Color budgetStatusColor(BuildContext context, BudgetStatus status) {
  final colors = context.appColors;
  return switch (status) {
    BudgetStatus.onTrack => Theme.of(context).colorScheme.tertiary,
    BudgetStatus.watch => colors.bills,
    BudgetStatus.over => colors.bills,
    BudgetStatus.funded => colors.treasury,
  };
}

/// The icon that goes with a status label.
IconData budgetStatusIcon(BudgetStatus status) => switch (status) {
      BudgetStatus.onTrack => Icons.check_circle_outline_rounded,
      BudgetStatus.watch => Icons.visibility_outlined,
      BudgetStatus.over => Icons.warning_amber_rounded,
      BudgetStatus.funded => Icons.check_circle_outline_rounded,
    };
