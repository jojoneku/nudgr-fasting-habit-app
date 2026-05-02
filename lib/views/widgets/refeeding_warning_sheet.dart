import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../utils/app_spacing.dart';
import '../../utils/app_text_styles.dart';
import 'system/system.dart';

class RefeedingWarningSheet extends StatelessWidget {
  final int elapsedSeconds;
  final VoidCallback onConfirmEnd;

  const RefeedingWarningSheet({
    super.key,
    required this.elapsedSeconds,
    required this.onConfirmEnd,
  });

  static Future<bool> show(BuildContext context, int elapsedSeconds) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => RefeedingWarningSheet(
        elapsedSeconds: elapsedSeconds,
        onConfirmEnd: () => Navigator.pop(context, true),
      ),
    );
    return result ?? false;
  }

  bool get _isVeryExtended => elapsedSeconds >= 172800; // 48h

  String _formatElapsed() {
    final h = elapsedSeconds ~/ 3600;
    final m = (elapsedSeconds % 3600) ~/ 60;
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Icon(Icons.warning_rounded,
                    color: theme.colorScheme.error, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Text('Extended fast — refeed safely',
                    style: AppTextStyles.titleMedium
                        .copyWith(color: theme.colorScheme.error)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            RichText(
              text: TextSpan(
                style: AppTextStyles.bodyMedium.copyWith(
                    color: theme.colorScheme.onSurfaceVariant, height: 1.5),
                children: [
                  const TextSpan(text: 'You have fasted for '),
                  TextSpan(
                    text: _formatElapsed(),
                    style: AppTextStyles.bodyMedium.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w600),
                  ),
                  const TextSpan(
                    text:
                        '. Breaking an extended fast incorrectly can cause discomfort. Follow the protocol below.',
                  ),
                ],
              ),
            ),
            if (_isVeryExtended) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm + 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.emergency_rounded,
                        color: theme.colorScheme.error, size: 16),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Refeeding syndrome risk after 48h+. Do not eat a large meal immediately.',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: theme.colorScheme.error),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Text('Refeeding protocol',
                style: AppTextStyles.titleSmall
                    .copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.sm),
            _buildStep(
              context,
              timeframe: 'First 1–2 hours',
              instruction: 'Bone broth, vegetable broth, or electrolytes. Small sips only.',
              icon: Icons.water_drop_outlined,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: AppSpacing.sm),
            _buildStep(
              context,
              timeframe: '2–6 hours after',
              instruction: 'Soft foods: banana, yogurt, soup, or plain rice. Small portions.',
              icon: Icons.restaurant_outlined,
              color: AppColors.gold,
            ),
            const SizedBox(height: AppSpacing.sm),
            _buildStep(
              context,
              timeframe: '6+ hours after',
              instruction: 'Gradually return to normal meals. Avoid heavy fats immediately.',
              icon: Icons.check_circle_outline,
              color: AppColors.success,
            ),
            const SizedBox(height: AppSpacing.mdGenerous),
            AppDestructiveButton(
              label: 'I understand — end fast',
              onPressed: onConfirmEnd,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppSecondaryButton(
              label: 'Continue fasting',
              onPressed: () => Navigator.pop(context, false),
              fullWidth: true,
              height: 48,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(
    BuildContext context, {
    required String timeframe,
    required String instruction,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppIconBadge(icon: icon, color: color, size: 32, iconSize: 16),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(timeframe,
                  style: AppTextStyles.labelMedium.copyWith(color: color)),
              const SizedBox(height: 2),
              Text(instruction,
                  style: AppTextStyles.bodySmall.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}
