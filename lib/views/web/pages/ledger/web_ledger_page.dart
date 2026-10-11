import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/finance_parse_result.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/app_radii.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';
import '../../widgets/web_receipt_drop.dart';
import '../../widgets/web_widgets.dart';
import 'ledger_cells.dart';
import 'ledger_filters.dart';
import 'ledger_filters_popover.dart';

export 'ledger_filters.dart';

/// Web Ledger page (Plan 051). A Google-Sheets-style, inline-editable
/// transaction grid matching the Claude Design reference
/// (`docs/design/treasury-web-reference/ledger.jsx`): click any cell to edit,
/// type in the bottom row to add, sortable headers, bulk select + delete,
/// running + per-account balance columns, a Filters & Sort popover with active
/// chips, and a natural-language Quick Add card. Theme-aware throughout — the
/// reference is the visual target, the palette is ours.
class WebLedgerPage extends StatefulWidget {
  final LedgerPresenter presenter;

  /// Filter/sort state, owned above the page so leaving the Ledger destination
  /// and coming back doesn't silently drop the filters the user set. Optional:
  /// without one the page keeps a private set, as it always did.
  final WebLedgerFilters? filters;

  const WebLedgerPage({super.key, required this.presenter, this.filters});

  @override
  State<WebLedgerPage> createState() => _WebLedgerPageState();
}

/// One enriched, display-ready ledger row.
typedef _Row = ({
  TransactionRecord txn,
  double runningBalance,
  double accountBalance,
});

class _WebLedgerPageState extends State<WebLedgerPage> {
  final _searchController = TextEditingController();
  final _gridHScroll = ScrollController(); // horizontal grid scroll (U8)
  final _gridVScroll =
      ScrollController(); // vertical rows scroll (sticky header)
  final _col = LedgerColWidths(); // drag-resizable column widths

  /// Filters & sort — View-side (never mutates presenter state), but owned
  /// above the page when the shell supplies one so they survive navigation.
  late final WebLedgerFilters _f = widget.filters ?? WebLedgerFilters();
  bool get _ownsFilters => widget.filters == null;

  String get _query => _f.query;

  // Selection for bulk delete.
  final Set<String> _selected = <String>{};

  // Draft "add a row" state.
  late DateTime _draftDate;
  String? _draftAccountId;
  String? _draftCategoryId;
  String _draftDesc = '';
  String _draftNote = '';
  double _draftInflow = 0;
  double _draftOutflow = 0;
  int _draftEpoch = 0; // bumped to reset inline field controllers after commit

  LedgerPresenter get _p => widget.presenter;

  @override
  void initState() {
    super.initState();
    _draftDate = DateTime.now();
    // Restore a query carried over from a previous visit to this destination.
    _searchController.text = _f.query;
    _searchController.addListener(_onSearchChanged);
    _f.addListener(_onFiltersChanged);
    _p.addListener(_onLedgerNeedsForm);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _gridHScroll.dispose();
    _gridVScroll.dispose();
    _f.removeListener(_onFiltersChanged);
    _p.removeListener(_onLedgerNeedsForm);
    if (_ownsFilters) _f.dispose();
    super.dispose();
  }

  /// True while [_drainToForm] is walking the queue, so a notify raised by the
  /// form's own commit doesn't start a second, overlapping walk.
  bool _drainingToForm = false;

