import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_bill_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_budgeted_expense_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_installment_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_receivable_sheet.dart';

/// The four things a New-entry sheet can create.
enum NewEntryType { bill, receivable, setAside, installment }

/// One "New entry" sheet (opened by the Bills FAB) — a type selector on top,
/// then the chosen type's form embedded below. Matches the Nudgr reference's
/// unified creation sheet, extended from Bill/Receivable to all four types.
///
/// Create-only: editing an existing record opens that type's own sheet directly
/// (inherently locked to its type).
class NewEntrySheet extends StatefulWidget {
  final BillsReceivablesPresenter presenter;
  final InstallmentPresenter installmentPresenter;
  final NewEntryType initialType;

  const NewEntrySheet({
    super.key,
    required this.presenter,
    required this.installmentPresenter,
    this.initialType = NewEntryType.bill,
  });

  @override
  State<NewEntrySheet> createState() => _NewEntrySheetState();
}

class _NewEntrySheetState extends State<NewEntrySheet> {
  late NewEntryType _type = widget.initialType;

  Widget _body() {
    switch (_type) {
      case NewEntryType.bill:
        return AddBillSheet(
            key: const ValueKey('bill'),
            presenter: widget.presenter,
            embedded: true);
      case NewEntryType.receivable:
        return AddReceivableSheet(
            key: const ValueKey('receivable'),
            presenter: widget.presenter,
            embedded: true);
      case NewEntryType.setAside:
        return AddBudgetedExpenseSheet(
            key: const ValueKey('setAside'),
            presenter: widget.presenter,
            embedded: true);
      case NewEntryType.installment:
        return AddInstallmentSheet(
            key: const ValueKey('installment'),
            presenter: widget.installmentPresenter,
            embedded: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'New entry',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            _TypeSelector(
              value: _type,
              onChanged: (t) => setState(() => _type = t),
            ),
            const SizedBox(height: 16),
            _body(),
          ],
        ),
      ),
    );
  }
}

class _TypeSelector extends StatelessWidget {
  final NewEntryType value;
  final ValueChanged<NewEntryType> onChanged;

  const _TypeSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final ac = context.appColors;
    final options = <(NewEntryType, IconData, String, Color)>[
      (NewEntryType.bill, Icons.receipt_long_outlined, 'Bill', ac.bills),
      (
        NewEntryType.receivable,
        Icons.account_balance_wallet_outlined,
        'Receivable',
        ac.success
      ),
      (NewEntryType.setAside, Icons.savings_outlined, 'Set-aside', ac.gold),
      (
        NewEntryType.installment,
        Icons.credit_score_outlined,
        'Installment',
        ac.purple
      ),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (type, icon, label, color) in options)
          _TypeChip(
            icon: icon,
            label: label,
            color: color,
            selected: value == type,
            onTap: () => onChanged(type),
          ),
      ],
    );
  }
}

class _TypeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _TypeChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? color.withValues(alpha: 0.15) : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? color
                  : cs.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 16, color: selected ? color : cs.onSurfaceVariant),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: selected ? color : cs.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
