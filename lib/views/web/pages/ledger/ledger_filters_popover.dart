import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/utils/app_radii.dart';
import 'package:intermittent_fasting/views/web/web_keys.dart';

import '../../design/web_breakpoints.dart';
import '../../design/web_constants.dart';
import '../../widgets/web_searchable_dropdown.dart';
import 'ledger_cells.dart';
import 'ledger_filters.dart';

/// Shared height for every Ledger toolbar control (Filters & Sort, search,
/// Add Transaction, active chips) so they line up at exactly the same height.
const double kLedgerControlHeight = 40;

/// The "Filters & Sort" trigger button + popover panel, anchored with an
/// [OverlayPortal] so interacting with the inner controls never closes it.
///
/// Moved out of `web_ledger_page.dart` in Plan 063 Phase 4 so the pre-v2 page
/// and `WebLedgerPageV2` open the very same popover. Behaviour is unchanged;
/// [label] lets the v2 toolbar use the canvas wording ("Filters & sort").
class LedgerFiltersPopover extends StatefulWidget {
  final List<FinancialAccount> accounts;
  final List<FinanceCategory> categories;
  final Set<String> accountIds;
  final Set<String> categoryIds;
  final WebLedgerType type;
  final DateTime? fromDate;
  final DateTime? toDate;
  final WebLedgerSortKey? sortKey;
  final int sortDir;
  final int activeCount;

  /// Toggles one account/category in the multi-select; null clears that filter.
  final ValueChanged<String?> onAccount;
  final ValueChanged<String?> onCategory;
  final ValueChanged<WebLedgerType> onType;
  final ValueChanged<DateTime?> onFromDate;
  final ValueChanged<DateTime?> onToDate;
  final ValueChanged<WebLedgerSortOption?> onSort;
  final VoidCallback onClear;
  final String label;

  const LedgerFiltersPopover({
    super.key,
    required this.accounts,
    required this.categories,
    required this.accountIds,
    required this.categoryIds,
    required this.type,
    required this.fromDate,
    required this.toDate,
    required this.sortKey,
    required this.sortDir,
    required this.activeCount,
    required this.onAccount,
    required this.onCategory,
    required this.onType,
    required this.onFromDate,
    required this.onToDate,
    required this.onSort,
    required this.onClear,
    this.label = 'Filters & Sort',
  });

  @override
  State<LedgerFiltersPopover> createState() => _LedgerFiltersPopoverState();
}

class _LedgerFiltersPopoverState extends State<LedgerFiltersPopover> {
  final _controller = OverlayPortalController();
  final _link = LayerLink();

  WebLedgerSortOption? get _activeSortOption =>
      ledgerSortPresetFor(widget.sortKey, widget.sortDir);

