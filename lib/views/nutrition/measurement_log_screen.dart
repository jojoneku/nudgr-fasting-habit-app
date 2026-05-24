import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/body_measurement_entry.dart';
import '../../models/nutrition_goals.dart';
import '../../presenters/nutrition_presenter.dart';
import '../widgets/system/system.dart';

class MeasurementLogScreen extends StatelessWidget {
  final NutritionPresenter presenter;
  const MeasurementLogScreen({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) => _MeasurementLogBody(presenter: presenter),
    );
  }
}

// ─── Body ─────────────────────────────────────────────────────────────────────

class _MeasurementLogBody extends StatelessWidget {
  final NutritionPresenter presenter;
  const _MeasurementLogBody({required this.presenter});

  void _openAddSheet(BuildContext context) {
    AppBottomSheet.show(
      context: context,
      title: 'Log Measurement',
      trailing: const _MeasureHelpButton(),
      body: _AddMeasurementSheet(presenter: presenter),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = presenter.measurementLog;

    return AppPageScaffold(
      title: 'Body Measurements',
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
                _StatsRow(presenter: presenter),
                const SizedBox(height: 20),
                _WaistTrendChart(entries: entries),
                const SizedBox(height: 20),
                _OtherSitesSummary(entries: entries, presenter: presenter),
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
              Icons.straighten_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No measurements yet',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Log a measurement to track body composition',
              textAlign: TextAlign.center,
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
  final NutritionPresenter presenter;
  const _StatsRow({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final entries = presenter.measurementLog;
    final latest = presenter.latestMeasurement;
    final waistEntries = entries.where((e) => e.waistCm != null).toList();
    final latestWaist = latest?.waistCm;
    final totalWaistChange = waistEntries.length >= 2
        ? waistEntries.last.waistCm! - waistEntries.first.waistCm!
        : null;
    final bf = presenter.estimatedBodyFatPercent;

    return Row(
      children: [
        Expanded(
          child: _StatTile(
            label: 'Latest Waist',
            value: latestWaist != null
                ? presenter.formatMeasurement(latestWaist)
                : '—',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            label: 'Total Change',
            value: totalWaistChange != null
                ? '${totalWaistChange >= 0 ? '+' : ''}${totalWaistChange.toStringAsFixed(1)} cm'
                : '—',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            label: 'Est. Body Fat',
            value: bf != null ? '~${bf.toStringAsFixed(0)} %' : '—',
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
        mainAxisSize: MainAxisSize.min,
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

// ─── Waist Trend Chart ────────────────────────────────────────────────────────

class _WaistTrendChart extends StatelessWidget {
  final List<BodyMeasurementEntry> entries;
  const _WaistTrendChart({required this.entries});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final waistPoints = entries.where((e) => e.waistCm != null).toList();
    if (waistPoints.length < 2) return const SizedBox.shrink();

    final labels = _buildMonthLabels(waistPoints);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Waist Trend',
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
              painter: _WaistTrendPainter(
                entries: waistPoints,
                color: theme.colorScheme.primary,
                gridColor:
                    theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
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
                  entries: waistPoints,
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

  List<_MonthLabel> _buildMonthLabels(List<BodyMeasurementEntry> entries) {
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

class _WaistTrendPainter extends CustomPainter {
  final List<BodyMeasurementEntry> entries;
  final Color color;
  final Color gridColor;

  const _WaistTrendPainter({
    required this.entries,
    required this.color,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.length < 2) return;
    final values = entries.map((e) => e.waistCm!).toList();
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final range = (maxV - minV).clamp(1.0, double.infinity);
    final pad = range * 0.25;
    final lo = minV - pad;
    final hi = maxV + pad;

    double toY(double v) => size.height * (1 - (v - lo) / (hi - lo));
    double toX(int i) => size.width * i / (entries.length - 1);

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    for (int g = 0; g <= 2; g++) {
      final y = size.height * g / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final points =
        List.generate(entries.length, (i) => Offset(toX(i), toY(values[i])));

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

  @override
  bool shouldRepaint(_WaistTrendPainter old) =>
      old.entries != entries || old.color != color;
}

class _MonthLabelPainter extends CustomPainter {
  final List<BodyMeasurementEntry> entries;
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

// ─── Other Sites Summary ──────────────────────────────────────────────────────

class _OtherSitesSummary extends StatelessWidget {
  final List<BodyMeasurementEntry> entries;
  final NutritionPresenter presenter;
  const _OtherSitesSummary({required this.entries, required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = entries.isNotEmpty ? entries.last : null;
    if (latest == null) return const SizedBox.shrink();
    final sites = <String>[];
    if (latest.hipsCm != null) {
      sites.add('Hips ${presenter.formatMeasurement(latest.hipsCm!)}');
    }
    if (latest.chestCm != null) {
      sites.add('Chest ${presenter.formatMeasurement(latest.chestCm!)}');
    }
    if (latest.bicepCm != null) {
      sites.add('Bicep ${presenter.formatMeasurement(latest.bicepCm!)}');
    }
    if (latest.thighCm != null) {
      sites.add('Thigh ${presenter.formatMeasurement(latest.thighCm!)}');
    }
    if (sites.isEmpty) return const SizedBox.shrink();

    return AppCard(
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(
          'Other Sites',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              sites.join('  ·  '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Entry List ───────────────────────────────────────────────────────────────

class _EntryList extends StatelessWidget {
  final List<BodyMeasurementEntry> entries;
  final NutritionPresenter presenter;
  const _EntryList({required this.entries, required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                presenter: presenter,
                onDelete: () => presenter.deleteMeasurement(reversed[i].id),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  final BodyMeasurementEntry entry;
  final BodyMeasurementEntry? prev;
  final NutritionPresenter presenter;
  final VoidCallback onDelete;

  const _EntryRow({
    required this.entry,
    required this.prev,
    required this.presenter,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final waist = entry.waistCm;
    final prevWaist = prev?.waistCm;
    final delta =
        (waist != null && prevWaist != null) ? waist - prevWaist : null;
    final isDown = delta != null && delta < 0;

    final extraSites = <String>[];
    if (entry.neckCm != null) {
      extraSites.add('Neck ${presenter.formatMeasurement(entry.neckCm!)}');
    }
    if (entry.hipsCm != null) {
      extraSites.add('Hips ${presenter.formatMeasurement(entry.hipsCm!)}');
    }
    if (entry.chestCm != null) {
      extraSites.add('Chest ${presenter.formatMeasurement(entry.chestCm!)}');
    }
    if (entry.bicepCm != null) {
      extraSites.add('Bicep ${presenter.formatMeasurement(entry.bicepCm!)}');
    }
    if (entry.thighCm != null) {
      extraSites.add('Thigh ${presenter.formatMeasurement(entry.thighCm!)}');
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (waist != null)
                  Text(
                    'Waist ${presenter.formatMeasurement(waist)}',
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
                if (extraSites.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    extraSites.join('  ·  '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.7),
                    ),
                  ),
                ],
                if (entry.notes != null && entry.notes!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.notes!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (delta != null)
            Container(
              margin: const EdgeInsets.only(right: 12, top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (isDown
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDown
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
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
    final waist = entry.waistCm;
    showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text(
          waist != null
              ? 'Waist ${waist.toStringAsFixed(1)} cm on '
                  '${DateFormat('EEE, MMM d, yyyy').format(entry.loggedAt)}'
              : DateFormat('EEE, MMM d, yyyy').format(entry.loggedAt),
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

// ─── Add Measurement Sheet ────────────────────────────────────────────────────

class _AddMeasurementSheet extends StatefulWidget {
  final NutritionPresenter presenter;
  const _AddMeasurementSheet({required this.presenter});

  @override
  State<_AddMeasurementSheet> createState() => _AddMeasurementSheetState();
}

class _AddMeasurementSheetState extends State<_AddMeasurementSheet> {
  final _waistCtrl = TextEditingController();
  final _neckCtrl = TextEditingController();
  final _hipsCtrl = TextEditingController();
  final _chestCtrl = TextEditingController();
  final _bicepCtrl = TextEditingController();
  final _thighCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  late DateTime _date;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _date = DateTime.now();
  }

  @override
  void dispose() {
    _waistCtrl.dispose();
    _neckCtrl.dispose();
    _hipsCtrl.dispose();
    _chestCtrl.dispose();
    _bicepCtrl.dispose();
    _thighCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  MeasurementUnit get _unit => widget.presenter.measurementUnit;

  String get _unitLabel => _unit == MeasurementUnit.imperial ? 'in' : 'cm';

  bool get _canSave {
    return [
      _waistCtrl,
      _neckCtrl,
      _hipsCtrl,
      _chestCtrl,
      _bicepCtrl,
      _thighCtrl,
    ].any((c) => double.tryParse(c.text.trim()) != null);
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

  double? _parse(TextEditingController ctrl) {
    final v = double.tryParse(ctrl.text.trim());
    if (v == null || v <= 0) return null;
    return widget.presenter.toStorageCm(v);
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final entry = BodyMeasurementEntry(
      id: BodyMeasurementEntry.generateId(),
      loggedAt: _date,
      waistCm: _parse(_waistCtrl),
      neckCm: _parse(_neckCtrl),
      hipsCm: _parse(_hipsCtrl),
      chestCm: _parse(_chestCtrl),
      bicepCm: _parse(_bicepCtrl),
      thighCm: _parse(_thighCtrl),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
    await widget.presenter.logMeasurement(entry);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isToday = DateUtils.isSameDay(_date, DateTime.now());

    return ListenableBuilder(
      listenable: widget.presenter,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Unit toggle
          Row(
            children: [
              Text(
                'Unit',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              _UnitPill(
                label: 'cm',
                selected: _unit == MeasurementUnit.metric,
                onTap: () =>
                    widget.presenter.setMeasurementUnit(MeasurementUnit.metric),
              ),
              const SizedBox(width: 8),
              _UnitPill(
                label: 'in',
                selected: _unit == MeasurementUnit.imperial,
                onTap: () => widget.presenter
                    .setMeasurementUnit(MeasurementUnit.imperial),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Primary: Waist
          TextField(
            controller: _waistCtrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Waist ($_unitLabel)',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // "Add more" expandable
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              'Add more sites',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            children: [
              _MeasurementField(
                ctrl: _neckCtrl,
                label: 'Neck ($_unitLabel)',
                note: 'Waist + Neck unlock body fat % estimation',
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 12),
              _MeasurementField(
                ctrl: _hipsCtrl,
                label: 'Hips ($_unitLabel)',
                note: 'Required for women\'s body fat % formula',
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 12),
              _MeasurementField(
                ctrl: _chestCtrl,
                label: 'Chest ($_unitLabel)',
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 12),
              _MeasurementField(
                ctrl: _bicepCtrl,
                label: 'Bicep ($_unitLabel)',
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 12),
              _MeasurementField(
                ctrl: _thighCtrl,
                label: 'Thigh ($_unitLabel)',
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesCtrl,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),

          const SizedBox(height: 12),

          // Date selector
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outline),
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
              onPressed: (_saving || !_canSave) ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MeasurementField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final String? note;
  final VoidCallback onChanged;

  const _MeasurementField({
    required this.ctrl,
    required this.label,
    this.note,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.next,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 4),
          Text(
            note!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }
}

class _UnitPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _UnitPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ─── Measurement help button ──────────────────────────────────────────────────

class _MeasureHelpButton extends StatelessWidget {
  const _MeasureHelpButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.help_outline,
        size: 20,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      tooltip: 'How to measure',
      onPressed: () => AppBottomSheet.show(
        context: context,
        title: 'How to measure',
        body: const _MeasurementGuideSheet(),
        isScrollControlled: true,
      ),
    );
  }
}

// ─── Measurement guide sheet ──────────────────────────────────────────────────

class _MeasurementGuideSheet extends StatelessWidget {
  const _MeasurementGuideSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 280,
            width: double.infinity,
            child: CustomPaint(
              painter: _BodyDiagramPainter(
                bodyColor: cs.onSurface.withValues(alpha: 0.22),
                waistColor: cs.primary,
                neckColor: cs.secondary,
                otherColor: cs.onSurfaceVariant.withValues(alpha: 0.7),
                hipColor: cs.tertiary,
              ),
            ),
          ),
          const SizedBox(height: 20),
          _GuideItem(
            color: cs.primary,
            label: 'Waist',
            description: 'At the belly button (navel), horizontal.',
          ),
          _GuideItem(
            color: cs.secondary,
            label: 'Neck',
            description:
                'Just below the larynx (Adam\'s apple). Keep tape horizontal — '
                'this unlocks body fat % estimation together with waist.',
          ),
          _GuideItem(
            color: cs.tertiary,
            label: 'Hips  ♀',
            description: 'Around the widest part of the hips and glutes. '
                'Required for women\'s body fat % formula.',
          ),
          _GuideItem(
            color: cs.onSurfaceVariant.withValues(alpha: 0.8),
            label: 'Chest',
            description: 'Around the fullest part of the chest.',
          ),
          _GuideItem(
            color: cs.onSurfaceVariant.withValues(alpha: 0.8),
            label: 'Bicep',
            description: 'Around the largest part of the upper arm. '
                'Stay consistent — always flexed or always relaxed.',
          ),
          _GuideItem(
            color: cs.onSurfaceVariant.withValues(alpha: 0.8),
            label: 'Thigh',
            description: 'Around the largest part of the upper thigh.',
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _GuideItem extends StatelessWidget {
  final Color color;
  final String label;
  final String description;
  const _GuideItem({
    required this.color,
    required this.label,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
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

// ─── Body diagram painter ─────────────────────────────────────────────────────

class _BodyDiagramPainter extends CustomPainter {
  final Color bodyColor;
  final Color waistColor;
  final Color neckColor;
  final Color otherColor;
  final Color hipColor;

  const _BodyDiagramPainter({
    required this.bodyColor,
    required this.waistColor,
    required this.neckColor,
    required this.otherColor,
    required this.hipColor,
  });

  static const double _dw = 200;
  static const double _dh = 320;
  static const double _cx = 100; // figure center-x in design space

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / _dw;
    final sy = size.height / _dh;
    final sc = math.min(sx, sy);

    Offset p(double x, double y) => Offset(x * sx, y * sy);

    final bodyPaint = Paint()
      ..color = bodyColor
      ..strokeWidth = sc * 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // ── HEAD ─────────────────────────────────────────────────────────────────
    canvas.drawCircle(p(_cx, 22), sc * 17, bodyPaint);

    // ── NECK ─────────────────────────────────────────────────────────────────
    canvas.drawLine(p(_cx - 7, 39), p(_cx - 7, 53), bodyPaint);
    canvas.drawLine(p(_cx + 7, 39), p(_cx + 7, 53), bodyPaint);

    // ── SHOULDERS ────────────────────────────────────────────────────────────
    canvas.drawLine(p(_cx - 7, 52), p(_cx - 38, 69), bodyPaint);
    canvas.drawLine(p(_cx + 7, 52), p(_cx + 38, 69), bodyPaint);

    // ── ARMS (open rectangles) ────────────────────────────────────────────────
    final leftArm = Path()
      ..moveTo(p(_cx - 38, 69).dx, p(_cx - 38, 69).dy)
      ..lineTo(p(_cx - 38, 156).dx, p(_cx - 38, 156).dy)
      ..lineTo(p(_cx - 23, 156).dx, p(_cx - 23, 156).dy)
      ..lineTo(p(_cx - 22, 69).dx, p(_cx - 22, 69).dy);
    canvas.drawPath(leftArm, bodyPaint);

    final rightArm = Path()
      ..moveTo(p(_cx + 38, 69).dx, p(_cx + 38, 69).dy)
      ..lineTo(p(_cx + 38, 156).dx, p(_cx + 38, 156).dy)
      ..lineTo(p(_cx + 23, 156).dx, p(_cx + 23, 156).dy)
      ..lineTo(p(_cx + 22, 69).dx, p(_cx + 22, 69).dy);
    canvas.drawPath(rightArm, bodyPaint);

    // ── TORSO SIDES ──────────────────────────────────────────────────────────
    // Left: armpit → chest → waist → hip
    canvas.drawLine(p(_cx - 22, 69), p(_cx - 21, 90), bodyPaint);
    canvas.drawLine(p(_cx - 21, 90), p(_cx - 20, 142), bodyPaint);
    canvas.drawLine(p(_cx - 20, 142), p(_cx - 27, 172), bodyPaint);

    // Right: mirror
    canvas.drawLine(p(_cx + 22, 69), p(_cx + 21, 90), bodyPaint);
    canvas.drawLine(p(_cx + 21, 90), p(_cx + 20, 142), bodyPaint);
    canvas.drawLine(p(_cx + 20, 142), p(_cx + 27, 172), bodyPaint);

    // ── LEGS ─────────────────────────────────────────────────────────────────
    // Left
    canvas.drawLine(p(_cx - 27, 172), p(_cx - 27, 300), bodyPaint);
    canvas.drawLine(p(_cx - 10, 175), p(_cx - 10, 300), bodyPaint);
    canvas.drawLine(p(_cx - 27, 300), p(_cx - 10, 300), bodyPaint);

    // Right
    canvas.drawLine(p(_cx + 27, 172), p(_cx + 27, 300), bodyPaint);
    canvas.drawLine(p(_cx + 10, 175), p(_cx + 10, 300), bodyPaint);
    canvas.drawLine(p(_cx + 10, 300), p(_cx + 27, 300), bodyPaint);

    // ── MEASUREMENT LINES ────────────────────────────────────────────────────
    // Neck: y=46
    _measLine(canvas, size, sc, 46, _cx - 42, _cx + 42, neckColor);
    // Chest: y=88
    _measLine(canvas, size, sc, 88, _cx - 40, _cx + 40, otherColor);
    // Bicep: y=112 — arms only (two segments)
    _measLineSplit(canvas, size, sc, 112, _cx - 39, _cx - 22, _cx + 22,
        _cx + 39, otherColor);
    // Waist: y=142 — primary, glow
    _measLineGlow(canvas, size, sc, 142, _cx - 42, _cx + 42, waistColor);
    // Hips: y=172
    _measLine(canvas, size, sc, 172, _cx - 45, _cx + 45, hipColor);
    // Thigh: y=222 — legs only
    _measLineSplit(canvas, size, sc, 222, _cx - 27, _cx - 10, _cx + 10,
        _cx + 27, otherColor);
  }

  void _measLine(Canvas canvas, Size size, double sc, double dy, double x1,
      double x2, Color color) {
    final sx = size.width / _dw;
    final sy = size.height / _dh;
    final paint = Paint()
      ..color = color
      ..strokeWidth = sc * 0.9
      ..style = PaintingStyle.stroke;
    _dashed(
        canvas, Offset(x1 * sx, dy * sy), Offset(x2 * sx, dy * sy), paint, sc);
  }

  void _measLineGlow(Canvas canvas, Size size, double sc, double dy, double x1,
      double x2, Color color) {
    final sx = size.width / _dw;
    final sy = size.height / _dh;
    // Glow pass
    canvas.drawLine(
      Offset(x1 * sx, dy * sy),
      Offset(x2 * sx, dy * sy),
      Paint()
        ..color = color.withValues(alpha: 0.28)
        ..strokeWidth = sc * 7
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    _measLine(canvas, size, sc, dy, x1, x2, color);
  }

  void _measLineSplit(Canvas canvas, Size size, double sc, double dy,
      double lx1, double lx2, double rx1, double rx2, Color color) {
    final sx = size.width / _dw;
    final sy = size.height / _dh;
    final paint = Paint()
      ..color = color
      ..strokeWidth = sc * 0.9
      ..style = PaintingStyle.stroke;
    _dashed(canvas, Offset(lx1 * sx, dy * sy), Offset(lx2 * sx, dy * sy), paint,
        sc);
    _dashed(canvas, Offset(rx1 * sx, dy * sy), Offset(rx2 * sx, dy * sy), paint,
        sc);
  }

  void _dashed(
      Canvas canvas, Offset start, Offset end, Paint paint, double sc) {
    final total = (end - start).distance;
    if (total <= 0) return;
    final dir = (end - start) / total;
    final dash = sc * 4.0;
    final gap = sc * 3.0;
    double drawn = 0;
    bool isDash = true;
    while (drawn < total) {
      final len = math.min(isDash ? dash : gap, total - drawn);
      if (isDash) {
        canvas.drawLine(
            start + dir * drawn, start + dir * (drawn + len), paint);
      }
      drawn += len;
      isDash = !isDash;
    }
  }

  @override
  bool shouldRepaint(_BodyDiagramPainter old) =>
      old.bodyColor != bodyColor || old.waistColor != waistColor;
}
