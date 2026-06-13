import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
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
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final twoColumn = constraints.maxWidth >= 900;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(WebInsets.xxl),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: double.infinity),
                child: _BillsBody(
                  presenter: presenter,
                  twoColumn: twoColumn,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Body ─────────────────────────────────────────────────────────────────────

class _BillsBody extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final bool twoColumn;

  const _BillsBody({required this.presenter, required this.twoColumn});

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
    // Outstanding = unpaid bills + unpaid budgeted expenses; previously this
    // duplicated `totalBillsPending`, making the tile a copy of "Due". (C2)
    final outstandingTotal = presenter.totalUnpaidObligations;
    final receiveTotal =
        pendingReceivables.fold(0.0, (sum, r) => sum + r.amount);

    final children = <Widget>[
      _Header(
        subtitle:
            '${monthLabel(presenter.selectedMonth)} · ${unpaid.length} bills due, ${pendingReceivables.length} to receive',
        onAddBill: () => _onAddBill(context),
      ),
      const SizedBox(height: WebInsets.xl),
      _StatStrip(
        dueTotal: dueTotal,
        paidTotal: paidTotal,
        outstandingTotal: outstandingTotal,
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
      receivables: receivables,
      pendingTotal: receiveTotal,
    );

    if (twoColumn) {
      children.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: upcomingCard),
              const SizedBox(width: WebInsets.xl),
              Expanded(flex: 2, child: receivablesCard),
            ],
          ),
        ),
      );
    } else {
      children
        ..add(upcomingCard)
        ..add(const SizedBox(height: WebInsets.xl))
        ..add(receivablesCard);
    }

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

  const _AddBillDialog({required this.presenter});

  @override
  State<_AddBillDialog> createState() => _AddBillDialogState();
}

class _AddBillDialogState extends State<_AddBillDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _dueDayController = TextEditingController();

  BillType _billType = BillType.other;
  String? _selectedAccountId;
  String? _selectedCategoryId;
  bool _isSubmitting = false;

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
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      // Previously a save failure left the dialog open with no message. (C7)
      messenger.showSnackBar(SnackBar(content: Text('Could not add bill: $e')));
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

    return AlertDialog(
      title: const Text('Add Bill'),
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
                    initialValue: _selectedAccountId,
                    decoration: const InputDecoration(
                        labelText: 'Payment account (optional)'),
                    items: accounts
                        .map((a) =>
                            DropdownMenuItem(value: a.id, child: Text(a.name)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedAccountId = v),
                  ),
                ],
                if (categories.isNotEmpty) ...[
                  const SizedBox(height: WebInsets.md),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedCategoryId,
                    decoration:
                        const InputDecoration(labelText: 'Category (optional)'),
                    items: categories
                        .map((c) =>
                            DropdownMenuItem(value: c.id, child: Text(c.name)))
                        .toList(),
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
              : const Text('Add Bill'),
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

// ─── Header ─────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String subtitle;
  final VoidCallback onAddBill;

  const _Header({required this.subtitle, required this.onAddBill});

  @override
  Widget build(BuildContext context) {
    return WebSectionHeader(
      title: 'Bills & Receivables',
      subtitle: subtitle,
      trailing: FilledButton.icon(
        onPressed: onAddBill,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Add Bill'),
      ),
    );
  }
}

// ─── Stat strip ───────────────────────────────────────────────────────────────

class _StatStrip extends StatelessWidget {
  final double dueTotal;
  final double paidTotal;
  final double outstandingTotal;
  final double receiveTotal;
  final int unpaidCount;
  final int paidCount;
  final int receivableCount;

  const _StatStrip({
    required this.dueTotal,
    required this.paidTotal,
    required this.outstandingTotal,
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
        label: 'Outstanding',
        value: formatPeso(outstandingTotal),
        sub: 'Unpaid bills + expenses',
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
    return WebCard(
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
        ],
      ),
    );
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
    if (accountId == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Add an account before marking paid.')),
      );
      return;
    }

    // Marking paid moves real money out of an account and can't be undone in
    // one click — confirm, and show exactly which account is debited (it may be
    // a silent fallback the user never picked). (Plan 052 U1/U2)
    final accountName = _accountName(accountId) ?? 'your account';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark bill as paid?'),
        content: Text('Pay ${formatPeso(bill.amount)} for "${bill.name}" from '
            '$accountName? This debits the account balance.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Mark paid')),
        ],
      ),
    );
    if (confirmed != true) return;

    await presenter.markBillPaid(
      bill.id,
      paidAmount: bill.amount,
      accountId: accountId,
    );
    messenger.showSnackBar(
      SnackBar(
          content: Text(
              'Paid ${formatPeso(bill.amount)} for "${bill.name}" from $accountName.')),
    );
  }
}

// ─── Receivables card ─────────────────────────────────────────────────────────

class _ReceivablesCard extends StatelessWidget {
  final List<Receivable> receivables;
  final double pendingTotal;

  const _ReceivablesCard({
    required this.receivables,
    required this.pendingTotal,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pending = receivables.where((r) => !r.isReceived).toList();

    return WebCard(
      title: 'Receivables',
      description: 'Money owed to you',
      child: receivables.isEmpty
          ? const _EmptyHint('Nothing owed to you this month.')
          : Column(
              children: [
                for (var i = 0; i < receivables.length; i++)
                  _ReceivableRow(
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
  final Receivable receivable;
  final bool showDivider;

  const _ReceivableRow({required this.receivable, required this.showDivider});

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
          _PaidCheckbox(checked: received, onTap: null),
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
        ],
      ),
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
