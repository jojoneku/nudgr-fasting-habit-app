import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/app_radii.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../../widgets/web_widgets.dart';
import 'web_ledger_dialogs.dart';
import 'web_ledger_filters.dart';
import 'web_ledger_table.dart';

/// Web Ledger page (Plan 050-B). A dense, sheet-like transaction feed grouped
/// by day with an in-content heading + "Add Transaction" launcher, search and
/// type filters, and a [showDialog]-based Add-Transaction modal that calls the
/// real [LedgerPresenter] add methods. Theme-aware throughout — reference is
/// the Claude Design export, palette is ours.
class WebLedgerPage extends StatefulWidget {
  final LedgerPresenter presenter;
  const WebLedgerPage({super.key, required this.presenter});

  @override
  State<WebLedgerPage> createState() => _WebLedgerPageState();
}

/// Lightweight type filter for the toolbar segmented control.
enum _LedgerFilter { all, income, expense }

class _WebLedgerPageState extends State<WebLedgerPage> {
  final _searchController = TextEditingController();
  String _query = '';
  _LedgerFilter _filter = _LedgerFilter.all;

  LedgerPresenter get _p => widget.presenter;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final next = _searchController.text.trim().toLowerCase();
    if (next == _query) return;
    setState(() => _query = next);
  }

  // ── Lookups ────────────────────────────────────────────────────────────────

  FinanceCategory? _categoryOf(TransactionRecord t) =>
      _p.categories.where((c) => c.id == t.categoryId).firstOrNull;

  FinancialAccount? _accountOf(String id) =>
      _p.accounts.where((a) => a.id == id).firstOrNull;

  /// Stable color for a category dot — mirrors the pie-chart color resolution
  /// so the ledger and charts always agree.
  Color _colorFor(FinanceCategory? cat) {
    if (cat == null) return Theme.of(context).colorScheme.onSurfaceVariant;
    final idx = _p.categories.indexWhere((c) => c.id == cat.id);
    return resolveSliceColor(cat.colorHex, idx < 0 ? 0 : idx);
  }

  bool _matchesFilters(TransactionRecord t) {
    final byType = switch (_filter) {
      _LedgerFilter.all => true,
      _LedgerFilter.income => t.type == TransactionType.inflow,
      _LedgerFilter.expense => t.type == TransactionType.outflow,
    };
    if (!byType) return false;
    if (_query.isEmpty) return true;
    final cat = _categoryOf(t)?.name.toLowerCase() ?? '';
    final acct = _accountOf(t.accountId)?.name.toLowerCase() ?? '';
    final haystack = '${t.description.toLowerCase()} '
        '${(t.note ?? '').toLowerCase()} $cat $acct';
    return haystack.contains(_query);
  }

  // ── Add-transaction modal ────────────────────────────────────────────────────

  Future<void> _openAddDialog() async {
    // The dashboard presenter may have added/removed accounts since the ledger
    // last loaded — refresh before the dropdowns are built (mirrors mobile).
    await _p.reloadAccounts();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _AddTransactionDialog(presenter: _p),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _p,
      builder: (context, _) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: double.infinity),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(WebInsets.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  WebSectionHeader(
                    title: 'Ledger',
                    subtitle:
                        'Every transaction for ${monthLabel(_p.selectedMonth)}.',
                    trailing: _AddButton(onPressed: _openAddDialog),
                  ),
                  if (_p.isLoading)
                    const _LoadingBlock()
                  else
                    _buildBody(context),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grouped = _p.groupedTransactions;

    // Apply search + type filters per day, dropping empty days.
    final sections = <WebTableSection<TransactionRecord>>[];
    var totalRows = 0;
    grouped.forEach((day, txns) {
      final rows = txns.where(_matchesFilters).toList();
      if (rows.isEmpty) return;
      totalRows += rows.length;
      final dayIn = rows
          .where((t) => t.type == TransactionType.inflow)
          .fold(0.0, (s, t) => s + t.amount);
      final dayOut = rows
          .where((t) => t.type == TransactionType.outflow)
          .fold(0.0, (s, t) => s + t.amount);
      sections.add(
        WebTableSection<TransactionRecord>(
          title: _dayLabel(day),
          trailing: _DayTotals(inflow: dayIn, outflow: dayOut),
          rows: rows,
        ),
      );
    });

    final hasAnyThisMonth = grouped.values.any((l) => l.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryRow(
          inflow: _p.filteredMonthInflow,
          outflow: _p.filteredMonthOutflow,
          net: _p.filteredMonthNet,
        ),
        const SizedBox(height: WebInsets.xl),
        _Toolbar(
          controller: _searchController,
          filter: _filter,
          onFilterChanged: (f) => setState(() => _filter = f),
          rowCount: totalRows,
        ),
        const SizedBox(height: WebInsets.md),
        WebCard(
          padding: EdgeInsets.zero,
          child: !hasAnyThisMonth
              ? _EmptyState(onAdd: _openAddDialog)
              : sections.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(WebInsets.xxl),
                      child: Center(
                        child: Text(
                          'No transactions match your filters.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                      child: WebDataTable<TransactionRecord>(
                        sections: sections,
                        onRowTap: null,
                        columns: _columns(context),
                      ),
                    ),
        ),
      ],
    );
  }

  List<WebColumn<TransactionRecord>> _columns(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return [
      WebColumn<TransactionRecord>(
        label: 'Description',
        flex: 4,
        cell: (context, t) {
          final isTransfer = t.transferGroupId != null;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t.description.isEmpty
                    ? (isTransfer ? 'Transfer' : '—')
                    : t.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              if ((t.note ?? '').isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  t.note!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ],
          );
        },
      ),
      WebColumn<TransactionRecord>(
        label: 'Account',
        flex: 3,
        cell: (context, t) {
          final acct = _accountOf(t.accountId)?.name ?? '—';
          final isTransfer = t.transferToAccountId != null;
          final to =
              isTransfer ? _accountOf(t.transferToAccountId!)?.name : null;
          return Text(
            to != null ? '$acct → $to' : acct,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          );
        },
      ),
      WebColumn<TransactionRecord>(
        label: 'Category',
        flex: 3,
        cell: (context, t) {
          final isTransfer = t.transferGroupId != null;
          if (isTransfer) {
            return const Align(
              alignment: Alignment.centerLeft,
              child: WebBadge('Transfer',
                  tone: WebBadgeTone.info, icon: Icons.swap_horiz_rounded),
            );
          }
          final cat = _categoryOf(t);
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _colorFor(cat),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: WebInsets.sm),
              Flexible(
                child: Text(
                  cat?.name ?? 'Uncategorized',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          );
        },
      ),
      WebColumn<TransactionRecord>(
        label: 'Amount',
        numeric: true,
        flex: 2,
        cell: (context, t) {
          final isTransfer = t.transferGroupId != null;
          final isInflow = t.type == TransactionType.inflow;
          final Color color;
          final String prefix;
          if (isTransfer) {
            color = cs.onSurfaceVariant;
            prefix = '';
          } else if (isInflow) {
            color = cs.tertiary;
            prefix = '+';
          } else {
            color = cs.error;
            prefix = '−';
          }
          return Text(
            '$prefix${formatPeso(t.amount)}',
            textAlign: TextAlign.right,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          );
        },
      ),
    ];
  }

  String _dayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('EEEE, MMM d').format(day);
  }
}

