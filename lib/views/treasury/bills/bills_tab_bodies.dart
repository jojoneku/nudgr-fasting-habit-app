import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/category_icon.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/bills/bills_list_parts.dart';
import 'package:intermittent_fasting/views/treasury/bills/obligation_card.dart';
import 'package:intermittent_fasting/views/treasury/bills/start_month_review_card.dart';
import 'package:intermittent_fasting/views/treasury/bills/statement_bill_card.dart';
import 'package:intl/intl.dart';

/// The bodies of the five Bills tabs and the row cards they list (Plan 071
/// Phase 6). Moved out of `bills_receivables_view.dart`, which keeps the
/// sheets, dialogs and batch logic and hands them in as [BillsRowActions].

// ─── Wiring ───────────────────────────────────────────────────────────────────

/// Everything a row on the Bills tab can do. The view owns the sheets and
/// dialogs behind each callback.
class BillsRowActions {
  final ValueChanged<Bill> payBill;
  final ValueChanged<Bill> undoBill;
  final ValueChanged<Bill> editBill;
  final ValueChanged<Bill> deleteBill;
  final ValueChanged<Bill> viewStatement;
  final ValueChanged<Receivable> receive;
  final ValueChanged<Receivable> undoReceipt;
  final ValueChanged<Receivable> editReceivable;
  final ValueChanged<Receivable> deleteReceivable;
  final ValueChanged<BudgetedExpense> fund;
  final ValueChanged<BudgetedExpense> undoFunding;
  final ValueChanged<BudgetedExpense> editSetAside;
  final ValueChanged<BudgetedExpense> deleteSetAside;
  final ValueChanged<Installment> payInstallment;
  final ValueChanged<Installment> undoInstallment;
  final ValueChanged<Installment> editInstallment;
  final ValueChanged<Installment> deleteInstallment;

  const BillsRowActions({
    required this.payBill,
    required this.undoBill,
    required this.editBill,
    required this.deleteBill,
    required this.viewStatement,
    required this.receive,
    required this.undoReceipt,
    required this.editReceivable,
    required this.deleteReceivable,
    required this.fund,
    required this.undoFunding,
    required this.editSetAside,
    required this.deleteSetAside,
    required this.payInstallment,
    required this.undoInstallment,
    required this.editInstallment,
    required this.deleteInstallment,
  });
}

/// The batch selection as the open tab sees it. A selection lives in one tab
/// only: switching tabs ends it.
class BillsRowSelection {
  /// True while this tab is in multi-select — its rows show checkboxes.
  final bool active;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;

  /// Long-press entry point: starts a selection with this id picked.
  final ValueChanged<String> onStart;

  const BillsRowSelection({
    required this.active,
    required this.selectedIds,
    required this.onToggle,
    required this.onStart,
  });
}

/// Bottom gap between cards. [key] belongs on the padding, not the card:
/// `ReorderableListView` keys its direct children, which are these wrappers.
Widget _cardPad(Widget child, {Key? key}) => Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 8),
      child: child,
    );

/// Resolves the category icon + theme-aware color for [categoryId]. Falls back
/// to a type-appropriate icon and [fallback] color when the item has no linked
/// category.
///
/// The palette slot comes from the category (via the presenter), not from the
/// card's position, so two entries sharing a category draw the same color.
({IconData icon, Color color}) _categoryVisual(
  BuildContext context,
  BillsReceivablesPresenter presenter,
  String categoryId, {
  required Color fallback,
}) {
  final cat = presenter.categoryById(categoryId);
  final icon = categoryIcon(cat?.name, cat?.type ?? CategoryType.expense);
  final color = cat != null
      ? resolveSliceColor(
          cat.colorHex,
          presenter.categoryPaletteSlot(categoryId),
          brightness: Theme.of(context).brightness,
        )
      : fallback;
  return (icon: icon, color: color);
}

// A bill's type is a subset of its category — shown as a small badge after
// the name. Label is context-free; color needs the theme.
String _billTypeLabel(BillType t) => switch (t) {
      BillType.creditCard => 'CC',
      BillType.installment => 'INSTALL',
      BillType.subscription => 'SUB',
      BillType.insurance => 'INS',
      BillType.govtContribution => 'GOV',
      BillType.utility => 'UTIL',
      BillType.other => 'OTHER',
    };

