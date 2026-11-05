import 'package:flutter/material.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/utils/app_radii.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// Keys the start-month review card's tests use.
abstract final class StartMonthReviewKeys {
  static const card = ValueKey('startMonthReview.card');
  static ValueKey<String> use(String id) =>
      ValueKey('startMonthReview.use.$id');
  static ValueKey<String> keep(String id) =>
      ValueKey('startMonthReview.keep.$id');
}

/// The Installments tab's one-time check (Plan 068): plans saved before start
/// months were computed, whose month differs from their card's cycle. Each
/// row takes the computed month or keeps the saved one. Shows nothing when no
/// plan waits. Shared by the mobile tab and the web v2 page.
class StartMonthReviewCard extends StatelessWidget {
  final InstallmentPresenter presenter;

  /// Space around the card, applied only while it shows.
  final EdgeInsetsGeometry margin;

  const StartMonthReviewCard({
    super.key,
    required this.presenter,
    this.margin = EdgeInsets.zero,
  });

  Future<void> _run(
      BuildContext context, Future<void> Function() action, String done) async {
    try {
      await action();
      if (context.mounted) AppToast.success(context, done);
    } catch (e) {
      if (context.mounted) AppToast.error(context, 'Could not save: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final banner = presenter.startMonthReviewBanner;
    if (banner == null) return const SizedBox.shrink();
    final items = presenter.startMonthReviewItems;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      key: StartMonthReviewKeys.card,
      margin: margin,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer,
        borderRadius: AppRadii.mdBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.event_repeat_rounded,
                  size: 18, color: cs.onTertiaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  banner,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onTertiaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          for (final item in items) ...[
            const SizedBox(height: 10),
            Text(
              item.name,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onTertiaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (item.detail.isNotEmpty)
              Text(
                item.detail,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onTertiaryContainer),
              ),
            Text(
              '${item.stored} · ${item.computed}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onTertiaryContainer),
            ),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              children: [
                TextButton(
                  key: StartMonthReviewKeys.keep(item.id),
                  onPressed: () => _run(
                    context,
                    () => presenter.keepStartMonth(item.id),
                    '${item.name}: ${item.keepLabel.toLowerCase()}',
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: cs.onTertiaryContainer,
                    minimumSize: const Size(44, 44),
                  ),
                  child: Text(item.keepLabel),
                ),
                FilledButton.tonal(
                  key: StartMonthReviewKeys.use(item.id),
                  onPressed: () => _run(
                    context,
                    () => presenter.useComputedStartMonth(item.id),
                    '${item.name}: ${item.useLabel.toLowerCase()}',
                  ),
                  style:
                      FilledButton.styleFrom(minimumSize: const Size(44, 44)),
                  child: Text(item.useLabel),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
