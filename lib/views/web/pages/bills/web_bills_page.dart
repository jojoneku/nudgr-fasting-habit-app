import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/utils/app_radii.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../../widgets/web_widgets.dart';

/// Web Bills & Receivables page (Plan 050-C).
///
/// Desktop redesign of the mobile [BillsReceivablesView] following the Claude
/// Design reference (`docs/design/treasury-web-reference/screens/bills.png`).
/// Reads exclusively from the injected presenters — no fabricated getters.
class WebBillsPage extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final InstallmentPresenter installmentPresenter;

  const WebBillsPage({
    super.key,
    required this.presenter,
    required this.installmentPresenter,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // Installments surface as bills only via the presenter's auto-generated
      // statements, but we still listen so counts stay live if it reloads.
      listenable: Listenable.merge([presenter, installmentPresenter]),
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.all(WebInsets.xxl),
        child: _BillsBody(presenter: presenter),
      ),
    );
  }
}

// ─── Body ─────────────────────────────────────────────────────────────────────

class _BillsBody extends StatelessWidget {
  final BillsReceivablesPresenter presenter;

  const _BillsBody({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final bills = presenter.bills;
    final unpaid = [...bills.where((b) => !b.isPaid)]
      ..sort((a, b) => a.dueDay.compareTo(b.dueDay));
    final paid = [...bills.where((b) => b.isPaid)]
      ..sort((a, b) => a.dueDay.compareTo(b.dueDay));
    final receivables = presenter.receivables;
    final pendingReceivables = receivables.where((r) => !r.isReceived).toList();

    final dueTotal = presenter.totalBillsPending;
    final paidTotal = presenter.totalBillsPaid;
    // All bills for the month (paid + unpaid). Budgeted expenses are NOT
    // surfaced on this page — they're an obligation shown on the dashboard's
    // "Current Obligations", so mixing them in here was confusing.
    final monthTotal = presenter.totalBillsAmount;
    final receiveTotal =
        pendingReceivables.fold(0.0, (sum, r) => sum + r.amount);

    final children = <Widget>[
      _Header(
        monthLabel: monthLabel(presenter.selectedMonth),
        subtitle:
            '${monthLabel(presenter.selectedMonth)} · ${unpaid.length} bills due, ${pendingReceivables.length} to receive',
        onAddBill: () => _onAddBill(context),
        onPrevMonth: () =>
            presenter.setMonth(previousMonth(presenter.selectedMonth)),
        onNextMonth: () =>
            presenter.setMonth(nextMonth(presenter.selectedMonth)),
      ),
      const SizedBox(height: WebInsets.xl),
      _StatStrip(
        dueTotal: dueTotal,
        paidTotal: paidTotal,
        monthTotal: monthTotal,
        receiveTotal: receiveTotal,
        unpaidCount: unpaid.length,
        paidCount: paid.length,
        receivableCount: pendingReceivables.length,
      ),
      const SizedBox(height: WebInsets.xl),
    ];

    final upcomingCard = _UpcomingCard(
      presenter: presenter,
      unpaid: unpaid,
      dueTotal: dueTotal,
    );
    final receivablesCard = _ReceivablesCard(
      presenter: presenter,
      receivables: receivables,
      pendingTotal: receiveTotal,
    );
    final budgetedCard = _BudgetedExpensesCard(
      presenter: presenter,
      expenses: presenter.budgetedExpenses,
    );

    // One card per row, full-width
    // (Upcoming → Receivables → Budgeted set-asides → Paid).
    children
      ..add(upcomingCard)
      ..add(const SizedBox(height: WebInsets.xl))
      ..add(receivablesCard)
      ..add(const SizedBox(height: WebInsets.xl))
      ..add(budgetedCard);

    if (paid.isNotEmpty) {
      children
        ..add(const SizedBox(height: WebInsets.xl))
        ..add(
            _PaidCard(presenter: presenter, paid: paid, paidTotal: paidTotal));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  void _onAddBill(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _AddBillDialog(presenter: presenter),
    );
  }
}

// ─── Add-bill dialog ────────────────────────────────────────────────────────

/// Desktop add-bill form (Plan 050). Mirrors the mobile [AddBillSheet]'s core
/// single-bill case: Name, Bill Type, Amount, Due Day, Payment Account, and
/// (expense) Category, then calls [BillsReceivablesPresenter.addBill] with a
/// freshly built [Bill] keyed to `presenter.selectedMonth`.
///
// TODO(plan-050): The mobile sheet also supports a payment note and a recurring
// toggle (with recurrence type). Those advanced fields are intentionally
// omitted here to keep the web form focused on the common case.
class _AddBillDialog extends StatefulWidget {
  final BillsReceivablesPresenter presenter;

  /// When non-null the dialog edits this bill in place via [updateBill];
  /// otherwise it creates a new one via [addBill].
  final Bill? existing;

  const _AddBillDialog({required this.presenter, this.existing});

  @override
  State<_AddBillDialog> createState() => _AddBillDialogState();
}

class _AddBillDialogState extends State<_AddBillDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _dueDayController = TextEditingController();

  late BillType _billType;
  String? _selectedAccountId;
  String? _selectedCategoryId;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    _billType = b?.billType ?? BillType.other;
    if (b != null) {
      _nameController.text = b.name;
      _amountController.text = b.amount == b.amount.roundToDouble()
          ? b.amount.round().toString()
          : b.amount.toString();
      _dueDayController.text = b.dueDay.toString();
      _selectedAccountId = b.accountId;
      _selectedCategoryId = b.categoryId.isEmpty ? null : b.categoryId;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _dueDayController.dispose();
    super.dispose();
  }

  List<FinanceCategory> get _expenseCategories => widget.presenter.categories
      .where((c) => c.type == CategoryType.expense)
      .toList();

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isSubmitting = true);
    try {
      final amount = double.parse(_amountController.text.replaceAll(',', ''));
      final dueDay = int.parse(_dueDayController.text);
      final existing = widget.existing;
      if (existing == null) {
        final bill = Bill(
          id: '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}',
          name: _nameController.text.trim(),
          billType: _billType,
          amount: amount,
          dueDay: dueDay,
          month: widget.presenter.selectedMonth,
          categoryId: _selectedCategoryId ?? '',
          accountId: _selectedAccountId,
        );
        await widget.presenter.addBill(bill);
      } else {
        // Edit in place — copyWith preserves fields the form doesn't expose
        // (paymentNote, recurrence, paid state, linked transaction).
        await widget.presenter.updateBill(existing.copyWith(
          name: _nameController.text.trim(),
          billType: _billType,
          amount: amount,
          dueDay: dueDay,
          categoryId: _selectedCategoryId ?? '',
          accountId: _selectedAccountId,
        ));
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      // Previously a save failure left the dialog open with no message. (C7)
      messenger
          .showSnackBar(SnackBar(content: Text('Could not save bill: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accounts =
        widget.presenter.accounts.where((a) => a.isActive).toList();
    final categories = _expenseCategories;

    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Bill' : 'Add Bill'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Name'),
                  textInputAction: TextInputAction.next,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                ),
                const SizedBox(height: WebInsets.md),
                DropdownButtonFormField<BillType>(
                  initialValue: _billType,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: BillType.values
                      .map((t) => DropdownMenuItem(
                          value: t, child: Text(_billTypeFormLabel(t))))
                      .toList(),
                  onChanged: (v) => setState(() => _billType = v ?? _billType),
                ),
                const SizedBox(height: WebInsets.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _amountController,
                        decoration: const InputDecoration(
                            labelText: 'Amount', prefixText: '₱ '),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        textInputAction: TextInputAction.next,
                        validator: (v) {
                          final p =
                              double.tryParse((v ?? '').replaceAll(',', ''));
                          if (p == null || p <= 0) return 'Must be > 0';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: WebInsets.md),
                    Expanded(
                      child: TextFormField(
                        controller: _dueDayController,
                        decoration:
                            const InputDecoration(labelText: 'Due day (1–31)'),
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) =>
                            _submit(), // Enter submits (U6)
                        validator: (v) {
                          final d = int.tryParse(v ?? '');
                          if (d == null || d < 1 || d > 31) return '1–31';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                if (accounts.isNotEmpty) ...[
                  const SizedBox(height: WebInsets.md),
                  DropdownButtonFormField<String>(
                    // Guard against a stored account that is no longer active —
                    // a value absent from `items` would assert. (edit case)
                    initialValue:
                        accounts.any((a) => a.id == _selectedAccountId)
                            ? _selectedAccountId
                            : null,
                    decoration: const InputDecoration(
                        labelText: 'Payment account (optional)'),
                    items: [
                      const DropdownMenuItem<String>(
                          value: null, child: Text('None')),
                      for (final a in accounts)
                        DropdownMenuItem(value: a.id, child: Text(a.name)),
                    ],
                    onChanged: (v) => setState(() => _selectedAccountId = v),
                  ),
                ],
                if (categories.isNotEmpty) ...[
                  const SizedBox(height: WebInsets.md),
                  DropdownButtonFormField<String>(
                    initialValue:
                        categories.any((c) => c.id == _selectedCategoryId)
                            ? _selectedCategoryId
                            : null,
                    decoration:
                        const InputDecoration(labelText: 'Category (optional)'),
                    items: [
                      const DropdownMenuItem<String>(
                          value: null, child: Text('None')),
                      for (final c in categories)
                        DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => setState(() => _selectedCategoryId = v),
                  ),
                ],
                if (accounts.isEmpty && categories.isEmpty) ...[
                  const SizedBox(height: WebInsets.sm),
                  Text(
                    'Add an account or category in the app for richer bills.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEdit ? 'Save' : 'Add Bill'),
        ),
      ],
    );
  }
}

String _billTypeFormLabel(BillType type) => switch (type) {
      BillType.installment => 'Installment',
      BillType.creditCard => 'Credit Card',
      BillType.subscription => 'Subscription',
      BillType.insurance => 'Insurance',
      BillType.govtContribution => 'Govt Contribution',
      BillType.utility => 'Utility',
      BillType.other => 'Other',
    };

// ─── Add/Edit-receivable dialog ───────────────────────────────────────────────

void _onAddReceivable(
    BuildContext context, BillsReceivablesPresenter presenter) {
  showDialog<void>(
    context: context,
    builder: (_) => _ReceivableDialog(presenter: presenter),
  );
}

/// Desktop add/edit-receivable form. Mirrors [_AddBillDialog]: Name, Type,
/// Amount, Expected day, destination account, and (income) Category, then calls
/// [BillsReceivablesPresenter.addReceivable] / `updateReceivable`.
class _ReceivableDialog extends StatefulWidget {
  final BillsReceivablesPresenter presenter;
  final Receivable? existing;

  const _ReceivableDialog({required this.presenter, this.existing});

  @override
  State<_ReceivableDialog> createState() => _ReceivableDialogState();
}

class _ReceivableDialogState extends State<_ReceivableDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _dayController = TextEditingController();

  late ReceivableType _type;
  String? _selectedAccountId;
  String? _selectedCategoryId;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    _type = r?.receivableType ?? ReceivableType.salary;
    if (r != null) {
      _nameController.text = r.name;
      _amountController.text = r.amount == r.amount.roundToDouble()
          ? r.amount.round().toString()
          : r.amount.toString();
      _dayController.text = r.expectedDate.day.toString();
      _selectedAccountId = r.accountId;
      _selectedCategoryId = r.categoryId.isEmpty ? null : r.categoryId;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _dayController.dispose();
    super.dispose();
  }

  List<FinanceCategory> get _incomeCategories => widget.presenter.categories
      .where((c) => c.type == CategoryType.income)
      .toList();

  /// Build an [expectedDate] for the selected month, clamping the day to the
  /// month's length so short months (e.g. Feb 30) never throw.
  DateTime _expectedDate(int day) {
    final parts = widget.presenter.selectedMonth.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, day.clamp(1, lastDay));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isSubmitting = true);
    try {
      final amount = double.parse(_amountController.text.replaceAll(',', ''));
      final day = int.parse(_dayController.text);
      final existing = widget.existing;
      if (existing == null) {
        final receivable = Receivable(
          id: '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}',
          name: _nameController.text.trim(),
          receivableType: _type,
          amount: amount,
          expectedDate: _expectedDate(day),
          month: widget.presenter.selectedMonth,
          categoryId: _selectedCategoryId ?? '',
          accountId: _selectedAccountId,
        );
        await widget.presenter.addReceivable(receivable);
      } else {
        await widget.presenter.updateReceivable(existing.copyWith(
          name: _nameController.text.trim(),
          receivableType: _type,
          amount: amount,
          expectedDate: _expectedDate(day),
          categoryId: _selectedCategoryId ?? '',
          accountId: _selectedAccountId,
        ));
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Could not save receivable: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accounts =
        widget.presenter.accounts.where((a) => a.isActive).toList();
    final categories = _incomeCategories;
    final isEdit = widget.existing != null;

    return AlertDialog(
      title: Text(isEdit ? 'Edit Receivable' : 'Add Receivable'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Name'),
                  textInputAction: TextInputAction.next,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                ),
                const SizedBox(height: WebInsets.md),
                DropdownButtonFormField<ReceivableType>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: ReceivableType.values
                      .map((t) => DropdownMenuItem(
                          value: t, child: Text(_receivableTypeLabel(t))))
                      .toList(),
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
                const SizedBox(height: WebInsets.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _amountController,
                        decoration: const InputDecoration(
                            labelText: 'Amount', prefixText: '₱ '),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        textInputAction: TextInputAction.next,
                        validator: (v) {
                          final p =
                              double.tryParse((v ?? '').replaceAll(',', ''));
                          if (p == null || p <= 0) return 'Must be > 0';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: WebInsets.md),
                    Expanded(
                      child: TextFormField(
                        controller: _dayController,
                        decoration: const InputDecoration(
                            labelText: 'Expected day (1–31)'),
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        validator: (v) {
                          final d = int.tryParse(v ?? '');
                          if (d == null || d < 1 || d > 31) return '1–31';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                if (accounts.isNotEmpty) ...[
                  const SizedBox(height: WebInsets.md),
                  DropdownButtonFormField<String>(
                    initialValue:
                        accounts.any((a) => a.id == _selectedAccountId)
                            ? _selectedAccountId
                            : null,
                    decoration: const InputDecoration(
                        labelText: 'Deposit account (optional)'),
                    items: [
                      const DropdownMenuItem<String>(
                          value: null, child: Text('None')),
                      for (final a in accounts)
                        DropdownMenuItem(value: a.id, child: Text(a.name)),
                    ],
                    onChanged: (v) => setState(() => _selectedAccountId = v),
                  ),
                ],
                if (categories.isNotEmpty) ...[
                  const SizedBox(height: WebInsets.md),
                  DropdownButtonFormField<String>(
                    initialValue:
                        categories.any((c) => c.id == _selectedCategoryId)
                            ? _selectedCategoryId
                            : null,
                    decoration:
                        const InputDecoration(labelText: 'Category (optional)'),
                    items: [
                      const DropdownMenuItem<String>(
                          value: null, child: Text('None')),
                      for (final c in categories)
                        DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => setState(() => _selectedCategoryId = v),
                  ),
                ],
                if (accounts.isEmpty && categories.isEmpty) ...[
                  const SizedBox(height: WebInsets.sm),
                  Text(
                    'Add an account or income category in the app for richer receivables.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEdit ? 'Save' : 'Add Receivable'),
        ),
      ],
    );
  }
}

// ─── Header ─────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String monthLabel;
  final String subtitle;
  final VoidCallback onAddBill;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;

  const _Header({
    required this.monthLabel,
    required this.subtitle,
    required this.onAddBill,
    required this.onPrevMonth,
    required this.onNextMonth,
  });

  @override
  Widget build(BuildContext context) {
    return WebSectionHeader(
      title: 'Bills & Receivables',
      subtitle: subtitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          WebMonthStepper(
            label: monthLabel,
            onPrev: onPrevMonth,
            onNext: onNextMonth,
          ),
          const SizedBox(width: WebInsets.sm),
          FilledButton.icon(
            onPressed: onAddBill,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Bill'),
          ),
        ],
      ),
    );
  }
}

// ─── Stat strip ───────────────────────────────────────────────────────────────

class _StatStrip extends StatelessWidget {
  final double dueTotal;
  final double paidTotal;
  final double monthTotal;
  final double receiveTotal;
  final int unpaidCount;
  final int paidCount;
  final int receivableCount;

  const _StatStrip({
    required this.dueTotal,
    required this.paidTotal,
    required this.monthTotal,
    required this.receiveTotal,
    required this.unpaidCount,
    required this.paidCount,
    required this.receivableCount,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tiles = <Widget>[
      WebStatTile(
        label: 'Due This Month',
        value: formatPeso(dueTotal),
        sub: '$unpaidCount unpaid',
        icon: Icons.receipt_long_outlined,
        valueColor: dueTotal > 0 ? cs.error : null,
      ),
      WebStatTile(
        label: 'Paid',
        value: formatPeso(paidTotal),
        sub: '$paidCount settled',
        icon: Icons.check_circle_outline,
        valueColor: cs.tertiary,
      ),
      WebStatTile(
        label: 'Total This Month',
        value: formatPeso(monthTotal),
        sub: '${unpaidCount + paidCount} bills',
        icon: Icons.description_outlined,
      ),
      WebStatTile(
        label: 'To Receive',
        value: formatPeso(receiveTotal),
        sub: '$receivableCount pending',
        icon: Icons.south_west,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 760 ? 4 : 2;
        const gap = WebInsets.lg;
        final tileWidth = (constraints.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final t in tiles) SizedBox(width: tileWidth, child: t),
          ],
        );
      },
    );
  }
}

// ─── Upcoming card ────────────────────────────────────────────────────────────

class _UpcomingCard extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final List<Bill> unpaid;
  final double dueTotal;

  const _UpcomingCard({
    required this.presenter,
    required this.unpaid,
    required this.dueTotal,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return WebCard(
      accentColor: cs.error,
      title: 'Upcoming',
      description:
          '${formatPeso(dueTotal)} across ${unpaid.length} ${unpaid.length == 1 ? 'bill' : 'bills'}',
      child: unpaid.isEmpty
          ? const _EmptyHint('No bills due — you are all caught up.')
          : Column(
              children: [
                for (var i = 0; i < unpaid.length; i++)
                  _BillRow(
                    presenter: presenter,
                    bill: unpaid[i],
                    showDivider: i > 0,
                  ),
                const SizedBox(height: WebInsets.md),
                Container(
                  padding: const EdgeInsets.only(top: WebInsets.md),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: 0.5)),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('DUE',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.7,
                          )),
                      Text(formatPeso(dueTotal),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.error,
                          )),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// ─── Paid card ──────────────────────────────────────────────────────────────

class _PaidCard extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final List<Bill> paid;
  final double paidTotal;

  const _PaidCard({
    required this.presenter,
    required this.paid,
    required this.paidTotal,
  });

  @override
  Widget build(BuildContext context) {
    return WebCard(
      title: 'Paid',
      description: '${formatPeso(paidTotal)} settled',
      child: Column(
        children: [
          for (var i = 0; i < paid.length; i++)
            _BillRow(
              presenter: presenter,
              bill: paid[i],
              showDivider: i > 0,
            ),
        ],
      ),
    );
  }
}

// ─── Bill row ─────────────────────────────────────────────────────────────────

class _BillRow extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final Bill bill;
  final bool showDivider;

  const _BillRow({
    required this.presenter,
    required this.bill,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final paid = bill.isPaid;
    final accountName = _accountName(bill.accountId);

    final nameStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: paid ? cs.onSurfaceVariant : cs.onSurface,
      decoration: paid ? TextDecoration.lineThrough : null,
    );
    final amountStyle = theme.textTheme.bodyLarge?.copyWith(
      fontWeight: FontWeight.w700,
      color: paid ? cs.onSurfaceVariant : cs.onSurface,
    );

    return Container(
      decoration: showDivider
          ? BoxDecoration(
              border: Border(
                top:
                    BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
            )
          : null,
      padding: const EdgeInsets.symmetric(vertical: WebInsets.md),
      child: Row(
        children: [
          _PaidCheckbox(
            checked: paid,
            onTap: paid ? null : () => _markPaid(context),
          ),
          const SizedBox(width: WebInsets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(bill.name,
                          style: nameStyle, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: WebInsets.sm),
                    WebBadge(
                      _billTypeLabel(bill.billType),
                      tone: _billTypeTone(bill.billType),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Due ${_ordinal(bill.dueDay)}${accountName != null ? ' · $accountName' : ''}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: WebInsets.md),
          Text(formatPeso(bill.amount), style: amountStyle),
          _RowActions(
            onEdit: () => _edit(context),
            onDelete: () => _delete(context),
          ),
        ],
      ),
    );
  }

  void _edit(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _AddBillDialog(presenter: presenter, existing: bill),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete bill?'),
        content: Text('Remove "${bill.name}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await presenter.deleteBill(bill.id);
    messenger.showSnackBar(SnackBar(content: Text('Deleted "${bill.name}".')));
  }

  String? _accountName(String? accountId) {
    if (accountId == null) return null;
    final match = presenter.accounts.where((a) => a.id == accountId).toList();
    return match.isEmpty ? null : match.first.name;
  }

  Future<void> _markPaid(BuildContext context) async {
    // Mirror the mobile mark-paid: pay the full billed amount from the bill's
    // preferred account, falling back to the first active liquid (asset)
    // account — never a liability/credit or inactive account.
    final fallback =
        presenter.accounts.where((a) => a.isActive && a.isLiquid).toList();
    final accountId =
        bill.accountId ?? (fallback.isNotEmpty ? fallback.first.id : null);
    final messenger = ScaffoldMessenger.of(context);
    final accountName = _accountName(accountId) ?? 'your account';

    // Marking paid moves real money out of an account and can't be undone in
    // one click — confirm, and show exactly which account is debited (it may be
    // a silent fallback the user never picked). (Plan 052 U1/U2) The "already
    // in ledger" toggle skips recording entirely for expenses logged manually.
    var alreadyInLedger = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: const Text('Mark bill as paid?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(alreadyInLedger
                  ? 'Mark "${bill.name}" (${formatPeso(bill.amount)}) as paid '
                      'without recording a transaction.'
                  : 'Pay ${formatPeso(bill.amount)} for "${bill.name}" from '
                      '$accountName? This debits the account balance.'),
              const SizedBox(height: 4),
              CheckboxListTile(
                value: alreadyInLedger,
                onChanged: (v) =>
                    setLocalState(() => alreadyInLedger = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Already added to ledger'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Mark paid')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    // An account is only required when we're actually recording the payment.
    if (!alreadyInLedger && accountId == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Add an account before marking paid.')),
      );
      return;
    }

    await presenter.markBillPaid(
      bill.id,
      paidAmount: bill.amount,
      accountId: alreadyInLedger ? null : accountId,
      recordInLedger: !alreadyInLedger,
    );
    messenger.showSnackBar(
      SnackBar(
          content: Text(alreadyInLedger
              ? 'Marked "${bill.name}" paid.'
              : 'Paid ${formatPeso(bill.amount)} for "${bill.name}" from $accountName.')),
    );
  }
}

// ─── Receivables card ─────────────────────────────────────────────────────────

class _ReceivablesCard extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final List<Receivable> receivables;
  final double pendingTotal;

  const _ReceivablesCard({
    required this.presenter,
    required this.receivables,
    required this.pendingTotal,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pending = receivables.where((r) => !r.isReceived).toList();

    return WebCard(
      accentColor: Theme.of(context).colorScheme.tertiary,
      title: 'Receivables',
      description: 'Money owed to you',
      trailing: OutlinedButton.icon(
        onPressed: () => _onAddReceivable(context, presenter),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Add Receivable'),
      ),
      child: receivables.isEmpty
          ? const _EmptyHint('Nothing owed to you this month.')
          : Column(
              children: [
                for (var i = 0; i < receivables.length; i++)
                  _ReceivableRow(
                    presenter: presenter,
                    receivable: receivables[i],
                    showDivider: i > 0,
                  ),
                if (pending.isNotEmpty) ...[
                  const SizedBox(height: WebInsets.md),
                  Container(
                    padding: const EdgeInsets.only(top: WebInsets.md),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                            color: cs.outlineVariant.withValues(alpha: 0.5)),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('PENDING',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.7,
                            )),
                        Text(formatPeso(pendingTotal),
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: cs.tertiary,
                            )),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _ReceivableRow extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final Receivable receivable;
  final bool showDivider;

  const _ReceivableRow({
    required this.presenter,
    required this.receivable,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final received = receivable.isReceived;

    return Container(
      decoration: showDivider
          ? BoxDecoration(
              border: Border(
                top:
                    BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
            )
          : null,
      padding: const EdgeInsets.symmetric(vertical: WebInsets.md),
      child: Row(
        children: [
          _PaidCheckbox(
            checked: received,
            onTap: received ? null : () => _markReceived(context),
          ),
          const SizedBox(width: WebInsets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  receivable.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: received ? cs.onSurfaceVariant : cs.onSurface,
                    decoration: received ? TextDecoration.lineThrough : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Due ${_ordinal(receivable.expectedDate.day)} · ${_receivableTypeLabel(receivable.receivableType)}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: WebInsets.md),
          Text(
            formatPeso(receivable.amount),
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: received ? cs.onSurfaceVariant : cs.tertiary,
            ),
          ),
          _RowActions(
            onEdit: () => _edit(context),
            onDelete: () => _delete(context),
          ),
        ],
      ),
    );
  }

  void _edit(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) =>
          _ReceivableDialog(presenter: presenter, existing: receivable),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete receivable?'),
        content: Text('Remove "${receivable.name}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await presenter.deleteReceivable(receivable.id);
    messenger
        .showSnackBar(SnackBar(content: Text('Deleted "${receivable.name}".')));
  }

  Future<void> _markReceived(BuildContext context) async {
    // Mirror the bill mark-paid flow but as an inflow: money lands in the
    // receivable's preferred account, falling back to the first active liquid
    // (asset) account.
    final fallback =
        presenter.accounts.where((a) => a.isActive && a.isLiquid).toList();
    final accountId = receivable.accountId ??
        (fallback.isNotEmpty ? fallback.first.id : null);
    final messenger = ScaffoldMessenger.of(context);
    final accountName = presenter.accountName(accountId) ?? 'your account';

    var alreadyInLedger = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: const Text('Mark as received?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(alreadyInLedger
                  ? 'Mark "${receivable.name}" (${formatPeso(receivable.amount)}) '
                      'as received without recording a transaction.'
                  : 'Deposit ${formatPeso(receivable.amount)} from '
                      '"${receivable.name}" into $accountName? This credits the '
                      'account balance.'),
              const SizedBox(height: 4),
              CheckboxListTile(
                value: alreadyInLedger,
                onChanged: (v) =>
                    setLocalState(() => alreadyInLedger = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Already added to ledger'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Mark received')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    // An account is only required when we're actually recording the receipt.
    if (!alreadyInLedger && accountId == null) {
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Add an account before marking received.')),
      );
      return;
    }

    await presenter.markReceivableReceived(
      receivable.id,
      receivedAmount: receivable.amount,
      accountId: alreadyInLedger ? null : accountId,
      recordInLedger: !alreadyInLedger,
    );
    messenger.showSnackBar(
      SnackBar(
          content: Text(alreadyInLedger
              ? 'Marked "${receivable.name}" received.'
              : 'Received ${formatPeso(receivable.amount)} for "${receivable.name}" into $accountName.')),
    );
  }
}

// ─── Budgeted expenses (set-asides) ───────────────────────────────────────────

void _onAddBudgetedExpense(
    BuildContext context, BillsReceivablesPresenter presenter) {
  showDialog<void>(
    context: context,
    builder: (_) => _BudgetedExpenseDialog(presenter: presenter),
  );
}

/// Money set aside that isn't a bill or a budget category — savings/sinking-fund
/// contributions and one-off plans (gifts, outings). Marking one "funded" posts
/// an outflow that leaves your liquid cash, mirroring the mobile flow.
class _BudgetedExpensesCard extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final List<BudgetedExpense> expenses;

  const _BudgetedExpensesCard(
      {required this.presenter, required this.expenses});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pending = expenses.where((e) => !e.isPaid).toList();
    final pendingTotal = pending.fold(0.0, (sum, e) => sum + e.allocatedAmount);

    return WebCard(
      accentColor: cs.secondary,
      title: 'Budgeted Set-Asides',
      description: 'Savings, sinking funds & one-off plans',
      trailing: OutlinedButton.icon(
        onPressed: () => _onAddBudgetedExpense(context, presenter),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Add Set-Aside'),
      ),
      child: expenses.isEmpty
          ? const _EmptyHint('No set-asides budgeted this month.')
          : Column(
              children: [
                for (var i = 0; i < expenses.length; i++)
                  _BudgetedExpenseRow(
                    presenter: presenter,
                    expense: expenses[i],
                    showDivider: i > 0,
                  ),
                if (pending.isNotEmpty) ...[
                  const SizedBox(height: WebInsets.md),
                  Container(
                    padding: const EdgeInsets.only(top: WebInsets.md),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                            color: cs.outlineVariant.withValues(alpha: 0.5)),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('TO SET ASIDE',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.7,
                            )),
                        Text(formatPeso(pendingTotal),
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: cs.secondary,
                            )),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _BudgetedExpenseRow extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final BudgetedExpense expense;
  final bool showDivider;

  const _BudgetedExpenseRow({
    required this.presenter,
    required this.expense,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final funded = expense.isPaid;
    final subtitle = expense.note == null || expense.note!.trim().isEmpty
        ? _billTypeLabel(expense.budgetedType)
        : '${_billTypeLabel(expense.budgetedType)} · ${expense.note!.trim()}';

    return Container(
      decoration: showDivider
          ? BoxDecoration(
              border: Border(
                top:
                    BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
            )
          : null,
      padding: const EdgeInsets.symmetric(vertical: WebInsets.md),
      child: Row(
        children: [
          _PaidCheckbox(
            checked: funded,
            onTap: funded ? null : () => _markFunded(context),
          ),
          const SizedBox(width: WebInsets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  expense.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: funded ? cs.onSurfaceVariant : cs.onSurface,
                    decoration: funded ? TextDecoration.lineThrough : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: WebInsets.md),
          Text(
            formatPeso(expense.allocatedAmount),
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: funded ? cs.onSurfaceVariant : cs.secondary,
            ),
          ),
          _RowActions(
            onEdit: () => _edit(context),
            onDelete: () => _delete(context),
          ),
        ],
      ),
    );
  }

  void _edit(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) =>
          _BudgetedExpenseDialog(presenter: presenter, existing: expense),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete set-aside?'),
        content: Text('Remove "${expense.name}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await presenter.deleteBudgetedExpense(expense.id);
    messenger
        .showSnackBar(SnackBar(content: Text('Deleted "${expense.name}".')));
  }

  Future<void> _markFunded(BuildContext context) async {
    // Funding a set-aside posts an outflow from a liquid account — the money
    // leaves your spendable cash (into savings / the planned spend), exactly
    // like the mobile "mark paid" flow.
    final fallback =
        presenter.accounts.where((a) => a.isActive && a.isLiquid).toList();
    final accountId = fallback.isNotEmpty ? fallback.first.id : null;
    final messenger = ScaffoldMessenger.of(context);
    if (accountId == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Add an account before funding.')),
      );
      return;
    }

    final accountName = presenter.accountName(accountId) ?? 'your account';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fund this set-aside?'),
        content: Text(
            'Move ${formatPeso(expense.allocatedAmount)} for "${expense.name}" '
            'out of $accountName? This debits the account balance.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Fund')),
        ],
      ),
    );
    if (confirmed != true) return;

    await presenter.markExpensePaid(
      expense.id,
      paidAmount: expense.allocatedAmount,
      accountId: accountId,
    );
    messenger.showSnackBar(
      SnackBar(
          content: Text(
              'Set aside ${formatPeso(expense.allocatedAmount)} for "${expense.name}" from $accountName.')),
    );
  }
}

/// Desktop add/edit form for a budgeted set-aside. Mirrors the mobile
/// [_AddBudgetedExpenseSheet]: Name, Type, Amount, optional Category, and a
/// free-text Note (e.g. "Maya Savings"). Calls
/// [BillsReceivablesPresenter.addBudgetedExpense] / `updateBudgetedExpense`.
class _BudgetedExpenseDialog extends StatefulWidget {
  final BillsReceivablesPresenter presenter;
  final BudgetedExpense? existing;

  const _BudgetedExpenseDialog({required this.presenter, this.existing});

  @override
  State<_BudgetedExpenseDialog> createState() => _BudgetedExpenseDialogState();
}

class _BudgetedExpenseDialogState extends State<_BudgetedExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  late BillType _type;
  String? _selectedCategoryId;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = e?.budgetedType ?? BillType.other;
    if (e != null) {
      _nameController.text = e.name;
      _amountController.text =
          e.allocatedAmount == e.allocatedAmount.roundToDouble()
              ? e.allocatedAmount.round().toString()
              : e.allocatedAmount.toString();
      _noteController.text = e.note ?? '';
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

  List<FinanceCategory> get _expenseCategories => widget.presenter.categories
      .where((c) => c.type == CategoryType.expense)
      .toList();

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isSubmitting = true);
    try {
      final amount = double.parse(_amountController.text.replaceAll(',', ''));
      final note = _noteController.text.trim();
      final existing = widget.existing;
      if (existing == null) {
        await widget.presenter.addBudgetedExpense(BudgetedExpense(
          id: '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}',
          name: _nameController.text.trim(),
          budgetedType: _type,
          month: widget.presenter.selectedMonth,
          allocatedAmount: amount,
          categoryId: _selectedCategoryId ?? '',
          note: note.isEmpty ? null : note,
        ));
      } else {
        await widget.presenter.updateBudgetedExpense(existing.copyWith(
          name: _nameController.text.trim(),
          budgetedType: _type,
          allocatedAmount: amount,
          categoryId: _selectedCategoryId ?? '',
          note: note.isEmpty ? null : note,
        ));
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Could not save set-aside: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final categories = _expenseCategories;
    final isEdit = widget.existing != null;

    return AlertDialog(
      title: Text(isEdit ? 'Edit Set-Aside' : 'Add Set-Aside'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                      labelText: 'Name (e.g. Travel Fund, Tanel Birthday)'),
                  textInputAction: TextInputAction.next,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                ),
                const SizedBox(height: WebInsets.md),
                DropdownButtonFormField<BillType>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: BillType.values
                      .map((t) => DropdownMenuItem(
                          value: t, child: Text(_billTypeFormLabel(t))))
                      .toList(),
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
                const SizedBox(height: WebInsets.md),
                TextFormField(
                  controller: _amountController,
                  decoration: const InputDecoration(
                      labelText: 'Amount', prefixText: '₱ '),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    final p = double.tryParse((v ?? '').replaceAll(',', ''));
                    if (p == null || p <= 0) return 'Must be > 0';
                    return null;
                  },
                ),
                const SizedBox(height: WebInsets.md),
                TextFormField(
                  controller: _noteController,
                  decoration: const InputDecoration(
                      labelText: 'Note (optional, e.g. Maya Savings)'),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                ),
                if (categories.isNotEmpty) ...[
                  const SizedBox(height: WebInsets.md),
                  DropdownButtonFormField<String>(
                    initialValue:
                        categories.any((c) => c.id == _selectedCategoryId)
                            ? _selectedCategoryId
                            : null,
                    decoration:
                        const InputDecoration(labelText: 'Category (optional)'),
                    items: [
                      const DropdownMenuItem<String>(
                          value: null, child: Text('None')),
                      for (final c in categories)
                        DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => setState(() => _selectedCategoryId = v),
                  ),
                ],
                const SizedBox(height: WebInsets.sm),
                Text(
                  'Funding a set-aside later debits a liquid account — the money '
                  'leaves your spendable cash.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEdit ? 'Save' : 'Add Set-Aside'),
        ),
      ],
    );
  }
}

// ─── Shared bits ──────────────────────────────────────────────────────────────

class _PaidCheckbox extends StatelessWidget {
  final bool checked;
  final VoidCallback? onTap;

  const _PaidCheckbox({required this.checked, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.sm),
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: checked ? cs.tertiary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          border: Border.all(
            color: checked ? cs.tertiary : cs.outline,
            width: 1.5,
          ),
        ),
        child:
            checked ? Icon(Icons.check, size: 14, color: cs.onTertiary) : null,
      ),
    );
  }
}

/// Trailing overflow menu shared by bill + receivable rows. Keeps edit/delete
/// out of the way until hovered/tapped so the row stays scannable.
class _RowActions extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RowActions({required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: Icon(Icons.more_vert, size: 18, color: cs.onSurfaceVariant),
      padding: EdgeInsets.zero,
      splashRadius: 20,
      onSelected: (v) {
        if (v == 'edit') onEdit();
        if (v == 'delete') onDelete();
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        PopupMenuItem(
          value: 'delete',
          child: Text('Delete', style: TextStyle(color: cs.error)),
        ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String message;

  const _EmptyHint(this.message);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WebInsets.lg),
      child: Center(
        child: Text(
          message,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _billTypeLabel(BillType type) => switch (type) {
      BillType.creditCard => 'Credit Card',
      BillType.installment => 'Installment',
      BillType.subscription => 'Subscription',
      BillType.insurance => 'Insurance',
      BillType.govtContribution => 'Govt',
      BillType.utility => 'Bills',
      BillType.other => 'Bills',
    };

String _receivableTypeLabel(ReceivableType type) => switch (type) {
      ReceivableType.salary => 'Salary',
      ReceivableType.reimbursement => 'Reimbursement',
      ReceivableType.business => 'Business',
      ReceivableType.other => 'Other',
    };

WebBadgeTone _billTypeTone(BillType type) => switch (type) {
      BillType.creditCard => WebBadgeTone.info,
      BillType.installment => WebBadgeTone.warning,
      _ => WebBadgeTone.neutral,
    };

String _ordinal(int day) {
  if (day >= 11 && day <= 13) return '${day}th';
  return switch (day % 10) {
    1 => '${day}st',
    2 => '${day}nd',
    3 => '${day}rd',
    _ => '${day}th',
  };
}
