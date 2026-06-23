import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intermittent_fasting/utils/app_text_styles.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/models/finance/finance_parse_result.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/ledger/add_transaction_sheet.dart';
import 'package:intermittent_fasting/views/treasury/ledger/manage_categories_sheet.dart';
import 'package:intermittent_fasting/views/treasury/ledger/spending_calendar.dart';
import 'package:intermittent_fasting/views/treasury/ledger/transaction_list_tile.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

final _dateHeaderFmt = DateFormat('EEEE, MMMM d');
final _filterChipFmt = DateFormat('MMM d');
final _dateFilterFmt = DateFormat('MMM d, yyyy');

class LedgerView extends StatefulWidget {
  final LedgerPresenter presenter;

  const LedgerView({super.key, required this.presenter});

  @override
  State<LedgerView> createState() => _LedgerViewState();
}

class _LedgerViewState extends State<LedgerView> {
  LedgerPresenter get presenter => widget.presenter;
  String? _lastSnackbarSummary;

  @override
  void initState() {
    super.initState();
    presenter.addListener(_onPresenterChange);
  }

  @override
  void dispose() {
    presenter.removeListener(_onPresenterChange);
    super.dispose();
  }

  /// Surfaces post-commit snackbars and the form-prefill fallback as side
  /// effects of presenter state changes. Anything more complex (animations,
  /// scroll restoration) belongs in the build path, not here.
  void _onPresenterChange() {
    if (!mounted) return;
    final summary = presenter.lastCommittedSummary;
    if (summary != null && summary != _lastSnackbarSummary) {
      _lastSnackbarSummary = summary;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(summary), duration: const Duration(seconds: 2)),
      );
      presenter.clearLastCommittedSummary();
    }
    final prefill = presenter.pendingFormPrefill;
    if (prefill != null) {
      presenter.consumeFormPrefill();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showAddTransactionSheet(prefill: prefill);
      });
    }
  }

  void _showAddTransactionSheet({ParsedTransaction? prefill}) {
    AppBottomSheet.show(
      context: context,
      title: 'Log Transaction',
      body: AddTransactionSheet(
        presenter: presenter,
        prefill: prefill,
        // Pre-fill the filtered day so a forgotten past-dated entry can be
        // logged without clearing the filter first.
        initialDate: presenter.selectedDate,
      ),
    );
  }

  void _showEditTransactionSheet(TransactionRecord txn) {
    AppBottomSheet.show(
      context: context,
      title: 'Edit Transaction',
      body: AddTransactionSheet(presenter: presenter, existing: txn),
    );
  }

  void _showManageCategoriesSheet() {
    AppBottomSheet.show(
      context: context,
      title: 'Manage Categories',
      body: ManageCategoriesSheet(presenter: presenter),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                _MonthSelectorRow(presenter: presenter),
                if (presenter.selectedDate != null)
                  _DateFilterChip(
                    date: presenter.selectedDate!,
                    onClear: () => presenter.setSelectedDate(null),
                  ),
                _SummaryCard(presenter: presenter),
                _AccountFilterRow(presenter: presenter),
                Expanded(
                  child: _TransactionList(
                    presenter: presenter,
                    onEditTransaction: _showEditTransactionSheet,
                  ),
                ),
                _ChatHardErrorChip(presenter: presenter),
                _LedgerChatDrawer(presenter: presenter),
                _LedgerChatInputBar(
                  presenter: presenter,
                  onOpenForm: _showAddTransactionSheet,
                  onOpenCategories: _showManageCategoriesSheet,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Chat drawer + input row ────────────────────────────────────────────────

/// Renders the transient AI dialog above the input bar. Hidden when
/// [LedgerChatState.phase] is idle.
class _LedgerChatDrawer extends StatelessWidget {
  final LedgerPresenter presenter;
  const _LedgerChatDrawer({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final state = presenter.chatState;
    final visible = state.phase != ChatPhase.idle;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: Alignment.bottomCenter,
      child: !visible
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              color: cs.surfaceContainerLow,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Transcript(turns: state.turns),
                  const SizedBox(height: 8),
                  if (state.lastStep is StepClarify)
                    _ClarifyActions(
                      presenter: presenter,
                      step: state.lastStep as StepClarify,
                    )
                  else if (state.lastStep is StepResolved)
                    _ResolveActions(presenter: presenter)
                  else if (state.phase == ChatPhase.classifying)
                    Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Thinking…',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                ],
              ),
            ),
    );
  }
}

class _Transcript extends StatelessWidget {
  final List<LedgerChatTurn> turns;
  const _Transcript({required this.turns});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Show last 3 turns only — anything older isn't load-bearing for the
    // user's decision and the drawer should stay compact.
    final visible = turns.length > 3 ? turns.sublist(turns.length - 3) : turns;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final t in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: t.isUser ? 'You: ' : 'AI: ',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  TextSpan(
                    text: t.text,
                    style: TextStyle(color: cs.onSurface, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ClarifyActions extends StatelessWidget {
  final LedgerPresenter presenter;
  final StepClarify step;
  const _ClarifyActions({required this.presenter, required this.step});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final replies = step.quickReplies ?? const <QuickReply>[];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final r in replies)
                ActionChip(
                  label: Text(r.label),
                  onPressed: () => presenter.sendChatInput(r.replyText),
                ),
            ],
          ),
        ),
        TextButton(
          onPressed: presenter.cancelChat,
          style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _ResolveActions extends StatelessWidget {
  final LedgerPresenter presenter;
  const _ResolveActions({required this.presenter});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
            onPressed: presenter.cancelChat, child: const Text('Cancel')),
        const SizedBox(width: 4),
        TextButton(
            onPressed: presenter.editResolved, child: const Text('Edit')),
        const SizedBox(width: 4),
        FilledButton(
          onPressed: presenter.confirmResolved,
          child: const Text('Yes'),
        ),
      ],
    );
  }
}