  /// The web surface that owns the transaction form, so it is the one that
  /// answers when the parser hands an entry back.
  ///
  /// Quick Add used to do this itself, from inside its own send(). Now that the
  /// assistant is the only place you type an entry, and it lives in the shell
  /// rather than on this page, the drain has to live with the form instead —
  /// otherwise a message the assistant only partly resolved leaves its
  /// leftovers queued in the presenter with nothing on web to open them.
  void _onLedgerNeedsForm() {
    if (!mounted || _drainingToForm) return;
    if (_p.pendingFormPrefill == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _drainToForm();
    });
  }

  /// Opens the prefilled form for the pending leftover, then for each one still
  /// queued behind it. Awaiting each dialog is what lets every unresolved entry
  /// from one message get filled in, rather than only the first.
  Future<void> _drainToForm() async {
    if (_drainingToForm) return;
    _drainingToForm = true;
    try {
      var prefill = _p.pendingFormPrefill;
      _p.consumeFormPrefill();
      while (prefill != null && mounted) {
        final remaining = _p.queuedFormPrefillCount;
        if (remaining > 0) {
          // Say a second form is coming. Two dialogs in a row with no warning
          // reads as the first one failing to close.
          AppToast.show(
            context,
            '$remaining more from that message after this one',
          );
        }
        await _openAddDialog(prefill);
        if (!mounted) return;
        prefill = _p.takeNextFormPrefill();
      }
    } finally {
      _drainingToForm = false;
    }
  }

  void _onFiltersChanged() {
    if (mounted) setState(() {});
  }

  Timer? _searchDebounce;

  void _onSearchChanged() {
    // Debounce so each keystroke doesn't re-filter the whole grid immediately;
    // the filter only re-runs once typing pauses (~220ms). (Plan 052 B2/P2)
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      _f.setQuery(_searchController.text.trim().toLowerCase());
    });
  }

  // ── Lookups ────────────────────────────────────────────────────────────────

  List<FinancialAccount> get _liquidAccounts =>
      _p.accounts.where((a) => a.isActive && !a.isSubAccount).toList();

  FinanceCategory? _categoryOf(String? id) =>
      _p.categories.where((c) => c.id == id).firstOrNull;

  FinancialAccount? _accountOf(String? id) =>
      _p.accounts.where((a) => a.id == id).firstOrNull;

  String _accountName(String? id) => _accountOf(id)?.name ?? '—';

  Color _colorFor(FinanceCategory? cat) {
    if (cat == null) return Theme.of(context).colorScheme.onSurfaceVariant;
    final idx = _p.categories.indexWhere((c) => c.id == cat.id);
    return resolveSliceColor(
      cat.colorHex,
      idx < 0 ? 0 : idx,
      brightness: Theme.of(context).brightness,
    );
  }

  List<FinanceCategory> _categoriesFor(TransactionType type) {
    final want = type == TransactionType.inflow
        ? CategoryType.income
        : CategoryType.expense;
    return _p.categories.where((c) => c.type == want).toList();
  }

  // ── Filtering + sorting (View-side) ──────────────────────────────────────────

  bool _matches(_Row r) {
    final t = r.txn;
    if (_f.accountIds.isNotEmpty && !_f.accountIds.contains(t.accountId)) {
      return false;
    }
    if (_f.categoryIds.isNotEmpty && !_f.categoryIds.contains(t.categoryId)) {
      return false;
    }
    switch (_f.type) {
      case WebLedgerType.inflow:
        if (t.type != TransactionType.inflow) return false;
      case WebLedgerType.outflow:
        if (t.type != TransactionType.outflow) return false;
      case WebLedgerType.all:
        break;
    }
    if (_f.fromDate != null && t.date.isBefore(_dayStart(_f.fromDate!))) {
      return false;
    }
    if (_f.toDate != null && t.date.isAfter(_dayEnd(_f.toDate!))) return false;
    if (_query.isNotEmpty) {
      final cat = _categoryOf(t.categoryId)?.name.toLowerCase() ?? '';
      final acct = _accountName(t.accountId).toLowerCase();
      final hay = '${t.description.toLowerCase()} '
          '${(t.note ?? '').toLowerCase()} $cat $acct';
      final textMatch = hay.contains(_query);

      // Numeric match: when the query (stripped of ₱, spaces and commas) is a
      // number, also match on the transaction amount — both exact (1000 ==
      // 1,000) and as a substring of the formatted amount, so "1000" finds
      // ₱1,000.00 and "10" finds ₱10.00. Either text OR amount may match.
      var amountMatch = false;
      final cleaned =
          _query.replaceAll('₱', '').replaceAll(' ', '').replaceAll(',', '');
      final n = double.tryParse(cleaned);
      if (n != null) {
        final fixed = t.amount.toStringAsFixed(2); // e.g. "1000.00"
        final grouped = NumberFormat(
          '#,##0.00',
          'en_PH',
        ).format(t.amount); // "1,000.00"
        amountMatch = t.amount == n ||
            fixed.contains(cleaned) ||
            grouped.contains(_query);
      }

      if (!textMatch && !amountMatch) return false;
    }
    return true;
  }

  List<_Row> _sorted(List<_Row> rows) {
    // Default ordering is newest-first — the most recent entry sits at the top,
    // right below the draft add-row. Explicit sort presets still override via
    // the filter model's sortKey/sortDir. (Ledger UX overhaul PR2)
    final key = _f.sortKey ?? WebLedgerSortKey.date;
    final dir = _f.sortKey == null ? -1 : _f.sortDir;
    Comparable keyOf(_Row r) {
      final t = r.txn;
      switch (key) {
        case WebLedgerSortKey.date:
          return t.date.millisecondsSinceEpoch;
        case WebLedgerSortKey.account:
          return _accountName(t.accountId).toLowerCase();
        case WebLedgerSortKey.description:
          return t.description.toLowerCase();
        case WebLedgerSortKey.category:
          return (_categoryOf(t.categoryId)?.name ?? '').toLowerCase();
        case WebLedgerSortKey.inflow:
          return t.type == TransactionType.inflow ? t.amount : 0.0;
        case WebLedgerSortKey.outflow:
          return t.type == TransactionType.outflow ? t.amount : 0.0;
        case WebLedgerSortKey.amount:
          return t.amount;
      }
    }

    final out = [...rows]
      ..sort((a, b) => Comparable.compare(keyOf(a), keyOf(b)) * dir);
    return out;
  }

  void _toggleHeaderSort(WebLedgerSortKey key) => _f.toggleHeaderSort(key);

  int get _activeFilterCount => _f.activeCount;

  void _clearFilters() {
    _searchController.clear();
    _f
      ..clear()
      ..setQuery('');
  }

  // ── Mutations ────────────────────────────────────────────────────────────────

  /// Every inline cell edit goes through here so an installment purchase's
  /// plan follows its record. The presenter refuses an edit that would end the
  /// purchase (income, or a non-credit account); say why.
  Future<void> _commitInline(TransactionRecord edited) async {
    final applied = await _p.updateRecordInline(edited);
    if (applied || !mounted) return;
    AppToast.error(
      context,
      'An installment purchase stays an expense on a credit account. '
      'Open the row to turn the split off.',
    );
  }

  void _editDate(TransactionRecord t, DateTime d) =>
      _commitInline(t.copyWith(date: d, month: toMonthKey(d)));

  void _editAccount(TransactionRecord t, String id) =>
      _commitInline(t.copyWith(accountId: id));

  void _editCategory(TransactionRecord t, String id) =>
      _commitInline(t.copyWith(categoryId: id));

  void _editDescription(TransactionRecord t, String v) {
    if (v.trim() == t.description) return;
    _commitInline(t.copyWith(description: v.trim()));
  }

  void _editNote(TransactionRecord t, String v) {
    final next = v.trim();
    if (next == (t.note ?? '')) return;
    _commitInline(t.copyWith(note: next));
  }

  /// Editing the inflow/outflow cells: a row's two amount columns are views of
  /// the single `amount`+`type`. Writing a positive value flips the row to that
  /// direction. Zero/empty is ignored (revert).
  void _editAmount(TransactionRecord t, double value, TransactionType dir) {
    if (value <= 0) return;
    if (t.type == dir && t.amount == value) return;
    // Flipping direction (outflow <-> inflow) invalidates the category: an
    // expense category on an income row (or vice versa) falls out of every
    // category aggregation. Clear it on a type change, matching the modal's
    // _setType and mobile. A pure amount edit keeps the category.
    final flippedType = t.type != dir;
    _commitInline(t.copyWith(
      type: dir,
      amount: value,
      categoryId: flippedType ? '' : t.categoryId,
    ));
  }

  /// Deleting one row goes straight through, with an Undo — the same contract
  /// as the phone's swipe-to-delete. It previously showed a modal claiming the
  /// delete "cannot be undone", which was both a different contract from mobile
  /// and untrue: the presenter can restore the exact records it removed.
  Future<void> _deleteRow(TransactionRecord t) async {
    setState(() => _selected.remove(t.id));
    final removed = await _p.deleteTransactionOrGroup(t.id);
    if (removed.isEmpty || !mounted) return;
    _offerUndo(
      t.transferGroupId != null
          ? 'Deleted transfer "${t.description}"'
          : 'Deleted "${t.description}"',
      removed,
    );
  }

  /// Bulk delete still confirms first — one keystroke wiping many rows deserves
  /// a beat — but the copy no longer overstates it, and Undo is offered after.
  Future<void> _deleteSelected() async {
    final ids = _selected.toSet();
    if (ids.isEmpty) return;
    final ok = await _confirmDelete(ids.length);
    if (!ok || !mounted) return;
    setState(_selected.clear);
    // One batched mutation + persist instead of N fire-and-forget writes. (C8)
    final removed = await _p.deleteTransactions(ids);
    if (removed.isEmpty || !mounted) return;
    _offerUndo('Deleted ${removed.length} transactions', removed);
  }

  void _offerUndo(String message, List<TransactionRecord> removed) {
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        width: 420,
        duration: const Duration(seconds: 6),
        content: Text(message),
        action: SnackBarAction(
          label: 'Undo',
          textColor: cs.inversePrimary,
          onPressed: () => _p.restoreTransactions(removed),
        ),
      ));
  }

  /// Confirms a destructive bulk delete of [count] transactions. (Plan 052 U2)
  Future<bool> _confirmDelete(int count) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete transactions?'),
        content: Text(
          'Delete $count transactions? This also reverses the affected '
          'account balances. You can undo it straight afterwards.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _commitDraft() {
    final amount = _draftInflow > 0 ? _draftInflow : _draftOutflow;
    if (amount <= 0) return; // need a value
    final type =
        _draftInflow > 0 ? TransactionType.inflow : TransactionType.outflow;
    final accountId = _draftAccountId ?? _liquidAccounts.firstOrNull?.id;
    if (accountId == null) return; // no accounts to post to
    final cats = _categoriesFor(type);
    // Require an explicit category when categories exist for this direction —
    // matches the add-transaction modal. Silently stamping the first expense
    // category (the old fallback) misattributed spend to a category the user
    // never chose, and it fell out of the intended category's totals.
    final picked = _draftCategoryId;
    if (cats.isNotEmpty &&
        (picked == null || !cats.any((c) => c.id == picked))) {
      AppToast.error(context, 'Pick a category before adding the row.');
      return;
    }
    final categoryId = picked ?? '';
    final desc = _draftDesc.trim().isEmpty
        ? (_categoryOf(categoryId)?.name ?? 'Transaction')
        : _draftDesc.trim();
    final id =
        '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';
    _p.addTransaction(
      TransactionRecord(
        id: id,
        date: _draftDate,
        accountId: accountId,
        categoryId: categoryId,
        amount: amount,
        type: type,
        description: desc,
        note: _draftNote.trim().isEmpty ? null : _draftNote.trim(),
        month: toMonthKey(_draftDate),
      ),
    );
    setState(() {
      _draftDesc = '';
      _draftNote = '';
      _draftInflow = 0;
      _draftOutflow = 0;
      _draftCategoryId = null;
      _draftDate = DateTime.now();
      _draftEpoch++; // reset inline controllers
    });
  }

  // ── Add-transaction modal ────────────────────────────────────────────────────

  Future<void> _openAddDialog([ParsedTransaction? prefill]) async {
    await _p.reloadAccounts();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _AddTransactionDialog(presenter: _p, prefill: prefill),
    );
  }

  /// Opens the edit dialog for [t]. Used by transfer rows, whose paired legs
  /// can't be edited inline in the grid.
  Future<void> _openEditDialog(TransactionRecord t) async {
    await _p.reloadAccounts();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _AddTransactionDialog(presenter: _p, existing: t),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _p,
      builder: (context, _) {
        return Padding(
          // No page-level vertical scroll: the summary cards + toolbar stay
          // pinned and only the grid rows scroll (sticky header + cards).
          padding: const EdgeInsets.all(WebInsets.xxl),
          child: _p.isLoading ? const _LoadingBlock() : _buildBody(context),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    // A search term or a date range is a question about the whole ledger. Kept
    // month-scoped, both silently returned nothing whenever the answer lived in
    // another month — and the empty grid read as "you have no such rows".
    final spansAll = _f.spansAllMonths;
    final all =
        spansAll ? _p.ledgerSpreadsheetRowsAllMonths : _p.ledgerSpreadsheetRows;
    final rows = _sorted(all.where(_matches).toList());

    // The page is focused purely on the ledger grid: the inflow/outflow/
    // net-cash summary tiles moved out, and typed entry moved to Nudgy in the
    // shell, so only receipt scanning still floats over the grid.
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The phone gives the Ledger a title row of its own and puts the
            // month and filter controls on a second row beneath it. Web opened
            // straight onto the toolbar, so the one page with no name was the
            // one users are in most. The toolbar below is that controls row.
            const WebPageHeader(title: 'Ledger'),
            _Toolbar(
              monthLabel: monthLabel(_p.selectedMonth),
              spansAllMonths: spansAll,
              matchCount: rows.length,
              onPrevMonth: () => _p.setMonth(previousMonth(_p.selectedMonth)),
              onNextMonth: () => _p.setMonth(nextMonth(_p.selectedMonth)),
              searchController: _searchController,
              accounts: _liquidAccounts,
              categories: _p.categories,
              accountIds: _f.accountIds,
              categoryIds: _f.categoryIds,
              type: _f.type,
              fromDate: _f.fromDate,
              toDate: _f.toDate,
              sortKey: _f.sortKey,
              sortDir: _f.sortDir,
              activeCount: _activeFilterCount,
              accountName: _accountName,
              categoryName: (id) => _categoryOf(id)?.name ?? '—',
              onAccount: _f.toggleAccount,
              onCategory: _f.toggleCategory,
              onType: _f.setType,
              onFromDate: _f.setFromDate,
              onToDate: _f.setToDate,
              onSort: _f.setSort,
              onClear: _clearFilters,
              onAdd: () => _openAddDialog(),
            ),
            const SizedBox(height: WebInsets.xl),
            // The table fills the remaining viewport height and owns its own
            // scrolling, so the toolbar above stays pinned.
            Expanded(
              child: _buildTableCard(context, rows, narrowed: _f.isNarrowed),
            ),
          ],
        ),
        // Receipt scanning. Typed entry moved to Nudgy, the assistant in the
        // shell — one input that logs what reads as a transaction and answers
        // everything else, instead of a box here that could only do the first.
        Positioned(
          right: 0,
          bottom: 0,
          child: FloatingActionButton.small(
            heroTag: 'ledgerReceiptScan',
            tooltip: 'Scan a receipt',
            onPressed: () => showWebReceiptDialog(context, ledger: _p),
            child: const Icon(Icons.document_scanner_outlined),
          ),
        ),
      ],
    );
  }

  Widget _buildTableCard(
    BuildContext context,
    List<_Row> rows, {
    required bool narrowed,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Card surface built by hand (not WebCard) because the table fills a
    // bounded height and uses an inner Expanded for the scrolling rows, which a
    // mainAxisSize.min card Column can't host.
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Selection bar — shown only while rows are selected.
          if (_selected.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: WebInsets.lg,
                vertical: WebInsets.md,
              ),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              ),
              child: _SelectionBar(
                count: _selected.length,
                onClear: () => setState(_selected.clear),
                onDelete: _deleteSelected,
              ),
            ),
          // Grid: header + draft row stay pinned; only the rows scroll
          // vertically. The Description column stretches to fill leftover width;
          // the grid scrolls horizontally when columns exceed the viewport.
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final avail = constraints.maxWidth;
                final descW = max(kLedgerDescMinWidth, avail - _col.fixedSum);
                final gridW = _col.fixedSum + descW;
                // Left edges of the two money columns, used to paint full-height
                // green/red column washes that run continuously behind every row
                // (header → draft → rows) instead of stopping inside each cell.
                final inflowLeft = kLedgerCheckWidth +
                    _col.date +
                    _col.account +
                    descW +
                    _col.category;
                final outflowLeft = inflowLeft + _col.inflow;
                return Scrollbar(
                  controller: _gridHScroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _gridHScroll,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: gridW,
                      child: Stack(
                        children: [
                          // Continuous column washes — span the full grid height
                          // so each money column reads as one solid band.
                          Positioned(
                            left: inflowLeft,
                            top: 0,
                            bottom: 0,
                            width: _col.inflow,
                            child: ColoredBox(color: _inflowTint(context)),
                          ),
                          Positioned(
                            left: outflowLeft,
                            top: 0,
                            bottom: 0,
                            width: _col.outflow,
                            child: ColoredBox(color: _outflowTint(context)),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Pinned header.
                              _GridHeader(
                                descWidth: descW,
                                widths: _col,
                                sortKey: _f.sortKey,
                                sortDir: _f.sortDir,
                                allSelected: rows.isNotEmpty &&
                                    rows.every(
                                      (r) => _selected.contains(r.txn.id),
                                    ),
                                onToggleAll: () => setState(() {
                                  final allSel = rows.isNotEmpty &&
                                      rows.every(
                                        (r) => _selected.contains(r.txn.id),
                                      );
                                  if (allSel) {
                                    _selected.clear();
                                  } else {
                                    _selected.addAll(rows.map((r) => r.txn.id));
                                  }
                                }),
                                onSort: _toggleHeaderSort,
                                onResize: (col, d) =>
                                    setState(() => _col.resize(col, d)),
                              ),
                              // Draft add-row — pinned at the TOP, right above
                              // the newest entries (newest-first ordering).
                              _DraftRow(
                                epoch: _draftEpoch,
                                descWidth: descW,
                                widths: _col,
                                date: _draftDate,
                                accountId: _draftAccountId,
                                categoryId: _draftCategoryId,
                                inflow: _draftInflow,
                                outflow: _draftOutflow,
                                accounts: _liquidAccounts,
                                categories: _categoriesFor(
                                  _draftInflow > 0
                                      ? TransactionType.inflow
                                      : TransactionType.outflow,
                                ),
                                colorFor: _colorFor,
                                onDate: (d) => setState(() => _draftDate = d),
                                onAccount: (id) =>
                                    setState(() => _draftAccountId = id),
                                onCategory: (id) =>
                                    setState(() => _draftCategoryId = id),
                                onDescription: (v) => _draftDesc = v,
                                onNote: (v) => _draftNote = v,
                                onInflow: (v) => setState(() {
                                  _draftInflow = v;
                                  if (v > 0) _draftOutflow = 0;
                                }),
                                onOutflow: (v) => setState(() {
                                  _draftOutflow = v;
                                  if (v > 0) _draftInflow = 0;
                                }),
                                onCommit: _commitDraft,
                              ),
                              // Scrolling rows (newest-first; newest on top).
                              Expanded(
                                child: Scrollbar(
                                  controller: _gridVScroll,
                                  thumbVisibility: true,
                                  child: ListView(
                                    controller: _gridVScroll,
                                    padding: EdgeInsets.zero,
                                    children: [
                                      if (rows.isEmpty)
                                        _EmptyGridHint(
                                          hasAccounts:
                                              _liquidAccounts.isNotEmpty,
                                          narrowed: narrowed,
                                          onClearFilters: _clearFilters,
                                        ),
                                      for (var i = 0; i < rows.length; i++)
                                        _EditableRow(
                                          key: ValueKey(rows[i].txn.id),
                                          row: rows[i],
                                          descWidth: descW,
                                          widths: _col,
                                          selected: _selected.contains(
                                            rows[i].txn.id,
                                          ),
                                          accounts: _liquidAccounts,
                                          categories: _categoriesFor(
                                            rows[i].txn.type,
                                          ),
                                          accountName: _accountName,
                                          categoryOf: _categoryOf,
                                          colorFor: _colorFor,
                                          onToggleSelect: () => setState(() {
                                            final id = rows[i].txn.id;
                                            _selected.contains(id)
                                                ? _selected.remove(id)
                                                : _selected.add(id);
                                          }),
                                          onDate: _editDate,
                                          onAccount: _editAccount,
                                          onCategory: _editCategory,
                                          onDescription: _editDescription,
                                          onNote: _editNote,
                                          onAmount: _editAmount,
                                          onDelete: _deleteRow,
                                          onEdit: _openEditDialog,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Footer hint.
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: WebInsets.lg,
              vertical: WebInsets.sm,
            ),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.edit_outlined, size: 13, color: cs.onSurfaceVariant),
                const SizedBox(width: WebInsets.sm),
                Expanded(
                  child: Text(
                    'Click any cell to edit · press Enter on the top row to '
                    'add · drag a column edge to resize · account balance '
                    'recalculates automatically.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
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

DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _dayEnd(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59);

// ═══════════════════════════════════════════════════════════════════════════════
// Toolbar — Filters & Sort popover + chips + search + Add
// ═══════════════════════════════════════════════════════════════════════════════

class _Toolbar extends StatelessWidget {
  final String monthLabel;

  /// True while a search term or date range widens the grid past the selected
  /// month — the month stepper is then not what's bounding the results, and the
  /// toolbar says so rather than leaving the month label looking authoritative.
  final bool spansAllMonths;
  final int matchCount;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final TextEditingController searchController;
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
  final String Function(String?) accountName;
  final String Function(String?) categoryName;
  final ValueChanged<String?> onAccount;
  final ValueChanged<String?> onCategory;
  final ValueChanged<WebLedgerType> onType;
  final ValueChanged<DateTime?> onFromDate;
  final ValueChanged<DateTime?> onToDate;
  final ValueChanged<WebLedgerSortOption?> onSort;
  final VoidCallback onClear;
  final VoidCallback onAdd;

  const _Toolbar({
    required this.monthLabel,
    required this.spansAllMonths,
    required this.matchCount,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.searchController,
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
    required this.accountName,
    required this.categoryName,
    required this.onAccount,
    required this.onCategory,
    required this.onType,
    required this.onFromDate,
    required this.onToDate,
    required this.onSort,
    required this.onClear,
    required this.onAdd,
  });

  WebLedgerSortOption? get _activeSortOption {
    for (final o in kLedgerSortOptions) {
      if (o.key == sortKey && o.dir == sortDir) return o;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final df = kLedgerMonthDayFmt;
    final dateLabel = fromDate != null && toDate != null
        ? '${df.format(fromDate!)} → ${df.format(toDate!)}'
        : fromDate != null
            ? 'From ${df.format(fromDate!)}'
            : toDate != null
                ? 'Until ${df.format(toDate!)}'
                : null;
    final sortLabel =
        _activeSortOption?.label ?? (sortKey != null ? 'Custom sort' : null);

    final chips = <Widget>[
      // One chip per selected account/category — picking a second no longer
      // replaces the first, matching mobile's multi-select filters.
      for (final id in accountIds)
        LedgerActiveChip(
          label: accountName(id),
          onClear: () => onAccount(id),
        ),
      for (final id in categoryIds)
        LedgerActiveChip(
          label: categoryName(id),
          onClear: () => onCategory(id),
        ),
      if (type != WebLedgerType.all)
        LedgerActiveChip(
          label: type == WebLedgerType.inflow ? 'Inflow only' : 'Outflow only',
          onClear: () => onType(WebLedgerType.all),
        ),
      if (dateLabel != null)
        LedgerActiveChip(
          label: dateLabel,
          icon: Icons.history,
          onClear: () {
            onFromDate(null);
            onToDate(null);
          },
        ),
      if (sortLabel != null)
        LedgerActiveChip(
          label: sortLabel,
          icon: Icons.swap_vert_rounded,
          onClear: () => onSort(null),
        ),
    ];

    // Month label sits far left; active-filter chips follow; Filters & Sort,
    // search and Add sit on the right.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Month stepper — page back/forward through months. Dimmed while a
        // search or date range is spanning all months: it isn't what bounds the
        // results then, and leaving it looking authoritative was the whole
        // reason a cross-month search read as "no such transactions".
        IconButton(
          onPressed: spansAllMonths ? null : onPrevMonth,
          icon: const Icon(Icons.chevron_left_rounded),
          tooltip: 'Previous month',
          visualDensity: VisualDensity.compact,
        ),
        Text(
          spansAllMonths ? 'All months' : monthLabel,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        IconButton(
          onPressed: spansAllMonths ? null : onNextMonth,
          icon: const Icon(Icons.chevron_right_rounded),
          tooltip: 'Next month',
          visualDensity: VisualDensity.compact,
        ),
        if (spansAllMonths) ...[
          const SizedBox(width: WebInsets.sm),
          _ScopeNote(
            label: matchCount == 1
                ? '1 match across all months'
                : '$matchCount matches across all months',
          ),
        ],
        const SizedBox(width: WebInsets.md),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: WebInsets.sm,
            runSpacing: WebInsets.sm,
            children: chips,
          ),
        ),
        const SizedBox(width: WebInsets.sm),
        LedgerFiltersPopover(
          accounts: accounts,
          categories: categories,
          accountIds: accountIds,
          categoryIds: categoryIds,
          type: type,
          fromDate: fromDate,
          toDate: toDate,
          sortKey: sortKey,
          sortDir: sortDir,
          activeCount: activeCount,
          onAccount: onAccount,
          onCategory: onCategory,
          onType: onType,
          onFromDate: onFromDate,
          onToDate: onToDate,
          onSort: onSort,
          onClear: onClear,
        ),
        const SizedBox(width: WebInsets.sm),
        _SearchField(controller: searchController),
        const SizedBox(width: WebInsets.sm),
        _AddButton(onPressed: onAdd),
      ],
    );
  }
}

/// Quiet pill telling the user the grid has widened past the selected month.
class _ScopeNote extends StatelessWidget {
  final String label;
  const _ScopeNote({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: WebInsets.md, vertical: WebInsets.xs),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.travel_explore_rounded, size: 14, color: cs.primary),
          const SizedBox(width: WebInsets.xs),
          Text(
            label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  const _SearchField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: kLedgerControlHeight,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search…',
          prefixIcon: const Icon(Icons.search_rounded, size: 18),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 0,
            horizontal: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _AddButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kLedgerControlHeight,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('Add Transaction'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: WebInsets.lg),
          minimumSize: const Size(0, kLedgerControlHeight),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Grid header + band + selection + body rows
// ═══════════════════════════════════════════════════════════════════════════════

class _SelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback onClear;
  final VoidCallback onDelete;
  const _SelectionBar({
    required this.count,
    required this.onClear,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            '$count selected',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        TextButton(onPressed: onClear, child: const Text('Clear')),
        const SizedBox(width: WebInsets.sm),
        FilledButton.icon(
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline_rounded, size: 16),
          label: Text(count > 1 ? 'Delete $count' : 'Delete'),
          style: FilledButton.styleFrom(
            backgroundColor: cs.error.withValues(alpha: 0.15),
            foregroundColor: cs.error,
            elevation: 0,
          ),
        ),
      ],
    );
  }
}

class _GridHeader extends StatelessWidget {
  final double descWidth;
  final LedgerColWidths widths;
  final WebLedgerSortKey? sortKey;
  final int sortDir;
  final bool allSelected;
  final VoidCallback onToggleAll;
  final ValueChanged<WebLedgerSortKey> onSort;
  final void Function(LedgerResizableCol, double) onResize;
  const _GridHeader({
    required this.descWidth,
    required this.widths,
    required this.sortKey,
    required this.sortDir,
    required this.allSelected,
    required this.onToggleAll,
    required this.onSort,
    required this.onResize,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        // Translucent so the green/red column washes painted behind the grid
        // still read through the header band.
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.8)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: kLedgerCheckWidth,
            child: Center(
              child: LedgerCheck(on: allSelected, onTap: onToggleAll),
            ),
          ),
          _hCell(
            'Date',
            widths.date,
            WebLedgerSortKey.date,
            resize: LedgerResizableCol.date,
          ),
          _hCell(
            'Account',
            widths.account,
            WebLedgerSortKey.account,
            resize: LedgerResizableCol.account,
          ),
          _hCell('Description', descWidth, WebLedgerSortKey.description),
          _hCell(
            'Category',
            widths.category,
            WebLedgerSortKey.category,
            resize: LedgerResizableCol.category,
          ),
          _hCell(
            'Inflow',
            widths.inflow,
            WebLedgerSortKey.inflow,
            right: true,
            resize: LedgerResizableCol.inflow,
          ),
          _hCell(
            'Outflow',
            widths.outflow,
            WebLedgerSortKey.outflow,
            right: true,
            resize: LedgerResizableCol.outflow,
          ),
          _hCell(
            'Acct. Balance',
            widths.acctBal,
            null,
            right: true,
            resize: LedgerResizableCol.acctBal,
          ),
          const SizedBox(width: kLedgerTrailingWidth),
        ],
      ),
    );
  }

  Widget _hCell(
    String label,
    double width,
    WebLedgerSortKey? key, {
    bool right = false,
    LedgerResizableCol? resize,
  }) {
    return LedgerHeaderCell(
      label: label,
      width: width,
      sortKey: key,
      active: key != null && key == sortKey,
      dir: sortDir,
      right: right,
      onSort: key == null ? null : () => onSort(key),
      onResize: resize == null ? null : (d) => onResize(resize, d),
    );
  }
}

/// Faint green/red wash behind the Inflow/Outflow columns so the two money
/// directions read apart at a glance, like a color-coded spreadsheet.
Color _inflowTint(BuildContext context) =>
    (Theme.of(context).extension<AppThemeExtension>()?.success ??
            Theme.of(context).colorScheme.tertiary)
        .withValues(alpha: 0.06);
Color _outflowTint(BuildContext context) =>
    Theme.of(context).colorScheme.error.withValues(alpha: 0.06);

class _EmptyGridHint extends StatelessWidget {
  final bool hasAccounts;

  /// True when a filter or search term is active. Without this the grid told
  /// every user "No transactions yet" — including the one whose filter had just
  /// hidden a full month of rows, which reads as data loss.
  final bool narrowed;
  final VoidCallback onClearFilters;

  const _EmptyGridHint({
    required this.hasAccounts,
    required this.narrowed,
    required this.onClearFilters,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: cs.onSurfaceVariant,
    );

    if (narrowed) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: WebInsets.xl),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('No transactions match your filters.', style: style),
            const SizedBox(height: WebInsets.sm),
            TextButton.icon(
              onPressed: onClearFilters,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
              label: const Text('Clear filters'),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: WebInsets.xl),
      alignment: Alignment.center,
      child: Text(
        hasAccounts
            ? 'No transactions this month — add one in the row above.'
            : 'Add an account in Setup before logging transactions.',
        style: style,
      ),
    );
  }
}

