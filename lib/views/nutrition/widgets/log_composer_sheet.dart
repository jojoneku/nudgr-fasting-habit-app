import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_colors.dart';
import '../../../models/food_entry.dart';
import '../../../models/food_template.dart';
import '../../../models/meal_slot.dart';
import '../../../presenters/nutrition_presenter.dart';
import '../../widgets/system/system.dart';
import '../food_photo_sheet.dart';

/// Opens the "Log a meal" composer bottom-sheet (Nudgr nutrition redesign).
///
/// Commits via the chat path ([NutritionPresenter.parseChat]) atomically —
/// type → analysing → committed — so the logged entry appears at the top of the
/// list once the sheet closes. Templates, manual add, and photo logging remain
/// reachable from here (superset of the old input bar). Photo/manual/template
/// commits also go through chat-visible paths.
Future<void> showLogComposerSheet(
  BuildContext context,
  NutritionPresenter presenter,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _LogComposerSheet(presenter: presenter),
  );
}

class _LogComposerSheet extends StatefulWidget {
  final NutritionPresenter presenter;
  const _LogComposerSheet({required this.presenter});

  @override
  State<_LogComposerSheet> createState() => _LogComposerSheetState();
}

class _LogComposerSheetState extends State<_LogComposerSheet> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  static final _qtyPrefixRe = RegExp(r'^\d');
  static final _leftWordRe = RegExp(r'\S+$');
  static final _rightWordRe = RegExp(r'^\S+');

  Timer? _suggestTimer;
  String? _suggestQuery;
  List<String> _suggestions = const [];

  bool _analyzing = false;
  bool _showEstimate = false;
  bool _committing = false; // guards double-tap on "Log it"

  // Inline rename of an estimate item: index of the row being edited (null =
  // none) and its editing controller/focus. _recomputingIndex is the row whose
  // nutrition is being re-resolved after a rename; _editedIndices marks rows
  // the user has renamed (shows an "edited" tag).
  int? _editingIndex;
  int? _recomputingIndex;
  final Set<int> _editedIndices = {};
  final _editCtrl = TextEditingController();
  final _editFocus = FocusNode();
  String? _error;
  // Each submitted message echoed as a chat bubble; accumulates so adding a
  // second item keeps the first bubble on screen (chat history, not a swap).
  final List<String> _draftTexts = [];
  bool _aiPromptShown = false;

  static const _quickChips = <_QuickChip>[
    _QuickChip(Icons.egg_outlined, '2 eggs & toast'),
    _QuickChip(Icons.coffee_outlined, 'Flat white'),
    _QuickChip(Icons.rice_bowl_outlined, 'Rice & chicken'),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onInputChanged);
    _focus.addListener(_onInputChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowAiPrompt());
  }

  @override
  void dispose() {
    _suggestTimer?.cancel();
    _ctrl.removeListener(_onInputChanged);
    _focus.removeListener(_onInputChanged);
    // Drop any un-logged estimate if the sheet closes without "Log it".
    widget.presenter.discardPendingChat();
    _ctrl.dispose();
    _focus.dispose();
    _editCtrl.dispose();
    _editFocus.dispose();
    super.dispose();
  }

  /// Enter inline-rename mode for the estimate item at [index].
  void _startEditingName(int index, String currentName) {
    setState(() {
      _editingIndex = index;
      _editCtrl.text = currentName;
      _editCtrl.selection =
          TextSelection(baseOffset: 0, extentOffset: currentName.length);
    });
    _editFocus.requestFocus();
  }

  /// Commit the inline rename: re-resolve the item's nutrition for the new
  /// name (with a per-row spinner), then mark it edited. Idempotent — a second
  /// call while already committing (e.g. onTapOutside + check tap) is a no-op.
  Future<void> _commitEditingName() async {
    final index = _editingIndex;
    if (index == null) return;
    final newName = _editCtrl.text.trim();
    setState(() => _editingIndex = null);
    if (newName.isEmpty) return;

    final entries = widget.presenter.pendingChatEntries;
    if (index < entries.length && entries[index].name == newName) return;

    setState(() => _recomputingIndex = index);
    await widget.presenter.recomputePendingChatEntry(index, newName);
    if (!mounted) return;
    setState(() {
      _recomputingIndex = null;
      _editedIndices.add(index);
    });
  }

  // The fasting "lock" is a now-only concept — past days can always be
  // backfilled (Plan 037). canLog drives every input affordance.
  bool get _locked =>
      widget.presenter.goals.ifSyncEnabled &&
      !widget.presenter.isEatingWindowOpen;
  bool get _canLog => widget.presenter.isSelectedDateToday ? !_locked : true;

  Future<void> _maybeShowAiPrompt() async {
    if (_aiPromptShown || !mounted) return;
    final should = await widget.presenter.shouldShowAiPrompt();
    if (!should || !mounted) return;
    _aiPromptShown = true;
    _focus.unfocus();
    await showDialog<void>(
      context: context,
      builder: (_) => _FirstRunAiPrompt(presenter: widget.presenter),
    );
  }

  void _onInputChanged() {
    if (!_focus.hasFocus) {
      _clearSuggestions();
      return;
    }
    final prefix = _caretLeftToken();
    if (prefix == null) {
      _clearSuggestions();
      return;
    }
    if (prefix == _suggestQuery) return;
    _suggestQuery = prefix;
    _suggestTimer?.cancel();
    _suggestTimer = Timer(const Duration(milliseconds: 120), () async {
      if (!mounted) return;
      final results = await widget.presenter.suggestFoodNames(prefix);
      if (!mounted || _suggestQuery != prefix) return;
      setState(() => _suggestions = results);
    });
  }

  void _clearSuggestions() {
    _suggestTimer?.cancel();
    if (_suggestQuery == null && _suggestions.isEmpty) return;
    _suggestQuery = null;
    if (mounted) setState(() => _suggestions = const []);
  }

  /// The whitespace-bounded token to the left of the caret — what the user is
  /// currently typing. Null if too short or a quantity like "100g".
  String? _caretLeftToken() {
    final text = _ctrl.text;
    final sel = _ctrl.selection;
    if (!sel.isValid || !sel.isCollapsed) return null;
    final caret = sel.baseOffset.clamp(0, text.length);
    final left = text.substring(0, caret);
    final match = _leftWordRe.firstMatch(left);
    if (match == null) return null;
    final token = match.group(0)!;
    if (token.length < 2) return null;
    if (_qtyPrefixRe.hasMatch(token)) return null;
    return token;
  }

  void _onSuggestionTap(String name) {
    final text = _ctrl.text;
    final caret = _ctrl.selection.baseOffset.clamp(0, text.length);
    final left = text.substring(0, caret);
    final right = text.substring(caret);
    final leftToken = _leftWordRe.firstMatch(left)?.group(0) ?? '';
    final rightToken = _rightWordRe.firstMatch(right)?.group(0) ?? '';
    final wordStart = caret - leftToken.length;
    final wordEnd = caret + rightToken.length;
    final replacement = '$name ';
    final newText =
        text.substring(0, wordStart) + replacement + text.substring(wordEnd);
    final newCaret = wordStart + replacement.length;
    _ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCaret),
    );
    _focus.requestFocus();
    _clearSuggestions();
  }

  Future<void> _send([String? override]) async {
    final text = (override ?? _ctrl.text).trim();
    if (text.isEmpty || _analyzing || !_canLog) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _analyzing = true;
      _error = null;
      _draftTexts.add(text);
    });
    _ctrl.clear();
    // Resolve WITHOUT logging — food yields an estimate to review; exercise is
    // logged directly (no estimate step).
    await widget.presenter.previewChat(text);
    if (!mounted) return;
    final err = widget.presenter.chatParseError;
    if (err != null) {
      // Put the text back so the user can fix it instead of retyping, and drop
      // its bubble (the item never made it into the estimate).
      _ctrl.text = text;
      setState(() {
        _analyzing = false;
        _error = err;
        if (_draftTexts.isNotEmpty) _draftTexts.removeLast();
      });
    } else if (widget.presenter.hasPendingChat) {
      setState(() {
        _analyzing = false;
        _showEstimate = true;
      });
    } else {
      Navigator.of(context).pop(); // exercise logged atomically
    }
  }

  /// Commit the reviewed estimate to the log, then close with an undo toast.
  Future<void> _logEstimate() async {
    if (_committing) return; // guard double-tap
    final messenger = ScaffoldMessenger.of(context);
    // Gate check before committing: if the eating window has closed while the
    // user lingered on the review step, keep the estimate on screen and explain
    // rather than silently dropping it.
    if (widget.presenter.isLoggingBlockedNow) {
      AppToast.error(
        messenger.context,
        "Outside your eating window — can't log this right now.",
      );
      return;
    }
    _committing = true;
    final kcal = widget.presenter.pendingChatTotalCalories;
    final id = await widget.presenter.commitPendingChat();
    if (!mounted) return;
    Navigator.of(context).pop();
    if (id != null) {
      AppToast.action(
        messenger.context,
        message: 'Logged · $kcal kcal',
        actionLabel: 'Undo',
        onAction: () => widget.presenter.removeChatMessage(id),
      );
    } else {
      // Residual race (window closed mid-commit): the estimate is gone, but at
      // least tell the user instead of a silent no-op.
      AppToast.error(
        messenger.context,
        "Couldn't log that — outside your eating window.",
      );
    }
  }

  /// Discard the estimate and return to the input to re-describe the meal.
  void _editEstimate() {
    widget.presenter.discardPendingChat();
    setState(() {
      _showEstimate = false;
      _analyzing = false;
      final last = _draftTexts.isNotEmpty ? _draftTexts.last : null;
      _draftTexts.clear();
      if (last != null) _ctrl.text = last;
    });
    _focus.requestFocus();
  }

  void _quick(String text) {
    _ctrl.text = text;
    _send(text);
  }

  void _openPhotoSheet() {
    Navigator.of(context).pop();
    showFoodPhotoSheet(context, widget.presenter);
  }

  void _showTemplates() {
    AppBottomSheet.show(
      context: context,
      title: 'Templates',
      useDraggableScrollableSheet: true,
      initialChildSize: 0.5,
      body: _TemplateBody(
        presenter: widget.presenter,
        onPick: (t) {
          widget.presenter.addMealFromTemplate(t, MealSlot.meal);
          if (mounted) Navigator.of(context).pop();
        },
      ),
    );
  }

  void _showManualAdd() {
    AppBottomSheet.show(
      context: context,
      title: 'Custom food',
      body: _ManualFoodBody(
        onAdd: (entry) {
          widget.presenter.addManualFoodEntry(entry);
          if (mounted) Navigator.of(context).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isToday = widget.presenter.isSelectedDateToday;
    final showSuggestions =
        _canLog && _suggestions.isNotEmpty && _focus.hasFocus;

    final hint = _showEstimate
        ? 'Add another item…'
        : !isToday
            ? 'Log food for ${DateFormat.MMMd().format(widget.presenter.selectedDate)}…'
            : _locked
                ? 'Fasting — logging paused'
                : 'Log food or exercise…';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Log a meal',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (_draftTexts.isNotEmpty && (_analyzing || _showEstimate))
              for (final draft in _draftTexts) _buildDraftBubble(cs, draft),
            if (_analyzing)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Analyzing your meal…',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, size: 16, color: cs.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(color: cs.error, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            if (_showEstimate && widget.presenter.hasPendingChat) ...[
              _buildEstimateCard(cs),
              const SizedBox(height: 12),
            ],
            if (!_analyzing && !_showEstimate) ...[
              // Quick-add chips + secondary entry points.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final chip in _quickChips)
                    _ComposerChip(
                      icon: chip.icon,
                      label: chip.label,
                      onTap: _canLog ? () => _quick(chip.label) : null,
                    ),
                  _ComposerChip(
                    icon: Icons.grid_view_outlined,
                    label: 'Templates',
                    onTap: _canLog ? _showTemplates : null,
                  ),
                  _ComposerChip(
                    icon: Icons.edit_outlined,
                    label: 'Manual',
                    onTap: _canLog ? _showManualAdd : null,
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (showSuggestions) _buildSuggestionStrip(cs),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.only(left: 14, right: 6),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _focus.hasFocus && _canLog
                            ? cs.primary
                            : cs.outlineVariant,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.photo_camera_outlined,
                              color: cs.onSurfaceVariant),
                          onPressed: _canLog ? _openPhotoSheet : null,
                          tooltip: 'Log from photo',
                          constraints:
                              const BoxConstraints(minWidth: 44, minHeight: 44),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _ctrl,
                            focusNode: _focus,
                            enabled: _canLog && !_analyzing,
                            autofocus: true,
                            style: TextStyle(color: cs.onSurface, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: hint,
                              hintStyle: TextStyle(
                                  color: cs.onSurfaceVariant, fontSize: 13),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 8),
                            ),
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _canLog && !_analyzing ? () => _send() : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _canLog && !_analyzing
                          ? cs.primary
                          : cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.arrow_upward,
                      color: _canLog && !_analyzing
                          ? cs.onPrimary
                          : cs.onSurfaceVariant,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The user's submission echoed as a right-aligned chat bubble while the
  /// estimate is being prepared/reviewed (mirrors the reference composer).
  Widget _buildDraftBubble(ColorScheme cs, String draft) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
          child: Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              border: Border.all(color: cs.outlineVariant),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(6),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              draft,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEstimateCard(ColorScheme cs) {
    final entries = widget.presenter.pendingChatEntries;
    final totalKcal = widget.presenter.pendingChatTotalCalories;
    final macros = widget.presenter.pendingChatMacros;
    final p = macros.protein;
    final c = macros.carbs;
    final f = macros.fat;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 14, color: cs.primary),
              const SizedBox(width: 7),
              Text(
                'ESTIMATE',
                style: TextStyle(
                  color: cs.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Text(
                'tap a name to edit',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 10.5),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // One card; each detected food is a row with inline name editing.
          for (final (i, e) in entries.indexed) _buildItemRow(cs, i, e),
          Divider(height: 1, color: cs.outlineVariant),
          const SizedBox(height: 11),
          Row(
            children: [
              _dot(cs.primary, '${p.round()}P'),
              const SizedBox(width: 11),
              _dot(context.appColors.gold, '${c.round()}C'),
              const SizedBox(width: 11),
              _dot(cs.error, '${f.round()}F'),
              const Spacer(),
              Text(
                '$totalKcal ',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text('kcal',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13)),
                    ),
                    onPressed: _logEstimate,
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Log it',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              SizedBox(
                height: 46,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.onSurfaceVariant,
                    side: BorderSide(color: cs.outlineVariant),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13)),
                  ),
                  onPressed: _editEstimate,
                  icon: const Icon(Icons.close, size: 15),
                  label: const Text('Discard', maxLines: 1),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// One detected food as a row inside the estimate card: name (tap to rename →
  /// recompute), macro subline, and calories (or a spinner while recomputing).
  Widget _buildItemRow(ColorScheme cs, int i, FoodEntry e) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _editingIndex == i
                    ? _buildNameEditor(cs)
                    : InkWell(
                        onTap: _recomputingIndex == i
                            ? null
                            : () => _startEditingName(i, e.name),
                        borderRadius: BorderRadius.circular(6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                e.name,
                                style: TextStyle(
                                  color: cs.onSurface,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Icon(Icons.edit_outlined,
                                size: 12, color: cs.onSurfaceVariant),
                            if (_editedIndices.contains(i)) ...[
                              const SizedBox(width: 6),
                              _editedTag(cs),
                            ],
                          ],
                        ),
                      ),
                const SizedBox(height: 2),
                Text(
                  _portionSub(e),
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (_recomputingIndex == i)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: cs.primary,
              ),
            )
          else
            Text(
              '${e.calories}',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }

  /// A small "edited" pill shown after an item the user has renamed.
  Widget _editedTag(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'edited',
        style: TextStyle(
          color: cs.primary,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  /// The inline name field shown in place of an estimate item's name while it
  /// is being renamed. Commits on submit, on the check tap, or on focus loss.
  Widget _buildNameEditor(ColorScheme cs) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _editCtrl,
            focusNode: _editFocus,
            autofocus: true,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _commitEditingName(),
            onTapOutside: (_) => _commitEditingName(),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              border: UnderlineInputBorder(
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: cs.primary, width: 1.5),
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: _commitEditingName,
          icon: Icon(Icons.check, size: 18, color: cs.primary),
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          tooltip: 'Done',
        ),
      ],
    );
  }

  /// Sub-line under an estimate item: portion (grams) then macros, e.g.
  /// "150g · P31 · C0 · F4". Grams omitted when unknown.
  String _portionSub(FoodEntry e) {
    final macro = _macroSub(e.protein, e.carbs, e.fat);
    final hasGrams = e.grams != null && e.grams! > 0;
    if (!hasGrams) return macro;
    final grams = '${e.grams!.round()}g';
    return macro.isEmpty ? grams : '$grams · $macro';
  }

  String _macroSub(double? p, double? c, double? f) {
    final parts = <String>[];
    if (p != null) parts.add('P${p.round()}');
    if (c != null) parts.add('C${c.round()}');
    if (f != null) parts.add('F${f.round()}');
    return parts.join(' · ');
  }

  Widget _dot(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );

  Widget _buildSuggestionStrip(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          itemCount: _suggestions.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            final name = _suggestions[i];
            return InkWell(
              onTap: () => _onSuggestionTap(name),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  name,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _QuickChip {
  final IconData icon;
  final String label;
  const _QuickChip(this.icon, this.label);
}

class _ComposerChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _ComposerChip({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          constraints: const BoxConstraints(minHeight: 34),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: enabled ? context.appColors.gold : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: enabled ? cs.onSurface : cs.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── First-run AI prompt ────────────────────────────────────────────────────

/// Plan 027 §3.2 — first-run modal. Shown when the user opens the composer but
/// neither cloud (signed in + toggle on) nor on-device Qwen is available, and
/// the user hasn't skipped within the cool-down window.
class _FirstRunAiPrompt extends StatefulWidget {
  final NutritionPresenter presenter;
  const _FirstRunAiPrompt({required this.presenter});

  @override
  State<_FirstRunAiPrompt> createState() => _FirstRunAiPromptState();
}

class _FirstRunAiPromptState extends State<_FirstRunAiPrompt> {
  bool _downloading = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Set up smart logging'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Logging works best with AI to read your meal descriptions.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          const _AiOptionRow(
            icon: Icons.phone_android_outlined,
            title: 'On-device AI',
            subtitle: '~586 MB · works offline · private',
          ),
          const SizedBox(height: 9),
          const _AiOptionRow(
            icon: Icons.cloud_outlined,
            title: 'Cloud AI',
            subtitle: 'Sign in via Settings for higher-quality estimates',
          ),
          const SizedBox(height: 12),
          Text(
            'Without AI, logging falls back to keyword matching — '
            'lower accuracy for out-of-database foods.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _downloading
              ? null
              : () async {
                  await widget.presenter.skipAiPrompt();
                  if (context.mounted) Navigator.pop(context);
                },
          child: const Text('Skip for now'),
        ),
        FilledButton.icon(
          onPressed: _downloading ? null : _onDownload,
          icon: _downloading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_outlined, size: 18),
          label: const Text('Download AI'),
        ),
      ],
    );
  }

  Future<void> _onDownload() async {
    setState(() => _downloading = true);
    try {
      await widget.presenter.downloadAiModel();
      await widget.presenter.resetAiPromptCooldown();
    } catch (e) {
      debugPrint('First-run AI download failed: $e');
    }
    if (mounted) Navigator.pop(context);
  }
}

