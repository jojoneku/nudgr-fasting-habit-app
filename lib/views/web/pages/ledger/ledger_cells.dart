import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

import '../../design/web_breakpoints.dart';
import '../../design/web_constants.dart';
import '../../widgets/web_searchable_dropdown.dart';
import 'ledger_filters.dart';

/// Hoisted so the per-row date cells don't allocate a new [DateFormat] on
/// every build. (Plan 052 P10)
final DateFormat kLedgerMonthDayFmt = DateFormat('MMM d');

// Fixed, non-resizable column widths (px). The selection checkbox and the
// trailing action column (hover-delete before v2, the ⋯ menu in v2) never
// resize.
const double kLedgerCheckWidth = 44;
const double kLedgerTrailingWidth = 48;

/// Minimum width the flexible Description column is allowed to shrink to before
/// the grid starts scrolling horizontally.
const double kLedgerDescMinWidth = 200;

/// Columns the user can drag-resize from the header.
enum LedgerResizableCol { date, account, category, inflow, outflow, acctBal }

/// Mutable per-column widths. The Description column is flexible (it stretches
/// to fill leftover space) so it isn't tracked here. Defaults reclaim the space
/// freed by removing the old Running + Notes columns and hand it to Account and
/// Category, which were truncating long names. (Ledger UX overhaul PR1)
///
/// Shared by both Ledger pages; the v2 page passes compact initial widths so
/// its grid fits the 1200 px content column without a horizontal scroll.
class LedgerColWidths {
  double date;
  double account;
  double category;
  double inflow;
  double outflow;
  double acctBal;

  LedgerColWidths({
    this.date = 118,
    this.account = 210,
    this.category = 210,
    this.inflow = 124,
    this.outflow = 124,
    this.acctBal = 150,
  });

  double get fixedSum =>
      kLedgerCheckWidth +
      date +
      account +
      category +
      inflow +
      outflow +
      acctBal +
      kLedgerTrailingWidth;

  void resize(LedgerResizableCol col, double delta) {
    switch (col) {
      case LedgerResizableCol.date:
        date = (date + delta).clamp(80.0, 360.0);
      case LedgerResizableCol.account:
        account = (account + delta).clamp(110.0, 420.0);
      case LedgerResizableCol.category:
        category = (category + delta).clamp(110.0, 420.0);
      case LedgerResizableCol.inflow:
        inflow = (inflow + delta).clamp(90.0, 260.0);
      case LedgerResizableCol.outflow:
        outflow = (outflow + delta).clamp(90.0, 260.0);
      case LedgerResizableCol.acctBal:
        acctBal = (acctBal + delta).clamp(100.0, 300.0);
    }
  }
}

/// A read-only grid cell: fixed [width], 12/8 padding, left- or right-aligned.
Widget ledgerReadCell({
  required double width,
  required Widget child,
  bool right = false,
}) =>
    SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WebInsets.md,
          vertical: WebInsets.sm,
        ),
        child: Align(
          alignment: right ? Alignment.centerRight : Alignment.centerLeft,
          child: child,
        ),
      ),
    );

/// One sortable, optionally drag-resizable header cell of the Ledger grid.
class LedgerHeaderCell extends StatelessWidget {
  final String label;
  final double width;
  final WebLedgerSortKey? sortKey;
  final bool active;
  final int dir;
  final bool right;
  final VoidCallback? onSort;

