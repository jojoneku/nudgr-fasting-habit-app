import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/category_icon.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/shared/month_year_picker.dart';
import 'package:intermittent_fasting/views/treasury/shared/sheet_fields.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_bill_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_installment_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_receivable_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/coming_up_timeline.dart';
import 'package:intermittent_fasting/views/treasury/bills/due_soon_stack.dart';
import 'package:intermittent_fasting/views/treasury/bills/obligation_card.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// The redesigned Bills tab: a swipeable due-soon stack, Pending/Paid/
/// Installments chips, a unified "Coming up" timeline, and titled sections of
/// Pay/Receive cards for bills, receivables, budgeted expenses, and
/// installments. The "Bills" title + month·year picker live in the shared
/// Treasury app bar (see `TreasuryModuleView`); credit cards live on the
/// Dashboard under Accounts.
class BillsReceivablesView extends StatefulWidget {
  final BillsReceivablesPresenter presenter;
  final InstallmentPresenter installmentPresenter;

  const BillsReceivablesView({
    super.key,
    required this.presenter,
    required this.installmentPresenter,
  });

  @override
  State<BillsReceivablesView> createState() => _BillsReceivablesViewState();
}

class _BillsReceivablesViewState extends State<BillsReceivablesView> {
  @override
  void initState() {
    super.initState();
    widget.presenter.load();
    widget.installmentPresenter.load();
  }

  /// Month is owned by the in-page picker (the shared app bar is hidden on this
  /// tab). Keep the bills and installment presenters in step.
  void _setMonth(String month) {
    widget.presenter.setMonth(month);
    widget.installmentPresenter.setMonth(month);
  }

  // ─── Sheets ────────────────────────────────────────────────────────────────

