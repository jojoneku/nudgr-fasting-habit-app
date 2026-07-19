import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/shared/sheet_fields.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';
import 'package:intl/intl.dart';

/// Opens the quick-pay sheet for a credit (liability) [card]. Shared by the
/// Bills tab and the Dashboard's Credit section so paying down a card behaves
/// identically wherever it's launched from.
Future<void> showQuickPaySheet(
  BuildContext context, {
  required FinancialAccount card,
  required BillsReceivablesPresenter presenter,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => QuickPaySheet(card: card, presenter: presenter),
  );
}

/// Pay down a credit-card balance directly (no statement bill required): cash
/// leaves the chosen funding account and the card's owed balance drops, via
/// [BillsReceivablesPresenter.quickPayCard]. Extracted from the Bills view so
/// the Dashboard Credit section can reuse the exact same flow.
class QuickPaySheet extends StatefulWidget {
  final FinancialAccount card;
  final BillsReceivablesPresenter presenter;

  const QuickPaySheet({super.key, required this.card, required this.presenter});

  @override
  State<QuickPaySheet> createState() => _QuickPaySheetState();
}

class _QuickPaySheetState extends State<QuickPaySheet> {
  late final TextEditingController _amountController;
  String? _selectedAccountId;
  DateTime _date = DateTime.now();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.card.currentPayable.toStringAsFixed(2),
    );
    // Non-liability accounts only (can't pay a CC from another CC).
    final payers =
        widget.presenter.accounts.where((a) => !a.isLiability).toList();
    _selectedAccountId = payers.isNotEmpty ? payers.first.id : null;
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
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _confirm() async {
    final amount = double.tryParse(_amountController.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) return;
    if (_selectedAccountId == null) return;
    setState(() => _isSubmitting = true);
    try {
      await widget.presenter.quickPayCard(
        accountId: widget.card.id,
        fromAccountId: _selectedAccountId!,
        amount: amount,
        date: _date,
      );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final payers =
        widget.presenter.accounts.where((a) => !a.isLiability).toList();

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pay ${widget.card.name}',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Current balance: ${formatPeso(widget.card.currentPayable)}',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _amountController,
              label: 'Amount to Pay',
              prefix: const Text('₱ '),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            if (payers.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(_selectedAccountId),
                initialValue: _selectedAccountId,
                decoration: sheetFieldDecoration(context, label: 'Pay from'),
                items: payers
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
                    Text(
                      DateFormat('MMMM d, yyyy').format(_date),
                      style:
                          TextStyle(color: colorScheme.onSurface, fontSize: 14),
                    ),
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
