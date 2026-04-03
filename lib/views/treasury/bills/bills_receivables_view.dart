import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_bill_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_receivable_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/bill_list_tile.dart';
import 'package:intermittent_fasting/views/treasury/bills/budgeted_expense_tile.dart';
import 'package:intermittent_fasting/views/treasury/bills/receivable_list_tile.dart';

class BillsReceivablesView extends StatefulWidget {
  final BillsReceivablesPresenter presenter;

  const BillsReceivablesView({super.key, required this.presenter});

  @override
  State<BillsReceivablesView> createState() => _BillsReceivablesViewState();
}

class _BillsReceivablesViewState extends State<BillsReceivablesView> {
  @override
  void initState() {
    super.initState();
    widget.presenter.load();
  }

  void _showAddBillSheet([Bill? existing]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) =>
          AddBillSheet(presenter: widget.presenter, existing: existing),
    );
  }

  void _showAddReceivableSheet([Receivable? existing]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => AddReceivableSheet(
          presenter: widget.presenter, existing: existing),
    );
  }

  void _showAddBudgetedExpenseSheet([BudgetedExpense? existing]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) =>
          _AddBudgetedExpenseSheet(presenter: widget.presenter, existing: existing),
    );
  }

  void _showMarkBillPaidSheet(Bill bill) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _MarkBillPaidSheet(bill: bill, presenter: widget.presenter),
    );
  }

  void _showMarkReceivedSheet(Receivable receivable) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) =>
          _MarkReceivedSheet(receivable: receivable, presenter: widget.presenter),
    );
  }

  void _showMarkExpensePaidSheet(BudgetedExpense expense) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) =>
          _MarkExpensePaidSheet(expense: expense, presenter: widget.presenter),
    );
  }

  void _showFabMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.receipt_long_outlined, color: AppColors.accent),
              title: Text('Add Bill',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                _showAddBillSheet();
              },
            ),
            ListTile(
              leading: Icon(Icons.attach_money, color: AppColors.success),
              title: Text('Add Receivable',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                _showAddReceivableSheet();
              },
            ),
            ListTile(
              leading: Icon(Icons.savings_outlined, color: AppColors.gold),
              title: Text('Add Budgeted Expense',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                _showAddBudgetedExpenseSheet();
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
      listenable: widget.presenter,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: AppColors.background,
          body: Column(
            children: [
              _MonthSelector(presenter: widget.presenter),
              _StatsBar(presenter: widget.presenter),
              Expanded(
                child: ListView(
                  children: [
                    _BillsSection(
                      presenter: widget.presenter,
                      onMarkPaid: _showMarkBillPaidSheet,
                      onEdit: _showAddBillSheet,
                    ),
                    _ReceivablesSection(
                      presenter: widget.presenter,
                      onMarkReceived: _showMarkReceivedSheet,
                      onEdit: _showAddReceivableSheet,
                    ),
                    _BudgetedExpensesSection(
                      presenter: widget.presenter,
                      onMarkPaid: _showMarkExpensePaidSheet,
                      onEdit: _showAddBudgetedExpenseSheet,
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: _showFabMenu,
            backgroundColor: AppColors.accent,
            foregroundColor: AppColors.background,
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }
}

// ─── Month Selector ───────────────────────────────────────────────────────────

class _MonthSelector extends StatelessWidget {
  final BillsReceivablesPresenter presenter;

  const _MonthSelector({required this.presenter});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              icon: Icon(Icons.chevron_left, color: AppColors.textSecondary),
              onPressed: () =>
                  presenter.setMonth(previousMonth(presenter.selectedMonth)),
            ),
          ),
          Text(
            monthLabel(presenter.selectedMonth),
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              icon: Icon(Icons.chevron_right, color: AppColors.textSecondary),
              onPressed: () =>
                  presenter.setMonth(nextMonth(presenter.selectedMonth)),
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

  const _StatsBar({required this.presenter});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          _StatChip(
            label: 'Pending',
            value: formatPesoCompact(presenter.totalBillsPending),
            color: AppColors.danger,
          ),
          const SizedBox(width: 8),
          _StatChip(
            label: 'Paid',
            value: formatPesoCompact(presenter.totalBillsPaid),
            color: AppColors.success,
          ),
          const SizedBox(width: 8),
          _StatChip(
            label: 'Receivables',
            value: formatPesoCompact(presenter.totalReceivablesAmount),
            color: AppColors.accent,
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
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
            Text(label,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 10)),
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
    final bills = presenter.bills;
    final paidCount = bills.where((b) => b.isPaid).length;
    return _SectionCard(
      title: 'BILLS',
      count: bills.length,
      subtitle: '$paidCount/${bills.length} paid',
      accentColor: AppColors.danger,
      initiallyExpanded: true,
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
      title: 'RECEIVABLES',
      count: receivables.length,
      subtitle: '$receivedCount/${receivables.length} received',
      accentColor: AppColors.success,
      initiallyExpanded: true,
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
      accentColor: AppColors.gold,
      initiallyExpanded: false,
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

// ─── Section Card (expandable) ────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final int count;
  final String subtitle;
  final Color accentColor;
  final bool initiallyExpanded;
  final String emptyMessage;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.count,
    required this.subtitle,
    required this.accentColor,
    required this.initiallyExpanded,
    required this.emptyMessage,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withOpacity(0.2)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
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
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                      color: accentColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Text(
              subtitle,
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 11),
            ),
          ),
          iconColor: AppColors.textSecondary,
          collapsedIconColor: AppColors.textSecondary,
          children: children.isEmpty
              ? [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                    child: Text(
                      emptyMessage,
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                    ),
                  )
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

  const _MarkBillPaidSheet(
      {required this.bill, required this.presenter});

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
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(primary: AppColors.accent),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _paidDate = picked);
  }

  Future<void> _confirm() async {
    final amount =
        double.tryParse(_amountController.text.replaceAll(',', ''));
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
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
              ],
              style: TextStyle(color: AppColors.textPrimary),
              decoration: _inputDec('Amount Paid', prefix: '₱ '),
            ),
            if (widget.presenter.accounts.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedAccountId,
                dropdownColor: AppColors.surface,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: _inputDec('Account'),
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
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.textSecondary.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        color: AppColors.textSecondary, size: 18),
                    const SizedBox(width: 12),
                    Text(DateFormat('MMMM d, yyyy').format(_paidDate),
                        style: TextStyle(
                            color: AppColors.textPrimary, fontSize: 14)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: AppColors.background,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Confirm Payment',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDec(String label, {String? prefix}) => InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.textSecondary),
        prefixText: prefix,
        prefixStyle: TextStyle(color: AppColors.accent),
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              BorderSide(color: AppColors.textSecondary.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.accent),
        ),
      );
}