  void _showAddBillSheet([Bill? existing]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          AddBillSheet(presenter: widget.presenter, existing: existing),
    );
  }

  void _showAddReceivableSheet([Receivable? existing]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          AddReceivableSheet(presenter: widget.presenter, existing: existing),
    );
  }

  void _showAddBudgetedExpenseSheet([BudgetedExpense? existing]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddBudgetedExpenseSheet(
          presenter: widget.presenter, existing: existing),
    );
  }

  void _showMarkBillPaidSheet(Bill bill) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          _MarkBillPaidSheet(bill: bill, presenter: widget.presenter),
    );
  }

  void _showMarkReceivedSheet(Receivable receivable) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _MarkReceivedSheet(
          receivable: receivable, presenter: widget.presenter),
    );
  }

  void _showMarkExpensePaidSheet(BudgetedExpense expense) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          _MarkExpensePaidSheet(expense: expense, presenter: widget.presenter),
    );
  }

  void _showAddInstallmentSheet([Installment? existing]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => AddInstallmentSheet(
          presenter: widget.installmentPresenter, existing: existing),
    );
  }

  void _showMarkInstallmentPaidSheet(Installment installment) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _MarkInstallmentPaidSheet(
          installment: installment, presenter: widget.installmentPresenter),
    );
  }

  void _showFabMenu() {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  Icon(Icons.receipt_long_outlined, color: colorScheme.primary),
              title: const Text('Add Bill'),
              onTap: () {
                Navigator.pop(context);
                _showAddBillSheet();
              },
            ),
            ListTile(
              leading:
                  Icon(Icons.attach_money, color: context.appColors.success),
              title: const Text('Add Receivable'),
              onTap: () {
                Navigator.pop(context);
                _showAddReceivableSheet();
              },
            ),
            ListTile(
              leading:
                  Icon(Icons.savings_outlined, color: context.appColors.gold),
              title: const Text('Add Budgeted Expense'),
              onTap: () {
                Navigator.pop(context);
                _showAddBudgetedExpenseSheet();
              },
            ),
            ListTile(
              leading:
                  Icon(Icons.credit_score_outlined, color: colorScheme.primary),
              title: const Text('Add Installment'),
              subtitle:
                  const Text('Track a purchase split into monthly payments'),
              onTap: () {
                Navigator.pop(context);
                _showAddInstallmentSheet();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  /// Resolves the category icon + theme-aware color for [categoryId]. Falls back
  /// to a type-appropriate icon and [fallback] color when the item has no linked
  /// category. Mirrors the ledger tiles' in-widget icon/color resolution.
  ({IconData icon, Color color}) _catVisual(
    String categoryId,
    int index, {
    required Color fallback,
  }) {
    final cat = widget.presenter.categoryById(categoryId);
    final icon = categoryIcon(cat?.name, cat?.type ?? CategoryType.expense);
    final color = cat != null
        ? resolveSliceColor(cat.colorHex, index,
            brightness: Theme.of(context).brightness)
        : fallback;
    return (icon: icon, color: color);
  }

  void _onComingUpTap(ComingUpItem item) {
    final s = item.source;
    if (s is Bill) {
      if (!s.isPaid) _showMarkBillPaidSheet(s);
    } else if (s is Receivable) {
      if (!s.isReceived) _showMarkReceivedSheet(s);
    } else if (s is BudgetedExpense) {
      if (!s.isPaid) _showMarkExpensePaidSheet(s);
    } else if (s is Installment) {
      if (!widget.installmentPresenter.isPaidForMonth(s.id)) {
        _showMarkInstallmentPaidSheet(s);
      }
    }
  }

  Future<void> _confirmDelete({
    required String title,
    required String body,
    required VoidCallback onConfirm,
  }) async {
    final ok = await AppConfirmDialog.confirm(
      context: context,
      title: title,
      body: body,
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      isDestructive: true,
    );
    if (ok) onConfirm();
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

  Color _billTypeColor(BillType t) {
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

  Color _receivableTypeColor(ReceivableType t) {
    final cs = Theme.of(context).colorScheme;
    return switch (t) {
      ReceivableType.salary => context.appColors.success,
      ReceivableType.reimbursement => cs.primary,
      ReceivableType.business => context.appColors.gold,
      ReceivableType.other => cs.onSurfaceVariant,
    };
  }

  // ─── Sections ────────────────────────────────────────────────────────────

  Widget _billsSection() {
    final bills = widget.presenter.bills;
    return _Section(
      title: 'Bills',
      count: bills.length,
      emptyMessage: 'No bills this month',
      children: [
        for (int i = 0; i < bills.length; i++) _cardPad(_billCard(bills[i], i)),
      ],
    );
  }

  Widget _billCard(Bill b, int i) {
    final v = _catVisual(b.categoryId, i, fallback: context.appColors.bills);
    final String? note = b.isPaid
        ? 'Paid ${formatPeso(b.paidAmount ?? b.amount)}'
            '${b.paidDate != null ? ' · ${DateFormat('MMM d').format(b.paidDate!)}' : ''}'
        : b.isAutoStatement
            ? 'Auto-generated statement'
            : (b.paymentNote != null && b.paymentNote!.isNotEmpty
                ? b.paymentNote
                : null);
    return ObligationCard(
      key: ValueKey('bill_${b.id}'),
      icon: v.icon,
      iconColor: v.color,
      name: b.name,
      badgeLabel: _billTypeLabel(b.billType),
      badgeColor: _billTypeColor(b.billType),
      note: note,
      amount: b.amount,
      dateLabel:
          'due ${DateFormat('MMM d').format(widget.presenter.billDueDate(b))}',
      actionLabel: 'Pay',
      done: b.isPaid,
      onAction: b.isPaid ? null : () => _showMarkBillPaidSheet(b),
      onEdit: () => _showAddBillSheet(b),
      onDelete: () => _confirmDelete(
        title: 'Delete Bill',
        body: 'Delete "${b.name}"?',
        onConfirm: () => widget.presenter.deleteBill(b.id),
      ),
    );
  }

  Widget _receivablesSection() {
    final receivables = widget.presenter.receivables;
    return _Section(
      title: 'Receivables',
      count: receivables.length,
      emptyMessage: 'No receivables this month',
      children: [
        for (int i = 0; i < receivables.length; i++)
          _cardPad(_receivableCard(receivables[i], i)),
      ],
    );
  }

  Widget _receivableCard(Receivable r, int i) {
    final v = _catVisual(r.categoryId, i, fallback: context.appColors.success);
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
      badgeLabel: _receivableTypeLabel(r.receivableType),
      badgeColor: _receivableTypeColor(r.receivableType),
      note: note,
      amount: r.amount,
      dateLabel: dateLabel,
      isInflow: true,
      actionLabel: 'Receive',
      done: r.isReceived,
      onAction: r.isReceived ? null : () => _showMarkReceivedSheet(r),
      onEdit: () => _showAddReceivableSheet(r),
      onDelete: () => _confirmDelete(
        title: 'Delete Receivable',
        body: 'Delete "${r.name}"?',
        onConfirm: () => widget.presenter.deleteReceivable(r.id),
      ),
    );
  }

  Widget _budgetedSection() {
    final expenses = widget.presenter.budgetedExpenses;
    return _Section(
      title: 'Budgeted',
      count: expenses.length,
      emptyMessage: 'No budgeted expenses this month',
      children: [
        for (int i = 0; i < expenses.length; i++)
          _cardPad(_budgetedCard(expenses[i], i)),
      ],
    );
  }

  Widget _budgetedCard(BudgetedExpense e, int i) {
    final v = _catVisual(e.categoryId, i, fallback: context.appColors.gold);
    final accountName = widget.presenter.accountName(e.accountId);
    final String? note = e.isPaid
        ? 'Funded ${formatPeso(e.spentAmount)}'
        : (e.note != null && e.note!.isNotEmpty
            ? e.note
            : (accountName != null ? 'Fund from $accountName' : null));
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
      onAction: e.isPaid ? null : () => _showMarkExpensePaidSheet(e),
      onEdit: () => _showAddBudgetedExpenseSheet(e),
      onDelete: () => _confirmDelete(
        title: 'Delete Budgeted Expense',
        body: 'Delete "${e.name}"?',
        onConfirm: () => widget.presenter.deleteBudgetedExpense(e.id),
      ),
    );
  }

  Widget _installmentsSection() {
    final installments = widget.installmentPresenter.dueThisMonth;
    return _Section(
      title: 'Installments',
      count: installments.length,
      emptyMessage: 'No installments due this month',
      children: [
        for (int i = 0; i < installments.length; i++)
          _cardPad(_installmentCard(installments[i])),
      ],
    );
  }

  Widget _installmentCard(Installment inst) {
    final paidThisMonth = widget.installmentPresenter.isPaidForMonth(inst.id);
    final count = widget.installmentPresenter.paidCount(inst.id);
    final dateLabel = paidThisMonth
        ? 'paid · $count/${inst.totalMonths}'
        : 'payment ${count + 1}/${inst.totalMonths}';
    final account = widget.installmentPresenter.accounts
        .where((a) => a.id == inst.accountId)
        .firstOrNull;
    return ObligationCard(
      key: ValueKey('inst_${inst.id}'),
      icon: Icons.credit_score_outlined,
      iconColor: context.appColors.purple,
      name: inst.name,
      note: account?.name,
      progress: widget.installmentPresenter.paymentProgress(inst.id),
      amount: inst.monthlyAmount,
      dateLabel: dateLabel,
      actionLabel: 'Pay',
      done: paidThisMonth,
      onAction:
          paidThisMonth ? null : () => _showMarkInstallmentPaidSheet(inst),
      onEdit: () => _showAddInstallmentSheet(inst),
      onDelete: () => _confirmDelete(
        title: 'Delete Installment',
        body:
            'Delete "${inst.name}"? All linked payment transactions will also be removed.',
        onConfirm: () => widget.installmentPresenter.deleteInstallment(inst.id),
      ),
    );
  }

  Widget _cardPad(Widget child) =>
      Padding(padding: const EdgeInsets.only(bottom: 8), child: child);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable:
          Listenable.merge([widget.presenter, widget.installmentPresenter]),
      builder: (context, _) {
        final imminent = widget.presenter.imminentUnpaidBills;
        final comingUp =
            widget.presenter.comingUpItems(widget.installmentPresenter);
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _BillsHeader(
                  monthKey: widget.presenter.selectedMonth,
                  onMonthChanged: _setMonth,
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    children: [
                      DueSoonStack(
                        presenter: widget.presenter,
                        onMarkPaid: _showMarkBillPaidSheet,
                        onEdit: _showAddBillSheet,
                      ),
                      if (imminent.isNotEmpty) const SizedBox(height: 16),
                      _StatChips(
                        presenter: widget.presenter,
                        installmentPresenter: widget.installmentPresenter,
                      ),
                      if (comingUp.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const _SectionLabel('Coming up'),
                        const SizedBox(height: 10),
                        ComingUpTimeline(
                            items: comingUp, onTap: _onComingUpTap),
                      ],
                      const SizedBox(height: 20),
                      _billsSection(),
                      const SizedBox(height: 18),
                      _receivablesSection(),
                      const SizedBox(height: 18),
                      _budgetedSection(),
                      const SizedBox(height: 18),
                      _installmentsSection(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: _showFabMenu,
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }
}

// ─── In-page header ───────────────────────────────────────────────────────────

/// The in-page Bills header — a large left-aligned "Bills" title with the
/// month·year picker on the right. Replaces the shared Treasury app bar, which
/// is hidden on this tab so the reference's header layout can show.
class _BillsHeader extends StatelessWidget {
  final String monthKey;
  final ValueChanged<String> onMonthChanged;

  const _BillsHeader({required this.monthKey, required this.onMonthChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Bills',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          MonthYearPill(monthKey: monthKey, onChanged: onMonthChanged),
        ],
      ),
    );
  }
}

// ─── Section scaffolding ──────────────────────────────────────────────────────

/// A plain bold section label (e.g. "Coming up").
class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 15,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

/// A titled list section: bold title + count, then its cards (or an empty note).
class _Section extends StatelessWidget {
  final String title;
  final int count;
  final String emptyMessage;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.count,
    required this.emptyMessage,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 2),
          child: Row(
            children: [
              _SectionLabel(title),
              if (count > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '$count',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (children.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 4),
            child: Text(
              emptyMessage,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
            ),
          )
        else
          ...children,
      ],
    );
  }
}

