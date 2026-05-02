import 'package:flutter/material.dart';
import '../../../../utils/app_radii.dart';
import '../../../../utils/app_spacing.dart';
import '../../../../utils/app_text_styles.dart';

/// M3 LinearProgressIndicator with optional label + value text.
class AppLinearProgress extends StatelessWidget {
  const AppLinearProgress({
    super.key,
    required this.value,
    this.label,
    this.valueText,
    this.color,
    this.backgroundColor,
    this.height = 8,
    this.clipped = true,
  });

  final double value;
  final String? label;
  final String? valueText;
  final Color? color;
  final Color? backgroundColor;
  final double height;
  final bool clipped;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasLabels = label != null || valueText != null;

    Widget bar = LinearProgressIndicator(
      value: value.clamp(0.0, 1.0),
      color: color ?? theme.colorScheme.primary,
      backgroundColor:
          backgroundColor ?? theme.colorScheme.surfaceContainerHighest,
      minHeight: height,
    );

    if (clipped) {
      bar = ClipRRect(borderRadius: AppRadii.smBorder, child: bar);
    }

    if (!hasLabels) return bar;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasLabels)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (label != null)
                Text(label!, style: AppTextStyles.labelMedium),
              if (valueText != null)
                Text(
                  valueText!,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        const SizedBox(height: AppSpacing.xs),
        bar,
      ],
    );
  }
}
