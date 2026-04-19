import 'package:flutter/material.dart';
import '../../app_colors.dart';

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
      backgroundColor: Colors.transparent,
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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: AppColors.danger.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHandle(),
              const SizedBox(height: 16),
              _buildHeader(),
              const SizedBox(height: 20),
              if (_isVeryExtended) ...[
                _buildRiskBanner(),
                const SizedBox(height: 16),
              ],
              _buildRefeedingSteps(),
              const SizedBox(height: 24),
              _buildActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHandle() => Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.neutral.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _buildHeader() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_rounded, color: AppColors.danger, size: 22),
              SizedBox(width: 8),
              Text(
                'EXTENDED FAST — REFEED SAFELY',
                style: TextStyle(
                  color: AppColors.danger,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14, height: 1.5),
              children: [
                const TextSpan(text: 'You have fasted for '),
                TextSpan(
                  text: _formatElapsed(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const TextSpan(
                  text:
                      '. Breaking an extended fast incorrectly can cause discomfort or worse. Follow the refeeding protocol below.',
                ),
              ],
            ),
          ),
        ],
      );

  Widget _buildRiskBanner() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
        ),
        child: const Row(
          children: [
            Icon(Icons.emergency_rounded, color: AppColors.danger, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'REFEEDING SYNDROME RISK: After 48h+ of fasting, your electrolytes are depleted. Do NOT eat a large meal immediately.',
                style: TextStyle(
                  color: AppColors.danger,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildRefeedingSteps() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'REFEEDING PROTOCOL',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          _buildStep(
            step: '01',
            timeframe: 'First 1–2 hours',
            instruction:
                'Start with bone broth, vegetable broth, or electrolytes. Small sips only.',
            icon: Icons.water_drop_outlined,
            color: AppColors.secondary,
          ),
          const SizedBox(height: 10),
          _buildStep(
            step: '02',
            timeframe: '2–6 hours after',
            instruction:
                'Soft, easy-to-digest foods: banana, yogurt, soup, or plain rice. Small portions.',
            icon: Icons.restaurant_outlined,
            color: AppColors.gold,
          ),
          const SizedBox(height: 10),
          _buildStep(
            step: '03',
            timeframe: '6+ hours after',
            instruction:
                'Gradually return to normal meals. Avoid heavy fats and large protein loads immediately.',
            icon: Icons.check_circle_outline,
            color: AppColors.success,
          ),
        ],
      );

  Widget _buildStep({
    required String step,
    required String timeframe,
    required String instruction,
    required IconData icon,
    required Color color,
  }) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  timeframe,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  instruction,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _buildActions(BuildContext context) => Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: onConfirmEnd,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: AppColors.textPrimary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26)),
              ),
              child: const Text(
                'I UNDERSTAND — END FAST',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: TextButton(
              onPressed: () => Navigator.pop(context, false),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
              ),
              child: const Text('Continue Fasting'),
            ),
          ),
        ],
      );
}
