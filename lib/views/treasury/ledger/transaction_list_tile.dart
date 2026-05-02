import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class TransactionListTile extends StatelessWidget {
  final TransactionRecord txn;
  final FinancialAccount? account;
  final FinanceCategory? category;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const TransactionListTile({
    super.key,
    required this.txn,
    this.account,
    this.category,
    this.onTap,
    this.onDelete,
  });

  Color _typeColor(ColorScheme cs) => switch (txn.type) {
        TransactionType.inflow => cs.tertiary,
        TransactionType.outflow => cs.error,
        TransactionType.transfer => cs.primary,
      };

  String get _amountText {
    final f = formatPeso(txn.amount);
    return switch (txn.type) {
      TransactionType.inflow => '+$f',
      TransactionType.outflow => '-$f',
      TransactionType.transfer => f,
    };
  }

  Color _parseColor(String hex, ColorScheme cs) {
    try {
      return Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));
    } catch (_) {
      return cs.primary;
    }
  }

  IconData _categoryIcon() {
    if (txn.type == TransactionType.transfer) return Icons.swap_horiz_rounded;
    return Icons.label_outline_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isTransfer = txn.type == TransactionType.transfer;
    final catColor = isTransfer
        ? cs.primary
        : (category != null ? _parseColor(category!.colorHex, cs) : cs.primary);
    final categoryLabel =
        isTransfer ? 'Transfer' : (category?.name ?? 'Uncategorized');
    final accountLabel = account?.name ?? '';
    final subtitleParts = [
      categoryLabel,
      if (accountLabel.isNotEmpty) accountLabel,
    ];

    return Semantics(
      label: '${txn.description}, $_amountText, $accountLabel',
      child: AppListTile(
        key: key,
        leading: AppIconBadge(
          icon: _categoryIcon(),
          color: catColor,
          size: 44,
          iconSize: 20,
        ),
        title: Text(
          txn.description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(subtitleParts.join(' · ')),
        trailing: AppNumberDisplay(
          value: _amountText,
          size: AppNumberSize.body,
          color: _typeColor(cs),
        ),
        onTap: onTap,
        onLongPress: onTap != null
            ? () async {
                final action = await AppActionSheet.show<String>(
                  context: context,
                  actions: [
                    const AppActionSheetItem(
                      label: 'Edit',
                      value: 'edit',
                      icon: Icons.edit_outlined,
                    ),
                    const AppActionSheetItem(
                      label: 'Delete',
                      value: 'delete',
                      icon: Icons.delete_outline_rounded,
                      isDestructive: true,
                    ),
                  ],
                );
                if (action == 'edit' && onTap != null) onTap!();
                if (action == 'delete' && onDelete != null) onDelete!();
              }
            : null,
        onDelete: onDelete != null ? () async => true : null,
      ),
    );
  }
}
