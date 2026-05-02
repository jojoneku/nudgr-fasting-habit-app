import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app_colors.dart';
import '../../models/food_db_entry.dart';
import '../../models/food_entry.dart';
import '../../models/food_template.dart';
import '../../models/meal_slot.dart';
import '../../presenters/nutrition_presenter.dart';
import '../widgets/system/system.dart';

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

    return AppPageScaffold(
      title: 'Food Library',
      padding: EdgeInsets.zero,
      floatingActionButton: _CreateTemplateFab(presenter: presenter),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
        children: [
          if (recents.isNotEmpty) ...[
            AppSection(
              title: 'Recent',
              child: Column(
                children: recents
                    .map((t) => _TemplateRow(
                          template: t,
                          presenter: presenter,
                          showDelete: false,
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 20),
          ],
          AppSection(
            title: 'Saved Foods',
            child: singles.isEmpty
                ? const _EmptyLabel(text: 'No saved foods yet')
                : Column(
                    children: singles
                        .map((t) => _TemplateRow(
                              template: t,
                              presenter: presenter,
                              showDelete: true,
                            ))
                        .toList(),
                  ),
          ),
          const SizedBox(height: 20),
          AppSection(
            title: 'Meal Templates',
            child: meals.isEmpty
                ? const _EmptyLabel(
                    text: 'No meal templates yet — save a meal when logging')
                : Column(
                    children: meals
                        .map((t) => _TemplateRow(
                              template: t,
                              presenter: presenter,
                              showDelete: true,
                            ))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyLabel extends StatelessWidget {
  final String text;
  const _EmptyLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(Icons.inbox_outlined,
              color: Theme.of(context).colorScheme.onSurfaceVariant, size: 14),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
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
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final List<FoodEntry> _items = [];

  List<FoodDbEntry> _searchResults = [];
  bool _isSearching = false;
  bool _isSaving = false;
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  bool get _canSave => _nameCtrl.text.trim().isNotEmpty && _items.isNotEmpty;
  int get _totalCalories => _items.fold(0, (s, e) => s + e.calories);

  void _onSearchChanged() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    final gen = ++_searchGeneration;
    setState(() => _isSearching = true);
    final results = await widget.presenter.foodDb.search(q);
    if (mounted && _searchGeneration == gen) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  void _onResultTapped(FoodDbEntry entry) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GramPickerSheet(
        entry: entry,
        onConfirm: (grams) {
          final foodEntry = entry.toFoodEntry(grams);
          setState(() {
            _items.add(foodEntry);
            if (_nameCtrl.text.trim().isEmpty && _items.length == 1) {
              _nameCtrl.text = entry.name
                  .split(',')
                  .first
                  .split(' ')
                  .take(3)
                  .join(' ')
                  .toLowerCase()
                  .trim();
            }
          });
        },
      ),
    );
  }

  void _removeItem(int index) {
    HapticFeedback.lightImpact();
    setState(() => _items.removeAt(index));
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();
    final template = FoodTemplate(
      id: FoodEntry.generateId(),
      name: _nameCtrl.text.trim(),
      isMeal: _items.length > 1,
      entries: _items,
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
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHandle(),
          _buildHeader(),
          const SizedBox(height: 12),
          _buildNameField(),
          const SizedBox(height: 12),
          if (_items.isNotEmpty) _buildItemsList(),
          _buildSearchField(),
          if (_isSearching)
            LinearProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
              backgroundColor: Colors.transparent,
              minHeight: 2,
            ),
          if (_searchResults.isNotEmpty) _buildSearchResults(),
          if (_searchResults.isEmpty &&
              _searchCtrl.text.isEmpty &&
              _items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text(
                'Search for foods to add to your template',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ),
          _buildSaveButton(bottomPad),
        ],
      ),
    );
  }

  Widget _buildHandle() => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _buildHeader() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: Row(
          children: [
            Text(
              'New Template',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            if (_items.isNotEmpty)
              Text(
                '$_totalCalories kcal',
                style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
          ],
        ),
      );

  Widget _buildNameField() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: AppTextField(
          controller: _nameCtrl,
          hint: 'Template name (e.g. Pre-workout meal)',
          onChanged: (_) => setState(() {}),
        ),
      );

  Widget _buildItemsList() => ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 200),
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          itemCount: _items.length,
          itemBuilder: (_, i) => _ItemChip(
            entry: _items[i],
            onRemove: () => _removeItem(i),
          ),
        ),
      );

  Widget _buildSearchField() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: AppTextField(
          controller: _searchCtrl,
          focusNode: _searchFocus,
          hint: 'Search foods to add…',
          prefixIcon: Icons.search,
          suffixIcon: _searchCtrl.text.isNotEmpty ? Icons.close : null,
          onSuffixIconTap: () {
            _searchCtrl.clear();
            setState(() => _searchResults = []);
          },
        ),
      );

  Widget _buildSearchResults() => ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          itemCount: _searchResults.length,
          itemBuilder: (_, i) {
            final entry = _searchResults[i];
            return InkWell(
              onTap: () => _onResultTapped(entry),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.name,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      entry.densityLabel,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.add_circle_outline,
                        color: Theme.of(context).colorScheme.primary, size: 18),
                  ],
                ),
              ),
            );
          },
        ),
      );

  Widget _buildSaveButton(double bottomPad) => Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottomPad),
        child: AppPrimaryButton(
          label: 'Save Template',
          isLoading: _isSaving,
          onPressed: _canSave && !_isSaving ? _save : null,
        ),
      );
}

