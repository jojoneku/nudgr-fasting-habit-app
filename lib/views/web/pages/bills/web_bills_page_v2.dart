/// The Bills page of the Treasury web v2 (Plan 063, Phase 5).
///
/// One header with the month stepper and one Add ▾ menu; a due-soon hero; ONE
/// tabbed list (Upcoming · Set-asides · Receivables · Installments · Paid)
/// with batch selection; the credit cards & lines card; and a side column
/// (This month · By account · Coming up). A bill appears once: in the hero
/// when it is due soon, and in its tab.
///
/// Same presenter calls as the pre-v2 page: the presenters own every figure,
/// the series reach and the statement cycle; this file lays them out.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/shared/account_badge_widget.dart';
import 'package:intermittent_fasting/views/treasury/shared/category_badge_widget.dart';
import 'package:intermittent_fasting/views/treasury/shared/recurring_scope_field.dart';
import 'package:intermittent_fasting/views/web/design/account_category_label.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';
import '../../web_keys.dart';
import '../../widgets/web_widgets.dart';
import 'web_bills_forms_v2.dart';
import 'web_statement_breakdown_dialog.dart';

final _shortDate = DateFormat('MMM d');

/// Below this content width the side column drops under the list.
const double _kTwoColumnMin = 900;

/// The v2 Bills page. Reads exclusively from the injected presenters.
///
/// [trailing] is the header slot the shell fills (the Ask Nudgy button); it
/// renders among the header actions before the Add ▾ menu.
class WebBillsPageV2 extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final InstallmentPresenter installmentPresenter;
  final Widget? trailing;

  const WebBillsPageV2({
    super.key,
    required this.presenter,
    required this.installmentPresenter,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // Installments surface as bills only via the presenter's auto-generated
      // statements, but we still listen so counts stay live if it reloads.
      listenable: Listenable.merge([presenter, installmentPresenter]),
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.all(WebInsets.xxl),
        child: _BillsBodyV2(
          presenter: presenter,
          installmentPresenter: installmentPresenter,
          trailing: trailing,
        ),
      ),
    );
  }
}

// ─── Tabs and sections ────────────────────────────────────────────────────────

enum _BillsTab { upcoming, setAsides, receivables, installments, paid }

/// Which list a running batch selection belongs to. Only one section can be
/// selecting at a time — a batch settles through one account on one date, and
/// a selection spanning bills *and* receivables has no single meaning. Paid
/// bills share the bills section, which is what makes batch undo reachable.
enum _BatchSection { bills, receivables, budgeted, installments }

extension on _BillsTab {
  _BatchSection get section => switch (this) {
        _BillsTab.upcoming || _BillsTab.paid => _BatchSection.bills,
        _BillsTab.setAsides => _BatchSection.budgeted,
        _BillsTab.receivables => _BatchSection.receivables,
        _BillsTab.installments => _BatchSection.installments,
      };

  String get emptyCopy => switch (this) {
        _BillsTab.upcoming => 'No bills due — you are all caught up.',
        _BillsTab.setAsides => 'No set-asides budgeted this month.',
        _BillsTab.receivables => 'Nothing owed to you this month.',
        _BillsTab.installments => 'No installment payments due this month.',
        _BillsTab.paid => 'Nothing paid yet this month.',
      };
}

enum _AddKind { bill, receivable, setAside, installment }

// ─── Body ─────────────────────────────────────────────────────────────────────

class _BillsBodyV2 extends StatefulWidget {
  final BillsReceivablesPresenter presenter;
  final InstallmentPresenter installmentPresenter;
  final Widget? trailing;

  const _BillsBodyV2({
    required this.presenter,
    required this.installmentPresenter,
    required this.trailing,
  });

  @override
  State<_BillsBodyV2> createState() => _BillsBodyV2State();
}

class _BillsBodyV2State extends State<_BillsBodyV2> {
  _BillsTab _tab = _BillsTab.upcoming;

  /// The section currently selecting, or null when not in selection mode.
  _BatchSection? _section;

  /// Ids picked in [_section].
  final Set<String> _selectedIds = {};

  /// True while a batch is in flight, so a second click can't fire it twice.
  bool _busy = false;

  BillsReceivablesPresenter get presenter => widget.presenter;
  InstallmentPresenter get installmentPresenter => widget.installmentPresenter;

  // ── Presenter-backed lists and totals (Rule 1: no math in build) ─────────

  List<Bill> get _unpaid => [...presenter.bills.where((b) => !b.isPaid)]
    ..sort((a, b) => a.dueDay.compareTo(b.dueDay));

  List<Bill> get _paid => [...presenter.bills.where((b) => b.isPaid)]
    ..sort((a, b) => a.dueDay.compareTo(b.dueDay));

  List<Receivable> get _receivables {
    final all = presenter.receivables;
    // Still-pending receivables float to the top; received ones sink below.
    return [
      ...all.where((r) => !r.isReceived),
      ...all.where((r) => r.isReceived),
    ];
  }

  List<BudgetedExpense> get _setAsides {
    final all = presenter.budgetedExpenses;
    // Unfunded first, funded below (stable partition).
    return [...all.where((e) => !e.isPaid), ...all.where((e) => e.isPaid)];
  }

  List<Installment> get _installmentsDue => installmentPresenter.dueThisMonth;

  Bill? get _heroBill => presenter.imminentUnpaidBills.firstOrNull;

  Set<String> get _imminentIds =>
      {for (final b in presenter.imminentUnpaidBills) b.id};

  double get _setAsidePendingTotal => presenter.budgetedExpenses
      .where((e) => !e.isPaid)
      .fold(0.0, (s, e) => s + e.allocatedAmount);

  int get _setAsidePendingCount =>
      presenter.budgetedExpenses.where((e) => !e.isPaid).length;

  List<String> _idsOf(_BatchSection section) => switch (section) {
        // Select-all covers every bill, paid included — the Paid tab is the
        // same selection, which is what makes a batch undo reachable.
        _BatchSection.bills => [
            for (final b in [..._unpaid, ..._paid]) b.id
          ],
        _BatchSection.receivables => [for (final r in _receivables) r.id],
        _BatchSection.budgeted => [for (final e in _setAsides) e.id],
        _BatchSection.installments => [for (final i in _installmentsDue) i.id],
      };

  // ── Selection ────────────────────────────────────────────────────────────

  bool _picking(_BatchSection section) => _section == section;
  bool _locked(_BatchSection section) =>
      _section != null && _section != section;

  void _start(_BatchSection section) => setState(() {
        _section = section;
        _selectedIds.clear();
      });

  void _exitSelection() => setState(() {
        _section = null;
        _selectedIds.clear();
      });

  void _toggle(String id) => setState(() {
        if (!_selectedIds.remove(id)) _selectedIds.add(id);
        // Emptying the selection leaves selection mode, same as mobile — an
        // empty batch bar has nothing to offer.
        if (_selectedIds.isEmpty) _section = null;
      });

  void _toggleAll(List<String> ids) => setState(() {
        final all = ids.isNotEmpty && ids.every(_selectedIds.contains);
        _selectedIds.clear();
        if (!all) _selectedIds.addAll(ids);
        if (_selectedIds.isEmpty) _section = null;
      });

  void _setTab(int index) {
    final next = _BillsTab.values[index];
    setState(() {
      // A selection belongs to one section; moving to another tab's list
      // ends it rather than carrying a hidden selection along.
      if (_section != null && _section != next.section) {
        _section = null;
        _selectedIds.clear();
      }
      _tab = next;
    });
  }

  /// How [id] participates in the selection, or null when [section] isn't the
  /// one selecting — which is what makes a row render normally.
  WebRowSelection? _selectionFor(_BatchSection section, String id) {
    if (!_picking(section)) return null;
    return WebRowSelection(
      active: true,
      selected: _selectedIds.contains(id),
      onToggle: () => _toggle(id),
    );
  }

  List<Bill> get _selectedBills =>
      presenter.bills.where((b) => _selectedIds.contains(b.id)).toList();

  List<Receivable> get _selectedReceivables =>
      presenter.receivables.where((r) => _selectedIds.contains(r.id)).toList();

  List<BudgetedExpense> get _selectedExpenses => presenter.budgetedExpenses
      .where((e) => _selectedIds.contains(e.id))
      .toList();

  List<Installment> get _selectedInstallments =>
      installmentPresenter.dueThisMonth
          .where((i) => _selectedIds.contains(i.id))
          .toList();

