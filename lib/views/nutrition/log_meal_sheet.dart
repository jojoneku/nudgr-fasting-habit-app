import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app_colors.dart';
import '../../models/ai_meal_estimate.dart';
import '../../models/food_db_entry.dart';
import '../../models/food_entry.dart';
import '../../models/food_template.dart';
import '../../models/meal_slot.dart';
import '../../presenters/nutrition_presenter.dart';

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

class _LogMealSheetState extends State<LogMealSheet> {
  final _inputCtrl = TextEditingController();
  final _inputFocus = FocusNode();

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
    _inputCtrl.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _onInputChanged() async {
    final q = _inputCtrl.text.trim();
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
    return ListenableBuilder(
      listenable: widget.presenter,
      builder: (_, __) => _buildSheet(context),
    );
  }

  Widget _buildSheet(BuildContext context) {
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
          _buildHandle(),
          _buildHeader(),
          const SizedBox(height: 10),
          _buildInputField(),
          if (_isSearching)
            const LinearProgressIndicator(
              color: AppColors.accent,
              backgroundColor: Colors.transparent,
              minHeight: 2,
            ),
          Flexible(
            child: Padding(
              padding: EdgeInsets.only(bottom: bottom),
              child: _buildContent(),
            ),
          ),
          _buildAiState(),
          if (_pendingEntries.isNotEmpty) _buildCart(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: _buildActions(),
          ),
        ],
      ),
    );
  }

  Widget _buildHandle() {
    return Column(
      children: [
        const SizedBox(height: 10),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.textSecondary.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
      child: Row(
        children: [
          const Text(
            'Add Food',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              icon: const Icon(Icons.close,
                  color: AppColors.textSecondary, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: _inputCtrl,
        focusNode: _inputFocus,
        autofocus: true,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search or describe a meal...',
          hintStyle: TextStyle(
            color: AppColors.textSecondary.withValues(alpha: 0.5),
            fontSize: 13,
          ),
          prefixIcon: const Icon(Icons.search,
              color: AppColors.textSecondary, size: 18),
          suffixIcon: _inputCtrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close,
                      color: AppColors.textSecondary, size: 16),
                  onPressed: () {
                    _inputCtrl.clear();
                    setState(() => _searchResults = []);
                    widget.presenter.clearEstimate();
                  },
                )
              : null,
          filled: true,
          fillColor: AppColors.background,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.accent, width: 1)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final hasInput = _inputCtrl.text.trim().isNotEmpty;

    if (!hasInput) return _buildQuickSection();

    if (_searchResults.isNotEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.only(top: 6, bottom: 12),
        itemCount: _searchResults.length,
        itemBuilder: (_, i) => _SearchResultRow(
          entry: _searchResults[i],
          onAdd: (entry) {
            _addEntry(entry);
            _inputCtrl.clear();
            setState(() => _searchResults = []);
          },
        ),
      );
    }

    if (!_isSearching) return _buildNoResults();

    return const SizedBox.shrink();
  }

  Widget _buildQuickSection() {
    final recents = widget.presenter.recentFoods;
    final templates = widget.presenter.savedTemplates;

    if (recents.isEmpty && templates.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search,
                  color: AppColors.textSecondary.withValues(alpha: 0.25),
                  size: 32),
              const SizedBox(height: 8),
              const Text(
                'Search the food database or describe your meal',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13, height: 1.5),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (recents.isNotEmpty) ...[
            _sectionLabel('Recently logged'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: recents.map((t) {
                final cal = t.totalCalories;
                return GestureDetector(
                  onTap: () {
                    for (final e in t.entries) {
                      _addEntry(FoodEntry(
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(t.name,
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontSize: 12)),
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
            _sectionLabel('Saved templates'),
            const SizedBox(height: 8),
            ...templates.map((t) => _TemplateCard(
                  template: t,
                  onAdd: () {
                    for (final e in t.entries) {
                      _addEntry(FoodEntry(
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
            const SizedBox(height: 8),
          ],
          GestureDetector(
            onTap: _showManualEntry,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.edit_outlined,
                    color: AppColors.textSecondary.withValues(alpha: 0.5),
                    size: 14),
                const SizedBox(width: 6),
                Text(
                  'Add manually',
                  style: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: 0.5),
                      fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResults() {
    final aiAvailable = widget.presenter.isAiAvailable;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Icon(Icons.search_off,
              color: AppColors.textSecondary.withValues(alpha: 0.25), size: 32),
          const SizedBox(height: 8),
          Text(
            'No results for "${_inputCtrl.text.trim()}"',
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (aiAvailable) ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent.withValues(alpha: 0.15),
                  foregroundColor: AppColors.accent,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: widget.presenter.isAiEstimating
                    ? null
                    : () =>
                        widget.presenter.estimateMeal(_inputCtrl.text.trim()),
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('Estimate with AI'),
              ),
            ),
            const SizedBox(height: 10),
          ] else ...[
            _AiUnavailableBanner(presenter: widget.presenter),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: BorderSide(
                    color: AppColors.textSecondary.withValues(alpha: 0.2)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _showManualEntry,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Add manually'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiState() {
    if (widget.presenter.isAiEstimating) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.accent),
            ),
            SizedBox(width: 12),
            Text('Analyzing meal...',
                style: TextStyle(color: AppColors.accent, fontSize: 12)),
          ],
        ),
      );
    }

    final error = widget.presenter.aiEstimateError;
    if (error != null) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppColors.danger, size: 15),
            const SizedBox(width: 8),
            Expanded(
              child: Text(error,
                  style:
                      const TextStyle(color: AppColors.danger, fontSize: 12)),
            ),
            GestureDetector(
              onTap: widget.presenter.clearEstimate,
              child: const Icon(Icons.close,
                  color: AppColors.textSecondary, size: 16),
            ),
          ],
        ),
      );
    }

    final estimate = widget.presenter.lastEstimate;
    if (estimate != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: _AiResultCard(
          estimate: estimate,
          onConfirm: (items) {
            for (final item in items) {
              _addEntry(item.toFoodEntry());
            }
            widget.presenter.clearEstimate();
            _inputCtrl.clear();
          },
          onDismiss: widget.presenter.clearEstimate,
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildCart() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._pendingEntries.map((p) => _CartRow(
                pending: p,
                onRemove: () => _removeEntry(p),
              )),
          const Divider(height: 16, color: Color(0x12FFFFFF)),
          Row(
            children: [
              Text(
                '$_totalCalories kcal',
                style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _pendingEntries.clear()),
                child: Text(
                  'Clear all',
                  style: TextStyle(
                      color: AppColors.danger.withValues(alpha: 0.7),
                      fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Switch.adaptive(
                value: _saveAsTemplate,
                onChanged: (v) => setState(() => _saveAsTemplate = v),
                activeThumbColor: AppColors.gold,
                activeTrackColor: AppColors.gold.withValues(alpha: 0.4),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 8),
              const Text('Save as template',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 12)),
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
          width: 72,
          height: 52,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: BorderSide(
                  color: AppColors.textSecondary.withValues(alpha: 0.2),
                  width: 0.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Icon(Icons.close, size: 18),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: hasItems ? AppColors.gold : AppColors.surface,
                foregroundColor:
                    hasItems ? AppColors.background : AppColors.textSecondary,
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
                          ? 'Log  ·  $_totalCalories kcal'
                          : 'Add items to log',
                      style: TextStyle(
                        fontWeight:
                            hasItems ? FontWeight.w600 : FontWeight.normal,
                        fontSize: 14,
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
      await widget.presenter.addFoodEntry(p.entry, MealSlot.meal);
    }
    if (_saveAsTemplate && _pendingEntries.isNotEmpty) {
      final template = FoodTemplate(
        id: FoodEntry.generateId(),
        name: '${DateTime.now().day}/${DateTime.now().month} meal',
        isMeal: _pendingEntries.length > 1,
        defaultSlot: MealSlot.meal,
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
      builder: (_) => _ManualEntrySheet(onAdd: _addEntry),
    );
  }

  Widget _sectionLabel(String label) => Text(
        label,
        style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w500),
      );
}

// ─── Cart Row ─────────────────────────────────────────────────────────────────

class _CartRow extends StatelessWidget {
  final _PendingEntry pending;
  final VoidCallback onRemove;
  const _CartRow({required this.pending, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              pending.entry.name,
              style:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${pending.entry.calories} kcal',
            style: const TextStyle(
                color: AppColors.gold,
                fontSize: 12,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child:
                  Icon(Icons.close, color: AppColors.textSecondary, size: 14),
            ),
          ),
        ],
      ),
    );
  }
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
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isMeal
                        ? Icons.restaurant_outlined
                        : Icons.set_meal_outlined,
                    color: AppColors.textSecondary,
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
                const Text(
                  '+ Add',
                  style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
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
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(14),
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
                              color: AppColors.textSecondary, fontSize: 11)),
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
                    label: const Text('Download AI model',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppColors.accent, size: 14),
              const SizedBox(width: 6),
              Text(
                '~$total kcal estimated',
                style: const TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w600,
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
                  if (item.protein != null)
                    _macroBadge('P', item.protein!.round(), AppColors.success),
                  if (item.carbs != null)
                    _macroBadge('C', item.carbs!.round(), AppColors.accent),
                  if (item.fat != null)
                    _macroBadge('F', item.fat!.round(), AppColors.gold),
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
              onPressed: _items.isEmpty ? null : () => widget.onConfirm(_items),
              child: Text(
                'Add to meal  ·  $total kcal',
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
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
                        Text('P ${protein.round()}g',
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
                              : AppColors.textSecondary.withValues(alpha: 0.2),
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
            const Text(
              'Custom food',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                icon: const Icon(Icons.close,
                    color: AppColors.textSecondary, size: 18),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ]),
          const SizedBox(height: 14),
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
              Text(_showMacros ? 'Hide macros' : 'Add macros (optional)',
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
              child: const Text('Add',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
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
            borderSide: const BorderSide(color: AppColors.accent, width: 1)),
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
