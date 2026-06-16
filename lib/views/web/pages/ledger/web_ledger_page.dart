import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/finance_parse_result.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/app_radii.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../../widgets/web_widgets.dart';

/// Hoisted so the per-row date cells don't allocate a new [DateFormat] on
/// every build. (Plan 052 P10)
final DateFormat _kMonthDayFmt = DateFormat('MMM d');

/// Web Ledger page (Plan 051). A Google-Sheets-style, inline-editable
/// transaction grid matching the Claude Design reference
/// (`docs/design/treasury-web-reference/ledger.jsx`): click any cell to edit,
/// type in the bottom row to add, sortable headers, bulk select + delete,
/// running + per-account balance columns, a Filters & Sort popover with active
/// chips, and a natural-language Quick Add card. Theme-aware throughout — the
/// reference is the visual target, the palette is ours.
class WebLedgerPage extends StatefulWidget {
  final LedgerPresenter presenter;
  const WebLedgerPage({super.key, required this.presenter});

  @override
  State<WebLedgerPage> createState() => _WebLedgerPageState();
}

/// One enriched, display-ready ledger row.
typedef _Row = ({
  TransactionRecord txn,
  double runningBalance,
  double accountBalance,
});

enum _LedgerType { all, inflow, outflow }

enum _SortKey { date, account, description, category, inflow, outflow, amount }

/// Preset sort options shown in the Filters & Sort popover.
class _SortOption {
  final String label;
  final _SortKey key;
  final int dir; // 1 asc, -1 desc
  const _SortOption(this.label, this.key, this.dir);
}

const _kSortOptions = <_SortOption>[
  _SortOption('Newest first', _SortKey.date, -1),
  _SortOption('Oldest first', _SortKey.date, 1),
  _SortOption('Highest outflow', _SortKey.outflow, -1),
  _SortOption('Highest inflow', _SortKey.inflow, -1),
  _SortOption('Largest amount', _SortKey.amount, -1),
];

// Fixed column widths (px) — total drives the horizontal scroll min-width.
const double _wCheck = 44;
const double _wDate = 118;
const double _wAccount = 152;
const double _wDesc = 224;
const double _wCategory = 170;
const double _wInflow = 122;
const double _wOutflow = 122;
const double _wRunning = 132;
const double _wAcctBal = 142;
const double _wNotes = 176;
const double _wDelete = 48;
const double _kGridWidth = _wCheck +
    _wDate +
    _wAccount +
    _wDesc +
    _wCategory +
    _wInflow +
    _wOutflow +
    _wRunning +
    _wAcctBal +
    _wNotes +
    _wDelete;

/// Shared height for every toolbar control (Filters & Sort, search, Add
/// Transaction, active chips) so they line up at exactly the same height.
const double _kControlHeight = 40;

class _WebLedgerPageState extends State<WebLedgerPage> {
  final _searchController = TextEditingController();
  final _gridHScroll = ScrollController(); // horizontal grid scroll (U8)
  String _query = '';

