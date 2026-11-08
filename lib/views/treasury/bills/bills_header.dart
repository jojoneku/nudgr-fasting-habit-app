import 'package:flutter/material.dart';
import 'package:intermittent_fasting/views/treasury/shared/month_stepper_pill.dart';
import 'package:intermittent_fasting/views/treasury/shared/month_year_picker.dart';

/// The in-page Bills header — a large left-aligned "Bills" title with the
/// month·year picker on the right. Replaces the shared Treasury app bar, which
/// is hidden on this tab so the reference's header layout can show.
class BillsHeader extends StatelessWidget {
  final String monthKey;
  final ValueChanged<String> onMonthChanged;

  const BillsHeader({
    super.key,
    required this.monthKey,
    required this.onMonthChanged,
  });

  Future<void> _openPicker(BuildContext context) async {
    final selected = await showMonthYearPicker(context, monthKey: monthKey);
    if (selected != null && selected != monthKey) onMonthChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canPop = Navigator.canPop(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(canPop ? 4 : 20, 8, 12, 4),
      child: Row(
        children: [
          if (canPop)
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back',
              onPressed: () => Navigator.maybePop(context),
            ),
          Expanded(
            child: Text(
              'Bills',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          MonthStepperPill(
            month: monthKey,
            onTap: () => _openPicker(context),
            onMonthChanged: onMonthChanged,
          ),
        ],
      ),
    );
  }
}
