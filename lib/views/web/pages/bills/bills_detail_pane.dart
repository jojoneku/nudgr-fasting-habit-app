import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/web/widgets/web_widgets.dart';
import 'package:intl/intl.dart';

import 'bills_selection.dart';
import 'bills_sheet_dialog.dart';

/// Right-hand detail/edit pane for the selected Bill / Receivable / Installment.
/// All settlement actions (mark-paid, mark-received, mark-installment-paid) are
/// wired to the presenters here. Pure presentation — amounts/labels/status come
/// from presenter getters.
class BillsDetailPane extends StatelessWidget {
  final BillsSelection? selection;
  final BillsReceivablesPresenter presenter;
  final InstallmentPresenter installmentPresenter;

  const BillsDetailPane({
    super.key,
    required this.selection,
    required this.presenter,
    required this.installmentPresenter,
  });

  @override
  Widget build(BuildContext context) {
    final sel = selection;
    if (sel == null) {
      return const _EmptyDetail();
    }
    return switch (sel) {
      BillSelection(:final id) => _resolveBill(context, id),
      ReceivableSelection(:final id) => _resolveReceivable(context, id),
      InstallmentSelection(:final id) => _resolveInstallment(context, id),
    };
  }

  Widget _resolveBill(BuildContext context, String id) {
    final bill = presenter.bills.where((b) => b.id == id).firstOrNull;
    if (bill == null) return const _EmptyDetail();
    return _BillDetail(bill: bill, presenter: presenter);
  }

  Widget _resolveReceivable(BuildContext context, String id) {
    final rec = presenter.receivables.where((r) => r.id == id).firstOrNull;
    if (rec == null) return const _EmptyDetail();
    return _ReceivableDetail(receivable: rec, presenter: presenter);
  }

  Widget _resolveInstallment(BuildContext context, String id) {
    final inst =
        installmentPresenter.installments.where((i) => i.id == id).firstOrNull;
    if (inst == null) return const _EmptyDetail();
    return _InstallmentDetail(
        installment: inst, presenter: installmentPresenter);
  }
}

