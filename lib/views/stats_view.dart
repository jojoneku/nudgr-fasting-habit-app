import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../presenters/stats_presenter.dart';
import '../models/user_stats.dart';
import 'widgets/level_up_overlay.dart';

class StatsView extends StatelessWidget {
  final StatsPresenter presenter;

  const StatsView({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) {
        final stats = presenter.stats;
        return Stack(
          children: [
            Scaffold(
              backgroundColor: AppColors.background,
              body: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(context, stats),
                      const SizedBox(height: 24),
                      _buildVitalitySection(context, stats),
                      const SizedBox(height: 24),
                      _buildAttributesGrid(context, stats),
                      const SizedBox(height: 24),
                      _buildDailyQuestLog(context, stats),
                    ],
                  ),
                ),
              ),
            ),
            if (presenter.showLevelUpDialog)
              LevelUpOverlay(
                newLevel: stats.level,
                onClose: presenter.dismissLevelUp,
              ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, UserStats stats) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "STATUS",
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  letterSpacing: 2.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "NAME: PLAYER", // Could be dynamic later
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "JOB: ${presenter.jobTitle.toUpperCase()}",
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                "TITLE: WOLF SLAYER", // Placeholder
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        _buildRankHexagon(presenter.rank),
      ],
    );
  }

  Widget _buildRankHexagon(String rank) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        shape: BoxShape.circle, // Hexagon is hard, circle for MVP
        border: Border.all(color: AppColors.gold, width: 2),
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withValues(alpha: 0.3),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        rank,
        style: const TextStyle(
          color: AppColors.gold,
          fontSize: 32,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildVitalitySection(BuildContext context, UserStats stats) {
    final maxHp = presenter.maxHp;
    final hpPercent = (stats.currentHp / maxHp).clamp(0.0, 1.0);
    
    final nextLevelXp = presenter.nextLevelXp;
    final xpPercent = (stats.currentXp / nextLevelXp).clamp(0.0, 1.0);

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("LEVEL: ${stats.level}", style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
            if (stats.statPoints > 0)
              Text("POINTS: ${stats.statPoints}", style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 16),
        _buildBar("HP", stats.currentHp, maxHp, hpPercent, AppColors.danger),
        const SizedBox(height: 12),
        _buildBar("XP", stats.currentXp, nextLevelXp, xpPercent, AppColors.accent),
      ],
    );
  }

  Widget _buildBar(String label, int current, int max, double percent, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
            Text("$current / $max", style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 12,
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.surface),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: percent,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAttributesGrid(BuildContext context, UserStats stats) {
    final attrs = stats.attributes;
    final canSpend = stats.statPoints > 0;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.5,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: [
        _buildStatBox("STR", attrs.str, canSpend),
        _buildStatBox("VIT", attrs.vit, canSpend),
        _buildStatBox("AGI", attrs.agi, canSpend),
        _buildStatBox("INT", attrs.intl, canSpend),
        _buildStatBox("SEN", attrs.sen, canSpend),
      ],
    );
  }

  Widget _buildStatBox(String label, int value, bool canSpend) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: canSpend ? AppColors.gold.withValues(alpha: 0.5) : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              Text("$value", style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          if (canSpend)
            IconButton(
              icon: const Icon(Icons.add_circle, color: AppColors.gold),
              onPressed: () => presenter.allocatePoint(label),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }

  Widget _buildDailyQuestLog(BuildContext context, UserStats stats) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "DAILY QUEST: PREPARING TO BECOME STRONG",
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildQuestItem("Daily Fast", true), // Placeholder logic
          _buildQuestItem("100 Pushups", false),
          _buildQuestItem("100 Sit-ups", false),
          _buildQuestItem("10km Run", false),
          const Divider(color: AppColors.textSecondary, height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Days Since Awakening", style: TextStyle(color: AppColors.textSecondary)),
              Text("${stats.streak}", style: const TextStyle(color: AppColors.accent, fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuestItem(String title, bool completed) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            completed ? Icons.check_box : Icons.check_box_outline_blank,
            color: completed ? AppColors.accent : AppColors.textSecondary,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: completed ? AppColors.textSecondary : AppColors.textPrimary,
              decoration: completed ? TextDecoration.lineThrough : null,
            ),
          ),
        ],
      ),
    );
  }
}
