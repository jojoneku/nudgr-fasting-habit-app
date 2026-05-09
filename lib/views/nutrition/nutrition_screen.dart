import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app_colors.dart';
import '../../models/chat_message.dart';
import '../../models/estimation_source.dart';
import '../../models/food_db_entry.dart';
import '../../models/food_entry.dart';
import '../../models/food_template.dart';
import '../../models/meal_slot.dart';
import '../../presenters/ai_coach_presenter.dart';
import '../../presenters/nutrition_presenter.dart';
import 'barcode_scanner_sheet.dart';
import 'food_library_screen.dart';
import 'nutrition_history_screen.dart';
import 'nutrition_settings_sheet.dart';
import '../widgets/system/system.dart';

// ─── Screen ───────────────────────────────────────────────────────────────────

class NutritionScreen extends StatelessWidget {
  final NutritionPresenter presenter;
  final AiCoachPresenter? aiCoachPresenter;
  const NutritionScreen({
    super.key,
    required this.presenter,
    this.aiCoachPresenter,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) => _NutritionBody(
        presenter: presenter,
        aiCoachPresenter: aiCoachPresenter,
      ),
    );
  }
}

class _NutritionBody extends StatelessWidget {
  final NutritionPresenter presenter;
  final AiCoachPresenter? aiCoachPresenter;
  const _NutritionBody({
    required this.presenter,
    this.aiCoachPresenter,
  });

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: canPop ? 0 : 20,
        leading: canPop
            ? IconButton(
                icon: Icon(Icons.arrow_back_ios_new,
                    color: cs.onSurfaceVariant, size: 18),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: Text(
          'Nutrition',
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.history_outlined,
                color: cs.onSurfaceVariant, size: 22),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => NutritionHistoryScreen(presenter: presenter)),
            ),
            tooltip: 'History',
          ),
          IconButton(
            icon: Icon(Icons.menu_book_outlined,
                color: cs.onSurfaceVariant, size: 22),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => FoodLibraryScreen(presenter: presenter)),
            ),
            tooltip: 'Library',
          ),
          IconButton(
            icon:
                Icon(Icons.tune_outlined, color: cs.onSurfaceVariant, size: 22),
            onPressed: () => showNutritionSettingsSheet(
              context,
              presenter,
              aiCoachPresenter: aiCoachPresenter,
            ),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            _WeekStripRow(presenter: presenter),
            _StatSection(presenter: presenter),
            Expanded(child: _ChatFeed(presenter: presenter)),
            _SmartSearchBanner(presenter: presenter),
            _ChatInputBar(presenter: presenter),
          ],
        ),
      ),
    );
  }
}

// ─── Week Strip ───────────────────────────────────────────────────────────────

class _WeekStripRow extends StatelessWidget {
  final NutritionPresenter presenter;
  const _WeekStripRow({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: AppDayChipRow(
        selectedDate: presenter.selectedDate,
        weekStart: monday,
        onSelected: (day) {
          if (!day.isAfter(today)) presenter.setSelectedDate(day);
        },
      ),
    );
  }
}

// ─── Stat Section ─────────────────────────────────────────────────────────────

void _showNutritionDetailSheet(
    BuildContext context, NutritionPresenter presenter) {
  AppBottomSheet.show(
    context: context,
    title: 'Breakdown',
    body: _NutritionDetailBody(presenter: presenter),
  );
}

