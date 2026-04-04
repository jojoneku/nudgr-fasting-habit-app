import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

class TransactionListTile extends StatelessWidget {
  final TransactionRecord txn;
  final FinancialAccount? account;
  final FinanceCategory? category;
  final VoidCallback? onTap;

  const TransactionListTile({
    super.key,
    required this.txn,
    this.account,
    this.category,
    this.onTap,
  });

  Color get _typeColor => switch (txn.type) {
    TransactionType.inflow   => AppColors.success,
    TransactionType.outflow  => AppColors.danger,
    TransactionType.transfer => Colors.amber,
  };

  String get _amountText {
    final f = formatPeso(txn.amount);
    return switch (txn.type) {
      TransactionType.inflow   => '+$f',
      TransactionType.outflow  => '-$f',
      TransactionType.transfer => '⇄ $f',
    };
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));
    } catch (_) {
      return AppColors.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTransfer = txn.type == TransactionType.transfer;
    final catColor = isTransfer
        ? Colors.amber
        : (category != null ? _parseColor(category!.colorHex) : AppColors.accent);
    final categoryLabel = isTransfer ? 'Transfer' : (category?.name ?? 'Uncategorized');
    final accountLabel  = account?.name ?? '';
    final subtitleParts = [categoryLabel, if (accountLabel.isNotEmpty) accountLabel];

    return Semantics(
      label: '${txn.description}, $_amountText, $accountLabel',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap != null
                ? () {
                    HapticFeedback.selectionClick();
                    onTap!();
                  }
                : null,
            borderRadius: BorderRadius.circular(12),
            splashColor: catColor.withOpacity(0.08),
            highlightColor: catColor.withOpacity(0.04),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: Row(
                children: [
                  _CategoryIcon(
                    isTransfer: isTransfer,
                    catColor: catColor,
                    letter: category?.name.isNotEmpty == true
                        ? category!.name[0].toUpperCase()
                        : '?',
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          txn.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitleParts.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _amountText,
                    style: GoogleFonts.jetBrainsMono(
                      textStyle: TextStyle(
                        color: _typeColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryIcon extends StatelessWidget {
  final bool isTransfer;
  final Color catColor;
  final String letter;

  const _CategoryIcon({
    required this.isTransfer,
    required this.catColor,
    required this.letter,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: catColor.withOpacity(0.12),
        shape: BoxShape.circle,
        border: Border.all(color: catColor.withOpacity(0.35), width: 1),
      ),
      child: Center(
        child: isTransfer
            ? Icon(Icons.swap_horiz, color: catColor, size: 20)
            : Text(
                letter,
                style: TextStyle(
                  color: catColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
      ),
    );
  }
}
