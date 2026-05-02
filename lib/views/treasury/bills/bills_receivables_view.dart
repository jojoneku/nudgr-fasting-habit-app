import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_bill_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_installment_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_receivable_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/bill_list_tile.dart';
import 'package:intermittent_fasting/views/treasury/bills/budgeted_expense_tile.dart';
import 'package:intermittent_fasting/views/treasury/bills/installment_list_tile.dart';
import 'package:intermittent_fasting/views/treasury/bills/receivable_list_tile.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

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

  void _setMonth(String month) {
    widget.presenter.setMonth(month);
    widget.installmentPresenter.setMonth(month);
  }

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
              leading: Icon(Icons.attach_money, color: const Color(0xFF4CAF50)),
              title: const Text('Add Receivable'),
              onTap: () {
                Navigator.pop(context);
                _showAddReceivableSheet();
              },
            ),
            ListTile(
              leading:
                  Icon(Icons.savings_outlined, color: const Color(0xFFFFB300)),
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable:
          Listenable.merge([widget.presenter, widget.installmentPresenter]),
      builder: (context, _) {
        return Scaffold(
          body: Column(
            children: [
              _MonthSelector(
                selectedMonth: widget.presenter.selectedMonth,
                onChanged: _setMonth,
              ),
              _StatsBar(
                presenter: widget.presenter,
                installmentPresenter: widget.installmentPresenter,
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    const SizedBox(height: 12),
                    _BillsSection(
                      presenter: widget.presenter,
                      onMarkPaid: _showMarkBillPaidSheet,
                      onEdit: _showAddBillSheet,
                    ),
                    const SizedBox(height: 12),
                    _ReceivablesSection(
                      presenter: widget.presenter,
                      onMarkReceived: _showMarkReceivedSheet,
                      onEdit: _showAddReceivableSheet,
                    ),
                    const SizedBox(height: 12),
                    _BudgetedExpensesSection(
                      presenter: widget.presenter,
                      onMarkPaid: _showMarkExpensePaidSheet,
                      onEdit: _showAddBudgetedExpenseSheet,
                    ),
                    const SizedBox(height: 12),
                    _InstallmentsSection(
                      presenter: widget.installmentPresenter,
                      onMarkPaid: _showMarkInstallmentPaidSheet,
                      onEdit: _showAddInstallmentSheet,
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ],
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

// ─── Month Selector ───────────────────────────────────────────────────────────

class _MonthSelector extends StatelessWidget {
  final String selectedMonth;
  final ValueChanged<String> onChanged;

  const _MonthSelector({required this.selectedMonth, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              icon:
                  Icon(Icons.chevron_left, color: colorScheme.onSurfaceVariant),
              onPressed: () => onChanged(previousMonth(selectedMonth)),
            ),
          ),
          Text(
            monthLabel(selectedMonth),
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              icon: Icon(Icons.chevron_right,
                  color: colorScheme.onSurfaceVariant),
              onPressed: () => onChanged(nextMonth(selectedMonth)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Stats Bar ────────────────────────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final InstallmentPresenter installmentPresenter;

  const _StatsBar(
      {required this.presenter, required this.installmentPresenter});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
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
            color: const Color(0xFF4CAF50),
          ),
          const SizedBox(width: 8),
          _StatChip(
            label: 'Installments',
            value: formatPesoCompact(installmentPresenter.totalDueThisMonth),
            color: colorScheme.primary,
          ),
        ],
      ),
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
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700, fontSize: 13)),
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

// ─── Bills Section ────────────────────────────────────────────────────────────

class _BillsSection extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final ValueChanged<Bill> onMarkPaid;
  final ValueChanged<Bill> onEdit;

  const _BillsSection({
    required this.presenter,
    required this.onMarkPaid,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bills = presenter.bills;
    final paidCount = bills.where((b) => b.isPaid).length;

    return _SectionCard(
      title: 'Bills',
      count: bills.length,
      subtitle: '$paidCount/${bills.length} paid',
      accentColor: colorScheme.error,
      initiallyExpanded: true,
      emptyIcon: Icons.receipt_outlined,
      emptyMessage: 'No bills for this month',
      children: bills
          .map((bill) => BillListTile(
                key: ValueKey(bill.id),
                bill: bill,
                onMarkPaid: () => onMarkPaid(bill),
                onEdit: () => onEdit(bill),
                onDelete: () => presenter.deleteBill(bill.id),
              ))
          .toList(),
    );
  }
}

// ─── Receivables Section ──────────────────────────────────────────────────────

class _ReceivablesSection extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final ValueChanged<Receivable> onMarkReceived;
  final ValueChanged<Receivable> onEdit;

  const _ReceivablesSection({
    required this.presenter,
    required this.onMarkReceived,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final receivables = presenter.receivables;
    final receivedCount = receivables.where((r) => r.isReceived).length;

    return _SectionCard(
      title: 'Receivables',
      count: receivables.length,
      subtitle: '$receivedCount/${receivables.length} received',
      accentColor: const Color(0xFF4CAF50),
      initiallyExpanded: true,
      emptyIcon: Icons.account_balance_wallet_outlined,
      emptyMessage: 'No receivables for this month',
      children: receivables
          .map((r) => ReceivableListTile(
                key: ValueKey(r.id),
                receivable: r,
                onMarkReceived: () => onMarkReceived(r),
                onDelete: () => presenter.deleteReceivable(r.id),
              ))
          .toList(),
    );
  }
}

// ─── Budgeted Expenses Section ────────────────────────────────────────────────

class _BudgetedExpensesSection extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final ValueChanged<BudgetedExpense> onMarkPaid;
  final ValueChanged<BudgetedExpense> onEdit;

  const _BudgetedExpensesSection({
    required this.presenter,
    required this.onMarkPaid,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final expenses = presenter.budgetedExpenses;
    final paidCount = expenses.where((e) => e.isPaid).length;

    return _SectionCard(
      title: 'BUDGETED EXPENSES',
      count: expenses.length,
      subtitle: '$paidCount/${expenses.length} paid',
      accentColor: const Color(0xFFFFB300),
      initiallyExpanded: false,
      emptyIcon: Icons.savings_outlined,
      emptyMessage: 'No budgeted expenses for this month',
      children: expenses
          .map((e) => BudgetedExpenseTile(
                key: ValueKey(e.id),
                expense: e,
                onMarkPaid: () => onMarkPaid(e),
                onDelete: () => presenter.deleteBudgetedExpense(e.id),
              ))
          .toList(),
    );
  }
}

// ─── Installments Section ─────────────────────────────────────────────────────

class _InstallmentsSection extends StatelessWidget {
  final InstallmentPresenter presenter;
  final ValueChanged<Installment> onMarkPaid;
  final ValueChanged<Installment> onEdit;

  const _InstallmentsSection({
    required this.presenter,
    required this.onMarkPaid,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final installments = presenter.dueThisMonth;
    final paidCount =
        installments.where((i) => presenter.isPaidForMonth(i.id)).length;
    final subtitle = installments.isEmpty
        ? 'None due this month'
        : '$paidCount/${installments.length} paid · ${formatPeso(presenter.totalDueThisMonth)} due';

    return _SectionCard(
      title: 'Installments',
      count: installments.length,
      subtitle: subtitle,
      accentColor: const Color(0xFF9C27B0),
      initiallyExpanded: installments.isNotEmpty,
      emptyIcon: Icons.credit_score_outlined,
      emptyMessage: 'No installments due this month',
      children: installments.map((i) {
        final account =
            presenter.accounts.where((a) => a.id == i.accountId).firstOrNull;
        return InstallmentListTile(
          key: ValueKey(i.id),
          installment: i,
          presenter: presenter,
          account: account,
          onMarkPaid: () => onMarkPaid(i),
          onEdit: () => onEdit(i),
          onDelete: () => _confirmDelete(context, presenter, i),
        );
      }).toList(),
    );
  }

  void _confirmDelete(
    BuildContext context,
    InstallmentPresenter presenter,
    Installment installment,
  ) {
    AppConfirmDialog.confirm(
      context: context,
      title: 'Delete Installment',
      body:
          'Delete "${installment.name}"? All linked payment transactions will also be removed.',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      isDestructive: true,
    ).then((confirmed) {
      if (confirmed) presenter.deleteInstallment(installment.id);
    });
  }
}

// ─── Section Card (expandable) ────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final int count;
  final String subtitle;
  final Color accentColor;
  final bool initiallyExpanded;
  final IconData emptyIcon;
  final String emptyMessage;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.count,
    required this.subtitle,
    required this.accentColor,
    required this.initiallyExpanded,
    required this.emptyIcon,
    required this.emptyMessage,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      variant: AppCardVariant.outlined,
      padding: EdgeInsets.zero,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: EdgeInsets.zero,
          title: Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(width: 8),
              AppBadge(
                text: '$count',
                color: accentColor,
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Text(
              subtitle,
              style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant, fontSize: 11),
            ),
          ),
          iconColor: theme.colorScheme.onSurfaceVariant,
          collapsedIconColor: theme.colorScheme.onSurfaceVariant,
          children: children.isEmpty
              ? [
                  AppEmptyState(
                    icon: emptyIcon,
                    title: emptyMessage,
                    iconSize: 40,
                  ),
                ]
              : children,
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

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.bill.amount.toStringAsFixed(2);
    _selectedAccountId = widget.bill.accountId ??
        (widget.presenter.accounts.isNotEmpty
            ? widget.presenter.accounts.first.id
            : null);
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
      await widget.presenter.markBillPaid(
        widget.bill.id,
        paidAmount: amount,
        accountId: _selectedAccountId!,
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
            if (widget.presenter.accounts.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedAccountId,
                decoration: const InputDecoration(labelText: 'Account'),
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
  DateTime _receivedDate = DateTime.now();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.receivable.amount.toStringAsFixed(2);
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
    setState(() => _isSubmitting = true);
    try {
      await widget.presenter.markReceivableReceived(
        widget.receivable.id,
        receivedAmount: amount,
        receivedDate: _receivedDate,
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
  DateTime _paidDate = DateTime.now();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.expense.allocatedAmount.toStringAsFixed(2);
    _selectedAccountId = widget.presenter.accounts.isNotEmpty
        ? widget.presenter.accounts.first.id
        : null;
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
                value: _selectedAccountId,
                decoration: const InputDecoration(labelText: 'Account'),
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

  BillType _budgetedType = BillType.other;
  String? _selectedCategoryId;
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
                decoration: const InputDecoration(labelText: 'Name'),
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                    labelText: 'Allocated Amount', prefixText: '₱ '),
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
              AppTextField(
                controller: _noteController,
                label: 'Note (optional)',
                textInputAction: TextInputAction.done,
              ),
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