// ─── Empty state ────────────────────────────────────────────────────────────

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return WebCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: WebInsets.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app_outlined,
                size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: WebInsets.md),
            Text(
              'Select a bill, receivable, or installment',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared detail scaffolding ──────────────────────────────────────────────

class _DetailShell extends StatelessWidget {
  final String title;
  final WebBadge statusBadge;
  final List<_DetailRow> rows;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Widget? action;

  const _DetailShell({
    required this.title,
    required this.statusBadge,
    required this.rows,
    required this.onEdit,
    required this.onDelete,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(title,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              statusBadge,
            ],
          ),
          const SizedBox(height: WebInsets.lg),
          for (final r in rows) r,
          const SizedBox(height: WebInsets.lg),
          if (action != null) ...[
            action!,
            const SizedBox(height: WebInsets.md),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit'),
                ),
              ),
              const SizedBox(width: WebInsets.md),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
                color: theme.colorScheme.error,
                tooltip: 'Delete',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: WebInsets.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ─── Bill detail ────────────────────────────────────────────────────────────

class _BillDetail extends StatelessWidget {
  final Bill bill;
  final BillsReceivablesPresenter presenter;

  const _BillDetail({required this.bill, required this.presenter});

  @override
  Widget build(BuildContext context) {
    final status = presenter.billStatus(bill);
    final account = presenter.accountName(bill.accountId);
    return _DetailShell(
      title: bill.name,
      statusBadge: billStatusBadge(status),
      onEdit: () => showAddBillDialog(context, presenter, existing: bill),
      onDelete: () => presenter.deleteBill(bill.id),
      rows: [
        _DetailRow(label: 'Type', value: billTypeLabel(bill.billType)),
        _DetailRow(label: 'Amount', value: formatPeso(bill.amount)),
        _DetailRow(label: 'Due day', value: 'Day ${bill.dueDay}'),
        if (account != null) _DetailRow(label: 'Account', value: account),
        if (bill.isRecurring)
          const _DetailRow(label: 'Recurring', value: 'Yes'),
        if (bill.paymentNote != null && bill.paymentNote!.isNotEmpty)
          _DetailRow(label: 'Notes', value: bill.paymentNote!),
        if (bill.isPaid && bill.paidDate != null)
          _DetailRow(
              label: 'Paid on',
              value: DateFormat('MMM d, yyyy').format(bill.paidDate!)),
        if (bill.isPaid && bill.paidAmount != null)
          _DetailRow(label: 'Paid', value: formatPeso(bill.paidAmount!)),
      ],
      action: bill.isPaid
          ? null
          : _SettleForm(
              ctaLabel: 'Mark Paid',
              defaultAmount: bill.amount,
              accounts: presenter.accounts.map((a) => (a.id, a.name)).toList(),
              preferredAccountId: bill.accountId,
              onConfirm: (amount, accountId, date) => presenter.markBillPaid(
                bill.id,
                paidAmount: amount,
                accountId: accountId,
                paidDate: date,
              ),
            ),
    );
  }
}

// ─── Receivable detail ──────────────────────────────────────────────────────

class _ReceivableDetail extends StatelessWidget {
  final Receivable receivable;
  final BillsReceivablesPresenter presenter;

  const _ReceivableDetail({required this.receivable, required this.presenter});

  @override
  Widget build(BuildContext context) {
    final account = presenter.accountName(receivable.accountId);
    return _DetailShell(
      title: receivable.name,
      statusBadge: receivable.isReceived
          ? const WebBadge('Received',
              tone: WebBadgeTone.success, icon: Icons.check_circle_outline)
          : const WebBadge('Pending', tone: WebBadgeTone.warning),
      onEdit: () =>
          showAddReceivableDialog(context, presenter, existing: receivable),
      onDelete: () => presenter.deleteReceivable(receivable.id),
      rows: [
        _DetailRow(
            label: 'Type',
            value: receivableTypeLabel(receivable.receivableType)),
        _DetailRow(label: 'Amount', value: formatPeso(receivable.amount)),
        _DetailRow(
            label: 'Expected',
            value: DateFormat('MMM d, yyyy').format(receivable.expectedDate)),
        if (account != null) _DetailRow(label: 'Account', value: account),
        if (receivable.isRecurring)
          const _DetailRow(label: 'Recurring', value: 'Yes'),
        if (receivable.isReceived && receivable.receivedDate != null)
          _DetailRow(
              label: 'Received on',
              value:
                  DateFormat('MMM d, yyyy').format(receivable.receivedDate!)),
        if (receivable.isReceived && receivable.receivedAmount != null)
          _DetailRow(
              label: 'Received', value: formatPeso(receivable.receivedAmount!)),
      ],
      action: receivable.isReceived
          ? null
          : _SettleForm(
              ctaLabel: 'Mark Received',
              defaultAmount: receivable.amount,
              accounts: presenter.accounts.map((a) => (a.id, a.name)).toList(),
              preferredAccountId: receivable.accountId,
              onConfirm: (amount, accountId, date) =>
                  presenter.markReceivableReceived(
                receivable.id,
                receivedAmount: amount,
                accountId: accountId,
                receivedDate: date,
              ),
            ),
    );
  }
}

// ─── Installment detail ─────────────────────────────────────────────────────

class _InstallmentDetail extends StatelessWidget {
  final Installment installment;
  final InstallmentPresenter presenter;

  const _InstallmentDetail(
      {required this.installment, required this.presenter});

  @override
  Widget build(BuildContext context) {
    final paidThisMonth = presenter.isPaidForMonth(installment.id);
    final remaining = presenter.remainingMonths(installment.id);
    final paid = presenter.paidCount(installment.id);
    final account = presenter.accountName(installment.accountId);
    final dueThisMonth = installment.isDueIn(presenter.selectedMonth);

    return _DetailShell(
      title: installment.name,
      statusBadge: installmentBadge(
          paidThisMonth: paidThisMonth, dueThisMonth: dueThisMonth),
      onEdit: () =>
          showAddInstallmentDialog(context, presenter, existing: installment),
      onDelete: () => presenter.deleteInstallment(installment.id),
      rows: [
        _DetailRow(
            label: 'Monthly', value: formatPeso(installment.monthlyAmount)),
        _DetailRow(label: 'Total', value: formatPeso(installment.totalAmount)),
        _DetailRow(
            label: 'Progress',
            value: '$paid / ${installment.totalMonths} paid'),
        _DetailRow(
            label: 'Remaining',
            value:
                '$remaining mo · ${formatPeso(presenter.remainingAmount(installment.id))}'),
        _DetailRow(
            label: 'Period',
            value:
                '${monthLabel(installment.startMonth)} → ${monthLabel(installment.endMonth)}'),
        if (account != null) _DetailRow(label: 'Account', value: account),
        if (installment.note != null && installment.note!.isNotEmpty)
          _DetailRow(label: 'Notes', value: installment.note!),
      ],
      action: (!dueThisMonth || paidThisMonth)
          ? null
          : _InstallmentPayButton(
              installment: installment, presenter: presenter),
    );
  }
}

class _InstallmentPayButton extends StatefulWidget {
  final Installment installment;
  final InstallmentPresenter presenter;

  const _InstallmentPayButton(
      {required this.installment, required this.presenter});

  @override
  State<_InstallmentPayButton> createState() => _InstallmentPayButtonState();
}

class _InstallmentPayButtonState extends State<_InstallmentPayButton> {
  bool _saving = false;

  Future<void> _confirm() async {
    setState(() => _saving = true);
    await widget.presenter.markPaid(widget.installment.id);
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _saving ? null : _confirm,
        icon: const Icon(Icons.check, size: 18),
        label: Text(_saving ? 'Saving…' : 'Mark This Month Paid'),
      ),
    );
  }
}

