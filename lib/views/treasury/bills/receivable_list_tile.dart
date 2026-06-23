import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class ReceivableListTile extends StatelessWidget {
  final Receivable receivable;
  final VoidCallback onMarkReceived;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const ReceivableListTile({
    super.key,
    required this.receivable,
    required this.onMarkReceived,
    this.onEdit,
    this.onDelete,
  });

  Color _typeColor(ReceivableType type, BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (type) {
      case ReceivableType.salary:
        return context.appColors.success;
      case ReceivableType.reimbursement:
        return colorScheme.primary;
      case ReceivableType.business:
        return context.appColors.gold;
      case ReceivableType.other:
        return colorScheme.onSurfaceVariant;
    }
  }

  String _typeLabel(ReceivableType type) {
    switch (type) {
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final typeColor = _typeColor(receivable.receivableType, context);

    Widget subtitleWidget;
    {
      final parts = <Widget>[];
      parts.add(Text(
        'Expected ${DateFormat('MMM d').format(receivable.expectedDate)} · ${_typeLabel(receivable.receivableType)}',
        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
      ));
      if (receivable.isReceived && receivable.receivedAmount != null) {
        parts.add(const SizedBox(height: 2));
        parts.add(Text(
          'Received ${formatPeso(receivable.receivedAmount!)}'
          '${receivable.receivedDate != null ? ' · ${DateFormat('MMM d').format(receivable.receivedDate!)}' : ''}',
          style: TextStyle(
            color: context.appColors.success.withValues(alpha: 0.85),
            fontSize: 12,
          ),
        ));
      }
      subtitleWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: parts,
      );
    }

    return AppListTile(
      key: ValueKey('tile_${receivable.id}'),
      leading: AppIconBadge(
        icon: Icons.account_balance_wallet_outlined,
        color: typeColor,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              receivable.name,
              style: TextStyle(
                color: receivable.isReceived
                    ? colorScheme.onSurfaceVariant
                    : colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                decoration:
                    receivable.isReceived ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          const SizedBox(width: 4),
          AppBadge(
            text: _typeLabel(receivable.receivableType),
            color: typeColor,
          ),
        ],
      ),
      subtitle: subtitleWidget,
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            formatPeso(receivable.amount),
            style: TextStyle(
              color: receivable.isReceived
                  ? colorScheme.onSurfaceVariant
                  : colorScheme.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 13,
              decoration:
                  receivable.isReceived ? TextDecoration.lineThrough : null,
            ),
          ),
          if (receivable.isReceived)
            Icon(Icons.check_circle, color: context.appColors.success, size: 18)
          else
            TextButton(
              onPressed: onMarkReceived,
              style: TextButton.styleFrom(
                foregroundColor: context.appColors.success,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(44, 44),
              ),
              child: const Text(
                'Mark Received',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
      onLongPress: onEdit != null || onDelete != null
          ? () => _showContextMenu(context)
          : null,
      onDelete: onDelete != null
          ? () async {
              final confirmed = await AppConfirmDialog.confirm(
                context: context,
                title: 'Delete Receivable',
                body: 'Delete "${receivable.name}"?',
                confirmLabel: 'Delete',
                cancelLabel: 'Cancel',
                isDestructive: true,
              );
              if (confirmed) onDelete!();
              return confirmed;
            }
          : null,
    );
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
