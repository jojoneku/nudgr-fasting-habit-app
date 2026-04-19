import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intermittent_fasting/utils/app_text_styles.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/ledger/add_transaction_sheet.dart';
import 'package:intermittent_fasting/views/treasury/ledger/manage_categories_sheet.dart';
import 'package:intermittent_fasting/views/treasury/ledger/spending_calendar.dart';
import 'package:intermittent_fasting/views/treasury/ledger/transaction_list_tile.dart';

final _dateHeaderFmt = DateFormat('EEEE, MMMM d');
final _filterChipFmt = DateFormat('MMM d');

class LedgerView extends StatefulWidget {
  final LedgerPresenter presenter;

  const LedgerView({super.key, required this.presenter});

  @override
  State<LedgerView> createState() => _LedgerViewState();
}

class _LedgerViewState extends State<LedgerView> {
  LedgerPresenter get presenter => widget.presenter;

  void _showAddTransactionSheet() {
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

  void _showManageCategoriesSheet() {
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
              _MonthSelectorRow(presenter: presenter),
              if (presenter.selectedDate != null)
                _DateFilterChip(
                  date: presenter.selectedDate!,
                  onClear: () => presenter.setSelectedDate(null),
                ),
              _SummaryCard(presenter: presenter),
              _AccountFilterRow(presenter: presenter),
              Expanded(child: _TransactionList(presenter: presenter)),
            ],
          ),
          floatingActionButton: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                heroTag: 'categories',
                onPressed: _showManageCategoriesSheet,
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.textSecondary,
                elevation: 2,
                child: const Icon(Icons.label_outline),
              ),
              const SizedBox(height: 12),
              FloatingActionButton(
                heroTag: 'add_txn',
                onPressed: _showAddTransactionSheet,
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.background,
                elevation: 4,
                child: const Icon(Icons.add),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Account Filter ──────────────────────────────────────────────────────────

class _AccountFilterRow extends StatelessWidget {
  final LedgerPresenter presenter;

  const _AccountFilterRow({required this.presenter});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          _AccountPill(
            label: 'All',
            icon: Icons.account_balance_wallet_outlined,
            selected: presenter.selectedAccountId == null,
            onTap: () => presenter.setAccount(null),
          ),
          ...presenter.accounts.map((a) => _AccountPill(
                label: a.name,
                selected: presenter.selectedAccountId == a.id,
                onTap: () => presenter.setAccount(a.id),
              )),
        ],
      ),
    );
  }
}

