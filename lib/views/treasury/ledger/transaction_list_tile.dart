import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

final _dateFmt = DateFormat('MMM d');

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

  Color get _amountColor {
    switch (txn.type) {
      case TransactionType.inflow:
        return AppColors.success;
      case TransactionType.outflow:
        return AppColors.danger;
      case TransactionType.transfer:
        return Colors.amber;
    }
  }

  String get _amountText {
    final formatted = formatPeso(txn.amount);
    switch (txn.type) {
      case TransactionType.inflow:
        return '+$formatted';
      case TransactionType.outflow:
        return '-$formatted';
      case TransactionType.transfer:
        return '→ $formatted';
    }
  }

  Color _parseColor(String hex) {
    try {
      final clean = hex.replaceFirst('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return AppColors.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${txn.description}, $_amountText, ${account?.name ?? ''}',
      child: ListTile(
        onTap: onTap != null ? () { HapticFeedback.selectionClick(); onTap!(); } : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: _LeadingCircle(txn: txn, category: category, parseColor: _parseColor),
        title: Text(
          txn.description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '${account?.name ?? ''} · ${_dateFmt.format(txn.date)}',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        trailing: Text(
          _amountText,
          style: GoogleFonts.jetBrainsMono(
            textStyle: TextStyle(color: _amountColor, fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ),
      ),
    );
  }
}

class _LeadingCircle extends StatelessWidget {
  final TransactionRecord txn;
  final FinanceCategory? category;
  final Color Function(String) parseColor;

  const _LeadingCircle({
    required this.txn,
    required this.category,
    required this.parseColor,
  });

  @override
  Widget build(BuildContext context) {
    if (txn.type == TransactionType.transfer) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.amber.withOpacity(0.15),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.swap_horiz, color: Colors.amber, size: 20),
      );
    }

    final catColor = category != null ? parseColor(category!.colorHex) : AppColors.accent;
    final letter = category?.name.isNotEmpty == true ? category!.name[0].toUpperCase() : '?';

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: catColor.withOpacity(0.15),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(color: catColor, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
    );
  }
}
