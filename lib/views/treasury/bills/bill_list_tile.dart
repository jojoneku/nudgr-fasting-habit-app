import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

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

  Color _billTypeColor(BillType type, ColorScheme colorScheme) {
    switch (type) {
      case BillType.creditCard:
        return colorScheme.error;
      case BillType.installment:
        return const Color(0xFFFFB300);
      case BillType.subscription:
        return colorScheme.primary;
      case BillType.insurance:
        return const Color(0xFF4CAF50);
      case BillType.govtContribution:
        return const Color(0xFF9C27B0);
      case BillType.utility:
        return const Color(0xFFFF9800);
      case BillType.other:
        return colorScheme.onSurfaceVariant;
    }
  }

  String _billTypeLabel(BillType type) {
    switch (type) {
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final typeColor = _billTypeColor(bill.billType, colorScheme);

    Widget? subtitleWidget;
    {
      final parts = <Widget>[];
      parts.add(Text(
        'Due ${_ordinal(bill.dueDay)} · ${_billTypeLabel(bill.billType)}',
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ));
      if (bill.isPaid && bill.paidAmount != null) {
        parts.add(const SizedBox(height: 2));
        parts.add(Text(
          'Paid ${formatPeso(bill.paidAmount!)}'
          '${bill.paidDate != null ? ' · ${DateFormat('MMM d').format(bill.paidDate!)}' : ''}',
          style: TextStyle(
            color: const Color(0xFF4CAF50).withValues(alpha: 0.85),
            fontSize: 12,
          ),
        ));
      }
      if (bill.paymentNote != null && bill.paymentNote!.isNotEmpty) {
        parts.add(const SizedBox(height: 2));
        parts.add(Text(
          bill.paymentNote!,
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11),
        ));
      }
      subtitleWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: parts,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppListTile(
          key: ValueKey('tile_${bill.id}'),
          leading: AppIconBadge(
            icon: Icons.receipt_outlined,
            color: typeColor,
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  bill.name,
                  style: TextStyle(
                    color: bill.isPaid
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    decoration: bill.isPaid ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              AppBadge(
                text: _billTypeLabel(bill.billType),
                color: typeColor,
              ),
            ],
          ),
          subtitle: subtitleWidget,
          trailing: bill.isPaid
              ? Icon(Icons.check_circle,
                  color: const Color(0xFF4CAF50), size: 24)
              : SizedBox(
                  height: 44,
                  child: TextButton(
                    onPressed: onMarkPaid,
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text(
                      'Mark Paid',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
          onLongPress: onEdit != null ? () => _showContextMenu(context) : null,
          onDelete: onDelete != null
              ? () => AppConfirmDialog.confirm(
                    context: context,
                    title: 'Delete Bill',
                    body: 'Delete "${bill.name}"?',
                    confirmLabel: 'Delete',
                    cancelLabel: 'Cancel',
                    isDestructive: true,
                  )
              : null,
        ),
      ],
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
                  onEdit?.call();
                },
              ),
            if (onDelete != null)
              ListTile(
                leading: Icon(Icons.delete_outline, color: colorScheme.error),
                title:
                    Text('Delete', style: TextStyle(color: colorScheme.error)),
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
