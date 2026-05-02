import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class InstallmentListTile extends StatelessWidget {
  final Installment installment;
  final InstallmentPresenter presenter;
  final FinancialAccount? account;
  final VoidCallback onMarkPaid;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const InstallmentListTile({
    super.key,
    required this.installment,
    required this.presenter,
    required this.account,
    required this.onMarkPaid,
    required this.onEdit,
    required this.onDelete,
  });

  Color _accountColor(ColorScheme colorScheme) {
    if (account == null) return colorScheme.primary;
    try {
      final hex = account!.colorHex.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = _accountColor(colorScheme);

    final paid = presenter.isPaidForMonth(installment.id);
    final count = presenter.paidCount(installment.id);
    final remaining = presenter.remainingMonths(installment.id);
    final remainingAmt = presenter.remainingAmount(installment.id);
    final progress = installment.totalMonths > 0
        ? (count / installment.totalMonths).clamp(0.0, 1.0)
        : 0.0;

    return Semantics(
      label:
          '${installment.name}, ${paid ? 'paid' : 'unpaid'}, $count of ${installment.totalMonths} payments',
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onEdit();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────────────
              AppListTile(
                leading: AppIconBadge(
                    icon: Icons.credit_score_outlined, color: color),
                title: Text(
                  installment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: account != null
                    ? Text(
                        account!.name,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      )
                    : null,
                trailing: AppNumberDisplay(
                  value: formatPeso(installment.monthlyAmount)
                      .replaceFirst('₱', ''),
                  prefix: '₱',
                  suffix: '/mo',
                  size: AppNumberSize.body,
                  color: color,
                ),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              // ── Progress ─────────────────────────────────────────────────────
              AppLinearProgress(
                value: progress,
                label: '$count/${installment.totalMonths} paid',
                valueText:
                    remaining > 0 ? '${formatPeso(remainingAmt)} left' : null,
                color: color,
                height: 6,
              ),
              const SizedBox(height: 8),
              // ── Action row ───────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (paid)
                    _PaidChip(onUndo: () {
                      HapticFeedback.lightImpact();
                      presenter.markUnpaid(installment.id);
                    })
                  else
                    _MarkPaidButton(onTap: onMarkPaid, color: color),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(Icons.delete_outline,
                          size: 16, color: colorScheme.onSurfaceVariant),
                      onPressed: onDelete,
                      tooltip: 'Delete installment',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarkPaidButton extends StatelessWidget {
  final VoidCallback onTap;
  final Color color;

  const _MarkPaidButton({required this.onTap, required this.color});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(
          'Mark Paid',
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _PaidChip extends StatelessWidget {
  final VoidCallback onUndo;

  const _PaidChip({required this.onUndo});

  @override
  Widget build(BuildContext context) {
    const successColor = Color(0xFF4CAF50);
    return GestureDetector(
      onTap: onUndo,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: successColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: successColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check, color: successColor, size: 12),
            const SizedBox(width: 4),
            Text(
              'Paid · Undo',
              style: TextStyle(
                color: successColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
