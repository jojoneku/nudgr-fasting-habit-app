import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/finance_parse_result.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/app_radii.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/web/web_keys.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

import '../../design/web_breakpoints.dart';
import '../../design/web_constants.dart';
import '../../widgets/web_badge.dart';
import '../../widgets/web_dialog.dart';
import '../../widgets/web_month_stepper.dart';
import '../../widgets/web_page_header_v2.dart';
import '../../widgets/web_receipt_drop.dart';
import '../../widgets/web_row_menu.dart';
import '../../widgets/web_searchable_dropdown.dart';
import 'ledger_cells.dart';
import 'ledger_filters.dart';
import 'ledger_filters_popover.dart';
import 'ledger_keys_v2.dart';
import 'web_transaction_dialog_v2.dart';

/// One enriched, display-ready ledger row.
typedef _Row = ({
  TransactionRecord txn,
  double runningBalance,
  double accountBalance,
});

/// The v2 Ledger page (Plan 063, Phase 4 — `Ledger.dc.html`).
///
/// Same inputs as the pre-v2 `WebLedgerPage`, plus a [trailing] slot the shell
/// fills with the Nudgy header button and an [onOpenSetup] callback for the
/// "no accounts" empty state. Every presenter call is the one the old page
/// made; what changed is the chrome: a `WebPageHeaderV2` with the month
/// stepper, Scan a receipt and Add transaction in the toolbar (no floating
/// buttons), notes under the description, a ⋯ menu on every row instead of a
/// hover-only delete, a footer with the month's totals, and the Add / Edit
/// dialog rebuilt on the shared kit.
class WebLedgerPageV2 extends StatefulWidget {
  final LedgerPresenter presenter;

  /// Filter/sort state, owned above the page so leaving the Ledger destination
  /// and coming back doesn't silently drop the filters the user set. Optional:
  /// without one the page keeps a private set.
  final WebLedgerFilters? filters;

  /// Shown after the page's own header actions (the shell's Ask Nudgy).
  final Widget? trailing;

  /// Opens Setup & Accounts from the "no accounts" empty state.
  final VoidCallback? onOpenSetup;

  const WebLedgerPageV2({
    super.key,
    required this.presenter,
    this.filters,
    this.trailing,
    this.onOpenSetup,
  });

  @override
  State<WebLedgerPageV2> createState() => _WebLedgerPageV2State();
}

class _WebLedgerPageV2State extends State<WebLedgerPageV2> {
  final _searchController = TextEditingController();
  final _gridHScroll = ScrollController();
  final _gridVScroll = ScrollController();

  /// Compact defaults so the grid fits the 1200 px content column without a
  /// horizontal scroll; drag a header edge to widen any column.
  final _col = LedgerColWidths(
    date: 96,
    account: 176,
    category: 170,
    inflow: 112,
    outflow: 112,
    acctBal: 132,
  );

  late final WebLedgerFilters _f = widget.filters ?? WebLedgerFilters();
  bool get _ownsFilters => widget.filters == null;
  String get _query => _f.query;

  final Set<String> _selected = <String>{};

  // Draft "add a row" state.
  late DateTime _draftDate;
  String? _draftAccountId;
  String? _draftCategoryId;
  String _draftDesc = '';
  double _draftInflow = 0;
  double _draftOutflow = 0;
  int _draftEpoch = 0;
  String? _draftError;

  Timer? _searchDebounce;
  bool _drainingToForm = false;

  LedgerPresenter get _p => widget.presenter;

  @override
  void initState() {
    super.initState();
    _draftDate = DateTime.now();
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

  // ── Assistant leftovers → form ─────────────────────────────────────────────

  /// The web surface that owns the transaction form answers when the parser
  /// hands an entry back; see the pre-v2 page for the history.
  void _onLedgerNeedsForm() {
    if (!mounted || _drainingToForm) return;
    if (_p.pendingFormPrefill == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _drainToForm();
    });
  }