// ── Gram picker sheet ─────────────────────────────────────────────────────────

class _GramPickerSheet extends StatefulWidget {
  final FoodDbEntry entry;
  final void Function(double grams) onConfirm;
  const _GramPickerSheet({required this.entry, required this.onConfirm});

  @override
  State<_GramPickerSheet> createState() => _GramPickerSheetState();
}

class _GramPickerSheetState extends State<_GramPickerSheet> {
  final _gramCtrl = TextEditingController(text: '100');
  static const _quickAmounts = [50.0, 100.0, 150.0, 200.0, 250.0];

  double get _grams => double.tryParse(_gramCtrl.text.trim()) ?? 100.0;
  int get _previewCalories =>
      (widget.entry.caloriesPer100g * _grams / 100).round();

  @override
  void dispose() {
    _gramCtrl.dispose();
    super.dispose();
  }

  void _confirm() {
    final g = _grams;
    if (g <= 0) return;
    Navigator.pop(context);
    widget.onConfirm(g);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomPad),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.entry.name,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            widget.entry.densityLabel,
            style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _quickAmounts.map((g) {
                final selected =
                    _gramCtrl.text.trim() == g.toStringAsFixed(0) ||
                        _gramCtrl.text.trim() == '${g.round()}';
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _gramCtrl.text = g.round().toString()),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? theme.colorScheme.primary.withValues(alpha: 0.15)
                            : theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected
                              ? theme.colorScheme.primary
                              : Colors.transparent,
                        ),
                      ),
                      child: Text(
                        '${g.round()}g',
                        style: TextStyle(
                          color: selected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ListenableBuilder(
                  listenable: _gramCtrl,
                  builder: (_, __) => AppTextField(
                    controller: _gramCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    hint: 'Grams',
                    suffix: const Text('g'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_previewCalories kcal',
                  style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppPrimaryButton(
            label: 'Add to Template',
            onPressed: _grams > 0 ? _confirm : null,
          ),
        ],
      ),
    );
  }
}

// ── Item chip ─────────────────────────────────────────────────────────────────

class _ItemChip extends StatelessWidget {
  final FoodEntry entry;
  final VoidCallback onRemove;
  const _ItemChip({required this.entry, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final macros = [
      if (entry.protein != null) 'P ${entry.protein!.round()}g',
      if (entry.carbs != null) 'C ${entry.carbs!.round()}g',
      if (entry.fat != null) 'F ${entry.fat!.round()}g',
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
                if (entry.grams != null)
                  Text(
                    '${entry.grams!.round()}g${macros.isNotEmpty ? ' · $macros' : ''}',
                    style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11),
                  ),
              ],
            ),
          ),
          Text(
            '${entry.calories} kcal',
            style: const TextStyle(
                color: AppColors.gold,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close,
                  color: theme.colorScheme.onSurfaceVariant, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Template Row ──────────────────────────────────────────────────────────────

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
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: template.isPinned
            ? Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.25),
                width: 0.5)
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (template.isPinned) ...[
                      Icon(Icons.push_pin,
                          color: theme.colorScheme.primary, size: 11),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        template.name,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
                Text(
                  template.isMeal
                      ? '${template.totalCalories} kcal · ${template.entries.length} items'
                      : '${template.totalCalories} kcal',
                  style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant, fontSize: 11),
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
          if (showDelete) ...[
            SizedBox(
              width: 36,
              height: 44,
              child: IconButton(
                icon: Icon(
                  Icons.push_pin,
                  color: template.isPinned
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.5),
                  size: 16,
                ),
                tooltip: template.isPinned ? 'Unpin' : 'Pin to top',
                onPressed: () => presenter.togglePinTemplate(template.id),
              ),
            ),
            SizedBox(
              width: 36,
              height: 44,
              child: IconButton(
                icon: Icon(Icons.edit_outlined,
                    color: theme.colorScheme.onSurfaceVariant, size: 16),
                tooltip: 'Rename',
                onPressed: () => _showRenameDialog(context),
              ),
            ),
            SizedBox(
              width: 36,
              height: 44,
              child: IconButton(
                icon: Icon(Icons.delete_outline,
                    color: theme.colorScheme.onSurfaceVariant, size: 16),
                onPressed: () => presenter.deleteFoodTemplate(template.id),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showSlotPicker(BuildContext context) {
    AppActionSheet.show<MealSlot>(
      context: context,
      title: 'Add "${template.name}" to…',
      actions: MealSlot.values
          .map((slot) => AppActionSheetItem(
                label: slot.label,
                value: slot,
              ))
          .toList(),
    ).then((slot) {
      if (slot != null) presenter.addMealFromTemplate(template, slot);
    });
  }

  void _showRenameDialog(BuildContext context) {
    final ctrl = TextEditingController(text: template.name);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename'),
        content: AppTextField(
          controller: ctrl,
          autofocus: true,
          hint: 'Template name',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              presenter.renameTemplate(template.id, ctrl.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
