import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../models/ai_meal_estimate.dart';
import '../../models/food_db_entry.dart';
import '../../models/food_entry.dart';
import '../../models/food_template.dart';
import '../../models/meal_slot.dart';
import '../../presenters/nutrition_presenter.dart';

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
  late MealSlot _slot;
  final _aiCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  List<FoodDbEntry> _searchResults = [];
  final List<_PendingEntry> _pendingEntries = [];

  bool _saveAsTemplate = false;
  bool _isSearching = false;
  bool _isLogging = false;

  @override
  void initState() {
    super.initState();
    _slot = MealSlot.meal;
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _aiCtrl.dispose();
    _searchCtrl.dispose();
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

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildAiSection(),
            const SizedBox(height: 16),
            _buildSearchSection(),
            if (_pendingEntries.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildPendingList(),
            ],
            const SizedBox(height: 20),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Text('LOG MEAL',
            style: TextStyle(
                color: AppColors.gold,
                fontSize: 12,
                letterSpacing: 2.0,
                fontWeight: FontWeight.w600)),
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
    );
  }

  Widget _buildAiSection() {
    // Wrap in ListenableBuilder so the branch re-evaluates when isAiAvailable
    // changes (e.g., after init() completes post-startup).
    return ListenableBuilder(
      listenable: widget.presenter,
      builder: (_, __) {
        final available = widget.presenter.isAiAvailable;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AI QUICK-LOG',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    letterSpacing: 1.5)),
            const SizedBox(height: 8),
            if (!available)
              _AiUnavailableBanner(presenter: widget.presenter)
            else ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _aiCtrl,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 13),
                      decoration: _inputDecoration(
                        'Describe your meal...',
                        'e.g. rice, grilled fish, mixed veggies',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent.withValues(alpha: 0.2),
                        foregroundColor: AppColors.accent,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _estimate,
                      child: const Text('ESTIMATE',
                          style: TextStyle(fontSize: 11, letterSpacing: 1.0)),
                    ),
                  ),
                ],
              ),
              _buildAiStatus(),
            ],
          ],
        );
      },
    );
  }

  Widget _buildAiStatus() {
    if (widget.presenter.isAiEstimating) {
      return const Padding(
        padding: EdgeInsets.only(top: 10),
        child: Row(
          children: [
            SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.accent)),
            SizedBox(width: 10),
            Text('System analyzing meal composition...',
                style: TextStyle(color: AppColors.accent, fontSize: 12)),
          ],
        ),
      );
    }

    final error = widget.presenter.aiEstimateError;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppColors.danger, size: 14),
            const SizedBox(width: 8),
            Expanded(
              child: Text(error,
                  style: const TextStyle(
                      color: AppColors.danger, fontSize: 12)),
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
      return _AiResultCard(
        estimate: estimate,
        onConfirm: (items) {
          widget.presenter.confirmAiEstimate(items, _slot);
          Navigator.pop(context);
        },
        onDismiss: widget.presenter.clearEstimate,
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildSearchSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('SEARCH & ADD',
            style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                letterSpacing: 1.5)),
        const SizedBox(height: 8),
        TextField(
          controller: _searchCtrl,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
          decoration: _inputDecoration('Search food...', 'e.g. chicken breast'),
        ),
        if (_isSearching)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(
                color: AppColors.gold, backgroundColor: Colors.transparent),
          ),
        if (_searchResults.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _searchResults.length,
              itemBuilder: (_, i) => _SearchResultRow(
                entry: _searchResults[i],
                onAdd: (grams) {
                  final food = _searchResults[i].toFoodEntry(grams);
                  setState(() {
                    _pendingEntries.add(_PendingEntry(food));
                    _searchCtrl.clear();
                    _searchResults = [];
                  });
                },
              ),
            ),
          ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _showManualEntry,
          child: const Text('+ Add manually',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildPendingList() {
    final total = _pendingEntries.fold(0, (s, e) => s + e.entry.calories);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ITEMS ADDED — $total kcal total',
            style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                letterSpacing: 1.5)),
        const SizedBox(height: 8),
        ..._pendingEntries.map((p) => _PendingRow(
              pending: p,
              onRemove: () => setState(() => _pendingEntries.remove(p)),
            )),
        const SizedBox(height: 10),
        Row(
          children: [
            Checkbox(
              value: _saveAsTemplate,
              onChanged: (v) => setState(() => _saveAsTemplate = v ?? false),
              activeColor: AppColors.gold,
            ),
            const Text('Save as meal template',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ],
        ),
      ],
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 48,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: const BorderSide(
                    color: AppColors.textSecondary, width: 0.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: SizedBox(
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.background,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed:
                  _pendingEntries.isEmpty || _isLogging ? null : _logMeal,
              child: const Text('LOG MEAL',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _estimate() async {
    final desc = _aiCtrl.text.trim();
    if (desc.isEmpty) return;
    await widget.presenter.estimateMeal(desc);
  }

  Future<void> _logMeal() async {
    setState(() => _isLogging = true);
    for (final p in _pendingEntries) {
      await widget.presenter.addFoodEntry(p.entry, _slot);
    }
    if (_saveAsTemplate && _pendingEntries.isNotEmpty) {
      final template = FoodTemplate(
        id: FoodEntry.generateId(),
        name: '${_slot.label} ${DateTime.now().day}/${DateTime.now().month}',
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
        onAdd: (entry) =>
            setState(() => _pendingEntries.add(_PendingEntry(entry))),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, String hint) {
    return InputDecoration(
      hintText: hint,
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      hintStyle:
          TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.5)),
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.gold, width: 1)),
    );
  }
}

