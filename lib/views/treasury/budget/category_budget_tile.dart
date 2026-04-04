import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

class CategoryBudgetTile extends StatelessWidget {
  final FinanceCategory category;
  final Budget? budget;
  final double spent;
  final double received;
  final bool isIncome;
  final List<TransactionRecord> transactions;

  const CategoryBudgetTile({
    super.key,
    required this.category,
    required this.budget,
    required this.spent,
    required this.received,
    required this.isIncome,
    required this.transactions,
  });

  @override
  Widget build(BuildContext context) {
    final allocated = budget?.allocatedAmount ?? 0.0;
    final actual = isIncome ? received : spent;
    final progress = allocated > 0 ? (actual / allocated).clamp(0.0, 2.0) : 0.0;
    final isOver = actual > allocated && allocated > 0;
    final isUnder = actual < allocated && allocated > 0 && isIncome;

    Color progressColor;
    if (isIncome) {
      progressColor = isOver ? AppColors.success : AppColors.gold;
    } else {
      progressColor = isOver ? AppColors.danger : AppColors.accent;
    }

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: EdgeInsets.zero,
        title: _TileHeader(
          category: category,
          budget: budget,
          actual: actual,
          allocated: allocated,
          isIncome: isIncome,
          isOver: isOver,
          isUnder: isUnder,
          progressColor: progressColor,
          progress: progress,
        ),
        children: transactions.isEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text(
                    'No transactions this month',
                    style:
                        TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ),
              ]
            : transactions.map((t) => _TransactionRow(transaction: t)).toList(),
      ),
    );
  }
}

class _TileHeader extends StatelessWidget {
  final FinanceCategory category;
  final Budget? budget;
  final double actual;
  final double allocated;
  final bool isIncome;
  final bool isOver;
  final bool isUnder;
  final Color progressColor;
  final double progress;

  const _TileHeader({
    required this.category,
    required this.budget,
    required this.actual,
    required this.allocated,
    required this.isIncome,
    required this.isOver,
    required this.isUnder,
    required this.progressColor,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final pct = allocated > 0 ? '${(actual / allocated * 100).round()}%' : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                category.name,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (budget != null)
              _BudgetTypeBadge(budgetType: budget!.budgetType),
            const SizedBox(width: 8),
            _AmountPair(
              actual: actual,
              allocated: allocated,
              isOver: isOver,
              isIncome: isIncome,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 5,
                  backgroundColor: AppColors.textSecondary.withOpacity(0.15),
                  valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              pct,
              style: TextStyle(
                color: isOver
                    ? (isIncome ? AppColors.success : AppColors.danger)
                    : AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AmountPair extends StatelessWidget {
  final double actual;
  final double allocated;
  final bool isOver;
  final bool isIncome;

  const _AmountPair({
    required this.actual,
    required this.allocated,
    required this.isOver,
    required this.isIncome,
  });

  @override
  Widget build(BuildContext context) {
    final actualColor = isOver
        ? (isIncome ? AppColors.success : AppColors.danger)
        : AppColors.textPrimary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          formatPesoCompact(actual),
          style: TextStyle(
              color: actualColor, fontSize: 13, fontWeight: FontWeight.w700),
        ),
        Text(
          ' / ${formatPesoCompact(allocated)}',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}

class _BudgetTypeBadge extends StatelessWidget {
  final BudgetType budgetType;

  const _BudgetTypeBadge({required this.budgetType});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.textSecondary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _label,
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 9,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  String get _label => switch (budgetType) {
        BudgetType.monthly => 'MONTHLY',
        BudgetType.fixed => 'FIXED',
        BudgetType.goal => 'GOAL',
        BudgetType.variable => 'VAR',
      };
}

class _TransactionRow extends StatelessWidget {
  final TransactionRecord transaction;

  const _TransactionRow({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final isInflow = transaction.type == TransactionType.inflow;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 28,
            decoration: BoxDecoration(
              color: isInflow
                  ? AppColors.success.withOpacity(0.5)
                  : AppColors.danger.withOpacity(0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              transaction.description,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            DateFormat('MMM d').format(transaction.date),
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
          const SizedBox(width: 8),
          Text(
            '${isInflow ? '+' : '-'}${formatPesoCompact(transaction.amount)}',
            style: TextStyle(
              color: isInflow ? AppColors.success : AppColors.danger,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
