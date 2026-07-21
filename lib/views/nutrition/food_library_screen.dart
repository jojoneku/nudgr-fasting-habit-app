import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app_colors.dart';
import '../../models/food_db_entry.dart';
import '../../models/food_entry.dart';
import '../../models/food_template.dart';
import '../../models/meal_slot.dart';
import '../../models/personal_food_entry.dart';
import '../../presenters/nutrition_presenter.dart';
import '../widgets/system/system.dart';

/// Shared "Nudgr redesign" row/card surface — top-right→bottom-left gradient,
/// hairline [outlineVariant] border, generous corner radius.
BoxDecoration _rowSurface(
  ColorScheme cs, {
  double radius = 18,
  Color? borderColor,
}) =>
    BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [cs.surfaceContainerHigh, cs.surfaceContainerLow],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor ?? cs.outlineVariant),
    );

/// Uppercase micro-label used for row sublabels and section hints.
TextStyle _microLabel(ColorScheme cs) => TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.0,
      color: cs.onSurfaceVariant,
    );

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
            title: 'Learned by AI',
            child: presenter.learnedFoods.isEmpty
                ? const _EmptyLabel(
                    text:
                        'No learned foods yet — confident Cloud AI logs land here')
                : Column(
                    children: presenter.learnedFoods
                        .map((e) => _LearnedFoodRow(
                              entry: e,
                              presenter: presenter,
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.inbox_outlined, color: cs.onSurfaceVariant, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12.5,
                height: 1.3,
              ),
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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FloatingActionButton.extended(
      onPressed: () => AppBottomSheet.show(
        context: context,
        title: 'New Template',
        body: _CreateTemplateSheet(presenter: presenter),
      ),
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      icon: const Icon(Icons.add, size: 20),
      label: const Text('New Template',
          style: TextStyle(fontWeight: FontWeight.w700)),
      shape: const StadiumBorder(),
    );
  }
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
    AppBottomSheet.show(
      context: context,
      title: entry.name,
      body: _GramPickerSheet(
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
    final cs = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_items.isNotEmpty) ...[
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$_totalCalories kcal',
              style: TextStyle(
                color: context.appColors.gold,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        AppTextField(
          controller: _nameCtrl,
          hint: 'Template name (e.g. Pre-workout meal)',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        if (_items.isNotEmpty) _buildItemsList(),
        _buildSearchField(),
        if (_isSearching)
          LinearProgressIndicator(
            color: cs.primary,
            backgroundColor: Colors.transparent,
            minHeight: 2,
          ),
        if (_searchResults.isNotEmpty) _buildSearchResults(),
        if (_searchResults.isEmpty &&
            _searchCtrl.text.isEmpty &&
            _items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              'Search for foods to add to your template',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ),
        const SizedBox(height: 12),
        AppPrimaryButton(
          label: 'Save Template',
          isLoading: _isSaving,
          onPressed: _canSave && !_isSaving ? _save : null,
        ),
      ],
    );
  }

  Widget _buildItemsList() => ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 200),
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 4),
          itemCount: _items.length,
          itemBuilder: (_, i) => _ItemChip(
            entry: _items[i],
            onRemove: () => _removeItem(i),
          ),
        ),
      );

  Widget _buildSearchField() => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
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
          padding: const EdgeInsets.only(bottom: 4),
          itemCount: _searchResults.length,
          itemBuilder: (_, i) {
            final entry = _searchResults[i];
            final cs = Theme.of(context).colorScheme;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _onResultTapped(entry),
                  borderRadius: BorderRadius.circular(18),
                  child: Ink(
                    decoration: _rowSurface(cs),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.name,
                            style: TextStyle(
                              color: cs.onSurface,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(entry.densityLabel, style: _microLabel(cs)),
                        const SizedBox(width: 6),
                        Icon(Icons.add_circle_outline,
                            color: cs.primary, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
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
    final cs = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.entry.densityLabel, style: _microLabel(cs)),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _quickAmounts.map((g) {
              final selected = _gramCtrl.text.trim() == g.toStringAsFixed(0) ||
                  _gramCtrl.text.trim() == '${g.round()}';
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () =>
                      setState(() => _gramCtrl.text = g.round().toString()),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? cs.primary.withValues(alpha: 0.15)
                          : cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected ? cs.primary : cs.outlineVariant,
                      ),
                    ),
                    child: Text(
                      '${g.round()}g',
                      style: TextStyle(
                        color: selected ? cs.primary : cs.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Text(
                '$_previewCalories kcal',
                style: TextStyle(
                  color: context.appColors.gold,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
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
    final cs = theme.colorScheme;
    final macros = [
      if (entry.protein != null) 'P ${entry.protein!.round()}g',
      if (entry.carbs != null) 'C ${entry.carbs!.round()}g',
      if (entry.fat != null) 'F ${entry.fat!.round()}g',
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: _rowSurface(cs),
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
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (entry.grams != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    '${entry.grams!.round()}g${macros.isNotEmpty ? ' · $macros' : ''}'
                        .toUpperCase(),
                    style: _microLabel(cs),
                  ),
                ],
              ],
            ),
          ),
          Text(
            '${entry.calories} kcal',
            style: TextStyle(
              color: context.appColors.gold,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close, color: cs.onSurfaceVariant, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Template Row ──────────────────────────────────────────────────────────────

/// Row for one personal-dict entry (Plan 027 §2.1). Shows the food name,
/// stored macros per 100g, hit count, and edit + delete affordances so
/// users can correct or remove a wrong entry without nuking the whole
/// dictionary.
class _LearnedFoodRow extends StatelessWidget {
  final PersonalFoodEntry entry;
  final NutritionPresenter presenter;
  const _LearnedFoodRow({required this.entry, required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _showEditDialog(context),
          child: Ink(
            decoration: _rowSurface(cs),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${entry.kcalPer100g.round()} kcal / 100g  ·  '
                                '${entry.hits} ${entry.hits == 1 ? 'use' : 'uses'}'
                            .toUpperCase(),
                        style: _microLabel(cs),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 36,
                  height: 44,
                  child: IconButton(
                    icon: Icon(
                      Icons.edit_outlined,
                      color: cs.onSurfaceVariant,
                      size: 18,
                    ),
                    tooltip: 'Edit macros',
                    onPressed: () => _showEditDialog(context),
                  ),
                ),
                SizedBox(
                  width: 36,
                  height: 44,
                  child: IconButton(
                    icon: Icon(
                      Icons.close,
                      color: cs.onSurfaceVariant,
                      size: 18,
                    ),
                    tooltip: 'Remove from learned',
                    onPressed: () => _confirmDelete(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showEditDialog(BuildContext context) async {
    final kcalCtrl =
        TextEditingController(text: entry.kcalPer100g.toStringAsFixed(0));
    final proteinCtrl = TextEditingController(
        text: entry.proteinPer100g?.toStringAsFixed(1) ?? '');
    final carbsCtrl = TextEditingController(
        text: entry.carbsPer100g?.toStringAsFixed(1) ?? '');
    final fatCtrl =
        TextEditingController(text: entry.fatPer100g?.toStringAsFixed(1) ?? '');
    final errorNotifier = ValueNotifier<String?>(null);

    double? parseOptional(String s) {
      final t = s.trim();
      if (t.isEmpty) return null;
      return double.tryParse(t);
    }

    final updated = await AppDialog.show<_EditedMacros>(
      context: context,
      title: entry.name,
      body: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Builder(
              builder: (ctx) => Text('PER 100G',
                  style: _microLabel(Theme.of(ctx).colorScheme)),
            ),
            const SizedBox(height: 12),
            AppTextField(
              label: 'Calories (kcal)',
              controller: kcalCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            AppTextField(
              label: 'Protein (g)',
              controller: proteinCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            AppTextField(
              label: 'Carbs (g)',
              controller: carbsCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            AppTextField(
              label: 'Fat (g)',
              controller: fatCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            ValueListenableBuilder<String?>(
              valueListenable: errorNotifier,
              builder: (ctx, err, __) => err == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(err,
                          style: TextStyle(
                              color: Theme.of(ctx).colorScheme.error)),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final kcal = double.tryParse(kcalCtrl.text.trim());
            if (kcal == null || kcal <= 0) {
              errorNotifier.value = 'Calories must be a number > 0';
              return;
            }
            Navigator.of(context).pop(_EditedMacros(
              kcal,
              parseOptional(proteinCtrl.text),
              parseOptional(carbsCtrl.text),
              parseOptional(fatCtrl.text),
            ));
          },
          child: const Text('Save'),
        ),
      ],
    );

    kcalCtrl.dispose();
    proteinCtrl.dispose();
    carbsCtrl.dispose();
    fatCtrl.dispose();
    errorNotifier.dispose();

    if (updated == null) return;
    await presenter.updateLearnedFood(
      name: entry.name,
      kcalPer100g: updated.kcal,
      proteinPer100g: updated.protein,
      carbsPer100g: updated.carbs,
      fatPer100g: updated.fat,
    );
    if (context.mounted) {
      AppToast.success(context, 'Updated ${entry.name}');
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await AppConfirmDialog.confirm(
      context: context,
      title: 'Remove learned food?',
      body:
          'The next time you log "${entry.name}", the AI will resolve it from scratch.',
      confirmLabel: 'Remove',
      isDestructive: true,
    );
    if (confirmed) {
      await presenter.removeLearnedFood(entry.name);
    }
  }
}

class _EditedMacros {
  final double kcal;
  final double? protein;
  final double? carbs;
  final double? fat;
  const _EditedMacros(this.kcal, this.protein, this.carbs, this.fat);
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: _rowSurface(
        cs,
        borderColor:
            template.isPinned ? cs.primary.withValues(alpha: 0.45) : null,
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
                      Icon(Icons.push_pin, color: cs.primary, size: 11),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        template.name,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  (template.isMeal
                          ? '${template.totalCalories} kcal · ${template.entries.length} items'
                          : '${template.totalCalories} kcal')
                      .toUpperCase(),
                  style: _microLabel(cs),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              icon: Icon(Icons.add_circle,
                  color: context.appColors.gold, size: 22),
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
                      ? cs.primary
                      : cs.onSurfaceVariant.withValues(alpha: 0.5),
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
                    color: cs.onSurfaceVariant, size: 16),
                tooltip: 'Rename',
                onPressed: () => _showRenameDialog(context),
              ),
            ),
            SizedBox(
              width: 36,
              height: 44,
              child: IconButton(
                icon: Icon(Icons.delete_outline,
                    color: cs.onSurfaceVariant, size: 16),
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
    AppDialog.show<void>(
      context: context,
      title: 'Rename',
      body: AppTextField(
        controller: ctrl,
        autofocus: true,
        hint: 'Template name',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            presenter.renameTemplate(template.id, ctrl.text);
            Navigator.of(context).pop();
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
