import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/utils/app_motion.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class BudgetedExpenseTile extends StatelessWidget {
  final BudgetedExpense expense;
  final VoidCallback onMarkPaid;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// Resolved name of the funding account this set-aside is assigned to, shown
  /// under the progress bar. Null when no account is set.
  final String? accountName;

  const BudgetedExpenseTile({
    super.key,
    required this.expense,
    required this.onMarkPaid,
    this.onEdit,
    this.onDelete,
    this.accountName,
  });

  String _typeLabel(SetAsideType type) => switch (type) {
        SetAsideType.savings => 'SAVINGS',
        SetAsideType.goal => 'GOAL',
        SetAsideType.sinkingFund => 'SINKING',
        SetAsideType.gift => 'GIFT',
        SetAsideType.other => 'BUDGETED',
      };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final goldColor = context.appColors.gold;

    final isOver = expense.spentAmount > expense.allocatedAmount;
    final progress = expense.allocatedAmount > 0
        ? (expense.spentAmount / expense.allocatedAmount).clamp(0.0, 1.0)
        : 0.0;

    // Funded set-asides read as clearly deactivated (dimmed), not just struck out.
    return AnimatedOpacity(
        opacity: expense.isPaid ? 0.5 : 1.0,
        duration: AppMotion.appear,
        child: AppListTile(
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
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
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
                  style: TextStyle(
                      color: colorScheme.onSurfaceVariant, fontSize: 11),
                ),
              ],
              if (accountName != null) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.account_balance_wallet_outlined,
                        size: 12, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      'Fund from $accountName',
                      style: TextStyle(
                          color: colorScheme.onSurfaceVariant, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ],
          ),
          trailing: expense.isPaid
              ? Icon(Icons.check_circle,
                  color: context.appColors.success, size: 24)
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
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
          onLongPress: onEdit != null || onDelete != null
              ? () => _showContextMenu(context)
              : null,
          onDelete: onDelete != null
              ? () async {
                  final confirmed = await AppConfirmDialog.confirm(
                    context: context,
                    title: 'Delete Expense',
                    body: 'Delete "${expense.name}"?',
                    confirmLabel: 'Delete',
                    cancelLabel: 'Cancel',
                    isDestructive: true,
                  );
                  if (confirmed) onDelete!();
                  return confirmed;
                }
              : null,
        ));
  }

  void _showContextMenu(BuildContext context) {
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
            if (onEdit != null)
              ListTile(
                leading: Icon(Icons.edit_outlined, color: colorScheme.primary),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.pop(context);
                  onEdit!();
                },
              ),
            if (onDelete != null)
              ListTile(
                leading: Icon(Icons.delete_outline, color: colorScheme.error),
                title:
                    Text('Delete', style: TextStyle(color: colorScheme.error)),
                onTap: () {
                  Navigator.pop(context);
                  onDelete!();
                },
              ),
          ],
        ),
      ),
    );
  }
}
