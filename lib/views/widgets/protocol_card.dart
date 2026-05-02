import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../utils/app_spacing.dart';
import '../../utils/app_text_styles.dart';
import 'system/system.dart';

class FastingProtocol {
  final int hours;
  final String rpgName;
  final String ratio;
  final String benefit;
  final bool isExtended;

  const FastingProtocol({
    required this.hours,
    required this.rpgName,
    required this.ratio,
    required this.benefit,
    this.isExtended = false,
  });

  static const List<FastingProtocol> all = [
    FastingProtocol(
      hours: 12,
      rpgName: 'Initiate Protocol',
      ratio: '12:12',
      benefit: 'Sync your circadian rhythm.',
    ),
    FastingProtocol(
      hours: 14,
      rpgName: 'Shadow Training',
      ratio: '14:10',
      benefit: 'Fat burn begins. Sustained energy.',
    ),
    FastingProtocol(
      hours: 16,
      rpgName: 'Warrior Mode',
      ratio: '16:8',
      benefit: 'The standard. Autophagy starts.',
    ),
    FastingProtocol(
      hours: 18,
      rpgName: "Hunter's Edge",
      ratio: '18:6',
      benefit: 'Enhanced fat oxidation.',
    ),
    FastingProtocol(
      hours: 20,
      rpgName: 'Iron Discipline',
      ratio: '20:4',
      benefit: 'Deep ketosis. Heightened focus.',
    ),
    FastingProtocol(
      hours: 24,
      rpgName: 'Lone Wolf',
      ratio: 'OMAD',
      benefit: 'One meal. Maximum simplicity.',
    ),
    FastingProtocol(
      hours: 36,
      rpgName: 'Blood Covenant',
      ratio: '36h',
      benefit: 'Deep autophagy. Immune reset begins.',
      isExtended: true,
    ),
    FastingProtocol(
      hours: 48,
      rpgName: 'Void Protocol',
      ratio: '48h',
      benefit: 'Stem cell renewal. Max cellular purge.',
      isExtended: true,
    ),
  ];

  Color get tierColor {
    if (isExtended) {
      return hours >= 48 ? AppColors.danger : const Color(0xFFFF7043);
    }
    if (hours >= 20) return const Color(0xFFAB47BC);
    if (hours >= 16) return AppColors.secondary;
    return AppColors.neutral;
  }
}

class ProtocolCard extends StatelessWidget {
  const ProtocolCard({
    super.key,
    required this.protocol,
    required this.isSelected,
    required this.onTap,
  });

  final FastingProtocol protocol;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = protocol.tierColor;

    return AppCard(
      variant: isSelected ? AppCardVariant.outlined : AppCardVariant.filled,
      color: isSelected ? color.withValues(alpha: 0.08) : null,
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.sm + 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              AppStatPill(
                value: protocol.ratio,
                color: isSelected ? AppStatColor.primary : AppStatColor.neutral,
                size: AppStatSize.small,
              ),
              if (protocol.isExtended)
                Icon(Icons.warning_amber_rounded,
                    size: 14, color: theme.colorScheme.error),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            protocol.rpgName,
            style: AppTextStyles.labelLarge.copyWith(
              color: isSelected ? color : theme.colorScheme.onSurface,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            protocol.benefit,
            style: AppTextStyles.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