  Future<void> _pickDate(BuildContext context, bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? widget.fromDate : widget.toDate) ?? DateTime.now(),
      firstDate: kWebDateRange.start,
      lastDate: kWebDateRange.end,
    );
    if (picked == null) return;
    isFrom ? widget.onFromDate(picked) : widget.onToDate(picked);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = widget.activeCount > 0;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _controller,
        overlayChildBuilder: _buildPanel,
        child: SizedBox(
          height: kLedgerControlHeight,
          child: OutlinedButton.icon(
            key: WebKeys.ledgerFiltersButton,
            onPressed: _controller.toggle,
            icon: const Icon(Icons.tune_rounded, size: 16),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.label),
                if (active) ...[
                  const SizedBox(width: WebInsets.sm),
                  Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '${widget.activeCount}',
                      style: TextStyle(
                        color: cs.onPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: WebInsets.xs),
                const Icon(Icons.expand_more_rounded, size: 16),
              ],
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: active ? cs.onSurface : cs.onSurfaceVariant,
              side: BorderSide(color: active ? cs.primary : cs.outlineVariant),
              padding: const EdgeInsets.symmetric(horizontal: WebInsets.md),
              minimumSize: const Size(0, kLedgerControlHeight),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Stack(
      children: [
        // Outside-tap barrier. translucent so the tap that dismisses the
        // panel also reaches the row cell the user intended to click. (fix)
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _controller.hide,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 6),
          child: Align(
            alignment: Alignment.topLeft,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 340,
                padding: const EdgeInsets.all(WebInsets.lg),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.6),
                  ),
                  boxShadow: [
                    BoxShadow(
                      // Theme shadow token, not literal black — black at 0.18
                      // reads far too heavy over light-mode surfaces. (T5)
                      color: cs.shadow.withValues(alpha: 0.18),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Multi-select: picking an entry toggles it rather than
                    // replacing the previous pick, so several accounts (or
                    // categories) can be filtered at once as on mobile. The
                    // selection reads back as removable chips in the toolbar.
                    _FilterRow(
                      label: 'Accounts',
                      child: WebSearchableDropdown<String?>(
                        key: WebKeys.ledgerFilterAccounts,
                        value: null,
                        hintText: widget.accountIds.isEmpty
                            ? 'All accounts'
                            : '${widget.accountIds.length} selected — add another',
                        entries: [
                          const WebDropdownEntry<String?>(
                            value: null,
                            label: 'All accounts',
                          ),
                          ...widget.accounts.map(
                            (a) => WebDropdownEntry<String?>(
                              value: a.id,
                              label: widget.accountIds.contains(a.id)
                                  ? '✓ ${a.name}'
                                  : a.name,
                            ),
                          ),
                        ],
                        onChanged: widget.onAccount,
                      ),
                    ),
                    const SizedBox(height: WebInsets.md),
                    _FilterRow(
                      label: 'Categories',
                      child: WebSearchableDropdown<String?>(
                        key: WebKeys.ledgerFilterCategories,
                        value: null,
                        hintText: widget.categoryIds.isEmpty
                            ? 'All categories'
                            : '${widget.categoryIds.length} selected — add another',
                        entries: [
                          const WebDropdownEntry<String?>(
                            value: null,
                            label: 'All categories',
                          ),
                          ...widget.categories.map(
                            (c) => WebDropdownEntry<String?>(
                              value: c.id,
                              label: widget.categoryIds.contains(c.id)
                                  ? '✓ ${c.name}'
                                  : c.name,
                            ),
                          ),
                        ],
                        onChanged: widget.onCategory,
                      ),
                    ),
                    const SizedBox(height: WebInsets.md),
                    _FilterRow(
                      label: 'Type',
                      child: _TypeSegmented(
                        key: WebKeys.ledgerFilterType,
                        value: widget.type,
                        onChanged: widget.onType,
                      ),
                    ),
                    const SizedBox(height: WebInsets.md),
                    _FilterRow(
                      label: 'Sort by',
                      child: _PanelDropdown<int>(
                        key: WebKeys.ledgerFilterSort,
                        value: _activeSortOption == null
                            ? -1
                            : kLedgerSortOptions.indexOf(_activeSortOption!),
                        items: [
                          const DropdownMenuItem(
                            value: -1,
                            child: Text('Default (date order)'),
                          ),
                          for (var i = 0; i < kLedgerSortOptions.length; i++)
                            DropdownMenuItem(
                              value: i,
                              child: Text(kLedgerSortOptions[i].label),
                            ),
                        ],
                        onChanged: (i) => widget.onSort(
                          i == null || i < 0 ? null : kLedgerSortOptions[i],
                        ),
                      ),
                    ),
                    const SizedBox(height: WebInsets.md),
                    _FilterRow(
                      label: 'Date range',
                      child: Row(
                        children: [
                          Expanded(
                            child: _DateButton(
                              key: WebKeys.ledgerFilterFrom,
                              label: widget.fromDate == null
                                  ? 'From'
                                  : kLedgerMonthDayFmt.format(widget.fromDate!),
                              onTap: () => _pickDate(context, true),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: WebInsets.sm,
                            ),
                            child: Text(
                              '→',
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          ),
                          Expanded(
                            child: _DateButton(
                              key: WebKeys.ledgerFilterUntil,
                              label: widget.toDate == null
                                  ? 'Until'
                                  : kLedgerMonthDayFmt.format(widget.toDate!),
                              onTap: () => _pickDate(context, false),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: WebInsets.lg),
                    Divider(
                      height: 1,
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: WebInsets.md),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          key: WebKeys.ledgerFilterClearAll,
                          onPressed: widget.onClear,
                          child: const Text('Clear all'),
                        ),
                        FilledButton(
                          key: WebKeys.ledgerFilterDone,
                          onPressed: _controller.hide,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: WebInsets.lg,
                            ),
                          ),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FilterRow extends StatelessWidget {
  final String label;
  final Widget child;
  const _FilterRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
        ),
        const SizedBox(height: WebInsets.sm),
        child,
      ],
    );
  }
}

class _PanelDropdown<T> extends StatelessWidget {
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  const _PanelDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: WebInsets.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          isExpanded: true,
          isDense: true,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          style: Theme.of(context).textTheme.bodyMedium,
          icon: const Icon(Icons.expand_more_rounded, size: 18),
        ),
      ),
    );
  }
}

class _TypeSegmented extends StatelessWidget {
  final WebLedgerType value;
  final ValueChanged<WebLedgerType> onChanged;
  const _TypeSegmented({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 40,
      padding: const EdgeInsets.all(WebInsets.xs),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          _seg(context, WebLedgerType.all, 'All'),
          _seg(context, WebLedgerType.inflow, 'Inflow'),
          _seg(context, WebLedgerType.outflow, 'Outflow'),
        ],
      ),
    );
  }

  Widget _seg(BuildContext context, WebLedgerType v, String label) {
    final cs = Theme.of(context).colorScheme;
    final sel = v == value;
    return Expanded(
      // MouseRegion for a pointer cursor — this was a bare GestureDetector with
      // no hover affordance on desktop. (Plan 052 U9)
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => onChanged(v),
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: sel ? cs.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadii.sm - 2),
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: sel ? cs.onPrimary : cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DateButton({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.sm),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: WebInsets.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 14,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: WebInsets.sm),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One active-filter chip in the Ledger toolbar, with a × that removes just
/// that filter. Shared by the pre-v2 page and `WebLedgerPageV2`.
class LedgerActiveChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onClear;

  /// Optional muted prefix ("Account", "Type") the v2 toolbar prints before
  /// the value, as on the canvas. Null renders the label alone.
  final String? kind;

  const LedgerActiveChip({
    super.key,
    required this.label,
    this.icon,
    required this.onClear,
    this.kind,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      height: kLedgerControlHeight,
      padding: const EdgeInsets.only(left: WebInsets.md, right: WebInsets.xs),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: cs.onSurfaceVariant),
            const SizedBox(width: WebInsets.sm),
          ],
          if (kind != null) ...[
            Text(
              kind!,
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: WebInsets.xs),
          ],
          Text(
            label,
            style: theme.textTheme.labelMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: WebInsets.xs),
          InkWell(
            onTap: onClear,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.close_rounded,
                size: 14,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
