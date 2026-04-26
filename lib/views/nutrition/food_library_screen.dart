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

class _CreateTemplateSheetState extends State<_CreateTemplateSheet> {
  final _nameCtrl = TextEditingController();
  final List<_ItemDraft> _items = [];
  bool _isSaving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  bool get _canSave =>
      _nameCtrl.text.trim().isNotEmpty && _items.isNotEmpty && _items.every((i) => i.isValid);

  int get _totalCalories =>
      _items.fold(0, (s, i) => s + (int.tryParse(i.calCtrl.text) ?? 0));

  void _addItem() {
    setState(() => _items.add(_ItemDraft()));
  }

  void _removeItem(_ItemDraft item) {
    item.dispose();
    setState(() => _items.remove(item));
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    final now = DateTime.now();
    final entries = _items.map((i) {
      return FoodEntry(
        id: FoodEntry.generateId(),
        name: i.nameCtrl.text.trim(),
        calories: int.parse(i.calCtrl.text),
        protein: double.tryParse(i.proteinCtrl.text),
        carbs: double.tryParse(i.carbsCtrl.text),
        fat: double.tryParse(i.fatCtrl.text),
        loggedAt: now,
      );
    }).toList();

    final template = FoodTemplate(
      id: FoodEntry.generateId(),
      name: _nameCtrl.text.trim(),
      isMeal: entries.length > 1,
      entries: entries,
    );

    await widget.presenter.saveFoodTemplate(template);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomPad),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
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
                  Text('$_totalCalories kcal total',
                      style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 20),

            // Template name
            _label('Template name'),
            const SizedBox(height: 8),
            TextField(
              controller: _nameCtrl,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: _inputDecoration('e.g. Pre-workout meal'),
            ),
            const SizedBox(height: 20),

            // Items
            _label('FOOD ITEMS'),
            const SizedBox(height: 10),
            ..._items.map((item) => _ItemRow(
                  draft: item,
                  onRemove: () => _removeItem(item),
                  onChanged: () => setState(() {}),
                )),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _addItem,
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.textSecondary.withValues(alpha: 0.2),
                    width: 0.5,
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, color: AppColors.textSecondary, size: 16),
                    SizedBox(width: 6),
                    Text('Add food item',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _canSave ? AppColors.primary : AppColors.surface,
                  foregroundColor:
                      _canSave ? Colors.black : AppColors.textSecondary,
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
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11));

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

// ── Item draft ────────────────────────────────────────────────────────────────

class _ItemDraft {
  final nameCtrl = TextEditingController();
  final calCtrl = TextEditingController();
  final proteinCtrl = TextEditingController();
  final carbsCtrl = TextEditingController();
  final fatCtrl = TextEditingController();

  bool get isValid =>
      nameCtrl.text.trim().isNotEmpty &&
      (int.tryParse(calCtrl.text) ?? 0) > 0;

  void dispose() {
    nameCtrl.dispose();
    calCtrl.dispose();
    proteinCtrl.dispose();
    carbsCtrl.dispose();
    fatCtrl.dispose();
  }
}

// ── Item row ──────────────────────────────────────────────────────────────────

class _ItemRow extends StatelessWidget {
  final _ItemDraft draft;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  const _ItemRow({
    required this.draft,
    required this.onRemove,
    required this.onChanged,
  });

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.primary, width: 1)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: draft.nameCtrl,
                  onChanged: (_) => onChanged(),
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 13),
                  decoration: _dec('Food name'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 44,
                height: 44,
                child: IconButton(
                  icon: const Icon(Icons.remove_circle_outline,
                      color: AppColors.danger, size: 18),
                  onPressed: onRemove,
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: draft.calCtrl,
                  onChanged: (_) => onChanged(),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 13),
                  decoration: _dec('kcal *'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: draft.proteinCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 13),
                  decoration: _dec('P (g)'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: draft.carbsCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 13),
                  decoration: _dec('C (g)'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: draft.fatCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 13),
                  decoration: _dec('F (g)'),
                ),
              ),
            ],
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
