import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/utils/app_motion.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/utils/statement_card_view.dart';
import 'package:intermittent_fasting/views/treasury/shared/account_badge_widget.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// A credit card / BNPL statement in the Bills tab, laid out like the issuer's
/// own bill: the card it belongs to, the cycle, what is left to pay and when,
/// and what is on it — with the items one tap away.
///
/// Replaces the plain [ObligationCard] row for statements, which led with a
/// spending-category icon (a fork and knife on a ShopeePay statement) and hid
/// the items behind a link floating under the note.
///
/// Dumb widget: [view] is resolved by the presenter; the callbacks open the
/// existing sheets.
class StatementBillCard extends StatelessWidget {
  final StatementCardView view;

  /// Opens the mark-paid sheet. Null hides the Pay button.
  final VoidCallback? onPay;

  /// Reverses a recorded payment. Shown in place of the check once paid.
  final VoidCallback? onUndo;

  /// Opens the statement's items.
  final VoidCallback? onViewItems;

  /// Tap — opens the bill's edit sheet.
  final VoidCallback? onEdit;

  /// Long-press (the Bills tab starts multi-select with it).
  final VoidCallback? onLongPress;

  final bool selectionMode;
  final bool selected;
  final VoidCallback? onSelectionToggle;

  const StatementBillCard({
    super.key,
    required this.view,
    this.onPay,
    this.onUndo,
    this.onViewItems,
    this.onEdit,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectionToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dimmed = view.isPaid && !selected;
    return AnimatedOpacity(
      opacity: dimmed ? 0.6 : 1,
      duration: AppMotion.appear,
      child: AppCard(
        variant: AppCardVariant.outlined,
        padding: EdgeInsets.zero,
        color: selected ? cs.primary.withValues(alpha: 0.12) : null,
        onTap: selectionMode ? onSelectionToggle : onEdit,
        onLongPress: selectionMode ? onSelectionToggle : onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 0),
              child: _Header(
                view: view,
                selectionMode: selectionMode,
                selected: selected,
                trailing: _trailing(context),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: _AmountRow(view: view),
            ),
            if (view.progress != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: _Progress(view: view),
              ),
            Divider(height: 1, color: cs.outlineVariant),
            _ItemsFooter(
              view: view,
              onTap: selectionMode ? null : onViewItems,
            ),
          ],
        ),
      ),
    );
  }

  Widget? _trailing(BuildContext context) {
    if (selectionMode) {
      return view.isPaid
          ? Icon(Icons.check_circle, color: context.appColors.success, size: 22)
          : null;
    }
    if (view.isPaid) {
      return onUndo == null
          ? Icon(Icons.check_circle, color: context.appColors.success, size: 22)
          : _UndoButton(onTap: onUndo!);
    }
    return onPay == null ? null : _PayButton(onTap: onPay!);
  }
}

class _Header extends StatelessWidget {
  final StatementCardView view;
  final bool selectionMode;
  final bool selected;
  final Widget? trailing;

  const _Header({
    required this.view,
    required this.selectionMode,
    required this.selected,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = view.account;
    return Row(
      children: [
        if (selectionMode) ...[
          Icon(
            selected
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 22,
            color: selected ? cs.primary : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
        ],
        AccountBadge(
          category: a.category,
          name: a.name,
          iconKey: a.icon,
          colorHex: a.colorHex,
          size: 40,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AppBadge(text: view.kindLabel, color: cs.error),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                view.periodLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          trailing!,
        ],
      ],
    );
  }
}

class _AmountRow extends StatelessWidget {
  final StatementCardView view;

  const _AmountRow({required this.view});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatPeso(view.headlineAmount),
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  letterSpacing: -0.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  view.headlineCaption,
                  if (view.minimumLabel != null) view.minimumLabel!,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _DuePill(label: view.dueLabel, tone: view.dueTone),
      ],
    );
  }
}

/// The due line as a pill whose tone carries urgency — and whose words carry
/// it too, so color is never the only signal.
class _DuePill extends StatelessWidget {
  final String label;
  final StatementDueTone tone;

  const _DuePill({required this.label, required this.tone});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = switch (tone) {
      StatementDueTone.normal => cs.onSurfaceVariant,
      StatementDueTone.soon => context.appColors.orange,
      StatementDueTone.overdue => cs.error,
      StatementDueTone.paid => context.appColors.success,
    };
    final icon = switch (tone) {
      StatementDueTone.paid => Icons.check_rounded,
      StatementDueTone.overdue => Icons.error_outline_rounded,
      _ => Icons.event_outlined,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  final StatementCardView view;

  const _Progress({required this.view});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: view.progress!.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: cs.outlineVariant.withValues(alpha: 0.3),
            color: context.appColors.success,
          ),
        ),
        if (view.progressLabel != null) ...[
          const SizedBox(height: 5),
          Text(
            view.progressLabel!,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11.5),
          ),
        ],
      ],
    );
  }
}

/// "3 purchases · 6 installments          View 9 items ›" — the whole strip is
/// the target, 48px tall.
class _ItemsFooter extends StatelessWidget {
  final StatementCardView view;
  final VoidCallback? onTap;

  const _ItemsFooter({required this.view, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: onTap != null,
      label: '${view.itemsLabel} on the ${view.account.name} statement',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.receipt_long_outlined,
                    size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    view.compositionLabel ?? 'Nothing on it yet',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  view.itemsLabel,
                  style: TextStyle(
                    color: cs.primary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 18, color: cs.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PayButton extends StatelessWidget {
  final VoidCallback onTap;

  const _PayButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: context.appColors.bills,
        foregroundColor: Theme.of(context).colorScheme.surface,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
      ),
      child: const Text('Pay'),
    );
  }
}

class _UndoButton extends StatelessWidget {
  final VoidCallback onTap;

  const _UndoButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Undo — mark this statement unpaid',
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.onSurfaceVariant,
          side: BorderSide(color: cs.outlineVariant),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: const Size(0, 44),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle:
              const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
        icon: const Icon(Icons.undo_rounded, size: 16),
        label: const Text('Undo'),
      ),
    );
  }
}
