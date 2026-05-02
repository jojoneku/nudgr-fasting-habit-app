import 'package:flutter/material.dart';
import '../../../../app_colors.dart';
import '../../../../utils/app_text_styles.dart';

enum AppStatColor { neutral, primary, success, warning, error }
enum AppStatSize { small, medium }

/// Compact label+value chip for HP, XP, kcal, step counts etc.
class AppStatPill extends StatelessWidget {
  const AppStatPill({
    super.key,
    this.label,
    required this.value,
    this.icon,
    this.color = AppStatColor.neutral,
    this.size = AppStatSize.medium,
  });

  final String? label;
  final String value;
  final IconData? icon;
  final AppStatColor color;
  final AppStatSize size;

  Color _resolveColor(BuildContext context) {
    final theme = Theme.of(context);
    return switch (color) {
      AppStatColor.primary => theme.colorScheme.primary,
      AppStatColor.success => AppColors.success,
      AppStatColor.warning => AppColors.gold,
      AppStatColor.error => theme.colorScheme.error,
      AppStatColor.neutral => theme.colorScheme.onSurfaceVariant,
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = _resolveColor(context);
    final isSmall = size == AppStatSize.small;
    final hPad = isSmall ? 6.0 : 10.0;
    final vPad = isSmall ? 2.0 : 4.0;
    final textStyle = isSmall ? AppTextStyles.labelSmall : AppTextStyles.labelMedium;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: isSmall ? 12 : 14, color: c),
          const SizedBox(width: 4),
        ],
        if (label != null) ...[
          Text(label!,
              style: textStyle.copyWith(
                  color: c, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
        ],
        Text(value, style: textStyle.copyWith(color: c)),
      ],
    );

    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: content,
    );
  }
}
