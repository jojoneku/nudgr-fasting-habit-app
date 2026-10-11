import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:intermittent_fasting/app_colors.dart';

/// Keys the v2 Budget page and its dialogs need beyond the `WebKeys`
/// registry (Plan 063, ground rule 4). Local to the Budget slice; the parity
/// test reads them next to the shared ones. Row- and group-scoped keys are
/// functions so a test can address one row without walking the tree.
abstract final class WebBudgetKeys {
  static const heroPacePill = ValueKey('web.budget.hero.pacePill');
  static const emptyState = ValueKey('web.budget.emptyState');
  static const tableHeader = ValueKey('web.budget.table.header');
  static const draftRow = ValueKey('web.budget.draftRow');

  /// One table group header (the subtotal row) by group id.
  static ValueKey<String> group(String groupId) =>
      ValueKey('web.budget.group.$groupId');

  /// One category / savings row by its budget key (category or account id).
  static ValueKey<String> row(String id) => ValueKey('web.budget.row.$id');

  /// The status pill of one row.
  static ValueKey<String> status(String id) =>
      ValueKey('web.budget.status.$id');

  /// One legend line of the allocation donut.
  static ValueKey<String> legend(String groupId) =>
      ValueKey('web.budget.legend.$groupId');

  // New category dialog.
  static const newCategoryName = ValueKey('web.budget.newCategory.name');
  static const newCategoryType = ValueKey('web.budget.newCategory.type');
  static const newCategoryColor = ValueKey('web.budget.newCategory.color');
  static const newCategoryIcon = ValueKey('web.budget.newCategory.icon');
  static const newCategoryIconMore =
      ValueKey('web.budget.newCategory.icon.more');
  static const newCategoryExclude = ValueKey('web.budget.newCategory.exclude');
  static const newCategoryCreate = ValueKey('web.budget.newCategory.create');
  static const newCategoryCancel = ValueKey('web.budget.newCategory.cancel');

  // Manage groups dialog.
  static ValueKey<String> groupRow(String groupId) =>
      ValueKey('web.budget.groups.row.$groupId');
  static const groupsRenameField = ValueKey('web.budget.groups.rename.field');
  static const groupsRenameSave = ValueKey('web.budget.groups.rename.save');
  static const groupsRenameCancel = ValueKey('web.budget.groups.rename.cancel');
}

/// The accent a budget group is drawn in — its table dot, its donut slice,
/// its legend line and the fill of its rows' Used bars. Cycles the domain
/// accents in group order so the three defaults read blue · purple · gold as
/// on the canvas, and a fourth, fifth or sixth custom group still gets a
/// colour of its own before the cycle repeats.
Color webBudgetGroupColor(BuildContext context, int index) {
  final cs = Theme.of(context).colorScheme;
  final a = context.appColors;
  final palette = [cs.primary, a.weight, a.treasury, a.food, a.move, a.bills];
  return palette[index % palette.length];
}

/// Whole-peso figure for the places the canvas drops the centavos — status
/// pills ("Over by ₱76") and the remaining cell ("₱76 over") — so the pill
/// stays one line in a 140 px column. Totals keep `formatPeso`.
String formatPesoWhole(double amount) {
  final formatter = NumberFormat('#,##0', 'en_PH');
  return '₱${formatter.format(amount.round())}';
}
