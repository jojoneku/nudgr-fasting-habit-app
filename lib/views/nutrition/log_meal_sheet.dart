import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app_colors.dart';
import '../../models/ai_meal_estimate.dart';
import '../../models/food_db_entry.dart';
import '../../models/food_entry.dart';
import '../../models/food_template.dart';
import '../../models/meal_slot.dart';
import '../../presenters/nutrition_presenter.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

const _kSlots = [
  MealSlot.breakfast,
  MealSlot.lunch,
  MealSlot.dinner,
  MealSlot.snack,
  MealSlot.meal,
];

const _kSlotIcons = {
  MealSlot.breakfast: Icons.wb_sunny_outlined,
  MealSlot.lunch: Icons.light_mode_outlined,
  MealSlot.dinner: Icons.nights_stay_outlined,
  MealSlot.snack: Icons.cookie_outlined,
  MealSlot.meal: Icons.restaurant_outlined,
};

// ─── Main Sheet ───────────────────────────────────────────────────────────────

class LogMealSheet extends StatefulWidget {
  final NutritionPresenter presenter;
  final MealSlot? preselectedSlot;

  const LogMealSheet({
    super.key,
    required this.presenter,
    this.preselectedSlot,
  });

  @override
  State<LogMealSheet> createState() => _LogMealSheetState();
}