  // Filters & sort (all transient, View-side — never mutate presenter state).
  String? _fAccountId; // null = all
  String? _fCategoryId; // null = all
  _LedgerType _fType = _LedgerType.all;
  DateTime? _fromDate;
  DateTime? _toDate;
  _SortKey? _sortKey; // null = presenter default (newest first)
  int _sortDir = -1;

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
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _gridHScroll.dispose();
    super.dispose();
  }

  Timer? _searchDebounce;

  void _onSearchChanged() {
    // Debounce so each keystroke doesn't re-filter the whole grid immediately;
    // the filter only re-runs once typing pauses (~220ms). (Plan 052 B2/P2)
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 220), () {
      final next = _searchController.text.trim().toLowerCase();
      if (next == _query || !mounted) return;
      setState(() => _query = next);
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
    return resolveSliceColor(cat.colorHex, idx < 0 ? 0 : idx,
        brightness: Theme.of(context).brightness);
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
    if (_fAccountId != null && t.accountId != _fAccountId) return false;
    if (_fCategoryId != null && t.categoryId != _fCategoryId) return false;
    switch (_fType) {
      case _LedgerType.inflow:
        if (t.type != TransactionType.inflow) return false;
      case _LedgerType.outflow:
        if (t.type != TransactionType.outflow) return false;
      case _LedgerType.all:
        break;
    }
    if (_fromDate != null && t.date.isBefore(_dayStart(_fromDate!))) {
      return false;
    }
    if (_toDate != null && t.date.isAfter(_dayEnd(_toDate!))) return false;
    if (_query.isNotEmpty) {
      final cat = _categoryOf(t.categoryId)?.name.toLowerCase() ?? '';
      final acct = _accountName(t.accountId).toLowerCase();
      final hay = '${t.description.toLowerCase()} '
          '${(t.note ?? '').toLowerCase()} $cat $acct';
      if (!hay.contains(_query)) return false;
    }
    return true;
  }

  List<_Row> _sorted(List<_Row> rows) {
    final key = _sortKey;
    if (key == null) return rows; // presenter order (newest first)
    Comparable keyOf(_Row r) {
      final t = r.txn;
      switch (key) {
        case _SortKey.date:
          return t.date.millisecondsSinceEpoch;
        case _SortKey.account:
          return _accountName(t.accountId).toLowerCase();
        case _SortKey.description:
          return t.description.toLowerCase();
        case _SortKey.category:
          return (_categoryOf(t.categoryId)?.name ?? '').toLowerCase();
        case _SortKey.inflow:
          return t.type == TransactionType.inflow ? t.amount : 0.0;
        case _SortKey.outflow:
          return t.type == TransactionType.outflow ? t.amount : 0.0;
        case _SortKey.amount:
          return t.amount;
      }
    }

    final out = [...rows]
      ..sort((a, b) => Comparable.compare(keyOf(a), keyOf(b)) * _sortDir);
    return out;
  }

  void _toggleHeaderSort(_SortKey key) {
    setState(() {
      if (_sortKey == key) {
        _sortDir = -_sortDir;
      } else {
        _sortKey = key;
        _sortDir = 1;
      }
    });
  }

  int get _activeFilterCount => [
        _fAccountId != null,
        _fCategoryId != null,
        _fType != _LedgerType.all,
        _fromDate != null || _toDate != null,
        _sortKey != null,
      ].where((b) => b).length;

  void _clearFilters() => setState(() {
        _fAccountId = null;
        _fCategoryId = null;
        _fType = _LedgerType.all;
        _fromDate = null;
        _toDate = null;
        _sortKey = null;
        _sortDir = -1;
      });

  // ── Mutations ────────────────────────────────────────────────────────────────

  void _editDate(TransactionRecord t, DateTime d) =>
      _p.updateTransaction(t.copyWith(date: d, month: toMonthKey(d)));

  void _editAccount(TransactionRecord t, String id) =>
      _p.updateTransaction(t.copyWith(accountId: id));

  void _editCategory(TransactionRecord t, String id) =>
      _p.updateTransaction(t.copyWith(categoryId: id));

  void _editDescription(TransactionRecord t, String v) {
    if (v.trim() == t.description) return;
    _p.updateTransaction(t.copyWith(description: v.trim()));
  }

  void _editNote(TransactionRecord t, String v) {
    final next = v.trim();
    if (next == (t.note ?? '')) return;
    _p.updateTransaction(t.copyWith(note: next));
  }

  /// Editing the inflow/outflow cells: a row's two amount columns are views of
  /// the single `amount`+`type`. Writing a positive value flips the row to that
  /// direction. Zero/empty is ignored (revert).
  void _editAmount(TransactionRecord t, double value, TransactionType dir) {
    if (value <= 0) return;
    if (t.type == dir && t.amount == value) return;
    _p.updateTransaction(t.copyWith(type: dir, amount: value));
  }

  Future<void> _deleteRow(TransactionRecord t) async {
    final ok = await _confirmDelete(1);
    if (!ok || !mounted) return;
    setState(() => _selected.remove(t.id));
    _p.deleteTransactionOrGroup(t.id);
  }

  Future<void> _deleteSelected() async {
    final ids = _selected.toSet();
    if (ids.isEmpty) return;
    final ok = await _confirmDelete(ids.length);
    if (!ok || !mounted) return;
    setState(_selected.clear);
    // One batched mutation + persist instead of N fire-and-forget writes. (C8)
    _p.deleteTransactions(ids);
  }

  /// Confirms a destructive delete of [count] transaction(s). (Plan 052 U2)
  Future<bool> _confirmDelete(int count) async {
    final noun = count == 1 ? 'this transaction' : '$count transactions';
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete transactions?'),
        content:
            Text('Permanently delete $noun? This also reverses the affected '
                'account balances and cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
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
    if (amount <= 0 && _draftDesc.trim().isEmpty) return; // nothing to add
    if (amount <= 0) return; // need a value
    final type =
        _draftInflow > 0 ? TransactionType.inflow : TransactionType.outflow;
    final accountId = _draftAccountId ?? _liquidAccounts.firstOrNull?.id;
    if (accountId == null) return; // no accounts to post to
    final cats = _categoriesFor(type);
    final categoryId =
        _draftCategoryId != null && cats.any((c) => c.id == _draftCategoryId)
            ? _draftCategoryId!
            : (cats.firstOrNull?.id ?? '');
    final desc = _draftDesc.trim().isEmpty
        ? (_categoryOf(categoryId)?.name ?? 'Transaction')
        : _draftDesc.trim();
    final id =
        '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';
    _p.addTransaction(TransactionRecord(
      id: id,
      date: _draftDate,
      accountId: accountId,
      categoryId: categoryId,
      amount: amount,
      type: type,
      description: desc,
      note: _draftNote.trim().isEmpty ? null : _draftNote.trim(),
      month: toMonthKey(_draftDate),
    ));
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

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _p,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(WebInsets.xxl),
          child: _p.isLoading ? const _LoadingBlock() : _buildBody(context),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    final all = _p.ledgerSpreadsheetRows;
    final rows = _sorted(all.where(_matches).toList());

    final totIn = rows
        .where((r) => r.txn.type == TransactionType.inflow)
        .fold(0.0, (s, r) => s + r.txn.amount);
    final totOut = rows
        .where((r) => r.txn.type == TransactionType.outflow)
        .fold(0.0, (s, r) => s + r.txn.amount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryRow(inflow: totIn, outflow: totOut, net: totIn - totOut),
        const SizedBox(height: WebInsets.xl),
        _QuickAdd(presenter: _p, onNeedsForm: _openAddDialog),
        const SizedBox(height: WebInsets.xl),
        _Toolbar(
          monthLabel: monthLabel(_p.selectedMonth),
          onPrevMonth: () => _p.setMonth(previousMonth(_p.selectedMonth)),
          onNextMonth: () => _p.setMonth(nextMonth(_p.selectedMonth)),
          searchController: _searchController,
          accounts: _liquidAccounts,
          categories: _p.categories,
          accountId: _fAccountId,
          categoryId: _fCategoryId,
          type: _fType,
          fromDate: _fromDate,
          toDate: _toDate,
          sortKey: _sortKey,
          sortDir: _sortDir,
          activeCount: _activeFilterCount,
          accountName: _accountName,
          categoryName: (id) => _categoryOf(id)?.name ?? '—',
          onAccount: (v) => setState(() => _fAccountId = v),
          onCategory: (v) => setState(() => _fCategoryId = v),
          onType: (v) => setState(() => _fType = v),
          onFromDate: (v) => setState(() => _fromDate = v),
          onToDate: (v) => setState(() => _toDate = v),
          onSort: (opt) => setState(() {
            if (opt == null) {
              _sortKey = null;
              _sortDir = -1;
            } else {
              _sortKey = opt.key;
              _sortDir = opt.dir;
            }
          }),
          onClear: _clearFilters,
          onAdd: () => _openAddDialog(),
        ),
        const SizedBox(height: WebInsets.xl),
        _buildTableCard(context, rows),
      ],
    );
  }

  Widget _buildTableCard(BuildContext context, List<_Row> rows) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return WebCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Selection bar — shown only while rows are selected. The month label
          // now lives in the toolbar and the totals are already in the summary
          // cards, so there's no resting band header above the grid.
          if (_selected.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: WebInsets.lg, vertical: WebInsets.md),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              ),
              child: _SelectionBar(
                count: _selected.length,
                onClear: () => setState(_selected.clear),
                onDelete: _deleteSelected,
              ),
            ),
          // Grid: fills the container by stretching the Description column;
          // falls back to horizontal scroll when narrower than the minimum.
          LayoutBuilder(
            builder: (context, constraints) {
              final avail = constraints.maxWidth;
              final descW = _wDesc + max(0.0, avail - _kGridWidth);
              final gridW = _wCheck +
                  _wDate +
                  _wAccount +
                  descW +
                  _wCategory +
                  _wInflow +
                  _wOutflow +
                  _wRunning +
                  _wAcctBal +
                  _wNotes +
                  _wDelete;
              return Scrollbar(
                controller: _gridHScroll,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _gridHScroll,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: gridW,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _GridHeader(
                          descWidth: descW,
                          sortKey: _sortKey,
                          sortDir: _sortDir,
                          allSelected: rows.isNotEmpty &&
                              rows.every((r) => _selected.contains(r.txn.id)),
                          onToggleAll: () => setState(() {
                            final allSel = rows.isNotEmpty &&
                                rows.every((r) => _selected.contains(r.txn.id));
                            if (allSel) {
                              _selected.clear();
                            } else {
                              _selected.addAll(rows.map((r) => r.txn.id));
                            }
                          }),
                          onSort: _toggleHeaderSort,
                        ),
                        // Draft add-row — placed at the TOP, where newly-added
                        // transactions appear (the list is newest-first).
                        _DraftRow(
                          epoch: _draftEpoch,
                          descWidth: descW,
                          date: _draftDate,
                          accountId: _draftAccountId,
                          categoryId: _draftCategoryId,
                          inflow: _draftInflow,
                          outflow: _draftOutflow,
                          accounts: _liquidAccounts,
                          categories: _categoriesFor(_draftInflow > 0
                              ? TransactionType.inflow
                              : TransactionType.outflow),
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
                        if (rows.isEmpty)
                          _EmptyGridHint(
                              hasAccounts: _liquidAccounts.isNotEmpty),
                        for (var i = 0; i < rows.length; i++)
                          _EditableRow(
                            key: ValueKey(rows[i].txn.id),
                            row: rows[i],
                            descWidth: descW,
                            selected: _selected.contains(rows[i].txn.id),
                            accounts: _liquidAccounts,
                            categories: _categoriesFor(rows[i].txn.type),
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
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          // Footer hint.
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: WebInsets.lg, vertical: WebInsets.sm),
            decoration: BoxDecoration(
              border: Border(
                top:
                    BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
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
                    'add · running balance recalculates automatically.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
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
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final TextEditingController searchController;
  final List<FinancialAccount> accounts;
  final List<FinanceCategory> categories;
  final String? accountId;
  final String? categoryId;
  final _LedgerType type;
  final DateTime? fromDate;
  final DateTime? toDate;
  final _SortKey? sortKey;
  final int sortDir;
  final int activeCount;
  final String Function(String?) accountName;
  final String Function(String?) categoryName;
  final ValueChanged<String?> onAccount;
  final ValueChanged<String?> onCategory;
  final ValueChanged<_LedgerType> onType;
  final ValueChanged<DateTime?> onFromDate;
  final ValueChanged<DateTime?> onToDate;
  final ValueChanged<_SortOption?> onSort;
  final VoidCallback onClear;
  final VoidCallback onAdd;

  const _Toolbar({
    required this.monthLabel,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.searchController,
    required this.accounts,
    required this.categories,
    required this.accountId,
    required this.categoryId,
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

  _SortOption? get _activeSortOption {
    for (final o in _kSortOptions) {
      if (o.key == sortKey && o.dir == sortDir) return o;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final df = _kMonthDayFmt;
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
      if (accountId != null)
        _ActiveChip(
            label: accountName(accountId), onClear: () => onAccount(null)),
      if (categoryId != null)
        _ActiveChip(
            label: categoryName(categoryId), onClear: () => onCategory(null)),
      if (type != _LedgerType.all)
        _ActiveChip(
          label: type == _LedgerType.inflow ? 'Inflow only' : 'Outflow only',
          onClear: () => onType(_LedgerType.all),
        ),
      if (dateLabel != null)
        _ActiveChip(
          label: dateLabel,
          icon: Icons.history,
          onClear: () {
            onFromDate(null);
            onToDate(null);
          },
        ),
      if (sortLabel != null)
        _ActiveChip(
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
        // Month stepper — page back/forward through months.
        IconButton(
          onPressed: onPrevMonth,
          icon: const Icon(Icons.chevron_left_rounded),
          tooltip: 'Previous month',
          visualDensity: VisualDensity.compact,
        ),
        Text(
          monthLabel,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        IconButton(
          onPressed: onNextMonth,
          icon: const Icon(Icons.chevron_right_rounded),
          tooltip: 'Next month',
          visualDensity: VisualDensity.compact,
        ),
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
        _FiltersAndSort(
          accounts: accounts,
          categories: categories,
          accountId: accountId,
          categoryId: categoryId,
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

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  const _SearchField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: _kControlHeight,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search…',
          prefixIcon: const Icon(Icons.search_rounded, size: 18),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
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
      height: _kControlHeight,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('Add Transaction'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: WebInsets.lg),
          minimumSize: const Size(0, _kControlHeight),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.sm)),
        ),
      ),
    );
  }
}

/// The "Filters & Sort" trigger button + popover panel, anchored with an
/// [OverlayPortal] so interacting with the inner controls never closes it.
class _FiltersAndSort extends StatefulWidget {
  final List<FinancialAccount> accounts;
  final List<FinanceCategory> categories;
  final String? accountId;
  final String? categoryId;
  final _LedgerType type;
  final DateTime? fromDate;
  final DateTime? toDate;
  final _SortKey? sortKey;
  final int sortDir;
  final int activeCount;
  final ValueChanged<String?> onAccount;
  final ValueChanged<String?> onCategory;
  final ValueChanged<_LedgerType> onType;
  final ValueChanged<DateTime?> onFromDate;
  final ValueChanged<DateTime?> onToDate;
  final ValueChanged<_SortOption?> onSort;
  final VoidCallback onClear;

  const _FiltersAndSort({
    required this.accounts,
    required this.categories,
    required this.accountId,
    required this.categoryId,
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
  });

  @override
  State<_FiltersAndSort> createState() => _FiltersAndSortState();
}

class _FiltersAndSortState extends State<_FiltersAndSort> {
  final _controller = OverlayPortalController();
  final _link = LayerLink();

  _SortOption? get _activeSortOption {
    for (final o in _kSortOptions) {
      if (o.key == widget.sortKey && o.dir == widget.sortDir) return o;
    }
    return null;
  }

  Future<void> _pickDate(BuildContext context, bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? widget.fromDate : widget.toDate) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
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
          height: _kControlHeight,
          child: OutlinedButton.icon(
            onPressed: _controller.toggle,
            icon: const Icon(Icons.tune_rounded, size: 16),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Filters & Sort'),
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
                    child: Text('${widget.activeCount}',
                        style: TextStyle(
                            color: cs.onPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
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
              minimumSize: const Size(0, _kControlHeight),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.sm)),
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
        // Outside-tap barrier.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
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
                      color: cs.outlineVariant.withValues(alpha: 0.6)),
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
                    _FilterRow(
                      label: 'Account',
                      child: _PanelDropdown<String?>(
                        value: widget.accountId,
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('All accounts')),
                          ...widget.accounts.map((a) => DropdownMenuItem(
                              value: a.id,
                              child: Text(a.name,
                                  overflow: TextOverflow.ellipsis))),
                        ],
                        onChanged: widget.onAccount,
                      ),
                    ),
                    const SizedBox(height: WebInsets.md),
                    _FilterRow(
                      label: 'Category',
                      child: _PanelDropdown<String?>(
                        value: widget.categoryId,
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('All categories')),
                          ...widget.categories.map((c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(c.name,
                                  overflow: TextOverflow.ellipsis))),
                        ],
                        onChanged: widget.onCategory,
                      ),
                    ),
                    const SizedBox(height: WebInsets.md),
                    _FilterRow(
                      label: 'Type',
                      child: _TypeSegmented(
                          value: widget.type, onChanged: widget.onType),
                    ),
                    const SizedBox(height: WebInsets.md),
                    _FilterRow(
                      label: 'Sort by',
                      child: _PanelDropdown<int>(
                        value: _activeSortOption == null
                            ? -1
                            : _kSortOptions.indexOf(_activeSortOption!),
                        items: [
                          const DropdownMenuItem(
                              value: -1, child: Text('Default (date order)')),
                          for (var i = 0; i < _kSortOptions.length; i++)
                            DropdownMenuItem(
                                value: i, child: Text(_kSortOptions[i].label)),
                        ],
                        onChanged: (i) => widget.onSort(
                            i == null || i < 0 ? null : _kSortOptions[i]),
                      ),
                    ),
                    const SizedBox(height: WebInsets.md),
                    _FilterRow(
                      label: 'Date range',
                      child: Row(
                        children: [
                          Expanded(
                            child: _DateButton(
                              label: widget.fromDate == null
                                  ? 'From'
                                  : _kMonthDayFmt.format(widget.fromDate!),
                              onTap: () => _pickDate(context, true),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: WebInsets.sm),
                            child: Text('→',
                                style: TextStyle(color: cs.onSurfaceVariant)),
                          ),
                          Expanded(
                            child: _DateButton(
                              label: widget.toDate == null
                                  ? 'Until'
                                  : _kMonthDayFmt.format(widget.toDate!),
                              onTap: () => _pickDate(context, false),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: WebInsets.lg),
                    Divider(
                        height: 1,
                        color: cs.outlineVariant.withValues(alpha: 0.5)),
                    const SizedBox(height: WebInsets.md),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                            onPressed: widget.onClear,
                            child: const Text('Clear all')),
                        FilledButton(
                          onPressed: _controller.hide,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: WebInsets.lg),
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
        Text(label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                )),
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
  const _PanelDropdown(
      {required this.value, required this.items, required this.onChanged});

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
  final _LedgerType value;
  final ValueChanged<_LedgerType> onChanged;
  const _TypeSegmented({required this.value, required this.onChanged});

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
          _seg(context, _LedgerType.all, 'All'),
          _seg(context, _LedgerType.inflow, 'Inflow'),
          _seg(context, _LedgerType.outflow, 'Outflow'),
        ],
      ),
    );
  }

  Widget _seg(BuildContext context, _LedgerType v, String label) {
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
            child: Text(label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: sel ? cs.onPrimary : cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    )),
          ),
        ),
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DateButton({required this.label, required this.onTap});

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
            Icon(Icons.calendar_today_outlined,
                size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: WebInsets.sm),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onClear;
  const _ActiveChip({required this.label, this.icon, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: _kControlHeight,
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
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(width: WebInsets.xs),
          InkWell(
            onTap: onClear,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close_rounded,
                  size: 14, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Summary tiles
// ═══════════════════════════════════════════════════════════════════════════════

class _SummaryRow extends StatelessWidget {
  final double inflow;
  final double outflow;
  final double net;
  const _SummaryRow(
      {required this.inflow, required this.outflow, required this.net});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final netPositive = net >= 0;
    return Row(
      children: [
        Expanded(
          child: _SumTile(
            label: 'Inflow',
            value: '+${formatPeso(inflow)}',
            icon: Icons.south_west_rounded,
            fg: cs.tertiary,
            bg: cs.tertiary.withValues(alpha: 0.14),
          ),
        ),
        const SizedBox(width: WebInsets.md),
        Expanded(
          child: _SumTile(
            label: 'Outflow',
            value: '−${formatPeso(outflow)}',
            icon: Icons.north_east_rounded,
            fg: cs.onSurface,
            bg: cs.surfaceContainerHighest,
          ),
        ),
        const SizedBox(width: WebInsets.md),
        Expanded(
          child: _SumTile(
            label: 'Net Cash',
            value: '${netPositive ? '+' : '−'}${formatPeso(net.abs())}',
            icon: Icons.swap_vert_rounded,
            fg: netPositive ? cs.tertiary : cs.error,
            bg: (netPositive ? cs.tertiary : cs.error).withValues(alpha: 0.14),
          ),
        ),
      ],
    );
  }
}

class _SumTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color fg;
  final Color bg;
  const _SumTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.fg,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return WebCard(
      padding: const EdgeInsets.all(WebInsets.lg),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Icon(icon, size: 20, color: fg),
          ),
          const SizedBox(width: WebInsets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.7,
                    )),
                const SizedBox(height: 2),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// QuickAdd — single-shot natural-language entry (no chat history)
// ═══════════════════════════════════════════════════════════════════════════════

class _QuickAdd extends StatefulWidget {
  final LedgerPresenter presenter;
  final void Function(ParsedTransaction? prefill) onNeedsForm;
  const _QuickAdd({required this.presenter, required this.onNeedsForm});

  @override
  State<_QuickAdd> createState() => _QuickAddState();
}

class _QuickAddState extends State<_QuickAdd> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);

    final p = widget.presenter;
    await p.sendChatInput(text);
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    if (p.lastCommittedSummary != null) {
      final summary = p.lastCommittedSummary!;
      p.clearLastCommittedSummary();
      _controller.clear();
      _toast(messenger, summary, ok: true);
    } else if (p.chatHardError != null) {
      final msg = p.chatHardError!.userMessage;
      p.clearChatHardError();
      _toast(messenger, msg, ok: false);
    } else {
      // Rule-based parser couldn't fully resolve (no on-device AI on web) —
      // hand off to the form prefilled with whatever we did parse.
      final prefill = p.pendingFormPrefill;
      p.consumeFormPrefill();
      _controller.clear();
      widget.onNeedsForm(prefill);
    }
    if (mounted) setState(() => _busy = false);
  }

  void _toast(ScaffoldMessengerState messenger, String message,
      {required bool ok}) {
    final cs = Theme.of(context).colorScheme;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        width: 420,
        backgroundColor: ok ? cs.tertiaryContainer : cs.errorContainer,
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                size: 18,
                color: ok ? cs.onTertiaryContainer : cs.onErrorContainer),
            const SizedBox(width: WebInsets.sm),
            Flexible(
              child: Text(message,
                  style: TextStyle(
                      color:
                          ok ? cs.onTertiaryContainer : cs.onErrorContainer)),
            ),
          ],
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return WebCard(
      padding: const EdgeInsets.all(WebInsets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 15, color: cs.secondary),
              const SizedBox(width: WebInsets.sm),
              Text('Quick Add',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(width: WebInsets.sm),
              Flexible(
                child: Text('· type a transaction in plain words',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
              ),
            ],
          ),
          const SizedBox(height: WebInsets.md),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: TextField(
                    controller: _controller,
                    enabled: !_busy,
                    onSubmitted: (_) => _send(),
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      hintText: 'e.g. “Grab 180 from gcash” or “Salary 46500”',
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 0, horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: WebInsets.sm),
              SizedBox(
                height: 44,
                child: FilledButton(
                  onPressed: _busy ? null : _send,
                  style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: WebInsets.xl),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.sm)),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Add'),
                ),
              ),
            ],
          ),
          // Loading indicator while the entry is being parsed + saved.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: _busy
                ? Padding(
                    padding: const EdgeInsets.only(top: WebInsets.md),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: const LinearProgressIndicator(minHeight: 3),
                    ),
                  )
                : const SizedBox(height: 0, width: double.infinity),
          ),
        ],
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
  const _SelectionBar(
      {required this.count, required this.onClear, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text('$count selected',
              style: theme.textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
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
  final _SortKey? sortKey;
  final int sortDir;
  final bool allSelected;
  final VoidCallback onToggleAll;
  final ValueChanged<_SortKey> onSort;
  const _GridHeader({
    required this.descWidth,
    required this.sortKey,
    required this.sortDir,
    required this.allSelected,
    required this.onToggleAll,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.8)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _wCheck,
            child: Center(child: _Check(on: allSelected, onTap: onToggleAll)),
          ),
          _hCell('Date', _wDate, _SortKey.date),
          _hCell('Account', _wAccount, _SortKey.account),
          _hCell('Description', descWidth, _SortKey.description),
          _hCell('Category', _wCategory, _SortKey.category),
          _hCell('Inflow', _wInflow, _SortKey.inflow, right: true),
          _hCell('Outflow', _wOutflow, _SortKey.outflow, right: true),
          _hCell('Running', _wRunning, null, right: true),
          _hCell('Acct. Balance', _wAcctBal, null, right: true),
          _hCell('Notes', _wNotes, null),
          const SizedBox(width: _wDelete),
        ],
      ),
    );
  }

  Widget _hCell(String label, double width, _SortKey? key,
      {bool right = false}) {
    return _HeaderCell(
      label: label,
      width: width,
      sortKey: key,
      active: key != null && key == sortKey,
      dir: sortDir,
      right: right,
      onSort: key == null ? null : () => onSort(key),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String label;
  final double width;
  final _SortKey? sortKey;
  final bool active;
  final int dir;
  final bool right;
  final VoidCallback? onSort;
  const _HeaderCell({
    required this.label,
    required this.width,
    required this.sortKey,
    required this.active,
    required this.dir,
    required this.right,
    required this.onSort,
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
              angle: active && dir < 0 ? 3.14159 : 0, child: chevron),
        Flexible(
            child: Text(label.toUpperCase(),
                style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (!right && onSort != null)
          Transform.rotate(
              angle: active && dir < 0 ? 3.14159 : 0, child: chevron),
      ],
    );
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onSort,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: WebInsets.md, vertical: WebInsets.md),
          child: Align(
            alignment: right ? Alignment.centerRight : Alignment.centerLeft,
            child: content,
          ),
        ),
      ),
    );
  }
}