  /// What the action bar needs: how many picked rows can still be settled, how
  /// many can be reversed, and the settle verb.
  ({int settleable, int undoable, String verb}) _batchStatus(
      _BatchSection section) {
    switch (section) {
      case _BatchSection.bills:
        final picked = _selectedBills;
        return (
          settleable: picked.where((b) => !b.isPaid).length,
          undoable: picked.where((b) => b.isPaid).length,
          verb: 'Pay',
        );
      case _BatchSection.receivables:
        final picked = _selectedReceivables;
        return (
          settleable: picked.where((r) => !r.isReceived).length,
          undoable: picked.where((r) => r.isReceived).length,
          verb: 'Receive',
        );
      case _BatchSection.budgeted:
        final picked = _selectedExpenses;
        return (
          settleable: picked.where((e) => !e.isPaid).length,
          undoable: picked.where((e) => e.isPaid).length,
          verb: 'Fund',
        );
      case _BatchSection.installments:
        final picked = _selectedInstallments;
        return (
          settleable: picked.where(installmentPresenter.canMarkPaid).length,
          undoable: picked.where(installmentPresenter.canMarkUnpaid).length,
          verb: 'Pay',
        );
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final unpaid = _unpaid;
    final pendingReceivables = presenter.pendingReceivables;
    final month = monthLabel(presenter.selectedMonth);
    final hero = _heroBill;

    final header = WebPageHeaderV2(
      title: 'Bills',
      subtitle: '$month · ${presenter.bills.length} '
          '${_plural(presenter.bills.length, 'bill')}, ${unpaid.length} still '
          'due · ${pendingReceivables.length} to receive · '
          '${formatPeso(presenter.totalBillsPending)} unpaid',
      monthStepper: WebMonthStepper(
        key: WebKeys.billsMonthStepper,
        label: month,
        onPrev: () =>
            presenter.setMonth(previousMonth(presenter.selectedMonth)),
        onNext: () => presenter.setMonth(nextMonth(presenter.selectedMonth)),
      ),
      actions: [
        if (widget.trailing != null) widget.trailing!,
        _AddMenuButton(onPick: (kind) => _openAdd(context, kind)),
      ],
    );

    final left = <Widget>[
      if (hero != null) ...[
        _DueSoonHeroV2(
          presenter: presenter,
          bill: hero,
          onMarkPaid: () => _markBillPaid(context, presenter, hero),
          onEdit: () =>
              showWebBillDialog(context, presenter: presenter, existing: hero),
          onToggleReminder: () => _toggleReminder(context, hero),
        ),
        const SizedBox(height: WebInsets.xl),
      ],
      _buildListCard(context),
      if (presenter.creditAccounts.isNotEmpty) ...[
        const SizedBox(height: WebInsets.xl),
        _CreditLinesCard(
          presenter: presenter,
          onPay: (card) => _payCard(context, card),
        ),
      ],
    ];

    final breakdown = presenter.fundingBreakdown();
    final comingUp = presenter.comingUpItems(installmentPresenter);
    final right = <Widget>[
      _ThisMonthCard(
        presenter: presenter,
        installmentPresenter: installmentPresenter,
        unpaidCount: unpaid.length,
        paidCount: _paid.length,
        setAsideTotal: _setAsidePendingTotal,
        setAsideCount: _setAsidePendingCount,
      ),
      if (breakdown.isNotEmpty) ...[
        const SizedBox(height: WebInsets.xl),
        _ByAccountCard(rows: breakdown),
      ],
      if (comingUp.isNotEmpty) ...[
        const SizedBox(height: WebInsets.xl),
        _ComingUpCard(
          items: comingUp.take(6).toList(),
          onTap: (item) => _openComingUpItem(context, item),
        ),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < _kTwoColumnMin) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...left,
                  const SizedBox(height: WebInsets.xl),
                  ...right,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: left,
                  ),
                ),
                const SizedBox(width: WebInsets.xl),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: right,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  // ── The tabbed list ──────────────────────────────────────────────────────

  Widget _buildListCard(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final section = _tab.section;
    final ids = _idsOf(section);

    final tabs = [
      WebTab('Upcoming', count: _unpaid.length, key: WebKeys.billsTabUpcoming),
      WebTab('Set-asides',
          count: _setAsides.length, key: WebKeys.billsTabSetAsides),
      WebTab('Receivables',
          count: _receivables.length, key: WebKeys.billsTabReceivables),
      WebTab('Installments',
          count: _installmentsDue.length, key: WebKeys.billsTabInstallments),
      WebTab('Paid', count: _paid.length, key: WebKeys.billsTabPaid),
    ];

    final selectControl = KeyedSubtree(
      key: WebKeys.billsBatchSelect,
      child: WebBatchSelectControl(
        active: _picking(section),
        locked: _locked(section),
        selectedCount: _selectedIds.length,
        totalCount: ids.length,
        onStart: () => _start(section),
        onCancel: _exitSelection,
        onToggleAll: () => _toggleAll(ids),
      ),
    );

    final status = _picking(section) ? _batchStatus(section) : null;

    return WebCard(
      key: WebKeys.billsListCard,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WebTabs(tabs: tabs, index: _tab.index, onChanged: _setTab),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WebInsets.lg,
              WebInsets.sm,
              WebInsets.md,
              0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _tabSummary,
                    key: WebKeys.billsTabSummary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                const SizedBox(width: WebInsets.sm),
                selectControl,
              ],
            ),
          ),
          ..._buildTabRows(context),
          if (status != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                WebInsets.lg,
                0,
                WebInsets.lg,
                WebInsets.md,
              ),
              child: WebBatchBar(
                key: WebKeys.billsBatchBar,
                settleVerb: status.verb,
                selectedCount: _selectedIds.length,
                settleableCount: status.settleable,
                undoableCount: status.undoable,
                enabled: !_busy,
                onSettle: _batchSettle,
                onUndo: _batchUndo,
                onDelete: _batchDelete,
              ),
            ),
          _buildFooter(context),
        ],
      ),
    );
  }

  List<Widget> _buildTabRows(BuildContext context) {
    switch (_tab) {
      case _BillsTab.upcoming:
        final unpaid = _unpaid;
        if (unpaid.isEmpty) return [_EmptyHint(_tab.emptyCopy)];
        final imminent = _imminentIds;
        final soon = unpaid.where((b) => imminent.contains(b.id)).toList();
        final later = unpaid.where((b) => !imminent.contains(b.id)).toList();
        final grouped = soon.isNotEmpty && later.isNotEmpty;
        Widget row(Bill b, bool last) => _BillRowV2(
              presenter: presenter,
              bill: b,
              divider: !last,
              selection: _selectionFor(_BatchSection.bills, b.id),
            );
        return [
          if (grouped) const _GroupLabel('Due soon'),
          for (var i = 0; i < soon.length; i++)
            row(soon[i], !grouped && i == soon.length - 1),
          if (grouped) const _GroupLabel('Later this month'),
          for (var i = 0; i < later.length; i++)
            row(later[i], i == later.length - 1),
        ];
      case _BillsTab.paid:
        final paid = _paid;
        if (paid.isEmpty) return [_EmptyHint(_tab.emptyCopy)];
        return [
          for (var i = 0; i < paid.length; i++)
            _BillRowV2(
              presenter: presenter,
              bill: paid[i],
              divider: i < paid.length - 1,
              selection: _selectionFor(_BatchSection.bills, paid[i].id),
            ),
        ];
      case _BillsTab.setAsides:
        final rows = _setAsides;
        if (rows.isEmpty) return [_EmptyHint(_tab.emptyCopy)];
        return [
          for (var i = 0; i < rows.length; i++)
            _SetAsideRowV2(
              presenter: presenter,
              expense: rows[i],
              divider: i < rows.length - 1,
              selection: _selectionFor(_BatchSection.budgeted, rows[i].id),
            ),
        ];
      case _BillsTab.receivables:
        final rows = _receivables;
        if (rows.isEmpty) return [_EmptyHint(_tab.emptyCopy)];
        return [
          for (var i = 0; i < rows.length; i++)
            _ReceivableRowV2(
              presenter: presenter,
              receivable: rows[i],
              divider: i < rows.length - 1,
              selection: _selectionFor(_BatchSection.receivables, rows[i].id),
            ),
        ];
      case _BillsTab.installments:
        final rows = _installmentsDue;
        if (rows.isEmpty) return [_EmptyHint(_tab.emptyCopy)];
        return [
          for (var i = 0; i < rows.length; i++)
            _InstallmentRowV2(
              presenter: installmentPresenter,
              bills: presenter,
              installment: rows[i],
              divider: i < rows.length - 1,
              selection: _selectionFor(_BatchSection.installments, rows[i].id),
            ),
        ];
    }
  }

  Widget _buildFooter(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final warning = context.appColors.bills;
    switch (_tab) {
      case _BillsTab.upcoming:
        final paid = _paid;
        return _ListFooter(
          label: 'Due',
          value: formatPeso(presenter.totalBillsPending),
          tone: presenter.totalBillsPending > 0 ? warning : cs.onSurface,
          hint: paid.isEmpty
              ? null
              : '${paid.length} paid already · '
                  '${formatPeso(presenter.totalBillsPaid)} settled',
        );
      case _BillsTab.setAsides:
        return _ListFooter(
          label: 'To set aside',
          value: formatPeso(_setAsidePendingTotal),
          tone: _setAsidePendingTotal > 0 ? warning : cs.onSurface,
        );
      case _BillsTab.receivables:
        return _ListFooter(
          label: 'Pending',
          value: '+${formatPeso(presenter.totalReceivablesPending)}',
          tone: cs.tertiary,
        );
      case _BillsTab.installments:
        return _ListFooter(
          label: 'Monthly load',
          value: '${formatPeso(installmentPresenter.totalPaidThisMonth)} / '
              '${formatPeso(installmentPresenter.monthlyInstallmentLoad)}',
          tone: warning,
          hint: 'paid / due this month',
        );
      case _BillsTab.paid:
        return _ListFooter(
          label: 'Settled',
          value: formatPeso(presenter.totalBillsPaid),
          tone: cs.tertiary,
        );
    }
  }

  /// The line under the tabs: what the open tab adds up to and how many rows
  /// it holds — the old cards' descriptions, one at a time.
  String get _tabSummary {
    switch (_tab) {
      case _BillsTab.upcoming:
        final n = _unpaid.length;
        if (n == 0) return 'Nothing due';
        final allMonthly = _unpaid.every((b) =>
            b.isRecurring &&
            (b.recurrenceType ?? RecurrenceType.monthly) ==
                RecurrenceType.monthly);
        return '${formatPeso(presenter.totalBillsPending)} across $n '
            '${_plural(n, 'bill')}${allMonthly ? ' · all monthly' : ''}';
      case _BillsTab.setAsides:
        final n = _setAsidePendingCount;
        if (n == 0) return 'Nothing left to set aside';
        return '${formatPeso(_setAsidePendingTotal)} across $n '
            '${_plural(n, 'set-aside')}';
      case _BillsTab.receivables:
        final n = presenter.pendingReceivables.length;
        if (n == 0) return 'Nothing pending';
        return '+${formatPeso(presenter.totalReceivablesPending)} across $n '
            '${_plural(n, 'receivable')}';
      case _BillsTab.installments:
        final n = _installmentsDue.length;
        if (n == 0) return 'No payments due';
        return '${formatPeso(installmentPresenter.monthlyInstallmentLoad)} '
            'this month across $n ${_plural(n, 'plan')}';
      case _BillsTab.paid:
        final n = _paid.length;
        if (n == 0) return 'Nothing paid yet';
        return '${formatPeso(presenter.totalBillsPaid)} across $n '
            '${_plural(n, 'bill')}';
    }
  }

  // ── Opening dialogs ──────────────────────────────────────────────────────

  void _openAdd(BuildContext context, _AddKind kind) {
    switch (kind) {
      case _AddKind.bill:
        showWebBillDialog(context, presenter: presenter);
      case _AddKind.receivable:
        showWebReceivableDialog(context, presenter: presenter);
      case _AddKind.setAside:
        showWebSetAsideDialog(context, presenter: presenter);
      case _AddKind.installment:
        showWebInstallmentDialog(context, presenter: installmentPresenter);
    }
  }

  /// Routes a "Coming up" row to the editor for its own kind, resolved off
  /// [ComingUpItem.source] — the same destination its tab row's Edit opens.
  void _openComingUpItem(BuildContext context, ComingUpItem item) {
    final source = item.source;
    if (source is Bill) {
      showWebBillDialog(context, presenter: presenter, existing: source);
    } else if (source is Receivable) {
      showWebReceivableDialog(context, presenter: presenter, existing: source);
    } else if (source is BudgetedExpense) {
      showWebSetAsideDialog(context, presenter: presenter, existing: source);
    } else if (source is Installment) {
      showWebInstallmentDialog(context,
          presenter: installmentPresenter, existing: source);
    }
  }

  Future<void> _toggleReminder(BuildContext context, Bill bill) async {
    final on = bill.reminderDaysBefore != null;
    try {
      await presenter.updateBill(
        bill.copyWith(reminderDaysBefore: on ? null : 1),
      );
      if (!context.mounted) return;
      AppToast.show(
        context,
        on
            ? 'Reminder off for ${bill.name}.'
            : 'Reminder set · 1 day before ${bill.name} is due.',
      );
    } catch (e) {
      if (context.mounted) AppToast.error(context, 'Could not save bill: $e');
    }
  }

  Future<void> _payCard(BuildContext context, FinancialAccount card) async {
    final paid = await showWebQuickPayDialog(
      context,
      card: card,
      presenter: presenter,
    );
    if (paid != null && context.mounted) {
      AppToast.success(context, 'Paid ${formatPeso(paid)} to ${card.name}.');
    }
  }

  // ── Batch actions ────────────────────────────────────────────────────────
  //
  // Each handler resolves the picked rows from the presenter's live lists,
  // asks once for whatever the whole batch shares, hands the work to a
  // presenter batch method, then reports what happened and leaves selection
  // mode. Same shape as the mobile view's handlers.

  /// Reports a finished batch and leaves selection mode. [skipped] rows are
  /// named explicitly — a batch that only half-applied must never read as a
  /// clean success.
  void _finishBatch(String message, {int skipped = 0}) {
    if (!mounted) return;
    _exitSelection();
    AppToast.show(
      context,
      skipped == 0
          ? message
          : '$message $skipped couldn\'t be done — check their accounts.',
    );
  }

  Future<void> _runBatch(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _batchSettle() => _runBatch(() async {
        switch (_section!) {
          case _BatchSection.bills:
            await _batchPayBills();
          case _BatchSection.receivables:
            await _batchReceiveReceivables();
          case _BatchSection.budgeted:
            await _batchFundExpenses();
          case _BatchSection.installments:
            await _batchPayInstallments();
        }
      });

  Future<void> _batchPayBills() async {
    final targets = _selectedBills.where((b) => !b.isPaid).toList();
    if (targets.isEmpty) return;
    // One row is the single flow — it honours the edited amount.
    if (targets.length == 1) {
      final paid = await _markBillPaid(context, presenter, targets.single);
      if (paid) _exitSelection();
      return;
    }
    final result = await showWebSettleDialog(
      context,
      kind: SettleKind.bill,
      targets: [
        for (final b in targets)
          SettleTarget(
            id: b.id,
            name: b.name,
            amount: presenter.billAmountOwed(b),
            dateLabel: _shortDate.format(presenter.billDueDate(b)),
          ),
      ],
      accounts: presenter.payerAccountsForAll(targets),
      initialAccountId: presenter.preferredBatchPayerAccountId(targets),
      requiresAccount: false,
    );
    if (result == null) return;
    // With no eligible account there is nothing to debit, so the bills are
    // flagged paid without a ledger entry rather than failing.
    final record = result.recordInLedger && result.accountId != null;
    final outcome = await presenter.markBillsPaid(
      [for (final b in targets) b.id],
      accountId: record ? result.accountId : null,
      paidDate: result.date,
      recordInLedger: record,
    );
    _finishBatch(
      'Marked ${outcome.applied} ${_plural(outcome.applied, 'bill')} paid.',
      skipped: outcome.skipped,
    );
  }

  Future<void> _batchReceiveReceivables() async {
    final targets = _selectedReceivables.where((r) => !r.isReceived).toList();
    if (targets.isEmpty) return;
    if (targets.length == 1) {
      final done = await _markReceived(context, presenter, targets.single);
      if (done) _exitSelection();
      return;
    }
    final result = await showWebSettleDialog(
      context,
      kind: SettleKind.receivable,
      targets: [
        for (final r in targets)
          SettleTarget(
            id: r.id,
            name: r.name,
            amount: r.amount,
            dateLabel: r.expectedDate == null
                ? 'ASAP'
                : _shortDate.format(r.expectedDate!),
          ),
      ],
      accounts: presenter.depositAccountsFor(targets.first),
      initialAccountId: presenter.preferredDepositAccountId(targets.first),
      requiresAccount: false,
    );
    if (result == null) return;
    final record = result.recordInLedger && result.accountId != null;
    final outcome = await presenter.markReceivablesReceived(
      [for (final r in targets) r.id],
      accountId: record ? result.accountId : null,
      receivedDate: result.date,
      recordInLedger: record,
    );
    _finishBatch('Marked ${outcome.applied} received.');
  }

  Future<void> _batchFundExpenses() async {
    final targets = _selectedExpenses.where((e) => !e.isPaid).toList();
    if (targets.isEmpty) return;
    final funders = presenter.setAsideFundingAccounts;
    if (funders.isEmpty) {
      AppToast.error(context, 'Add an account before funding.');
      return;
    }
    if (targets.length == 1) {
      final done = await _fundSetAside(context, presenter, targets.single);
      if (done) _exitSelection();
      return;
    }
    // Rows that already know where they are going keep their own destination;
    // the dialog only has to ask about the rest.
    final withDestination = targets
        .where((e) => presenter.preferredSetAsideDestinationId(e) != null)
        .length;
    final named = targets.map((e) => e.accountId).toSet();
    final result = await showWebSettleDialog(
      context,
      kind: SettleKind.setAside,
      targets: [
        for (final e in targets)
          SettleTarget(id: e.id, name: e.name, amount: e.allocatedAmount),
      ],
      accounts: funders,
      destinations: presenter.setAsideDestinationAccounts,
      initialAccountId: named.length == 1 ? named.first : null,
      savedDestinationCount: withDestination,
      requiresAccount: false,
    );
    if (result == null || result.accountId == null) return;
    final outcome = await presenter.markExpensesPaid(
      [for (final e in targets) e.id],
      accountId: result.accountId!,
      toAccountId: result.destinationId,
      preferSavedDestination: result.useSavedDestinations,
      paidDate: result.date,
    );
    _finishBatch(
        'Funded ${outcome.applied} ${_plural(outcome.applied, 'set-aside')}.');
  }

  Future<void> _batchPayInstallments() async {
    final targets =
        _selectedInstallments.where(installmentPresenter.canMarkPaid).toList();
    if (targets.isEmpty) return;
    if (targets.length == 1) {
      final done =
          await _payInstallment(context, installmentPresenter, targets.single);
      if (done) _exitSelection();
      return;
    }
    final result = await showWebSettleDialog(
      context,
      kind: SettleKind.installment,
      targets: [
        for (final i in targets)
          SettleTarget(id: i.id, name: i.name, amount: i.monthlyAmount),
      ],
      accounts: const [],
      requiresAccount: false,
    );
    if (result == null) return;
    final applied = await installmentPresenter
        .markManyPaid([for (final i in targets) i.id], date: result.date);
    _finishBatch(
        'Paid $applied ${_plural(applied, 'installment')} this month.');
  }

  Future<void> _batchUndo() => _runBatch(() async {
        switch (_section!) {
          case _BatchSection.bills:
            final targets = _selectedBills.where((b) => b.isPaid).toList();
            if (targets.isEmpty) return;
            final choice = await showWebUndoSettlementDialog(
              context,
              title: 'Undo ${targets.length} payments?',
              name: _batchName(targets.length, 'bill'),
              entryLabel: 'bill',
              hasLedgerEntry: targets.any(presenter.billHasLedgerEntry),
              ledgerEffect:
                  '${formatPeso(targets.fold(0.0, (s, b) => s + (b.paidAmount ?? b.amount)))} '
                  'goes back into the accounts they were paid from.',
            );
            if (choice == null) return;
            final outcome = await presenter.markBillsUnpaid(
              [for (final b in targets) b.id],
              removeTransaction: choice.removeTransaction,
            );
            _finishBatch('Marked ${outcome.applied} '
                '${_plural(outcome.applied, 'bill')} unpaid.');
          case _BatchSection.receivables:
            final targets =
                _selectedReceivables.where((r) => r.isReceived).toList();
            if (targets.isEmpty) return;
            final choice = await showWebUndoSettlementDialog(
              context,
              title: 'Undo ${targets.length} receipts?',
              name: _batchName(targets.length, 'receivable'),
              entryLabel: 'receivable',
              hasLedgerEntry: targets.any(presenter.receivableHasLedgerEntry),
              ledgerEffect:
                  '${formatPeso(targets.fold(0.0, (s, r) => s + (r.receivedAmount ?? r.amount)))} '
                  'is taken back out of the accounts it was deposited into.',
            );
            if (choice == null) return;
            final outcome = await presenter.markReceivablesUnreceived(
              [for (final r in targets) r.id],
              removeTransaction: choice.removeTransaction,
            );
            _finishBatch('Marked ${outcome.applied} not received.');
          case _BatchSection.budgeted:
            final targets = _selectedExpenses.where((e) => e.isPaid).toList();
            if (targets.isEmpty) return;
            final choice = await showWebUndoSettlementDialog(
              context,
              title: 'Undo ${targets.length} fundings?',
              name: _batchName(targets.length, 'set-aside'),
              entryLabel: 'set-aside',
              hasLedgerEntry: targets.any(presenter.expenseHasLedgerEntry),
              ledgerEffect:
                  '${formatPeso(targets.fold(0.0, (s, e) => s + e.spentAmount))} '
                  'is moved back to the accounts it was funded from.',
            );
            if (choice == null) return;
            final outcome = await presenter.markExpensesUnpaid(
              [for (final e in targets) e.id],
              removeTransaction: choice.removeTransaction,
            );
            _finishBatch('Marked ${outcome.applied} '
                '${_plural(outcome.applied, 'set-aside')} unfunded.');
          case _BatchSection.installments:
            final targets = _selectedInstallments
                .where(installmentPresenter.canMarkUnpaid)
                .toList();
            if (targets.isEmpty) return;
            final choice = await showWebUndoSettlementDialog(
              context,
              title: 'Undo ${targets.length} payments?',
              name: _batchName(targets.length, 'installment payment'),
              entryLabel: 'installment payment',
              // An installment payment IS its transaction — there is no flag
              // to reverse on its own, so the transaction always goes with it.
              hasLedgerEntry: false,
              ledgerEffect:
                  "This month's payment transactions are removed and the "
                  'accounts they were paid from are credited back.',
            );
            if (choice == null) return;
            final applied = await installmentPresenter
                .markManyUnpaid([for (final i in targets) i.id]);
            _finishBatch('Marked $applied '
                '${_plural(applied, 'installment')} unpaid this month.');
        }
      });

  Future<void> _batchDelete() => _runBatch(() async {
        final section = _section!;
        final ids = _selectedIds.toList();
        final noun = switch (section) {
          _BatchSection.bills => 'bill',
          _BatchSection.receivables => 'receivable',
          _BatchSection.budgeted => 'set-aside',
          _BatchSection.installments => 'installment',
        };
        // Same series question the row's own delete asks. Installments have
        // no per-month row, so no scope.
        final reach = switch (section) {
          _BatchSection.bills => presenter.billBatchSeriesReach(ids),
          _BatchSection.receivables =>
            presenter.receivableBatchSeriesReach(ids),
          _BatchSection.budgeted => presenter.expenseBatchSeriesReach(ids),
          _BatchSection.installments => (recurring: 0, extraMonths: 0),
        };
        final scope = await confirmWebRecurringBatchDelete(
          context,
          noun: noun,
          month: presenter.selectedMonth,
          selectedCount: ids.length,
          recurringCount: reach.recurring,
          extraMonthCount: reach.extraMonths,
          plainBody: section == _BatchSection.installments
              ? 'Their linked payment transactions are removed too. This '
                  'cannot be undone.'
              : 'This cannot be undone.',
          soleName: ids.length == 1 ? _batchSoleName(section, ids.first) : null,
        );
        if (scope == null) return;
        final applyToFuture = scope == RecurringScope.thisAndFuture;
        final deleted = switch (section) {
          _BatchSection.bills =>
            await presenter.deleteBills(ids, applyToFuture: applyToFuture),
          _BatchSection.receivables => await presenter.deleteReceivables(ids,
              applyToFuture: applyToFuture),
          _BatchSection.budgeted => await presenter.deleteBudgetedExpenses(ids,
              applyToFuture: applyToFuture),
          _BatchSection.installments =>
            await installmentPresenter.deleteInstallments(ids),
        };
        _finishBatch('Deleted $deleted ${_plural(deleted, noun)}.');
      });

  /// The name of the only selected row, so a one-row batch delete is asked
  /// about by name rather than as "1 receivable".
  String? _batchSoleName(_BatchSection section, String id) {
    final names = switch (section) {
      _BatchSection.bills => [
          for (final b in presenter.allBills)
            if (b.id == id) b.name
        ],
      _BatchSection.receivables => [
          for (final r in presenter.allReceivables)
            if (r.id == id) r.name
        ],
      _BatchSection.budgeted => [
          for (final e in presenter.allBudgetedExpenses)
            if (e.id == id) e.name
        ],
      _BatchSection.installments => const <String>[],
    };
    return names.isEmpty ? null : names.first;
  }
}