class _LogMealSheetState extends State<LogMealSheet>
    with SingleTickerProviderStateMixin {
  late MealSlot _slot;
  late TabController _tabCtrl;

  final _aiCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  List<FoodDbEntry> _searchResults = [];
  final List<_PendingEntry> _pendingEntries = [];

  bool _saveAsTemplate = false;
  bool _isSearching = false;
  bool _isLogging = false;

  int get _totalCalories =>
      _pendingEntries.fold(0, (s, e) => s + e.entry.calories);

  @override
  void initState() {
    super.initState();
    _slot = widget.preselectedSlot ?? MealSlot.meal;
    _tabCtrl = TabController(length: 3, vsync: this);
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _aiCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _isSearching = true);
    final results = await widget.presenter.foodDb.search(q);
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  void _addEntry(FoodEntry entry) {
    HapticFeedback.lightImpact();
    setState(() => _pendingEntries.add(_PendingEntry(entry)));
  }

  void _removeEntry(_PendingEntry p) {
    HapticFeedback.lightImpact();
    setState(() => _pendingEntries.remove(p));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textSecondary.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _buildHeader(),
          ),
          const SizedBox(height: 14),
          // Slot chips
          _buildSlotSelector(),
          const SizedBox(height: 14),
          // Tab bar
          _buildTabBar(),
          // Tab content — flexible so it doesn't overflow
          Flexible(
            child: Padding(
              padding: EdgeInsets.only(bottom: bottom),
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _AiTab(
                    presenter: widget.presenter,
                    controller: _aiCtrl,
                    slot: _slot,
                    onConfirm: (entries) {
                      for (final e in entries) {
                        _addEntry(e.toFoodEntry());
                      }
                    },
                  ),
                  _SearchTab(
                    controller: _searchCtrl,
                    focusNode: _searchFocus,
                    results: _searchResults,
                    isSearching: _isSearching,
                    onAdd: (entry) {
                      _addEntry(entry);
                      _searchCtrl.clear();
                      setState(() => _searchResults = []);
                    },
                    onManual: _showManualEntry,
                  ),
                  _QuickTab(
                    presenter: widget.presenter,
                    slot: _slot,
                    onAdd: _addEntry,
                  ),
                ],
              ),
            ),
          ),
          // Cart
          if (_pendingEntries.isNotEmpty)
            _buildCart(),
          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: _buildActions(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.restaurant_menu, color: AppColors.gold, size: 16),
        const SizedBox(width: 8),
        const Text(
          'LOG MEAL',
          style: TextStyle(
              color: AppColors.gold,
              fontSize: 13,
              letterSpacing: 2.0,
              fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.close,
                color: AppColors.textSecondary, size: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildSlotSelector() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _kSlots.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final slot = _kSlots[i];
          final selected = slot == _slot;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _slot = slot);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.gold.withValues(alpha: 0.15)
                    : AppColors.background,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected
                      ? AppColors.gold
                      : AppColors.textSecondary.withValues(alpha: 0.2),
                  width: selected ? 1.2 : 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _kSlotIcons[slot] ?? Icons.restaurant_outlined,
                    size: 12,
                    color: selected
                        ? AppColors.gold
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    slot.label,
                    style: TextStyle(
                      color: selected
                          ? AppColors.gold
                          : AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabCtrl,
        onTap: (i) {
          if (i == 1) {
            // Auto-focus search when switching to search tab
            Future.delayed(const Duration(milliseconds: 150),
                () => _searchFocus.requestFocus());
          }
        },
        indicator: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.12),
              blurRadius: 6,
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: AppColors.accent,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8),
        unselectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
        tabs: const [
          Tab(text: '✦ AI'),
          Tab(text: '⌕ SEARCH'),
          Tab(text: '⚡ QUICK'),
        ],
      ),
    );
  }

  Widget _buildCart() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.gold.withValues(alpha: 0.2), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_fire_department,
                  color: AppColors.gold, size: 14),
              const SizedBox(width: 6),
              Text(
                '$_totalCalories kcal  ·  ${_pendingEntries.length} item${_pendingEntries.length == 1 ? '' : 's'}',
                style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (_pendingEntries.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() => _pendingEntries.clear()),
                  child: const Text('Clear all',
                      style: TextStyle(
                          color: AppColors.danger,
                          fontSize: 11)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _pendingEntries.map((p) {
              return GestureDetector(
                onTap: () => _removeEntry(p),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppColors.textSecondary.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          p.entry.name,
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${p.entry.calories}',
                        style: const TextStyle(
                            color: AppColors.gold,
                            fontSize: 10,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.close,
                          color: AppColors.textSecondary, size: 10),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Checkbox(
                value: _saveAsTemplate,
                onChanged: (v) =>
                    setState(() => _saveAsTemplate = v ?? false),
                activeColor: AppColors.gold,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              const Text('Save as template',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    final hasItems = _pendingEntries.isNotEmpty;
    return Row(
      children: [
        SizedBox(
          width: 80,
          height: 52,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: BorderSide(
                  color: AppColors.textSecondary.withValues(alpha: 0.3),
                  width: 0.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('✕',
                style: TextStyle(fontSize: 16)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 52,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: hasItems
                    ? [
                        BoxShadow(
                          color: AppColors.gold.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : [],
              ),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      hasItems ? AppColors.gold : AppColors.surface,
                  foregroundColor: hasItems
                      ? AppColors.background
                      : AppColors.textSecondary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: !hasItems || _isLogging ? null : _logMeal,
                child: _isLogging
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.background))
                    : Text(
                        hasItems
                            ? 'LOG  ·  $_totalCalories kcal'
                            : 'ADD ITEMS TO LOG',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.6,
                          fontSize: hasItems ? 13 : 11,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _logMeal() async {
    setState(() => _isLogging = true);
    HapticFeedback.mediumImpact();
    for (final p in _pendingEntries) {
      await widget.presenter.addFoodEntry(p.entry, _slot);
    }
    if (_saveAsTemplate && _pendingEntries.isNotEmpty) {
      final template = FoodTemplate(
        id: FoodEntry.generateId(),
        name:
            '${_slot.label} ${DateTime.now().day}/${DateTime.now().month}',
        isMeal: _pendingEntries.length > 1,
        defaultSlot: _slot,
        entries: _pendingEntries.map((p) => p.entry).toList(),
      );
      await widget.presenter.saveFoodTemplate(template);
    }
    if (mounted) Navigator.pop(context);
  }

  void _showManualEntry() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ManualEntrySheet(
        onAdd: (entry) => _addEntry(entry),
      ),
    );
  }
}

// ─── AI Tab ───────────────────────────────────────────────────────────────────

class _AiTab extends StatelessWidget {
  final NutritionPresenter presenter;
  final TextEditingController controller;
  final MealSlot slot;
  final void Function(List<AiItemEstimate>) onConfirm;

  const _AiTab({
    required this.presenter,
    required this.controller,
    required this.slot,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (_, __) {
        final available = presenter.isAiAvailable;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: available ? _buildActiveState() : _AiUnavailableBanner(presenter: presenter),
        );
      },
    );
  }

  Widget _buildActiveState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Describe field
        Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.25)),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.auto_awesome,
                    color: AppColors.accent, size: 13),
                SizedBox(width: 6),
                Text('Describe your meal',
                    style: TextStyle(
                        color: AppColors.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8)),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 14, height: 1.4),
                maxLines: 3,
                minLines: 2,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _runEstimate(),
                decoration: InputDecoration(
                  hintText:
                      'e.g. 2 cups of rice, grilled chicken breast 200g, mixed salad with olive oil dressing',
                  hintStyle: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: 0.5),
                      fontSize: 13,
                      height: 1.4),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent.withValues(alpha: 0.15),
                    foregroundColor: AppColors.accent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: presenter.isAiEstimating ? null : _runEstimate,
                  icon: const Icon(Icons.bolt, size: 15),
                  label: const Text('ANALYSE MEAL',
                      style: TextStyle(fontSize: 11, letterSpacing: 1.0, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Status / result
        _buildStatus(),
      ],
    );
  }

  Widget _buildStatus() {
    if (presenter.isAiEstimating) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.15)),
        ),
        child: const Row(
          children: [
            SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.accent)),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'System analysing meal composition...',
                style: TextStyle(color: AppColors.accent, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    final error = presenter.aiEstimateError;
    if (error != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppColors.danger, size: 15),
            const SizedBox(width: 8),
            Expanded(
              child: Text(error,
                  style: const TextStyle(color: AppColors.danger, fontSize: 12)),
            ),
            GestureDetector(
              onTap: presenter.clearEstimate,
              child: const Icon(Icons.close,
                  color: AppColors.textSecondary, size: 16),
            ),
          ],
        ),
      );
    }

    final estimate = presenter.lastEstimate;
    if (estimate != null) {
      return _AiResultCard(
        estimate: estimate,
        onConfirm: (items) {
          onConfirm(items);
          presenter.clearEstimate();
        },
        onDismiss: presenter.clearEstimate,
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.tips_and_updates_outlined,
              color: AppColors.textSecondary, size: 14),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Be specific — include portion sizes for better accuracy.',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  void _runEstimate() {
    final desc = controller.text.trim();
    if (desc.isEmpty) return;
    presenter.estimateMeal(desc);
  }
}