Color _billTypeColor(BuildContext context, BillType t) {
  final cs = Theme.of(context).colorScheme;
  return switch (t) {
    BillType.creditCard => cs.error,
    BillType.installment => context.appColors.gold,
    BillType.subscription => cs.primary,
    BillType.insurance => context.appColors.success,
    BillType.govtContribution => context.appColors.purple,
    BillType.utility => context.appColors.orange,
    BillType.other => cs.onSurfaceVariant,
  };
}

String _receivableTypeLabel(ReceivableType t) => switch (t) {
      ReceivableType.salary => 'SALARY',
      ReceivableType.reimbursement => 'REIMB',
      ReceivableType.business => 'BIZ',
      ReceivableType.other => 'OTHER',
    };

Color _receivableTypeColor(BuildContext context, ReceivableType t) {
  final cs = Theme.of(context).colorScheme;
  return switch (t) {
    ReceivableType.salary => context.appColors.success,
    ReceivableType.reimbursement => cs.primary,
    ReceivableType.business => context.appColors.gold,
    ReceivableType.other => cs.onSurfaceVariant,
  };
}

// ─── Tab bodies ───────────────────────────────────────────────────────────────

/// Upcoming: the due-soon bills (the hero's included, so its full row
/// actions are here), then the later ones.
class UpcomingBillsTab extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final BillsRowActions actions;
  final BillsRowSelection selection;

  const UpcomingBillsTab({
    super.key,
    required this.presenter,
    required this.actions,
    required this.selection,
  });

  @override
  Widget build(BuildContext context) {
    final soon = presenter.unpaidDueSoon;
    final later = presenter.unpaidLater;
    Widget card(Bill b) => _cardPad(BillRowCard(
          presenter: presenter,
          bill: b,
          actions: actions,
          selection: selection,
        ));
    if (soon.isEmpty && later.isEmpty) {
      return BillsSection(
        emptyMessage: presenter.upcomingEmptyMessage,
        children: const [],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (soon.isNotEmpty)
          BillsSection(
            title: 'Due soon',
            count: soon.length,
            emptyMessage: '',
            children: [for (final b in soon) card(b)],
          ),
        if (soon.isNotEmpty && later.isNotEmpty) const SizedBox(height: 10),
        if (later.isNotEmpty)
          BillsSection(
            // Only named when there is a "Due soon" group to tell it from.
            title: soon.isEmpty ? null : 'Later this month',
            count: later.length,
            emptyMessage: '',
            children: [for (final b in later) card(b)],
          ),
      ],
    );
  }
}

/// Paid: only the month's paid bills.
class PaidBillsTab extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final BillsRowActions actions;
  final BillsRowSelection selection;

  const PaidBillsTab({
    super.key,
    required this.presenter,
    required this.actions,
    required this.selection,
  });

  @override
  Widget build(BuildContext context) {
    return BillsSection(
      emptyMessage: 'Nothing paid yet this month.',
      children: [
        for (final b in presenter.paidBills)
          _cardPad(BillRowCard(
            presenter: presenter,
            bill: b,
            actions: actions,
            selection: selection,
          )),
      ],
    );
  }
}

/// Set-asides: the month's budgeted expenses, unfunded first.
class SetAsidesTab extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final BillsRowActions actions;
  final BillsRowSelection selection;

  const SetAsidesTab({
    super.key,
    required this.presenter,
    required this.actions,
    required this.selection,
  });

  @override
  Widget build(BuildContext context) {
    return BillsSection(
      emptyMessage: 'No set-asides budgeted this month.',
      children: [
        for (final e in presenter.budgetedExpenses)
          _cardPad(SetAsideRowCard(
            presenter: presenter,
            expense: e,
            actions: actions,
            selection: selection,
          )),
      ],
    );
  }
}