class _AiOptionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _AiOptionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Template body ──────────────────────────────────────────────────────────

class _TemplateBody extends StatelessWidget {
  final NutritionPresenter presenter;
  final ValueChanged<FoodTemplate> onPick;
  const _TemplateBody({required this.presenter, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final templates = presenter.savedTemplates;
    final recents = presenter.recentFoods.take(5).toList();

    if (templates.isEmpty && recents.isEmpty) {
      return const AppEmptyState(
        icon: Icons.bookmark_border,
        title: 'No templates yet',
        body: 'Save a meal from the Library.',
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (recents.isNotEmpty) ...[
          _sectionLabel('Recent', context),
          ..._templateList(context, recents),
        ],
        if (templates.isNotEmpty) ...[
          _sectionLabel('Saved Meals', context),
          ..._templateList(context, templates),
        ],
        SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
      ],
    );
  }

  List<Widget> _templateList(BuildContext context, List<FoodTemplate> items) {
    return items.map((t) {
      final totalCal = t.entries.fold<int>(0, (sum, e) => sum + e.calories);
      return AppListTile(
        leading: t.isPinned
            ? Icon(Icons.push_pin,
                color: Theme.of(context).colorScheme.primary, size: 14)
            : null,
        title: Text(t.name),
        trailing: Text(
          totalCal > 0 ? '$totalCal kcal' : '',
          style: TextStyle(color: context.appColors.gold, fontSize: 12),
        ),
        onTap: () {
          Navigator.pop(context);
          onPick(t);
        },
      );
    }).toList();
  }

  Widget _sectionLabel(String label, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ─── Manual food body ───────────────────────────────────────────────────────

class _ManualFoodBody extends StatefulWidget {
  final void Function(FoodEntry) onAdd;
  const _ManualFoodBody({required this.onAdd});

  @override
  State<_ManualFoodBody> createState() => _ManualFoodBodyState();
}

class _ManualFoodBodyState extends State<_ManualFoodBody> {
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

  void _add() {
    final name = _nameCtrl.text.trim();
    final cal = int.tryParse(_calCtrl.text.trim());
    if (name.isEmpty || cal == null || cal <= 0) return;
    Navigator.pop(context);
    widget.onAdd(FoodEntry(
      id: FoodEntry.generateId(),
      name: name,
      calories: cal,
      protein: double.tryParse(_pCtrl.text.trim()),
      carbs: double.tryParse(_cCtrl.text.trim()),
      fat: double.tryParse(_fCtrl.text.trim()),
      loggedAt: DateTime.now(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          controller: _nameCtrl,
          autofocus: true,
          label: 'Food name',
          hint: 'e.g. Chicken breast 150g',
        ),
        const SizedBox(height: 10),
        AppTextField(
          controller: _calCtrl,
          keyboardType: TextInputType.number,
          label: 'Calories (kcal)',
          hint: 'e.g. 320',
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => setState(() => _showMacros = !_showMacros),
          child: Builder(builder: (context) {
            final color = Theme.of(context).colorScheme.onSurfaceVariant;
            return Row(children: [
              Icon(
                _showMacros
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                color: color,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                _showMacros ? 'Hide macros' : 'Add macros (optional)',
                style: TextStyle(color: color, fontSize: 12),
              ),
            ]);
          }),
        ),
        if (_showMacros) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: AppTextField(
                    controller: _pCtrl,
                    keyboardType: TextInputType.number,
                    label: 'Protein',
                    hint: 'g')),
            const SizedBox(width: 8),
            Expanded(
                child: AppTextField(
                    controller: _cCtrl,
                    keyboardType: TextInputType.number,
                    label: 'Carbs',
                    hint: 'g')),
            const SizedBox(width: 8),
            Expanded(
                child: AppTextField(
                    controller: _fCtrl,
                    keyboardType: TextInputType.number,
                    label: 'Fat',
                    hint: 'g')),
          ]),
        ],
        const SizedBox(height: 16),
        AppPrimaryButton(label: 'Add', onPressed: _add),
        const SizedBox(height: 8),
      ],
    );
  }
}