class _ChatHardErrorChip extends StatelessWidget {
  final LedgerPresenter presenter;
  const _ChatHardErrorChip({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final error = presenter.chatHardError;
    if (error == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: cs.errorContainer,
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: cs.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error.userMessage,
              style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: cs.onErrorContainer, size: 18),
            onPressed: presenter.clearChatHardError,
            tooltip: 'Dismiss',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _LedgerChatInputBar extends StatefulWidget {
  final LedgerPresenter presenter;
  final void Function({ParsedTransaction? prefill}) onOpenForm;
  final VoidCallback onOpenCategories;

  const _LedgerChatInputBar({
    required this.presenter,
    required this.onOpenForm,
    required this.onOpenCategories,
  });

  @override
  State<_LedgerChatInputBar> createState() => _LedgerChatInputBarState();
}

class _LedgerChatInputBarState extends State<_LedgerChatInputBar> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      _ctrl.clear();
      await widget.presenter.sendChatInput(text);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _hint(LedgerPresenter p) {
    if (!p.isSelectedDateToday) return 'Tap the form to log on this day';
    if (p.chatState.phase == ChatPhase.clarifying) return 'Reply…';
    return 'Log a transaction…';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Quick chat-logging stamps "today", so it stays gated to the current day.
    // The form, however, is always reachable and pre-fills the filtered day.
    final canSend = widget.presenter.isSelectedDateToday;
    return Container(
      color: cs.surface,
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.label_outline, color: cs.onSurfaceVariant),
            onPressed: widget.onOpenCategories,
            tooltip: 'Manage categories',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
          IconButton(
            icon: Icon(Icons.edit_outlined, color: cs.onSurfaceVariant),
            // Always available — the form pre-fills the filtered day so a
            // past-dated transaction can be logged without clearing the filter.
            onPressed: () => widget.onOpenForm(),
            tooltip: 'Open form',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
          Expanded(
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              enabled: canSend,
              decoration: InputDecoration(
                hintText: _hint(widget.presenter),
                filled: true,
                fillColor: cs.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                isDense: true,
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              icon: _sending ||
                      widget.presenter.chatState.phase == ChatPhase.classifying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              onPressed: canSend ? _send : null,
            ),
          ),
        ],
      ),
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
    final cs = Theme.of(context).colorScheme;
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
                ? cs.primary.withValues(alpha: 0.15)
                : cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? cs.primary : cs.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 13,
                    color: selected ? cs.primary : cs.onSurfaceVariant),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? cs.primary : cs.onSurfaceVariant,
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      color: theme.scaffoldBackgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              icon: Icon(Icons.chevron_left, color: cs.onSurfaceVariant),
              onPressed: () => widget.presenter.stepDay(-1),
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
                      widget.presenter.selectedDate != null
                          ? _dateFilterFmt
                              .format(widget.presenter.selectedDate!)
                          : monthLabel(widget.presenter.selectedMonth),
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      color: cs.onSurfaceVariant,
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
              icon: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
              onPressed: () => widget.presenter.stepDay(1),
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
                  color: Theme.of(context)
                      .colorScheme
                      .shadow
                      .withValues(alpha: 0.35),
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
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.primary.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today_outlined,
                    size: 12, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  'Filtered: ${_filterChipFmt.format(date)}',
                  style: TextStyle(
                    color: cs.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: onClear,
                  child: Icon(Icons.close_rounded, size: 14, color: cs.primary),
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final inflow = presenter.filteredMonthInflow;
    final outflow = presenter.filteredMonthOutflow;
    final net = presenter.filteredMonthNet;
    final netColor = net >= 0 ? cs.tertiary : cs.error;
    final netPrefix = net >= 0 ? '+' : '';

    return Container(
      width: double.infinity,
      color: theme.scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          _SummaryChip(
            label: 'Income',
            value: formatPeso(inflow),
            color: cs.tertiary,
          ),
          const SizedBox(width: 8),
          _SummaryChip(
            label: 'Expenses',
            value: formatPeso(outflow),
            color: cs.error,
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
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
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
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
  final void Function(TransactionRecord txn) onEditTransaction;

  const _TransactionList({
    required this.presenter,
    required this.onEditTransaction,
  });

  @override
  Widget build(BuildContext context) {
    final grouped = presenter.groupedTransactions;

    if (grouped.isEmpty) {
      return const AppEmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No transactions this month',
        body: 'Tap + to log your first one',
      );
    }

    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: sortedDates.length,
      itemBuilder: (context, index) {
        final date = sortedDates[index];
        final txns = grouped[date]!;
        return _DateGroup(
          date: date,
          transactions: txns,
          presenter: presenter,
          onEditTransaction: onEditTransaction,
        );
      },
    );
  }
}

// ── Date Group ───────────────────────────────────────────────────────────────

class _DateGroup extends StatelessWidget {
  final DateTime date;
  final List<TransactionRecord> transactions;
  final LedgerPresenter presenter;
  final void Function(TransactionRecord txn) onEditTransaction;

  const _DateGroup({
    required this.date,
    required this.transactions,
    required this.presenter,
    required this.onEditTransaction,
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

  /// Resolves an account's swatch color (palette-indexed, brightness-aware)
  /// for the subtitle dot. Null when the account is unknown.
  Color? _accountColor(BuildContext context, String id) {
    final idx = presenter.accounts.indexWhere((a) => a.id == id);
    if (idx < 0) return null;
    return resolveSliceColor(
      presenter.accounts[idx].colorHex,
      idx,
      brightness: Theme.of(context).brightness,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: AppSection(
        title: _DateHeader.labelFor(date),
        trailing: _dailyNet != 0 ? _DailyNetBadge(dailyNet: _dailyNet) : null,
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Column(
          children: [
            ...transactions.map(
              (txn) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: AppCard(
                  variant: AppCardVariant.filled,
                  padding: EdgeInsets.zero,
                  child: TransactionListTile(
                    key: ValueKey(txn.id),
                    txn: txn,
                    account: _findAccount(txn.accountId),
                    accountColor: _accountColor(context, txn.accountId),
                    category: _findCategory(txn.categoryId),
                    onTap: () => onEditTransaction(txn),
                    onDelete: () {
                      HapticFeedback.mediumImpact();
                      final deleted = txn;
                      presenter.deleteTransaction(deleted.id);
                      AppToast.action(
                        context,
                        message: 'Deleted "${deleted.description}"',
                        actionLabel: 'Undo',
                        onAction: () => presenter.addTransaction(deleted),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

// ── Date Header ──────────────────────────────────────────────────────────────

class _DateHeader extends StatelessWidget {
  final DateTime date;
  final double dailyNet;

  const _DateHeader({required this.date, required this.dailyNet});

  static String labelFor(DateTime date) {
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
    return Text(labelFor(date).toUpperCase());
  }
}

// ── Daily Net Badge ───────────────────────────────────────────────────────────

class _DailyNetBadge extends StatelessWidget {
  final double dailyNet;

  const _DailyNetBadge({required this.dailyNet});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final netColor = dailyNet > 0
        ? cs.tertiary
        : dailyNet < 0
            ? cs.error
            : cs.onSurfaceVariant;
    final prefix = dailyNet > 0 ? '+' : '';

    return Text(
      '$prefix${formatPeso(dailyNet.abs())}',
      style: AppTextStyles.mono(
        textStyle: TextStyle(
          color: netColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