String _plural(int n, String singular) => n == 1 ? singular : '${singular}s';

String _batchName(int n, String singular) => '$n ${_plural(n, singular)}';

// ─── Settle flows ─────────────────────────────────────────────────────────────
//
// Top-level because several surfaces drive each one — a row's action, the
// hero, a one-row batch — and a second copy would be a second set of rules
// for which accounts may fund what. Each returns true when something was
// settled.

Future<bool> _markBillPaid(
  BuildContext context,
  BillsReceivablesPresenter presenter,
  Bill bill,
) async {
  // payerAccountsFor excludes the liability itself for a statement bill (you
  // can't pay a statement from the card it belongs to); restrict to active
  // liquid accounts as the fundable set.
  final payers = presenter
      .payerAccountsFor(bill)
      .where((a) => a.isActive && a.isLiquid)
      .toList();
  String? preferredAccountId = payers.firstOrNull?.id;
  if (bill.accountId != null && payers.any((a) => a.id == bill.accountId)) {
    preferredAccountId = bill.accountId;
  }
  final result = await showWebSettleDialog(
    context,
    kind: SettleKind.bill,
    targets: [
      SettleTarget(
        id: bill.id,
        name: bill.name,
        // A part-paid credit statement prefills what is left, not the bill.
        amount: presenter.billAmountOwed(bill),
        dateLabel: 'due ${_shortDate.format(presenter.billDueDate(bill))}',
        accountId: bill.accountId,
      ),
    ],
    accounts: payers,
    initialAccountId: preferredAccountId,
    emptyAccountsMessage: 'Add a funding account before marking paid.',
    onSubmit: (r) => presenter.markBillPaid(
      bill.id,
      paidAmount: r.amount,
      accountId: r.accountId,
      paidDate: r.date,
      recordInLedger: r.recordInLedger,
    ),
  );
  if (result == null || !context.mounted) return false;
  final payerName = presenter.accountName(result.accountId) ?? 'your account';
  AppToast.success(
    context,
    !result.recordInLedger
        ? 'Marked "${bill.name}" paid.'
        : 'Paid ${formatPeso(result.amount)} for "${bill.name}" from $payerName.',
  );
  return true;
}

