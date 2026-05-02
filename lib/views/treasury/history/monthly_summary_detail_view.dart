import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class MonthlySummaryDetailView extends StatelessWidget {
  final MonthlySummary summary;
  final List<FinanceCategory> categories;

  const MonthlySummaryDetailView({
    super.key,
    required this.summary,
    required this.categories,
  });

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold.large(
      title: monthLabel(summary.month).toUpperCase(),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.pop(context),
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _CashFlowSection(summary: summary),
              const SizedBox(height: 16),
              _BillsReceivablesSection(summary: summary),
              const SizedBox(height: 16),
              _CategorySpendSection(summary: summary, categories: categories),
              const SizedBox(height: 16),
              _AccountSnapshotsSection(summary: summary),
            ]),
          ),
        ),
      ],
    );
  }
}

// ─── Cash Flow Section ────────────────────────────────────────────────────────

class _CashFlowSection extends StatelessWidget {
  final MonthlySummary summary;

  const _CashFlowSection({required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final total = summary.totalInflow + summary.totalOutflow;
    final inflowPct =
        total > 0 ? (summary.totalInflow / total).clamp(0.0, 1.0) : 0.5;

    return AppSection(
      title: 'CASH FLOW',
      child: AppCard(
        variant: AppCardVariant.elevated,
        child: Column(
          children: [
            // 3-column metrics
            Row(
              children: [
                Expanded(
                  child: AppNumberDisplay(
                    value: formatPeso(summary.totalInflow),
                    label: 'Total Inflow',
                    size: AppNumberSize.body,
                    color: cs.tertiary,
                    textAlign: TextAlign.start,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppNumberDisplay(
                    value: formatPeso(summary.totalOutflow),
                    label: 'Total Outflow',
                    size: AppNumberSize.body,
                    color: cs.error,
                    textAlign: TextAlign.start,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppNumberDisplay(
                    value: formatPeso(summary.netSavings.abs()),
                    prefix: summary.netSavings >= 0 ? '+' : '−',
                    label: 'Net Savings',
                    size: AppNumberSize.body,
                    color: summary.netSavings >= 0 ? cs.tertiary : cs.error,
                    textAlign: TextAlign.start,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Visual inflow/outflow split bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Row(
                children: [
                  Expanded(
                    flex: (inflowPct * 100).round().clamp(1, 99),
                    child: Container(height: 8, color: cs.tertiary),
                  ),
                  Expanded(
                    flex: ((1 - inflowPct) * 100).round().clamp(1, 99),
                    child: Container(height: 8, color: cs.error),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Bills & Receivables Section ──────────────────────────────────────────────

class _BillsReceivablesSection extends StatelessWidget {
  final MonthlySummary summary;

  const _BillsReceivablesSection({required this.summary});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final allBillsPaid =
        summary.billsPaidCount == summary.billCount && summary.billCount > 0;
    final allReceived = summary.receivableCount > 0
        ? summary.totalReceived >= summary.totalReceivables
        : false;

    return AppSection(
      title: 'BILLS & RECEIVABLES',
      child: AppCard(
        variant: AppCardVariant.elevated,
        child: Column(
          children: [
            AppListTile(
              dense: true,
              leading: Icon(
                allBillsPaid
                    ? Icons.check_circle_outline
                    : Icons.pending_outlined,
                color: allBillsPaid ? cs.tertiary : cs.secondary,
                size: 18,
              ),
              title: const Text('Bills Paid'),
              subtitle: Text(
                '${summary.billsPaidCount} / ${summary.billCount}  '
                '(${formatPeso(summary.totalBillsPaid)} / ${formatPeso(summary.totalBills)})',
              ),
              contentPadding: EdgeInsets.zero,
            ),
            AppListTile(
              dense: true,
              leading: Icon(
                allReceived
                    ? Icons.check_circle_outline
                    : Icons.schedule_outlined,
                color: allReceived ? cs.tertiary : cs.primary,
                size: 18,
              ),
              title: const Text('Receivables'),
              subtitle: Text(
                '${formatPeso(summary.totalReceived)} received of '
                '${formatPeso(summary.totalReceivables)}',
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Category Spend Section ───────────────────────────────────────────────────

class _CategorySpendSection extends StatelessWidget {
  final MonthlySummary summary;
  final List<FinanceCategory> categories;

  const _CategorySpendSection(
      {required this.summary, required this.categories});

  @override
  Widget build(BuildContext context) {
    if (summary.categorySpend.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

    final sorted = summary.categorySpend.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxSpend = sorted.first.value;

    return AppSection(
      title: 'SPENDING BY CATEGORY',
      child: AppCard(
        variant: AppCardVariant.elevated,
        child: Column(
          children: sorted.map((entry) {
            final cat = categories.cast<FinanceCategory?>().firstWhere(
                  (c) => c?.id == entry.key,
                  orElse: () => null,
                );
            final pct =
                maxSpend > 0 ? (entry.value / maxSpend).clamp(0.0, 1.0) : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppLinearProgress(
                value: pct,
                label: cat?.name ?? entry.key,
                valueText: formatPeso(entry.value),
                color: cs.primary,
                height: 5,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ─── Account Snapshots Section ────────────────────────────────────────────────

class _AccountSnapshotsSection extends StatelessWidget {
  final MonthlySummary summary;

  const _AccountSnapshotsSection({required this.summary});

  @override
  Widget build(BuildContext context) {
    if (summary.accountSnapshots.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AppSection(
      title: 'ACCOUNT BALANCES AT CLOSE',
      child: AppCard(
        variant: AppCardVariant.elevated,
        child: Column(
          children: summary.accountSnapshots.entries
              .map(
                (e) => AppListTile(
                  dense: true,
                  title: Text(e.key),
                  trailing: AppNumberDisplay(
                    value: formatPeso(e.value),
                    size: AppNumberSize.body,
                    color: cs.onSurface,
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