/// Receivables, with a Reorder toggle once there are two or more still-owed
/// entries to arrange. In reorder mode the still-owed rows become a
/// [ReorderableListView] with an explicit drag handle — the cards' own
/// tap/long-press (edit, delete) is suppressed so a drag can't fire them, and
/// the default long-press drag is off for the same reason.
class ReceivablesTab extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final BillsRowActions actions;
  final BillsRowSelection selection;

  /// The view's reorder switch. Reordering and selecting are both "act on the
  /// list as a whole" modes, so reorder is offered only outside a selection.
  final bool reordering;
  final VoidCallback onToggleReorder;

  const ReceivablesTab({
    super.key,
    required this.presenter,
    required this.actions,
    required this.selection,
    required this.reordering,
    required this.onToggleReorder,
  });

  @override
  Widget build(BuildContext context) {
    final pending = presenter.pendingReceivables;
    final received = presenter.receivedReceivables;
    final canReorder = pending.length > 1 && !selection.active;
    final dragging = reordering && canReorder;
    Widget card(Receivable r, {int? dragIndex}) => ReceivableRowCard(
          presenter: presenter,
          receivable: r,
          actions: actions,
          selection: selection,
          dragIndex: dragIndex,
        );
    return BillsSection(
      emptyMessage: 'Nothing owed to you this month.',
      trailing: canReorder
          ? ReorderToggle(
              active: dragging,
              onToggle: onToggleReorder,
              onReset: dragging && presenter.hasManualReceivableOrder
                  ? presenter.resetReceivableOrder
                  : null,
            )
          : null,
      children: [
        if (dragging)
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: presenter.reorderPendingReceivables,
            children: [
              for (int i = 0; i < pending.length; i++)
                _cardPad(
                  key: ValueKey('reorder_${pending[i].id}'),
                  card(pending[i], dragIndex: i),
                ),
            ],
          )
        else
          for (final r in pending) _cardPad(card(r)),
        for (final r in received) _cardPad(card(r)),
      ],
    );
  }
}

/// Installments due this month, under the start-month review card.
class InstallmentsTab extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final InstallmentPresenter installmentPresenter;
  final BillsRowActions actions;
  final BillsRowSelection selection;

  const InstallmentsTab({
    super.key,
    required this.presenter,
    required this.installmentPresenter,
    required this.actions,
    required this.selection,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Plans whose first payment month differs from the card's cycle
        // (Plan 068) — shown above the rows, even in a month with none due.
        StartMonthReviewCard(
          presenter: installmentPresenter,
          margin: const EdgeInsets.only(bottom: 12),
        ),
        BillsSection(
          emptyMessage: 'No installment payments due this month.',
          children: [
            for (final inst in installmentPresenter.dueThisMonth)
              _cardPad(InstallmentRowCard(
                presenter: presenter,
                installmentPresenter: installmentPresenter,
                installment: inst,
                actions: actions,
                selection: selection,
              )),
          ],
        ),
      ],
    );
  }
}

// ─── Row cards ────────────────────────────────────────────────────────────────

/// One bill: a statement card for a credit statement, an [ObligationCard]
/// otherwise.
class BillRowCard extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final Bill bill;
  final BillsRowActions actions;
  final BillsRowSelection selection;

  const BillRowCard({
    super.key,
    required this.presenter,
    required this.bill,
    required this.actions,
    required this.selection,
  });

  @override
  Widget build(BuildContext context) {
    final b = bill;
    final selected = selection.selectedIds.contains(b.id);
    final statement = presenter.statementCard(b);
    if (statement != null) {
      return StatementBillCard(
        key: ValueKey('bill_${b.id}'),
        view: statement,
        onPay: () => actions.payBill(b),
        onUndo:
            presenter.hasUndoablePayment(b) ? () => actions.undoBill(b) : null,
        onViewItems: () => actions.viewStatement(b),
        onEdit: () => actions.editBill(b),
        onLongPress: () => selection.onStart(b.id),
        selectionMode: selection.active,
        selected: selected,
        onSelectionToggle: () => selection.onToggle(b.id),
      );
    }
    final v = _categoryVisual(context, presenter, b.categoryId,
        fallback: context.appColors.bills);
    final String? note = presenter.statementProgressNote(b) ??
        (b.isPaid
            ? 'Paid ${formatPeso(b.paidAmount ?? b.amount)}'
                '${b.paidDate != null ? ' · ${DateFormat('MMM d').format(b.paidDate!)}' : ''}'
            : b.isAutoStatement
                ? 'Auto-generated statement'
                : (b.paymentNote != null && b.paymentNote!.isNotEmpty
                    ? b.paymentNote
                    : null));
    return ObligationCard(
      key: ValueKey('bill_${b.id}'),
      icon: v.icon,
      iconColor: v.color,
      name: b.name,
      // "Other" carries no meaning now the type picker is gone — hide the badge
      // rather than stamp every manual bill with a noisy "OTHER".
      badgeLabel:
          b.billType == BillType.other ? null : _billTypeLabel(b.billType),
      badgeColor: _billTypeColor(context, b.billType),
      note: note,
      amount: b.amount,
      progress: presenter.statementProgressFraction(b),
      dateLabel: 'due ${DateFormat('MMM d').format(presenter.billDueDate(b))}',
      actionLabel: 'Pay',
      done: b.isPaid,
      onAction: b.isPaid ? null : () => actions.payBill(b),
      onUndo:
          presenter.hasUndoablePayment(b) ? () => actions.undoBill(b) : null,
      undoLabel: 'Mark unpaid',
      onEdit: () => actions.editBill(b),
      onDelete: () => actions.deleteBill(b),
      onLongPress: () => selection.onStart(b.id),
      selectionMode: selection.active,
      selected: selected,
      onSelectionToggle: () => selection.onToggle(b.id),
      // Credit statements list what is on them: purchases, installment
      // months, refunds and repayments, each opening its transaction form.
      detailLabel: presenter.statementItemsLabel(b),
      onDetail: () => actions.viewStatement(b),
    );
  }
}

