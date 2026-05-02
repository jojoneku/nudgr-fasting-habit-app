import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app_colors.dart';
import '../../models/ai_meal_estimate.dart';
import '../../models/food_db_entry.dart';
import '../../models/estimation_source.dart';
import '../../models/food_entry.dart';
import '../../models/food_parse_result.dart';
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

  // Incremented on every search to discard stale results from earlier queries.
  int _searchGeneration = 0;

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
      widget.presenter.clearParseResult();
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    // Capture generation before the async gap so stale completions are ignored.
    final generation = ++_searchGeneration;
    widget.presenter.clearParseResult();
    setState(() => _isSearching = true);

    final results = await widget.presenter.foodDb.search(q);

    if (mounted && _searchGeneration == generation) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
      // Auto-analyze when DB has no matches.
      if (results.isEmpty) {
        widget.presenter.parseMeal(q);
      }
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

    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
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
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: KeyedSubtree(
                  key: ValueKey(_contentPhase),
                  child: _buildContent(),
                ),
              ),
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
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        const SizedBox(height: 10),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: cs.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
      child: Row(
        children: [
          Text(
            'Add Food',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              tooltip: 'Close',
              icon: Icon(Icons.close, color: cs.onSurfaceVariant, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: _inputCtrl,
        focusNode: _inputFocus,
        autofocus: true,
        style: TextStyle(color: cs.onSurface, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search or describe a meal...',
          hintStyle: TextStyle(
            color: cs.onSurfaceVariant.withValues(alpha: 0.6),
            fontSize: 13,
          ),
          prefixIcon: Icon(Icons.search, color: cs.onSurfaceVariant, size: 18),
          suffixIcon: _inputCtrl.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close, color: cs.onSurfaceVariant, size: 16),
                  onPressed: () {
                    _inputCtrl.clear();
                    setState(() => _searchResults = []);
                    widget.presenter.clearEstimate();
                  },
                )
              : null,
          filled: true,
          fillColor: cs.surfaceContainerHighest,
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

  String get _contentPhase {
    final hasInput = _inputCtrl.text.trim().isNotEmpty;
    if (!hasInput) return 'quick';
    if (_searchResults.isNotEmpty) return 'results';
    if (_isSearching) return 'searching';
    final p = widget.presenter;
    if (p.isParsing || p.isAiEstimating) return 'analyzing';
    return 'no-results';
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

    if (_isSearching) return const SizedBox.shrink();

    final p = widget.presenter;
    if (p.isParsing || p.isAiEstimating) return _buildAnalyzingPlaceholder();

    return _buildNoResults();
  }

  Widget _buildAnalyzingPlaceholder() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              widget.presenter.isAiEstimating
                  ? 'Estimating with AI…'
                  : 'Analyzing…',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickSection() {
    final recents = widget.presenter.recentFoods;
    final templates = widget.presenter.savedTemplates;

    if (recents.isEmpty && templates.isEmpty) {
      final cs0 = Theme.of(context).colorScheme;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search,
                  color: cs0.onSurfaceVariant.withValues(alpha: 0.3),
                  size: 32),
              const SizedBox(height: 8),
              Text(
                'Search the food database or describe your meal',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: cs0.onSurfaceVariant, fontSize: 13, height: 1.5),
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
                  child: Builder(builder: (ctx) {
                    final cs = Theme.of(ctx).colorScheme;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(t.name,
                              style: TextStyle(
                                  color: cs.onSurface, fontSize: 12)),
                          const SizedBox(width: 6),
                          Text('$cal',
                              style: const TextStyle(
                                  color: AppColors.gold,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    );
                  }),
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
            child: Builder(builder: (ctx) {
              final color = Theme.of(ctx)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.5);
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.edit_outlined, color: color, size: 14),
                  const SizedBox(width: 6),
                  Text('Add manually',
                      style: TextStyle(color: color, fontSize: 12)),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResults() {
    final aiAvailable = widget.presenter.isAiAvailable;
    final hasParseError = widget.presenter.parseError != null;
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Icon(Icons.search_off,
              color: cs.onSurfaceVariant.withValues(alpha: 0.3), size: 32),
          const SizedBox(height: 8),
          Text(
            hasParseError
                ? 'No matches found for "${_inputCtrl.text.trim()}"'
                : 'No results for "${_inputCtrl.text.trim()}"',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          if (hasParseError) ...[
            const SizedBox(height: 4),
            Text(
              'Try AI estimation or enter nutrients manually.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 20),
          if (aiAvailable) ...[
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent.withValues(alpha: 0.12),
                  foregroundColor: AppColors.accent,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: widget.presenter.isAiEstimating
                    ? null
                    : () =>
                        widget.presenter.estimateMeal(_inputCtrl.text.trim()),
                icon: const Icon(Icons.auto_awesome, size: 15),
                label: const Text('Estimate with AI',
                    style: TextStyle(fontSize: 13)),
              ),
            ),
            const SizedBox(height: 8),
          ] else ...[
            _AiUnavailableBanner(presenter: widget.presenter),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.onSurfaceVariant,
                side: BorderSide(color: cs.outlineVariant),
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
    final parseError = widget.presenter.parseError;
    if (parseError != null) {
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
              child: Text(parseError,
                  style:
                      const TextStyle(color: AppColors.danger, fontSize: 12)),
            ),
            GestureDetector(
              onTap: widget.presenter.clearParseResult,
              child: Icon(Icons.close,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 16),
            ),
          ],
        ),
      );
    }

    final parseResult = widget.presenter.lastParseResult;
    if (parseResult != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: _ParseResultCard(
          result: parseResult,
          dbMatches: widget.presenter.parsedDbMatches,
          onConfirm: (entries) {
            for (final e in entries) {
              _addEntry(e);
            }
            widget.presenter.clearParseResult();
            _inputCtrl.clear();
            setState(() => _searchResults = []);
          },
          onDismiss: widget.presenter.clearParseResult,
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
              child: Icon(Icons.close,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 16),
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._pendingEntries.map((p) => _CartRow(
                pending: p,
                onRemove: () => _removeEntry(p),
              )),
          Divider(height: 16, color: cs.outlineVariant),
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
              Text('Save as template',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    final hasItems = _pendingEntries.isNotEmpty;
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 72,
          height: 52,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: cs.onSurfaceVariant,
              side: BorderSide(color: cs.outlineVariant, width: 0.5),
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
                backgroundColor:
                    hasItems ? AppColors.gold : cs.surfaceContainerHigh,
                foregroundColor:
                    hasItems ? Colors.black87 : cs.onSurfaceVariant,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: !hasItems || _isLogging ? null : _promptAndLog,
              child: _isLogging
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black87))
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

  Future<void> _promptAndLog() async {
    if (_saveAsTemplate && _pendingEntries.isNotEmpty) {
      final defaultName = _pendingEntries.length == 1
          ? _pendingEntries.first.entry.name
          : '${DateTime.now().day}/${DateTime.now().month} meal';
      final ctrl = TextEditingController(text: defaultName);
      final cs = Theme.of(context).colorScheme;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Name this template',
              style: TextStyle(color: cs.onSurface, fontSize: 16)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            style: TextStyle(color: cs.onSurface, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Template name',
              hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              filled: true,
              fillColor: cs.surfaceContainerHighest,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 1)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style: TextStyle(color: cs.onSurfaceVariant)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save',
                  style: TextStyle(color: AppColors.primary)),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await _logMeal(templateName: ctrl.text.trim());
    } else {
      await _logMeal();
    }
  }

  Future<void> _logMeal({String? templateName}) async {
    setState(() => _isLogging = true);
    HapticFeedback.mediumImpact();
    try {
      for (final p in _pendingEntries) {
        await widget.presenter.addFoodEntry(p.entry, MealSlot.meal);
      }
      if (_saveAsTemplate && _pendingEntries.isNotEmpty) {
        final name = (templateName != null && templateName.isNotEmpty)
            ? templateName
            : (_pendingEntries.length == 1
                ? _pendingEntries.first.entry.name
                : '${DateTime.now().day}/${DateTime.now().month} meal');
        final template = FoodTemplate(
          id: FoodEntry.generateId(),
          name: name,
          isMeal: _pendingEntries.length > 1,
          defaultSlot: MealSlot.meal,
          entries: _pendingEntries.map((p) => p.entry).toList(),
        );
        await widget.presenter.saveFoodTemplate(template);
      }
    } finally {
      // Always dismiss — if the sheet stays open with _isLogging=true the
      // transparent modal barrier blocks the entire screen behind it.
      if (mounted) Navigator.pop(context);
    }
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
        style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              pending.entry.name,
              style: TextStyle(color: cs.onSurface, fontSize: 13),
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
          IconButton(
            tooltip: 'Remove',
            icon: Icon(Icons.close, color: cs.onSurfaceVariant, size: 14),
            onPressed: onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
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

    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
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
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isMeal
                        ? Icons.restaurant_outlined
                        : Icons.set_meal_outlined,
                    color: cs.onSurfaceVariant,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(template.name,
                          style: TextStyle(
                              color: cs.onSurface,
                              fontSize: 13,
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text(
                        isMeal
                            ? '${template.entries.length} items · $cal kcal'
                            : '$cal kcal',
                        style: TextStyle(
                            color: cs.onSurfaceVariant, fontSize: 11),
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

// ─── Parse Result Card ────────────────────────────────────────────────────────

class _ParseResultCard extends StatefulWidget {
  final FoodParseResult result;
  final List<FoodDbEntry?> dbMatches;
  final void Function(List<FoodEntry>) onConfirm;
  final VoidCallback onDismiss;

  const _ParseResultCard({
    required this.result,
    required this.dbMatches,
    required this.onConfirm,
    required this.onDismiss,
  });

  @override
  State<_ParseResultCard> createState() => _ParseResultCardState();
}

class _ParseResultCardState extends State<_ParseResultCard> {
  late List<bool> _selected;

  @override
  void initState() {
    super.initState();
    _selected = List.filled(widget.result.items.length, true);
  }

  List<FoodEntry> _buildEntries() {
    final entries = <FoodEntry>[];
    for (int i = 0; i < widget.result.items.length; i++) {
      if (!_selected[i]) continue;
      final item = widget.result.items[i];
      final db = i < widget.dbMatches.length ? widget.dbMatches[i] : null;
      if (db != null) {
        entries.add(db.toFoodEntry(item.grams));
      } else {
        // No DB match — create a rough entry from grams alone
        entries.add(FoodEntry(
          id: FoodEntry.generateId(),
          name: item.name,
          calories: (item.grams * 2).round(),
          grams: item.grams,
          estimationSource: EstimationSource.keywordDensity,
          loggedAt: DateTime.now(),
        ));
      }
    }
    return entries;
  }

  int get _totalCalories => _buildEntries().fold(0, (s, e) => s + e.calories);

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selected.where((v) => v).length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.manage_search_outlined,
                  color: AppColors.primary, size: 14),
              const SizedBox(width: 6),
              Text(
                widget.result.usedModel
                    ? 'AI parsed ${widget.result.items.length} items'
                    : '${widget.result.items.length} items matched',
                style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Dismiss',
                icon: Icon(Icons.close,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 16),
                onPressed: widget.onDismiss,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...widget.result.items.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            final db = i < widget.dbMatches.length ? widget.dbMatches[i] : null;
            final cal = db != null
                ? (db.caloriesPer100g * item.grams / 100).round()
                : (item.grams * 2).round();
            final hasDb = db != null;

            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _selected[i],
                      onChanged: (v) =>
                          setState(() => _selected[i] = v ?? false),
                      activeColor: AppColors.primary,
                      side: BorderSide(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.4)),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          db?.name ?? item.name,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${item.grams.round()}g${item.isEstimated ? ' ~est' : ''}',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${hasDb ? '' : '~'}$cal kcal',
                    style: TextStyle(
                        color: hasDb
                            ? AppColors.gold
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: selectedCount == 0
                  ? null
                  : () => widget.onConfirm(_buildEntries()),
              child: Text(
                'Add $selectedCount item${selectedCount == 1 ? '' : 's'}  ·  $_totalCalories kcal',
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ),
        ],
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
        final cs = Theme.of(context).colorScheme;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('On-Device AI',
                          style: TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                      Text('Fully private — no internet needed',
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 11)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(presenter.aiSizeLabel,
                      style: TextStyle(
                          color: cs.onSurfaceVariant, fontSize: 10)),
                ),
              ]),
              const SizedBox(height: 14),
              if (downloading) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress / 100.0,
                    minHeight: 6,
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHigh,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(AppColors.accent),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Downloading model...',
                        style: TextStyle(
                            color: cs.onSurfaceVariant, fontSize: 11)),
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
              IconButton(
                tooltip: 'Dismiss',
                icon: Icon(Icons.close,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 16),
                onPressed: widget.onDismiss,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
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
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 12)),
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
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        color: AppColors.danger, size: 14),
                    onPressed: () => setState(() => _items.removeAt(i)),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 44, minHeight: 44),
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
                foregroundColor: Colors.black87,
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

  void _selectGrams(double g) {
    setState(() {
      _grams = g;
      _ctrl.text = g.round().toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cal = (widget.entry.caloriesPer100g * _grams / 100).round();
    final protein = widget.entry.proteinPer100g != null
        ? (widget.entry.proteinPer100g! * _grams / 100)
        : null;

    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
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
                        style: TextStyle(
                            color: cs.onSurface,
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
                    ]),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Grams input — standalone pill
                  Container(
                    width: 58,
                    height: 34,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: TextField(
                      controller: _ctrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurface, fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        border: InputBorder.none,
                        suffix: Text('g',
                            style: TextStyle(
                                color: cs.onSurfaceVariant, fontSize: 10)),
                      ),
                      onChanged: (v) {
                        final g = double.tryParse(v);
                        if (g != null && g > 0) setState(() => _grams = g);
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Add button — separate
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: Material(
                      color: AppColors.gold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () =>
                            widget.onAdd(widget.entry.toFoodEntry(_grams)),
                        child: const Icon(Icons.add,
                            color: AppColors.gold, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Compact pill presets
          Wrap(
            spacing: 6,
            children: _servingSizes.map((g) {
              final selected = _grams == g;
              return GestureDetector(
                onTap: () => _selectGrams(g),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.gold.withValues(alpha: 0.15)
                        : cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected
                          ? AppColors.gold
                          : cs.outlineVariant,
                      width: selected ? 1 : 0.5,
                    ),
                  ),
                  child: Text('${g.round()}g',
                      style: TextStyle(
                          color: selected
                              ? AppColors.gold
                              : cs.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.normal)),
                ),
              );
            }).toList(),
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
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(
              'Custom food',
              style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                icon: Icon(Icons.close, color: cs.onSurfaceVariant, size: 18),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          TextField(
              controller: _nameCtrl,
              autofocus: true,
              style: TextStyle(color: cs.onSurface),
              decoration: _dec('Food name', 'e.g. Chicken breast 150g', cs)),
          const SizedBox(height: 10),
          TextField(
              controller: _calCtrl,
              keyboardType: TextInputType.number,
              style: TextStyle(color: cs.onSurface),
              decoration: _dec('Calories (kcal)', 'e.g. 320', cs)),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => setState(() => _showMacros = !_showMacros),
            child: Row(children: [
              Icon(
                  _showMacros
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: cs.onSurfaceVariant,
                  size: 16),
              const SizedBox(width: 4),
              Text(_showMacros ? 'Hide macros' : 'Add macros (optional)',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ]),
          ),
          if (_showMacros) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _pCtrl,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: cs.onSurface, fontSize: 12),
                      decoration: _dec('Protein', 'g', cs))),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: _cCtrl,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: cs.onSurface, fontSize: 12),
                      decoration: _dec('Carbs', 'g', cs))),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: _fCtrl,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: cs.onSurface, fontSize: 12),
                      decoration: _dec('Fat', 'g', cs))),
            ]),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black87,
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

  InputDecoration _dec(String label, String hint, ColorScheme cs) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: cs.onSurfaceVariant),
        hintStyle: TextStyle(
            color: cs.onSurfaceVariant.withValues(alpha: 0.5), fontSize: 11),
        filled: true,
        fillColor: cs.surfaceContainerHighest,
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