// ─── Search Tab ───────────────────────────────────────────────────────────────

class _SearchTab extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<FoodDbEntry> results;
  final bool isSearching;
  final void Function(FoodEntry) onAdd;
  final VoidCallback onManual;

  const _SearchTab({
    required this.controller,
    required this.focusNode,
    required this.results,
    required this.isSearching,
    required this.onAdd,
    required this.onManual,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: _buildSearchField(),
        ),
        if (isSearching)
          const LinearProgressIndicator(
              color: AppColors.accent,
              backgroundColor: Colors.transparent,
              minHeight: 2),
        Expanded(
          child: results.isEmpty
              ? _buildEmpty()
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 6, bottom: 12),
                  itemCount: results.length,
                  itemBuilder: (_, i) => _SearchResultRow(
                    entry: results[i],
                    onAdd: onAdd,
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: GestureDetector(
            onTap: onManual,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.textSecondary.withValues(alpha: 0.15)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.edit_outlined,
                      color: AppColors.textSecondary, size: 14),
                  SizedBox(width: 6),
                  Text('Enter manually',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search food database...',
        hintStyle: TextStyle(
            color: AppColors.textSecondary.withValues(alpha: 0.5),
            fontSize: 13),
        prefixIcon: const Icon(Icons.search,
            color: AppColors.textSecondary, size: 18),
        suffixIcon: controller.text.isNotEmpty
            ? GestureDetector(
                onTap: controller.clear,
                child: const Icon(Icons.close,
                    color: AppColors.textSecondary, size: 16),
              )
            : null,
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: AppColors.accent, width: 1)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search,
              color: AppColors.textSecondary.withValues(alpha: 0.3),
              size: 36),
          const SizedBox(height: 8),
          Text(
            controller.text.isEmpty
                ? 'Type to search 1000+ foods'
                : 'No results for "${controller.text}"',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ─── Quick Tab ────────────────────────────────────────────────────────────────

class _QuickTab extends StatelessWidget {
  final NutritionPresenter presenter;
  final MealSlot slot;
  final void Function(FoodEntry) onAdd;

  const _QuickTab({
    required this.presenter,
    required this.slot,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (_, __) {
        final recents = presenter.recentFoods;
        final templates = presenter.savedTemplates;

        if (recents.isEmpty && templates.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt_outlined,
                    color: AppColors.textSecondary.withValues(alpha: 0.3),
                    size: 36),
                const SizedBox(height: 8),
                const Text('Log meals to build quick-access history',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (recents.isNotEmpty) ...[
                _sectionLabel('RECENTLY LOGGED'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: recents.map((t) {
                    final cal = t.totalCalories;
                    return GestureDetector(
                      onTap: () {
                        for (final e in t.entries) {
                          onAdd(FoodEntry(
                            id: FoodEntry.generateId(),
                            name: e.name,
                            calories: e.calories,
                            protein: e.protein,
                            carbs: e.carbs,
                            fat: e.fat,
                            grams: e.grams,
                            loggedAt: DateTime.now(),
                          ));
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: AppColors.textSecondary
                                  .withValues(alpha: 0.15)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(t.name,
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 12)),
                            const SizedBox(width: 6),
                            Text('$cal',
                                style: const TextStyle(
                                    color: AppColors.gold,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),
              ],
              if (templates.isNotEmpty) ...[
                _sectionLabel('SAVED TEMPLATES'),
                const SizedBox(height: 8),
                ...templates.map((t) => _TemplateCard(
                      template: t,
                      onAdd: () {
                        for (final e in t.entries) {
                          onAdd(FoodEntry(
                            id: FoodEntry.generateId(),
                            name: e.name,
                            calories: e.calories,
                            protein: e.protein,
                            carbs: e.carbs,
                            fat: e.fat,
                            grams: e.grams,
                            loggedAt: DateTime.now(),
                          ));
                        }
                      },
                    )),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _sectionLabel(String label) => Text(
        label,
        style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w600),
      );
}

// ─── Template Card ────────────────────────────────────────────────────────────

class _TemplateCard extends StatelessWidget {
  final FoodTemplate template;
  final VoidCallback onAdd;

  const _TemplateCard({required this.template, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final isMeal = template.isMeal;
    final cal = template.totalCalories;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.textSecondary.withValues(alpha: 0.12)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onAdd,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isMeal ? Icons.restaurant : Icons.set_meal_outlined,
                    color: AppColors.gold,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(template.name,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text(
                        isMeal
                            ? '${template.entries.length} items · $cal kcal'
                            : '$cal kcal',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('+ ADD',
                      style: TextStyle(
                          color: AppColors.gold,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── AI Unavailable Banner ────────────────────────────────────────────────────

class _AiUnavailableBanner extends StatelessWidget {
  final NutritionPresenter presenter;
  const _AiUnavailableBanner({required this.presenter});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (_, __) {
        final downloading = presenter.isAiDownloading;
        final progress = presenter.aiDownloadProgress;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.auto_awesome,
                      color: AppColors.accent, size: 14),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('On-Device AI',
                          style: TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                      Text('Fully private — no internet needed',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(presenter.aiSizeLabel,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 10)),
                ),
              ]),
              const SizedBox(height: 14),
              if (downloading) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress / 100.0,
                    minHeight: 6,
                    backgroundColor: AppColors.surface,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(AppColors.accent),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Downloading model...',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 11)),
                    Text('$progress%',
                        style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ] else
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent.withValues(alpha: 0.12),
                      foregroundColor: AppColors.accent,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: const Text('DOWNLOAD AI MODEL',
                        style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 1.0,
                            fontWeight: FontWeight.w600)),
                    onPressed: () => presenter.downloadAiModel(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ─── AI Result Card ───────────────────────────────────────────────────────────

class _AiResultCard extends StatefulWidget {
  final AiMealEstimate estimate;
  final void Function(List<AiItemEstimate>) onConfirm;
  final VoidCallback onDismiss;

  const _AiResultCard({
    required this.estimate,
    required this.onConfirm,
    required this.onDismiss,
  });

  @override
  State<_AiResultCard> createState() => _AiResultCardState();
}

class _AiResultCardState extends State<_AiResultCard> {
  late List<AiItemEstimate> _items;

  @override
  void initState() {
    super.initState();
    _items = List<AiItemEstimate>.from(widget.estimate.items);
  }

  @override
  Widget build(BuildContext context) {
    final total = _items.fold(0, (s, i) => s + i.calories);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.auto_awesome,
                  color: AppColors.accent, size: 14),
              const SizedBox(width: 6),
              Text(
                '~$total kcal estimated',
                style: const TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
              const Spacer(),
              GestureDetector(
                onTap: widget.onDismiss,
                child: const Icon(Icons.close,
                    color: AppColors.textSecondary, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Item rows
          ..._items.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(item.name,
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 12)),
                  ),
                  // Macro badges
                  if (item.protein != null)
                    _macroBadge('P', item.protein!.round(), AppColors.success),
                  if (item.carbs != null)
                    _macroBadge(
                        'C', item.carbs!.round(), AppColors.accent),
                  if (item.fat != null)
                    _macroBadge(
                        'F', item.fat!.round(), AppColors.gold),
                  const SizedBox(width: 4),
                  Text('${item.calories}',
                      style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => setState(() => _items.removeAt(i)),
                    child: const Icon(Icons.remove_circle_outline,
                        color: AppColors.danger, size: 14),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.background,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _items.isEmpty
                  ? null
                  : () => widget.onConfirm(_items),
              child: Text(
                'ADD TO MEAL  ·  $total kcal',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                    fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _macroBadge(String label, int value, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('$label$value',
          style: TextStyle(
              color: color, fontSize: 9, fontWeight: FontWeight.w600)),
    );
  }
}

// ─── Search Result Row ────────────────────────────────────────────────────────

class _SearchResultRow extends StatefulWidget {
  final FoodDbEntry entry;
  final void Function(FoodEntry) onAdd;
  const _SearchResultRow({required this.entry, required this.onAdd});

  @override
  State<_SearchResultRow> createState() => _SearchResultRowState();
}

class _SearchResultRowState extends State<_SearchResultRow> {
  double _grams = 100;
  final _ctrl = TextEditingController(text: '100');

  static const _servingSizes = [50.0, 100.0, 150.0, 200.0];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cal = (widget.entry.caloriesPer100g * _grams / 100).round();
    final protein = widget.entry.proteinPer100g != null
        ? (widget.entry.proteinPer100g! * _grams / 100)
        : null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.entry.name,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Row(children: [
                      Text('$cal kcal',
                          style: const TextStyle(
                              color: AppColors.gold,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      if (protein != null) ...[
                        const SizedBox(width: 8),
                        Text('P: ${protein.round()}g',
                            style: const TextStyle(
                                color: AppColors.success, fontSize: 11)),
                      ],
                      const SizedBox(width: 8),
                      Text('${_grams.round()}g',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11)),
                    ]),
                  ],
                ),
              ),
              SizedBox(
                width: 44,
                height: 44,
                child: IconButton(
                  icon: const Icon(Icons.add_circle,
                      color: AppColors.gold, size: 26),
                  onPressed: () =>
                      widget.onAdd(widget.entry.toFoodEntry(_grams)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Serving size chips
          SizedBox(
            height: 26,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ..._servingSizes.map((g) {
                  final selected = _grams == g;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _grams = g;
                        _ctrl.text = g.round().toString();
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.gold.withValues(alpha: 0.15)
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected
                              ? AppColors.gold
                              : AppColors.textSecondary
                                  .withValues(alpha: 0.2),
                          width: selected ? 1 : 0.5,
                        ),
                      ),
                      child: Text('${g.round()}g',
                          style: TextStyle(
                              color: selected
                                  ? AppColors.gold
                                  : AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.normal)),
                    ),
                  );
                }),
                // Custom grams input
                SizedBox(
                  width: 64,
                  child: TextField(
                    controller: _ctrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 11),
                    decoration: InputDecoration(
                      hintText: 'custom',
                      hintStyle: TextStyle(
                          color: AppColors.textSecondary.withValues(alpha: 0.5),
                          fontSize: 10),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                    ),
                    onChanged: (v) {
                      final g = double.tryParse(v);
                      if (g != null && g > 0) setState(() => _grams = g);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Pending Entry ────────────────────────────────────────────────────────────

class _PendingEntry {
  final FoodEntry entry;
  _PendingEntry(this.entry);
}

// ─── Manual Entry Sheet ───────────────────────────────────────────────────────

class _ManualEntrySheet extends StatefulWidget {
  final void Function(FoodEntry) onAdd;
  const _ManualEntrySheet({required this.onAdd});

  @override
  State<_ManualEntrySheet> createState() => _ManualEntrySheetState();
}

class _ManualEntrySheetState extends State<_ManualEntrySheet> {
  final _nameCtrl = TextEditingController();
  final _calCtrl = TextEditingController();
  final _pCtrl = TextEditingController();
  final _cCtrl = TextEditingController();
  final _fCtrl = TextEditingController();
  bool _showMacros = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _calCtrl.dispose();
    _pCtrl.dispose();
    _cCtrl.dispose();
    _fCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('CUSTOM FOOD',
                style: TextStyle(
                    color: AppColors.gold,
                    fontSize: 11,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(Icons.close,
                    color: AppColors.textSecondary, size: 14),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          TextField(
              controller: _nameCtrl,
              autofocus: true,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: _dec('Food name', 'e.g. Chicken breast 150g')),
          const SizedBox(height: 10),
          TextField(
              controller: _calCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: _dec('Calories (kcal)', 'e.g. 320')),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => setState(() => _showMacros = !_showMacros),
            child: Row(children: [
              Icon(
                  _showMacros
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: AppColors.textSecondary,
                  size: 16),
              const SizedBox(width: 4),
              Text(
                  _showMacros ? 'Hide macros' : 'Add macros (optional)',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
            ]),
          ),
          if (_showMacros) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _pCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 12),
                      decoration: _dec('Protein', 'g'))),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: _cCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 12),
                      decoration: _dec('Carbs', 'g'))),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: _fCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 12),
                      decoration: _dec('Fat', 'g'))),
            ]),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.background,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _add,
              child: const Text('ADD TO MEAL',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, letterSpacing: 0.8)),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _dec(String label, String hint) => InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        hintStyle: TextStyle(
            color: AppColors.textSecondary.withValues(alpha: 0.5),
            fontSize: 11),
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: AppColors.accent, width: 1)),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      );

  void _add() {
    final name = _nameCtrl.text.trim();
    final cal = int.tryParse(_calCtrl.text.trim());
    if (name.isEmpty || cal == null || cal <= 0) return;
    widget.onAdd(FoodEntry(
      id: FoodEntry.generateId(),
      name: name,
      calories: cal,
      protein: double.tryParse(_pCtrl.text.trim()),
      carbs: double.tryParse(_cCtrl.text.trim()),
      fat: double.tryParse(_fCtrl.text.trim()),
      loggedAt: DateTime.now(),
    ));
    Navigator.pop(context);
  }
}
