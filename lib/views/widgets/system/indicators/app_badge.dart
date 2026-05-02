import 'package:flutter/material.dart';
import '../../../../utils/app_text_styles.dart';

enum AppBadgeVariant { tonal, filled, outlined }

enum AppBadgeSize { small, medium }

/// Tiny pill badge — text or count.
class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.text,
    this.variant = AppBadgeVariant.tonal,
    this.color,
    this.size = AppBadgeSize.small,
  });

  const factory AppBadge.count({
    Key? key,
    required int count,
    Color? color,
    int max,
  }) = _AppBadgeCount;

  final String text;
  final AppBadgeVariant variant;
  final Color? color;
  final AppBadgeSize size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.primary;
    final isSmall = size == AppBadgeSize.small;
    final style =
        (isSmall ? AppTextStyles.labelSmall : AppTextStyles.labelMedium);

    Color bg;
    Color fg;
    Border? border;

    switch (variant) {
      case AppBadgeVariant.tonal:
        bg = c.withValues(alpha: 0.15);
        fg = c;
      case AppBadgeVariant.filled:
        bg = c;
        fg = theme.colorScheme.onPrimary;
      case AppBadgeVariant.outlined:
        bg = Colors.transparent;
        fg = c;
        border = Border.all(color: c);
    }

    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isSmall ? 6 : 8, vertical: isSmall ? 2 : 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: border,
      ),
      child: Text(text, style: style.copyWith(color: fg)),
    );
  }
}

class _AppBadgeCount extends AppBadge {
  const _AppBadgeCount({
    super.key,
    required this.count,
    super.color,
    this.max = 99,
  }) : super(text: '');

  final int count;
  final int max;

  @override
  Widget build(BuildContext context) {
    final label = count > max ? '$max+' : '$count';
    return AppBadge(
      text: label,
      variant: AppBadgeVariant.filled,
      color: color,
      size: AppBadgeSize.small,
    );
  }
}
