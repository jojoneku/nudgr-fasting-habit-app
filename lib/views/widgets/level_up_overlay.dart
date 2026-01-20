import 'package:flutter/material.dart';
import '../../app_colors.dart';

class LevelUpOverlay extends StatelessWidget {
  final int newLevel;
  final VoidCallback onClose;

  const LevelUpOverlay({
    super.key,
    required this.newLevel,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.8),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            "LEVEL UP!",
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 48,
              fontWeight: FontWeight.bold,
              letterSpacing: 4.0,
              shadows: [
                Shadow(color: AppColors.gold, blurRadius: 20),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "You have reached Level $newLevel",
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 24,
            ),
          ),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: onClose,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
            child: const Text("ACCEPT"),
          ),
        ],
      ),
    );
  }
}