/// One receivable. [dragIndex] is set in reorder mode, where every row
/// action steps aside for the drag handle.
class ReceivableRowCard extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final Receivable receivable;
  final BillsRowActions actions;
  final BillsRowSelection selection;
  final int? dragIndex;

  const ReceivableRowCard({
    super.key,
    required this.presenter,
    required this.receivable,
    required this.actions,
    required this.selection,
    this.dragIndex,
  });

  @override
  Widget build(BuildContext context) {
    final r = receivable;
    final v = _categoryVisual(context, presenter, r.categoryId,
        fallback: context.appColors.success);
    final locked = dragIndex != null;
    final date = r.expectedDate;
    final dateLabel =
        date == null ? 'ASAP' : 'exp ${DateFormat('MMM d').format(date)}';
    final String? note = r.isReceived
        ? 'Received ${formatPeso(r.receivedAmount ?? r.amount)}'
            '${r.receivedDate != null ? ' · ${DateFormat('MMM d').format(r.receivedDate!)}' : ''}'
        : null;
    return ObligationCard(
      key: ValueKey('rec_${r.id}'),
      icon: v.icon,
      iconColor: v.color,
      name: r.name,
      badgeLabel: r.receivableType == ReceivableType.other
          ? null
          : _receivableTypeLabel(r.receivableType),
      badgeColor: _receivableTypeColor(context, r.receivableType),
      note: note,
      amount: r.amount,
      dateLabel: dateLabel,
      isInflow: true,
      actionLabel: 'Receive',
      done: r.isReceived,
      onAction: r.isReceived || locked ? null : () => actions.receive(r),
      onUndo: r.isReceived && !locked ? () => actions.undoReceipt(r) : null,
      undoLabel: 'Mark not received',
      onEdit: locked ? null : () => actions.editReceivable(r),
      onDelete: locked ? null : () => actions.deleteReceivable(r),
      onLongPress: locked ? null : () => selection.onStart(r.id),
      // A row being dragged is not a row being picked.
      selectionMode: selection.active && !locked,
      selected: selection.selectedIds.contains(r.id),
      onSelectionToggle: () => selection.onToggle(r.id),
      dragHandle: dragIndex == null
          ? null
          : ReorderableDragStartListener(
              index: dragIndex!,
              child: Tooltip(
                message: 'Drag to reorder',
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    size: 22,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
    );
  }
}

/// One set-aside (budgeted expense).
class SetAsideRowCard extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final BudgetedExpense expense;
  final BillsRowActions actions;
  final BillsRowSelection selection;

  const SetAsideRowCard({
    super.key,
    required this.presenter,
    required this.expense,
    required this.actions,
    required this.selection,
  });

  @override
  Widget build(BuildContext context) {
    final e = expense;
    final v = _categoryVisual(context, presenter, e.categoryId,
        fallback: context.appColors.gold);
    final accountName = presenter.accountName(e.accountId);
    final destinationName = presenter.accountName(e.destinationAccountId);
    // Say where the money is headed when the set-aside names a destination
    // ("BPI → Maya"), so the route is visible before you fund it.
    final String? route = accountName == null && destinationName == null
        ? null
        : destinationName == null
            ? 'Fund from $accountName'
            : accountName == null
                ? 'Set aside into $destinationName'
                : '$accountName → $destinationName';
    final String? note = e.isPaid
        ? 'Funded ${formatPeso(e.spentAmount)}'
        : (e.note != null && e.note!.isNotEmpty ? e.note : route);
    final progress = e.allocatedAmount > 0
        ? (e.spentAmount / e.allocatedAmount).clamp(0.0, 1.0)
        : null;
    return ObligationCard(
      key: ValueKey('bud_${e.id}'),
      icon: v.icon,
      iconColor: v.color,
      name: e.name,
      note: note,
      progress: progress,
      amount: e.allocatedAmount,
      dateLabel: e.budgetedType.label,
      actionLabel: 'Fund',
      done: e.isPaid,
      onAction: e.isPaid ? null : () => actions.fund(e),
      onUndo: e.isPaid ? () => actions.undoFunding(e) : null,
      undoLabel: 'Mark unfunded',
      onEdit: () => actions.editSetAside(e),
      onDelete: () => actions.deleteSetAside(e),
      onLongPress: () => selection.onStart(e.id),
      selectionMode: selection.active,
      selected: selection.selectedIds.contains(e.id),
      onSelectionToggle: () => selection.onToggle(e.id),
    );
  }
}