  Future<void> _drainToForm() async {
    if (_drainingToForm) return;
    _drainingToForm = true;
    try {
      var prefill = _p.pendingFormPrefill;
      _p.consumeFormPrefill();
      while (prefill != null && mounted) {
        final remaining = _p.queuedFormPrefillCount;
        if (remaining > 0) {
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

  // ── Filtering + sorting (View-side) ────────────────────────────────────────

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

      // Numeric match: "1000" finds ₱1,000.00 and "10" finds ₱10.00.
      var amountMatch = false;
      final cleaned =
          _query.replaceAll('₱', '').replaceAll(' ', '').replaceAll(',', '');
      final n = double.tryParse(cleaned);
      if (n != null) {
        final fixed = t.amount.toStringAsFixed(2);
        final grouped = NumberFormat('#,##0.00', 'en_PH').format(t.amount);
        amountMatch = t.amount == n ||
            fixed.contains(cleaned) ||
            grouped.contains(_query);
      }

      if (!textMatch && !amountMatch) return false;
    }
    return true;
  }

  List<_Row> _sorted(List<_Row> rows) {
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

  String get _sortLabel {
    if (_f.sortKey == null) return 'date';
    final preset = ledgerSortPresetFor(_f.sortKey, _f.sortDir);
    if (preset != null) return preset.label.toLowerCase();
    return '${_f.sortKey!.name} ${_f.sortDir > 0 ? '↑' : '↓'}';
  }

  void _clearFilters() {
    _searchController.clear();
    _f
      ..clear()
      ..setQuery('');
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

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

  /// A row's two amount columns are views of the single `amount`+`type`.
  /// Writing a positive value flips the row to that direction; zero/empty is
  /// ignored (revert). Flipping direction clears the category, as on mobile.
  void _editAmount(TransactionRecord t, double value, TransactionType dir) {
    if (value <= 0) return;
    if (t.type == dir && t.amount == value) return;
    final flippedType = t.type != dir;
    _commitInline(t.copyWith(
      type: dir,
      amount: value,
      categoryId: flippedType ? '' : t.categoryId,
    ));
  }

  /// Deleting one row goes straight through, with a 6 s Undo — the same
  /// contract as the phone's swipe-to-delete.
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

  /// Bulk delete confirms first — one click wiping many rows deserves a beat —
  /// and offers Undo after.
  Future<void> _deleteSelected() async {
    final ids = _selected.toSet();
    if (ids.isEmpty) return;
    final n = ids.length;
    final ok = await showWebConfirm(
      context,
      title: n == 1 ? 'Delete 1 transaction?' : 'Delete $n transactions?',
      message: 'Account balances recalculate. You can undo this for 6 seconds.',
      confirmLabel: 'Delete $n',
    );
    if (!ok || !mounted) return;
    setState(_selected.clear);
    final removed = await _p.deleteTransactions(ids);
    if (removed.isEmpty || !mounted) return;
    _offerUndo('Deleted ${removed.length} transactions', removed);
  }

  void _offerUndo(String message, List<TransactionRecord> removed) {
    AppToast.action(
      context,
      message: message,
      actionLabel: 'Undo',
      icon: Icons.delete_outline_rounded,
      duration: const Duration(seconds: 6),
      onAction: () => _p.restoreTransactions(removed),
    );
  }

  /// "Change category" on the selection bar: one picker, applied to every
  /// selected non-transfer row through the same inline update a single cell
  /// edit uses (there is no bulk category method on the presenter).
  Future<void> _changeCategoryForSelection(List<_Row> rows) async {
    final targets = [
      for (final r in rows)
        if (_selected.contains(r.txn.id) && r.txn.transferGroupId == null)
          r.txn,
    ];
    if (targets.isEmpty) {
      AppToast.show(context, 'Transfers carry no category.');
      return;
    }
    final types = targets.map((t) => t.type).toSet();
    final cats = types.length == 1
        ? _categoriesFor(types.first)
        : _p.categories
            .where((c) => c.id != FinanceCategory.transferCategoryId)
            .toList();
    final picked = await showWebDialog<String>(
      context,
      builder: (ctx) => _ChangeCategoryDialog(
        count: targets.length,
        categories: cats,
        colorFor: _colorFor,
      ),
    );
    if (picked == null || !mounted) return;
    for (final t in targets) {
      if (t.categoryId == picked) continue;
      await _p.updateRecordInline(t.copyWith(categoryId: picked));
    }
    if (!mounted) return;
    setState(_selected.clear);
    AppToast.success(
      context,
      'Changed category on ${targets.length} '
      '${targets.length == 1 ? 'transaction' : 'transactions'}',
    );
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
    // matches the add-transaction dialog. Shown inline under the draft row
    // (the pre-v2 page raised a toast with the same copy).
    final picked = _draftCategoryId;
    if (cats.isNotEmpty &&
        (picked == null || !cats.any((c) => c.id == picked))) {
      setState(() => _draftError = 'Pick a category before adding the row.');
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
        month: toMonthKey(_draftDate),
      ),
    );
    setState(() {
      _draftDesc = '';
      _draftInflow = 0;
      _draftOutflow = 0;
      _draftCategoryId = null;
      _draftDate = DateTime.now();
      _draftError = null;
      _draftEpoch++; // reset inline controllers
    });
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────

  Future<void> _openAddDialog([ParsedTransaction? prefill]) =>
      showWebTransactionDialogV2(context, presenter: _p, prefill: prefill);

  Future<void> _openEditDialog(
    TransactionRecord t, {
    bool split = false,
    bool reimbursable = false,
  }) =>
      showWebTransactionDialogV2(
        context,
        presenter: _p,
        existing: t,
        splitInstallments: split,
        reimbursable: reimbursable,
        onDelete: _deleteRow,
      );

  Future<void> _duplicate(TransactionRecord t) =>
      showWebTransactionDialogV2(context, presenter: _p, duplicateOf: t);

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _p,
      builder: (context, _) =>
          _p.isLoading ? const _LoadingBlock() : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final spansAll = _f.spansAllMonths;
    final all =
        spansAll ? _p.ledgerSpreadsheetRowsAllMonths : _p.ledgerSpreadsheetRows;
    final rows = _sorted(all.where(_matches).toList());
    final monthCount = _p.ledgerSpreadsheetRows.length;
    final month = monthLabel(_p.selectedMonth);
    final inflow = _p.tableInflow;
    final outflow = _p.tableOutflow;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WebPageHeaderV2(
          title: 'Ledger',
          subtitle: '$month · $monthCount '
              '${monthCount == 1 ? 'transaction' : 'transactions'} · '
              'In ${formatPeso(inflow)} · Out ${formatPeso(outflow)}',
          monthStepper: spansAll
              ? _ScopePill(
                  key: LedgerKeysV2.scopePill,
                  label: 'All months · ${rows.length} '
                      '${rows.length == 1 ? 'match' : 'matches'}',
                )
              : WebMonthStepper(
                  key: WebKeys.ledgerMonthStepper,
                  label: month,
                  onPrev: () => _p.setMonth(previousMonth(_p.selectedMonth)),
                  onNext: () => _p.setMonth(nextMonth(_p.selectedMonth)),
                ),
          actions: [
            OutlinedButton.icon(
              key: WebKeys.ledgerScanReceipt,
              onPressed: () => showWebReceiptDialog(context, ledger: _p),
              icon: const Icon(Icons.document_scanner_outlined, size: 16),
              label: const Text('Scan a receipt'),
            ),
            FilledButton.icon(
              key: WebKeys.ledgerAddTransaction,
              onPressed: () => _openAddDialog(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add transaction'),
            ),
            if (widget.trailing != null) widget.trailing!,
          ],
        ),
        _ToolbarV2(
          searchController: _searchController,
          filters: _f,
          accounts: _liquidAccounts,
          categories: _p.categories,
          accountName: _accountName,
          categoryName: (id) => _categoryOf(id)?.name ?? '—',
          sortLabel: _sortLabel,
          rowCount: rows.length,
          onClear: _clearFilters,
        ),
        const SizedBox(height: WebInsets.lg),
        Expanded(
          child: _buildTableCard(
            context,
            rows,
            month: month,
            inflow: inflow,
            outflow: outflow,
          ),
        ),
      ],
    );
  }

  Widget _buildTableCard(
    BuildContext context,
    List<_Row> rows, {
    required String month,
    required double inflow,
    required double outflow,
  }) {
    final cs = Theme.of(context).colorScheme;
    final allSelected =
        rows.isNotEmpty && rows.every((r) => _selected.contains(r.txn.id));

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: cs.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_selected.isNotEmpty)
            _SelectionBarV2(
              count: _selected.length,
              onClear: () => setState(_selected.clear),
              onChangeCategory: () => _changeCategoryForSelection(rows),
              onDelete: _deleteSelected,
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final avail = constraints.maxWidth;
                final descW = max(kLedgerDescMinWidth, avail - _col.fixedSum);
                final gridW = _col.fixedSum + descW;
                return Scrollbar(
                  controller: _gridHScroll,
                  thumbVisibility: gridW > avail,
                  child: SingleChildScrollView(
                    controller: _gridHScroll,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: gridW,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _GridHeaderV2(
                            descWidth: descW,
                            widths: _col,
                            sortKey: _f.sortKey,
                            sortDir: _f.sortDir,
                            allSelected: allSelected,
                            onToggleAll: () => setState(() {
                              if (allSelected) {
                                _selected.clear();
                              } else {
                                _selected.addAll(rows.map((r) => r.txn.id));
                              }
                            }),
                            onSort: _f.toggleHeaderSort,
                            onResize: (col, d) =>
                                setState(() => _col.resize(col, d)),
                          ),
                          _DraftRowV2(
                            epoch: _draftEpoch,
                            descWidth: descW,
                            widths: _col,
                            date: _draftDate,
                            accountId: _draftAccountId,
                            categoryId: _draftCategoryId,
                            inflow: _draftInflow,
                            outflow: _draftOutflow,
                            error: _draftError,
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
                            onCategory: (id) => setState(() {
                              _draftCategoryId = id;
                              _draftError = null;
                            }),
                            onDescription: (v) => _draftDesc = v,
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
                          Expanded(
                            child: Scrollbar(
                              controller: _gridVScroll,
                              thumbVisibility: true,
                              child: rows.isEmpty
                                  ? ListView(
                                      controller: _gridVScroll,
                                      padding: EdgeInsets.zero,
                                      children: [
                                        _EmptyHintV2(
                                          hasAccounts:
                                              _liquidAccounts.isNotEmpty,
                                          narrowed: _f.isNarrowed,
                                          onClearFilters: _clearFilters,
                                          onOpenSetup: widget.onOpenSetup,
                                        ),
                                      ],
                                    )
                                  : ListView.builder(
                                      controller: _gridVScroll,
                                      padding: EdgeInsets.zero,
                                      itemCount: rows.length,
                                      itemBuilder: (context, i) {
                                        final r = rows[i];
                                        return _LedgerRowV2(
                                          key: ValueKey(r.txn.id),
                                          row: r,
                                          descWidth: descW,
                                          widths: _col,
                                          selected:
                                              _selected.contains(r.txn.id),
                                          accounts: _liquidAccounts,
                                          categories:
                                              _categoriesFor(r.txn.type),
                                          accountOf: _accountOf,
                                          colorFor: _colorFor,
                                          canSplit: (t) =>
                                              _p.canSplitIntoInstallments(t),
                                          onToggleSelect: () => setState(() {
                                            final id = r.txn.id;
                                            _selected.contains(id)
                                                ? _selected.remove(id)
                                                : _selected.add(id);
                                          }),
                                          onDate: _editDate,
                                          onAccount: _editAccount,
                                          onCategory: _editCategory,
                                          onDescription: _editDescription,
                                          onAmount: _editAmount,
                                          onDelete: _deleteRow,
                                          onEdit: (t) => _openEditDialog(t),
                                          onDuplicate: _duplicate,
                                          onSplit: (t) => _openEditDialog(
                                            t,
                                            split: true,
                                          ),
                                          onReimbursable: (t) =>
                                              _openEditDialog(
                                            t,
                                            reimbursable: true,
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          _FooterTotals(month: month, inflow: inflow, outflow: outflow),
        ],
      ),
    );
  }
}

DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _dayEnd(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59);

// ═══════════════════════════════════════════════════════════════════════════════
// Toolbar — search · Filters & sort · active chips · Clear all · sort summary
// ═══════════════════════════════════════════════════════════════════════════════

class _ToolbarV2 extends StatelessWidget {
  final TextEditingController searchController;
  final WebLedgerFilters filters;
  final List<FinancialAccount> accounts;
  final List<FinanceCategory> categories;
  final String Function(String?) accountName;
  final String Function(String?) categoryName;
  final String sortLabel;
  final int rowCount;
  final VoidCallback onClear;

  const _ToolbarV2({
    required this.searchController,
    required this.filters,
    required this.accounts,
    required this.categories,
    required this.accountName,
    required this.categoryName,
    required this.sortLabel,
    required this.rowCount,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final f = filters;
    final df = kLedgerMonthDayFmt;
    final dateLabel = f.fromDate != null && f.toDate != null
        ? '${df.format(f.fromDate!)} → ${df.format(f.toDate!)}'
        : f.fromDate != null
            ? 'From ${df.format(f.fromDate!)}'
            : f.toDate != null
                ? 'Until ${df.format(f.toDate!)}'
                : null;
    final preset = ledgerSortPresetFor(f.sortKey, f.sortDir);
    final sortChip =
        preset?.label ?? (f.sortKey != null ? 'Custom sort' : null);

    final chips = <Widget>[
      for (final id in f.accountIds)
        LedgerActiveChip(
          kind: 'Account',
          label: accountName(id),
          onClear: () => f.toggleAccount(id),
        ),
      for (final id in f.categoryIds)
        LedgerActiveChip(
          kind: 'Category',
          label: categoryName(id),
          onClear: () => f.toggleCategory(id),
        ),
      if (f.type != WebLedgerType.all)
        LedgerActiveChip(
          kind: 'Type',
          label:
              f.type == WebLedgerType.inflow ? 'Inflow only' : 'Outflow only',
          onClear: () => f.setType(WebLedgerType.all),
        ),
      if (dateLabel != null)
        LedgerActiveChip(
          kind: 'Dates',
          label: dateLabel,
          icon: Icons.history,
          onClear: () {
            f.setFromDate(null);
            f.setToDate(null);
          },
        ),
      if (sortChip != null)
        LedgerActiveChip(
          kind: 'Sort',
          label: sortChip,
          icon: Icons.swap_vert_rounded,
          onClear: () => f.setSort(null),
        ),
      if (f.isNarrowed)
        SizedBox(
          height: kLedgerControlHeight,
          child: TextButton(
            key: LedgerKeysV2.clearAll,
            onPressed: onClear,
            child: const Text('Clear all'),
          ),
        ),
    ];

    // The controls and chips wrap as one flow (the canvas toolbar is a
    // flex-wrap); the sort summary stays pinned at the right and shortens
    // rather than overflowing when the column is narrow (Nudgy rail open).
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: WebInsets.sm,
            runSpacing: WebInsets.sm,
            children: [
              _SearchFieldV2(controller: searchController),
              LedgerFiltersPopover(
                label: 'Filters & sort',
                accounts: accounts,
                categories: categories,
                accountIds: f.accountIds,
                categoryIds: f.categoryIds,
                type: f.type,
                fromDate: f.fromDate,
                toDate: f.toDate,
                sortKey: f.sortKey,
                sortDir: f.sortDir,
                activeCount: f.activeCount,
                onAccount: f.toggleAccount,
                onCategory: f.toggleCategory,
                onType: f.setType,
                onFromDate: f.setFromDate,
                onToDate: f.setToDate,
                onSort: f.setSort,
                onClear: onClear,
              ),
              if (chips.isNotEmpty)
                Wrap(
                  key: WebKeys.ledgerActiveChips,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: WebInsets.sm,
                  runSpacing: WebInsets.sm,
                  children: chips,
                ),
            ],
          ),
        ),
        const SizedBox(width: WebInsets.md),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(
            'Sorted by $sortLabel · $rowCount ${rowCount == 1 ? 'row' : 'rows'}',
            key: LedgerKeysV2.sortSummary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontSize: 12.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchFieldV2 extends StatelessWidget {
  final TextEditingController controller;
  const _SearchFieldV2({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(visualDensity: VisualDensity.standard),
      child: SizedBox(
        width: 240,
        height: kLedgerControlHeight,
        child: TextField(
          key: WebKeys.ledgerSearch,
          controller: controller,
          style: WebInput.textStyle(context).copyWith(fontSize: 13.5),
          decoration: WebInput.decoration(
            context,
            hint: 'Search all months…',
            height: kLedgerControlHeight,
          ).copyWith(
            prefixIcon: const Icon(Icons.search_rounded, size: 18),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ),
      ),
    );
  }
}

/// Quiet pill in the stepper's place while a search or date range widens the
/// grid past the selected month.
class _ScopePill extends StatelessWidget {
  final String label;
  const _ScopePill({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      height: kLedgerControlHeight,
      padding: const EdgeInsets.symmetric(horizontal: WebInsets.md),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.travel_explore_rounded, size: 14, color: cs.primary),
          const SizedBox(width: WebInsets.xs),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Selection bar
// ═══════════════════════════════════════════════════════════════════════════════

class _SelectionBarV2 extends StatelessWidget {
  final int count;
  final VoidCallback onClear;
  final VoidCallback onChangeCategory;
  final VoidCallback onDelete;
  const _SelectionBarV2({
    required this.count,
    required this.onClear,
    required this.onChangeCategory,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      key: WebKeys.ledgerSelectionBar,
      padding: const EdgeInsets.symmetric(
        horizontal: WebInsets.lg,
        vertical: WebInsets.sm,
      ),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        border: Border(bottom: BorderSide(color: cs.outline)),
      ),
      child: Row(
        children: [
          Text(
            '$count selected',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(width: WebInsets.sm),
          TextButton(
            key: WebKeys.ledgerSelectionClear,
            onPressed: onClear,
            child: const Text('Clear'),
          ),
          const Spacer(),
          OutlinedButton.icon(
            key: LedgerKeysV2.selectionChangeCategory,
            onPressed: onChangeCategory,
            icon: const Icon(Icons.label_outline_rounded, size: 16),
            label: const Text('Change category'),
          ),
          const SizedBox(width: WebInsets.sm),
          FilledButton.icon(
            key: WebKeys.ledgerSelectionDelete,
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, size: 16),
            label: Text('Delete $count'),
            style: FilledButton.styleFrom(
              backgroundColor: cs.error.withValues(alpha: 0.15),
              foregroundColor: cs.error,
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }
}

/// The category picker behind "Change category".
class _ChangeCategoryDialog extends StatefulWidget {
  final int count;
  final List<FinanceCategory> categories;
  final Color Function(FinanceCategory?) colorFor;
  const _ChangeCategoryDialog({
    required this.count,
    required this.categories,
    required this.colorFor,
  });

  @override
  State<_ChangeCategoryDialog> createState() => _ChangeCategoryDialogState();
}

class _ChangeCategoryDialogState extends State<_ChangeCategoryDialog> {
  String? _picked;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return WebDialog(
      title: 'Change category',
      subtitle: 'Applies to ${widget.count} selected '
          '${widget.count == 1 ? 'transaction' : 'transactions'}.',
      primaryExpands: false,
      body: WebField(
        label: 'Category',
        child: Container(
          height: kWebInputHeight,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: AppRadii.mdBorder,
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: WebSearchableDropdown<String>(
            key: LedgerKeysV2.changeCategoryPicker,
            value: _picked,
            hintText: 'Select…',
            isDense: true,
            entries: [
              for (final c in widget.categories)
                WebDropdownEntry<String>(
                  value: c.id,
                  label: c.name,
                  dotColor: widget.colorFor(c),
                ),
            ],
            onChanged: (v) => setState(() => _picked = v),
          ),
        ),
      ),
      secondary: TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      primary: FilledButton(
        key: LedgerKeysV2.changeCategoryApply,
        onPressed:
            _picked == null ? null : () => Navigator.of(context).pop(_picked),
        child: const Text('Apply'),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Grid header · draft row · rows · empty · footer
// ═══════════════════════════════════════════════════════════════════════════════

class _GridHeaderV2 extends StatelessWidget {
  final double descWidth;
  final LedgerColWidths widths;
  final WebLedgerSortKey? sortKey;
  final int sortDir;
  final bool allSelected;
  final VoidCallback onToggleAll;
  final ValueChanged<WebLedgerSortKey> onSort;
  final void Function(LedgerResizableCol, double) onResize;
  const _GridHeaderV2({
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
        color: cs.surfaceContainerHigh.withValues(alpha: 0.6),
        border: Border(bottom: BorderSide(color: cs.outline)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: kLedgerCheckWidth,
            child: Center(
              child: LedgerCheck(
                key: WebKeys.ledgerSelectAll,
                on: allSelected,
                onTap: onToggleAll,
              ),
            ),
          ),
          _cell('Date', widths.date, WebLedgerSortKey.date,
              resize: LedgerResizableCol.date),
          _cell('Account', widths.account, WebLedgerSortKey.account,
              resize: LedgerResizableCol.account),
          _cell('Description', descWidth, WebLedgerSortKey.description),
          _cell('Category', widths.category, WebLedgerSortKey.category,
              resize: LedgerResizableCol.category),
          _cell('Inflow', widths.inflow, WebLedgerSortKey.inflow,
              right: true, resize: LedgerResizableCol.inflow),
          _cell('Outflow', widths.outflow, WebLedgerSortKey.outflow,
              right: true, resize: LedgerResizableCol.outflow),
          _cell('Balance', widths.acctBal, null,
              right: true, resize: LedgerResizableCol.acctBal),
          const SizedBox(width: kLedgerTrailingWidth),
        ],
      ),
    );
  }

  Widget _cell(
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

/// The 18 px account tile (initials on the account color) drawn before the
/// account name in the Account column.
class _AccountTile extends StatelessWidget {
  final FinancialAccount? account;
  final int index;
  const _AccountTile({required this.account, required this.index});

  static String initials(String name) {
    final words =
        name.split(RegExp(r'[\s()]+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first[0].toUpperCase();
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final a = account;
    if (a == null) return const SizedBox(width: 18, height: 18);
    final color = resolveSliceColor(
      a.colorHex,
      index < 0 ? 0 : index,
      brightness: Theme.of(context).brightness,
    );
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        initials(a.name),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

class _DraftRowV2 extends StatelessWidget {
  final int epoch;
  final double descWidth;
  final LedgerColWidths widths;
  final DateTime date;
  final String? accountId;
  final String? categoryId;
  final double inflow;
  final double outflow;
  final String? error;
  final List<FinancialAccount> accounts;
  final List<FinanceCategory> categories;
  final Color Function(FinanceCategory?) colorFor;
  final ValueChanged<DateTime> onDate;
  final ValueChanged<String> onAccount;
  final ValueChanged<String> onCategory;
  final ValueChanged<String> onDescription;
  final ValueChanged<double> onInflow;
  final ValueChanged<double> onOutflow;
  final VoidCallback onCommit;

  const _DraftRowV2({
    required this.epoch,
    required this.descWidth,
    required this.widths,
    required this.date,
    required this.accountId,
    required this.categoryId,
    required this.inflow,
    required this.outflow,
    required this.error,
    required this.accounts,
    required this.categories,
    required this.colorFor,
    required this.onDate,
    required this.onAccount,
    required this.onCategory,
    required this.onDescription,
    required this.onInflow,
    required this.onOutflow,
    required this.onCommit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final w = widths;
    final acctIndex = accounts.indexWhere((a) => a.id == accountId);
    final acct = acctIndex < 0 ? null : accounts[acctIndex];
    return Container(
      key: WebKeys.ledgerDraftRow,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.35),
        border: Border(bottom: BorderSide(color: cs.outline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(width: kLedgerCheckWidth),
              LedgerDateCell(
                key: LedgerKeysV2.draftDate,
                width: w.date,
                date: date,
                enabled: true,
                onChanged: onDate,
              ),
              accounts.isEmpty
                  ? ledgerReadCell(width: w.account, child: const Text('—'))
                  : SizedBox(
                      width: w.account,
                      child: Row(
                        children: [
                          const SizedBox(width: WebInsets.md),
                          _AccountTile(account: acct, index: acctIndex),
                          const SizedBox(width: WebInsets.xs),
                          LedgerAccountCell(
                            key: LedgerKeysV2.draftAccount,
                            width: w.account - WebInsets.md - 18 - WebInsets.xs,
                            value: accountId,
                            accounts: accounts,
                            hintText: 'Account…',
                            showDots: false,
                            onChanged: onAccount,
                          ),
                        ],
                      ),
                    ),
              LedgerInlineText(
                key: ValueKey('${LedgerKeysV2.draftDescription.value}_$epoch'),
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
                      key: LedgerKeysV2.draftCategory,
                      width: w.category,
                      value: categoryId,
                      categories: categories,
                      colorFor: colorFor,
                      hintText: 'Category…',
                      onChanged: onCategory,
                    ),
              LedgerAmountCell(
                key: ValueKey('${LedgerKeysV2.draftInflow.value}_$epoch'),
                width: w.inflow,
                value: inflow,
                color: cs.tertiary,
                onCommit: onInflow,
                onChanged: onInflow,
                onSubmit: onCommit,
              ),
              LedgerAmountCell(
                key: ValueKey('${LedgerKeysV2.draftOutflow.value}_$epoch'),
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
                  'auto',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.appColors.textMuted,
                  ),
                ),
              ),
              SizedBox(
                width: kLedgerTrailingWidth,
                child: Center(
                  child: IconButton(
                    key: WebKeys.ledgerDraftAdd,
                    onPressed: onCommit,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    color: cs.primary,
                    tooltip: 'Add row',
                    style: IconButton.styleFrom(
                      minimumSize: const Size(kWebHitTarget, kWebHitTarget),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (error != null)
            Padding(
              key: LedgerKeysV2.draftError,
              padding: const EdgeInsets.fromLTRB(
                kLedgerCheckWidth + WebInsets.md,
                0,
                WebInsets.md,
                WebInsets.sm,
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded, size: 14, color: cs.error),
                  const SizedBox(width: WebInsets.xs),
                  Text(
                    error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.error,
                      fontSize: 12,
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

class _LedgerRowV2 extends StatefulWidget {
  final _Row row;
  final double descWidth;
  final LedgerColWidths widths;
  final bool selected;
  final List<FinancialAccount> accounts;
  final List<FinanceCategory> categories;
  final FinancialAccount? Function(String?) accountOf;
  final Color Function(FinanceCategory?) colorFor;
  final bool Function(TransactionRecord) canSplit;
  final VoidCallback onToggleSelect;
  final void Function(TransactionRecord, DateTime) onDate;
  final void Function(TransactionRecord, String) onAccount;
  final void Function(TransactionRecord, String) onCategory;
  final void Function(TransactionRecord, String) onDescription;
  final void Function(TransactionRecord, double, TransactionType) onAmount;
  final void Function(TransactionRecord) onDelete;
  final void Function(TransactionRecord) onEdit;
  final void Function(TransactionRecord) onDuplicate;
  final void Function(TransactionRecord) onSplit;
  final void Function(TransactionRecord) onReimbursable;

  const _LedgerRowV2({
    super.key,
    required this.row,
    required this.descWidth,
    required this.widths,
    required this.selected,
    required this.accounts,
    required this.categories,
    required this.accountOf,
    required this.colorFor,
    required this.canSplit,
    required this.onToggleSelect,
    required this.onDate,
    required this.onAccount,
    required this.onCategory,
    required this.onDescription,
    required this.onAmount,
    required this.onDelete,
    required this.onEdit,
    required this.onDuplicate,
    required this.onSplit,
    required this.onReimbursable,
  });

  @override
  State<_LedgerRowV2> createState() => _LedgerRowV2State();
}

class _LedgerRowV2State extends State<_LedgerRowV2> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final t = widget.row.txn;
    final isTransfer = t.transferGroupId != null;
    final w = widget.widths;
    final acctIndex = widget.accounts.indexWhere((a) => a.id == t.accountId);
    final acct = widget.accountOf(t.accountId);
    final note = t.note?.trim() ?? '';

    Color? bg;
    if (widget.selected) {
      bg = cs.primary.withValues(alpha: 0.10);
    } else if (_hover) {
      bg = cs.onSurface.withValues(alpha: 0.06);
    }

    final showSplit = !isTransfer &&
        t.type == TransactionType.outflow &&
        acct?.isLiability == true &&
        widget.canSplit(t);
    final showReimbursable =
        !isTransfer && t.type == TransactionType.outflow && !t.isInstallment;

    Widget body = Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: kLedgerCheckWidth,
            child: Center(
              child: LedgerCheck(
                  on: widget.selected, onTap: widget.onToggleSelect),
            ),
          ),
          LedgerDateCell(
            width: w.date,
            date: t.date,
            enabled: !isTransfer,
            onChanged: (d) => widget.onDate(t, d),
          ),
          isTransfer
              ? LedgerTransferAccountCell(
                  width: w.account,
                  txn: t,
                  accounts: widget.accounts,
                  leading: _AccountTile(account: acct, index: acctIndex),
                )
              : SizedBox(
                  width: w.account,
                  child: Row(
                    children: [
                      const SizedBox(width: WebInsets.md),
                      _AccountTile(account: acct, index: acctIndex),
                      const SizedBox(width: WebInsets.xs),
                      LedgerAccountCell(
                        width: w.account - WebInsets.md - 18 - WebInsets.xs,
                        value: t.accountId,
                        accounts: widget.accounts,
                        showDots: false,
                        onChanged: (id) => widget.onAccount(t, id),
                      ),
                    ],
                  ),
                ),
          // Description, with the note as a muted subline. Notes were stored
          // but never shown in the grid before v2.
          SizedBox(
            width: widget.descWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                LedgerInlineText(
                  key: ValueKey('desc_${t.id}'),
                  width: widget.descWidth,
                  initialValue: t.description,
                  hintText: '—',
                  bold: true,
                  enabled: !isTransfer,
                  onCommit: (v) => widget.onDescription(t, v),
                ),
                if (note.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      isTransfer ? WebInsets.md : 18,
                      0,
                      WebInsets.md,
                      6,
                    ),
                    child: Text(
                      note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.appColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          isTransfer
              ? ledgerReadCell(
                  width: w.category,
                  child: const WebBadge(
                    'Transfer',
                    tone: WebBadgeTone.info,
                    icon: Icons.swap_horiz_rounded,
                  ),
                )
              : LedgerCategoryCell(
                  width: w.category,
                  value: t.categoryId,
                  categories: widget.categories,
                  colorFor: widget.colorFor,
                  onChanged: (id) => widget.onCategory(t, id),
                ),
          LedgerAmountCell(
            key: ValueKey('in_${t.id}'),
            width: w.inflow,
            value: t.type == TransactionType.inflow ? t.amount : 0,
            color: cs.tertiary,
            enabled: !isTransfer,
            onCommit: (v) => widget.onAmount(t, v, TransactionType.inflow),
          ),
          LedgerAmountCell(
            key: ValueKey('out_${t.id}'),
            width: w.outflow,
            value: t.type == TransactionType.outflow ? t.amount : 0,
            color: cs.onSurface,
            enabled: !isTransfer,
            onCommit: (v) => widget.onAmount(t, v, TransactionType.outflow),
          ),
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
          SizedBox(
            width: kLedgerTrailingWidth,
            child: Center(
              child: WebRowMenu(
                key: WebKeys.ledgerRowMenu,
                tooltip: 'Row actions',
                items: [
                  WebMenuItem(
                    isTransfer ? 'Edit transfer' : 'Edit in dialog',
                    key: WebKeys.ledgerRowEdit,
                    icon: Icons.edit_outlined,
                    onTap: () => widget.onEdit(t),
                  ),
                  WebMenuItem(
                    'Duplicate',
                    key: WebKeys.ledgerRowDuplicate,
                    icon: Icons.content_copy_outlined,
                    onTap: () => widget.onDuplicate(t),
                  ),
                  if (showSplit)
                    WebMenuItem(
                      t.isInstallment
                          ? 'Edit installment plan'
                          : 'Split into installments',
                      key: WebKeys.ledgerRowSplitInstallments,
                      icon: Icons.calendar_view_month_outlined,
                      onTap: () => widget.onSplit(t),
                    ),
                  if (showReimbursable)
                    WebMenuItem(
                      t.reimbursable
                          ? 'Edit "I\'ll get this back"'
                          : 'Mark "I\'ll get this back"',
                      key: WebKeys.ledgerRowReimbursable,
                      icon: Icons.keyboard_return_rounded,
                      onTap: () => widget.onReimbursable(t),
                    ),
                  WebMenuItem(
                    'Delete · undo for 6 s',
                    key: WebKeys.ledgerRowDelete,
                    icon: Icons.delete_outline_rounded,
                    destructive: true,
                    onTap: () => widget.onDelete(t),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (isTransfer) {
      // A transfer's two legs must change together, so its cells are read-only
      // and clicking the row opens the pair-aware edit dialog instead.
      body = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onEdit(t),
        child: Tooltip(message: 'Edit transfer', child: body),
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

class _EmptyHintV2 extends StatelessWidget {
  final bool hasAccounts;
  final bool narrowed;
  final VoidCallback onClearFilters;
  final VoidCallback? onOpenSetup;

  const _EmptyHintV2({
    required this.hasAccounts,
    required this.narrowed,
    required this.onClearFilters,
    required this.onOpenSetup,
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
        padding: const EdgeInsets.symmetric(vertical: WebInsets.xxl),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('No transactions match your filters.', style: style),
            const SizedBox(height: WebInsets.sm),
            TextButton.icon(
              key: WebKeys.ledgerEmptyClearFilters,
              onPressed: onClearFilters,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
              label: const Text('Clear filters'),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: WebInsets.xxl),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            hasAccounts
                ? 'No transactions this month — add one in the row above.'
                : 'Add an account in Setup before logging transactions.',
            style: style,
          ),
          if (!hasAccounts && onOpenSetup != null) ...[
            const SizedBox(height: WebInsets.sm),
            TextButton.icon(
              key: LedgerKeysV2.emptyOpenSetup,
              onPressed: onOpenSetup,
              icon: const Icon(Icons.tune_rounded, size: 16),
              label: const Text('Open Setup'),
            ),
          ],
        ],
      ),
    );
  }
}

/// The card footer: the editing hint on the left, the month's In / Out / Net
/// on the right (the presenter's `tableInflow` / `tableOutflow`).
class _FooterTotals extends StatelessWidget {
  final String month;
  final double inflow;
  final double outflow;
  const _FooterTotals({
    required this.month,
    required this.inflow,
    required this.outflow,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final net = inflow - outflow;
    return Container(
      key: WebKeys.ledgerFooterTotals,
      padding: const EdgeInsets.symmetric(
        horizontal: WebInsets.lg,
        vertical: WebInsets.md,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$month totals · click a cell to edit · drag a column edge to '
              'resize · balances recalculate',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: WebInsets.lg),
          _Total(label: 'In', value: formatPeso(inflow), color: cs.tertiary),
          const SizedBox(width: WebInsets.lg),
          _Total(label: 'Out', value: formatPeso(outflow), color: cs.onSurface),
          const SizedBox(width: WebInsets.lg),
          _Total(
            label: 'Net',
            value: formatPesoSigned(net),
            color: net < 0 ? cs.error : cs.tertiary,
          ),
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Total({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const SizedBox(width: WebInsets.xs),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

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
