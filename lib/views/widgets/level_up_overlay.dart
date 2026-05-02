import 'package:flutter/material.dart';
import '../../app_colors.dart';
import 'system/system.dart';

class LevelUpOverlay extends StatelessWidget {
  const LevelUpOverlay({
    super.key,
    required this.newLevel,
    required this.onClose,
  });

  final int newLevel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.8),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'LEVEL UP!',
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 48,
              fontWeight: FontWeight.bold,
              letterSpacing: 4.0,
              shadows: [Shadow(color: AppColors.gold, blurRadius: 20)],
            ),
          ),
          const SizedBox(height: 20),
          AppNumberDisplay(
            value: '$newLevel',
            label: 'You have reached',
            labelPosition: AppNumberLabelPosition.above,
            size: AppNumberSize.headline,
            color: AppColors.textPrimary,
          ),
          const SizedBox(height: 40),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: AppPrimaryButton(
              label: 'ACCEPT',
              onPressed: onClose,
              height: 52,
            ),
          ),
        ],
      ),
    );
  }
}
