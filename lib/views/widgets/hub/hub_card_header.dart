import 'package:flutter/material.dart';
import '../system/system.dart';
import '../../../utils/app_spacing.dart';
import '../../../utils/app_text_styles.dart';

class HubCardHeader extends StatelessWidget {
  const HubCardHeader({
    super.key,
    required this.icon,
    required this.title,
    this.accentColor,
    this.isActive = false,
  });

  final IconData icon;
  final String title;
  final Color? accentColor;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isActive
        ? (accentColor ?? theme.colorScheme.primary)
        : theme.colorScheme.onSurfaceVariant;

    return Row(
      children: [
        AppIconBadge(icon: icon, color: color, size: 36, iconSize: 18),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(title, style: AppTextStyles.titleSmall)),
        Icon(Icons.chevron_right, size: 16, color: theme.colorScheme.onSurfaceVariant),
      ],
    );
  }
}