// ─── Mark Received Sheet ──────────────────────────────────────────────────────

class _MarkReceivedSheet extends StatefulWidget {
  final Receivable receivable;
  final BillsReceivablesPresenter presenter;

  const _MarkReceivedSheet(
      {required this.receivable, required this.presenter});

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
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(primary: AppColors.success),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _receivedDate = picked);
  }

  Future<void> _confirm() async {
    final amount =
        double.tryParse(_amountController.text.replaceAll(',', ''));
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
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
              ],
              style: TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Amount Received',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                prefixText: '₱ ',
                prefixStyle: TextStyle(color: AppColors.success),
                filled: true,
                fillColor: AppColors.background,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                      color: AppColors.textSecondary.withOpacity(0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.success),
                ),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.textSecondary.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        color: AppColors.textSecondary, size: 18),
                    const SizedBox(width: 12),
                    Text(DateFormat('MMMM d, yyyy').format(_receivedDate),
                        style: TextStyle(
                            color: AppColors.textPrimary, fontSize: 14)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: AppColors.background,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Confirm Receipt',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
              ),
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

  const _MarkExpensePaidSheet(
      {required this.expense, required this.presenter});

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
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(primary: AppColors.accent),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _paidDate = picked);
  }

  Future<void> _confirm() async {
    final amount =
        double.tryParse(_amountController.text.replaceAll(',', ''));
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
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
              ],
              style: TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Amount Paid',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                prefixText: '₱ ',
                prefixStyle: TextStyle(color: AppColors.accent),
                filled: true,
                fillColor: AppColors.background,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                      color: AppColors.textSecondary.withOpacity(0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.accent),
                ),
              ),
            ),
            if (widget.presenter.accounts.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedAccountId,
                dropdownColor: AppColors.surface,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Account',
                  labelStyle: TextStyle(color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: AppColors.textSecondary.withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppColors.accent),
                  ),
                ),
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
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.textSecondary.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        color: AppColors.textSecondary, size: 18),
                    const SizedBox(width: 12),
                    Text(DateFormat('MMMM d, yyyy').format(_paidDate),
                        style: TextStyle(
                            color: AppColors.textPrimary, fontSize: 14)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: AppColors.background,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Confirm Payment',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
              ),
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

  const _AddBudgetedExpenseSheet(
      {required this.presenter, this.existing});

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
      final amount =
          double.parse(_amountController.text.replaceAll(',', ''));
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

  InputDecoration _inputDec(String label, {String? prefix}) => InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.textSecondary),
        prefixText: prefix,
        prefixStyle: TextStyle(color: AppColors.gold),
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              BorderSide(color: AppColors.textSecondary.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.gold),
        ),
      );

  @override
  Widget build(BuildContext context) {
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
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                style: TextStyle(color: AppColors.textPrimary),
                decoration: _inputDec('Name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                ],
                style: TextStyle(color: AppColors.textPrimary),
                decoration: _inputDec('Allocated Amount', prefix: '₱ '),
                validator: (v) {
                  final p = double.tryParse(v ?? '');
                  if (p == null || p <= 0) return 'Must be > 0';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteController,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: _inputDec('Note (optional)'),
              ),
              if (expenseCategories.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Category',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: expenseCategories.map((cat) {
                    final isSelected = _selectedCategoryId == cat.id;
                    return ChoiceChip(
                      label: Text(cat.name),
                      selected: isSelected,
                      selectedColor: AppColors.gold.withOpacity(0.2),
                      labelStyle: TextStyle(
                        color: isSelected
                            ? AppColors.gold
                            : AppColors.textSecondary,
                        fontSize: 12,
                      ),
                      backgroundColor: AppColors.surface,
                      side: BorderSide(
                          color: isSelected
                              ? AppColors.gold
                              : AppColors.textSecondary.withOpacity(0.3)),
                      onSelected: (_) =>
                          setState(() => _selectedCategoryId = cat.id),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.background,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          widget.existing != null
                              ? 'Save'
                              : 'Add Expense',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
