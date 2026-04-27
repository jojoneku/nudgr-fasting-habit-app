import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app_colors.dart';
import '../../models/chat_message.dart';
import '../../models/food_template.dart';
import '../../models/food_entry.dart';
import '../../models/meal_slot.dart';
import '../../presenters/ai_coach_presenter.dart';
import '../../presenters/nutrition_presenter.dart';
import 'food_library_screen.dart';
import 'nutrition_history_screen.dart';
import 'nutrition_settings_sheet.dart';

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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: canPop ? 0 : 20,
        leading: canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new,
                    color: AppColors.textSecondary, size: 18),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: const Text(
          'Nutrition',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_outlined,
                color: AppColors.textSecondary, size: 22),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      NutritionHistoryScreen(presenter: presenter)),
            ),
            tooltip: 'History',
          ),
          IconButton(
            icon: const Icon(Icons.menu_book_outlined,
                color: AppColors.textSecondary, size: 22),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      FoodLibraryScreen(presenter: presenter)),
            ),
            tooltip: 'Library',
          ),
          IconButton(
            icon: const Icon(Icons.tune_outlined,
                color: AppColors.textSecondary, size: 22),
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
            _WeekStrip(presenter: presenter),
            _StatSection(presenter: presenter),
            Expanded(child: _ChatFeed(presenter: presenter)),
            _ChatInputBar(presenter: presenter),
          ],
        ),
      ),
    );
  }
}

// ─── Week Strip ───────────────────────────────────────────────────────────────

