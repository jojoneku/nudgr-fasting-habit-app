import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

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

  @override
  Widget build(BuildContext context) {
    final progress = expense.allocatedAmount > 0
        ? (expense.spentAmount / expense.allocatedAmount).clamp(0.0, 1.0)
        : 0.0;

    return Dismissible(
      key: ValueKey(expense.id),
      direction: DismissDirection.endToStart,
      background: _DismissBackground(),
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) => onDelete?.call(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TileHeader(expense: expense, onMarkPaid: onMarkPaid),
            const SizedBox(height: 6),
            _ProgressRow(expense: expense, progress: progress),
            if (expense.note != null && expense.note!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                expense.note!,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete Expense',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Delete "${expense.name}"?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}

class _TileHeader extends StatelessWidget {
  final BudgetedExpense expense;
  final VoidCallback onMarkPaid;

  const _TileHeader({required this.expense, required this.onMarkPaid});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            expense.name,
            style: TextStyle(
              color: expense.isPaid
                  ? AppColors.textSecondary
                  : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              decoration: expense.isPaid ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _BudgetedTypeBadge(billType: expense.budgetedType),
        const SizedBox(width: 8),
        if (expense.isPaid)
          Icon(Icons.check_circle, color: AppColors.success, size: 24)
        else
          SizedBox(
            height: 44,
            child: TextButton(
              onPressed: onMarkPaid,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text(
                'Mark Paid',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
      ],
    );
  }
}

class _ProgressRow extends StatelessWidget {
  final BudgetedExpense expense;
  final double progress;

  const _ProgressRow({required this.expense, required this.progress});

  @override
  Widget build(BuildContext context) {
    final isOver = expense.spentAmount > expense.allocatedAmount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${formatPeso(expense.spentAmount)} spent',
              style: TextStyle(
                color: isOver ? AppColors.danger : AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            Text(
              'of ${formatPeso(expense.allocatedAmount)}',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: AppColors.textSecondary.withOpacity(0.15),
            valueColor: AlwaysStoppedAnimation<Color>(
              isOver ? AppColors.danger : AppColors.accent,
            ),
          ),
        ),
      ],
    );
  }
}

class _BudgetedTypeBadge extends StatelessWidget {
  final BillType billType;

  const _BudgetedTypeBadge({required this.billType});

  @override
  Widget build(BuildContext context) {
    const color = AppColors.gold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.4), width: 0.5),
      ),
      child: Text(
        _label,
        style: const TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  String get _label {
    switch (billType) {
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
}

class _DismissBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      color: AppColors.danger.withOpacity(0.2),
      child: Icon(Icons.delete_outline, color: AppColors.danger, size: 24),
    );
  }
}
