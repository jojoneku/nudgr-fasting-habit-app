import 'package:flutter/material.dart';

/// Which group of the v2 nav rail a destination sits under (Plan 063).
///
/// The canvas groups the rail: Overview · Money · Plan · Review, with Setup &
/// Accounts in the rail's foot rather than in a group.
enum WebNavGroup {
  overview('Overview'),
  money('Money'),
  plan('Plan'),
  review('Review');

  final String label;
  const WebNavGroup(this.label);
}

/// A destination of the Treasury web v2 shell.
///
/// Replaces the shared `int` index the pre-v2 shell used, which only worked
/// because the desktop list happened to be in the mobile tab order. The v2
/// desktop list has no Cart, so the position in the rail is no longer the
/// position in the mobile `TreasuryModuleView`; [mobileTabIndex] carries the
/// mapping explicitly instead.
enum WebDest {
  dashboard(
    label: 'Dashboard',
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard,
    group: WebNavGroup.overview,
    mobileTabIndex: 0,
  ),
  ledger(
    label: 'Ledger',
    icon: Icons.list_alt_outlined,
    selectedIcon: Icons.list_alt,
    group: WebNavGroup.money,
    mobileTabIndex: 1,
  ),
  bills(
    label: 'Bills',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long,
    group: WebNavGroup.money,
    mobileTabIndex: 2,
  ),
  budget(
    label: 'Budget',
    icon: Icons.pie_chart_outline,
    selectedIcon: Icons.pie_chart,
    group: WebNavGroup.money,
    mobileTabIndex: 3,
  ),
  history(
    label: 'History',
    icon: Icons.history_outlined,
    selectedIcon: Icons.history,
    group: WebNavGroup.review,
    mobileTabIndex: 4,
  ),
  goals(
    label: 'Goals',
    icon: Icons.flag_outlined,
    selectedIcon: Icons.flag,
    group: WebNavGroup.plan,
    mobileTabIndex: 6,
  ),
  setup(
    label: 'Setup & Accounts',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    group: null,
    mobileTabIndex: 7,
  );

  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// Null for [setup], which lives in the nav foot rather than in a group.
  final WebNavGroup? group;

  /// Index of the matching tab in the mobile `TreasuryModuleView` that the
  /// narrow (< 840 dp) web layout mounts: Dashboard 0 · Ledger 1 · Bills 2 ·
  /// Budget 3 · History 4 · Cart 5 · Goals 6 · More 7. Setup maps to More,
  /// which is where the narrow layout reaches Setup from.
  final int mobileTabIndex;

  const WebDest({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.group,
    required this.mobileTabIndex,
  });

  /// The desktop destination for a mobile tab index, or null when that tab
  /// has no desktop counterpart (Cart, index 5) — the caller keeps whatever
  /// destination it already had.
  static WebDest? fromMobileTabIndex(int index) {
    for (final d in values) {
      if (d.mobileTabIndex == index) return d;
    }
    return null;
  }

  /// Destinations of [group], in rail order.
  static List<WebDest> inGroup(WebNavGroup group) =>
      values.where((d) => d.group == group).toList();
}