// ─── Reusable settle form (amount + account + date → confirm) ───────────────

class _SettleForm extends StatefulWidget {
  final String ctaLabel;
  final double defaultAmount;
  final List<(String id, String name)> accounts;
  final String? preferredAccountId;
  final Future<void> Function(double amount, String accountId, DateTime date)
      onConfirm;

  const _SettleForm({
    required this.ctaLabel,
    required this.defaultAmount,
    required this.accounts,
    required this.preferredAccountId,
    required this.onConfirm,
  });

  @override
  State<_SettleForm> createState() => _SettleFormState();
}

class _SettleFormState extends State<_SettleForm> {
  late final TextEditingController _amount;
  String? _accountId;
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amount =
        TextEditingController(text: widget.defaultAmount.toStringAsFixed(2));
    final preferred = widget.preferredAccountId;
    if (preferred != null && widget.accounts.any((a) => a.$1 == preferred)) {
      _accountId = preferred;
    } else if (widget.accounts.isNotEmpty) {
      _accountId = widget.accounts.first.$1;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _confirm() async {
    final amount = double.tryParse(_amount.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) return;
    if (_accountId == null) return;
    setState(() => _saving = true);
    try {
      await widget.onConfirm(amount, _accountId!, _date);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return WebCard(
      onSurface: true,
      padding: const EdgeInsets.all(WebInsets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Settle',
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: WebInsets.md),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount',
              prefixText: '₱ ',
              isDense: true,
            ),
          ),
          if (widget.accounts.isNotEmpty) ...[
            const SizedBox(height: WebInsets.md),
            DropdownButtonFormField<String>(
              initialValue: _accountId,
              isDense: true,
              decoration:
                  const InputDecoration(labelText: 'Account', isDense: true),
              items: widget.accounts
                  .map((a) => DropdownMenuItem(value: a.$1, child: Text(a.$2)))
                  .toList(),
              onChanged: (v) => setState(() => _accountId = v),
            ),
          ],
          const SizedBox(height: WebInsets.md),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_outlined, size: 16),
            label: Text(DateFormat('MMM d, yyyy').format(_date)),
          ),
          const SizedBox(height: WebInsets.md),
          FilledButton(
            onPressed: _saving ? null : _confirm,
            child: Text(_saving ? 'Saving…' : widget.ctaLabel),
          ),
        ],
      ),
    );
  }
}

// ─── Label + badge helpers (presentation-only) ──────────────────────────────

String billTypeLabel(BillType t) => switch (t) {
      BillType.installment => 'Installment',
      BillType.creditCard => 'Credit Card',
      BillType.subscription => 'Subscription',
      BillType.insurance => 'Insurance',
      BillType.govtContribution => 'Govt Contribution',
      BillType.utility => 'Utility',
      BillType.other => 'Other',
    };

String receivableTypeLabel(ReceivableType t) => switch (t) {
      ReceivableType.salary => 'Salary',
      ReceivableType.reimbursement => 'Reimbursement',
      ReceivableType.business => 'Business',
      ReceivableType.other => 'Other',
    };

WebBadge billStatusBadge(BillStatus status) => switch (status) {
      BillStatus.paid => const WebBadge('Paid',
          tone: WebBadgeTone.success, icon: Icons.check_circle_outline),
      BillStatus.overdue =>
        const WebBadge('Overdue', tone: WebBadgeTone.danger),
      BillStatus.dueSoon =>
        const WebBadge('Due soon', tone: WebBadgeTone.warning),
      BillStatus.unpaid => const WebBadge('Unpaid', tone: WebBadgeTone.neutral),
    };

WebBadge installmentBadge(
    {required bool paidThisMonth, required bool dueThisMonth}) {
  if (paidThisMonth) {
    return const WebBadge('Paid',
        tone: WebBadgeTone.success, icon: Icons.check_circle_outline);
  }
  if (dueThisMonth) return const WebBadge('Due', tone: WebBadgeTone.warning);
  return const WebBadge('Not due', tone: WebBadgeTone.neutral);
}
