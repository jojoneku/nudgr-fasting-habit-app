import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text(
          monthLabel(summary.month).toUpperCase(),
          style: const TextStyle(fontSize: 14, letterSpacing: 1.5),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _IncomeExpenseSection(summary: summary),
          const SizedBox(height: 12),
          _BillsReceivablesSection(summary: summary),
          const SizedBox(height: 12),
          _CategorySpendSection(summary: summary, categories: categories),
          const SizedBox(height: 12),
          _AccountSnapshotsSection(summary: summary),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─── Income vs Expense Section ────────────────────────────────────────────────

class _IncomeExpenseSection extends StatelessWidget {
  final MonthlySummary summary;

  const _IncomeExpenseSection({required this.summary});

  @override
  Widget build(BuildContext context) {
    final total = summary.totalInflow + summary.totalOutflow;
    final inflowPct =
        total > 0 ? (summary.totalInflow / total).clamp(0.0, 1.0) : 0.5;

    return _Card(
      title: 'CASH FLOW',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _FlowMetric(
                  label: 'Total Inflow',
                  value: formatPeso(summary.totalInflow),
                  color: AppColors.success,
                  icon: Icons.arrow_downward,
                ),
              ),
              Expanded(
                child: _FlowMetric(
                  label: 'Total Outflow',
                  value: formatPeso(summary.totalOutflow),
                  color: AppColors.danger,
                  icon: Icons.arrow_upward,
                ),
              ),
              Expanded(
                child: _FlowMetric(
                  label: 'Net Savings',
                  value: formatPeso(summary.netSavings.abs()),
                  color: summary.netSavings >= 0
                      ? AppColors.success
                      : AppColors.danger,
                  prefix: summary.netSavings >= 0 ? '+' : '-',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Row(
              children: [
                Expanded(
                  flex: (inflowPct * 100).round(),
                  child: Container(height: 8, color: AppColors.success),
                ),
                Expanded(
                  flex: ((1 - inflowPct) * 100).round(),
                  child: Container(height: 8, color: AppColors.danger),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FlowMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData? icon;
  final String prefix;

  const _FlowMetric({
    required this.label,
    required this.value,
    required this.color,
    this.icon,
    this.prefix = '',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: color, size: 12),
              const SizedBox(width: 3),
            ],
            Text(label,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '$prefix$value',
          style: TextStyle(
              color: color, fontSize: 13, fontWeight: FontWeight.w700),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ─── Bills & Receivables Section ──────────────────────────────────────────────

class _BillsReceivablesSection extends StatelessWidget {
  final MonthlySummary summary;

  const _BillsReceivablesSection({required this.summary});

  @override
  Widget build(BuildContext context) {
    final allBillsPaid =
        summary.billsPaidCount == summary.billCount && summary.billCount > 0;
    final allReceived = summary.receivableCount > 0
        ? summary.totalReceived >= summary.totalReceivables
        : false;

    return _Card(
      title: 'BILLS & RECEIVABLES',
      child: Column(
        children: [
          _DetailRow(
            label: 'Bills Paid',
            value:
                '${summary.billsPaidCount} / ${summary.billCount}  (${formatPeso(summary.totalBillsPaid)} / ${formatPeso(summary.totalBills)})',
            color: allBillsPaid ? AppColors.success : AppColors.gold,
            icon: allBillsPaid
                ? Icons.check_circle_outline
                : Icons.pending_outlined,
          ),
          const SizedBox(height: 8),
          _DetailRow(
            label: 'Receivables',
            value:
                '${formatPeso(summary.totalReceived)} received of ${formatPeso(summary.totalReceivables)}',
            color: allReceived ? AppColors.success : AppColors.accent,
            icon: allReceived
                ? Icons.check_circle_outline
                : Icons.schedule_outlined,
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _DetailRow({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              const SizedBox(height: 2),
              Text(value,
                  style: TextStyle(
                      color: color, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
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

    final sorted = summary.categorySpend.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final maxSpend = sorted.first.value;

    return _Card(
      title: 'SPENDING BY CATEGORY',
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      cat?.name ?? entry.key,
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                    Text(
                      formatPeso(entry.value),
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 5,
                    backgroundColor: AppColors.textSecondary.withOpacity(0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
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

    return _Card(
      title: 'ACCOUNT BALANCES AT CLOSE',
      child: Column(
        children: summary.accountSnapshots.entries
            .map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      e.key,
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      formatPeso(e.value),
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

// ─── Shared card widget ───────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final String title;
  final Widget child;

  const _Card({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.textSecondary.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
