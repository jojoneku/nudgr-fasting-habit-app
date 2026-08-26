import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/utils/app_text_styles.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// How far a save of a recurring item reaches: just the month being edited, or
/// every later month too.
enum RecurringScope {
  /// Write only the row the user opened. Later months keep whatever they hold.
  thisMonthOnly,

  /// Carry the save across every later month of the same series.
  thisAndFuture,
}

/// Asks how far a *delete* reaches, for an item whose series has
/// [futureMonthCount] later months already generated ahead of it.
///
/// A switch would be wrong here: unlike an edit, a delete cannot be reviewed
/// afterwards, so both outcomes are named as explicit buttons and neither is
/// the button your thumb lands on by reflex. Returns null when the user backs
/// out.
///
/// [isRecurring] is what decides whether the choice is worth asking, not
/// [futureMonthCount]. A recurring item that happens to have no later month
/// generated *yet* still has a future to speak for: months are seeded from the
/// previous month on demand, so deleting one row of a live series and stopping
/// the series are different outcomes even when the count is zero. Asking only
/// when a copy already existed is what left users deleting the same salary
/// again every month.
///
/// Falls back to the ordinary confirm for a one-off item with nothing ahead of
/// it — there, offering a choice between two identical outcomes is just a
/// harder dialog to read.
Future<RecurringScope?> confirmRecurringDelete({
  required BuildContext context,
  required String title,
  required String name,
  required int futureMonthCount,
  required bool isRecurring,
}) async {
  if (futureMonthCount == 0 && !isRecurring) {
    final ok = await AppConfirmDialog.confirm(
      context: context,
      title: title,
      body: 'Delete "$name"?',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      isDestructive: true,
    );
    return ok ? RecurringScope.thisMonthOnly : null;
  }

  // Two different truths to tell. With copies already generated the blast
  // radius is a number the user can picture; with none yet the thing worth
  // saying is that it will come back on its own.
  final body = futureMonthCount == 0
      ? '"$name" repeats, so it will keep coming back each month. '
          'Delete just this month, or all of them?'
      : '"$name" repeats — it is also set up in '
          '${_laterMonths(futureMonthCount)}. How much of it should go?';
  return _askScope(context: context, title: title, body: body);
}

/// The same question for a multi-select delete, where [selectedCount] rows are
/// going and [recurringCount] of them repeat.
///
/// Ticking a recurring salary in the batch bar used to be a quieter delete than
/// opening it and choosing "All months" — same row, same outcome asked about in
/// one place and not the other. This closes that, and delegates to
/// [confirmRecurringDelete] for a single selection so the copy can name the
/// item rather than counting to one.
///
/// [extraMonthCount] is how many *additional* later-month rows the all-months
/// option would take, resolved per series by the presenter — so two selected
/// months of one series don't count their shared future twice.
///
/// [plainBody] is the ordinary confirmation text, used verbatim when nothing in
/// the selection repeats (installments, one-offs) and there is no scope to ask
/// about.
Future<RecurringScope?> confirmRecurringBatchDelete({
  required BuildContext context,
  required String title,
  required int selectedCount,
  required int recurringCount,
  required int extraMonthCount,
  required String plainBody,
  String? soleName,
}) async {
  if (recurringCount == 0) {
    final ok = await AppConfirmDialog.confirm(
      context: context,
      title: title,
      body: plainBody,
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      isDestructive: true,
    );
    return ok ? RecurringScope.thisMonthOnly : null;
  }

  if (selectedCount == 1 && soleName != null) {
    return confirmRecurringDelete(
      context: context,
      title: title,
      name: soleName,
      futureMonthCount: extraMonthCount,
      isRecurring: true,
    );
  }

  final repeats = recurringCount == selectedCount
      ? (selectedCount == 2 ? 'Both repeat' : 'All $selectedCount repeat')
      : (recurringCount == 1
          ? '1 of them repeats'
          : '$recurringCount of them repeat');
  final ahead = extraMonthCount == 0
      ? ', so they will keep coming back each month.'
      : ' — with ${_laterMonths(extraMonthCount)} already set up ahead.';
  return _askScope(
    context: context,
    title: title,
    body: '$repeats$ahead Delete this month only, or all months?',
  );
}

String _laterMonths(int count) =>
    count == 1 ? '1 later month' : '$count later months';

