import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/utils/app_text_styles.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/models/finance/finance_parse_result.dart';
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

  void _showFilterSortSheet() {
    HapticFeedback.selectionClick();
    AppBottomSheet.show(
      context: context,
      title: 'Filter & sort',
      body: _FilterSortSheet(presenter: presenter),
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
                _FilterSortBar(
                  presenter: presenter,
                  onOpenFilters: _showFilterSortSheet,
                ),
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final blue = context.appColors.fast;
    // Quick chat-logging stamps "today", so it stays gated to the current day.
    // The form, however, is always reachable and pre-fills the filtered day.
    final canSend = widget.presenter.isSelectedDateToday;
    final busy =
        _sending || widget.presenter.chatState.phase == ChatPhase.classifying;
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
          // Reference-style input pill: a sparkle glyph hinting at AI parsing +
          // the free-text field, inside a single rounded container.
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.only(left: 14, right: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, size: 16, color: blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      enabled: canSend,
                      decoration: InputDecoration(
                        hintText: _hint(widget.presenter),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Circular accent send button (reference's blue mic/send affordance).
          Semantics(
            button: true,
            label: 'Send',
            child: Material(
              color: canSend ? blue : cs.surfaceContainerHighest,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: canSend ? _send : null,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: busy
                      ? const Padding(
                          padding: EdgeInsets.all(13),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          Icons.arrow_upward_rounded,
                          size: 20,
                          color: canSend ? Colors.white : cs.onSurfaceVariant,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Filter & Sort ─────────────────────────────────────────────────────────

/// Single-button filter/sort bar (reference "Filter & sort"): a pill button
/// with an active-count badge that opens [_FilterSortSheet].
class _FilterSortBar extends StatelessWidget {
  final LedgerPresenter presenter;
  final VoidCallback onOpenFilters;

  const _FilterSortBar({
    required this.presenter,
    required this.onOpenFilters,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final blue = context.appColors.fast;
    final count = presenter.activeFilterCount;
    final active = count > 0 || presenter.isCustomSort;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Row(
        children: [
          GestureDetector(
            onTap: onOpenFilters,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              decoration: BoxDecoration(
                color: active
                    ? blue.withValues(alpha: 0.15)
                    : cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: active ? blue : cs.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune_rounded,
                      size: 15, color: active ? blue : cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    'Filter & sort',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: active ? blue : cs.onSurfaceVariant,
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: blue,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Quick clear — wipes the active filters (keeps sort) without opening
          // the sheet. Only shown when something is filtered.
          if (count > 0) ...[
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: 'Clear filters',
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  presenter.clearAllFilters();
                },
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    shape: BoxShape.circle,
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Icon(Icons.close_rounded,
                      size: 16, color: cs.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The Filter & sort bottom sheet: multi-select categories + accounts, the owed
/// toggle, and Date/Amount sort with direction. Applies live via the presenter.
class _FilterSortSheet extends StatelessWidget {
  final LedgerPresenter presenter;
  const _FilterSortSheet({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) {
        final expense = presenter.categories
            .where((c) => c.type == CategoryType.expense)
            .toList();
        final income = presenter.categories
            .where((c) => c.type == CategoryType.income)
            .toList();
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _FilterHeading('Sort by'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _SelectChip(
                    label: 'Newest',
                    selected: presenter.sortField == LedgerSortField.date &&
                        presenter.sortDescending,
                    onTap: () => presenter.setSort(LedgerSortField.date,
                        descending: true),
                  ),
                  _SelectChip(
                    label: 'Oldest',
                    selected: presenter.sortField == LedgerSortField.date &&
                        !presenter.sortDescending,
                    onTap: () => presenter.setSort(LedgerSortField.date,
                        descending: false),
                  ),
                  _SelectChip(
                    label: 'Largest',
                    selected: presenter.sortField == LedgerSortField.amount &&
                        presenter.sortDescending,
                    onTap: () => presenter.setSort(LedgerSortField.amount,
                        descending: true),
                  ),
                  _SelectChip(
                    label: 'Smallest',
                    selected: presenter.sortField == LedgerSortField.amount &&
                        !presenter.sortDescending,
                    onTap: () => presenter.setSort(LedgerSortField.amount,
                        descending: false),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (presenter.hasOutstandingOwed || presenter.owedOnly) ...[
                const _FilterHeading('Money owed to you'),
                _SelectChip(
                  label: 'Owed: ${formatPeso(presenter.outstandingOwedTotal)}',
                  selected: presenter.owedOnly,
                  onTap: () => presenter.setOwedFilter(!presenter.owedOnly),
                ),
                const SizedBox(height: 16),
              ],
              // Accounts + Categories always show (with an empty hint) so the
              // filter dimensions are never a mystery — even before any account
              // or category exists on this device.
              const _FilterHeading('Accounts'),
              if (presenter.accounts.isEmpty)
                const _FilterEmptyHint('No accounts yet')
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final a in presenter.accounts)
                      _SelectChip(
                        label: a.name,
                        selected: presenter.selectedAccountIds.contains(a.id),
                        onTap: () => presenter.toggleAccountFilter(a.id),
                      ),
                  ],
                ),
              const SizedBox(height: 16),
              const _FilterHeading('Categories'),
              if (expense.isEmpty && income.isEmpty)
                const _FilterEmptyHint('No categories yet')
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in [...expense, ...income])
                      _SelectChip(
                        label: c.name,
                        dotColor: resolveSliceColor(c.colorHex, 0,
                            brightness: brightness),
                        selected: presenter.selectedCategoryIds.contains(c.id),
                        onTap: () => presenter.toggleCategoryFilter(c.id),
                      ),
                  ],
                ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: AppSecondaryButton(
                      label: 'Clear all',
                      onPressed: presenter.activeFilterCount == 0
                          ? null
                          : presenter.clearAllFilters,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppPrimaryButton(
                      label: 'Done',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FilterHeading extends StatelessWidget {
  final String text;
  const _FilterHeading(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: context.appColors.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
      ),
    );
  }
}

class _FilterEmptyHint extends StatelessWidget {
  final String text;
  const _FilterEmptyHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.appColors.textMuted,
            ),
      ),
    );
  }
}

class _SelectChip extends StatelessWidget {
  final String label;
  final Color? dotColor;
  final bool selected;
  final VoidCallback onTap;

  const _SelectChip({
    required this.label,
    this.dotColor,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary.withValues(alpha: 0.15)
              : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? cs.primary : cs.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dotColor != null) ...[
              Container(
                width: 9,
                height: 9,
                decoration:
                    BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? cs.primary : cs.onSurface,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 6),
              Icon(Icons.check_rounded, size: 14, color: cs.primary),
            ],
          ],
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
                // Reference-style bordered month pill with a caret.
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
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
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: cs.onSurfaceVariant,
                        size: 18,
                      ),
                    ],
                  ),
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

/// Builds one transaction row — account/category resolved, swipe-to-delete with
/// undo. Shared by the day-grouped list and the flat (amount-sorted) list.
Widget _buildTxnTile(
  BuildContext context,
  LedgerPresenter presenter,
  TransactionRecord txn,
  void Function(TransactionRecord txn) onEdit,
) {
  final account =
      presenter.accounts.where((a) => a.id == txn.accountId).firstOrNull;
  final category =
      presenter.categories.where((c) => c.id == txn.categoryId).firstOrNull;
  final idx = presenter.accounts.indexWhere((a) => a.id == txn.accountId);
  final accountColor = idx < 0
      ? null
      : resolveSliceColor(presenter.accounts[idx].colorHex, idx,
          brightness: Theme.of(context).brightness);
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: AppCard(
      variant: AppCardVariant.filled,
      padding: EdgeInsets.zero,
      child: TransactionListTile(
        key: ValueKey(txn.id),
        txn: txn,
        account: account,
        accountColor: accountColor,
        category: category,
        onTap: () => onEdit(txn),
        onDelete: () {
          HapticFeedback.mediumImpact();
          final deleted = txn;
          presenter.deleteTransaction(deleted.id);
          AppToast.action(
            context,
            message: 'Deleted "${deleted.description}"',
            actionLabel: 'Undo',
            onAction: () => presenter.restoreTransaction(deleted),
          );
        },
      ),
    ),
  );
}

class _TransactionList extends StatelessWidget {
  final LedgerPresenter presenter;
  final void Function(TransactionRecord txn) onEditTransaction;

  const _TransactionList({
    required this.presenter,
    required this.onEditTransaction,
  });

  static const _empty = AppEmptyState(
    icon: Icons.receipt_long_outlined,
    title: 'No transactions this month',
    body: 'Tap + to log your first one',
  );

  @override
  Widget build(BuildContext context) {
    // Amount sort → a flat list ordered by amount (day grouping doesn't apply).
    if (presenter.sortField == LedgerSortField.amount) {
      final txns = presenter.sortedTransactions;
      if (txns.isEmpty) return _empty;
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
        itemCount: txns.length,
        itemBuilder: (context, i) =>
            _buildTxnTile(context, presenter, txns[i], onEditTransaction),
      );
    }

    // Date sort → day-grouped; the presenter already ordered the day keys.
    final grouped = presenter.groupedTransactions;
    if (grouped.isEmpty) return _empty;
    final dates = grouped.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: dates.length,
      itemBuilder: (context, index) {
        final date = dates[index];
        return _DateGroup(
          date: date,
          transactions: grouped[date]!,
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
            ...transactions.map((txn) =>
                _buildTxnTile(context, presenter, txn, onEditTransaction)),
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