Future<void> _undoBillPaid(
  BuildContext context,
  BillsReceivablesPresenter presenter,
  Bill bill,
) async {
  final choice = await showWebUndoSettlementDialog(
    context,
    title: 'Undo payment?',
    name: bill.name,
    entryLabel: 'bill',
    hasLedgerEntry: presenter.billHasLedgerEntry(bill),
    ledgerEffect: '${formatPeso(bill.paidAmount ?? bill.amount)} goes back '
        'into ${presenter.accountName(bill.accountId) ?? 'your account'}.',
  );
  if (choice == null) return;
  await presenter.markBillUnpaid(
    bill.id,
    removeTransaction: choice.removeTransaction,
  );
  if (!context.mounted) return;
  AppToast.show(context, 'Marked "${bill.name}" unpaid.');
}

Future<void> _deleteBill(
  BuildContext context,
  BillsReceivablesPresenter presenter,
  Bill bill,
) async {
  // A recurring bill is asked about by series, so the months generated ahead
  // aren't silently orphaned when this one goes.
  final scope = await confirmWebRecurringDelete(
    context,
    noun: 'bill',
    name: bill.name,
    month: bill.month,
    futureMonthCount: presenter.futureSeriesBills(bill).length,
    isRecurring: bill.isRecurring,
  );
  if (scope == null) return;
  await presenter.deleteBill(
    bill.id,
    applyToFuture: scope == RecurringScope.thisAndFuture,
  );
  if (!context.mounted) return;
  AppToast.show(context, 'Deleted "${bill.name}".');
}

Future<bool> _markReceived(
  BuildContext context,
  BillsReceivablesPresenter presenter,
  Receivable receivable,
) async {
  final result = await showWebSettleDialog(
    context,
    kind: SettleKind.receivable,
    targets: [
      SettleTarget(
        id: receivable.id,
        name: receivable.name,
        amount: receivable.amount,
        dateLabel: receivable.expectedDate == null
            ? 'ASAP'
            : 'expected ${_shortDate.format(receivable.expectedDate!)}',
      ),
    ],
    accounts: presenter.depositAccountsFor(receivable),
    initialAccountId: presenter.preferredDepositAccountId(receivable),
    emptyAccountsMessage: 'Add an account before marking received.',
    onSubmit: (r) => presenter.markReceivableReceived(
      receivable.id,
      receivedAmount: r.amount,
      accountId: r.accountId,
      receivedDate: r.date,
      recordInLedger: r.recordInLedger,
    ),
  );
  if (result == null || !context.mounted) return false;
  final accountName = presenter.accountName(result.accountId) ?? 'your account';
  AppToast.success(
    context,
    !result.recordInLedger
        ? 'Marked "${receivable.name}" received.'
        : 'Received ${formatPeso(result.amount)} for "${receivable.name}" into $accountName.',
  );
  return true;
}

Future<void> _undoReceived(
  BuildContext context,
  BillsReceivablesPresenter presenter,
  Receivable receivable,
) async {
  final choice = await showWebUndoSettlementDialog(
    context,
    title: 'Undo receipt?',
    name: receivable.name,
    entryLabel: 'receivable',
    hasLedgerEntry: presenter.receivableHasLedgerEntry(receivable),
    ledgerEffect:
        '${formatPeso(receivable.receivedAmount ?? receivable.amount)} is '
        'taken back out of the account it was deposited into.',
  );
  if (choice == null) return;
  await presenter.markReceivableUnreceived(
    receivable.id,
    removeTransaction: choice.removeTransaction,
  );
  if (!context.mounted) return;
  AppToast.show(context, 'Marked "${receivable.name}" not received.');
}

