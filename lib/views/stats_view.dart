import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../presenters/stats_presenter.dart';
import '../presenters/fasting_presenter.dart';
import '../models/user_stats.dart';
import 'widgets/level_up_overlay.dart';
import 'widgets/stat_radar_chart.dart';
import 'settings_screen.dart';

class StatsView extends StatelessWidget {
  final StatsPresenter presenter;
  final FastingPresenter fastingPresenter;

  const StatsView({
    super.key,
    required this.presenter,
    required this.fastingPresenter,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([presenter, fastingPresenter]),
      builder: (context, _) {
        final stats = presenter.stats;
        return Stack(
          children: [
            Scaffold(
              backgroundColor: AppColors.background,
              body: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Card(
                      elevation: 8,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                      clipBehavior: Clip.antiAlias,
                      child: Container(
                        color: AppColors.surface,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                const Text(
                                  "STATUS",
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 18,
                                    letterSpacing: 4.0,
                                    fontWeight: FontWeight.bold,
                                    shadows: [
                                      Shadow(color: AppColors.primary, blurRadius: 8),
                                    ],
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: IconButton(
                                    icon: const Icon(Icons.settings_outlined,
                                        color: AppColors.textSecondary, size: 20),
                                    onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => SettingsScreen(
                                            presenter: fastingPresenter),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            
                            // Profile Section
                            _buildProfileSection(context, stats),
                            _buildDivider(),
                            
                            // Vitals Section
                            _buildVitalitySection(context, stats),
                            _buildDivider(),
                            
                            // Stats Section
                            _buildStatsGrid(context, stats),
                          ],
                        ),
                      ),
                    ),
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

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Container(
        height: 1,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withValues(alpha: 0.0),
              AppColors.primary.withValues(alpha: 0.5),
              AppColors.primary.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileSection(BuildContext context, UserStats stats) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow("NAME", stats.name, isEditable: true, context: context),
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(
                    width: 60,
                    child: Text(
                      "RANK",
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.15),
                      border: Border.all(color: AppColors.gold),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.gold.withValues(alpha: 0.1),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Text(
                      "${presenter.rank}-Rank",
                      style: const TextStyle(
                        color: AppColors.gold,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Column(
          children: [
            const Text(
              "LEVEL",
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            Text(
              "${stats.level}",
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isEditable = false, BuildContext? context}) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (isEditable && context != null)
          InkWell(
            onTap: () => _editName(context, value),
            child: Row(
              children: [
                Text(
                  value.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.edit, size: 12, color: AppColors.textSecondary),
              ],
            ),
          )
        else
          Text(
            value.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
      ],
    );
  }

  Future<void> _editName(BuildContext context, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text("Update Name", style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: AppColors.textPrimary),
          cursorColor: AppColors.primary,
          decoration: const InputDecoration(
            hintText: "Enter Name",
            hintStyle: TextStyle(color: AppColors.textSecondary),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.textSecondary),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.primary),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text("Save", style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );

    if (newName != null && newName.trim().isNotEmpty) {
      presenter.updateName(newName.trim());
    }
  }

  Widget _buildVitalitySection(BuildContext context, UserStats stats) {
    final maxHp = presenter.maxHp;
    final hpPercent = (stats.currentHp / maxHp).clamp(0.0, 1.0);
    
    final nextLevelXp = presenter.nextLevelXp;
    final xpPercent = (stats.currentXp / nextLevelXp).clamp(0.0, 1.0);

    return Column(
      children: [
        _buildBar("HP", stats.currentHp, maxHp, hpPercent, AppColors.danger),
        const SizedBox(height: 12),
        _buildBar("XP", stats.currentXp, nextLevelXp, xpPercent, AppColors.accent), // XP is Blue/Cyan like MP usually
      ],
    );
  }

  Widget _buildBar(String label, int current, int max, double percent, Color color) {
    return Row(
      children: [
        SizedBox(
          width: 30,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: Column(
            children: [
              Container(
                height: 14,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black,
                  border: Border.all(color: AppColors.textSecondary.withValues(alpha: 0.3)),
                ),
                child: Stack(
                  children: [
                    FractionallySizedBox(
                      widthFactor: percent,
                      child: Container(
                        color: color.withValues(alpha: 0.8),
                      ),
                    ),
                    Center(
                      child: Text(
                        "$current / $max",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          shadows: [Shadow(color: Colors.black, blurRadius: 2)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsGrid(BuildContext context, UserStats stats) {
    final attrs = stats.attributes;
    final canSpend = stats.statPoints > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "STATISTICS",
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (canSpend)
              Text(
                "(AVAILABLE POINTS: ${stats.statPoints})",
                style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(color: AppColors.gold, blurRadius: 4)],
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        
        // New Layout: Radar Chart + List
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Left: Stats List
            Expanded(
              flex: 4,
              child: Column(
                children: [
                  _buildStatRow("STRENGTH", attrs.str, "STR", canSpend),
                  _buildStatRow("VITALITY", attrs.vit, "VIT", canSpend),
                  _buildStatRow("AGILITY", attrs.agi, "AGI", canSpend),
                  _buildStatRow("INTELLIGENCE", attrs.intl, "INT", canSpend),
                  _buildStatRow("SENSE", attrs.sen, "SEN", canSpend),
                ],
              ),
            ),
            
            const SizedBox(width: 24), // Added spacing

            // Right: Radar Chart
            Expanded(
              flex: 5,
              child: Center(
                child: StatRadarChart(
                  stats: {
                    'STR': attrs.str,
                    'VIT': attrs.vit,
                    'AGI': attrs.agi,
                    'INT': attrs.intl,
                    'SEN': attrs.sen,
                  },
                  size: 140,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatRow(String label, int value, String key, bool canSpend) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
          ),
          Row(
            children: [
              Text(
                "$value",
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              if (canSpend) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => presenter.allocatePoint(key),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.gold),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add, size: 12, color: AppColors.gold),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

}
