import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../design/web_breakpoints.dart';

final _dateFmt = DateFormat('MMMM d, yyyy');

/// Desktop counterpart of the mobile `QuickPaySheet`, held to the same
/// contract: any non-liability account may fund the payment, the payment can be
/// dated (so last month's payments can be reconciled from a desktop), the
/// amount is validated rather than silently discarded, and the button shows
/// progress while the write lands.
///
/// Returns the amount paid, or null if the user cancelled.
Future<double?> showWebQuickPayDialog(
  BuildContext context, {
  required FinancialAccount card,
  required BillsReceivablesPresenter presenter,
}) {
  return showDialog<double>(
    context: context,
    builder: (_) => _WebQuickPayDialog(card: card, presenter: presenter),
  );
}

class _WebQuickPayDialog extends StatefulWidget {
  final FinancialAccount card;
  final BillsReceivablesPresenter presenter;

  const _WebQuickPayDialog({required this.card, required this.presenter});

  @override
  State<_WebQuickPayDialog> createState() => _WebQuickPayDialogState();
}

class _WebQuickPayDialogState extends State<_WebQuickPayDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  String? _fromAccountId;
  DateTime _date = DateTime.now();
  bool _isSubmitting = false;

  List<FinancialAccount> get _payers => widget.presenter.accounts
      .where((a) => a.isActive && !a.isLiability)
      .toList();

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.card.currentPayable.toStringAsFixed(2),
    );
    _fromAccountId = _payers.firstOrNull?.id;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final fromId = _fromAccountId;
    if (fromId == null) return;
    final amount = double.parse(_amountController.text.replaceAll(',', ''));
    setState(() => _isSubmitting = true);
    try {
      await widget.presenter.quickPayCard(
        accountId: widget.card.id,
        fromAccountId: fromId,
        amount: amount,
        date: _date,
      );
      if (mounted) Navigator.of(context).pop(amount);
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Could not pay: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final payers = _payers;
    final payable = widget.card.currentPayable;
    final funder = payers.where((a) => a.id == _fromAccountId).firstOrNull;

    return AlertDialog(
      title: Text('Pay ${widget.card.name}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You owe ${formatPeso(payable)}. This moves cash out of the '
                'funding account and lowers what you owe.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: WebInsets.lg),
              TextFormField(
                controller: _amountController,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₱ ',
                ),
                validator: (v) {
                  final amount =
                      double.tryParse((v ?? '').replaceAll(',', '').trim());
                  if (amount == null || amount <= 0) return 'Enter an amount';
                  if (payable > 0 && amount > payable) {
                    return 'More than the ${formatPeso(payable)} owed';
                  }
                  final balance = funder?.balance;
                  if (balance != null && amount > balance) {
                    return '${funder!.name} only has ${formatPeso(balance)}';
                  }
                  return null;
                },
              ),
              const SizedBox(height: WebInsets.lg),
              DropdownButtonFormField<String>(
                initialValue: _fromAccountId,
                decoration: const InputDecoration(labelText: 'Pay from'),
                items: [
                  for (final a in payers)
                    DropdownMenuItem(
                      value: a.id,
                      child: Text('${a.name} · ${formatPeso(a.balance)}'),
                    ),
                ],
                // Re-validate: the balance check depends on which account pays.
                onChanged: (v) {
                  setState(() => _fromAccountId = v ?? _fromAccountId);
                  _formKey.currentState?.validate();
                },
              ),
              const SizedBox(height: WebInsets.lg),
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Payment date'),
                child: InkWell(
                  onTap: _pickDate,
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 16, color: cs.onSurfaceVariant),
                      const SizedBox(width: WebInsets.sm),
                      Text(_dateFmt.format(_date),
                          style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting || payers.isEmpty ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Pay'),
        ),
      ],
    );
  }
}
