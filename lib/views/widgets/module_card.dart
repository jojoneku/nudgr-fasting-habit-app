import 'package:flutter/material.dart';
import '../../app_colors.dart';
import 'system/system.dart';

class ModuleCard extends StatelessWidget {
  const ModuleCard({
    super.key,
    required this.title,
    required this.rpgName,
    required this.icon,
    required this.accentColor,
    this.subtitle,
    this.isLocked = false,
    this.onTap,
  });

  final String title;
  final String rpgName;
  final IconData icon;
  final Color accentColor;
  final String? subtitle;
  final bool isLocked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isLocked ? 0.45 : 1.0,
      child: AppCard(
        variant: AppCardVariant.outlined,
        onTap: isLocked ? null : onTap,
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 128),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppIconBadge(
                    icon: icon,
                    color: accentColor,
                    size: 44,
                    iconSize: 22,
                  ),
                  if (isLocked)
                    const Icon(Icons.lock_outline,
                        color: AppColors.neutral, size: 16),
                ],
              ),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    rpgName,
                    style: TextStyle(
                      color: accentColor.withValues(alpha: 0.75),
                      fontSize: 10,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
