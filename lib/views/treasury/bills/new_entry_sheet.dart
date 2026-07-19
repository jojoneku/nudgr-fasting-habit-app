import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    final cs = Theme.of(context).colorScheme;
    // A single segmented control: four equal compartments in one rounded track,
    // the active one filled with its type accent (per the reference).
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final (type, icon, label, color) in options)
            Expanded(
              child: _TypeSegment(
                icon: icon,
                label: label,
                color: color,
                selected: value == type,
                onTap: () => onChanged(type),
              ),
            ),
        ],
      ),
    );
  }
}

/// One compartment of the type segmented control: icon over label, stacked so
/// the four (incl. the long "Receivable"/"Installment") fit in a single row.
class _TypeSegment extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _TypeSegment({
    required this.icon,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? Colors.white : cs.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: selected
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap();
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
          decoration: BoxDecoration(
            color: selected ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
