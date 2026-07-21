import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app_colors.dart';
import '../../models/weight_entry.dart';
import '../../presenters/nutrition_presenter.dart';
import '../widgets/system/system.dart';

class WeightLogScreen extends StatelessWidget {
  final NutritionPresenter presenter;
  const WeightLogScreen({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) => _WeightLogBody(presenter: presenter),
    );
  }
}

// ─── Body ─────────────────────────────────────────────────────────────────────

class _WeightLogBody extends StatelessWidget {
  final NutritionPresenter presenter;
  const _WeightLogBody({required this.presenter});

  void _openAddSheet(BuildContext context) {
    AppBottomSheet.show(
      context: context,
      title: 'Log Weight',
      body: _AddEntrySheet(presenter: presenter),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = presenter.weightLog; // chronological

    return AppPageScaffold(
      title: 'Weight Log',
      padding: EdgeInsets.zero,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAddSheet(context),
        child: const Icon(Icons.add),
      ),
      body: entries.isEmpty
          ? _EmptyState(onAdd: () => _openAddSheet(context))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                _StatsRow(entries: entries),
                const SizedBox(height: 20),
                _TrendChart(entries: entries),
                const SizedBox(height: 20),
                _EntryList(entries: entries, presenter: presenter),
              ],
            ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.monitor_weight_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No entries yet',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to log your first weight',
              style: theme.textTheme.bodySmall?.copyWith(
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Stats Row ────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final List<WeightEntry> entries;
  const _StatsRow({required this.entries});

  @override
  Widget build(BuildContext context) {
    final latest = entries.last.weightKg;
    final totalChange = entries.length >= 2
        ? entries.last.weightKg - entries.first.weightKg
        : null;

    return Row(
      children: [
        Expanded(
          child: _StatTile(
            label: 'Current',
            value: '${latest.toStringAsFixed(1)} kg',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            label: 'Total Change',
            value: totalChange != null
                ? '${totalChange >= 0 ? '+' : ''}${totalChange.toStringAsFixed(1)} kg'
                : '—',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            label: 'Entries',
            value: entries.length.toString(),
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Trend Chart ──────────────────────────────────────────────────────────────

class _TrendChart extends StatelessWidget {
  final List<WeightEntry> entries;
  const _TrendChart({required this.entries});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gold = context.appColors.gold;

    // X-axis month labels
    final labels = _buildMonthLabels(entries);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Trend',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: CustomPaint(
              size: const Size(double.infinity, 160),
              painter: _TrendPainter(
                entries: entries,
                color: gold,
                gridColor:
                    theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                labelColor: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (labels.isNotEmpty) ...[
            const SizedBox(height: 4),
            SizedBox(
              height: 16,
              child: CustomPaint(
                size: const Size(double.infinity, 16),
                painter: _MonthLabelPainter(
                  entries: entries,
                  labels: labels,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<_MonthLabel> _buildMonthLabels(List<WeightEntry> entries) {
    if (entries.isEmpty) return [];
    final result = <_MonthLabel>[];
    final fmt = DateFormat('MMM');
    int? lastMonth;
    for (int i = 0; i < entries.length; i++) {
      final m = entries[i].loggedAt.month;
      if (m != lastMonth) {
        result
            .add(_MonthLabel(index: i, text: fmt.format(entries[i].loggedAt)));
        lastMonth = m;
      }
    }
    return result;
  }
}

class _MonthLabel {
  final int index;
  final String text;
  const _MonthLabel({required this.index, required this.text});
}

class _TrendPainter extends CustomPainter {
  final List<WeightEntry> entries;
  final Color color;
  final Color gridColor;
  final Color labelColor;

  const _TrendPainter({
    required this.entries,
    required this.color,
    required this.gridColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.length < 2) {
      // Single point — draw a dot
      _drawSinglePoint(canvas, size);
      return;
    }

    final weights = entries.map((e) => e.weightKg).toList();
    final minW = weights.reduce(math.min);
    final maxW = weights.reduce(math.max);
    final range = (maxW - minW).clamp(1.0, double.infinity);
    final pad = range * 0.25;
    final lo = minW - pad;
    final hi = maxW + pad;

    double toY(double kg) => size.height * (1 - (kg - lo) / (hi - lo));
    double toX(int i) => size.width * i / (entries.length - 1);

    // Grid lines (3 horizontal)
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    for (int g = 0; g <= 2; g++) {
      final y = size.height * g / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final points = List.generate(entries.length, (i) {
      return Offset(toX(i), toY(entries[i].weightKg));
    });

    // Area fill
    final areaPath = Path()..moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      final cp1 =
          Offset((points[i - 1].dx + points[i].dx) / 2, points[i - 1].dy);
      final cp2 = Offset((points[i - 1].dx + points[i].dx) / 2, points[i].dy);
      areaPath.cubicTo(
          cp1.dx, cp1.dy, cp2.dx, cp2.dy, points[i].dx, points[i].dy);
    }
    areaPath
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();

    canvas.drawPath(
      areaPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.22),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // Line
    final linePath = Path()..moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      final cp1 =
          Offset((points[i - 1].dx + points[i].dx) / 2, points[i - 1].dy);
      final cp2 = Offset((points[i - 1].dx + points[i].dx) / 2, points[i].dy);
      linePath.cubicTo(
          cp1.dx, cp1.dy, cp2.dx, cp2.dy, points[i].dx, points[i].dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = color.withValues(alpha: 0.85)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // First + last dots
    final dotFill = Paint()..color = color;
    final dotBorder = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final pt in [points.first, points.last]) {
      canvas.drawCircle(pt, 4.5, dotBorder);
      canvas.drawCircle(pt, 3.0, dotFill);
    }
  }

  void _drawSinglePoint(Canvas canvas, Size size) {
    final pt = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(pt, 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.entries != entries || old.color != color;
}

class _MonthLabelPainter extends CustomPainter {
  final List<WeightEntry> entries;
  final List<_MonthLabel> labels;
  final Color color;

  const _MonthLabelPainter({
    required this.entries,
    required this.labels,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.length < 2) return;
    final style = TextStyle(fontSize: 10, color: color);
    for (final lbl in labels) {
      final x = size.width * lbl.index / (entries.length - 1);
      final span = TextSpan(text: lbl.text, style: style);
      final tp = TextPainter(text: span, textDirection: ui.TextDirection.ltr)
        ..layout();
      tp.paint(canvas,
          Offset((x - tp.width / 2).clamp(0.0, size.width - tp.width), 0));
    }
  }

  @override
  bool shouldRepaint(_MonthLabelPainter old) => old.labels != labels;
}

// ─── Entry List ───────────────────────────────────────────────────────────────

class _EntryList extends StatelessWidget {
  final List<WeightEntry> entries;
  final NutritionPresenter presenter;

  const _EntryList({required this.entries, required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gold = context.appColors.gold;
    // newest first
    final reversed = entries.reversed.toList();

    return AppSection(
      title: 'All Entries',
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (int i = 0; i < reversed.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              _EntryRow(
                entry: reversed[i],
                prev: i + 1 < reversed.length ? reversed[i + 1] : null,
                gold: gold,
                onDelete: () => presenter.deleteWeight(reversed[i].id),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  final WeightEntry entry;
  final WeightEntry? prev;
  final Color gold;
  final VoidCallback onDelete;

  const _EntryRow({
    required this.entry,
    required this.prev,
    required this.gold,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final delta = prev != null ? entry.weightKg - prev!.weightKg : null;
    final isDown = delta != null && delta < 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.weightKg.toStringAsFixed(1)} kg',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('EEE, MMM d, yyyy').format(entry.loggedAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (delta != null)
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (isDown ? gold : theme.colorScheme.error)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDown ? gold : theme.colorScheme.error,
                ),
              ),
            ),
          GestureDetector(
            onTap: () => _confirmDelete(context),
            child: Icon(
              Icons.delete_outline,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    final fmt = DateFormat('EEE, MMM d, yyyy');
    showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text(
          '${entry.weightKg.toStringAsFixed(1)} kg on ${fmt.format(entry.loggedAt)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              onDelete();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ─── Add Entry Sheet ──────────────────────────────────────────────────────────

class _AddEntrySheet extends StatefulWidget {
  final NutritionPresenter presenter;
  const _AddEntrySheet({required this.presenter});

  @override
  State<_AddEntrySheet> createState() => _AddEntrySheetState();
}

class _AddEntrySheetState extends State<_AddEntrySheet> {
  late final TextEditingController _ctrl;
  late DateTime _date;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _date = DateTime.now();
    final latest = widget.presenter.latestWeight;
    _ctrl = TextEditingController(
      text: latest != null ? latest.weightKg.toStringAsFixed(1) : '',
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final kg = double.tryParse(_ctrl.text.trim());
    if (kg == null || kg <= 0 || kg > 500) return;
    setState(() => _saving = true);
    await widget.presenter.logWeightOnDate(kg, _date);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isToday = DateUtils.isSameDay(_date, DateTime.now());

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LabeledField(
          label: 'Weight (kg)',
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Date selector
        InkWell(
          onTap: _pickDate,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(
                color: theme.colorScheme.outline,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isToday
                        ? 'Today'
                        : DateFormat('EEE, MMM d, yyyy').format(_date),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ),
      ],
    );
  }
}
