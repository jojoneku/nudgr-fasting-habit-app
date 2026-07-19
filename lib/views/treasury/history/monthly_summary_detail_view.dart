import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class MonthlySummaryDetailView extends StatelessWidget {
  final MonthlySummary summary;
  final List<FinanceCategory> categories;
  final List<FinancialAccount> accounts;

  const MonthlySummaryDetailView({
    super.key,
    required this.summary,
    required this.categories,
    this.accounts = const [],
  });

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold.large(
      title: monthLabel(summary.month),
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
              _AccountSnapshotsSection(summary: summary, accounts: accounts),
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
    final netPositive = summary.netSavings >= 0;
    final rate = summary.savingsRate;

    return AppCard(
      variant: AppCardVariant.filled,
      child: Column(
        children: [
          // IN · OUT · NET, three centered columns split by hairline dividers.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TotalCol(
                  label: 'IN',
                  value: formatPesoCompact(summary.totalInflow),
                  color: cs.tertiary,
                ),
                _divider(cs),
                _TotalCol(
                  label: 'OUT',
                  value: formatPesoCompact(summary.totalOutflow),
                  color: cs.error,
                ),
                _divider(cs),
                _TotalCol(
                  label: 'NET',
                  value:
                      '${netPositive ? '+' : '−'}${formatPesoCompact(summary.netSavings.abs())}',
                  color: netPositive ? cs.primary : cs.error,
                ),
              ],
            ),
          ),
          if (rate != null) ...[
            const SizedBox(height: 13),
            AppLinearProgress(
              value: rate.clamp(0.0, 1.0),
              color: cs.primary,
              height: 7,
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Saved ${(rate * 100).round()}% of income',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _divider(ColorScheme cs) => Container(
        width: 1,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: cs.outlineVariant,
      );
}

class _TotalCol extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _TotalCol(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w800),
          ),
        ],
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
        variant: AppCardVariant.filled,
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

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final sorted = summary.categorySpend.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return AppSection(
      title: 'SPENDING BY CATEGORY',
      child: Column(
        children: [
          for (var i = 0; i < sorted.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Builder(builder: (context) {
              final entry = sorted[i];
              final cat = categories.cast<FinanceCategory?>().firstWhere(
                    (c) => c?.id == entry.key,
                    orElse: () => null,
                  );
              final dot = cat != null
                  ? resolveSliceColor(cat.colorHex, i,
                      brightness: theme.brightness)
                  : cs.onSurfaceVariant;
              return AppCard(
                variant: AppCardVariant.filled,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: dot,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        cat?.name ?? entry.key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatPeso(entry.value),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

// ─── Account Snapshots Section ────────────────────────────────────────────────

class _AccountSnapshotsSection extends StatelessWidget {
  final MonthlySummary summary;
  final List<FinancialAccount> accounts;

  const _AccountSnapshotsSection({
    required this.summary,
    required this.accounts,
  });

  @override
  Widget build(BuildContext context) {
    if (summary.accountSnapshots.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final nameById = {for (final a in accounts) a.id: a.name};

    return AppSection(
      title: 'ACCOUNT BALANCES AT CLOSE',
      child: AppCard(
        variant: AppCardVariant.filled,
        child: Column(
          children: summary.accountSnapshots.entries
              .map(
                (e) => AppListTile(
                  dense: true,
                  title: Text(nameById[e.key] ?? e.key),
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
