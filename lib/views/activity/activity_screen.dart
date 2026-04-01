import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../../app_colors.dart';
import '../../models/activity_log.dart';
import '../../presenters/activity_presenter.dart';

class ActivityScreen extends StatefulWidget {
  final ActivityPresenter presenter;

  const ActivityScreen({super.key, required this.presenter});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ringController;
  late Animation<double> _ringAnimation;
  double _lastProgress = 0;

  @override
  void initState() {
    super.initState();
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _ringAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _ringController, curve: Curves.easeOut),
    );
    // Sync on open (non-blocking)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.presenter.hasHealthPermission) {
        widget.presenter.syncFromHealthConnect();
      }
    });
  }

  @override
  void dispose() {
    _ringController.dispose();
    super.dispose();
  }

  void _animateRingTo(double target) {
    _ringAnimation = Tween<double>(
      begin: _lastProgress,
      end: target.clamp(0, 1.5),
    ).animate(CurvedAnimation(parent: _ringController, curve: Curves.easeOut));
    _lastProgress = target.clamp(0, 1.5);
    _ringController
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'TRAINING GROUNDS',
          style: TextStyle(letterSpacing: 2.0, fontSize: 14),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _showGoalSheet(context),
            tooltip: 'Set step goal',
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.presenter,
        builder: (context, _) {
          final p = widget.presenter;
          _animateRingTo(p.stepProgress);
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StepRingSection(
                    animation: _ringAnimation,
                    presenter: p,
                  ),
                  const SizedBox(height: 20),
                  _HealthConnectStatusBar(presenter: p),
                  const SizedBox(height: 24),
                  _HistorySection(history: p.history),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showGoalSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _GoalSheet(presenter: widget.presenter),
    );
  }
}

// ─── Step Ring ────────────────────────────────────────────────────────────────

class _StepRingSection extends StatelessWidget {
  final Animation<double> animation;
  final ActivityPresenter presenter;

  const _StepRingSection({required this.animation, required this.presenter});

  @override
  Widget build(BuildContext context) {
    final p = presenter;
    final fmt = NumberFormat('#,###');

    return Column(
      children: [
        const SizedBox(height: 16),
        SizedBox(
          width: 200,
          height: 200,
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, _) => CustomPaint(
              painter: _RingPainter(
                progress: animation.value,
                ringColor: AppColors.success,
                trackColor: AppColors.surface,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      fmt.format(p.todaySteps),
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        letterSpacing: -1,
                      ),
                    ),
                    Text(
                      'steps',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        letterSpacing: 1.5,
                      ),
                    ),
                    if (p.isGoalMet)
                      const Icon(Icons.check_circle, color: AppColors.success, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          p.summaryLabel,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        if (p.todayLog.activeCalories != null ||
            p.todayLog.distanceMeters != null) ...[
          const SizedBox(height: 12),
          _BonusStats(log: p.todayLog),
        ],
      ],
    );
  }
}

class _BonusStats extends StatelessWidget {
  final ActivityLog log;

  const _BonusStats({required this.log});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (log.activeCalories != null) ...[
          Icon(MdiIcons.fire, size: 16, color: AppColors.gold),
          const SizedBox(width: 4),
          Text(
            '${log.activeCalories!.round()} kcal',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
        if (log.activeCalories != null && log.distanceMeters != null)
          const SizedBox(width: 16),
        if (log.distanceMeters != null) ...[
          Icon(MdiIcons.mapMarkerDistance, size: 16, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            '${(log.distanceMeters! / 1000).toStringAsFixed(1)} km',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ],
    );
  }
}

// ─── Health Connect Status Bar ────────────────────────────────────────────────

class _HealthConnectStatusBar extends StatelessWidget {
  final ActivityPresenter presenter;

