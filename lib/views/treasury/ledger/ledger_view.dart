import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/ledger/add_transaction_sheet.dart';
import 'package:intermittent_fasting/views/treasury/ledger/manage_categories_sheet.dart';
import 'package:intermittent_fasting/views/treasury/ledger/transaction_list_tile.dart';

final _dateHeaderFmt = DateFormat('EEEE, MMMM d');

class LedgerView extends StatelessWidget {
  final LedgerPresenter presenter;

  const LedgerView({super.key, required this.presenter});

  void _showAddTransactionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => AddTransactionSheet(presenter: presenter),
    );
  }

  void _showManageCategoriesSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ManageCategoriesSheet(presenter: presenter),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: AppColors.background,
          body: Column(
            children: [
              _AccountFilterRow(presenter: presenter),
              _MonthSelectorRow(presenter: presenter),
              _SummaryRow(presenter: presenter),
              Expanded(child: _TransactionList(presenter: presenter)),
            ],
          ),
          floatingActionButton: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                heroTag: 'categories',
                onPressed: () => _showManageCategoriesSheet(context),
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.textSecondary,
                child: const Icon(Icons.label_outline),
              ),
              const SizedBox(height: 12),
              FloatingActionButton(
                heroTag: 'add_txn',
                onPressed: () => _showAddTransactionSheet(context),
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.background,
                child: const Icon(Icons.add),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AccountFilterRow extends StatelessWidget {
  final LedgerPresenter presenter;

  const _AccountFilterRow({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final accounts = presenter.accounts;

    return SizedBox(
      height: 52,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            _AccountChip(
              label: 'All',
              selected: presenter.selectedAccountId == null,
              onSelected: (_) => presenter.setAccount(null),
            ),
            ...accounts.map(
              (a) => _AccountChip(
                label: a.name,
                selected: presenter.selectedAccountId == a.id,
                onSelected: (_) => presenter.setAccount(a.id),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountChip extends StatelessWidget {
  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  const _AccountChip({required this.label, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: onSelected,
        selectedColor: AppColors.accent.withOpacity(0.2),
        checkmarkColor: AppColors.accent,
        labelStyle: TextStyle(
          color: selected ? AppColors.accent : AppColors.textSecondary,
          fontSize: 12,
        ),
        backgroundColor: AppColors.surface,
        side: BorderSide(color: selected ? AppColors.accent : AppColors.textSecondary.withOpacity(0.3)),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      ),
    );
  }
}

class _MonthSelectorRow extends StatelessWidget {
  final LedgerPresenter presenter;

  const _MonthSelectorRow({required this.presenter});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              icon: Icon(Icons.chevron_left, color: AppColors.textSecondary),
              onPressed: () => presenter.setMonth(previousMonth(presenter.selectedMonth)),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                monthLabel(presenter.selectedMonth),
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              icon: Icon(Icons.chevron_right, color: AppColors.textSecondary),
              onPressed: () => presenter.setMonth(nextMonth(presenter.selectedMonth)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final LedgerPresenter presenter;

  const _SummaryRow({required this.presenter});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.arrow_upward, color: AppColors.success, size: 14),
              const SizedBox(width: 4),
              Text(
                formatPeso(presenter.filteredMonthInflow),
                style: GoogleFonts.jetBrainsMono(
                  textStyle: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Icon(Icons.arrow_downward, color: AppColors.danger, size: 14),
              const SizedBox(width: 4),
              Text(
                formatPeso(presenter.filteredMonthOutflow),
                style: GoogleFonts.jetBrainsMono(
                  textStyle: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TransactionList extends StatelessWidget {
  final LedgerPresenter presenter;

  const _TransactionList({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final grouped = presenter.groupedTransactions;

    if (grouped.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined,
                color: AppColors.textSecondary.withOpacity(0.3), size: 48),
            const SizedBox(height: 12),
            Text(
              'No transactions this month',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap + to log your first one',
              style: TextStyle(
                  color: AppColors.textSecondary.withOpacity(0.5), fontSize: 12),
            ),
          ],
        ),
      );
    }

    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: sortedDates.length,
      itemBuilder: (context, index) {
        final date = sortedDates[index];
        final txns = grouped[date]!;
        return _DateGroup(date: date, transactions: txns, presenter: presenter);
      },
    );
  }
}

class _DateGroup extends StatelessWidget {
  final DateTime date;
  final List<TransactionRecord> transactions;
  final LedgerPresenter presenter;

  const _DateGroup({
    required this.date,
    required this.transactions,
    required this.presenter,
  });

  FinancialAccount? _findAccount(String id) {
    try {
      return presenter.accounts.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  FinanceCategory? _findCategory(String id) {
    try {
      return presenter.categories.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  void _showEditSheet(BuildContext context, TransactionRecord txn) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => AddTransactionSheet(presenter: presenter, existing: txn),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DateHeader(date: date),
        ...transactions.map(
          (txn) => Dismissible(
            key: ValueKey(txn.id),
            direction: DismissDirection.endToStart,
            background: _SwipeDeleteBackground(),
            onDismissed: (_) {
              HapticFeedback.mediumImpact();
              final deleted = txn;
              presenter.deleteTransaction(deleted.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Deleted "${deleted.description}"'),
                  duration: const Duration(seconds: 4),
                  backgroundColor: AppColors.surface,
                  behavior: SnackBarBehavior.floating,
                  action: SnackBarAction(
                    label: 'Undo',
                    textColor: AppColors.accent,
                    onPressed: () => presenter.addTransaction(deleted),
                  ),
                ),
              );
            },
            child: TransactionListTile(
              txn: txn,
              account: _findAccount(txn.accountId),
              category: _findCategory(txn.categoryId),
              onTap: () => _showEditSheet(context, txn),
            ),
          ),
        ),
      ],
    );
  }
}

class _DateHeader extends StatelessWidget {
  final DateTime date;

  const _DateHeader({required this.date});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        _dateHeaderFmt.format(date),
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SwipeDeleteBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.danger.withOpacity(0.8),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 16),
      child: const Icon(Icons.delete_outline, color: Colors.white),
    );
  }
}
