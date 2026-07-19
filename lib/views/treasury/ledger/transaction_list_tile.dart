import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/shared/category_badge_widget.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class TransactionListTile extends StatelessWidget {
  final TransactionRecord txn;
  final FinancialAccount? account;

  /// Palette-indexed, brightness-aware swatch color for the account, rendered
  /// as a small dot before the account name in the subtitle. Null hides it.
  final Color? accountColor;
  final FinanceCategory? category;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const TransactionListTile({
    super.key,
    required this.txn,
    this.account,
    this.accountColor,
    this.category,
    this.onTap,
    this.onDelete,
  });

  // Amount coloring stays semantic (spec §4): income green, expense red,
  // transfer neutral grey — so the red/green scan reads on every row.
  Color _typeColor(ColorScheme cs) => switch (txn.type) {
        TransactionType.inflow => cs.tertiary,
        TransactionType.outflow => cs.error,
        TransactionType.transfer => cs.onSurfaceVariant,
      };

  String get _amountText {
    final f = formatPeso(txn.amount);
    return switch (txn.type) {
      TransactionType.inflow => '+$f',
      // U+2212 minus (matches the IN/OUT/NET strip and daily-net badge).
      TransactionType.outflow => '−$f',
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
    // The colored category icon now carries the category identity, so the row
    // subtitle is the account name only (spec §4). When a txn has no account we
    // fall back to the category label so the subtitle is never blank. The
    // account color dot (kept from the pre-redesign row) precedes the account
    // name so accounts stay distinguishable at a glance.
    final subtitleText = accountLabel.isNotEmpty ? accountLabel : categoryLabel;
    final showAccountDot = accountLabel.isNotEmpty && accountColor != null;

    return Semantics(
      label: '${txn.description}, $_amountText, $accountLabel',
      child: AppListTile(
        key: key,
        leading: isTransfer
            ? AppIconBadge(
                icon: Icons.swap_horiz_rounded,
                color: catColor,
                size: 40,
                iconSize: 18,
              )
            : CategoryBadge(
                iconKey: category?.icon,
                name: category?.name,
                type: category?.type ?? CategoryType.expense,
                color: catColor,
                size: 40,
                iconSize: 18,
              ),
        title: Text(
          txn.description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
        ),
        subtitle: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showAccountDot) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accountColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                subtitleText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
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
        onDelete: onDelete != null
            ? () async {
                onDelete!();
                return true;
              }
            : null,
      ),
    );
  }
}
