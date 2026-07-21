import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app_colors.dart';
import '../../presenters/ai_coach_presenter.dart';
import '../../presenters/nutrition_presenter.dart';
import 'food_library_screen.dart';
import 'nutrition_history_screen.dart';
import 'nutrition_settings_sheet.dart';
import 'widgets/eaten_today_hero.dart';
import 'widgets/log_composer_sheet.dart';
import 'widgets/nutrition_log_list.dart';
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
    // No ListenableBuilder here — the Scaffold and AppBar are static.
    // Each body section has its own scoped ListenableBuilder (see _NutritionBody).
    return _NutritionBody(
      presenter: presenter,
      aiCoachPresenter: aiCoachPresenter,
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
        title: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Nutrition',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(width: 10),
            _AiTierBadge(presenter: presenter),
          ],
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
            ListenableBuilder(
              listenable: presenter,
              builder: (_, __) => _WeekStrip(presenter: presenter),
            ),
            ListenableBuilder(
              listenable: presenter,
              builder: (_, __) => EatenTodayHero(
                presenter: presenter,
                onTap: () => _showNutritionDetailSheet(context, presenter),
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: presenter,
                builder: (_, __) => NutritionLogList(presenter: presenter),
              ),
            ),
            ListenableBuilder(
              listenable: presenter,
              builder: (_, __) => _ComposerTriggerBar(presenter: presenter),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Composer Trigger Bar ─────────────────────────────────────────────────────

/// Thin pinned bar that opens the logging composer. Also surfaces the inline
/// analyzing/error states from a chat parse in progress and honours the IF-sync
/// lock (disabled while fasting today; past days always loggable — Plan 037).
class _ComposerTriggerBar extends StatelessWidget {
  final NutritionPresenter presenter;
  const _ComposerTriggerBar({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isToday = presenter.isSelectedDateToday;
    final locked =
        presenter.goals.ifSyncEnabled && !presenter.isEatingWindowOpen;
    final canLog = isToday ? !locked : true;
    final parsing = presenter.isChatParsing;
    final error = presenter.chatParseError;

    final hint = !isToday
        ? 'Log food for ${DateFormat.MMMd().format(presenter.selectedDate)}…'
        : locked
            ? 'Fasting — logging paused'
            : 'Log a meal or exercise…';

    return Container(
      color: cs.surface,
      padding: EdgeInsets.fromLTRB(
          16, 8, 16, MediaQuery.of(context).padding.bottom + 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (parsing)
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: cs.primary),
                  ),
                  const SizedBox(width: 9),
                  Text('Analyzing…',
                      style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            )
          else if (error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: cs.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: cs.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(error,
                        style: TextStyle(color: cs.error, fontSize: 12.5)),
                  ),
                  InkWell(
                    onTap: presenter.clearChatParseError,
                    borderRadius: BorderRadius.circular(999),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 15, color: cs.error),
                    ),
                  ),
                ],
              ),
            ),
          Opacity(
            opacity: canLog ? 1 : 0.55,
            child: Material(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: canLog
                    ? () => showLogComposerSheet(context, presenter)
                    : null,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.only(left: 15, right: 7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.photo_camera_outlined,
                          size: 20, color: cs.onSurfaceVariant),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          hint,
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 14),
                        ),
                      ),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color:
                              canLog ? cs.primary : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.arrow_upward,
                          size: 17,
                          color: canLog ? cs.onPrimary : cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── AI Tier Badge ────────────────────────────────────────────────────────────