Future<void> _deleteReceivable(
  BuildContext context,
  BillsReceivablesPresenter presenter,
  Receivable receivable,
) async {
  final scope = await confirmWebRecurringDelete(
    context,
    noun: 'receivable',
    name: receivable.name,
    month: receivable.month,
    futureMonthCount: presenter.futureSeriesReceivables(receivable).length,
    isRecurring: receivable.isRecurring,
  );
  if (scope == null) return;
  await presenter.deleteReceivable(
    receivable.id,
    applyToFuture: scope == RecurringScope.thisAndFuture,
  );
  if (!context.mounted) return;
  AppToast.show(context, 'Deleted "${receivable.name}".');
}

Future<bool> _fundSetAside(
  BuildContext context,
  BillsReceivablesPresenter presenter,
  BudgetedExpense expense,
) async {
  // Setting money aside is a transfer between your own accounts: it leaves
  // the funding source and lands in a savings/goal destination (or is spent,
  // for a one-off plan).
  final payers = presenter.setAsideFundingAccounts;
  if (payers.isEmpty) {
    AppToast.error(context, 'Add an account before funding.');
    return false;
  }
  final fromId = payers.any((a) => a.id == expense.accountId)
      ? expense.accountId
      : payers.first.id;
  // With no destination on file the field starts empty and Fund waits for an
  // answer, rather than auto-picking a savings account the user never named.
  final toId =
      presenter.preferredSetAsideDestinationId(expense, fromAccountId: fromId);
  final result = await showWebSettleDialog(
    context,
    kind: SettleKind.setAside,
    targets: [
      SettleTarget(
        id: expense.id,
        name: expense.name,
        amount: expense.allocatedAmount,
        accountId: fromId,
        destinationId: toId,
      ),
    ],
    accounts: payers,
    initialAccountId: fromId,
    destinations: presenter.setAsideDestinationAccounts,
    onSubmit: (r) => presenter.markExpensePaid(
      expense.id,
      paidAmount: r.amount,
      accountId: r.accountId!,
      toAccountId: r.destinationId,
      paidDate: r.date,
    ),
  );
  if (result == null || !context.mounted) return false;
  final fromName = presenter.accountName(result.accountId) ?? 'your account';
  final toName = presenter.accountName(result.destinationId);
  AppToast.success(
    context,
    toName != null
        ? 'Transferred ${formatPeso(result.amount)} for "${expense.name}" from $fromName to $toName.'
        : 'Set aside ${formatPeso(result.amount)} for "${expense.name}" from $fromName.',
  );
  return true;
}

Future<void> _undoFunded(
  BuildContext context,
  BillsReceivablesPresenter presenter,
  BudgetedExpense expense,
) async {
  final choice = await showWebUndoSettlementDialog(
    context,
    title: 'Undo funding?',
    name: expense.name,
    entryLabel: 'set-aside',
    hasLedgerEntry: presenter.expenseHasLedgerEntry(expense),
    ledgerEffect: '${formatPeso(expense.spentAmount)} is moved back to the '
        'account it was funded from.',
  );
  if (choice == null) return;
  await presenter.markExpenseUnpaid(
    expense.id,
    removeTransaction: choice.removeTransaction,
  );
  if (!context.mounted) return;
  AppToast.show(context, 'Marked "${expense.name}" unfunded.');
}

Future<void> _deleteSetAside(
  BuildContext context,
  BillsReceivablesPresenter presenter,
  BudgetedExpense expense,
) async {
  final scope = await confirmWebRecurringDelete(
    context,
    noun: 'set-aside',
    name: expense.name,
    month: expense.month,
    futureMonthCount: presenter.futureSeriesExpenses(expense).length,
    isRecurring: expense.isRecurring,
  );
  if (scope == null) return;
  await presenter.deleteBudgetedExpense(
    expense.id,
    applyToFuture: scope == RecurringScope.thisAndFuture,
  );
  if (!context.mounted) return;
  AppToast.show(context, 'Deleted "${expense.name}".');
}

Future<bool> _payInstallment(
  BuildContext context,
  InstallmentPresenter presenter,
  Installment installment,
) async {
  // No account picker: an installment is always charged to its linked card.
  final result = await showWebSettleDialog(
    context,
    kind: SettleKind.installment,
    targets: [
      SettleTarget(
        id: installment.id,
        name: installment.name,
        amount: installment.monthlyAmount,
      ),
    ],
    accounts: const [],
    onSubmit: (r) => presenter.markPaid(
      installment.id,
      overrideAmount: r.amount,
      date: r.date,
    ),
  );
  if (result == null || !context.mounted) return false;
  AppToast.success(
    context,
    'Recorded ${formatPeso(result.amount)} for "${installment.name}".',
  );
  return true;
}

Future<void> _undoInstallment(
  BuildContext context,
  InstallmentPresenter presenter,
  Installment installment,
) async {
  // An installment has no paid flag of its own — the transaction IS the
  // record — so undoing always removes it; the dialog confirms rather than
  // offering a keep-the-transaction choice.
  final choice = await showWebUndoSettlementDialog(
    context,
    title: 'Undo payment?',
    name: installment.name,
    entryLabel: 'installment payment',
    hasLedgerEntry: false,
    ledgerEffect: "This month's payment transaction is removed and "
        '${presenter.accountName(installment.accountId) ?? 'the account'} '
        'is credited back.',
  );
  if (choice == null) return;
  await presenter.markUnpaid(installment.id);
  if (!context.mounted) return;
  AppToast.show(context, 'Marked "${installment.name}" unpaid this month.');
}

Future<void> _deleteInstallment(
  BuildContext context,
  InstallmentPresenter presenter,
  Installment installment,
) async {
  final confirmed = await showWebConfirm(
    context,
    title: 'Delete ${installment.name}?',
    message: 'All linked payment transactions will also be removed. This '
        'cannot be undone.',
  );
  if (!confirmed) return;
  await presenter.deleteInstallment(installment.id);
  if (!context.mounted) return;
  AppToast.show(context, 'Deleted "${installment.name}".');
}

// ─── Header: Add ▾ ────────────────────────────────────────────────────────────

/// One Add ▾ menu in place of five Add buttons: Bill · Receivable · Set-aside
/// · Installment, each opening its form.
class _AddMenuButton extends StatelessWidget {
  final ValueChanged<_AddKind> onPick;

  const _AddMenuButton({required this.onPick});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    PopupMenuItem<_AddKind> item(_AddKind kind, String label, Key key) =>
        PopupMenuItem<_AddKind>(
          key: key,
          value: kind,
          height: 40,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
    return PopupMenuButton<_AddKind>(
      key: WebKeys.billsAddMenu,
      tooltip: 'Add',
      position: PopupMenuPosition.under,
      color: cs.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outline),
      ),
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      onSelected: onPick,
      itemBuilder: (_) => [
        item(_AddKind.bill, 'Bill', WebKeys.billsAddBill),
        item(_AddKind.receivable, 'Receivable', WebKeys.billsAddReceivable),
        item(_AddKind.setAside, 'Set-aside', WebKeys.billsAddSetAside),
        item(_AddKind.installment, 'Installment', WebKeys.billsAddInstallment),
      ],
      child: Container(
        height: kWebHitTarget,
        padding: const EdgeInsets.only(left: 14, right: 10),
        decoration: BoxDecoration(
          color: cs.primary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 18, color: cs.onPrimary),
            const SizedBox(width: 6),
            Text(
              'Add',
              style: theme.textTheme.labelLarge?.copyWith(
                color: cs.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded, size: 18, color: cs.onPrimary),
          ],
        ),
      ),
    );
  }
}

// ─── Due-soon hero ────────────────────────────────────────────────────────────

