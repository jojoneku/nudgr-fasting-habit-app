import 'package:flutter/material.dart';
import '../../app_colors.dart';
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
}

class ProtocolCard extends StatelessWidget {
  final FastingProtocol protocol;
  final bool isSelected;
  final VoidCallback onTap;

  const ProtocolCard({
    super.key,
    required this.protocol,
    required this.isSelected,
    required this.onTap,
  });

  Color get _tierColor {
    if (protocol.isExtended) {
      return protocol.hours >= 48 ? AppColors.danger : const Color(0xFFFF7043);
    }
    if (protocol.hours >= 20) return const Color(0xFFAB47BC);
    if (protocol.hours >= 16) return AppColors.secondary;
    return AppColors.neutral;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        width: 160,
        clipBehavior: Clip.hardEdge,
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        transform: isSelected
            ? Matrix4.diagonal3Values(1.02, 1.02, 1.0)
            : Matrix4.identity(),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? _tierColor.withValues(alpha: 0.12)
              : AppColors.background.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? _tierColor
                : AppColors.neutral.withValues(alpha: 0.2),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _tierColor.withValues(alpha: 0.25),
                    blurRadius: 12,
                    spreadRadius: 1,
                  )
                ]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppStatPill(
                    value: protocol.ratio,
                    color: AppStatColor.neutral,
                    size: AppStatSize.small,
                  ),
                  if (protocol.isExtended)
                    AppStatPill(
                      value: '⚠',
                      color: AppStatColor.error,
                      size: AppStatSize.small,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                protocol.rpgName,
                style: TextStyle(
                  color: isSelected ? _tierColor : AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                protocol.benefit,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
