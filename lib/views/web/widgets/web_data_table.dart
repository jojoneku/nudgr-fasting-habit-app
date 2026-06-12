import 'package:flutter/material.dart';
import '../design/web_breakpoints.dart';

/// Column definition for [WebDataTable].
class WebColumn<T> {
  final String label;

  /// Right-aligns the header + cells (use for money/number columns).
  final bool numeric;

  /// Flex weight across the row width.
  final int flex;

  /// Builds the cell content for [row]. Keep it presentational — formatting and
  /// math belong in the presenter, not here.
  final Widget Function(BuildContext context, T row) cell;

  const WebColumn({
    required this.label,
    required this.cell,
    this.numeric = false,
    this.flex = 1,
  });
}

/// An optional grouping of rows under a band header with an optional trailing
/// summary widget (e.g. month subtotals — the sheet's "monthly totals on top").
class WebTableSection<T> {
  final String? title;
  final Widget? trailing;
  final List<T> rows;
  const WebTableSection({this.title, this.trailing, required this.rows});
}

/// A dense, sheet-like table: sticky header, hover row highlight, right-aligned
/// numerics, optional section bands, and row tap. The reusable grid behind the
/// web Ledger / Bills / Budget / History / Cart tables (Plan 050).
///
/// Provide EITHER [rows] (flat) OR [sections] (grouped).
class WebDataTable<T> extends StatelessWidget {
  final List<WebColumn<T>> columns;
  final List<T>? rows;
  final List<WebTableSection<T>>? sections;
  final void Function(T row)? onRowTap;
  final String emptyLabel;

  const WebDataTable({
    super.key,
    required this.columns,
    this.rows,
    this.sections,
    this.onRowTap,
    this.emptyLabel = 'No records',
  }) : assert(rows != null || sections != null,
            'Provide either rows or sections');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final secs = sections ?? [WebTableSection<T>(rows: rows ?? const [])];
    final isEmpty = secs.every((s) => s.rows.isEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _HeaderRow<T>(columns: columns),
        if (isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: WebInsets.xxl),
            child: Center(
              child: Text(emptyLabel,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant)),
            ),
          )
        else
          for (final section in secs) ...[
            if (section.title != null || section.trailing != null)
              _SectionBand(title: section.title, trailing: section.trailing),
            for (var i = 0; i < section.rows.length; i++)
              _BodyRow<T>(
                columns: columns,
                row: section.rows[i],
                zebra: i.isOdd,
                onTap: onRowTap,
              ),
          ],
      ],
    );
  }
}

class _HeaderRow<T> extends StatelessWidget {
  final List<WebColumn<T>> columns;
  const _HeaderRow({required this.columns});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final style = theme.textTheme.labelMedium?.copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: WebInsets.md, vertical: WebInsets.md),
      decoration: BoxDecoration(
        border: Border(
            bottom:
                BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6))),
      ),
      child: Row(
        children: [
          for (final c in columns)
            Expanded(
              flex: c.flex,
              child: Text(
                c.label,
                style: style,
                textAlign: c.numeric ? TextAlign.right : TextAlign.left,
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionBand extends StatelessWidget {
  final String? title;
  final Widget? trailing;
  const _SectionBand({this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: WebInsets.md, vertical: WebInsets.sm),
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Row(
        children: [
          Expanded(
            child: Text(title ?? '',
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _BodyRow<T> extends StatefulWidget {
  final List<WebColumn<T>> columns;
  final T row;
  final bool zebra;
  final void Function(T row)? onTap;
  const _BodyRow({
    required this.columns,
    required this.row,
    required this.zebra,
    this.onTap,
  });

  @override
  State<_BodyRow<T>> createState() => _BodyRowState<T>();
}

class _BodyRowState<T> extends State<_BodyRow<T>> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tappable = widget.onTap != null;

    Color? bg;
    if (_hover && tappable) {
      bg = cs.primary.withValues(alpha: 0.06);
    } else if (widget.zebra) {
      bg = cs.surfaceContainerHighest.withValues(alpha: 0.25);
    }

    return MouseRegion(
      cursor: tappable ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: tappable ? () => widget.onTap!(widget.row) : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: WebInsets.md, vertical: WebInsets.md),
          decoration: BoxDecoration(
            color: bg,
            border: Border(
              bottom:
                  BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
            ),
          ),
          child: Row(
            children: [
              for (final c in widget.columns)
                Expanded(
                  flex: c.flex,
                  child: Align(
                    alignment: c.numeric
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: DefaultTextStyle.merge(
                      style: theme.textTheme.bodyMedium,
                      child: c.cell(context, widget.row),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
