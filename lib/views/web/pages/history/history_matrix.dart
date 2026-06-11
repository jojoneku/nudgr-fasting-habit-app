import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/presenters/treasury_history_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../../widgets/web_widgets.dart';

/// Short month header label: '2026-03' → "Mar '26".
String _monthShort(String monthKey) =>
    DateFormat("MMM ''yy").format(DateTime.parse('$monthKey-01'));

const double _labelW = 168;
const double _monthW = 96;
const double _totalW = 116;
const double _rowH = 40;

/// The sheet's "Historical Summary" top block: metric rows × month columns
/// (Income / Expenses / Net / Savings Rate / Cumulative). Horizontally
/// scrollable when there are many months.
class MonthMatrixTable extends StatelessWidget {
  final List<MonthHistoryColumn> columns;
  const MonthMatrixTable({super.key, required this.columns});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget cell(String text,
        {double width = _monthW,
        bool header = false,
        Color? color,
        Alignment align = Alignment.centerRight}) {
      return Container(
        width: width,
        height: _rowH,
        alignment: align,
        padding: const EdgeInsets.symmetric(horizontal: WebInsets.sm),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              (header ? theme.textTheme.labelMedium : theme.textTheme.bodySmall)
                  ?.copyWith(
            color: color ?? (header ? cs.onSurfaceVariant : cs.onSurface),
            fontWeight: header ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      );
    }

    Widget rowLabel(String text) =>
        cell(text, width: _labelW, align: Alignment.centerLeft, header: true);

    Widget dataRow(String label, Widget Function(MonthHistoryColumn) build) {
      return Row(children: [
        rowLabel(label),
        for (final c in columns) build(c),
      ]);
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.6))),
            ),
            child: Row(children: [
              cell('Month',
                  width: _labelW, header: true, align: Alignment.centerLeft),
              for (final c in columns) cell(_monthShort(c.month), header: true),
            ]),
          ),
          dataRow('Income',
              (c) => cell(formatPesoCompact(c.income), color: cs.tertiary)),
          dataRow('Expenses', (c) => cell(formatPesoCompact(c.expenses))),
          dataRow(
              'Net Cash Flow',
              (c) => cell(formatPesoCompact(c.net),
                  color: c.net < 0 ? cs.error : cs.tertiary)),
          dataRow(
              'Savings Rate',
              (c) => cell(
                  c.savingsRate == null ? '—' : formatPercent(c.savingsRate!))),
          Container(
            decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.6))),
            ),
            child: dataRow(
                'Cumulative Net',
                (c) => cell(formatPesoCompact(c.cumulativeNet),
                    color: c.cumulativeNet < 0 ? cs.error : cs.onSurface)),
          ),
        ],
      ),
    );
  }
}

/// The sheet's category breakdown grid: one row per category × month columns,
/// plus a Total column. Sorted by total spend (presenter-side).
class CategoryMatrixTable extends StatelessWidget {
  final List<String> months;
  final List<CategoryHistoryRow> rows;
  const CategoryMatrixTable(
      {super.key, required this.months, required this.rows});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget cell(String text,
        {double width = _monthW,
        bool header = false,
        Color? color,
        bool bold = false,
        Alignment align = Alignment.centerRight}) {
      return Container(
        width: width,
        height: _rowH,
        alignment: align,
        padding: const EdgeInsets.symmetric(horizontal: WebInsets.sm),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              (header ? theme.textTheme.labelMedium : theme.textTheme.bodySmall)
                  ?.copyWith(
            color: color ?? (header ? cs.onSurfaceVariant : cs.onSurface),
            fontWeight: (header || bold) ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.6))),
            ),
            child: Row(children: [
              cell('Category',
                  width: _labelW, header: true, align: Alignment.centerLeft),
              for (final m in months) cell(_monthShort(m), header: true),
              cell('Total', width: _totalW, header: true),
            ]),
          ),
          for (final r in rows)
            Row(children: [
              cell(r.name,
                  width: _labelW, align: Alignment.centerLeft, bold: false),
              for (final m in months)
                cell((r.byMonth[m] ?? 0) == 0
                    ? '—'
                    : formatPesoCompact(r.byMonth[m]!)),
              cell(formatPesoCompact(r.total), width: _totalW, bold: true),
            ]),
        ],
      ),
    );
  }
}
