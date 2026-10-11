import 'package:flutter/foundation.dart';

/// Ledger v2 keys that `WebKeys` (owned by the shell phase) does not define
/// yet. Named in the same `web.ledger.*` scheme so they can move into
/// `WebKeys` unchanged once that file is open for edits.
abstract final class LedgerKeysV2 {
  // Toolbar
  static const clearAll = ValueKey('web.ledger.clearAll');
  static const sortSummary = ValueKey('web.ledger.sortSummary');
  static const scopePill = ValueKey('web.ledger.scopePill');

  // Selection bar
  static const selectionChangeCategory =
      ValueKey('web.ledger.selection.changeCategory');
  static const changeCategoryPicker =
      ValueKey('web.ledger.changeCategory.picker');
  static const changeCategoryApply =
      ValueKey('web.ledger.changeCategory.apply');

  // Draft row cells
  static const draftDate = ValueKey('web.ledger.draft.date');
  static const draftAccount = ValueKey('web.ledger.draft.account');
  static const draftDescription = ValueKey('web.ledger.draft.description');
  static const draftCategory = ValueKey('web.ledger.draft.category');
  static const draftInflow = ValueKey('web.ledger.draft.inflow');
  static const draftOutflow = ValueKey('web.ledger.draft.outflow');
  static const draftError = ValueKey('web.ledger.draft.error');

  // Empty states
  static const emptyOpenSetup = ValueKey('web.ledger.empty.openSetup');

  // Add / Edit dialog
  static const dialogDelete = ValueKey('web.ledger.dialog.delete');
  static const dialogOwedBy = ValueKey('web.ledger.dialog.owedBy');
  static const dialogExpectedBack = ValueKey('web.ledger.dialog.expectedBack');
  static const dialogInstallmentMonths =
      ValueKey('web.ledger.dialog.installments.months');
  static const dialogInstallmentRate =
      ValueKey('web.ledger.dialog.installments.rate');
}