// ─── Supporting widgets ───────────────────────────────────────────────────────

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
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.auto_awesome,
                    color: AppColors.accent, size: 14),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'AI Meal Estimation',
                    style: TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
                  ),
                ),
                Text(
                  presenter.aiSizeLabel,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
              ]),
              const SizedBox(height: 4),
              const Text(
                'Describe a meal and get an instant calorie breakdown — runs fully on-device.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
              const SizedBox(height: 12),
              if (downloading) ...[
                Row(children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress / 100.0,
                        minHeight: 6,
                        backgroundColor: AppColors.surface,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.accent),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('$progress%',
                      style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ]),
              ] else
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      side:
                          const BorderSide(color: AppColors.accent, width: 0.8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('DOWNLOAD AI MODEL',
                        style: TextStyle(fontSize: 12, letterSpacing: 1.2)),
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
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppColors.accent, size: 14),
              const SizedBox(width: 6),
              Text(
                '~${widget.estimate.totalCalories} kcal estimated',
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
          const SizedBox(height: 8),
          ..._items.map((AiItemEstimate item) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('· ${item.name}: ${item.calories} kcal',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
              )),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.background,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => widget.onConfirm(_items),
              child: const Text('CONFIRM',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchResultRow extends StatefulWidget {
  final FoodDbEntry entry;
  final void Function(double grams) onAdd;
  const _SearchResultRow({required this.entry, required this.onAdd});

  @override
  State<_SearchResultRow> createState() => _SearchResultRowState();
}

class _SearchResultRowState extends State<_SearchResultRow> {
  double _grams = 100;

  @override
  Widget build(BuildContext context) {
    final cal = (widget.entry.caloriesPer100g * _grams / 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.entry.name,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 13)),
                Text('$cal kcal · ${_grams.toStringAsFixed(0)}g',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          SizedBox(
            width: 64,
            child: TextField(
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: '100g',
                hintStyle: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.5),
                    fontSize: 11),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none),
              ),
              onChanged: (v) {
                final g = double.tryParse(v);
                if (g != null && g > 0) setState(() => _grams = g);
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              icon:
                  const Icon(Icons.add_circle, color: AppColors.gold, size: 22),
              onPressed: () => widget.onAdd(_grams),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingEntry {
  final FoodEntry entry;
  _PendingEntry(this.entry);
}

class _PendingRow extends StatelessWidget {
  final _PendingEntry pending;
  final VoidCallback onRemove;
  const _PendingRow({required this.pending, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(pending.entry.name,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 13)),
          ),
          Text('${pending.entry.calories} kcal',
              style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              icon: const Icon(Icons.remove_circle_outline,
                  color: AppColors.danger, size: 18),
              onPressed: onRemove,
            ),
          ),
        ],
      ),
    );
  }
}

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
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
              decoration: _dec('Calories', 'kcal')),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => setState(() => _showMacros = !_showMacros),
            child: Text(
                _showMacros ? '▲ Hide macros' : '▼ Add macros (optional)',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
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
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.background,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _add,
              child: const Text('ADD',
                  style: TextStyle(fontWeight: FontWeight.bold)),
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
