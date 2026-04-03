import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intl/intl.dart';

class ReceivableListTile extends StatelessWidget {
  final Receivable receivable;
  final VoidCallback onMarkReceived;
  final VoidCallback? onDelete;

  const ReceivableListTile({
    super.key,
    required this.receivable,
    required this.onMarkReceived,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(receivable.id),
      direction: DismissDirection.endToStart,
      background: _DismissBackground(),
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) => onDelete?.call(),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: _TileTitle(receivable: receivable),
        subtitle: _TileSubtitle(receivable: receivable),
        trailing: _TileTrailing(receivable: receivable, onMarkReceived: onMarkReceived),
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete Receivable', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Delete "${receivable.name}"?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
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

class _TileTitle extends StatelessWidget {
  final Receivable receivable;

  const _TileTitle({required this.receivable});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            receivable.name,
            style: TextStyle(
              color: receivable.isReceived ? AppColors.textSecondary : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              decoration: receivable.isReceived ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _ReceivableTypeBadge(receivableType: receivable.receivableType),
      ],
    );
  }
}

class _TileSubtitle extends StatelessWidget {
  final Receivable receivable;

  const _TileSubtitle({required this.receivable});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              formatPeso(receivable.amount),
              style: TextStyle(
                color: receivable.isReceived ? AppColors.textSecondary : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Expected ${DateFormat('MMM d').format(receivable.expectedDate)}',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
        if (receivable.isReceived && receivable.receivedAmount != null) ...[
          const SizedBox(height: 2),
          Text(
            'Received ${formatPeso(receivable.receivedAmount!)}${receivable.receivedDate != null ? '  ·  ${DateFormat('MMM d').format(receivable.receivedDate!)}' : ''}',
            style: TextStyle(color: AppColors.success.withOpacity(0.8), fontSize: 12),
          ),
        ],
      ],
    );
  }
}

class _TileTrailing extends StatelessWidget {
  final Receivable receivable;
  final VoidCallback onMarkReceived;

  const _TileTrailing({required this.receivable, required this.onMarkReceived});

  @override
  Widget build(BuildContext context) {
    if (receivable.isReceived) {
      return Icon(Icons.check_circle, color: AppColors.success, size: 24);
    }
    return SizedBox(
      height: 44,
      child: TextButton(
        onPressed: onMarkReceived,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.success,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        child: const Text(
          'Mark Received',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _ReceivableTypeBadge extends StatelessWidget {
  final ReceivableType receivableType;

  const _ReceivableTypeBadge({required this.receivableType});

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
        style: TextStyle(color: _color, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.3),
      ),
    );
  }

  Color get _color {
    switch (receivableType) {
      case ReceivableType.salary:
        return AppColors.success;
      case ReceivableType.reimbursement:
        return AppColors.accent;
      case ReceivableType.business:
        return AppColors.gold;
      case ReceivableType.other:
        return AppColors.textSecondary;
    }
  }

  String get _label {
    switch (receivableType) {
      case ReceivableType.salary:
        return 'SALARY';
      case ReceivableType.reimbursement:
        return 'REIMB';
      case ReceivableType.business:
        return 'BIZ';
      case ReceivableType.other:
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
      color: AppColors.danger.withOpacity(0.2),
      child: Icon(Icons.delete_outline, color: AppColors.danger, size: 24),
    );
  }
}
