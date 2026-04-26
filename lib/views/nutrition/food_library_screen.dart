import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app_colors.dart';
import '../../models/food_entry.dart';
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
      floatingActionButton: _CreateTemplateFab(presenter: presenter),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
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
        child: Row(
          children: [
            const Icon(Icons.inbox_outlined,
                color: AppColors.textSecondary, size: 14),
            const SizedBox(width: 6),
            Text(text,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      );
}

// ── Create template FAB ────────────────────────────────────────────────────────

class _CreateTemplateFab extends StatelessWidget {
  final NutritionPresenter presenter;
  const _CreateTemplateFab({required this.presenter});

  @override
  Widget build(BuildContext context) => FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _CreateTemplateSheet(presenter: presenter),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add, size: 20),
        label: const Text('New Template',
            style: TextStyle(fontWeight: FontWeight.w700)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      );
}

// ── Create template sheet ──────────────────────────────────────────────────────

class _CreateTemplateSheet extends StatefulWidget {
  final NutritionPresenter presenter;
  const _CreateTemplateSheet({required this.presenter});

  @override
  State<_CreateTemplateSheet> createState() => _CreateTemplateSheetState();
}

class _TemplateItem {
  final String name;
  final int calories;
  final double? protein;
  final double? carbs;
  final double? fat;

  const _TemplateItem({
    required this.name,
    required this.calories,
    this.protein,
    this.carbs,
    this.fat,
  });

  FoodEntry toFoodEntry() => FoodEntry(
        id: FoodEntry.generateId(),
        name: name,
        calories: calories,
        protein: protein,
        carbs: carbs,
        fat: fat,
        loggedAt: DateTime.now(),
      );
}

class _CreateTemplateSheetState extends State<_CreateTemplateSheet> {
  final _nameCtrl = TextEditingController();
  final _inputCtrl = TextEditingController();
  final _inputFocus = FocusNode();
  final List<_TemplateItem> _items = [];
  bool _isParsing = false;
  bool _isSaving = false;
  String? _parseError;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _inputCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  bool get _canSave => _nameCtrl.text.trim().isNotEmpty && _items.isNotEmpty;

  int get _totalCalories => _items.fold(0, (s, i) => s + i.calories);

  Future<void> _parseInput() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _isParsing = true;
      _parseError = null;
    });
    try {
      final entries = await widget.presenter.parseFoodItemsForTemplate(text);
      if (entries.isEmpty) {
        setState(() => _parseError = 'No food items recognised — try "100g chicken" or "2 eggs"');
      } else {
        _inputCtrl.clear();
        setState(() {
          for (final e in entries) {
            _items.add(_TemplateItem(
              name: e.name,
              calories: e.calories,
              protein: e.protein,
              carbs: e.carbs,
              fat: e.fat,
            ));
          }
          // Auto-fill name from first item if still empty
          if (_nameCtrl.text.trim().isEmpty && _items.length == 1) {
            _nameCtrl.text = _items.first.name;
          }
        });
      }
    } catch (e) {
      setState(() => _parseError = 'Something went wrong. Try again.');
    } finally {
      setState(() => _isParsing = false);
    }
  }

  void _removeItem(int index) => setState(() => _items.removeAt(index));

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    final template = FoodTemplate(
      id: FoodEntry.generateId(),
      name: _nameCtrl.text.trim(),
      isMeal: _items.length > 1,
      entries: _items.map((i) => i.toFoodEntry()).toList(),
    );

    await widget.presenter.saveFoodTemplate(template);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      constraints: BoxConstraints(maxHeight: screenHeight * 0.88),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: AppColors.textSecondary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    const Text('New Template',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (_items.isNotEmpty)
                      Text('$_totalCalories kcal',
                          style: const TextStyle(
                              color: AppColors.gold,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 16),
                // Template name
                TextField(
                  controller: _nameCtrl,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  decoration: _inputDecoration('Template name (e.g. Pre-workout meal)'),
                ),
              ],
            ),
          ),

          // ── Items list ────────────────────────────────────────────────────
          if (_items.isNotEmpty)
            Flexible(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                shrinkWrap: true,
                itemCount: _items.length,
                itemBuilder: (_, i) => _ItemChip(
                  item: _items[i],
                  onRemove: () => _removeItem(i),
                ),
              ),
            ),

          if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                'Type a food below — e.g. "100g chicken breast, 1 cup rice"',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ),

          if (_parseError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(_parseError!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 11)),
            ),

          // ── Chat input ────────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 8 + bottomPad),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputCtrl,
                    focusNode: _inputFocus,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _parseInput(),
                    decoration: _inputDecoration('Add food… e.g. 2 boiled eggs'),
                  ),
                ),
                const SizedBox(width: 10),
                _isParsing
                    ? const SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.primary),
                          ),
                        ),
                      )
                    : GestureDetector(
                        onTap: _parseInput,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.send_rounded,
                              color: AppColors.primary, size: 18),
                        ),
                      ),
              ],
            ),
          ),

          // ── Save button ───────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomPad),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _canSave ? AppColors.primary : AppColors.background,
                  foregroundColor: _canSave ? Colors.black : AppColors.textSecondary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _canSave && !_isSaving ? _save : null,
                child: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : const Text('Save Template',
                        style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 1)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );
}

// ── Item chip ─────────────────────────────────────────────────────────────────

class _ItemChip extends StatelessWidget {
  final _TemplateItem item;
  final VoidCallback onRemove;
  const _ItemChip({required this.item, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final macros = [
      if (item.protein != null) 'P ${item.protein!.round()}g',
      if (item.carbs != null) 'C ${item.carbs!.round()}g',
      if (item.fat != null) 'F ${item.fat!.round()}g',
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
                if (macros.isNotEmpty)
                  Text(macros,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          Text('${item.calories} kcal',
              style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, color: AppColors.textSecondary, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Existing widgets ──────────────────────────────────────────────────────────

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