class _WeekStrip extends StatelessWidget {
  final NutritionPresenter presenter;
  const _WeekStrip({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateUtils.dateOnly(now);
    final selected = DateUtils.dateOnly(presenter.selectedDate);
    // Monday of this week
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final days = List.generate(7, (i) => monday.add(Duration(days: i)));

    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: days.map((day) {
          final isToday = day == today;
          final isSelected = day == selected;
          final isFuture = day.isAfter(today);
          return _DayChip(
            day: day,
            isToday: isToday,
            isSelected: isSelected,
            isFuture: isFuture,
            onTap: isFuture ? null : () => presenter.setSelectedDate(day),
          );
        }).toList(),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  final DateTime day;
  final bool isToday;
  final bool isSelected;
  final bool isFuture;
  final VoidCallback? onTap;
  const _DayChip({
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.isFuture,
    required this.onTap,
  });

  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final label = _dayLabels[day.weekday - 1];
    final textColor = isFuture
      ? AppColors.textSecondary.withValues(alpha: 0.3)
        : isSelected
            ? AppColors.background
            : isToday
                ? AppColors.primary
                : AppColors.textSecondary;
    final bgColor = isSelected ? AppColors.primary : Colors.transparent;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 40,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isFuture
                    ? AppColors.textSecondary.withValues(alpha: 0.3)
                    : AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                '${day.day}',
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontWeight:
                      isSelected || isToday ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Stat Section ─────────────────────────────────────────────────────────────

void _showNutritionDetailSheet(
    BuildContext context, NutritionPresenter presenter) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _NutritionDetailSheet(presenter: presenter),
  );
}

class _StatSection extends StatelessWidget {
  final NutritionPresenter presenter;
  const _StatSection({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final p = presenter;
    final burned = p.selectedDateCaloriesBurned;
    final barColor = p.isOverGoal ? AppColors.danger : AppColors.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: GestureDetector(
        onTap: () => _showNutritionDetailSheet(context, p),
        child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            // ── Calories side (60%) ───────────────────────────────────────
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CALORIES',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _TinyBar(
                    progress: p.netCalorieProgress,
                    color: barColor,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _StatCell(
                        value: '${p.todayCalories}',
                        label: 'Eaten',
                        color: AppColors.textPrimary,
                      ),
                      const _ColDivider(),
                      _StatCell(
                        value: '${p.remainingCalories}',
                        label: 'Left',
                        color: AppColors.textPrimary,
                      ),
                      const _ColDivider(),
                      _StatCell(
                        value: burned > 0 ? '$burned' : '—',
                        label: 'Burned',
                        color: AppColors.textPrimary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // ── Divider ───────────────────────────────────────────────────
            Container(
              width: 1,
              height: 56,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              color: AppColors.textSecondary.withValues(alpha: 0.20),
            ),
            // ── Macros side (40%) ─────────────────────────────────────────
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'MACROS',
                    style: TextStyle(
                      color: AppColors.textSecondary,
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
                        color: AppColors.textPrimary,
                        barColor: AppColors.primary,
                        progress: p.proteinProgress,
                      ),
                      const _ColDivider(),
                      _StatCell(
                        value: '${p.todayCarbs.round()}g',
                        label: 'Carbs',
                        color: AppColors.textPrimary,
                        barColor: AppColors.gold,
                        progress: p.carbsProgress,
                      ),
                      const _ColDivider(),
                      _StatCell(
                        value: '${p.todayFat.round()}g',
                        label: 'Fat',
                        color: AppColors.textPrimary,
                        barColor: AppColors.danger,
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
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: AppColors.textSecondary.withValues(alpha: 0.20),
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
            _TinyBar(progress: progress!, color: barColor ?? color),
            const SizedBox(height: 5),
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
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _TinyBar extends StatelessWidget {
  final double progress;
  final Color color;
  const _TinyBar({required this.progress, required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, box) {
      return Container(
        height: 3,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            height: 3,
            width: box.maxWidth * progress.clamp(0.0, 1.0),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      );
    });
  }
}


// ─── Nutrition Detail Sheet ───────────────────────────────────────────────────

class _NutritionDetailSheet extends StatelessWidget {
  final NutritionPresenter presenter;
  const _NutritionDetailSheet({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final p = presenter;
    final burned = p.selectedDateCaloriesBurned;
    final calGoal = p.effectiveGoal;
    final remaining = p.remainingCalories;
    final barColor = p.isOverGoal ? AppColors.danger : AppColors.primary;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.55,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Text(
            'BREAKDOWN',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 16),
          // ── Calories row ────────────────────────────────────────────────
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
          const Divider(color: Color(0x18FFFFFF), height: 1),
          const SizedBox(height: 14),
          // ── Macros ──────────────────────────────────────────────────────
          if (p.proteinGoal != null)
            _DetailRow(
              label: 'Protein',
              value: p.todayProtein.round(),
              goal: p.proteinGoal!,
              remaining: (p.proteinGoal! - p.todayProtein.round()).clamp(0, p.proteinGoal!),
              unit: 'g',
              color: AppColors.primary,
            ),
          if (p.proteinGoal != null) const SizedBox(height: 10),
          if (p.carbsGoal != null)
            _DetailRow(
              label: 'Carbs',
              value: p.todayCarbs.round(),
              goal: p.carbsGoal!,
              remaining: (p.carbsGoal! - p.todayCarbs.round()).clamp(0, p.carbsGoal!),
              unit: 'g',
              color: AppColors.gold,
            ),
          if (p.carbsGoal != null) const SizedBox(height: 10),
          if (p.fatGoal != null)
            _DetailRow(
              label: 'Fat',
              value: p.todayFat.round(),
              goal: p.fatGoal!,
              remaining: (p.fatGoal! - p.todayFat.round()).clamp(0, p.fatGoal!),
              unit: 'g',
              color: AppColors.danger,
            ),
          if (p.proteinGoal == null && p.carbsGoal == null && p.fatGoal == null)
            const Text(
              'No macro targets set — configure them in Settings.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
        ],
      ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
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
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _FullBar(progress: progress, color: color),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              '$remaining $unit remaining',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
            if (extra != null) ...[
              const Spacer(),
              Text(
                extra!,
                style: const TextStyle(
                  color: AppColors.textSecondary,
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

class _FullBar extends StatelessWidget {
  final double progress;
  final Color color;
  const _FullBar({required this.progress, required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, box) {
      return Container(
        height: 8,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            height: 8,
            width: box.maxWidth * progress,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      );
    });
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
      return _EmptyChatState(
          isToday: widget.presenter.isSelectedDateToday);
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemCount: messages.length + (isParsing ? 1 : 0) + (error != null ? 1 : 0),
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline,
              color: AppColors.textSecondary.withValues(alpha: 0.3), size: 40),
          const SizedBox(height: 12),
          Text(
            isToday ? 'Log food or exercise below' : 'Nothing logged',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 14),
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
          color: AppColors.danger.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(error,
            style: const TextStyle(color: AppColors.danger, fontSize: 13)),
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.textSecondary,
              ),
            ),
            SizedBox(width: 8),
            Text('Analyzing…',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
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
          ? _FoodAnalysisCard(
              message: message, presenter: presenter, key: key)
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
      return TextEditingController(
          text: item.amountText ?? item.name);
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
    if (mounted) setState(() { _editing = false; _saving = false; });
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

  Future<void> _saveAsTemplate(BuildContext context) async {
    final rawText = widget.message.rawText;
    final suggested = rawText.length > 40 ? rawText.substring(0, 40) : rawText;
    final nameCtrl = TextEditingController(text: suggested);
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Save as template',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 15)),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Template name',
            hintStyle: const TextStyle(color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.background,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save',
                style: TextStyle(color: AppColors.primary)),
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
    final messenger2 = messenger; // already captured above
    await widget.presenter.saveFoodTemplate(template);
    if (mounted) {
      messenger2.showSnackBar(
        SnackBar(
          content: Text('Saved "${template.name}" to library'),
          backgroundColor: AppColors.surface,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Original input header ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Text(
              message.rawText,
              style: TextStyle(
                color: AppColors.textSecondary.withValues(alpha: 0.7),
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          Divider(
              height: 1,
              color: AppColors.textSecondary.withValues(alpha: 0.08)),
          // ── Food item rows ─────────────────────────────────────────────────
          ...message.foodItems.asMap().entries.map((e) => _FoodItemRow(
                item: e.value,
                index: e.key,
                isLast: e.key == message.foodItems.length - 1,
                editing: _editing,
                controller: _controllers[e.key],
              )),
          // ── Footer ─────────────────────────────────────────────────────────
          _MessageFooter(
            timestamp: message.timestamp,
            editing: _editing,
            saving: _saving,
            onEdit: () => setState(() => _editing = true),
            onDelete: () => widget.presenter.removeChatMessage(message.id),
            onSaveTemplate: () => _saveAsTemplate(context),
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
  const _FoodItemRow({
    required this.item,
    required this.index,
    required this.isLast,
    required this.editing,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: editing
              ? TextField(
                  controller: controller,
                  autofocus: index == 0,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 8, horizontal: 10),
                    fillColor: AppColors.background,
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                          color: AppColors.primary.withValues(alpha: 0.4)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                    hintText: 'e.g. 100g rice',
                    hintStyle: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                  ),
                )
              : _FoodItemDisplay(item: item),
        ),
        if (!isLast)
          Divider(
            height: 1,
            indent: 14,
            endIndent: 14,
            color: AppColors.textSecondary.withValues(alpha: 0.08),
          ),
      ],
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
            if (item.isEstimated)
              const Text('~',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
            Expanded(
              child: Text(
                item.name,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (hasGrams) ...[
              _NutriBadge(
                label: _gramsLabel(item.grams!),
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
            ],
            _NutriBadge(
              label: '${item.calories} kcal',
              color: AppColors.gold,
            ),
          ],
        ),
        if (item.protein != null ||
            item.carbs != null ||
            item.fat != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              if (item.protein != null)
                _MacroBadge(
                    label: 'P', value: item.protein!, color: AppColors.primary),
              if (item.carbs != null) ...[
                const SizedBox(width: 4),
                _MacroBadge(
                    label: 'C', value: item.carbs!, color: AppColors.gold),
              ],
              if (item.fat != null) ...[
                const SizedBox(width: 4),
                _MacroBadge(
                    label: 'F', value: item.fat!, color: AppColors.danger),
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
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w600),
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
        style: TextStyle(
            color: color, fontSize: 10, fontWeight: FontWeight.w500),
      ),
    );
  }
}

// ─── Exercise Analysis Card ───────────────────────────────────────────────────

class _ExerciseAnalysisCard extends StatelessWidget {
  final ChatMessage message;
  final NutritionPresenter presenter;
  const _ExerciseAnalysisCard(
      {required this.message, required this.presenter});

  @override
  Widget build(BuildContext context) {
    final e = message.exerciseEntry!;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Original input header ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Text(
              message.rawText,
              style: TextStyle(
                color: AppColors.textSecondary.withValues(alpha: 0.7),
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          Divider(
              height: 1,
              color: AppColors.textSecondary.withValues(alpha: 0.08)),
          // ── Exercise row ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Row(
              children: [
                const Icon(Icons.local_fire_department_outlined,
                    color: AppColors.gold, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.name,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (e.statsLabel.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          e.statsLabel,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ),
                _NutriBadge(
                  label: '−${e.caloriesBurned} kcal',
                  color: AppColors.success,
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
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _MessageFooter({
    required this.timestamp,
    required this.editing,
    required this.saving,
    required this.onEdit,
    required this.onDelete,
    required this.onSaveTemplate,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('h:mm a').format(timestamp);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 8, 8),
      child: Row(
        children: [
          Text(
            timeStr,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 10),
          ),
          const Spacer(),
          if (editing) ...[
            if (saving)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.success),
              )
            else
              _FooterBtn(
                  icon: Icons.check,
                  color: AppColors.success,
                  onTap: onConfirm),
            const SizedBox(width: 2),
            _FooterBtn(
                icon: Icons.close,
                color: AppColors.textSecondary,
                onTap: onCancel),
          ] else ...[
            if (onEdit != null)
              _FooterBtn(
                  icon: Icons.edit_outlined,
                  color: AppColors.textSecondary,
                  onTap: onEdit!),
            if (onSaveTemplate != null) ...[
              const SizedBox(width: 2),
              _FooterBtn(
                  icon: Icons.bookmark_border,
                  color: AppColors.textSecondary,
                  onTap: onSaveTemplate!),
            ],
            const SizedBox(width: 2),
            _FooterBtn(
                icon: Icons.delete_outline,
                color: AppColors.textSecondary,
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
    // Dismiss keyboard first, then defer parseChat to the next frame so the
    // keyboard dismiss animation starts before triggering a rebuild.
    FocusScope.of(context).unfocus();
    Future.delayed(Duration.zero, () {
      if (mounted) widget.presenter.parseChat(text);
    });
  }

  void _showTemplates(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _TemplateSheet(presenter: widget.presenter),
    );
  }

  void _showManualAdd(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ManualFoodSheet(
        onAdd: (entry) => widget.presenter.addManualFoodEntry(entry),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.presenter.goals.ifSyncEnabled &&
        !widget.presenter.isEatingWindowOpen;
    final isToday = widget.presenter.isSelectedDateToday;

    return Container(
      color: AppColors.background,
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.grid_view_outlined,
                color: AppColors.textSecondary),
            onPressed: isToday ? () => _showTemplates(context) : null,
            tooltip: 'Templates',
            constraints:
                const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined,
                color: AppColors.textSecondary),
            onPressed:
                isToday && !locked ? () => _showManualAdd(context) : null,
            tooltip: 'Add manually',
            constraints:
                const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
          Expanded(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                enabled: isToday && !locked,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: locked
                      ? 'Fasting — logging paused'
                      : !isToday
                          ? 'View only — select today to log'
                          : 'Log food or exercise…',
                  hintStyle: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 8),
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
                color: isToday && !locked
                    ? AppColors.primary
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(
                Icons.arrow_upward,
                color: isToday && !locked
                    ? AppColors.background
                    : AppColors.textSecondary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Template Sheet ───────────────────────────────────────────────────────────

class _TemplateSheet extends StatelessWidget {
  final NutritionPresenter presenter;
  const _TemplateSheet({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final templates = presenter.savedTemplates;
    final recents = presenter.recentFoods.take(5).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (recents.isNotEmpty) ...[
            _sheetSectionLabel('Recent'),
            ..._templateList(context, recents),
          ],
          if (templates.isNotEmpty) ...[
            _sheetSectionLabel('Saved Meals'),
            ..._templateList(context, templates),
          ],
          if (templates.isEmpty && recents.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No templates yet. Save a meal from the Library.',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }

  List<Widget> _templateList(
      BuildContext context, List<FoodTemplate> items) {
    return items.map((t) {
      final totalCal =
          t.entries.fold<int>(0, (sum, e) => sum + e.calories);
      return ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        leading: t.isPinned
            ? const Icon(Icons.push_pin, color: AppColors.primary, size: 14)
            : null,
        title: Text(t.name,
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 14)),
        trailing: Text(
          totalCal > 0 ? '$totalCal kcal' : '',
          style: const TextStyle(
              color: AppColors.gold, fontSize: 12),
        ),
        onTap: () {
          Navigator.pop(context);
          presenter.addMealFromTemplate(t, MealSlot.meal);
        },
      );
    }).toList();
  }

  Widget _sheetSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Text(
        label,
        style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5),
      ),
    );
  }
}

// ─── Manual Food Sheet ────────────────────────────────────────────────────────

class _ManualFoodSheet extends StatefulWidget {
  final void Function(FoodEntry) onAdd;
  const _ManualFoodSheet({required this.onAdd});

  @override
  State<_ManualFoodSheet> createState() => _ManualFoodSheetState();
}

class _ManualFoodSheetState extends State<_ManualFoodSheet> {
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
                backgroundColor: AppColors.primary,
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
            borderSide: const BorderSide(color: AppColors.primary, width: 1)),
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
