import 'package:flutter/material.dart';
import '../../../../utils/app_spacing.dart';
import '../../../../utils/app_text_styles.dart';

/// Section block — title + optional hint or trailing action, then body.
class AppSection extends StatelessWidget {
  const AppSection({
    super.key,
    required this.title,
    this.hint,
    this.trailing,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final String title;
  final String? hint;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.titleMedium),
                    if (hint != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        hint!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}