class _Check extends StatelessWidget {
  final bool on;
  final VoidCallback onTap;
  const _Check({required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: on ? cs.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: on ? cs.primary : cs.outline, width: 1.5),
        ),
        child: on
            ? Icon(Icons.check_rounded, size: 11, color: cs.onPrimary)
            : null,
      ),
    );
  }
}

class _EmptyGridHint extends StatelessWidget {
  final bool hasAccounts;
  const _EmptyGridHint({required this.hasAccounts});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: WebInsets.xl),
      alignment: Alignment.center,
      child: Text(
        hasAccounts
            ? 'No transactions yet — add one in the row below.'
            : 'Add an account in Setup before logging transactions.',
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: cs.onSurfaceVariant),
      ),
    );
  }
}

// ── Editable row ────────────────────────────────────────────────────────────────

class _EditableRow extends StatefulWidget {
  final _Row row;
  final double descWidth;
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

  const _EditableRow({
    super.key,
    required this.row,
    required this.descWidth,
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

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          border: Border(
            bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: _wCheck,
              child: Center(
                  child: _Check(
                      on: widget.selected, onTap: widget.onToggleSelect)),
            ),
            // Date
            _DateCell(
              width: _wDate,
              date: t.date,
              enabled: !isTransfer,
              onChanged: (d) => widget.onDate(t, d),
            ),
            // Account
            isTransfer
                ? _readCell(
                    width: _wAccount,
                    child: Text(
                      '${widget.accountName(t.accountId)} → '
                      '${widget.accountName(t.transferToAccountId)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                : _AccountCell(
                    width: _wAccount,
                    value: t.accountId,
                    accounts: widget.accounts,
                    onChanged: (id) => widget.onAccount(t, id),
                  ),
            // Description
            _InlineText(
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
                ? _readCell(
                    width: _wCategory,
                    child: const Align(
                      alignment: Alignment.centerLeft,
                      child: WebBadge('Transfer',
                          tone: WebBadgeTone.info,
                          icon: Icons.swap_horiz_rounded),
                    ),
                  )
                : _CategoryCell(
                    width: _wCategory,
                    value: t.categoryId,
                    categories: widget.categories,
                    colorFor: widget.colorFor,
                    onChanged: (id) => widget.onCategory(t, id),
                  ),
            // Inflow
            _AmountCell(
              key: ValueKey('in_${t.id}'),
              width: _wInflow,
              value: t.type == TransactionType.inflow ? t.amount : 0,
              color: cs.tertiary,
              enabled: !isTransfer,
              onCommit: (v) => widget.onAmount(t, v, TransactionType.inflow),
            ),
            // Outflow
            _AmountCell(
              key: ValueKey('out_${t.id}'),
              width: _wOutflow,
              value: t.type == TransactionType.outflow ? t.amount : 0,
              color: cs.onSurface,
              enabled: !isTransfer,
              onCommit: (v) => widget.onAmount(t, v, TransactionType.outflow),
            ),
            // Running
            _readCell(
              width: _wRunning,
              right: true,
              child: Text(formatPeso(widget.row.runningBalance),
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
            ),
            // Acct. balance
            _readCell(
              width: _wAcctBal,
              right: true,
              child: Text(formatPeso(widget.row.accountBalance),
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
            ),
            // Notes
            _InlineText(
              key: ValueKey('note_${t.id}_${t.note}'),
              width: _wNotes,
              initialValue: t.note ?? '',
              hintText: '—',
              muted: true,
              enabled: !isTransfer,
              onCommit: (v) => widget.onNote(t, v),
            ),
            // Delete
            SizedBox(
              width: _wDelete,
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
      ),
    );
  }
}

Widget _readCell(
        {required double width, required Widget child, bool right = false}) =>
    SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: WebInsets.md, vertical: WebInsets.sm),
        child: Align(
          alignment: right ? Alignment.centerRight : Alignment.centerLeft,
          child: child,
        ),
      ),
    );

// ── Draft add-row ─────────────────────────────────────────────────────────────

class _DraftRow extends StatelessWidget {
  final int epoch;
  final double descWidth;
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
    return Container(
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.04),
      ),
      child: Row(
        children: [
          const SizedBox(width: _wCheck),
          _DateCell(
              width: _wDate, date: date, enabled: true, onChanged: onDate),
          accounts.isEmpty
              ? _readCell(width: _wAccount, child: const Text('—'))
              : _AccountCell(
                  width: _wAccount,
                  // Null until the user picks — shows the "Account" placeholder
                  // so the draft reads as an empty add-row, not a real entry.
                  value: accountId,
                  accounts: accounts,
                  onChanged: onAccount,
                ),
          _InlineText(
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
              ? _readCell(width: _wCategory, child: const Text('—'))
              : _CategoryCell(
                  width: _wCategory,
                  // Null until picked — shows the "Category" placeholder.
                  value: categoryId,
                  categories: categories,
                  colorFor: colorFor,
                  onChanged: onCategory,
                ),
          _AmountCell(
            key: ValueKey('draft_in_$epoch'),
            width: _wInflow,
            value: inflow,
            color: cs.tertiary,
            onCommit: onInflow,
            onChanged: onInflow,
            onSubmit: onCommit,
          ),
          _AmountCell(
            key: ValueKey('draft_out_$epoch'),
            width: _wOutflow,
            value: outflow,
            color: cs.onSurface,
            onCommit: onOutflow,
            onChanged: onOutflow,
            onSubmit: onCommit,
          ),
          _readCell(
              width: _wRunning,
              right: true,
              child: Text('—',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant))),
          _readCell(
              width: _wAcctBal,
              right: true,
              child: Text('—',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant))),
          _InlineText(
            key: ValueKey('draft_note_$epoch'),
            width: _wNotes,
            initialValue: '',
            hintText: '—',
            muted: true,
            onCommit: onNote,
            onChanged: onNote,
            onSubmit: onCommit,
          ),
          SizedBox(
            width: _wDelete,
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

// ── Editable cell primitives ─────────────────────────────────────────────────────

class _InlineText extends StatefulWidget {
  final double width;
  final String initialValue;
  final String? hintText;
  final bool bold;
  final bool muted;
  final bool enabled;
  final ValueChanged<String> onCommit;

  /// Fired live on every keystroke (used by the draft row so its value is
  /// current even if the field hasn't blurred when "Add row" is clicked).
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmit;
  const _InlineText({
    super.key,
    required this.width,
    required this.initialValue,
    this.hintText,
    this.bold = false,
    this.muted = false,
    this.enabled = true,
    required this.onCommit,
    this.onChanged,
    this.onSubmit,
  });

  @override
  State<_InlineText> createState() => _InlineTextState();
}

class _InlineTextState extends State<_InlineText> {
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
  void didUpdateWidget(_InlineText old) {
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
      color: widget.muted ? cs.onSurfaceVariant : cs.onSurface,
    );
    if (!widget.enabled) {
      return _readCell(
        width: widget.width,
        child: Text(
            widget.initialValue.isEmpty
                ? (widget.hintText ?? '')
                : widget.initialValue,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style),
      );
    }
    return SizedBox(
      width: widget.width,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: WebInsets.sm, vertical: WebInsets.xs),
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
                width: 1.5),
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: WebInsets.sm, vertical: 4),
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
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AmountCell extends StatefulWidget {
  final double width;
  final double value;
  final Color color;
  final bool enabled;
  final ValueChanged<double> onCommit;

  /// Fired live on every keystroke (used by the draft row so its value is
  /// current even if the field hasn't blurred when "Add row" is clicked).
  final ValueChanged<double>? onChanged;
  final VoidCallback? onSubmit;
  const _AmountCell({
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
  State<_AmountCell> createState() => _AmountCellState();
}

class _AmountCellState extends State<_AmountCell> {
  late final TextEditingController _c;
  late final FocusNode _f;
  bool _focused = false;

  static final _fmt = NumberFormat('#,##0.##', 'en_PH');

  String _display(double v) => v <= 0 ? '' : _fmt.format(v);

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
  void didUpdateWidget(_AmountCell old) {
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
      return _readCell(
        width: widget.width,
        right: true,
        child: Text(widget.value <= 0 ? '—' : _display(widget.value),
            textAlign: TextAlign.right, style: style),
      );
    }
    return SizedBox(
      width: widget.width,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: WebInsets.sm, vertical: WebInsets.xs),
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
                width: 1.5),
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: WebInsets.sm, vertical: 4),
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
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))
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
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountCell extends StatelessWidget {
  final double width;
  final String? value;
  final List<FinancialAccount> accounts;
  final ValueChanged<String> onChanged;
  const _AccountCell({
    required this.width,
    required this.value,
    required this.accounts,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasValue = accounts.any((a) => a.id == value);
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: WebInsets.sm, vertical: WebInsets.xs),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: hasValue ? value : null,
            isExpanded: true,
            isDense: true,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            style: theme.textTheme.bodySmall,
            icon: const Icon(Icons.expand_more_rounded, size: 16),
            hint: Text('Account',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
            items: accounts
                .map((a) => DropdownMenuItem(
                      value: a.id,
                      child: Text(a.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ),
    );
  }
}

class _CategoryCell extends StatelessWidget {
  final double width;
  final String? value;
  final List<FinanceCategory> categories;
  final Color Function(FinanceCategory?) colorFor;
  final ValueChanged<String> onChanged;
  const _CategoryCell({
    required this.width,
    required this.value,
    required this.categories,
    required this.colorFor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasValue = categories.any((c) => c.id == value);
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: WebInsets.sm, vertical: WebInsets.xs),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: hasValue ? value : null,
            isExpanded: true,
            isDense: true,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            style: theme.textTheme.bodySmall,
            icon: const Icon(Icons.expand_more_rounded, size: 16),
            hint: Text('Category',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
            items: categories
                .map((c) => DropdownMenuItem(
                      value: c.id,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: colorFor(c),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: WebInsets.sm),
                          Flexible(
                            child: Text(c.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ),
    );
  }
}

class _DateCell extends StatelessWidget {
  final double width;
  final DateTime date;
  final bool enabled;
  final ValueChanged<DateTime> onChanged;
  const _DateCell({
    required this.width,
    required this.date,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = _kMonthDayFmt.format(date);
    final text = Text(label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall);
    if (!enabled) return _readCell(width: width, child: text);
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: date,
            firstDate: DateTime(2020),
            lastDate: DateTime(2035),
          );
          if (picked != null) onChanged(picked);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: WebInsets.md, vertical: WebInsets.sm),
          child: Align(alignment: Alignment.centerLeft, child: text),
        ),
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

class _AddTransactionDialog extends StatefulWidget {
  final LedgerPresenter presenter;
  final ParsedTransaction? prefill;
  const _AddTransactionDialog({required this.presenter, this.prefill});

  @override
  State<_AddTransactionDialog> createState() => _AddTransactionDialogState();
}

class _AddTransactionDialogState extends State<_AddTransactionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _noteController = TextEditingController();

  TransactionType _type = TransactionType.outflow;
  String? _accountId;
  String? _toAccountId;
  String? _categoryId;
  DateTime _date = DateTime.now();
  bool _isSubmitting = false;

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
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _noteController.dispose();
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_accountId == null) return;
    if (_type == TransactionType.transfer && _toAccountId == null) return;

    setState(() => _isSubmitting = true);
    try {
      final amount = double.parse(_amountController.text.replaceAll(',', ''));
      final description = _descriptionController.text.trim();
      final note = _noteController.text.trim();
      final month = toMonthKey(_date);

      if (_type == TransactionType.transfer) {
        final cats = _p.categories;
        final expense = cats.where((c) => c.type == CategoryType.expense);
        final categoryId =
            (expense.isNotEmpty ? expense : cats).firstOrNull?.id ?? '';
        await _p.addTransfer(
          fromAccountId: _accountId!,
          toAccountId: _toAccountId!,
          amount: amount,
          categoryId: categoryId,
          description: description.isEmpty ? 'Transfer' : description,
          date: _date,
          note: note.isEmpty ? null : note,
        );
      } else {
        final id =
            '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';
        await _p.addTransaction(TransactionRecord(
          id: id,
          date: _date,
          accountId: _accountId!,
          categoryId: _categoryId ?? '',
          amount: amount,
          type: _type,
          description: description,
          note: note.isEmpty ? null : note,
          month: month,
        ));
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

    return Dialog(
      backgroundColor: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  WebInsets.xl, WebInsets.lg, WebInsets.md, WebInsets.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Add Transaction',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
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
                        : const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add Transaction'),
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
              Icon(Icons.calendar_today_outlined,
                  size: 16, color: cs.onSurfaceVariant),
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
    required ValueChanged<String?> onChanged,
  }) {
    final accounts = _accounts;
    return _labeledField(
      label,
      DropdownButtonFormField<String>(
        initialValue: accounts.any((a) => a.id == value) ? value : null,
        isExpanded: true,
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
        ),
        items: accounts
            .map((a) => DropdownMenuItem(
                  value: a.id,
                  child: Text(a.name, overflow: TextOverflow.ellipsis),
                ))
            .toList(),
        onChanged: onChanged,
        validator: (v) => v == null ? 'Select an account' : null,
      ),
    );
  }

  Widget _categoryDropdown() {
    final cats = _filteredCategories;
    return _labeledField(
      'Category',
      DropdownButtonFormField<String>(
        initialValue: cats.any((c) => c.id == _categoryId) ? _categoryId : null,
        isExpanded: true,
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
        ),
        hint: Text(cats.isEmpty ? 'No categories' : 'Select…'),
        items: cats
            .map((c) => DropdownMenuItem(
                  value: c.id,
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: resolveSliceColor(c.colorHex, cats.indexOf(c),
                              brightness: Theme.of(context).brightness),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: WebInsets.sm),
                      Flexible(
                        child: Text(c.name, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ))
            .toList(),
        onChanged: (v) => setState(() => _categoryId = v),
        validator: (v) =>
            (v == null && cats.isNotEmpty) ? 'Select a category' : null,
      ),
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
