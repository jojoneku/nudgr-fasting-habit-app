import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app_colors.dart';
import '../../models/food_entry.dart';
import '../../models/meal_slot.dart';
import '../../presenters/nutrition_presenter.dart';
import 'food_library_screen.dart';
import 'log_meal_sheet.dart';
import 'nutrition_history_screen.dart';
import 'nutrition_settings_sheet.dart';

final _calFmt = NumberFormat('#,###');

class NutritionScreen extends StatelessWidget {
  final NutritionPresenter presenter;

  const NutritionScreen({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) => _NutritionBody(presenter: presenter),
    );
  }
}

class _NutritionBody extends StatelessWidget {
  final NutritionPresenter presenter;
  const _NutritionBody({required this.presenter});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(context),
      body: _buildBody(context),
      floatingActionButton: _buildFab(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    return AppBar(
      title: const Text('Nutrition'),
      centerTitle: false,
      actions: [
        _ModeChip(mode: presenter.goals.mode),
        IconButton(
          icon: const Icon(Icons.history_outlined, size: 22),
          onPressed: () =>
              _push(context, NutritionHistoryScreen(presenter: presenter)),
        ),
        IconButton(
          icon: const Icon(Icons.tune_outlined, size: 22),
          onPressed: () => _showSettings(context),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    return CustomScrollView(
      slivers: [
        if (presenter.goals.ifSyncEnabled)
          SliverToBoxAdapter(child: _IfSyncBanner(presenter: presenter)),
        SliverToBoxAdapter(child: _SummaryCard(presenter: presenter)),
        SliverToBoxAdapter(child: _QuickAddRow(presenter: presenter)),
        SliverToBoxAdapter(
          child: _MealSection(
            slot: MealSlot.meal,
            presenter: presenter,
            onAddTap: () => _showLogMealSheet(context),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }

  Widget _buildFab(BuildContext context) {
    final locked =
        presenter.goals.ifSyncEnabled && !presenter.isEatingWindowOpen;
    return FloatingActionButton(
      onPressed: locked ? null : () => _showLogMealSheet(context),
      backgroundColor: locked ? AppColors.surface : AppColors.gold,
      foregroundColor: locked ? AppColors.textSecondary : AppColors.background,
      elevation: locked ? 0 : 4,
      child: Icon(locked ? Icons.lock_outline : Icons.add, size: 24),
    );
  }

  void _showLogMealSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LogMealSheet(presenter: presenter),
    );
  }

  void _showSettings(BuildContext context) {
    showNutritionSettingsSheet(context, presenter);
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }
}

// ─── IF-Sync Banner ───────────────────────────────────────────────────────────

class _IfSyncBanner extends StatelessWidget {
  final NutritionPresenter presenter;
  const _IfSyncBanner({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final open = presenter.isEatingWindowOpen;
    final color = open ? AppColors.success : AppColors.danger;
    final icon = open ? Icons.lock_open_outlined : Icons.lock_outline;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 8),
          Text(
            presenter.windowStatusLabel,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

// ─── Summary Card ─────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final NutritionPresenter presenter;
  const _SummaryCard({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final goalMet = presenter.isCalorieGoalMet;
    final barColor = goalMet ? AppColors.success : AppColors.secondary;
    final progress = presenter.calorieProgress.clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _calFmt.format(presenter.todayCalories),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'of ${_calFmt.format(presenter.effectiveGoal)} kcal',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
              if (goalMet) ...[
                const Spacer(),
                const Icon(Icons.check_circle,
                    color: AppColors.success, size: 18),
              ],
            ],
          ),
          const SizedBox(height: 12),
          _AnimatedBar(progress: progress, color: barColor),
          if (presenter.goals.proteinGrams != null) ...[
            const SizedBox(height: 12),
            _MacroBars(presenter: presenter),
          ],
          if (presenter.goalStreak > 0) ...[
            const SizedBox(height: 8),
            Text(
              '${presenter.goalStreak}-day streak',
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class _AnimatedBar extends StatelessWidget {
  final double progress;
  final Color color;
  const _AnimatedBar({required this.progress, required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return Container(
        height: 6,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            height: 6,
            width: constraints.maxWidth * progress,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      );
    });
  }
}

class _MacroBars extends StatelessWidget {
  final NutritionPresenter presenter;
  const _MacroBars({required this.presenter});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _MacroRow('P', presenter.todayProtein, presenter.goals.proteinGrams,
            AppColors.primary),
        const SizedBox(height: 6),
        _MacroRow('C', presenter.todayCarbs, presenter.goals.carbsGrams,
            AppColors.gold),
        const SizedBox(height: 6),
        _MacroRow('F', presenter.todayFat, presenter.goals.fatGrams,
            AppColors.danger),
      ],
    );
  }
}

class _MacroRow extends StatelessWidget {
  final String label;
  final double current;
  final double? goal;
  final Color color;
  const _MacroRow(this.label, this.current, this.goal, this.color);

  @override
  Widget build(BuildContext context) {
    final progress =
        goal != null && goal! > 0 ? (current / goal!).clamp(0.0, 1.0) : 0.0;
    final text = goal != null
        ? '$label ${current.toStringAsFixed(0)}/${goal!.toStringAsFixed(0)}g'
        : '$label ${current.toStringAsFixed(0)}g';
    return Row(
      children: [
        SizedBox(
          width: 76,
          child: Text(text,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w500)),
        ),
        Expanded(child: _AnimatedBar(progress: progress, color: color)),
      ],
    );
  }
}

// ─── Quick-Add Row ────────────────────────────────────────────────────────────

class _QuickAddRow extends StatelessWidget {
  final NutritionPresenter presenter;
  const _QuickAddRow({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final recents = presenter.recentFoods;
    if (recents.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          ...recents.map((t) => _QuickChip(
                label: t.name,
                onTap: () => presenter.addMealFromTemplate(t, MealSlot.meal),
              )),
          _QuickChip(
            label: 'Library',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FoodLibraryScreen(presenter: presenter),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _QuickChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
        ),
      ),
    );
  }
}

// ─── Meal Section ─────────────────────────────────────────────────────────────

class _MealSection extends StatefulWidget {
  final MealSlot slot;
  final NutritionPresenter presenter;
  final VoidCallback onAddTap;
  const _MealSection({
    required this.slot,
    required this.presenter,
    required this.onAddTap,
  });

  @override
  State<_MealSection> createState() => _MealSectionState();
}

class _MealSectionState extends State<_MealSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final entries = widget.presenter.todayLog.entriesForSlot(widget.slot);
    final calories = widget.presenter.caloriesForSlot(widget.slot);
    final hasItems = entries.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          calories: calories,
          expanded: _expanded,
          hasItems: hasItems,
          onAddTap: widget.onAddTap,
          onToggle: () => setState(() => _expanded = !_expanded),
        ),
        if (_expanded) ...[
          if (!hasItems) _EmptySlot(onAddTap: widget.onAddTap),
          ...entries.map((entry) => _EntryRow(
                entry: entry,
                onDelete: () =>
                    widget.presenter.removeFoodEntry(entry.id, widget.slot),
              )),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final int calories;
  final bool expanded;
  final bool hasItems;
  final VoidCallback onAddTap;
  final VoidCallback onToggle;
  const _SectionHeader({
    required this.calories,
    required this.expanded,
    required this.hasItems,
    required this.onAddTap,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 4, 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: hasItems ? onToggle : null,
            child: Row(
              children: [
                const Text(
                  'Today',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (calories > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    '· ${_calFmt.format(calories)} kcal',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
                if (hasItems) ...[
                  const SizedBox(width: 2),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textSecondary,
                    size: 16,
                  ),
                ],
              ],
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              icon:
                  const Icon(Icons.add, color: AppColors.textPrimary, size: 20),
              onPressed: onAddTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  final VoidCallback onAddTap;
  const _EmptySlot({required this.onAddTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onAddTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.add_circle_outline,
                  color: AppColors.textSecondary.withValues(alpha: 0.5),
                  size: 16),
              const SizedBox(width: 10),
              Text(
                'Log your first meal today',
                style: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.7),
                    fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  final FoodEntry entry;
  final VoidCallback onDelete;
  const _EntryRow({required this.entry, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
          child: Row(
            children: [
              if (entry.aiEstimated)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    '~',
                    style: TextStyle(
                      color: AppColors.accent.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      if (entry.protein != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'P ${entry.protein!.round()}g · '
                          'C ${(entry.carbs ?? 0).round()}g · '
                          'F ${(entry.fat ?? 0).round()}g',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '${entry.calories}',
                      style: const TextStyle(
                        color: AppColors.gold,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const TextSpan(
                      text: ' kcal',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 44,
                height: 44,
                child: IconButton(
                  icon: const Icon(Icons.close,
                      color: AppColors.textSecondary, size: 16),
                  onPressed: onDelete,
                ),
              ),
            ],
          ),
        ),
        const Divider(
            height: 1, indent: 16, endIndent: 16, color: Color(0x12FFFFFF)),
      ],
    );
  }
}

// ─── Mode Chip ────────────────────────────────────────────────────────────────

class _ModeChip extends StatelessWidget {
  final TrackingMode mode;
  const _ModeChip({required this.mode});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.textSecondary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          mode.label.toLowerCase(),
          style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