// ── Editable row ────────────────────────────────────────────────────────────────

class _EditableRow extends StatefulWidget {
  final _Row row;
  final double descWidth;
  final LedgerColWidths widths;
  final bool selected;
  final List<FinancialAccount> accounts;
  final List<FinanceCategory> categories;
  final String Function(String?) accountName;
  final FinanceCategory? Function(String?) categoryOf;
  final Color Function(FinanceCategory?) colorFor;
  final VoidCallback onToggleSelect;
  final void Function(TransactionRecord, DateTime) onDate;
  final void Function(TransactionRecord, String) onAccount;
  final void Function(TransactionRecord, String) onCategory;
  final void Function(TransactionRecord, String) onDescription;
  final void Function(TransactionRecord, String) onNote;
  final void Function(TransactionRecord, double, TransactionType) onAmount;
  final void Function(TransactionRecord) onDelete;

  /// Opens the edit dialog for [t]. The grid edits ordinary rows inline, but a
  /// transfer's two legs must move together, so transfer rows route here instead.
  final void Function(TransactionRecord) onEdit;

  const _EditableRow({
    super.key,
    required this.row,
    required this.descWidth,
    required this.widths,
    required this.selected,
    required this.accounts,
    required this.categories,
    required this.accountName,
    required this.categoryOf,
    required this.colorFor,
    required this.onToggleSelect,
    required this.onDate,
    required this.onAccount,
    required this.onCategory,
    required this.onDescription,
    required this.onNote,
    required this.onAmount,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  State<_EditableRow> createState() => _EditableRowState();
}

class _EditableRowState extends State<_EditableRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final t = widget.row.txn;
    final isTransfer = t.transferGroupId != null;
    final w = widget.widths;

    // Flat grid (no zebra) — rows are separated by a hairline bottom border and
    // a hover tint only, matching the reference's clean spreadsheet look.
    Color? bg;
    if (widget.selected) {
      bg = cs.primary.withValues(alpha: 0.10);
    } else if (_hover) {
      // 0.03 was below the perceptual threshold on dark surfaces — the hover
      // affordance was effectively invisible. (T6)
      bg = cs.onSurface.withValues(alpha: 0.06);
    }

    // A transfer's two legs must change together, so its cells are read-only in
    // the inline grid; clicking the row opens the pair-aware edit dialog instead.
    Widget body = Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: kLedgerCheckWidth,
            child: Center(
              child: LedgerCheck(
                on: widget.selected,
                onTap: widget.onToggleSelect,
              ),
            ),
          ),
          // Date
          LedgerDateCell(
            width: w.date,
            date: t.date,
            enabled: !isTransfer,
            onChanged: (d) => widget.onDate(t, d),
          ),
          // Account
          isTransfer
              ? LedgerTransferAccountCell(
                  width: w.account,
                  txn: t,
                  accounts: widget.accounts,
                )
              : LedgerAccountCell(
                  width: w.account,
                  value: t.accountId,
                  accounts: widget.accounts,
                  onChanged: (id) => widget.onAccount(t, id),
                ),
          // Description
          LedgerInlineText(
            // Key on the row id ONLY — embedding the value meant every commit
            // disposed+recreated the controller/FocusNode, breaking Tab/Enter
            // flow and dropping focus. didUpdateWidget syncs the text. (C3)
            key: ValueKey('desc_${t.id}'),
            width: widget.descWidth,
            initialValue: t.description,
            hintText: '—',
            bold: true,
            enabled: !isTransfer,
            onCommit: (v) => widget.onDescription(t, v),
          ),
          // Category
          isTransfer
              ? ledgerReadCell(
                  width: w.category,
                  child: const Align(
                    alignment: Alignment.centerLeft,
                    child: WebBadge(
                      'Transfer',
                      tone: WebBadgeTone.info,
                      icon: Icons.swap_horiz_rounded,
                    ),
                  ),
                )
              : LedgerCategoryCell(
                  width: w.category,
                  value: t.categoryId,
                  categories: widget.categories,
                  colorFor: widget.colorFor,
                  onChanged: (id) => widget.onCategory(t, id),
                ),
          // Inflow — sits over the green column wash painted behind the grid.
          LedgerAmountCell(
            key: ValueKey('in_${t.id}'),
            width: w.inflow,
            value: t.type == TransactionType.inflow ? t.amount : 0,
            color: cs.tertiary,
            enabled: !isTransfer,
            onCommit: (v) => widget.onAmount(t, v, TransactionType.inflow),
          ),
          // Outflow — sits over the red column wash painted behind the grid.
          LedgerAmountCell(
            key: ValueKey('out_${t.id}'),
            width: w.outflow,
            value: t.type == TransactionType.outflow ? t.amount : 0,
            color: cs.onSurface,
            enabled: !isTransfer,
            onCommit: (v) => widget.onAmount(t, v, TransactionType.outflow),
          ),
          // Acct. balance — brighter (onSurface) so it reads as the key figure.
          ledgerReadCell(
            width: w.acctBal,
            right: true,
            child: Text(
              formatPeso(widget.row.accountBalance),
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          // Delete
          SizedBox(
            width: kLedgerTrailingWidth,
            child: Center(
              // IgnorePointer when hidden — a 0-opacity button still hit-tests,
              // causing accidental deletes on non-hovered rows. (U4)
              child: IgnorePointer(
                ignoring: !_hover,
                child: AnimatedOpacity(
                  opacity: _hover ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: IconButton(
                    onPressed: () => widget.onDelete(t),
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    color: cs.onSurfaceVariant,
                    hoverColor: cs.error.withValues(alpha: 0.12),
                    tooltip: 'Delete',
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (isTransfer) {
      body = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onEdit(t),
        child: Tooltip(
          message: 'Edit transfer',
          child: body,
        ),
      );
    }

    return MouseRegion(
      cursor: isTransfer ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: body,
    );
  }
}

// ── Draft add-row ─────────────────────────────────────────────────────────────

class _DraftRow extends StatelessWidget {
  final int epoch;
  final double descWidth;
  final LedgerColWidths widths;
  final DateTime date;
  final String? accountId;
  final String? categoryId;
  final double inflow;
  final double outflow;
  final List<FinancialAccount> accounts;
  final List<FinanceCategory> categories;
  final Color Function(FinanceCategory?) colorFor;
  final ValueChanged<DateTime> onDate;
  final ValueChanged<String> onAccount;
  final ValueChanged<String> onCategory;
  final ValueChanged<String> onDescription;
  final ValueChanged<String> onNote;
  final ValueChanged<double> onInflow;
  final ValueChanged<double> onOutflow;
  final VoidCallback onCommit;

  const _DraftRow({
    required this.epoch,
    required this.descWidth,
    required this.widths,
    required this.date,
    required this.accountId,
    required this.categoryId,
    required this.inflow,
    required this.outflow,
    required this.accounts,
    required this.categories,
    required this.colorFor,
    required this.onDate,
    required this.onAccount,
    required this.onCategory,
    required this.onDescription,
    required this.onNote,
    required this.onInflow,
    required this.onOutflow,
    required this.onCommit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final w = widths;
    return Container(
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.04),
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: kLedgerCheckWidth),
          LedgerDateCell(
            width: w.date,
            date: date,
            enabled: true,
            onChanged: onDate,
          ),
          accounts.isEmpty
              ? ledgerReadCell(width: w.account, child: const Text('—'))
              : LedgerAccountCell(
                  width: w.account,
                  // Null until the user picks — shows the "Account" placeholder
                  // so the draft reads as an empty add-row, not a real entry.
                  value: accountId,
                  accounts: accounts,
                  onChanged: onAccount,
                ),
          LedgerInlineText(
            key: ValueKey('draft_desc_$epoch'),
            width: descWidth,
            initialValue: '',
            hintText: 'Add a row…',
            bold: true,
            onCommit: onDescription,
            onChanged: onDescription,
            onSubmit: onCommit,
          ),
          categories.isEmpty
              ? ledgerReadCell(width: w.category, child: const Text('—'))
              : LedgerCategoryCell(
                  width: w.category,
                  // Null until picked — shows the "Category" placeholder.
                  value: categoryId,
                  categories: categories,
                  colorFor: colorFor,
                  onChanged: onCategory,
                ),
          LedgerAmountCell(
            key: ValueKey('draft_in_$epoch'),
            width: w.inflow,
            value: inflow,
            color: cs.tertiary,
            onCommit: onInflow,
            onChanged: onInflow,
            onSubmit: onCommit,
          ),
          LedgerAmountCell(
            key: ValueKey('draft_out_$epoch'),
            width: w.outflow,
            value: outflow,
            color: cs.onSurface,
            onCommit: onOutflow,
            onChanged: onOutflow,
            onSubmit: onCommit,
          ),
          ledgerReadCell(
            width: w.acctBal,
            right: true,
            child: Text(
              '—',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          SizedBox(
            width: kLedgerTrailingWidth,
            child: Center(
              child: IconButton(
                onPressed: onCommit,
                icon: const Icon(Icons.check_rounded, size: 16),
                color: cs.primary,
                tooltip: 'Add row',
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Loading ─────────────────────────────────────────────────────────────────────

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 64),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Add-Transaction modal
// ═══════════════════════════════════════════════════════════════════════════════

/// Opens the web ledger's edit dialog for [txn] from outside the ledger page —
/// e.g. a line on a credit statement's item list. Same dialog, and the same
/// account refresh first, as editing a transfer row in the grid.
Future<void> showWebEditTransactionDialog(
  BuildContext context, {
  required LedgerPresenter presenter,
  required TransactionRecord txn,
}) async {
  await presenter.reloadAccounts();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _AddTransactionDialog(presenter: presenter, existing: txn),
  );
}

class _AddTransactionDialog extends StatefulWidget {
  final LedgerPresenter presenter;
  final ParsedTransaction? prefill;

  /// When set, the dialog edits this transaction instead of adding a new one.
  /// For a transfer, pass either leg — both are rebuilt from the shared group.
  final TransactionRecord? existing;
  const _AddTransactionDialog({
    required this.presenter,
    this.prefill,
    this.existing,
  });

  @override
  State<_AddTransactionDialog> createState() => _AddTransactionDialogState();
}

class _AddTransactionDialogState extends State<_AddTransactionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _noteController = TextEditingController();
  final _owedByController = TextEditingController();

  TransactionType _type = TransactionType.outflow;
  String? _accountId;
  String? _toAccountId;
  String? _categoryId;
  DateTime _date = DateTime.now();

  // Reimbursable / loan state (outflow only): money out now, owed back later.
  // [_expectedReimbursementDate] null = "ASAP" (surfaces in the current month);
  // a date buckets the spawned receivable into that month instead.
  bool _reimbursable = false;
  DateTime? _expectedReimbursementDate;

  // Installment purchase state (outflow on liability account only):
  bool _splitInstallments = false;
  int _installmentMonths = 3;
  double _interestRate = 0.0;

  FinancialAccount? get _selectedAccount =>
      _accounts.where((a) => a.id == _accountId).firstOrNull;

  bool _isSubmitting = false;
  bool _showFieldErrors = false;

  LedgerPresenter get _p => widget.presenter;

  List<FinancialAccount> get _accounts =>
      _p.accounts.where((a) => a.isActive && !a.isSubAccount).toList();

  List<FinanceCategory> get _filteredCategories {
    if (_type == TransactionType.inflow) {
      return _p.categories.where((c) => c.type == CategoryType.income).toList();
    }
    return _p.categories.where((c) => c.type == CategoryType.expense).toList();
  }

  @override
  void initState() {
    super.initState();
    final editing = widget.existing;
    if (editing != null) {
      _initFromExisting(editing);
      return;
    }
    final liquid = _accounts;
    final pre = widget.prefill;
    if (pre?.type != null) _type = pre!.type!;
    _accountId =
        (pre?.accountId != null && liquid.any((a) => a.id == pre!.accountId))
            ? pre!.accountId
            : liquid.firstOrNull?.id;
    _toAccountId = (pre?.transferToAccountId != null &&
            liquid.any((a) => a.id == pre!.transferToAccountId))
        ? pre!.transferToAccountId
        : (liquid.length > 1 ? liquid[1].id : null);
    if (pre?.categoryId != null &&
        _filteredCategories.any((c) => c.id == pre!.categoryId)) {
      _categoryId = pre!.categoryId;
    }
    if (pre?.amount != null && pre!.amount! > 0) {
      _amountController.text = pre.amount!.toStringAsFixed(2);
    }
    if (pre != null && pre.description.isNotEmpty) {
      _descriptionController.text = pre.description;
    }
    if (pre?.reimbursable == true) _reimbursable = true;
  }

  /// Hydrates the form from an existing record. A transfer is two legs sharing a
  /// `transferGroupId` (neither leg's `type` is `transfer`), so rebuild From/To
  /// from the pair rather than the single leg's fields.
  void _initFromExisting(TransactionRecord t) {
    _amountController.text = t.amount.toStringAsFixed(2);
    _descriptionController.text = t.description;
    _noteController.text = t.note ?? '';
    _date = t.date;
    if (t.transferGroupId != null) {
      _type = TransactionType.transfer;
      String? fromId;
      String? toId;
      for (final leg in _p.allTransactions) {
        if (leg.transferGroupId != t.transferGroupId) continue;
        if (leg.type == TransactionType.outflow) fromId = leg.accountId;
        if (leg.type == TransactionType.inflow) toId = leg.accountId;
      }
      _accountId = fromId ?? t.accountId;
      _toAccountId = toId ?? t.transferToAccountId;
    } else {
      _type = t.type;
      _accountId = t.accountId;
      _categoryId = t.categoryId;
      _reimbursable = t.reimbursable;
      _owedByController.text = t.owedBy ?? '';
      // The expected payback date lives on the linked receivable, not the txn —
      // load it so editing a scheduled reimbursable doesn't show (and re-save)
      // "ASAP". Null stays "ASAP".
      final receivableId = t.reimbursementReceivableId;
      if (t.reimbursable && receivableId != null) {
        _expectedReimbursementDate =
            _p.reimbursementReceivableExpectedDate(receivableId);
      }
      if (t.isInstallment) {
        _splitInstallments = true;
        if (t.installmentId != null) {
          final inst = _p.findInstallmentById(t.installmentId!);
          if (inst != null) {
            _installmentMonths = inst.totalMonths;
            _interestRate = inst.interestRate;
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _noteController.dispose();
    _owedByController.dispose();
    super.dispose();
  }

  void _setType(TransactionType t) {
    setState(() {
      _type = t;
      _categoryId = null;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickReimbursementDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _expectedReimbursementDate ?? _date.add(const Duration(days: 30)),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _expectedReimbursementDate = picked);
  }

  String _genId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';

  Future<void> _submit() async {
    final formOk = _formKey.currentState!.validate();
    // Account & category are now searchable dropdowns (not form fields), so
    // validate them manually and surface inline errors on the first attempt.
    final accountMissing = _accountId == null;
    final toAccountMissing =
        _type == TransactionType.transfer && _toAccountId == null;
    final categoryMissing = _type != TransactionType.transfer &&
        _filteredCategories.isNotEmpty &&
        _categoryId == null;
    if (!formOk || accountMissing || toAccountMissing || categoryMissing) {
      setState(() => _showFieldErrors = true);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final amount = double.parse(_amountController.text.replaceAll(',', ''));
      final description = _descriptionController.text.trim();
      final note = _noteController.text.trim();
      final month = toMonthKey(_date);
      final existing = widget.existing;

      if (_type == TransactionType.transfer) {
        // Editing a transfer: drop the old pair first, since addTransfer always
        // mints a fresh outflow+inflow — otherwise the edit would duplicate the
        // transfer and double-apply both account balances.
        if (existing != null) {
          await _p.deleteTransactionOrGroup(existing.id);
        }
        await _p.addTransfer(
          fromAccountId: _accountId!,
          toAccountId: _toAccountId!,
          amount: amount,
          description: description.isEmpty ? 'Transfer' : description,
          date: _date,
          note: note.isEmpty ? null : note,
        );
      } else if (_type == TransactionType.outflow &&
          _splitInstallments &&
          _p.canSplitIntoInstallments(existing) &&
          _selectedAccount?.isLiability == true) {
        // New purchase, in-place edit of an existing one, or conversion of a
        // regular record: the presenter owns all three.
        await _p.saveInstallmentPurchase(
          existing: existing,
          accountId: _accountId!,
          amount: amount,
          months: _installmentMonths,
          interestRate: _interestRate,
          date: _date,
          description: description,
          note: note,
          categoryId: _categoryId,
        );
      } else {
        // Reimbursable only applies to outflows. Reuse the existing linked
        // receivable id when editing so the link survives; mint one otherwise.
        final isReimbursable =
            _type == TransactionType.outflow && _reimbursable;
        final receivableId = isReimbursable
            ? (existing?.reimbursementReceivableId ?? _genId())
            : null;
        final owedBy = _owedByController.text.trim();
        // Null = "ASAP / no set date" — surfaces in the current month.
        final expectedDate = _expectedReimbursementDate;
        // Reuse the existing id when editing a normal record so the row updates
        // in place; mint a new one when adding (or converting a transfer).
        final id = (existing != null && existing.transferGroupId == null)
            ? existing.id
            : _genId();
        final txn = TransactionRecord(
          id: id,
          date: _date,
          accountId: _accountId!,
          categoryId: _categoryId ?? '',
          amount: amount,
          type: _type,
          description: description,
          note: note.isEmpty ? null : note,
          month: month,
          reimbursable: isReimbursable,
          reimbursementReceivableId: receivableId,
          owedBy: isReimbursable && owedBy.isNotEmpty ? owedBy : null,
        );
        if (existing != null) {
          // A stale linked receivable (no longer reimbursable) is retired by
          // updateTransaction itself.
          final oldReceivableId = existing.reimbursementReceivableId;
          if (existing.transferGroupId != null) {
            // Converting a transfer into a normal income/expense: remove the
            // whole transfer group, then add the single replacement record.
            await _p.deleteTransactionOrGroup(existing.id);
            await _p.addTransaction(txn);
          } else if (existing.isInstallment) {
            // Split turned off, or moved off a credit account: the plan goes
            // and the record takes its full balance effect, exactly once.
            await _p.convertInstallmentPurchaseToRegular(txn);
          } else {
            await _p.updateTransaction(txn);
          }
          // Newly reimbursable → spawn the linked receivable; still reimbursable
          // → re-sync its amount/name/owedBy so it never drifts.
          if (isReimbursable && oldReceivableId == null) {
            await _p.spawnReimbursementReceivable(txn, expectedDate);
          } else if (isReimbursable) {
            // Propagate the (possibly changed or cleared) payback date so the
            // edit actually updates the receivable's schedule, not just its
            // amount/name.
            await _p.syncReimbursementReceivable(
              txn,
              updateExpectedDate: true,
              expectedDate: expectedDate,
            );
          }
        } else if (isReimbursable) {
          await _p.addReimbursableExpense(
            txn,
            expectedReimbursementDate: expectedDate,
          );
        } else {
          await _p.addTransaction(txn);
        }
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isTransfer = _type == TransactionType.transfer;
    final isEdit = widget.existing != null;

    return Dialog(
      backgroundColor: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                WebInsets.xl,
                WebInsets.lg,
                WebInsets.md,
                WebInsets.lg,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isEdit ? 'Edit Transaction' : 'Add Transaction',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(WebInsets.xl),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ModalTypeSegments(selected: _type, onChanged: _setType),
                      const SizedBox(height: WebInsets.xl),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _amountField()),
                          const SizedBox(width: WebInsets.lg),
                          Expanded(child: _dateField(context)),
                        ],
                      ),
                      const SizedBox(height: WebInsets.lg),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _accountDropdown(
                              label: isTransfer ? 'From Account' : 'Account',
                              value: _accountId,
                              onChanged: (v) => setState(() => _accountId = v),
                            ),
                          ),
                          const SizedBox(width: WebInsets.lg),
                          Expanded(
                            child: isTransfer
                                ? _accountDropdown(
                                    label: 'To Account',
                                    value: _toAccountId,
                                    onChanged: (v) =>
                                        setState(() => _toAccountId = v),
                                  )
                                : _categoryDropdown(),
                          ),
                        ],
                      ),
                      const SizedBox(height: WebInsets.lg),
                      _labeledField(
                        'Description',
                        TextFormField(
                          controller: _descriptionController,
                          maxLength: 60,
                          decoration: const InputDecoration(
                            isDense: true,
                            counterText: '',
                            hintText: 'e.g. Grocery run at S&R',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) && !isTransfer
                                  ? 'Enter a description'
                                  : null,
                        ),
                      ),
                      const SizedBox(height: WebInsets.lg),
                      _labeledField(
                        'Notes (optional)',
                        TextFormField(
                          controller: _noteController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'Add a note…',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      if (_type == TransactionType.outflow) ...[
                        if (_p.canSplitIntoInstallments(widget.existing) &&
                            _selectedAccount?.isLiability == true) ...[
                          const SizedBox(height: WebInsets.lg),
                          _installmentSection(theme, isEdit: isEdit),
                        ],
                        if (!_splitInstallments) ...[
                          const SizedBox(height: WebInsets.lg),
                          _reimbursableSection(theme),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
            Padding(
              padding: const EdgeInsets.all(WebInsets.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: WebInsets.sm),
                  FilledButton.icon(
                    onPressed: _isSubmitting ? null : _submit,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(isEdit ? Icons.check_rounded : Icons.add_rounded,
                            size: 18),
                    label: Text(isEdit
                        ? (_splitInstallments
                            ? 'Convert to Installments'
                            : 'Save Changes')
                        : (_splitInstallments
                            ? 'Add Installment'
                            : 'Add Transaction')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _labeledField(String label, Widget field) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
        ),
        const SizedBox(height: WebInsets.sm),
        field,
      ],
    );
  }

  /// "Split into installments" — logs a purchase on a credit / BNPL liability
  /// account as an installment plan. Holds credit limit now without inflating
  /// the current month's cash expenses.
  Widget _installmentSection(ThemeData theme, {bool isEdit = false}) {
    final cs = theme.colorScheme;
    final amount =
        double.tryParse(_amountController.text.replaceAll(',', '')) ?? 0.0;
    final monthly = _installmentMonths > 0 && amount > 0
        ? Installment.computeMonthlyAmount(
            principal: amount,
            months: _installmentMonths,
            monthlyRate: _interestRate,
          )
        : 0.0;
    final totalPayable = monthly * _installmentMonths;
    final totalInterest = (totalPayable - amount).clamp(0.0, double.infinity);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      padding: const EdgeInsets.fromLTRB(
          WebInsets.md, WebInsets.sm, WebInsets.md, WebInsets.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEdit
                          ? 'Convert to installments'
                          : 'Split into installments',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isEdit
                          ? 'Converts this entry into an installment plan: removes immediate lump-sum spending and bills it cycle-by-cycle.'
                          : 'Holds credit limit now, but monthly dues are billed per cycle under this category.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _splitInstallments,
                onChanged: (v) => setState(() {
                  _splitInstallments = v;
                  if (v) _reimbursable = false;
                }),
              ),
            ],
          ),
          if (_splitInstallments) ...[
            Divider(height: WebInsets.md, color: cs.outlineVariant),
            Row(
              children: [
                Text(
                  'Duration',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                const Spacer(),
                Wrap(
                  spacing: 6,
                  children: [3, 6, 12, 24].map((m) {
                    final selected = _installmentMonths == m;
                    return InkWell(
                      onTap: () => setState(() => _installmentMonths = m),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected
                              ? cs.primary.withValues(alpha: 0.15)
                              : cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: selected ? cs.primary : cs.outlineVariant,
                          ),
                        ),
                        child: Text(
                          '${m}mo',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected ? cs.primary : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            const SizedBox(height: WebInsets.md),
            Row(
              children: [
                Text(
                  'Interest / mo',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                const Spacer(),
                Wrap(
                  spacing: 6,
                  children: [0.0, 1.0, 1.5, 2.0, 3.0].map((r) {
                    final selected = _interestRate == r;
                    final label = r == 0
                        ? '0%'
                        : '${r == r.roundToDouble() ? r.round() : r}%';
                    return InkWell(
                      onTap: () => setState(() => _interestRate = r),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected
                              ? cs.primary.withValues(alpha: 0.15)
                              : cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: selected ? cs.primary : cs.outlineVariant,
                          ),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected ? cs.primary : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            if (amount > 0) ...[
              const SizedBox(height: WebInsets.sm),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '≈ ${formatPeso(monthly)} / month for $_installmentMonths months',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                    if (_interestRate > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Total interest: ${formatPeso(totalInterest)} · Total payable: ${formatPeso(totalPayable)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// "I'll get this back" — marks an outflow as a reimbursable expense or a loan.
  /// Mirrors the mobile sheet: keeps it out of spending and tracks it as money
  /// you're owed, with an optional payback date (null = ASAP, shows this month).
  Widget _reimbursableSection(ThemeData theme) {
    final cs = theme.colorScheme;
    final date = _expectedReimbursementDate;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      padding: const EdgeInsets.fromLTRB(
          WebInsets.md, WebInsets.sm, WebInsets.md, WebInsets.sm),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "I'll get this back",
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'A reimbursable expense or money you lent out. Leaves your '
                      "cash but isn't counted as spending — we'll track it as "
                      "money you're owed.",
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _reimbursable,
                onChanged: (v) => setState(() => _reimbursable = v),
              ),
            ],
          ),
          if (_reimbursable) ...[
            Divider(height: WebInsets.md, color: cs.outlineVariant),
            InkWell(
              onTap: _pickReimbursementDate,
              borderRadius: BorderRadius.circular(AppRadii.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: WebInsets.sm),
                child: Row(
                  children: [
                    Icon(Icons.event_outlined,
                        size: 18, color: cs.onSurfaceVariant),
                    const SizedBox(width: WebInsets.sm),
                    Expanded(
                      child: Text('Expected back by',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant)),
                    ),
                    if (date == null)
                      // No date: "ASAP" — surfaces in the current month. Tapping
                      // the row opens the picker to set a scheduled date.
                      Text('ASAP',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600))
                    else ...[
                      Text(DateFormat('MMM d, yyyy').format(date),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () =>
                            setState(() => _expectedReimbursementDate = null),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(Icons.close,
                              size: 16, color: cs.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: WebInsets.sm),
            TextFormField(
              controller: _owedByController,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: 'Who owes you? (optional)',
                isDense: true,
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _amountField() {
    return _labeledField(
      'Amount',
      TextFormField(
        controller: _amountController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
        decoration: const InputDecoration(
          isDense: true,
          prefixText: '₱ ',
          hintText: '0.00',
          border: OutlineInputBorder(),
        ),
        validator: (v) {
          if (v == null || v.isEmpty) return 'Enter an amount';
          final parsed = double.tryParse(v.replaceAll(',', ''));
          if (parsed == null || parsed <= 0) return 'Must be > 0';
          return null;
        },
      ),
    );
  }

  Widget _dateField(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _labeledField(
      'Date',
      InkWell(
        onTap: _pickDate,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: InputDecorator(
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          child: Row(
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 16,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: WebInsets.sm),
              Expanded(
                child: Text(
                  DateFormat('MMM d, yyyy').format(_date),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _accountDropdown({
    required String label,
    required String? value,
    required ValueChanged<String> onChanged,
  }) {
    final accounts = _accounts;
    final entries = [
      for (var i = 0; i < accounts.length; i++)
        WebDropdownEntry<String>(
          value: accounts[i].id,
          label: accounts[i].name,
          dotColor: resolveSliceColor(
            accounts[i].colorHex,
            i,
            brightness: Theme.of(context).brightness,
          ),
        ),
    ];
    return _labeledField(
      label,
      _decoratedField(
        error: _showFieldErrors && value == null ? 'Select an account' : null,
        child: WebSearchableDropdown<String>(
          value: accounts.any((a) => a.id == value) ? value : null,
          hintText: 'Select…',
          entries: entries,
          isDense: true,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _categoryDropdown() {
    final cats = _filteredCategories;
    final entries = [
      for (var i = 0; i < cats.length; i++)
        WebDropdownEntry<String>(
          value: cats[i].id,
          label: cats[i].name,
          dotColor: resolveSliceColor(
            cats[i].colorHex,
            i,
            brightness: Theme.of(context).brightness,
          ),
        ),
    ];
    final showError =
        _showFieldErrors && cats.isNotEmpty && _categoryId == null;
    return _labeledField(
      'Category',
      _decoratedField(
        error: showError ? 'Select a category' : null,
        child: WebSearchableDropdown<String>(
          value: cats.any((c) => c.id == _categoryId) ? _categoryId : null,
          hintText: cats.isEmpty ? 'No categories' : 'Select…',
          entries: entries,
          isDense: true,
          onChanged: (v) => setState(() => _categoryId = v),
        ),
      ),
    );
  }

  /// Wraps a [WebSearchableDropdown] in an outlined box matching the dialog's
  /// other form fields, with an optional inline error message below it.
  Widget _decoratedField({required Widget child, String? error}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border: Border.all(color: error != null ? cs.error : cs.outline),
          ),
          child: child,
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(
              top: WebInsets.xs,
              left: WebInsets.sm,
            ),
            child: Text(
              error,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
            ),
          ),
      ],
    );
  }
}

class _ModalTypeSegments extends StatelessWidget {
  final TransactionType selected;
  final ValueChanged<TransactionType> onChanged;
  const _ModalTypeSegments({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 40,
      padding: const EdgeInsets.all(WebInsets.xs),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          _seg(context, TransactionType.outflow, 'Expense'),
          _seg(context, TransactionType.inflow, 'Income'),
          _seg(context, TransactionType.transfer, 'Transfer'),
        ],
      ),
    );
  }

  Widget _seg(BuildContext context, TransactionType value, String label) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = value == selected;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Material(
          color: isSelected ? cs.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.sm - 2),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.sm - 2),
            onTap: () => onChanged(value),
            child: Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