  /// When non-null, a draggable divider on the cell's right edge resizes the
  /// column by the horizontal drag delta.
  final ValueChanged<double>? onResize;
  const LedgerHeaderCell({
    super.key,
    required this.label,
    required this.width,
    required this.sortKey,
    required this.active,
    required this.dir,
    required this.right,
    required this.onSort,
    this.onResize,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: active ? cs.onSurface : cs.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        );
    final chevron = onSort == null
        ? const SizedBox.shrink()
        : Icon(
            Icons.expand_more_rounded,
            size: 13,
            color: active
                ? cs.onSurface
                : cs.onSurfaceVariant.withValues(alpha: 0.35),
          );
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (right && onSort != null)
          Transform.rotate(
            angle: active && dir < 0 ? 3.14159 : 0,
            child: chevron,
          ),
        Flexible(
          child: Text(
            label.toUpperCase(),
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (!right && onSort != null)
          Transform.rotate(
            angle: active && dir < 0 ? 3.14159 : 0,
            child: chevron,
          ),
      ],
    );
    return SizedBox(
      width: width,
      child: Stack(
        children: [
          InkWell(
            onTap: onSort,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: WebInsets.md,
                vertical: WebInsets.md,
              ),
              child: Align(
                alignment: right ? Alignment.centerRight : Alignment.centerLeft,
                child: content,
              ),
            ),
          ),
          if (onResize != null)
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragUpdate: (d) => onResize!(d.delta.dx),
                  child: Center(
                    child: Container(
                      width: 1,
                      height: 16,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      color: cs.outlineVariant.withValues(alpha: 0.6),
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

/// The 16 px grid checkbox, inside a [kWebHitTarget]-square hit area.
class LedgerCheck extends StatelessWidget {
  final bool on;
  final VoidCallback onTap;
  const LedgerCheck({super.key, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      checked: on,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: kWebHitTarget,
          height: kWebHitTarget,
          child: Center(
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: on ? cs.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: on ? cs.primary : cs.outline,
                  width: 1.5,
                ),
              ),
              child: on
                  ? Icon(Icons.check_rounded, size: 11, color: cs.onPrimary)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Editable cell primitives ─────────────────────────────────────────────────────

/// An inline text cell: looks like plain text at rest, grows a focus ring when
/// edited, commits on blur or Enter, reverts on Esc.
class LedgerInlineText extends StatefulWidget {
  final double width;
  final String initialValue;
  final String? hintText;
  final bool bold;
  final bool enabled;
  final ValueChanged<String> onCommit;

  /// Fired live on every keystroke (used by the draft row so its value is
  /// current even if the field hasn't blurred when "Add row" is clicked).
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmit;
  const LedgerInlineText({
    super.key,
    required this.width,
    required this.initialValue,
    this.hintText,
    this.bold = false,
    this.enabled = true,
    required this.onCommit,
    this.onChanged,
    this.onSubmit,
  });

  @override
  State<LedgerInlineText> createState() => _LedgerInlineTextState();
}

class _LedgerInlineTextState extends State<LedgerInlineText> {
  late final TextEditingController _c;
  late final FocusNode _f;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initialValue);
    _f = FocusNode()..addListener(_onFocus);
  }

  void _onFocus() {
    if (!_f.hasFocus && _focused) widget.onCommit(_c.text);
    setState(() => _focused = _f.hasFocus);
  }

  @override
  void didUpdateWidget(LedgerInlineText old) {
    super.didUpdateWidget(old);
    // The row now persists across commits (keyed on id), so sync the controller
    // when the external value changes — but never clobber active typing. (C3)
    if (!_focused && widget.initialValue != _c.text) {
      _c.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _f.removeListener(_onFocus);
    _f.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final style = theme.textTheme.bodySmall?.copyWith(
      fontWeight: widget.bold ? FontWeight.w600 : FontWeight.w400,
      color: cs.onSurface,
    );
    if (!widget.enabled) {
      return ledgerReadCell(
        width: widget.width,
        child: Text(
          widget.initialValue.isEmpty
              ? (widget.hintText ?? '')
              : widget.initialValue,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      );
    }
    return SizedBox(
      width: widget.width,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WebInsets.sm,
          vertical: WebInsets.xs,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: _focused
                ? cs.surfaceContainerHighest.withValues(alpha: 0.7)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            // Border width is always reserved (transparent at rest) so focusing
            // never shifts the row's layout; the focus ring is a softened
            // primary rather than a hard solid box. (matches reference ring)
            border: Border.all(
              color: _focused
                  ? cs.primary.withValues(alpha: 0.55)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: WebInsets.sm,
            vertical: 4,
          ),
          child: Focus(
            canRequestFocus: false,
            onKeyEvent: (_, event) {
              // Esc reverts to the original value, then blurs (the blur commit
              // becomes a no-op). (Plan 052 U5)
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                _c.text = widget.initialValue;
                _f.unfocus();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TextField(
              controller: _c,
              focusNode: _f,
              style: style,
              maxLines: 1,
              textAlignVertical: TextAlignVertical.center,
              onChanged: widget.onChanged,
              onSubmitted: (_) {
                widget.onCommit(_c.text);
                widget.onSubmit?.call();
              },
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: widget.hintText,
                hintStyle: style?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An inline money cell. Shows `₱1,000.00` at rest (blank when zero), the raw
/// number while focused; commits on blur or Enter, reverts on Esc or when
/// cleared to zero.
class LedgerAmountCell extends StatefulWidget {
  final double width;
  final double value;
  final Color color;
  final bool enabled;
  final ValueChanged<double> onCommit;

  /// Fired live on every keystroke (used by the draft row so its value is
  /// current even if the field hasn't blurred when "Add row" is clicked).
  final ValueChanged<double>? onChanged;
  final VoidCallback? onSubmit;
  const LedgerAmountCell({
    super.key,
    required this.width,
    required this.value,
    required this.color,
    this.enabled = true,
    required this.onCommit,
    this.onChanged,
    this.onSubmit,
  });

  @override
  State<LedgerAmountCell> createState() => _LedgerAmountCellState();
}

class _LedgerAmountCellState extends State<LedgerAmountCell> {
  late final TextEditingController _c;
  late final FocusNode _f;
  bool _focused = false;

  // Peso-prefixed, two-decimal, comma-grouped formatting so amounts line up
  // like a ledger (e.g. ₱1,000.00). Blank when zero so empty cells stay clean.
  String _display(double v) => v <= 0 ? '' : formatPeso(v);

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: _display(widget.value));
    _f = FocusNode()..addListener(_onFocus);
  }

  void _onFocus() {
    if (_f.hasFocus) {
      // Show raw editable number.
      _c.text = widget.value <= 0 ? '' : _trimZeros(widget.value);
      _c.selection = TextSelection(baseOffset: 0, extentOffset: _c.text.length);
    } else {
      final v = _parse();
      widget.onCommit(v);
      // If the parse came back as 0 (field cleared) the amount-edit rule
      // ignores it — fall back to the current value instead of showing a blank
      // cell. didUpdateWidget reconciles once the parent rebuilds. (C2)
      _c.text = _display(v > 0 ? v : widget.value);
    }
    setState(() => _focused = _f.hasFocus);
  }

  @override
  void didUpdateWidget(LedgerAmountCell old) {
    super.didUpdateWidget(old);
    if (!_focused && old.value != widget.value) {
      _c.text = _display(widget.value);
    }
  }

  double _parse() {
    final raw = _c.text.replaceAll(',', '').replaceAll('₱', '').trim();
    return double.tryParse(raw) ?? 0;
  }

  String _trimZeros(double v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  }

  @override
  void dispose() {
    _f.removeListener(_onFocus);
    _f.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final style = theme.textTheme.bodySmall?.copyWith(
      color: widget.color,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    if (!widget.enabled) {
      return ledgerReadCell(
        width: widget.width,
        right: true,
        child: Text(
          widget.value <= 0 ? '—' : _display(widget.value),
          textAlign: TextAlign.right,
          style: style,
        ),
      );
    }
    return SizedBox(
      width: widget.width,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WebInsets.sm,
          vertical: WebInsets.xs,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: _focused
                ? cs.surfaceContainerHighest.withValues(alpha: 0.7)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            // Border width always reserved so focus never shifts layout;
            // softened primary ring rather than a hard box.
            border: Border.all(
              color: _focused
                  ? cs.primary.withValues(alpha: 0.55)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: WebInsets.sm,
            vertical: 4,
          ),
          child: Focus(
            canRequestFocus: false,
            onKeyEvent: (_, event) {
              // Esc reverts to the current value, then blurs. (Plan 052 U5)
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                _c.text = widget.value <= 0 ? '' : _trimZeros(widget.value);
                _f.unfocus();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TextField(
              controller: _c,
              focusNode: _f,
              style: style,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
              ],
              onChanged: (_) => widget.onChanged?.call(_parse()),
              onSubmitted: (_) {
                widget.onCommit(_parse());
                widget.onSubmit?.call();
              },
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: '—',
                hintStyle: style?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline account picker (searchable). [showDots] renders each account's
/// color swatch in the field and the list; the v2 grid turns it off because
/// it draws the account tile beside the field instead.
class LedgerAccountCell extends StatelessWidget {
  final double width;
  final String? value;
  final List<FinancialAccount> accounts;
  final ValueChanged<String> onChanged;
  final String hintText;
  final bool showDots;
  const LedgerAccountCell({
    super.key,
    required this.width,
    required this.value,
    required this.accounts,
    required this.onChanged,
    this.hintText = 'Account',
    this.showDots = true,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final entries = [
      for (var i = 0; i < accounts.length; i++)
        WebDropdownEntry<String>(
          value: accounts[i].id,
          label: accounts[i].name,
          dotColor: showDots
              ? resolveSliceColor(
                  accounts[i].colorHex,
                  i,
                  brightness: brightness,
                )
              : null,
        ),
    ];
    final hasValue = accounts.any((a) => a.id == value);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: WebInsets.sm,
        vertical: WebInsets.xs,
      ),
      child: WebSearchableDropdown<String>(
        width: width - WebInsets.sm * 2,
        value: hasValue ? value : null,
        entries: entries,
        hintText: hintText,
        isDense: true,
        onChanged: onChanged,
      ),
    );
  }
}

/// A transfer leg's account, read-only (with its color dot).
class LedgerTransferAccountCell extends StatelessWidget {
  final double width;
  final TransactionRecord txn;
  final List<FinancialAccount> accounts;

  /// A leading widget (the v2 account tile) drawn before the name; replaces
  /// the dot when given.
  final Widget? leading;

  const LedgerTransferAccountCell({
    super.key,
    required this.width,
    required this.txn,
    required this.accounts,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    // A transfer is stored as two legs sharing a [transferGroupId]. Each leg
    // touches exactly one account: the outflow leg debits its [accountId], the
    // inflow leg credits its [accountId]. So we show only the leg's own account
    // — the row's inflow/outflow column already tells you the direction, and
    // pairing the two rows shows the full "A → B" picture without cramming both
    // accounts (and an arrow) into every cell.
    final acct = accounts.where((a) => a.id == txn.accountId).firstOrNull;
    final dot = acct == null
        ? null
        : resolveSliceColor(
            acct.colorHex,
            accounts.indexOf(acct),
            brightness: brightness,
          );

    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WebInsets.md,
          vertical: WebInsets.xs,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kWebHitTarget),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: WebInsets.sm),
                ] else if (dot != null) ...[
                  WebDot(color: dot),
                  const SizedBox(width: WebInsets.xs),
                ],
                Flexible(
                  child: Text(
                    acct?.name ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline category picker (searchable, with the category's color dot).
class LedgerCategoryCell extends StatelessWidget {
  final double width;
  final String? value;
  final List<FinanceCategory> categories;
  final Color Function(FinanceCategory?) colorFor;
  final ValueChanged<String> onChanged;
  final String hintText;
  const LedgerCategoryCell({
    super.key,
    required this.width,
    required this.value,
    required this.categories,
    required this.colorFor,
    required this.onChanged,
    this.hintText = 'Category',
  });

  @override
  Widget build(BuildContext context) {
    final entries = [
      for (final c in categories)
        WebDropdownEntry<String>(
          value: c.id,
          label: c.name,
          dotColor: colorFor(c),
        ),
    ];
    final hasValue = categories.any((c) => c.id == value);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: WebInsets.sm,
        vertical: WebInsets.xs,
      ),
      child: WebSearchableDropdown<String>(
        width: width - WebInsets.sm * 2,
        value: hasValue ? value : null,
        entries: entries,
        hintText: hintText,
        isDense: true,
        onChanged: onChanged,
      ),
    );
  }
}

/// Inline date cell: click opens a date picker.
class LedgerDateCell extends StatelessWidget {
  final double width;
  final DateTime date;
  final bool enabled;
  final ValueChanged<DateTime> onChanged;
  const LedgerDateCell({
    super.key,
    required this.width,
    required this.date,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = kLedgerMonthDayFmt.format(date);
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall,
    );
    if (!enabled) return ledgerReadCell(width: width, child: text);
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: date,
            firstDate: kWebDateRange.start,
            lastDate: kWebDateRange.end,
          );
          if (picked != null) onChanged(picked);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WebInsets.md,
            vertical: WebInsets.sm,
          ),
          child: Align(alignment: Alignment.centerLeft, child: text),
        ),
      ),
    );
  }
}
