import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
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

  /// Which optional long-press actions this row offers (from
  /// [LedgerPresenter.rowActionsFor]). Null offers only Edit, Duplicate and
  /// Delete.
  final LedgerRowActions? actions;
  final VoidCallback? onDuplicate;
  final VoidCallback? onSplit;
  final VoidCallback? onReimbursable;

  /// The record's date, printed after the account name. Null hides it; day
  /// headers carry the date in the grouped list.
  final String? dateLabel;

  const TransactionListTile({
    super.key,
    required this.txn,
    this.account,
    this.accountColor,
    this.category,
    this.onTap,
    this.onDelete,
    this.actions,
    this.onDuplicate,
    this.onSplit,
    this.onReimbursable,
    this.dateLabel,
  });

  /// The record's note, trimmed, or null when there is none. Shown as one
  /// muted line under the account name.
  String? get _noteLine {
    final note = txn.note?.trim() ?? '';
    return note.isEmpty ? null : note;
  }

  /// Long-press sheet: the web v2 row menu, same visibility rules.
  List<AppActionSheetItem<_RowAction>> get _menuItems => [
        const AppActionSheetItem(
          label: 'Edit',
          value: _RowAction.edit,
          icon: Icons.edit_outlined,
        ),
        if (onDuplicate != null)
          const AppActionSheetItem(
            label: 'Duplicate',
            value: _RowAction.duplicate,
            icon: Icons.content_copy_outlined,
          ),
        if (actions?.canSplit == true && onSplit != null)
          AppActionSheetItem(
            label: actions!.splitLabel,
            value: _RowAction.split,
            icon: Icons.calendar_view_month_outlined,
          ),
        if (actions?.canMarkReimbursable == true && onReimbursable != null)
          AppActionSheetItem(
            label: actions!.reimbursableLabel,
            value: _RowAction.reimbursable,
            icon: Icons.keyboard_return_rounded,
          ),
        if (onDelete != null)
          const AppActionSheetItem(
            label: 'Delete',
            value: _RowAction.delete,
            icon: Icons.delete_outline_rounded,
            isDestructive: true,
          ),
      ];

  Future<void> _showRowMenu(BuildContext context) async {
    final action = await AppActionSheet.show<_RowAction>(
      context: context,
      actions: _menuItems,
    );
    switch (action) {
      case _RowAction.edit:
        onTap?.call();
      case _RowAction.duplicate:
        onDuplicate?.call();
      case _RowAction.split:
        onSplit?.call();
      case _RowAction.reimbursable:
        onReimbursable?.call();
      case _RowAction.delete:
        onDelete?.call();
      case null:
        break;
    }
  }

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
    final noteLine = _noteLine;

    return Semantics(
      label: '${txn.description}, $_amountText, $accountLabel',
      child: AppListTile(
        key: key,
        // Each row is its own card: a lighter grey fill on the darker screen
        // background, so a day's transactions read as a stack of items rather
        // than as text on the page.
        cardColor: cs.surfaceContainerLow,
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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
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
                    style:
                        TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                  ),
                ),
                if (dateLabel != null)
                  Text(
                    ' · $dateLabel',
                    key: const ValueKey('txnDateLabel'),
                    maxLines: 1,
                    style:
                        TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                  ),
                if (txn.isInstallment) ...[
                  const SizedBox(width: 6),
                  const AppBadge(
                    text: 'Installment',
                    size: AppBadgeSize.small,
                  ),
                ],
              ],
            ),
            if (noteLine != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  noteLine,
                  key: const ValueKey('txnNoteLine'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontStyle: FontStyle.italic,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
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
        onLongPress: onTap != null ? () => _showRowMenu(context) : null,
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

enum _RowAction { edit, duplicate, split, reimbursable, delete }