/// One installment plan's payment for the month.
class InstallmentRowCard extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final InstallmentPresenter installmentPresenter;
  final Installment installment;
  final BillsRowActions actions;
  final BillsRowSelection selection;

  const InstallmentRowCard({
    super.key,
    required this.presenter,
    required this.installmentPresenter,
    required this.installment,
    required this.actions,
    required this.selection,
  });

  @override
  Widget build(BuildContext context) {
    final inst = installment;
    // On a card with statements a month is paid by paying its statement, so
    // the row follows that statement instead of calling a billed month paid.
    final onStatement = presenter.installmentStatementStatus(inst);
    final statementBill = onStatement?.statement;
    final paidThisMonth =
        onStatement?.paid ?? installmentPresenter.isPaidForMonth(inst.id);
    final canPay = installmentPresenter.canMarkPaid(inst);
    final canUndo = installmentPresenter.canMarkUnpaid(inst);
    final account = installmentPresenter.accounts
        .where((a) => a.id == inst.accountId)
        .firstOrNull;
    return ObligationCard(
      key: ValueKey('inst_${inst.id}'),
      icon: Icons.credit_score_outlined,
      iconColor: context.appColors.purple,
      name: inst.name,
      // On a card with statements the note says why there is no Pay button:
      // the month can only be paid with the whole statement.
      note: onStatement?.note ?? account?.name,
      // Paid months only: a month billed onto an open statement is not paid.
      progress: onStatement?.progress ??
          installmentPresenter.paymentProgress(inst.id),
      amount: inst.monthlyAmount,
      dateLabel: onStatement?.label ?? installmentPresenter.statusLabel(inst),
      actionLabel: 'Pay',
      done: paidThisMonth,
      // A plan on a card with statements is billed at close and paid with the
      // statement, so its row offers neither Pay nor Undo.
      onAction: canPay ? () => actions.payInstallment(inst) : null,
      onUndo: canUndo ? () => actions.undoInstallment(inst) : null,
      undoLabel: 'Mark unpaid this month',
      detailLabel: onStatement?.linkLabel,
      onDetail: statementBill == null
          ? null
          : () => actions.viewStatement(statementBill),
      onEdit: () => actions.editInstallment(inst),
      onDelete: () => actions.deleteInstallment(inst),
      onLongPress: () => selection.onStart(inst.id),
      selectionMode: selection.active,
      selected: selection.selectedIds.contains(inst.id),
      onSelectionToggle: () => selection.onToggle(inst.id),
    );
  }
}