/// The first unpaid bill due within a week, on the bills gradient: eyebrow,
/// name, meta, amount, Mark paid, Edit and the reminder bell. Overdue is said
/// in words and an icon, still in the bills tone — red is kept for errors.
class _DueSoonHeroV2 extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final Bill bill;
  final VoidCallback onMarkPaid;
  final VoidCallback onEdit;
  final VoidCallback onToggleReminder;

  const _DueSoonHeroV2({
    required this.presenter,
    required this.bill,
    required this.onMarkPaid,
    required this.onEdit,
    required this.onToggleReminder,
  });

  String get _meta {
    final category = presenter.categoryById(bill.categoryId)?.name;
    final account = presenter.accountName(bill.accountId);
    return [
      if (category != null && category.isNotEmpty) category,
      'due ${_shortDate.format(presenter.billDueDate(bill))}',
      if (account != null) 'pay from $account',
      if (bill.isRecurring)
        recurrenceLabel(bill.recurrenceType ?? RecurrenceType.monthly)
            .toLowerCase(),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final due = presenter.billDueInfo(bill);
    // Overdue is said in words (and an icon), still in the bills tone — the
    // error red is kept for errors and destructive actions.
    final accent = context.appColors.bills;
    final reminderOn = bill.reminderDaysBefore != null;

    return KeyedSubtree(
      key: WebKeys.billsHero,
      child: WebHeroCard(
        accent: accent,
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  due.overdue
                      ? Icons.error_outline_rounded
                      : Icons.schedule_rounded,
                  size: 15,
                  color: accent,
                ),
                const SizedBox(width: 6),
                Text(
                  due.label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontSize: 11,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bill.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: cs.onSurface,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.appColors.textMuted,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: WebInsets.lg),
                Text(
                  formatPeso(bill.amount),
                  style: webNumericStyle(
                    theme.textTheme.headlineMedium?.copyWith(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: WebInsets.lg),
            Row(
              children: [
                FilledButton.icon(
                  key: WebKeys.billsHeroMarkPaid,
                  onPressed: onMarkPaid,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: cs.surface,
                    minimumSize: const Size(0, kWebHitTarget),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Mark paid'),
                ),
                const SizedBox(width: WebInsets.sm),
                OutlinedButton.icon(
                  key: WebKeys.billsHeroEdit,
                  onPressed: onEdit,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.onSurface,
                    side: BorderSide(color: accent.withValues(alpha: 0.45)),
                    minimumSize: const Size(0, kWebHitTarget),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit'),
                ),
                const SizedBox(width: WebInsets.sm),
                IconButton(
                  key: WebKeys.billsHeroReminder,
                  onPressed: onToggleReminder,
                  tooltip: reminderOn
                      ? 'Reminder on · ${bill.reminderDaysBefore} '
                          '${bill.reminderDaysBefore == 1 ? 'day' : 'days'} '
                          'before · click to turn off'
                      : 'Remind me before it is due',
                  style: IconButton.styleFrom(
                    foregroundColor: reminderOn ? accent : cs.onSurfaceVariant,
                    backgroundColor: accent.withValues(alpha: 0.12),
                    minimumSize: const Size(kWebHitTarget, kWebHitTarget),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: Icon(
                    reminderOn
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_none_rounded,
                    size: 18,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── List rows ────────────────────────────────────────────────────────────────

/// The compact primary action at the end of a row — "Mark paid", "Pay",
/// "Receive", "Fund" — in the kind's tone. 40 px tall with a padded tap
/// target, so the hit area meets the 44 px rule.
class _RowAction extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _RowAction({
    super.key,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.45)),
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        tapTargetSize: MaterialTapTargetSize.padded,
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label),
    );
  }
}

/// A row's figure, right-aligned: tabular, 15/800, muted when settled.
Widget _amountText(BuildContext context, String text,
    {required Color color, bool strike = false}) {
  final theme = Theme.of(context);
  return Text(
    text,
    style: webNumericStyle(
      theme.textTheme.bodyLarge?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        decoration: strike ? TextDecoration.lineThrough : null,
      ),
      color: color,
    ),
  );
}

class _BillRowV2 extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final Bill bill;
  final bool divider;

  /// Non-null while the bills section is selecting: the row shows a selection
  /// box and hides its actions, so a click can only mean "pick this row".
  final WebRowSelection? selection;

  const _BillRowV2({
    required this.presenter,
    required this.bill,
    required this.divider,
    this.selection,
  });

  Widget _badge(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final warning = context.appColors.bills;
    final statement = presenter.statementCard(bill);
    if (bill.isPaid) {
      final when = bill.paidDate;
      return WebBadge(
        when == null ? 'Paid' : 'Paid ${_shortDate.format(when)}',
        tone: WebBadgeTone.success,
      );
    }
    if (statement != null) {
      return const WebBadge('Statement', tone: WebBadgeTone.info);
    }
    final due = presenter.billDueInfo(bill);
    if (due.overdue) {
      return WebBadge(
        'Overdue · ${_shortDate.format(presenter.billDueDate(bill))}',
        tone: WebBadgeTone.warning,
        icon: Icons.error_outline_rounded,
      );
    }
    return Builder(
      builder: (_) => DefaultTextStyle.merge(
        style: TextStyle(color: due.imminent ? warning : cs.onSurfaceVariant),
        child: WebBadge(
          'Due ${_shortDate.format(presenter.billDueDate(bill))}',
          tone: due.imminent ? WebBadgeTone.warning : WebBadgeTone.neutral,
        ),
      ),
    );
  }

  /// The row's leading category badge, resolved exactly as the mobile Bills
  /// tab resolves it; the bills accent is the fallback for an uncategorised
  /// bill. A credit statement leads with its card instead.
  Widget _tile(BuildContext context) {
    final statement = presenter.statementCard(bill);
    if (statement != null) {
      return AccountBadge(
        category: statement.account.category,
        name: statement.account.name,
        iconKey: statement.account.icon,
        colorHex: statement.account.colorHex,
        size: 36,
      );
    }
    final category = presenter.categoryById(bill.categoryId);
    final color = category != null
        ? resolveSliceColor(
            category.colorHex,
            presenter.categoryPaletteSlot(bill.categoryId),
            brightness: Theme.of(context).brightness,
          )
        : context.appColors.bills;
    return CategoryBadge(
      iconKey: category?.icon,
      name: category?.name,
      type: category?.type ?? CategoryType.expense,
      color: color,
      size: 36,
      iconSize: 17,
    );
  }

  String _subtitle() {
    final statement = presenter.statementCard(bill);
    final progressNote = presenter.statementProgressNote(bill);
    if (statement != null) {
      return [
        statement.periodLabel,
        statement.dueLabel,
        if (statement.compositionLabel != null) statement.compositionLabel!,
        if (progressNote != null) progressNote,
      ].join(' · ');
    }
    final category = presenter.categoryById(bill.categoryId)?.name;
    final account = presenter.accountName(bill.accountId);
    final reminder = bill.reminderDaysBefore;
    return [
      if (category != null && category.isNotEmpty) category,
      if (account != null) account,
      'due ${ordinalDay(bill.dueDay)}',
      if (bill.isRecurring)
        recurrenceLabel(bill.recurrenceType ?? RecurrenceType.monthly)
            .toLowerCase(),
      if (reminder != null)
        'reminder $reminder ${reminder == 1 ? 'day' : 'days'} before',
      if (progressNote != null) progressNote,
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final paid = bill.isPaid;
    final statement = presenter.statementCard(bill);
    final selecting = selection != null;
    final amountColor = paid ? cs.onSurfaceVariant : cs.onSurface;

    final Widget trailing;
    if (statement != null) {
      trailing = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          _amountText(context, formatPeso(statement.headlineAmount),
              color: amountColor),
          Text(
            [
              statement.headlineCaption,
              if (statement.minimumLabel != null) statement.minimumLabel!,
            ].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ],
      );
    } else {
      trailing = _amountText(context, formatPeso(bill.amount),
          color: amountColor, strike: paid);
    }

    return WebListRow(
      leading: selecting
          ? WebRowSelectBox(
              selected: selection!.selected,
              onTap: selection!.onToggle,
            )
          : _tile(context),
      title:
          statement != null ? '${statement.account.name} statement' : bill.name,
      badge: _badge(context),
      subtitle: _subtitle(),
      trailing: trailing,
      selected: selecting && selection!.selected,
      onTap: selecting ? selection!.onToggle : null,
      divider: divider,
      actions: selecting
          ? const []
          : [
              if (statement != null) ...[
                TextButton.icon(
                  key: WebKeys.billsRowStatementItems,
                  onPressed: () => showWebStatementBreakdownDialog(
                    context,
                    presenter: presenter,
                    bill: bill,
                    onPayNow: () => _markBillPaid(context, presenter, bill),
                  ),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, kWebHitTarget),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  icon: const Icon(Icons.receipt_long_outlined, size: 16),
                  label: Text(statement.itemsLabel),
                ),
                const SizedBox(width: WebInsets.xs),
              ],
              if (!paid) ...[
                _RowAction(
                  key: WebKeys.billsRowSettle,
                  label: 'Mark paid',
                  color: context.appColors.bills,
                  onPressed: () => _markBillPaid(context, presenter, bill),
                ),
                const SizedBox(width: WebInsets.xs),
              ],
              WebRowMenu(
                key: WebKeys.billsRowMenu,
                items: [
                  if (presenter.hasUndoablePayment(bill))
                    WebMenuItem(
                      'Mark unpaid',
                      key: WebKeys.billsRowMarkUnpaid,
                      icon: Icons.undo_rounded,
                      onTap: () => _undoBillPaid(context, presenter, bill),
                    ),
                  WebMenuItem(
                    'Edit',
                    key: WebKeys.billsRowEdit,
                    icon: Icons.edit_outlined,
                    onTap: () => showWebBillDialog(context,
                        presenter: presenter, existing: bill),
                  ),
                  WebMenuItem(
                    'Delete',
                    key: WebKeys.billsRowDelete,
                    icon: Icons.delete_outline_rounded,
                    destructive: true,
                    onTap: () => _deleteBill(context, presenter, bill),
                  ),
                ],
              ),
            ],
    );
  }
}

class _SetAsideRowV2 extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final BudgetedExpense expense;
  final bool divider;
  final WebRowSelection? selection;

  const _SetAsideRowV2({
    required this.presenter,
    required this.expense,
    required this.divider,
    this.selection,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final funded = expense.isPaid;
    final selecting = selection != null;
    final from = presenter.accountName(expense.accountId);
    final into = presenter.accountName(expense.destinationAccountId);
    final note = expense.note?.trim();
    final subtitle = [
      expense.budgetedType.label,
      if (note != null && note.isNotEmpty) note,
      if (from != null) 'from $from',
      if (into != null) 'into $into',
    ].join(' · ');

    return WebListRow(
      leading: selecting
          ? WebRowSelectBox(
              selected: selection!.selected,
              onTap: selection!.onToggle,
            )
          : WebRowTile(
              color: context.appColors.gold,
              child: const Icon(Icons.savings_outlined),
            ),
      title: expense.name,
      badge:
          funded ? const WebBadge('Funded', tone: WebBadgeTone.success) : null,
      subtitle: subtitle,
      trailing: _amountText(
        context,
        formatPeso(expense.allocatedAmount),
        color: funded ? cs.onSurfaceVariant : context.appColors.bills,
        strike: funded,
      ),
      selected: selecting && selection!.selected,
      onTap: selecting ? selection!.onToggle : null,
      divider: divider,
      actions: selecting
          ? const []
          : [
              if (!funded) ...[
                _RowAction(
                  key: WebKeys.billsRowSettle,
                  label: 'Fund',
                  color: cs.primary,
                  onPressed: () => _fundSetAside(context, presenter, expense),
                ),
                const SizedBox(width: WebInsets.xs),
              ],
              WebRowMenu(
                key: WebKeys.billsRowMenu,
                items: [
                  if (funded)
                    WebMenuItem(
                      'Mark unfunded',
                      key: WebKeys.billsRowMarkUnpaid,
                      icon: Icons.undo_rounded,
                      onTap: () => _undoFunded(context, presenter, expense),
                    ),
                  WebMenuItem(
                    'Edit',
                    key: WebKeys.billsRowEdit,
                    icon: Icons.edit_outlined,
                    onTap: () => showWebSetAsideDialog(context,
                        presenter: presenter, existing: expense),
                  ),
                  WebMenuItem(
                    'Delete',
                    key: WebKeys.billsRowDelete,
                    icon: Icons.delete_outline_rounded,
                    destructive: true,
                    onTap: () => _deleteSetAside(context, presenter, expense),
                  ),
                ],
              ),
            ],
    );
  }
}

class _ReceivableRowV2 extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final Receivable receivable;
  final bool divider;
  final WebRowSelection? selection;

  const _ReceivableRowV2({
    required this.presenter,
    required this.receivable,
    required this.divider,
    this.selection,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final received = receivable.isReceived;
    final selecting = selection != null;
    final into = presenter.accountName(receivable.accountId);
    final expected = receivable.expectedDate;

    return WebListRow(
      leading: selecting
          ? WebRowSelectBox(
              selected: selection!.selected,
              onTap: selection!.onToggle,
            )
          : WebRowTile(
              color: context.appColors.success,
              child: const Icon(Icons.south_west_rounded),
            ),
      title: receivable.name,
      badge: received
          ? const WebBadge('Received', tone: WebBadgeTone.success)
          : WebBadge(
              expected == null ? 'ASAP' : 'Due ${_shortDate.format(expected)}',
            ),
      subtitle: [
        receivableTypeLabel(receivable.receivableType),
        if (into != null) 'into $into',
      ].join(' · '),
      trailing: _amountText(
        context,
        '+${formatPeso(receivable.amount)}',
        color: received ? cs.onSurfaceVariant : cs.tertiary,
        strike: received,
      ),
      selected: selecting && selection!.selected,
      onTap: selecting ? selection!.onToggle : null,
      divider: divider,
      actions: selecting
          ? const []
          : [
              if (!received) ...[
                _RowAction(
                  key: WebKeys.billsRowSettle,
                  label: 'Receive',
                  color: cs.tertiary,
                  onPressed: () =>
                      _markReceived(context, presenter, receivable),
                ),
                const SizedBox(width: WebInsets.xs),
              ],
              WebRowMenu(
                key: WebKeys.billsRowMenu,
                items: [
                  if (received)
                    WebMenuItem(
                      'Mark not received',
                      key: WebKeys.billsRowMarkUnpaid,
                      icon: Icons.undo_rounded,
                      onTap: () =>
                          _undoReceived(context, presenter, receivable),
                    ),
                  WebMenuItem(
                    'Edit',
                    key: WebKeys.billsRowEdit,
                    icon: Icons.edit_outlined,
                    onTap: () => showWebReceivableDialog(context,
                        presenter: presenter, existing: receivable),
                  ),
                  WebMenuItem(
                    'Delete',
                    key: WebKeys.billsRowDelete,
                    icon: Icons.delete_outline_rounded,
                    destructive: true,
                    onTap: () =>
                        _deleteReceivable(context, presenter, receivable),
                  ),
                ],
              ),
            ],
    );
  }
}

class _InstallmentRowV2 extends StatelessWidget {
  final InstallmentPresenter presenter;

  /// Resolves a plan's month against the statement it is billed on.
  final BillsReceivablesPresenter bills;
  final Installment installment;
  final bool divider;
  final WebRowSelection? selection;

  const _InstallmentRowV2({
    required this.presenter,
    required this.bills,
    required this.installment,
    required this.divider,
    this.selection,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final warning = context.appColors.bills;
    final selecting = selection != null;
    // On a card with statements a month is paid by paying its statement, so
    // the row follows that statement instead of calling a billed month paid.
    final onStatement = bills.installmentStatementStatus(installment);
    final statementBill = onStatement?.statement;
    final paid = onStatement?.paid ?? presenter.isPaidForMonth(installment.id);
    final canPay = presenter.canMarkPaid(installment);
    final canUndo = presenter.canMarkUnpaid(installment);
    final count = presenter.paidCount(installment.id);
    final progress =
        onStatement?.progress ?? presenter.paymentProgress(installment.id);
    final detail = [
      if (onStatement != null) onStatement.label,
      if (onStatement != null) onStatement.note,
      presenter.detailLine(installment, withRemaining: true) ?? '',
    ].where((s) => s.isNotEmpty).join(' · ');

    return WebListRow(
      leading: selecting
          ? WebRowSelectBox(
              selected: selection!.selected,
              onTap: selection!.onToggle,
            )
          : WebRowTile(
              color: context.appColors.purple,
              child: const Icon(Icons.credit_card_rounded),
            ),
      title: installment.name,
      badge: WebBadge(
        '$count/${installment.totalMonths}',
        tone: paid ? WebBadgeTone.success : WebBadgeTone.warning,
      ),
      subtitle: detail,
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          _amountText(
            context,
            '${formatPeso(installment.monthlyAmount)}/mo',
            color: paid ? cs.onSurfaceVariant : cs.onSurface,
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 96,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: cs.surfaceContainerHighest,
                color: warning,
              ),
            ),
          ),
        ],
      ),
      selected: selecting && selection!.selected,
      onTap: selecting ? selection!.onToggle : null,
      divider: divider,
      actions: selecting
          ? const []
          : [
              if (statementBill != null && onStatement?.linkLabel != null) ...[
                TextButton.icon(
                  key: WebKeys.billsRowStatementItems,
                  onPressed: () => showWebStatementBreakdownDialog(
                    context,
                    presenter: bills,
                    bill: statementBill,
                    onPayNow: () =>
                        _markBillPaid(context, bills, statementBill),
                  ),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, kWebHitTarget),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  icon: const Icon(Icons.receipt_long_outlined, size: 16),
                  label: Text(onStatement!.linkLabel!),
                ),
                const SizedBox(width: WebInsets.xs),
              ],
              if (canPay) ...[
                _RowAction(
                  key: WebKeys.billsRowSettle,
                  label: 'Pay',
                  color: warning,
                  onPressed: () =>
                      _payInstallment(context, presenter, installment),
                ),
                const SizedBox(width: WebInsets.xs),
              ],
              WebRowMenu(
                key: WebKeys.billsRowMenu,
                items: [
                  if (canUndo)
                    WebMenuItem(
                      'Mark unpaid this month',
                      key: WebKeys.billsRowMarkUnpaid,
                      icon: Icons.undo_rounded,
                      onTap: () =>
                          _undoInstallment(context, presenter, installment),
                    ),
                  WebMenuItem(
                    'Edit',
                    key: WebKeys.billsRowEdit,
                    icon: Icons.edit_outlined,
                    onTap: () => showWebInstallmentDialog(context,
                        presenter: presenter, existing: installment),
                  ),
                  WebMenuItem(
                    'Delete',
                    key: WebKeys.billsRowDelete,
                    icon: Icons.delete_outline_rounded,
                    destructive: true,
                    onTap: () =>
                        _deleteInstallment(context, presenter, installment),
                  ),
                ],
              ),
            ],
    );
  }
}

