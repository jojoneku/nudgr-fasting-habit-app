import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../models/food_template.dart';
import '../../models/meal_slot.dart';
import '../../presenters/nutrition_presenter.dart';

class FoodLibraryScreen extends StatelessWidget {
  final NutritionPresenter presenter;
  const FoodLibraryScreen({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final singles = presenter.savedTemplates.where((t) => !t.isMeal).toList();
    final meals = presenter.savedTemplates.where((t) => t.isMeal).toList();
    final recents = presenter.recentFoods;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Food Library'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (recents.isNotEmpty) ...[
            _sectionHeader('RECENT'),
            const SizedBox(height: 8),
            ...recents.map((t) => _TemplateRow(
                  template: t,
                  presenter: presenter,
                  showDelete: false,
                )),
            const SizedBox(height: 20),
          ],
          _sectionHeader('SAVED FOODS'),
          const SizedBox(height: 8),
          if (singles.isEmpty)
            _emptyLabel('No saved foods yet')
          else
            ...singles.map((t) => _TemplateRow(
                  template: t,
                  presenter: presenter,
                  showDelete: true,
                )),
          const SizedBox(height: 20),
          _sectionHeader('MEAL TEMPLATES'),
          const SizedBox(height: 8),
          if (meals.isEmpty)
            _emptyLabel('No meal templates yet — save a meal when logging')
          else
            ...meals.map((t) => _TemplateRow(
                  template: t,
                  presenter: presenter,
                  showDelete: true,
                )),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label) => Text(
        label,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      );

  Widget _emptyLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      );
}

class _TemplateRow extends StatelessWidget {
  final FoodTemplate template;
  final NutritionPresenter presenter;
  final bool showDelete;
  const _TemplateRow({
    required this.template,
    required this.presenter,
    required this.showDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(template.name,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
                Text(
                  template.isMeal
                      ? '${template.totalCalories} kcal · ${template.entries.length} items'
                      : '${template.totalCalories} kcal',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              icon:
                  const Icon(Icons.add_circle, color: AppColors.gold, size: 22),
              tooltip: template.isMeal ? 'Add all items' : 'Add',
              onPressed: () => _showSlotPicker(context),
            ),
          ),
          if (showDelete)
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.textSecondary, size: 18),
                onPressed: () => presenter.deleteFoodTemplate(template.id),
              ),
            ),
        ],
      ),
    );
  }

  void _showSlotPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SlotPicker(
        title: template.name,
        onSlotSelected: (slot) => presenter.addMealFromTemplate(template, slot),
      ),
    );
  }
}

class _SlotPicker extends StatelessWidget {
  final String title;
  final void Function(MealSlot) onSlotSelected;
  const _SlotPicker({required this.title, required this.onSlotSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add "$title" to...',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ...MealSlot.values.map((slot) => ListTile(
                contentPadding: EdgeInsets.zero,
                minVerticalPadding: 0,
                title: Text(slot.label,
                    style: const TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  onSlotSelected(slot);
                  Navigator.pop(context);
                },
              )),
        ],
      ),
    );
  }
}
