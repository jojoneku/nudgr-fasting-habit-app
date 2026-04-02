import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../../app_colors.dart';
import '../../models/food_entry.dart';
import '../../models/meal_slot.dart';
import '../../presenters/nutrition_presenter.dart';
import 'food_library_screen.dart';
import 'log_meal_sheet.dart';
import 'nutrition_history_screen.dart';
import 'nutrition_settings_sheet.dart';

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
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    return AppBar(
      title: const Text(
        'ALCHEMY LAB',
        style: TextStyle(letterSpacing: 3.0, fontSize: 14),
      ),
      centerTitle: true,
      actions: [
        _ModeChip(mode: presenter.goals.mode),
        IconButton(
          icon: const Icon(Icons.history),
          onPressed: () =>
              _push(context, NutritionHistoryScreen(presenter: presenter)),
        ),
        IconButton(
          icon: const Icon(Icons.tune),
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
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  Widget _buildFab(BuildContext context) {
    final locked =
        presenter.goals.ifSyncEnabled && !presenter.isEatingWindowOpen;
    return FloatingActionButton.extended(
      onPressed: locked ? null : () => _showLogMealSheet(context),
      backgroundColor: locked ? AppColors.neutral : AppColors.gold,
      foregroundColor: AppColors.background,
      icon: Icon(locked ? Icons.lock_outline : Icons.add),
      label: Text(
        locked ? 'FASTING' : 'LOG MEAL',
        style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
      ),
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
    final icon = open ? Icons.lock_open : Icons.lock_outline;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(
            presenter.windowStatusLabel,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600),
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
    final barColor = goalMet ? AppColors.success : AppColors.gold;
    final progress = presenter.calorieProgress.clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: barColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(MdiIcons.flask, color: barColor, size: 18),
              const SizedBox(width: 8),
              Text(
                presenter.summaryLabel,
                style: TextStyle(
                  color: barColor,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              if (goalMet) ...[
                const SizedBox(width: 8),
                const Icon(Icons.check_circle,
                    color: AppColors.success, size: 20),
              ],
            ],
          ),
          const SizedBox(height: 10),
          _AnimatedBar(progress: progress, color: barColor),
          if (presenter.goals.proteinGrams != null) ...[
            const SizedBox(height: 12),
            _MacroBars(presenter: presenter),
          ],
          if (presenter.goalStreak > 0) ...[
            const SizedBox(height: 8),
            Text(
              '🔥 ${presenter.goalStreak}-day goal streak',
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
        height: 8,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            height: 8,
            width: constraints.maxWidth * progress,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
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
        ? '$label: ${current.toStringAsFixed(0)}/${goal!.toStringAsFixed(0)}g'
        : '$label: ${current.toStringAsFixed(0)}g';
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(text,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600)),
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
            label: '+ Library',
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
      padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            slot: widget.slot,
            calories: calories,
            expanded: _expanded,
            onAddTap: widget.onAddTap,
            onToggle: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded) ...[
            if (!hasItems)
              _EmptySlot(slot: widget.slot, onAddTap: widget.onAddTap),
            ...entries.map((entry) => _EntryRow(
                  entry: entry,
                  onDelete: () =>
                      widget.presenter.removeFoodEntry(entry.id, widget.slot),
                )),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final MealSlot slot;
  final int calories;
  final bool expanded;
  final VoidCallback onAddTap;
  final VoidCallback onToggle;
  const _SectionHeader({
    required this.slot,
    required this.calories,
    required this.expanded,
    required this.onAddTap,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: onToggle,
          child: Row(
            children: [
              Text(
                slot.label.toUpperCase(),
                style: TextStyle(
                  color: AppColors.gold.withValues(alpha: 0.8),
                  fontSize: 11,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (calories > 0) ...[
                const SizedBox(width: 6),
                Text('· $calories kcal',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
              ],
              const SizedBox(width: 4),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                color: AppColors.textSecondary,
                size: 16,
              ),
            ],
          ),
        ),
        const Spacer(),
        SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
            icon: const Icon(Icons.add, color: AppColors.gold, size: 18),
            onPressed: onAddTap,
            tooltip: 'Add to ${slot.label}',
          ),
        ),
      ],
    );
  }
}

class _EmptySlot extends StatelessWidget {
  final MealSlot slot;
  final VoidCallback onAddTap;
  const _EmptySlot({required this.slot, required this.onAddTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onAddTap,
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: AppColors.gold.withValues(alpha: 0.08), width: 1),
        ),
        child: Text(
          'Tap + to log ${slot.label.toLowerCase()}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
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
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          if (entry.aiEstimated)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text('~',
                  style: TextStyle(
                      color: AppColors.accent.withValues(alpha: 0.8),
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.name,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
                if (entry.protein != null)
                  Text(
                    'P: ${entry.protein!.toStringAsFixed(0)}g  '
                    'C: ${(entry.carbs ?? 0).toStringAsFixed(0)}g  '
                    'F: ${(entry.fat ?? 0).toStringAsFixed(0)}g',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 10),
                  ),
              ],
            ),
          ),
          Text('${entry.calories} kcal',
              style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: AppColors.textSecondary, size: 17),
              onPressed: onDelete,
            ),
          ),
        ],
      ),
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
          color: AppColors.gold.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
        ),
        child: Text(
          mode.label.toUpperCase(),
          style: const TextStyle(
              color: AppColors.gold,
              fontSize: 9,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