// ─── Stat chips (Pending / Paid / Installments) ───────────────────────────────

class _StatChips extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final InstallmentPresenter installmentPresenter;

  const _StatChips(
      {required this.presenter, required this.installmentPresenter});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        _StatChip(
          label: 'Pending',
          value: formatPesoCompact(presenter.totalBillsPending),
          color: colorScheme.error,
        ),
        const SizedBox(width: 8),
        _StatChip(
          label: 'Paid',
          value: formatPesoCompact(presenter.totalBillsPaid),
          color: context.appColors.success,
        ),
        const SizedBox(width: 8),
        _StatChip(
          label: 'Installments',
          value: formatPesoCompact(installmentPresenter.totalDueThisMonth),
          color: colorScheme.primary,
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 11),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 1),
            Text(label,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

// ─── Mark Bill Paid Sheet ─────────────────────────────────────────────────────

class _MarkBillPaidSheet extends StatefulWidget {
  final Bill bill;
  final BillsReceivablesPresenter presenter;

  const _MarkBillPaidSheet({required this.bill, required this.presenter});

  @override
  State<_MarkBillPaidSheet> createState() => _MarkBillPaidSheetState();
}

class _MarkBillPaidSheetState extends State<_MarkBillPaidSheet> {
  final _amountController = TextEditingController();
  String? _selectedAccountId;
  DateTime _paidDate = DateTime.now();
  bool _isSubmitting = false;
  // When true the user already logged this expense in the ledger, so marking
  // paid should NOT create a transaction or debit an account.
  bool _alreadyInLedger = false;

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.bill.amount.toStringAsFixed(2);
    // For CC/liability bills, restrict payer to non-liability accounts.
    final payers = widget.presenter.payerAccountsFor(widget.bill);
    final preferred = widget.bill.accountId;
    if (preferred != null && payers.any((a) => a.id == preferred)) {
      _selectedAccountId = preferred;
    } else if (payers.isNotEmpty) {
      _selectedAccountId = payers.first.id;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _paidDate = picked);
  }

  Future<void> _confirm() async {
    final amount = double.tryParse(_amountController.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) return;
    // An account is only needed when we're recording the payment in the ledger.
    if (!_alreadyInLedger && _selectedAccountId == null) return;
    setState(() => _isSubmitting = true);
    try {
      await widget.presenter.markBillPaid(
        widget.bill.id,
        paidAmount: amount,
        accountId: _alreadyInLedger ? null : _selectedAccountId,
        paidDate: _paidDate,
        recordInLedger: !_alreadyInLedger,
      );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mark Paid — ${widget.bill.name}',
                style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            AppTextField(
              controller: _amountController,
              label: 'Amount Paid',
              prefix: const Text('₱ '),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              value: _alreadyInLedger,
              onChanged: (v) => setState(() => _alreadyInLedger = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Already added to ledger'),
              subtitle: const Text(
                  "Just mark it paid — don't record a transaction or debit an account."),
            ),
            if (!_alreadyInLedger) ...[
              const SizedBox(height: 12),
              Builder(builder: (context) {
                final payers = widget.presenter.payerAccountsFor(widget.bill);
                if (payers.isEmpty) return const SizedBox.shrink();
                return DropdownButtonFormField<String>(
                  key: ValueKey(_selectedAccountId),
                  initialValue: _selectedAccountId,
                  decoration: sheetFieldDecoration(context, label: 'Pay from'),
                  items: payers
                      .map((a) =>
                          DropdownMenuItem(value: a.id, child: Text(a.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedAccountId = v),
                );
              }),
            ],
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        color: colorScheme.onSurfaceVariant, size: 18),
                    const SizedBox(width: 12),
                    Text(DateFormat('MMMM d, yyyy').format(_paidDate),
                        style: TextStyle(
                            color: colorScheme.onSurface, fontSize: 14)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            AppPrimaryButton(
              label: 'Confirm Payment',
              onPressed: _isSubmitting ? null : _confirm,
              isLoading: _isSubmitting,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─── Mark Received Sheet ──────────────────────────────────────────────────────

class _MarkReceivedSheet extends StatefulWidget {
  final Receivable receivable;
  final BillsReceivablesPresenter presenter;

  const _MarkReceivedSheet({required this.receivable, required this.presenter});

  @override
  State<_MarkReceivedSheet> createState() => _MarkReceivedSheetState();
}

class _MarkReceivedSheetState extends State<_MarkReceivedSheet> {
  final _amountController = TextEditingController();
  String? _selectedAccountId;
  DateTime _receivedDate = DateTime.now();
  bool _isSubmitting = false;
  // When true the user already logged this income in the ledger, so marking
  // received should NOT create a transaction or credit an account.
  bool _alreadyInLedger = false;

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.receivable.amount.toStringAsFixed(2);
    // Prefer the receivable's saved destination account; fall back to first
    // account when none was set at creation time.
    final preferred = widget.receivable.accountId;
    final accounts = widget.presenter.accounts;
    if (preferred != null && accounts.any((a) => a.id == preferred)) {
      _selectedAccountId = preferred;
    } else if (accounts.isNotEmpty) {
      _selectedAccountId = accounts.first.id;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _receivedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _receivedDate = picked);
  }

  Future<void> _confirm() async {
    final amount = double.tryParse(_amountController.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) return;
    // An account is only needed when we're recording the receipt in the ledger.
    if (!_alreadyInLedger && _selectedAccountId == null) return;
    setState(() => _isSubmitting = true);
    try {
      await widget.presenter.markReceivableReceived(
        widget.receivable.id,
        receivedAmount: amount,
        accountId: _alreadyInLedger ? null : _selectedAccountId,
        receivedDate: _receivedDate,
        recordInLedger: !_alreadyInLedger,
      );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mark Received — ${widget.receivable.name}',
                style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            AppTextField(
              controller: _amountController,
              label: 'Amount Received',
              prefix: const Text('₱ '),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              value: _alreadyInLedger,
              onChanged: (v) => setState(() => _alreadyInLedger = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Already added to ledger'),
              subtitle: const Text(
                  "Just mark it received — don't record a transaction or credit an account."),
            ),
            if (!_alreadyInLedger && widget.presenter.accounts.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedAccountId,
                decoration: sheetFieldDecoration(context, label: 'Account'),
                items: widget.presenter.accounts
                    .map((a) =>
                        DropdownMenuItem(value: a.id, child: Text(a.name)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedAccountId = v),
              ),
            ],
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        color: colorScheme.onSurfaceVariant, size: 18),
                    const SizedBox(width: 12),
                    Text(DateFormat('MMMM d, yyyy').format(_receivedDate),
                        style: TextStyle(
                            color: colorScheme.onSurface, fontSize: 14)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            AppPrimaryButton(
              label: 'Confirm Receipt',
              onPressed: _isSubmitting ? null : _confirm,
              isLoading: _isSubmitting,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─── Mark Expense Paid Sheet ──────────────────────────────────────────────────

class _MarkExpensePaidSheet extends StatefulWidget {
  final BudgetedExpense expense;
  final BillsReceivablesPresenter presenter;

  const _MarkExpensePaidSheet({required this.expense, required this.presenter});

  @override
  State<_MarkExpensePaidSheet> createState() => _MarkExpensePaidSheetState();
}

class _MarkExpensePaidSheetState extends State<_MarkExpensePaidSheet> {
  final _amountController = TextEditingController();
  String? _selectedAccountId;
  String? _selectedToAccountId;
  DateTime _paidDate = DateTime.now();
  bool _isSubmitting = false;

  /// Asset accounts money can be set aside into (savings/goals first), used to
  /// populate the "Set aside into" transfer destination.
  List<FinancialAccount> get _destinations {
    final list = widget.presenter.accounts
        .where((a) => a.isActive && !a.isLiability)
        .toList()
      ..sort((a, b) {
        int rank(FinancialAccount x) => switch (x.category) {
              AccountCategory.savings => 0,
              AccountCategory.goal => 1,
              AccountCategory.timeDeposit => 2,
              AccountCategory.investment => 3,
              _ => 4,
            };
        return rank(a).compareTo(rank(b));
      });
    return list;
  }

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.expense.allocatedAmount.toStringAsFixed(2);
    // Default to the account the set-aside is assigned to, falling back to the
    // first account when none is set (or it no longer exists).
    final accounts = widget.presenter.accounts;
    final assigned = widget.expense.accountId;
    _selectedAccountId =
        assigned != null && accounts.any((a) => a.id == assigned)
            ? assigned
            : (accounts.isNotEmpty ? accounts.first.id : null);
    // Destination defaults to the first savings/goal asset that isn't the
    // source; null means "spend it" (plain outflow, no transfer).
    _selectedToAccountId = _destinations
        .where((a) => a.id != _selectedAccountId)
        .map((a) => a.id)
        .firstOrNull;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _paidDate = picked);
  }

  Future<void> _confirm() async {
    final amount = double.tryParse(_amountController.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) return;
    if (_selectedAccountId == null) return;
    setState(() => _isSubmitting = true);
    try {
      await widget.presenter.markExpensePaid(
        widget.expense.id,
        paidAmount: amount,
        accountId: _selectedAccountId!,
        toAccountId: _selectedToAccountId,
        paidDate: _paidDate,
      );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mark Paid — ${widget.expense.name}',
                style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            AppTextField(
              controller: _amountController,
              label: 'Amount Paid',
              prefix: const Text('₱ '),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            if (widget.presenter.accounts.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedAccountId,
                decoration: sheetFieldDecoration(context, label: 'Fund from'),
                items: widget.presenter.accounts
                    .map((a) =>
                        DropdownMenuItem(value: a.id, child: Text(a.name)))
                    .toList(),
                onChanged: (v) => setState(() {
                  _selectedAccountId = v;
                  if (_selectedToAccountId == v) {
                    _selectedToAccountId = null; // can't transfer to itself
                  }
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedToAccountId,
                decoration:
                    sheetFieldDecoration(context, label: 'Set aside into'),
                items: [
                  const DropdownMenuItem<String>(
                      value: null, child: Text('Spend it (no transfer)')),
                  for (final a in _destinations)
                    if (a.id != _selectedAccountId)
                      DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) => setState(() => _selectedToAccountId = v),
              ),
            ],
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        color: colorScheme.onSurfaceVariant, size: 18),
                    const SizedBox(width: 12),
                    Text(DateFormat('MMMM d, yyyy').format(_paidDate),
                        style: TextStyle(
                            color: colorScheme.onSurface, fontSize: 14)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            AppPrimaryButton(
              label: 'Confirm Payment',
              onPressed: _isSubmitting ? null : _confirm,
              isLoading: _isSubmitting,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─── Add Budgeted Expense Sheet ───────────────────────────────────────────────

class _AddBudgetedExpenseSheet extends StatefulWidget {
  final BillsReceivablesPresenter presenter;
  final BudgetedExpense? existing;

  const _AddBudgetedExpenseSheet({required this.presenter, this.existing});

  @override
  State<_AddBudgetedExpenseSheet> createState() =>
      _AddBudgetedExpenseSheetState();
}

class _AddBudgetedExpenseSheetState extends State<_AddBudgetedExpenseSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  SetAsideType _budgetedType = SetAsideType.other;
  String? _selectedCategoryId;
  String? _selectedAccountId;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameController.text = e.name;
      _amountController.text = e.allocatedAmount.toStringAsFixed(2);
      _noteController.text = e.note ?? '';
      _budgetedType = e.budgetedType;
      _selectedCategoryId = e.categoryId.isEmpty ? null : e.categoryId;
      _selectedAccountId = e.accountId;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final amount = double.parse(_amountController.text.replaceAll(',', ''));
      final id = widget.existing?.id ??
          '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';
      final expense = BudgetedExpense(
        id: id,
        name: _nameController.text.trim(),
        budgetedType: _budgetedType,
        month: widget.presenter.selectedMonth,
        allocatedAmount: amount,
        categoryId: _selectedCategoryId ?? '',
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        accountId: _selectedAccountId,
      );
      if (widget.existing != null) {
        await widget.presenter.updateBudgetedExpense(expense);
      } else {
        await widget.presenter.addBudgetedExpense(expense);
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final expenseCategories = widget.presenter.categories
        .where((c) => c.type == CategoryType.expense)
        .toList();
    // Only liquid accounts can fund a set-aside — funding it later debits one.
    final liquidAccounts = widget.presenter.accounts
        .where((a) => a.isActive && a.isLiquid)
        .toList();

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.existing != null
                    ? 'Edit Budgeted Expense'
                    : 'Add Budgeted Expense',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: sheetFieldDecoration(context, label: 'Name'),
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountController,
                decoration: sheetFieldDecoration(context,
                    label: 'Allocated Amount',
                    prefixText: '₱ ',
                    emphasize: true),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                validator: (v) {
                  final p = double.tryParse(v ?? '');
                  if (p == null || p <= 0) return 'Must be > 0';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<SetAsideType>(
                initialValue: _budgetedType,
                decoration: sheetFieldDecoration(context, label: 'Type'),
                items: SetAsideType.values
                    .map(
                        (t) => DropdownMenuItem(value: t, child: Text(t.label)))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _budgetedType = v ?? _budgetedType),
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _noteController,
                label: 'Note (optional)',
                textInputAction: TextInputAction.done,
              ),
              if (liquidAccounts.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue:
                      liquidAccounts.any((a) => a.id == _selectedAccountId)
                          ? _selectedAccountId
                          : null,
                  decoration: const InputDecoration(
                      labelText: 'Fund from account (optional)'),
                  items: [
                    const DropdownMenuItem<String>(
                        value: null, child: Text('None')),
                    for (final a in liquidAccounts)
                      DropdownMenuItem(value: a.id, child: Text(a.name)),
                  ],
                  onChanged: (v) => setState(() => _selectedAccountId = v),
                ),
              ],
              if (expenseCategories.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Category',
                    style: TextStyle(
                        color: colorScheme.onSurfaceVariant, fontSize: 12)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: expenseCategories.map((cat) {
                    final isSelected = _selectedCategoryId == cat.id;
                    return ChoiceChip(
                      label: Text(cat.name),
                      selected: isSelected,
                      onSelected: (_) =>
                          setState(() => _selectedCategoryId = cat.id),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 20),
              AppPrimaryButton(
                label: widget.existing != null ? 'Save' : 'Add Expense',
                onPressed: _isSubmitting ? null : _submit,
                isLoading: _isSubmitting,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Mark Installment Paid Sheet ──────────────────────────────────────────────

class _MarkInstallmentPaidSheet extends StatefulWidget {
  final Installment installment;
  final InstallmentPresenter presenter;

  const _MarkInstallmentPaidSheet({
    required this.installment,
    required this.presenter,
  });

  @override
  State<_MarkInstallmentPaidSheet> createState() =>
      _MarkInstallmentPaidSheetState();
}

class _MarkInstallmentPaidSheetState extends State<_MarkInstallmentPaidSheet> {
  late final TextEditingController _amountCtrl;
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(
        text: widget.installment.monthlyAmount.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) return;
    setState(() => _saving = true);
    await widget.presenter.markPaid(
      widget.installment.id,
      overrideAmount: amount,
      date: _date,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final count = widget.presenter.paidCount(widget.installment.id) + 1;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Mark Payment $count/${widget.installment.totalMonths}',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                widget.installment.name,
                style: TextStyle(
                    color: colorScheme.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 20),
              Text('Amount',
                  style: TextStyle(
                      color: colorScheme.onSurfaceVariant, fontSize: 12)),
              const SizedBox(height: 6),
              AppTextField(
                controller: _amountCtrl,
                prefix: const Text('₱ '),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Date',
                    style: TextStyle(
                        color: colorScheme.onSurfaceVariant, fontSize: 12)),
                subtitle: Text(
                  '${_date.day}/${_date.month}/${_date.year}',
                  style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w500),
                ),
                trailing: Icon(Icons.calendar_today_outlined,
                    color: colorScheme.primary, size: 18),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
              ),
              const SizedBox(height: 20),
              AppPrimaryButton(
                label: 'Confirm Payment',
                onPressed: _saving ? null : _confirm,
                isLoading: _saving,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