/// "DUE SOON" / "LATER THIS MONTH" — a small uppercase label between the two
/// groups of the Upcoming tab.
class _GroupLabel extends StatelessWidget {
  final String label;

  const _GroupLabel(this.label);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        WebInsets.lg,
        WebInsets.md,
        WebInsets.lg,
        WebInsets.xs,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: cs.onSurfaceVariant,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.74,
        ),
      ),
    );
  }
}

/// The list card's footer: an uppercase label at the left (with an optional
/// muted hint beside it) and the total at the right in its tone.
class _ListFooter extends StatelessWidget {
  final String label;
  final String value;
  final Color tone;
  final String? hint;

  const _ListFooter({
    required this.label,
    required this.value,
    required this.tone,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WebInsets.lg,
        vertical: WebInsets.md,
      ),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor.withValues(alpha: 0.35),
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.74,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(width: WebInsets.md),
            Expanded(
              child: Text(
                hint!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.appColors.textMuted,
                  fontSize: 11.5,
                ),
              ),
            ),
          ] else
            const Spacer(),
          const SizedBox(width: WebInsets.md),
          Text(
            value,
            style: webNumericStyle(
              theme.textTheme.bodyLarge?.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
              color: tone,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String message;

  const _EmptyHint(this.message);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: WebInsets.xl,
        horizontal: WebInsets.lg,
      ),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ─── Credit cards & lines ─────────────────────────────────────────────────────

/// Every credit card, credit line and BNPL account with a balance: what is
/// owed, how much of the limit is used, the statement and due days, and Pay
/// now. Lines with no balance are named in one muted sentence.
class _CreditLinesCard extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final ValueChanged<FinancialAccount> onPay;

  const _CreditLinesCard({required this.presenter, required this.onPay});

  List<FinancialAccount> get _cards => presenter.creditAccounts;
  List<FinancialAccount> get _withBalance =>
      _cards.where((c) => c.currentPayable > 0).toList();
  List<FinancialAccount> get _clear =>
      _cards.where((c) => c.currentPayable <= 0).toList();

  double get _available => _cards.fold(
      0.0, (s, c) => s + (c.availableCredit ?? 0).clamp(0, double.infinity));

  String get _description {
    final owed = presenter.totalCreditOwed(_cards);
    if (owed <= 0) return 'No outstanding balance';
    return 'Owe ${formatPeso(owed)} across ${_withBalance.length} of '
        '${_cards.length} ${_plural(_cards.length, 'line')} · '
        '${formatPeso(_available)} available · pay anytime';
  }

  String _subtitle(FinancialAccount card) {
    final limit = card.creditLimit;
    final parts = <String>[];
    if (limit == null) {
      parts.add('No credit limit set');
    } else {
      final u = card.utilization ?? 0;
      if (u >= 0.5) parts.add('${(u * 100).round()} % used');
      parts.add('${formatPeso((card.availableCredit ?? 0).clamp(0, limit))} '
          'of ${formatPeso(limit)} available');
    }
    if (card.statementDay != null) {
      parts.add('statement ${ordinalDay(card.statementDay!)}');
    }
    if (card.paymentDueDay != null) {
      parts.add('due ${ordinalDay(card.paymentDueDay!)}');
    } else if (card.dueDaysAfterStatement != null) {
      parts.add('due ${card.dueDaysAfterStatement} days after');
    }
    return parts.join(' · ');
  }

  String get _clearLine {
    final names = [
      for (final c in _clear)
        c.creditLimit != null
            ? '${c.name} (${formatPeso(c.creditLimit!)})'
            : c.name,
    ];
    final String list;
    if (names.length == 1) {
      list = names.single;
    } else if (names.length == 2) {
      list = '${names[0]} and ${names[1]}';
    } else {
      list = '${names.sublist(0, names.length - 1).join(', ')} and '
          '${names.last}';
    }
    return names.length == 1
        ? '$list has no balance.'
        : '$list have no balance.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final warning = context.appColors.bills;
    final withBalance = _withBalance;

    return WebCard(
      key: WebKeys.billsCreditCards,
      title: 'Credit cards & lines',
      description: _description,
      padding: const EdgeInsets.fromLTRB(
        WebInsets.xl,
        WebInsets.xl,
        WebInsets.xl,
        WebInsets.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (withBalance.isEmpty)
            Padding(
              key: WebKeys.billsCreditCardsEmpty,
              padding: const EdgeInsets.only(bottom: WebInsets.sm),
              child: Text(
                'Nothing owed on any line right now.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ),
          for (var i = 0; i < withBalance.length; i++)
            Builder(
              builder: (context) {
                final card = withBalance[i];
                final u = (card.utilization ?? 0).clamp(0.0, 1.0);
                return WebListRow(
                  leading: AccountBadge(
                    category: card.category,
                    name: card.name,
                    iconKey: card.icon,
                    colorHex: card.colorHex,
                    size: 36,
                  ),
                  title: card.name,
                  badge: card.category == AccountCategory.creditCard
                      ? null
                      : WebBadge(card.category.label),
                  subtitle: _subtitle(card),
                  divider: i < withBalance.length - 1,
                  trailing: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _amountText(
                        context,
                        formatPeso(card.currentPayable),
                        color: cs.error,
                      ),
                      if (card.creditLimit != null) ...[
                        const SizedBox(height: 6),
                        SizedBox(
                          width: 110,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: u,
                              minHeight: 4,
                              backgroundColor: cs.surfaceContainerHighest,
                              color: u >= 0.5 ? warning : cs.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  actions: [
                    _RowAction(
                      key: WebKeys.billsPayCard,
                      label: 'Pay now',
                      color: warning,
                      onPressed: () => onPay(card),
                    ),
                  ],
                );
              },
            ),
          if (_clear.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: WebInsets.md),
              child: Text(
                _clearLine,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.appColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Side column ──────────────────────────────────────────────────────────────

/// A label + muted subline at the left, a figure at the right.
class _KvRow extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final Color? tone;
  final bool divider;

  const _KvRow({
    required this.label,
    required this.value,
    this.sub,
    this.tone,
    this.divider = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: divider
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: cs.outlineVariant)),
            )
          : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (sub != null)
                  Text(
                    sub!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.appColors.textMuted,
                      fontSize: 11.5,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: WebInsets.md),
          Text(
            value,
            style: webNumericStyle(
              theme.textTheme.bodyLarge?.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
              color: tone ?? cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// "This month": the six figures the old stat strip carried, as one
/// statement — due, paid, total, to receive, set-asides to fund, installments.
class _ThisMonthCard extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final InstallmentPresenter installmentPresenter;
  final int unpaidCount;
  final int paidCount;
  final double setAsideTotal;
  final int setAsideCount;

  const _ThisMonthCard({
    required this.presenter,
    required this.installmentPresenter,
    required this.unpaidCount,
    required this.paidCount,
    required this.setAsideTotal,
    required this.setAsideCount,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final warning = context.appColors.bills;
    final due = presenter.totalBillsPending;
    final pending = presenter.pendingReceivables;
    final receivedCount = presenter.receivedReceivables.length;
    final plansDue = installmentPresenter.dueThisMonth.length;
    final plansAll =
        installmentPresenter.allInstallments.where((i) => i.isActive).length;

    return WebCard(
      key: WebKeys.billsThisMonth,
      title: 'This month',
      description: 'Bills, receivables, set-asides and installments',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _KvRow(
            label: 'Due this month',
            value: formatPeso(due),
            sub: '$unpaidCount unpaid',
            tone: due > 0 ? warning : null,
          ),
          _KvRow(
            label: 'Paid',
            value: formatPeso(presenter.totalBillsPaid),
            sub: '$paidCount settled',
            tone: cs.tertiary,
          ),
          _KvRow(
            label: 'Total this month',
            value: formatPeso(presenter.totalBillsAmount),
            sub: '${unpaidCount + paidCount} '
                '${_plural(unpaidCount + paidCount, 'bill')}',
          ),
          _KvRow(
            label: 'To receive',
            value: '+${formatPeso(presenter.totalReceivablesPending)}',
            sub: [
              '${pending.length} pending',
              if (receivedCount > 0) '$receivedCount received',
            ].join(' · '),
            tone: cs.tertiary,
          ),
          _KvRow(
            label: 'Set-asides to fund',
            value: formatPeso(setAsideTotal),
            sub: '$setAsideCount ${_plural(setAsideCount, 'fund')}',
            tone: setAsideTotal > 0 ? warning : null,
          ),
          _KvRow(
            label: 'Installments',
            value: formatPeso(installmentPresenter.monthlyInstallmentLoad),
            sub:
                '$plansDue of $plansAll ${_plural(plansAll, 'plan')} this month',
            divider: false,
          ),
        ],
      ),
    );
  }
}

/// "By account": how much still needs to land in each funding account to
/// cover the unpaid bills and unfunded set-asides. Reads the pre-aggregated
/// rows from [BillsReceivablesPresenter.fundingBreakdown]; no math here.
class _ByAccountCard extends StatelessWidget {
  final List<
      ({
        FinancialAccount? account,
        double billsDue,
        double setAsides,
        double total,
        int count,
      })> rows;

  const _ByAccountCard({required this.rows});

  double get _grandTotal => rows.fold(0.0, (s, r) => s + r.total);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return WebCard(
      key: WebKeys.billsByAccount,
      title: 'By account',
      description: 'How much to move into each account to cover what is due',
      padding: const EdgeInsets.fromLTRB(
        WebInsets.xl,
        WebInsets.xl,
        WebInsets.xl,
        WebInsets.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++)
            Builder(builder: (context) {
              final row = rows[i];
              final account = row.account;
              final detail = [
                '${row.count} ${_plural(row.count, 'item')}',
                if (row.billsDue > 0) '${formatPeso(row.billsDue)} bills',
                if (row.setAsides > 0)
                  '${formatPeso(row.setAsides)} set-asides',
                if (account == null) 'no account set',
              ].join(' · ');
              return WebListRow(
                leading: account != null
                    ? AccountBadge(
                        category: account.category,
                        name: account.name,
                        iconKey: account.icon,
                        colorHex: account.colorHex,
                        size: 32,
                      )
                    : WebRowTile(
                        size: 32,
                        color: cs.surfaceContainerHighest,
                        child: Icon(
                          Icons.help_outline_rounded,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                title: account?.name ?? 'Unassigned',
                subtitle: detail,
                divider: i < rows.length - 1,
                trailing: _amountText(
                  context,
                  formatPeso(row.total),
                  color: account == null ? cs.onSurface : cs.primary,
                ),
              );
            }),
          Padding(
            padding: const EdgeInsets.only(top: WebInsets.md),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'TOTAL TO MOVE',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.74,
                    ),
                  ),
                ),
                const SizedBox(width: WebInsets.md),
                _amountText(context, formatPeso(_grandTotal),
                    color: cs.primary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Coming up": the next six across bills, receivables, set-asides and
/// installments, from the presenter's merged timeline. A click opens the
/// item's editor — the same destination its tab row's Edit reaches.
class _ComingUpCard extends StatelessWidget {
  final List<ComingUpItem> items;
  final ValueChanged<ComingUpItem> onTap;

  const _ComingUpCard({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = context.appColors;
    return WebCard(
      key: WebKeys.billsComingUp,
      title: 'Coming up',
      description: 'Next ${items.length} across everything',
      padding: const EdgeInsets.fromLTRB(
        WebInsets.xl,
        WebInsets.xl,
        WebInsets.xl,
        WebInsets.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++)
            Builder(builder: (context) {
              final item = items[i];
              final (Color color, IconData icon, String kind) =
                  switch (item.kind) {
                ComingUpKind.bill => (
                    c.bills,
                    Icons.receipt_long_outlined,
                    'bill'
                  ),
                ComingUpKind.receivable => (
                    c.success,
                    Icons.south_west_rounded,
                    'receivable'
                  ),
                ComingUpKind.budgeted => (
                    c.gold,
                    Icons.savings_outlined,
                    'set-aside'
                  ),
                ComingUpKind.installment => (
                    c.purple,
                    Icons.credit_card_rounded,
                    'installment'
                  ),
              };
              return WebListRow(
                leading: WebRowTile(size: 32, color: color, child: Icon(icon)),
                title: item.name,
                subtitle: '${item.dateLabel} · $kind',
                divider: i < items.length - 1,
                onTap: () => onTap(item),
                trailing: _amountText(
                  context,
                  '${item.isInflow ? '+' : ''}${formatPeso(item.amount)}',
                  color: item.isInflow ? c.success : cs.onSurface,
                ),
              );
            }),
        ],
      ),
    );
  }
}