/// The two-outcome delete dialog itself. Neither outcome is the button your
/// thumb lands on by reflex, and both are named — a delete cannot be reviewed
/// afterwards the way an edit can. Returns null when the user backs out.
Future<RecurringScope?> _askScope({
  required BuildContext context,
  required String title,
  required String body,
}) async {
  if (!context.mounted) return null;
  return showDialog<RecurringScope>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return AlertDialog(
        title: Text(title, style: AppTextStyles.titleLarge),
        content: Text(
          // Always say what "all months" spares: deleting the rows ahead is not
          // deleting the history behind.
          '$body\nEarlier months are left as they are.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(RecurringScope.thisMonthOnly),
            child: const Text('This month only'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: () =>
                Navigator.of(ctx).pop(RecurringScope.thisAndFuture),
            // "All months" rather than "This and future": the user thinks in
            // terms of the repeating thing, not the row in front of them, and
            // the body copy already says history is spared.
            child: const Text('All months'),
          ),
        ],
      );
    },
  );
}

/// The "does this change stick for next month too?" choice, shown inline in the
/// edit sheet for a recurring bill, receivable or set-aside.
///
/// Every month of a recurring item is a separate row, so an edit that stops at
/// the month it was made in leaves the already-generated later months frozen at
/// the amount they were seeded with. Defaulting to [RecurringScope.thisAndFuture]
/// makes the common intent — "my rent went up" — the no-effort path, while the
/// switch keeps the genuinely one-off case ("they only overcharged me in March")
/// one tap away.
///
/// Deliberately says how many months it will touch rather than "future months":
/// the blast radius is the thing worth being sure about before saving.
class RecurringScopeField extends StatelessWidget {
  /// How many later months the save would reach. The caller resolves this from
  /// the presenter — the widget never counts rows itself.
  final int futureMonthCount;

  /// `YYYY-MM` of the row being edited, named in the "this month only" copy so
  /// the choice reads concretely ("Only August 2026 changes").
  final String month;

  final RecurringScope value;
  final ValueChanged<RecurringScope> onChanged;

  /// What the item is called in the subtitle — "amount", "allocation". Keeps
  /// the copy specific to bills vs set-asides without three near-identical
  /// widgets.
  final String noun;

  /// True when applying forward would *remove* the later months rather than
  /// restate them — the user has switched recurrence off, so the copies that
  /// exist only because it recurred are about to go. Deleting months under a
  /// label that promises an update would be a nasty surprise, so the copy says
  /// what will actually happen.
  final bool removesFutureMonths;

  const RecurringScopeField({
    super.key,
    required this.futureMonthCount,
    required this.month,
    required this.value,
    required this.onChanged,
    this.noun = 'change',
    this.removesFutureMonths = false,
  });

  bool get _appliesToFuture => value == RecurringScope.thisAndFuture;

  String get _title => removesFutureMonths
      ? 'Also drop future months'
      : 'Apply to future months';

  String get _subtitle {
    if (!_appliesToFuture) {
      return removesFutureMonths
          ? 'The months already generated ahead stay'
          : 'Only ${monthLabel(month)} changes';
    }
    if (removesFutureMonths) {
      return futureMonthCount == 1
          ? 'The month generated ahead will be removed'
          : 'The $futureMonthCount months generated ahead will be removed';
    }
    return futureMonthCount == 1
        ? 'The next month will use this $noun too'
        : 'The next $futureMonthCount months will use this $noun too';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = context.appColors;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: !_appliesToFuture
              ? colorScheme.outlineVariant
              : removesFutureMonths
                  ? colorScheme.error.withValues(alpha: 0.4)
                  : colorScheme.primary.withValues(alpha: 0.4),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      child: Row(
        children: [
          Icon(
            !_appliesToFuture
                ? Icons.event_available_rounded
                : removesFutureMonths
                    ? Icons.event_busy_rounded
                    : Icons.event_repeat_rounded,
            size: 20,
            color: !_appliesToFuture
                ? colorScheme.onSurfaceVariant
                : removesFutureMonths
                    ? colorScheme.error
                    : colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: appColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _appliesToFuture,
            onChanged: (on) => onChanged(
              on ? RecurringScope.thisAndFuture : RecurringScope.thisMonthOnly,
            ),
          ),
        ],
      ),
    );
  }
}