class _AccountPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const _AccountPill({
    required this.label,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withOpacity(0.15)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? AppColors.accent
                  : AppColors.textSecondary.withOpacity(0.25),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 13,
                    color:
                        selected ? AppColors.accent : AppColors.textSecondary),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.accent : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Month Selector ──────────────────────────────────────────────────────────

class _MonthSelectorRow extends StatefulWidget {
  final LedgerPresenter presenter;

  const _MonthSelectorRow({required this.presenter});

  @override
  State<_MonthSelectorRow> createState() => _MonthSelectorRowState();
}

class _MonthSelectorRowState extends State<_MonthSelectorRow> {
  final _labelKey = GlobalKey();

  Future<void> _showCalendarPopover() async {
    HapticFeedback.selectionClick();
    final box = _labelKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final offset = box.localToGlobal(Offset.zero);
    final size = box.size;
    final topOffset = offset.dy + size.height + 6;

    await showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => _CalendarPopover(
        presenter: widget.presenter,
        topOffset: topOffset,
        onDismiss: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              icon: Icon(Icons.chevron_left, color: AppColors.textSecondary),
              onPressed: () => widget.presenter
                  .setMonth(previousMonth(widget.presenter.selectedMonth)),
            ),
          ),
          Expanded(
            child: Center(
              child: GestureDetector(
                key: _labelKey,
                onTap: _showCalendarPopover,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      monthLabel(widget.presenter.selectedMonth),
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              icon: Icon(Icons.chevron_right, color: AppColors.textSecondary),
              onPressed: () => widget.presenter
                  .setMonth(nextMonth(widget.presenter.selectedMonth)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Calendar Popover ─────────────────────────────────────────────────────────

class _CalendarPopover extends StatelessWidget {
  final LedgerPresenter presenter;
  final double topOffset;
  final VoidCallback onDismiss;

  const _CalendarPopover({
    required this.presenter,
    required this.topOffset,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onDismiss,
      child: Align(
        alignment: Alignment.topCenter,
        child: GestureDetector(
          // Swallow taps inside so they don't propagate to the dismiss handler
          onTap: () {},
          child: Container(
            margin: EdgeInsets.only(top: topOffset, left: 12, right: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: SpendingCalendar(
              presenter: presenter,
              onDaySelected: (day) {
                HapticFeedback.selectionClick();
                final current = presenter.selectedDate;
                if (current != null &&
                    current.year == day.year &&
                    current.month == day.month &&
                    current.day == day.day) {
                  presenter.setSelectedDate(null);
                } else {
                  presenter.setSelectedDate(day);
                }
                onDismiss();
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ── Date Filter Chip ─────────────────────────────────────────────────────────

class _DateFilterChip extends StatelessWidget {
  final DateTime date;
  final VoidCallback onClear;

  const _DateFilterChip({required this.date, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.accent.withOpacity(0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today_outlined,
                    size: 12, color: AppColors.accent),
                const SizedBox(width: 6),
                Text(
                  'Filtered: ${_filterChipFmt.format(date)}',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: onClear,
                  child: Icon(Icons.close_rounded,
                      size: 14, color: AppColors.accent),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Summary Card ─────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final LedgerPresenter presenter;

  const _SummaryCard({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final inflow = presenter.filteredMonthInflow;
    final outflow = presenter.filteredMonthOutflow;
    final net = presenter.filteredMonthNet;
    final netColor = net >= 0 ? AppColors.success : AppColors.danger;
    final netPrefix = net >= 0 ? '+' : '';

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          _SummaryChip(
            label: 'Income',
            value: formatPeso(inflow),
            color: AppColors.success,
          ),
          const SizedBox(width: 8),
          _SummaryChip(
            label: 'Expenses',
            value: formatPeso(outflow),
            color: AppColors.danger,
          ),
          const SizedBox(width: 8),
          _SummaryChip(
            label: 'Net',
            value: '$netPrefix${formatPeso(net.abs())}',
            color: netColor,
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: AppTextStyles.mono(
                textStyle: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Transaction List ─────────────────────────────────────────────────────────

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
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(
                    color: AppColors.textSecondary.withOpacity(0.15)),
              ),
              child: Icon(
                Icons.receipt_long_outlined,
                color: AppColors.textSecondary.withOpacity(0.4),
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No transactions this month',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap + to log your first one',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: sortedDates.length,
      itemBuilder: (context, index) {
        final date = sortedDates[index];
        final txns = grouped[date]!;
        return _DateGroup(date: date, transactions: txns, presenter: presenter);
      },
    );
  }
}

// ── Date Group ───────────────────────────────────────────────────────────────

class _DateGroup extends StatelessWidget {
  final DateTime date;
  final List<TransactionRecord> transactions;
  final LedgerPresenter presenter;

  const _DateGroup({
    required this.date,
    required this.transactions,
    required this.presenter,
  });

  double get _dailyNet => transactions.fold(
      0.0,
      (sum, txn) => switch (txn.type) {
            TransactionType.inflow => sum + txn.amount,
            TransactionType.outflow => sum - txn.amount,
            TransactionType.transfer => sum,
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
        _DateHeader(date: date, dailyNet: _dailyNet),
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
        const SizedBox(height: 4),
      ],
    );
  }
}

// ── Date Header ──────────────────────────────────────────────────────────────

class _DateHeader extends StatelessWidget {
  final DateTime date;
  final double dailyNet;

  const _DateHeader({required this.date, required this.dailyNet});

  String get _label {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(date.year, date.month, date.day);
    if (d == today) return 'Today';
    if (d == yesterday) return 'Yesterday';
    return _dateHeaderFmt.format(date);
  }

  @override
  Widget build(BuildContext context) {
    final netColor = dailyNet > 0
        ? AppColors.success
        : dailyNet < 0
            ? AppColors.danger
            : AppColors.textSecondary;
    final prefix = dailyNet > 0 ? '+' : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _label.toUpperCase(),
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              letterSpacing: 1.0,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (dailyNet != 0)
            Text(
              '$prefix${formatPeso(dailyNet.abs())}',
              style: AppTextStyles.mono(
                textStyle: TextStyle(
                  color: netColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Swipe Delete Background ──────────────────────────────────────────────────

class _SwipeDeleteBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(0.85),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.delete_outline, color: Colors.white, size: 22),
          const SizedBox(height: 2),
          Text(
            'DELETE',
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
