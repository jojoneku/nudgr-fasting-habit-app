import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../../widgets/web_widgets.dart';
import 'bills_detail_pane.dart';
import 'bills_selection.dart';
import 'bills_sheet_dialog.dart';

/// Web Bills & Receivables page (Plan 050-C).
///
/// Desktop two-pane layout: a KPI strip + month navigator on top, three
/// sheet-style tables (Bills · Receivables · Installments) on the left, and a
/// detail/edit pane on the right wired to the presenters' settle actions. Below
/// the two-pane breakpoint the detail pane stacks under the tables.
class WebBillsPage extends StatefulWidget {
  final BillsReceivablesPresenter presenter;
  final InstallmentPresenter installmentPresenter;
  const WebBillsPage({
    super.key,
    required this.presenter,
    required this.installmentPresenter,
  });

  @override
  State<WebBillsPage> createState() => _WebBillsPageState();
}

class _WebBillsPageState extends State<WebBillsPage> {
  BillsSelection? _selection;

  /// Width below which the right detail pane stacks under the tables.
  static const double _twoPaneMin = 1080;

  @override
  void initState() {
    super.initState();
    widget.presenter.load();
    widget.installmentPresenter.load();
  }

  void _setMonth(String month) {
    widget.presenter.setMonth(month);
    widget.installmentPresenter.setMonth(month);
    setState(() => _selection = null);
  }

  void _select(BillsSelection selection) =>
      setState(() => _selection = selection);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable:
          Listenable.merge([widget.presenter, widget.installmentPresenter]),
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(WebInsets.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WebSectionHeader(
                title: 'Bills & Receivables',
                subtitle: 'What you owe and what is owed to you.',
                trailing: _AddMenu(
                  presenter: widget.presenter,
                  installmentPresenter: widget.installmentPresenter,
                ),
              ),
              _MonthNavigator(
                month: widget.presenter.selectedMonth,
                onChanged: _setMonth,
              ),
              const SizedBox(height: WebInsets.lg),
              _KpiStrip(
                presenter: widget.presenter,
                installmentPresenter: widget.installmentPresenter,
              ),
              const SizedBox(height: WebInsets.xl),
              LayoutBuilder(
                builder: (context, constraints) {
                  final twoPane = constraints.maxWidth >= _twoPaneMin;
                  final tables = _TablesColumn(
                    presenter: widget.presenter,
                    installmentPresenter: widget.installmentPresenter,
                    onSelect: _select,
                  );
                  final detail = BillsDetailPane(
                    selection: _selection,
                    presenter: widget.presenter,
                    installmentPresenter: widget.installmentPresenter,
                  );
                  if (!twoPane) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        tables,
                        const SizedBox(height: WebInsets.xl),
                        detail,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: tables),
                      const SizedBox(width: WebInsets.xl),
                      Expanded(flex: 2, child: detail),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Month navigator ────────────────────────────────────────────────────────

class _MonthNavigator extends StatelessWidget {
  final String month;
  final ValueChanged<String> onChanged;

  const _MonthNavigator({required this.month, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => onChanged(previousMonth(month)),
          tooltip: 'Previous month',
        ),
        Text(monthLabel(month),
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: () => onChanged(nextMonth(month)),
          tooltip: 'Next month',
        ),
      ],
    );
  }
}

// ─── KPI strip ──────────────────────────────────────────────────────────────

class _KpiStrip extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final InstallmentPresenter installmentPresenter;

  const _KpiStrip(
      {required this.presenter, required this.installmentPresenter});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tiles = [
      WebStatTile(
        label: 'Unpaid bills',
        value: formatPeso(presenter.totalUnpaidObligations),
        sub: '${formatPeso(presenter.totalBillsPaid)} paid',
        icon: Icons.receipt_long_outlined,
        valueColor: presenter.totalUnpaidObligations > 0 ? cs.error : null,
      ),
      WebStatTile(
        label: 'Pending receivables',
        value: formatPeso(presenter.totalReceivablesPending),
        sub: '${formatPeso(presenter.totalReceived)} received',
        icon: Icons.account_balance_wallet_outlined,
      ),
      WebStatTile(
        label: 'Installment load',
        value: formatPeso(installmentPresenter.monthlyInstallmentLoad),
        sub: '${formatPeso(installmentPresenter.totalPaidThisMonth)} paid',
        icon: Icons.credit_score_outlined,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < 640;
        if (stack) {
          return Column(
            children: [
              for (final t in tiles) ...[
                t,
                if (t != tiles.last) const SizedBox(height: WebInsets.md),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              Expanded(child: tiles[i]),
              if (i != tiles.length - 1) const SizedBox(width: WebInsets.md),
            ],
          ],
        );
      },
    );
  }
}

