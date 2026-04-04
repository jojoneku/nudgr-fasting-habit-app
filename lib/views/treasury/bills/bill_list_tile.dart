import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intl/intl.dart';

class BillListTile extends StatelessWidget {
  final Bill bill;
  final VoidCallback onMarkPaid;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const BillListTile({
    super.key,
    required this.bill,
    required this.onMarkPaid,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(bill.id),
      direction: DismissDirection.endToStart,
      background: _DismissBackground(),
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) => onDelete?.call(),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: _TileTitle(bill: bill),
        subtitle: _TileSubtitle(bill: bill),
        trailing: _TileTrailing(bill: bill, onMarkPaid: onMarkPaid),
        onLongPress: () => _showContextMenu(context),
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Delete Bill',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          'Delete "${bill.name}"?',
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

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onEdit != null)
              ListTile(
                leading: Icon(Icons.edit_outlined, color: AppColors.accent),
                title: Text('Edit',
                    style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  onEdit?.call();
                },
              ),
            if (onDelete != null)
              ListTile(
                leading: Icon(Icons.delete_outline, color: AppColors.danger),
                title:
                    Text('Delete', style: TextStyle(color: AppColors.danger)),
                onTap: () {
                  Navigator.pop(context);
                  onDelete?.call();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _TileTitle extends StatelessWidget {
  final Bill bill;

  const _TileTitle({required this.bill});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            bill.name,
            style: TextStyle(
              color:
                  bill.isPaid ? AppColors.textSecondary : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              decoration: bill.isPaid ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _BillTypeBadge(billType: bill.billType),
      ],
    );
  }
}

class _TileSubtitle extends StatelessWidget {
  final Bill bill;

  const _TileSubtitle({required this.bill});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              formatPeso(bill.amount),
              style: TextStyle(
                color: bill.isPaid
                    ? AppColors.textSecondary
                    : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Due ${_ordinal(bill.dueDay)}',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
        if (bill.isPaid && bill.paidAmount != null) ...[
          const SizedBox(height: 2),
          Text(
            'Paid ${formatPeso(bill.paidAmount!)}${bill.paidDate != null ? '  ·  ${DateFormat('MMM d').format(bill.paidDate!)}' : ''}',
            style: TextStyle(
                color: AppColors.success.withOpacity(0.8), fontSize: 12),
          ),
        ],
        if (bill.paymentNote != null && bill.paymentNote!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            bill.paymentNote!,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
        ],
      ],
    );
  }

  String _ordinal(int day) {
    if (day >= 11 && day <= 13) return '${day}th';
    switch (day % 10) {
      case 1:
        return '${day}st';
      case 2:
        return '${day}nd';
      case 3:
        return '${day}rd';
      default:
        return '${day}th';
    }
  }
}

class _TileTrailing extends StatelessWidget {
  final Bill bill;
  final VoidCallback onMarkPaid;

  const _TileTrailing({required this.bill, required this.onMarkPaid});

  @override
  Widget build(BuildContext context) {
    if (bill.isPaid) {
      return Icon(Icons.check_circle, color: AppColors.success, size: 24);
    }
    return SizedBox(
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
    );
  }
}

class _BillTypeBadge extends StatelessWidget {
  final BillType billType;

  const _BillTypeBadge({required this.billType});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _color.withOpacity(0.4), width: 0.5),
      ),
      child: Text(
        _label,
        style: TextStyle(
            color: _color,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3),
      ),
    );
  }

  Color get _color {
    switch (billType) {
      case BillType.creditCard:
        return AppColors.danger;
      case BillType.installment:
        return AppColors.gold;
      case BillType.subscription:
        return AppColors.accent;
      case BillType.insurance:
        return AppColors.success;
      case BillType.govtContribution:
        return const Color(0xFF9C27B0);
      case BillType.utility:
        return const Color(0xFFFF9800);
      case BillType.other:
        return AppColors.textSecondary;
    }
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
        return 'OTHER';
    }
  }
}

class _DismissBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(0.2),
      ),
      child: Icon(Icons.delete_outline, color: AppColors.danger, size: 24),
    );
  }
}