class _StatSection extends StatelessWidget {
  final NutritionPresenter presenter;
  const _StatSection({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final p = presenter;
    final cs = Theme.of(context).colorScheme;
    final burned = p.selectedDateCaloriesBurned;
    final barColor = p.isOverGoal ? cs.error : cs.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        onTap: () => _showNutritionDetailSheet(context, p),
        child: Row(
          children: [
            // ── Calories side (60%) ─────────────────────────────────────────
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CALORIES',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  AppLinearProgress(
                    value: p.netCalorieProgress,
                    color: barColor,
                    height: 3,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _StatCell(
                        value: '${p.todayCalories}',
                        label: 'Eaten',
                        color: cs.onSurface,
                      ),
                      const _ColDivider(),
                      _StatCell(
                        value: '${p.remainingCalories}',
                        label: 'Left',
                        color: cs.onSurface,
                      ),
                      const _ColDivider(),
                      _StatCell(
                        value: burned > 0 ? '$burned' : '—',
                        label: 'Burned',
                        color: cs.onSurface,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // ── Divider ────────────────────────────────────────────────────
            Container(
              width: 1,
              height: 56,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              color: cs.outlineVariant,
            ),
            // ── Macros side (40%) ──────────────────────────────────────────
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MACROS',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _StatCell(
                        value: '${p.todayProtein.round()}g',
                        label: 'Protein',
                        color: cs.onSurface,
                        barColor: cs.primary,
                        progress: p.proteinProgress,
                      ),
                      const _ColDivider(),
                      _StatCell(
                        value: '${p.todayCarbs.round()}g',
                        label: 'Carbs',
                        color: cs.onSurface,
                        barColor: context.appColors.gold,
                        progress: p.carbsProgress,
                      ),
                      const _ColDivider(),
                      _StatCell(
                        value: '${p.todayFat.round()}g',
                        label: 'Fat',
                        color: cs.onSurface,
                        barColor: cs.error,
                        progress: p.fatProgress,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColDivider extends StatelessWidget {
  const _ColDivider();
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 36,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: Theme.of(context).colorScheme.outlineVariant,
      );
}

class _StatCell extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final Color? barColor;
  final double? progress;
  const _StatCell({
    required this.value,
    required this.label,
    required this.color,
    this.barColor,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (progress != null) ...[
            AppLinearProgress(
              value: progress!,
              color: barColor ?? color,
              height: 3,
            ),
            const SizedBox(height: 8),
          ],
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Nutrition Detail Body ────────────────────────────────────────────────────

class _NutritionDetailBody extends StatelessWidget {
  final NutritionPresenter presenter;
  const _NutritionDetailBody({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final p = presenter;
    final burned = p.selectedDateCaloriesBurned;
    final calGoal = p.effectiveGoal;
    final remaining = p.remainingCalories;
    final cs = Theme.of(context).colorScheme;
    final barColor = p.isOverGoal ? cs.error : cs.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailRow(
          label: 'Calories',
          value: p.todayCalories,
          goal: calGoal,
          remaining: remaining.clamp(0, calGoal),
          unit: 'kcal',
          color: barColor,
          extra: burned > 0 ? '🔥 $burned kcal burned' : null,
        ),
        const SizedBox(height: 14),
        Divider(color: cs.outlineVariant, height: 1),
        const SizedBox(height: 14),
        if (p.proteinGoal != null)
          _DetailRow(
            label: 'Protein',
            value: p.todayProtein.round(),
            goal: p.proteinGoal!,
            remaining: (p.proteinGoal! - p.todayProtein.round())
                .clamp(0, p.proteinGoal!),
            unit: 'g',
            color: cs.primary,
          ),
        if (p.proteinGoal != null) const SizedBox(height: 10),
        if (p.carbsGoal != null)
          _DetailRow(
            label: 'Carbs',
            value: p.todayCarbs.round(),
            goal: p.carbsGoal!,
            remaining:
                (p.carbsGoal! - p.todayCarbs.round()).clamp(0, p.carbsGoal!),
            unit: 'g',
            color: context.appColors.gold,
          ),
        if (p.carbsGoal != null) const SizedBox(height: 10),
        if (p.fatGoal != null)
          _DetailRow(
            label: 'Fat',
            value: p.todayFat.round(),
            goal: p.fatGoal!,
            remaining: (p.fatGoal! - p.todayFat.round()).clamp(0, p.fatGoal!),
            unit: 'g',
            color: cs.error,
          ),
        if (p.proteinGoal == null && p.carbsGoal == null && p.fatGoal == null)
          Text(
            'No macro targets set — configure them in Settings.',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final int value;
  final int goal;
  final int remaining;
  final String unit;
  final Color color;
  final String? extra;

  const _DetailRow({
    required this.label,
    required this.value,
    required this.goal,
    required this.remaining,
    required this.unit,
    required this.color,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    final progress = goal > 0 ? (value / goal).clamp(0.0, 1.0) : 0.0;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              '$value',
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
            Text(
              ' / $goal $unit',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
                height: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AppLinearProgress(value: progress, color: color, height: 8),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              '$remaining $unit remaining',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
            if (extra != null) ...[
              const Spacer(),
              Text(
                extra!,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

// ─── Chat Feed ────────────────────────────────────────────────────────────────

class _ChatFeed extends StatefulWidget {
  final NutritionPresenter presenter;
  const _ChatFeed({required this.presenter});

  @override
  State<_ChatFeed> createState() => _ChatFeedState();
}

class _ChatFeedState extends State<_ChatFeed> {
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(_ChatFeed old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.presenter.chatMessages;
    final isParsing = widget.presenter.isChatParsing;
    final error = widget.presenter.chatParseError;

    if (messages.isEmpty && !isParsing) {
      return _EmptyChatState(isToday: widget.presenter.isSelectedDateToday);
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemCount:
          messages.length + (isParsing ? 1 : 0) + (error != null ? 1 : 0),
      itemBuilder: (context, index) {
        if (error != null && index == messages.length) {
          return _ErrorBubble(error: error);
        }
        if (isParsing && index == messages.length + (error != null ? 1 : 0)) {
          return const _ThinkingBubble();
        }
        final msg = messages[index];
        return _ChatMessageCard(
          message: msg,
          presenter: widget.presenter,
          key: ValueKey(msg.id),
        );
      },
    );
  }
}

class _EmptyChatState extends StatelessWidget {
  final bool isToday;
  const _EmptyChatState({required this.isToday});

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.chat_bubble_outline,
      title: isToday ? 'Log food or exercise below' : 'Nothing logged',
      iconSize: 40,
    );
  }
}

/// Subtle banner above the chat input. Rendered only when the smart-search
/// feature is in a state worth surfacing (downloading, indexing, or active).
/// Hidden in the steady-state "ready" mode after first-day usage to reduce
/// chrome. Hidden entirely when the feature is unavailable / not opted in.
class _SmartSearchBanner extends StatelessWidget {
  final NutritionPresenter presenter;
  const _SmartSearchBanner({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = presenter.foodSearchStatus;

    final visible = status == FoodSearchStatus.downloading ||
        status == FoodSearchStatus.indexing ||
        status == FoodSearchStatus.loading;
    if (!visible) return const SizedBox.shrink();

    final progress = presenter.foodIndexProgress;
    final (String label, double? value) = switch (status) {
      FoodSearchStatus.downloading => (
          'Downloading smart search… ${presenter.foodEmbedderDownloadProgress}%',
          presenter.foodEmbedderDownloadProgress / 100.0,
        ),
      FoodSearchStatus.loading => (
          'Loading smart search…',
          null,
        ),
      FoodSearchStatus.indexing => (
          'Indexing food database… ${progress.indexed} / ${progress.total}',
          progress.fraction,
        ),
      _ => ('', null),
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: value,
                  minHeight: 2,
                  backgroundColor:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBubble extends StatelessWidget {
  final String error;
  const _ErrorBubble({required this.error});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(error,
            style: TextStyle(
                color: Theme.of(context).colorScheme.error, fontSize: 13)),
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Text('Analyzing…',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

// ─── Chat Message Card ────────────────────────────────────────────────────────

class _ChatMessageCard extends StatelessWidget {
  final ChatMessage message;
  final NutritionPresenter presenter;
  const _ChatMessageCard(
      {required this.message, required this.presenter, super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: message.kind == ChatMessageKind.food
          ? _FoodAnalysisCard(message: message, presenter: presenter, key: key)
          : message.exerciseEntry != null
              ? _ExerciseAnalysisCard(message: message, presenter: presenter)
              : const SizedBox.shrink(),
    );
  }
}

// ─── Food Analysis Card ───────────────────────────────────────────────────────

class _FoodAnalysisCard extends StatefulWidget {
  final ChatMessage message;
  final NutritionPresenter presenter;
  const _FoodAnalysisCard(
      {required this.message, required this.presenter, super.key});

  @override
  State<_FoodAnalysisCard> createState() => _FoodAnalysisCardState();
}

class _FoodAnalysisCardState extends State<_FoodAnalysisCard> {
  bool _editing = false;
  bool _saving = false;
  late List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _resetControllers();
  }

  void _resetControllers() {
    _controllers = widget.message.foodItems.map((item) {
      return TextEditingController(text: item.amountText ?? item.name);
    }).toList();
  }

  @override
  void didUpdateWidget(_FoodAnalysisCard old) {
    super.didUpdateWidget(old);
    if (!_editing) {
      for (final c in _controllers) {
        c.dispose();
      }
      _resetControllers();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final texts = _controllers.map((c) => c.text.trim()).toList();
    await widget.presenter.editAllChatFoodItems(widget.message.id, texts);
    if (mounted) {
      setState(() {
        _editing = false;
        _saving = false;
      });
    }
  }

  void _cancel() {
    setState(() {
      _editing = false;
      for (var i = 0; i < _controllers.length; i++) {
        final item = widget.message.foodItems[i];
        _controllers[i].text = item.amountText ?? item.name;
      }
    });
  }

  Future<void> _onDislike(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await widget.presenter.markChatMessageDisliked(widget.message.id);
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(
        content: Text("Thanks — we'll improve the match next time."),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _saveAsTemplate(BuildContext context) async {
    final rawText = widget.message.rawText;
    final suggested = rawText.length > 40 ? rawText.substring(0, 40) : rawText;
    final nameCtrl = TextEditingController(text: suggested);
    final messenger = ScaffoldMessenger.of(context);

    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Save as template',
            style: TextStyle(color: cs.onSurface, fontSize: 15)),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: TextStyle(color: cs.onSurface),
          decoration: InputDecoration(
            hintText: 'Template name',
            hintStyle: TextStyle(color: cs.onSurfaceVariant),
            filled: true,
            fillColor: cs.surfaceContainerHighest,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: cs.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Save',
                style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ),
        ],
      ),
    );

    nameCtrl.dispose();
    if (confirmed != true || !mounted) return;

    final items = widget.message.foodItems;
    final template = FoodTemplate(
      id: FoodEntry.generateId(),
      name: nameCtrl.text.trim().isEmpty ? suggested : nameCtrl.text.trim(),
      isMeal: items.length > 1,
      entries: items
          .map((item) => FoodEntry(
                id: item.entryId,
                name: item.name,
                calories: item.calories,
                protein: item.protein,
                carbs: item.carbs,
                fat: item.fat,
                loggedAt: DateTime.now(),
              ))
          .toList(),
    );
    final messenger2 = messenger;
    await widget.presenter.saveFoodTemplate(template);
    if (mounted) {
      messenger2.showSnackBar(
        SnackBar(
          content: Text('Saved "${template.name}" to library'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Text(
              message.rawText,
              style: TextStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          ...message.foodItems.asMap().entries.map((e) => _FoodItemRow(
                item: e.value,
                index: e.key,
                isLast: e.key == message.foodItems.length - 1,
                editing: _editing,
                controller: _controllers[e.key],
                onDelete: _editing && message.foodItems.length > 1
                    ? () =>
                        widget.presenter.removeChatFoodItemAt(message.id, e.key)
                    : null,
                onSwapAlternative: (altIndex) =>
                    widget.presenter.swapChatFoodAlternative(
                  message.id,
                  e.key,
                  altIndex,
                ),
              )),
          if (message.foodItems.length >= 2)
            _MealTotalRow(items: message.foodItems),
          _MessageFooter(
            timestamp: message.timestamp,
            editing: _editing,
            saving: _saving,
            onEdit: () => setState(() => _editing = true),
            onDelete: () => widget.presenter.removeChatMessage(message.id),
            onSaveTemplate: () => _saveAsTemplate(context),
            onDislike: () => _onDislike(context),
            onConfirm: _save,
            onCancel: _cancel,
          ),
        ],
      ),
    );
  }
}

class _FoodItemRow extends StatelessWidget {
  final ChatFoodItem item;
  final int index;
  final bool isLast;
  final bool editing;
  final TextEditingController controller;
  final VoidCallback? onDelete;
  final ValueChanged<int>? onSwapAlternative;
  const _FoodItemRow({
    required this.item,
    required this.index,
    required this.isLast,
    required this.editing,
    required this.controller,
    this.onDelete,
    this.onSwapAlternative,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final body = editing
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _FoodEditField(
                  controller: controller,
                  autofocus: index == 0,
                ),
              ),
              if (onDelete != null) ...[
                const SizedBox(width: 6),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  tooltip: 'Remove this item',
                  icon: Icon(Icons.close, color: cs.error),
                  onPressed: onDelete,
                ),
              ],
            ],
          )
        : _FoodItemDisplay(item: item);

    final showAlternatives =
        !editing && item.alternatives.isNotEmpty && onSwapAlternative != null;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: body,
        ),
        if (showAlternatives)
          _AlternativesStrip(
            alternatives: item.alternatives,
            onTap: onSwapAlternative!,
          ),
        if (!isLast)
          Divider(
            height: 1,
            indent: 14,
            endIndent: 14,
            color: cs.outlineVariant,
          ),
      ],
    );
  }
}

/// Edit field with on-the-fly DB suggestions. Tap a suggestion to fill the
/// text. Suggestions come from FoodDbService.search() — same path used by the
/// resolution pipeline, so users can pick a known entry directly.
class _FoodEditField extends StatefulWidget {
  final TextEditingController controller;
  final bool autofocus;
  const _FoodEditField({required this.controller, required this.autofocus});

  @override
  State<_FoodEditField> createState() => _FoodEditFieldState();
}

class _FoodEditFieldState extends State<_FoodEditField> {
  List<FoodDbEntry> _suggestions = const [];
  Timer? _debounce;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged() {
    final text = widget.controller.text.trim();
    if (text == _lastQuery) return;
    _lastQuery = text;
    _debounce?.cancel();
    if (text.length < 2) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 200), () => _runQuery(text));
  }

  Future<void> _runQuery(String q) async {
    final presenter = context
        .findAncestorStateOfType<_FoodAnalysisCardState>()
        ?.widget
        .presenter;
    if (presenter == null) return;
    final results = await presenter.foodDb.search(q);
    if (!mounted || widget.controller.text.trim() != q) return;
    setState(() => _suggestions = results.take(5).toList(growable: false));
  }

  void _accept(FoodDbEntry entry) {
    widget.controller.text = entry.name;
    widget.controller.selection = TextSelection.collapsed(
      offset: widget.controller.text.length,
    );
    setState(() => _suggestions = const []);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: widget.controller,
          autofocus: widget.autofocus,
          style: TextStyle(color: cs.onSurface, fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            fillColor: cs.surfaceContainerHighest,
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: cs.primary.withValues(alpha: 0.4)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: cs.primary),
            ),
            hintText: 'e.g. 100g rice',
            hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
        ),
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              children: [
                for (var i = 0; i < _suggestions.length; i++)
                  InkWell(
                    onTap: () => _accept(_suggestions[i]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.search,
                              size: 14, color: cs.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _suggestions[i].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  TextStyle(color: cs.onSurface, fontSize: 13),
                            ),
                          ),
                          Text(
                            _suggestions[i].densityLabel,
                            style: TextStyle(
                                color: cs.onSurfaceVariant, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Sums calories + macros across a multi-item meal and renders a footer row.
/// Renders runner-up DB matches as tap-to-swap chips. Shown beneath a chat
/// food item when the matcher's auto-pick was low-confidence (Plan 022 §2.2).
/// Tapping a chip calls [onTap] with the alternative index — the presenter
/// swaps it into today's log and learns the choice into the personal dict.
class _AlternativesStrip extends StatelessWidget {
  final List<ChatFoodAlternative> alternatives;
  final ValueChanged<int> onTap;

  const _AlternativesStrip({required this.alternatives, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Not this? Try:',
            style: TextStyle(
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < alternatives.length; i++)
                _AlternativeChip(
                  alt: alternatives[i],
                  onTap: () => onTap(i),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AlternativeChip extends StatelessWidget {
  final ChatFoodAlternative alt;
  final VoidCallback onTap;

  const _AlternativeChip({required this.alt, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ActionChip(
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: cs.surfaceContainerHigh,
      side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
      label: Text(
        '${alt.name} · ${alt.calories} kcal',
        style: TextStyle(
          color: cs.onSurface,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _MealTotalRow extends StatelessWidget {
  final List<ChatFoodItem> items;
  const _MealTotalRow({required this.items});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    var kcal = 0;
    double? p, c, f;
    for (final item in items) {
      kcal += item.calories;
      if (item.protein != null) p = (p ?? 0) + item.protein!;
      if (item.carbs != null) c = (c ?? 0) + item.carbs!;
      if (item.fat != null) f = (f ?? 0) + item.fat!;
    }
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Row(
        children: [
          Text(
            'Total',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const Spacer(),
          if (p != null) ...[
            _MacroBadge(label: 'P', value: p, color: cs.primary),
            const SizedBox(width: 4),
          ],
          if (c != null) ...[
            _MacroBadge(label: 'C', value: c, color: context.appColors.gold),
            const SizedBox(width: 4),
          ],
          if (f != null) ...[
            _MacroBadge(label: 'F', value: f, color: cs.error),
            const SizedBox(width: 4),
          ],
          _NutriBadge(label: '$kcal kcal', color: context.appColors.gold),
        ],
      ),
    );
  }
}

class _FoodItemDisplay extends StatelessWidget {
  final ChatFoodItem item;
  const _FoodItemDisplay({required this.item});

  @override
  Widget build(BuildContext context) {
    final hasGrams = item.grams != null && item.grams! > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                item.name,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (item.needsConfirmation) ...[
              Tooltip(
                message: 'Low-confidence — tap edit to verify',
                child: _NutriBadge(
                    label: '?', color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(width: 4),
            ],
            if (!item.estimationSource.isTrusted) ...[
              Tooltip(
                message: _sourceTooltip(item.estimationSource),
                child: _NutriBadge(
                  label: item.estimationSource.badge,
                  color: item.estimationSource.badgeColor(context),
                ),
              ),
              const SizedBox(width: 4),
            ],
            if (hasGrams) ...[
              _NutriBadge(
                label: _gramsLabel(item.grams!),
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
            ],
            _NutriBadge(
              label: '${item.calories} kcal',
              color: context.appColors.gold,
            ),
          ],
        ),
        if (item.protein != null || item.carbs != null || item.fat != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              if (item.protein != null)
                _MacroBadge(
                    label: 'P',
                    value: item.protein!,
                    color: Theme.of(context).colorScheme.primary),
              if (item.carbs != null) ...[
                const SizedBox(width: 4),
                _MacroBadge(
                    label: 'C',
                    value: item.carbs!,
                    color: context.appColors.gold),
              ],
              if (item.fat != null) ...[
                const SizedBox(width: 4),
                _MacroBadge(
                    label: 'F',
                    value: item.fat!,
                    color: Theme.of(context).colorScheme.error),
              ],
            ],
          ),
        ],
      ],
    );
  }

  String _gramsLabel(double g) {
    if (g >= 1000) return '${(g / 1000).toStringAsFixed(1)}kg';
    if (g == g.roundToDouble()) return '${g.round()}g';
    return '${g.toStringAsFixed(1)}g';
  }

  String _sourceTooltip(EstimationSource s) => switch (s) {
        EstimationSource.aiPerItem => 'AI estimate',
        EstimationSource.keywordDensity => 'Rough estimate from keyword match',
        _ => '',
      };
}

class _NutriBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _NutriBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _MacroBadge extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _MacroBadge(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        '$label ${value.round()}g',
        style:
            TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w500),
      ),
    );
  }
}

// ─── Exercise Analysis Card ───────────────────────────────────────────────────

class _ExerciseAnalysisCard extends StatelessWidget {
  final ChatMessage message;
  final NutritionPresenter presenter;
  const _ExerciseAnalysisCard({required this.message, required this.presenter});

  @override
  Widget build(BuildContext context) {
    final e = message.exerciseEntry!;
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Text(
              message.rawText,
              style: TextStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Row(
              children: [
                Icon(Icons.local_fire_department_outlined,
                    color: context.appColors.gold, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.name,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (e.statsLabel.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          e.statsLabel,
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ),
                _NutriBadge(
                  label: '−${e.caloriesBurned} kcal',
                  color: context.appColors.success,
                ),
              ],
            ),
          ),
          _MessageFooter(
            timestamp: message.timestamp,
            editing: false,
            saving: false,
            onEdit: null,
            onDelete: () => presenter.removeChatMessage(message.id),
            onSaveTemplate: null,
            onConfirm: () {},
            onCancel: () {},
          ),
        ],
      ),
    );
  }
}

// ─── Message Footer ───────────────────────────────────────────────────────────

class _MessageFooter extends StatelessWidget {
  final DateTime timestamp;
  final bool editing;
  final bool saving;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onSaveTemplate;
  final VoidCallback? onDislike;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _MessageFooter({
    required this.timestamp,
    required this.editing,
    required this.saving,
    required this.onEdit,
    required this.onDelete,
    required this.onSaveTemplate,
    this.onDislike,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('h:mm a').format(timestamp);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 8, 8),
      child: Row(
        children: [
          Text(
            timeStr,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 10),
          ),
          const Spacer(),
          if (editing) ...[
            if (saving)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: context.appColors.success),
              )
            else
              _FooterBtn(
                  icon: Icons.check,
                  color: context.appColors.success,
                  onTap: onConfirm),
            const SizedBox(width: 2),
            _FooterBtn(
                icon: Icons.close, color: cs.onSurfaceVariant, onTap: onCancel),
          ] else ...[
            if (onEdit != null)
              _FooterBtn(
                  icon: Icons.edit_outlined,
                  color: cs.onSurfaceVariant,
                  onTap: onEdit!),
            if (onSaveTemplate != null) ...[
              const SizedBox(width: 2),
              _FooterBtn(
                  icon: Icons.bookmark_border,
                  color: cs.onSurfaceVariant,
                  onTap: onSaveTemplate!),
            ],
            if (onDislike != null) ...[
              const SizedBox(width: 2),
              _FooterBtn(
                  icon: Icons.thumb_down_outlined,
                  color: cs.onSurfaceVariant,
                  onTap: onDislike!),
            ],
            const SizedBox(width: 2),
            _FooterBtn(
                icon: Icons.delete_outline,
                color: cs.onSurfaceVariant,
                onTap: onDelete),
          ],
        ],
      ),
    );
  }
}

class _FooterBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _FooterBtn(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }
}

// ─── Chat Input Bar ───────────────────────────────────────────────────────────

class _ChatInputBar extends StatefulWidget {
  final NutritionPresenter presenter;
  const _ChatInputBar({required this.presenter});

  @override
  State<_ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<_ChatInputBar> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty || widget.presenter.isChatParsing) return;
    _ctrl.clear();
    FocusScope.of(context).unfocus();
    Future.delayed(Duration.zero, () {
      if (mounted) widget.presenter.parseChat(text);
    });
  }

  void _showTemplates(BuildContext context) {
    AppBottomSheet.show(
      context: context,
      title: 'Templates',
      body: _TemplateBody(presenter: widget.presenter),
      useDraggableScrollableSheet: true,
      initialChildSize: 0.5,
    );
  }

  void _showManualAdd(BuildContext context) {
    AppBottomSheet.show(
      context: context,
      title: 'Custom food',
      body: _ManualFoodBody(
        onAdd: (entry) => widget.presenter.addManualFoodEntry(entry),
      ),
      isScrollControlled: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.presenter.goals.ifSyncEnabled &&
        !widget.presenter.isEatingWindowOpen;
    final isToday = widget.presenter.isSelectedDateToday;

    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.grid_view_outlined, color: cs.onSurfaceVariant),
            onPressed: isToday ? () => _showTemplates(context) : null,
            tooltip: 'Templates',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
          IconButton(
            icon: Icon(Icons.qr_code_scanner, color: cs.onSurfaceVariant),
            onPressed: isToday && !locked
                ? () =>
                    showBarcodeScanFlow(context, presenter: widget.presenter)
                : null,
            tooltip: 'Scan barcode',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
          IconButton(
            icon: Icon(Icons.edit_outlined, color: cs.onSurfaceVariant),
            onPressed:
                isToday && !locked ? () => _showManualAdd(context) : null,
            tooltip: 'Add manually',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                enabled: isToday && !locked,
                style: TextStyle(color: cs.onSurface, fontSize: 14),
                decoration: InputDecoration(
                  hintText: locked
                      ? 'Fasting — logging paused'
                      : !isToday
                          ? 'View only — select today to log'
                          : 'Log food or exercise…',
                  hintStyle:
                      TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
              ),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: isToday && !locked ? _send : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color:
                    isToday && !locked ? cs.primary : cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(
                Icons.arrow_upward,
                color: isToday && !locked ? cs.onPrimary : cs.onSurfaceVariant,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Template Body ────────────────────────────────────────────────────────────

class _TemplateBody extends StatelessWidget {
  final NutritionPresenter presenter;
  const _TemplateBody({required this.presenter});

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
          presenter.addMealFromTemplate(t, MealSlot.meal);
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

// ─── Manual Food Body ─────────────────────────────────────────────────────────

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
