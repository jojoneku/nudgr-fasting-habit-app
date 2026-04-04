import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

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

  Color get _accentColor {
    if (account == null) return AppColors.accent;
    try {
      final hex = account!.colorHex.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return AppColors.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final paid = presenter.isPaidForMonth(installment.id);
    final count = presenter.paidCount(installment.id);
    final remaining = presenter.remainingMonths(installment.id);
    final remainingAmt = presenter.remainingAmount(installment.id);
    final progress = installment.totalMonths > 0
        ? (count / installment.totalMonths).clamp(0.0, 1.0)
        : 0.0;
    final color = _accentColor;

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
              // ── Header row ──────────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          installment.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (account != null)
                          Text(
                            account!.name,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    '${formatPeso(installment.monthlyAmount)}/mo',
                    style: GoogleFonts.jetBrainsMono(
                      textStyle: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // ── Progress bar ─────────────────────────────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: color.withOpacity(0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 5,
                ),
              ),
              const SizedBox(height: 6),
              // ── Stats + action row ───────────────────────────────────────────
              Row(
                children: [
                  Text(
                    '$count/${installment.totalMonths} paid',
                    style: GoogleFonts.jetBrainsMono(
                      textStyle: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  if (remaining > 0) ...[
                    Text(
                      '  ·  ',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 11),
                    ),
                    Text(
                      '${formatPeso(remainingAmt)} left',
                      style: GoogleFonts.jetBrainsMono(
                        textStyle: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (paid)
                    _PaidChip(onUndo: () {
                      HapticFeedback.lightImpact();
                      presenter.markUnpaid(installment.id);
                    })
                  else
                    _MarkPaidButton(
                      onTap: onMarkPaid,
                      color: color,
                    ),
                  const SizedBox(width: 4),
                  _DeleteButton(onDelete: onDelete),
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
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.3)),
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
    return GestureDetector(
      onTap: onUndo,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.success.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.success.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check, color: AppColors.success, size: 12),
            const SizedBox(width: 4),
            Text(
              'Paid · Undo',
              style: TextStyle(
                color: AppColors.success,
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

class _DeleteButton extends StatelessWidget {
  final VoidCallback onDelete;

  const _DeleteButton({required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(Icons.delete_outline,
            size: 16, color: AppColors.textSecondary),
        onPressed: onDelete,
        tooltip: 'Delete installment',
      ),
    );
  }
}
