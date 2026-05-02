import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

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

  Color _typeColor(ReceivableType type, ColorScheme colorScheme) {
    switch (type) {
      case ReceivableType.salary:
        return const Color(0xFF4CAF50);
      case ReceivableType.reimbursement:
        return colorScheme.primary;
      case ReceivableType.business:
        return const Color(0xFFFFB300);
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
    final typeColor = _typeColor(receivable.receivableType, colorScheme);

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
            color: const Color(0xFF4CAF50).withValues(alpha: 0.85),
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
      trailing: receivable.isReceived
          ? Icon(Icons.check_circle,
              color: const Color(0xFF4CAF50), size: 24)
          : SizedBox(
              height: 44,
              child: TextButton(
                onPressed: onMarkReceived,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF4CAF50),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text(
                  'Mark Received',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
      onDelete: onDelete != null
          ? () => AppConfirmDialog.confirm(
                context: context,
                title: 'Delete Receivable',
                body: 'Delete "${receivable.name}"?',
                confirmLabel: 'Delete',
                cancelLabel: 'Cancel',
                isDestructive: true,
              )
          : null,
    );
  }
}
