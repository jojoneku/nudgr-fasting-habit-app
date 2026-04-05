import 'package:flutter/material.dart';
import '../../../app_colors.dart';

const List<int> _milestones = [7, 21, 30, 66, 100];

/// Row of achievement badges for streak milestones.
class StreakBadgeRow extends StatelessWidget {
  final int currentStreak;

  /// Set of milestone integers that have been unlocked.
  final Set<int> unlockedMilestones;

  const StreakBadgeRow({
    super.key,
    required this.currentStreak,
    required this.unlockedMilestones,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: _milestones.map((m) {
        final isUnlocked = unlockedMilestones.contains(m);
        return _BadgeTile(
          milestone: m,
          isUnlocked: isUnlocked,
          isNext: !isUnlocked && _nextTarget(unlockedMilestones) == m,
          progress: isUnlocked ? 1.0 : (currentStreak / m).clamp(0.0, 1.0),
        );
      }).toList(),
    );
  }

  int? _nextTarget(Set<int> unlocked) {
    for (final m in _milestones) {
      if (!unlocked.contains(m)) return m;
    }
    return null;
  }
}

class _BadgeTile extends StatelessWidget {
  final int milestone;
  final bool isUnlocked;
  final bool isNext;
  final double progress;

  const _BadgeTile({
    required this.milestone,
    required this.isUnlocked,
    required this.isNext,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final color = _color();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: progress,
                strokeWidth: 3,
                backgroundColor: AppColors.neutral.withValues(alpha: 0.15),
                valueColor:
                    AlwaysStoppedAnimation(color.withValues(alpha: 0.7)),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isUnlocked
                      ? color.withValues(alpha: 0.2)
                      : AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isUnlocked
                        ? color
                        : AppColors.neutral.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Text(
                    _emoji(),
                    style: TextStyle(
                      fontSize: 16,
                      color: isUnlocked
                          ? color
                          : AppColors.neutral.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${milestone}d',
          style: TextStyle(
            fontSize: 10,
            fontWeight: isUnlocked ? FontWeight.bold : FontWeight.normal,
            color: isUnlocked ? color : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Color _color() => switch (milestone) {
        7 => const Color(0xFF66BB6A),
        21 => const Color(0xFF29B6F6),
        30 => const Color(0xFFCE93D8),
        66 => const Color(0xFFFFCA28),
        _ => const Color(0xFFEF5350), // 100 — S-rank red
      };

  String _emoji() => switch (milestone) {
        7 => '🌱',
        21 => '⚔️',
        30 => '🔮',
        66 => '👑',
        _ => '🌟',
      };
}
