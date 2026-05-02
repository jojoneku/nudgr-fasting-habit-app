import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class BudgetedExpenseTile extends StatelessWidget {
  final BudgetedExpense expense;
  final VoidCallback onMarkPaid;
  final VoidCallback? onDelete;

  const BudgetedExpenseTile({
    super.key,
    required this.expense,
    required this.onMarkPaid,
    this.onDelete,
  });

  String _typeLabel(BillType type) {
    switch (type) {
      case BillType.creditCard:
        return 'CC';
      case BillType.installment:
        return 'INSTALL';
      case BillType.subscription:
        return 'SUB';
      case BillType.insurance:
        return 'INS';
      case BillType.govtContribution:
        return 'GOV';
      case BillType.utility:
        return 'UTIL';
      case BillType.other:
        return 'BUDGETED';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const goldColor = Color(0xFFFFB300);

    final isOver = expense.spentAmount > expense.allocatedAmount;
    final progress = expense.allocatedAmount > 0
        ? (expense.spentAmount / expense.allocatedAmount).clamp(0.0, 1.0)
        : 0.0;

    return AppListTile(
      key: ValueKey('tile_${expense.id}'),
      leading: AppIconBadge(
        icon: Icons.savings_outlined,
        color: goldColor,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              expense.name,
              style: TextStyle(
                color: expense.isPaid
                    ? colorScheme.onSurfaceVariant
                    : colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                decoration: expense.isPaid ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          const SizedBox(width: 4),
          AppBadge(
            text: _typeLabel(expense.budgetedType),
            color: goldColor,
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 4),
          AppLinearProgress(
            value: progress,
            label: '${formatPeso(expense.spentAmount)} spent',
            valueText: 'of ${formatPeso(expense.allocatedAmount)}',
            color: isOver ? colorScheme.error : colorScheme.primary,
            height: 6,
          ),
          if (expense.note != null && expense.note!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              expense.note!,
              style:
                  TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11),
            ),
          ],
        ],
      ),
      trailing: expense.isPaid
          ? Icon(Icons.check_circle, color: const Color(0xFF4CAF50), size: 24)
          : SizedBox(
              height: 44,
              child: TextButton(
                onPressed: onMarkPaid,
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text(
                  'Mark Paid',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
      onDelete: onDelete != null
          ? () => AppConfirmDialog.confirm(
                context: context,
                title: 'Delete Expense',
                body: 'Delete "${expense.name}"?',
                confirmLabel: 'Delete',
                cancelLabel: 'Cancel',
                isDestructive: true,
              )
          : null,
    );
  }
}
