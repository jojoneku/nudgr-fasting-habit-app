import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Compact pill showing the selected month + year (e.g. "Jun 2026") with a
/// caret, opening a month·year picker sheet on tap. Sits in the Bills app-bar
/// actions. Theme-token colors only, so it reads in dark and light.
class MonthYearPill extends StatelessWidget {
  /// 'YYYY-MM' key of the currently selected month.
  final String monthKey;

  /// Fires with the newly chosen 'YYYY-MM' key (only when it actually changes).
  final ValueChanged<String> onChanged;

  const MonthYearPill({
    super.key,
    required this.monthKey,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final date = DateTime.tryParse('$monthKey-01') ?? DateTime.now();
    final label = DateFormat('MMM yyyy').format(date);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => _openPicker(context),
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(999),
              border:
                  Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.keyboard_arrow_down_rounded,
                    size: 16, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _MonthYearPickerSheet(monthKey: monthKey),
    );
    if (selected != null && selected != monthKey) onChanged(selected);
  }
}

/// Bottom-sheet body: a year stepper over a 4×3 grid of months. Returns the
/// chosen 'YYYY-MM' key via `Navigator.pop`.
class _MonthYearPickerSheet extends StatefulWidget {
  final String monthKey;

  const _MonthYearPickerSheet({required this.monthKey});

  @override
  State<_MonthYearPickerSheet> createState() => _MonthYearPickerSheetState();
}

class _MonthYearPickerSheetState extends State<_MonthYearPickerSheet> {
  late int _year;

  @override
  void initState() {
    super.initState();
    final d = DateTime.tryParse('${widget.monthKey}-01') ?? DateTime.now();
    _year = d.year;
  }

  String _key(int y, int m) => '$y-${m.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton(
                    icon: Icon(Icons.chevron_left, color: cs.onSurfaceVariant),
                    onPressed: () => setState(() => _year--),
                  ),
                ),
                Text(
                  '$_year',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton(
                    icon: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                    onPressed: () => setState(() => _year++),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.9,
              children: [
                for (int m = 1; m <= 12; m++)
                  _MonthCell(
                    label: DateFormat('MMM').format(DateTime(_year, m)),
                    selected: _key(_year, m) == widget.monthKey,
                    onTap: () => Navigator.pop(context, _key(_year, m)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthCell extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MonthCell({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.primary : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? cs.onPrimary : cs.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