// ── Header add button ──────────────────────────────────────────────────────────

class _AddButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _AddButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('Add Transaction'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: WebInsets.lg),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.sm)),
        ),
      ),
    );
  }
}

// ── Month inflow / outflow / net summary ─────────────────────────────────────────

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
          child: WebStatTile(
            label: 'Inflow',
            value: '+${formatPeso(inflow)}',
            icon: Icons.south_west_rounded,
            valueColor: cs.tertiary,
          ),
        ),
        const SizedBox(width: WebInsets.md),
        Expanded(
          child: WebStatTile(
            label: 'Outflow',
            value: '−${formatPeso(outflow)}',
            icon: Icons.north_east_rounded,
          ),
        ),
        const SizedBox(width: WebInsets.md),
        Expanded(
          child: WebStatTile(
            label: 'Net Cash',
            value: '${netPositive ? '+' : '−'}${formatPeso(net.abs())}',
            icon: Icons.swap_vert_rounded,
            valueColor: netPositive ? cs.tertiary : cs.error,
          ),
        ),
      ],
    );
  }
}

// ── Search + type-filter toolbar ─────────────────────────────────────────────────

class _Toolbar extends StatelessWidget {
  final TextEditingController controller;
  final _LedgerFilter filter;
  final ValueChanged<_LedgerFilter> onFilterChanged;
  final int rowCount;