class _AiTierBadge extends StatelessWidget {
  final NutritionPresenter presenter;
  const _AiTierBadge({required this.presenter});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final isCloud =
            presenter.isCloudAiConfigured && presenter.isCloudAiAvailable;
        final label = isCloud ? 'Cloud' : 'Local';
        final icon =
            isCloud ? Icons.cloud_outlined : Icons.phone_android_outlined;
        final color = isCloud ? cs.primary : cs.outline;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border:
                Border.all(color: color.withValues(alpha: 0.35), width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Week Strip ───────────────────────────────────────────────────────────────

class _WeekStrip extends StatefulWidget {
  final NutritionPresenter presenter;
  const _WeekStrip({required this.presenter});

  @override
  State<_WeekStrip> createState() => _WeekStripState();
}

class _WeekStripState extends State<_WeekStrip> {
  late DateTime _weekStart;

  static DateTime _mondayOf(DateTime date) {
    final d = DateUtils.dateOnly(date);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  @override
  void initState() {
    super.initState();
    _weekStart = _mondayOf(widget.presenter.selectedDate);
  }

  void _goBack() =>
      setState(() => _weekStart = _weekStart.subtract(const Duration(days: 7)));

  void _goForward() {
    final currentMonday = _mondayOf(DateUtils.dateOnly(DateTime.now()));
    if (_weekStart.isBefore(currentMonday)) {
      setState(() => _weekStart = _weekStart.add(const Duration(days: 7)));
    }
  }

  void _openMonthPicker(BuildContext context) {
    AppBottomSheet.show(
      context: context,
      title: 'Pick Date',
      body: _MonthPicker(
        selectedDate: widget.presenter.selectedDate,
        onDateSelected: (date) {
          setState(() => _weekStart = _mondayOf(date));
          widget.presenter.setSelectedDate(date);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateUtils.dateOnly(DateTime.now());
    final currentMonday = _mondayOf(today);
    final canGoForward = _weekStart.isBefore(currentMonday);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: IconButton(
                  icon: Icon(Icons.chevron_left,
                      color: theme.colorScheme.onSurfaceVariant),
                  iconSize: 22,
                  padding: EdgeInsets.zero,
                  onPressed: _goBack,
                  tooltip: 'Previous week',
                ),
              ),
              Expanded(
                child: AppDayChipRow(
                  selectedDate: widget.presenter.selectedDate,
                  weekStart: _weekStart,
                  onSelected: (day) {
                    if (!day.isAfter(today)) {
                      widget.presenter.setSelectedDate(day);
                    }
                  },
                ),
              ),
              SizedBox(
                width: 44,
                height: 44,
                child: IconButton(
                  icon: Icon(
                    Icons.chevron_right,
                    color: canGoForward
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.25),
                  ),
                  iconSize: 22,
                  padding: EdgeInsets.zero,
                  onPressed: canGoForward ? _goForward : null,
                  tooltip: 'Next week',
                ),
              ),
            ],
          ),
        ),
        // Calendar expand handle — full-width strip so it's easy to tap
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openMonthPicker(context),
          child: SizedBox(
            width: double.infinity,
            height: 24,
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
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

// ─── Month Picker ─────────────────────────────────────────────────────────────

class _MonthPicker extends StatefulWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  const _MonthPicker(
      {required this.selectedDate, required this.onDateSelected});

  @override
  State<_MonthPicker> createState() => _MonthPickerState();
}

class _MonthPickerState extends State<_MonthPicker> {
  late DateTime _month; // normalized to day=1

  static final _monthFmt = DateFormat('MMMM yyyy');
  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.selectedDate.year, widget.selectedDate.month);
  }

  void _prevMonth() =>
      setState(() => _month = DateTime(_month.year, _month.month - 1));

  void _nextMonth() {
    final now = DateTime.now();
    final next = DateTime(_month.year, _month.month + 1);
    if (!next.isAfter(DateTime(now.year, now.month))) {
      setState(() => _month = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateUtils.dateOnly(DateTime.now());
    final selected = DateUtils.dateOnly(widget.selectedDate);
    final canGoForward = _month.isBefore(DateTime(today.year, today.month));

    final daysInMonth = DateUtils.getDaysInMonth(_month.year, _month.month);
    // Monday-first: Monday weekday = 1 → offset 0, Sunday = 7 → offset 6
    final offset = _month.weekday - 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Month navigation
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: _prevMonth,
              tooltip: 'Previous month',
            ),
            Expanded(
              child: Text(
                _monthFmt.format(_month),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.chevron_right,
                color: canGoForward
                    ? null
                    : theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.25),
              ),
              onPressed: canGoForward ? _nextMonth : null,
              tooltip: 'Next month',
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Day-of-week labels
        Row(
          children: _dayLabels
              .map((l) => Expanded(
                    child: Text(
                      l,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 6),
        // Calendar grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 0,
            crossAxisSpacing: 0,
            childAspectRatio: 1.1,
          ),
          itemCount: offset + daysInMonth,
          itemBuilder: (ctx, index) {
            if (index < offset) return const SizedBox.shrink();

            final dayNum = index - offset + 1;
            final date =
                DateUtils.dateOnly(DateTime(_month.year, _month.month, dayNum));
            final isFuture = date.isAfter(today);
            final isSelected = date == selected;
            final isToday = date == today;

            Color? bg;
            Color fg;
            BoxBorder? border;

            if (isSelected) {
              bg = theme.colorScheme.primary;
              fg = theme.colorScheme.onPrimary;
            } else if (isFuture) {
              fg = theme.colorScheme.onSurface.withValues(alpha: 0.2);
            } else if (isToday) {
              border = Border.all(color: theme.colorScheme.primary, width: 1.5);
              fg = theme.colorScheme.primary;
            } else {
              fg = theme.colorScheme.onSurface;
            }

            return GestureDetector(
              onTap: isFuture
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      widget.onDateSelected(date);
                    },
              child: Container(
                margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: bg,
                  shape: BoxShape.circle,
                  border: border,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$dayNum',
                  style: TextStyle(
                    fontSize: 12,
                    color: fg,
                    fontWeight: isSelected || isToday
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}
