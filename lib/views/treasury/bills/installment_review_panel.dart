import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/utils/app_radii.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// Keys the review step's tests and the web dialog share.
abstract final class InstallmentReviewKeys {
  static const panel = ValueKey('installmentReview.panel');
  static const useSuggested = ValueKey('installmentReview.useSuggested');
  static const back = ValueKey('installmentReview.back');
  static const confirm = ValueKey('installmentReview.confirm');
}

/// The installment form's review step (Plan 067): the schedule, the first
/// statement and the receivables a save commits to. Every string comes from
/// the presenters; this only lays them out. The mobile review sheet and the
/// web dialog's review page both show it.
class InstallmentReviewPanel extends StatelessWidget {
  final InstallmentReview review;
  final InstallmentReceivablePreview? receivables;

  /// Takes the start month the card's cycle gives. Shown only when
  /// [InstallmentReview.startMonthWarning] is set.
  final VoidCallback? onUseSuggested;

  const InstallmentReviewPanel({
    super.key = InstallmentReviewKeys.panel,
    required this.review,
    required this.receivables,
    this.onUseSuggested,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final warning = review.startMonthWarning;
    final preview = receivables;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (warning != null) ...[
          _StartMonthWarning(
            text: warning,
            actionLabel: review.suggestedStartLabel,
            onAction: onUseSuggested,
          ),
          const SizedBox(height: 12),
        ],
        _ReviewRow('First payment', review.firstMonth),
        _ReviewRow('Last payment', review.lastMonth),
        _ReviewRow('Monthly', review.monthly),
        _ReviewRow('Total', review.total, strong: true),
        _ReviewRow('Deferral', review.deferral),
        _ReviewRow('Statement close', review.statementClose),
        _ReviewRow('First due date', review.firstDue),
        if (preview != null) ...[
          const SizedBox(height: 12),
          Divider(height: 1, color: cs.outlineVariant),
          const SizedBox(height: 12),
          Text(
            preview.title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            preview.summary,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          for (final row in preview.rows) _ReceivableRow(row),
        ],
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;

  const _ReviewRow(this.label, this.value, {this.strong = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceivableRow extends StatelessWidget {
  final InstallmentReceivablePreviewRow row;

  const _ReceivableRow(this.row);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = row.isRemoval ? cs.error : cs.onSurface;
    final decoration = row.isRemoval ? TextDecoration.lineThrough : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              row.month,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: color, decoration: decoration),
            ),
          ),
          Text(
            row.amount,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: color, decoration: decoration),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 104,
            child: Text(
              row.status,
              textAlign: TextAlign.end,
              style: theme.textTheme.labelMedium?.copyWith(
                color: row.isRemoval ? cs.error : cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StartMonthWarning extends StatelessWidget {
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _StartMonthWarning({
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final label = actionLabel;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer,
        borderRadius: AppRadii.mdBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 18, color: cs.onTertiaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onTertiaryContainer,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          if (label != null && onAction != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: InstallmentReviewKeys.useSuggested,
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: cs.onTertiaryContainer,
                  minimumSize: const Size(44, 44),
                ),
                child: Text(label),
              ),
            ),
        ],
      ),
    );
  }
}

/// Opens the review as a bottom sheet over the mobile form. Resolves to the
/// plan to save when the user confirms, or null on Back. Taking the suggested
/// start month calls [onStartMonthChanged], so the form shows it on Back too.
Future<Installment?> showInstallmentReviewSheet(
  BuildContext context, {
  required InstallmentPresenter presenter,
  required BillsReceivablesPresenter? receivables,
  required Installment draft,
  Installment? existing,
  required ValueChanged<String> onStartMonthChanged,
}) =>
    showModalBottomSheet<Installment>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _InstallmentReviewSheet(
        presenter: presenter,
        receivables: receivables,
        draft: draft,
        existing: existing,
        onStartMonthChanged: onStartMonthChanged,
      ),
    );

class _InstallmentReviewSheet extends StatefulWidget {
  final InstallmentPresenter presenter;
  final BillsReceivablesPresenter? receivables;
  final Installment draft;
  final Installment? existing;
  final ValueChanged<String> onStartMonthChanged;

  const _InstallmentReviewSheet({
    required this.presenter,
    required this.receivables,
    required this.draft,
    required this.existing,
    required this.onStartMonthChanged,
  });

  @override
  State<_InstallmentReviewSheet> createState() =>
      _InstallmentReviewSheetState();
}

class _InstallmentReviewSheetState extends State<_InstallmentReviewSheet> {
  late Installment _draft;
  late InstallmentReview _review;
  InstallmentReceivablePreview? _receivables;

  @override
  void initState() {
    super.initState();
    _show(widget.draft);
  }

  void _show(Installment draft) {
    _draft = draft;
    _review = widget.presenter.reviewPlan(draft, existing: widget.existing);
    _receivables = widget.receivables?.installmentReceivablePreview(draft);
  }

  void _useSuggested() {
    final month = _review.suggestedStartMonth;
    if (month == null) return;
    widget.onStartMonthChanged(month);
    setState(() => _show(_draft.copyWith(startMonth: month)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Review ${_draft.name}',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            InstallmentReviewPanel(
              review: _review,
              receivables: _receivables,
              onUseSuggested: _useSuggested,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: AppSecondaryButton(
                    key: InstallmentReviewKeys.back,
                    label: 'Back',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppPrimaryButton(
                    key: InstallmentReviewKeys.confirm,
                    label: 'Confirm',
                    onPressed: () => Navigator.of(context).pop(_draft),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