  const _HealthConnectStatusBar({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final p = presenter;

    if (p.isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (p.isHealthConnectAvailable && p.hasHealthPermission) {
      return _StatusCard(
        icon: Icons.check_circle_outline,
        iconColor: AppColors.success,
        label: p.todayLog.isManualEntry ? 'Manual entry' : 'Synced from Health Connect',
        action: FilledButton.tonal(
          onPressed: () => p.syncFromHealthConnect(),
          style: FilledButton.styleFrom(minimumSize: const Size(100, 40)),
          child: const Text('Sync Now'),
        ),
      );
    }

    if (p.isHealthConnectAvailable && !p.hasHealthPermission) {
      return _StatusCard(
        icon: Icons.warning_amber_outlined,
        iconColor: AppColors.gold,
        label: 'Health Connect not connected',
        action: FilledButton(
          onPressed: () => p.requestHealthPermission(),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.success,
            minimumSize: const Size(100, 40),
          ),
          child: const Text('Connect'),
        ),
      );
    }

    // Manual mode
    return _StatusCard(
      icon: Icons.edit_outlined,
      iconColor: AppColors.textSecondary,
      label: 'Manual mode',
      action: FilledButton.tonal(
        onPressed: () => _showManualEntry(context, p),
        style: FilledButton.styleFrom(minimumSize: const Size(100, 40)),
        child: const Text('Enter Steps'),
      ),
    );
  }

  void _showManualEntry(BuildContext context, ActivityPresenter p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ManualEntrySheet(presenter: p),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final Widget action;

  const _StatusCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surface.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
          action,
        ],
      ),
    );
  }
}

// ─── History Section ──────────────────────────────────────────────────────────

class _HistorySection extends StatelessWidget {
  final List<ActivityLog> history;

  const _HistorySection({required this.history});

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            'No history yet',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'RECENT DAYS',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 8),
        ...history.map((log) => _HistoryRow(log: log)),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final ActivityLog log;

  const _HistoryRow({required this.log});

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('MMM d').format(DateTime.parse(log.date));
    final isYesterday = log.date ==
        DateFormat('yyyy-MM-dd')
            .format(DateTime.now().subtract(const Duration(days: 1)));
    final label = isYesterday ? 'Yesterday' : date;
    final fmt = NumberFormat('#,###');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              fmt.format(log.steps),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          if (log.steps >= 8000)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check, size: 14, color: AppColors.success),
                const SizedBox(width: 4),
                Text(
                  'Goal met',
                  style: TextStyle(color: AppColors.success, fontSize: 12),
                ),
              ],
            ),
          if (log.isManualEntry)
            Text(
              ' (manual)',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
        ],
      ),
    );
  }
}

// ─── Goal Sheet ───────────────────────────────────────────────────────────────

class _GoalSheet extends StatefulWidget {
  final ActivityPresenter presenter;

  const _GoalSheet({required this.presenter});

  @override
  State<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<_GoalSheet> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.presenter.goals.dailyStepGoal.toString(),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Daily Step Goal',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Steps',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.success,
              minimumSize: const Size.fromHeight(50),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _save() {
    final steps = int.tryParse(_ctrl.text);
    if (steps == null || steps <= 0) return;
    widget.presenter
        .updateGoals(widget.presenter.goals.copyWith(dailyStepGoal: steps));
    Navigator.pop(context);
  }
}

// ─── Manual Entry Sheet ───────────────────────────────────────────────────────

class _ManualEntrySheet extends StatefulWidget {
  final ActivityPresenter presenter;

  const _ManualEntrySheet({required this.presenter});

  @override
  State<_ManualEntrySheet> createState() => _ManualEntrySheetState();
}

class _ManualEntrySheetState extends State<_ManualEntrySheet> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.presenter.todaySteps > 0
          ? widget.presenter.todaySteps.toString()
          : '',
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Today's Steps",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Steps taken today',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.success,
              minimumSize: const Size.fromHeight(50),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _save() {
    final steps = int.tryParse(_ctrl.text);
    if (steps == null || steps < 0) return;
    widget.presenter.setManualSteps(steps);
    Navigator.pop(context);
  }
}

// ─── Ring Painter ─────────────────────────────────────────────────────────────

class _RingPainter extends CustomPainter {
  final double progress;
  final Color ringColor;
  final Color trackColor;

  const _RingPainter({
    required this.progress,
    required this.ringColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide / 2) - 12;
    const strokeWidth = 14.0;

    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final ringPaint = Paint()
      ..color = ringColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Track
    canvas.drawCircle(center, radius, trackPaint);

    // Progress arc — start at top (-π/2), sweep clockwise
    final sweep = (progress * 2 * math.pi).clamp(0.0, 2 * math.pi);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      ringPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}