// ─── Tables column (Bills / Receivables / Installments) ─────────────────────

class _TablesColumn extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final InstallmentPresenter installmentPresenter;
  final ValueChanged<BillsSelection> onSelect;

  const _TablesColumn({
    required this.presenter,
    required this.installmentPresenter,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WebCard(
          title: 'Bills',
          description: 'Recurring and one-off obligations this month.',
          child: WebDataTable<Bill>(
            emptyLabel: 'No bills for this month',
            rows: presenter.bills,
            onRowTap: (b) => onSelect(BillSelection(b.id)),
            columns: [
              WebColumn(
                label: 'Name',
                flex: 3,
                cell: (_, b) => Text(b.name, overflow: TextOverflow.ellipsis),
              ),
              WebColumn(
                label: 'Type',
                flex: 2,
                cell: (_, b) => Text(billTypeLabel(b.billType),
                    overflow: TextOverflow.ellipsis),
              ),
              WebColumn(
                label: 'Amount',
                numeric: true,
                flex: 2,
                cell: (_, b) => Text(formatPeso(b.amount)),
              ),
              WebColumn(
                label: 'Due',
                flex: 1,
                cell: (_, b) => Text('Day ${b.dueDay}'),
              ),
              WebColumn(
                label: 'Status',
                flex: 2,
                cell: (_, b) => Align(
                  alignment: Alignment.centerLeft,
                  child: billStatusBadge(presenter.billStatus(b)),
                ),
              ),
              WebColumn(
                label: 'Notes',
                flex: 2,
                cell: (_, b) =>
                    Text(b.paymentNote ?? '—', overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
        const SizedBox(height: WebInsets.xl),
        WebCard(
          title: 'Receivables',
          description: 'Money expected to come in this month.',
          child: WebDataTable<Receivable>(
            emptyLabel: 'No receivables for this month',
            rows: presenter.receivables,
            onRowTap: (r) => onSelect(ReceivableSelection(r.id)),
            columns: [
              WebColumn(
                label: 'Name',
                flex: 3,
                cell: (_, r) => Text(r.name, overflow: TextOverflow.ellipsis),
              ),
              WebColumn(
                label: 'Amount',
                numeric: true,
                flex: 2,
                cell: (_, r) => Text(formatPeso(r.amount)),
              ),
              WebColumn(
                label: 'Status',
                flex: 2,
                cell: (_, r) => Align(
                  alignment: Alignment.centerLeft,
                  child: r.isReceived
                      ? const WebBadge('Received',
                          tone: WebBadgeTone.success,
                          icon: Icons.check_circle_outline)
                      : const WebBadge('Pending', tone: WebBadgeTone.warning),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: WebInsets.xl),
        WebCard(
          title: 'Installments',
          description: 'Purchases split into monthly payments.',
          child: WebDataTable<Installment>(
            emptyLabel: 'No active installments',
            rows: installmentPresenter.installments,
            onRowTap: (i) => onSelect(InstallmentSelection(i.id)),
            columns: [
              WebColumn(
                label: 'Name',
                flex: 3,
                cell: (_, i) => Text(i.name, overflow: TextOverflow.ellipsis),
              ),
              WebColumn(
                label: 'Monthly',
                numeric: true,
                flex: 2,
                cell: (_, i) => Text(formatPeso(i.monthlyAmount)),
              ),
              WebColumn(
                label: 'Remaining',
                numeric: true,
                flex: 2,
                cell: (_, i) =>
                    Text('${installmentPresenter.remainingMonths(i.id)} mo'),
              ),
              WebColumn(
                label: 'Due',
                flex: 2,
                cell: (_, i) => Align(
                  alignment: Alignment.centerLeft,
                  child: installmentBadge(
                    paidThisMonth: installmentPresenter.isPaidForMonth(i.id),
                    dueThisMonth: i.isDueIn(installmentPresenter.selectedMonth),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Add menu (popup → existing sheets as dialogs) ──────────────────────────

class _AddMenu extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final InstallmentPresenter installmentPresenter;

  const _AddMenu({required this.presenter, required this.installmentPresenter});

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder: (context, controller, _) => FilledButton.icon(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Add'),
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.receipt_long_outlined),
          onPressed: () => showAddBillDialog(context, presenter),
          child: const Text('Add Bill'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.account_balance_wallet_outlined),
          onPressed: () => showAddReceivableDialog(context, presenter),
          child: const Text('Add Receivable'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.credit_score_outlined),
          onPressed: () =>
              showAddInstallmentDialog(context, installmentPresenter),
          child: const Text('Add Installment'),
        ),
      ],
    );
  }
}