  const _Toolbar({
    required this.controller,
    required this.filter,
    required this.onFilterChanged,
    required this.rowCount,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 44,
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search description, category or account…',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: WebInsets.md),
        _SegmentedFilter(selected: filter, onChanged: onFilterChanged),
        const SizedBox(width: WebInsets.md),
        Text(
          rowCount == 1 ? '1 row' : '$rowCount rows',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _SegmentedFilter extends StatelessWidget {
  final _LedgerFilter selected;
  final ValueChanged<_LedgerFilter> onChanged;
  const _SegmentedFilter({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 44,
      padding: const EdgeInsets.all(WebInsets.xs),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(context, _LedgerFilter.all, 'All'),
          _segment(context, _LedgerFilter.income, 'Income'),
          _segment(context, _LedgerFilter.expense, 'Expense'),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, _LedgerFilter value, String label) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = value == selected;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Material(
        color: isSelected ? cs.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.sm - 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.sm - 2),
          onTap: () => onChanged(value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: WebInsets.md),
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

// ── Per-day total trailing widget ─────────────────────────────────────────────────

class _DayTotals extends StatelessWidget {
  final double inflow;
  final double outflow;
  const _DayTotals({required this.inflow, required this.outflow});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final style = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (inflow > 0)
          Text('+${formatPeso(inflow)}',
              style: style?.copyWith(color: cs.tertiary)),
        if (inflow > 0 && outflow > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: WebInsets.sm),
            child: Text('·', style: TextStyle(color: cs.onSurfaceVariant)),
          ),
        if (outflow > 0)
          Text('−${formatPeso(outflow)}',
              style: style?.copyWith(color: cs.onSurface)),
      ],
    );
  }
}

// ── Loading + empty states ─────────────────────────────────────────────────────────

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

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: WebInsets.xxl + WebInsets.lg, horizontal: WebInsets.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 40, color: cs.onSurfaceVariant),
          const SizedBox(height: WebInsets.md),
          Text('No transactions yet this month',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: WebInsets.xs),
          Text('Add your first transaction to start the ledger.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: WebInsets.lg),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Transaction'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Add-Transaction modal
// ═══════════════════════════════════════════════════════════════════════════════

class _AddTransactionDialog extends StatefulWidget {
  final LedgerPresenter presenter;
  const _AddTransactionDialog({required this.presenter});

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
    if (liquid.isNotEmpty) _accountId = liquid.first.id;
    if (liquid.length > 1) _toAccountId = liquid[1].id;
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
      _categoryId = null; // categories differ per income/expense
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

  /// Builds the same model the mobile sheet builds and calls the same presenter
  /// method: [LedgerPresenter.addTransfer] for transfers, otherwise
  /// [LedgerPresenter.addTransaction] with a freshly-constructed
  /// [TransactionRecord].
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
        // Transfers need a categoryId per the data model; reuse the presenter's
        // own fallback shape by handing the first expense category (or any).
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
            // Header
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
            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(WebInsets.xl),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _TypeSegments(selected: _type, onChanged: _setType),
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
            // Footer
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
            if (_mode == LedgerViewMode.table)
              _TableMode(
                presenter: presenter,
                onAdd: _addTransaction,
                onEditRow: _editTransaction,
              )
            else
              _ChatMode(presenter: presenter),
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
                          color: resolveSliceColor(c.colorHex, cats.indexOf(c)),
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

// ── Type segmented control (Expense / Income / Transfer) ─────────────────────────

class _TypeSegments extends StatelessWidget {
  final TransactionType selected;
  final ValueChanged<TransactionType> onChanged;
  const _TypeSegments({required this.selected, required this.onChanged});

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

// ── Mode toggle ───────────────────────────────────────────────────────────

class _ModeToggle extends StatelessWidget {
  final LedgerViewMode mode;
  final ValueChanged<LedgerViewMode> onChanged;
  const _ModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<LedgerViewMode>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(
          value: LedgerViewMode.table,
          icon: Icon(Icons.table_rows_outlined, size: 18),
          label: Text('Table'),
        ),
        ButtonSegment(
          value: LedgerViewMode.chat,
          icon: Icon(Icons.chat_bubble_outline, size: 18),
          label: Text('Chat'),
        ),
      ],
      selected: {mode},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

// ── Table mode ──────────────────────────────────────────────────────────────

class _TableMode extends StatelessWidget {
  final LedgerPresenter presenter;
  final VoidCallback onAdd;
  final void Function(TransactionRecord txn) onEditRow;
  const _TableMode({
    required this.presenter,
    required this.onAdd,
    required this.onEditRow,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LedgerFilterBar(presenter: presenter, onAdd: onAdd),
        const SizedBox(height: WebInsets.lg),
        WebCard(
          padding: EdgeInsets.zero,
          child: LedgerDataTable(presenter: presenter, onRowTap: onEditRow),
        ),
      ],
    );
  }
}

// ── Chat mode (embeds the existing mobile chat view) ─────────────────────────

class _ChatMode extends StatelessWidget {
  final LedgerPresenter presenter;
  const _ChatMode({required this.presenter});

  @override
  Widget build(BuildContext context) {
    // LedgerView is a full Scaffold (its own input bar lives at the bottom).
    // Give it a bounded height so it lays out inside the scrolling web page
    // instead of trying to fill an unbounded column.
    final height = MediaQuery.sizeOf(context).height - 220;
    return WebCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: height.clamp(420.0, 900.0),
          child: LedgerView(presenter: presenter),
        ),
      ),
    );
  }
}
