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
          // The module hides its "TREASURY" app bar on this tab, so the Ledger
          // owns the top: keep the top safe-area inset here to clear the status
          // bar under the "Ledger" title.
          body: SafeArea(
            child: Column(
              children: [
                const _LedgerHeader(),
                _LedgerControlsRow(
                  presenter: presenter,
                  onOpenFilters: _showFilterSortSheet,
                ),
                _SummaryStrip(presenter: presenter),
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
          12, 10, 12, MediaQuery.of(context).padding.bottom + 10),
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
              height: 52,
              padding: const EdgeInsets.only(left: 14, right: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(26),
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
                  width: 48,
                  height: 48,
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

/// Page title row — `Ledger` on its own line, left-aligned (reference header).
class _LedgerHeader extends StatelessWidget {
  const _LedgerHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(20, 13, 20, 0),
      child: Text(
        'Ledger',
        style: theme.textTheme.headlineSmall?.copyWith(
          fontSize: 23,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// Controls row: the `Filter & sort` pill (+ quick-clear ✕) on the left and the
/// month/year pill on the right, **in line** on one row (spec §2).
class _LedgerControlsRow extends StatelessWidget {
  final LedgerPresenter presenter;
  final VoidCallback onOpenFilters;

  const _LedgerControlsRow({
    required this.presenter,
    required this.onOpenFilters,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      // Expanded left cluster + natural-width month pill: guarantees the two
      // pills never overflow on narrow screens (the filter label ellipsizes
      // under pressure instead of throwing a RenderFlex overflow).
      child: Row(
        children: [
          Expanded(
            child: _FilterSortButton(
              presenter: presenter,
              onOpenFilters: onOpenFilters,
            ),
          ),
          const SizedBox(width: 8),
          _MonthPill(presenter: presenter),
        ],
      ),
    );
  }
}

/// The `Filter & sort` pill with an active-count badge (opens [_FilterSortSheet])
/// plus a quick-clear ✕ that wipes active filters without opening the sheet.
class _FilterSortButton extends StatelessWidget {
  final LedgerPresenter presenter;
  final VoidCallback onOpenFilters;

  const _FilterSortButton({
    required this.presenter,
    required this.onOpenFilters,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final blue = context.appColors.fast;
    final count = presenter.activeFilterCount;
    final active = count > 0 || presenter.isCustomSort;
    // Inside an Expanded (see _LedgerControlsRow): a loose Flexible lets the pill
    // size to its content but shrink (label ellipsizes) if space is tight, so it
    // never overflows the row on a narrow screen.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: GestureDetector(
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
                  Flexible(
                    child: Text(
                      'Filter & sort',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: active ? blue : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
    );
  }
}

/// The Filter & sort bottom sheet: multi-select categories + accounts, the owed
/// toggle, and Date/Amount sort with direction. Applies live via the presenter.
/// Opens the spending-heat calendar to pick a single day within the selected
/// month (tapping the active day again clears it). Used by the Day filter.
Future<void> _pickLedgerDay(
    BuildContext context, LedgerPresenter presenter) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16),
      child: SpendingCalendar(
        presenter: presenter,
        onDaySelected: (day) {
          final cur = presenter.selectedDate;
          final same = cur != null &&
              cur.year == day.year &&
              cur.month == day.month &&
              cur.day == day.day;
          presenter.setSelectedDate(same ? null : day);
          Navigator.of(ctx).pop();
        },
      ),
    ),
  );
}

/// Opens the month grid to change the selected month from inside the sheet.
Future<void> _pickLedgerMonth(
    BuildContext context, LedgerPresenter presenter) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: _MonthGridPicker(
        presenter: presenter,
        onPicked: () => Navigator.of(ctx).pop(),
      ),
    ),
  );
}

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
              const _FilterHeading('Month'),
              _SelectChip(
                label: monthLabel(presenter.selectedMonth),
                selected: false,
                onTap: () => _pickLedgerMonth(context, presenter),
              ),
              const SizedBox(height: 16),
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
              const _FilterHeading('Day'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _SelectChip(
                    label: 'Any day',
                    selected: presenter.selectedDate == null,
                    onTap: () => presenter.setSelectedDate(null),
                  ),
                  _SelectChip(
                    label: presenter.selectedDate != null
                        ? _filterChipFmt.format(presenter.selectedDate!)
                        : 'Pick a day…',
                    selected: presenter.selectedDate != null,
                    onTap: () => _pickLedgerDay(context, presenter),
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

// ── Month / Year Switcher ────────────────────────────────────────────────────

/// A tappable month/year pill (reference, top-right) that opens a month-grid
/// popover with year navigation — pick any month the way you'd pick a day on the
/// calendar. Lives on the right of [_LedgerControlsRow], in line with the filter
/// pill.
class _MonthPill extends StatefulWidget {
  final LedgerPresenter presenter;

  const _MonthPill({required this.presenter});

  @override
  State<_MonthPill> createState() => _MonthPillState();
}

class _MonthPillState extends State<_MonthPill> {
  final _pillKey = GlobalKey();

  Future<void> _openPicker() async {
    HapticFeedback.selectionClick();
    final box = _pillKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final offset = box.localToGlobal(Offset.zero);
    final topOffset = offset.dy + box.size.height + 8;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (ctx) => _MonthPickerPopover(
        presenter: widget.presenter,
        topOffset: topOffset,
        onDismiss: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      key: _pillKey,
      onTap: _openPicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
              monthLabel(widget.presenter.selectedMonth),
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down_rounded,
                color: cs.onSurfaceVariant, size: 16),
          ],
        ),
      ),
    );
  }
}

/// Anchored popover: a year header (‹ 2026 ›) + a 3-column grid of the twelve
/// months. Selecting a month sets it and closes.
class _MonthPickerPopover extends StatelessWidget {
  final LedgerPresenter presenter;
  final double topOffset;
  final VoidCallback onDismiss;

  const _MonthPickerPopover({
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
          onTap: () {},
          child: Container(
            width: 300,
            margin: EdgeInsets.only(top: topOffset, left: 12, right: 12),
            child: _MonthGridPicker(presenter: presenter, onPicked: onDismiss),
          ),
        ),
      ),
    );
  }
}

/// Year header (‹ 2026 ›) + a 3-column grid of the twelve months. Selecting a
/// month sets it on the presenter and calls [onPicked]. Reused by the header
/// popover and the Filter & sort sheet's Month control.
class _MonthGridPicker extends StatefulWidget {
  final LedgerPresenter presenter;
  final VoidCallback onPicked;

  const _MonthGridPicker({required this.presenter, required this.onPicked});

  @override
  State<_MonthGridPicker> createState() => _MonthGridPickerState();
}

class _MonthGridPickerState extends State<_MonthGridPicker> {
  late int _year;
  late final int _selYear;
  late final int _selMonth;

  @override
  void initState() {
    super.initState();
    final parts = widget.presenter.selectedMonth.split('-');
    _selYear = int.parse(parts[0]);
    _selMonth = int.parse(parts[1]);
    _year = _selYear;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final now = DateTime.now();
    return AppCard(
      variant: AppCardVariant.elevated,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: IconButton(
                  icon: Icon(Icons.chevron_left, color: cs.onSurfaceVariant),
                  tooltip: 'Previous year',
                  onPressed: () => setState(() => _year--),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text('$_year',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
              ),
              SizedBox(
                width: 40,
                height: 40,
                child: IconButton(
                  icon: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                  tooltip: 'Next year',
                  onPressed: () => setState(() => _year++),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            childAspectRatio: 2.2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (var m = 1; m <= 12; m++)
                _MonthCell(
                  label: DateFormat('MMM').format(DateTime(_year, m)),
                  selected: _year == _selYear && m == _selMonth,
                  isCurrent: _year == now.year && m == now.month,
                  onTap: () {
                    widget.presenter
                        .setMonth('$_year-${m.toString().padLeft(2, '0')}');
                    widget.onPicked();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MonthCell extends StatelessWidget {
  final String label;
  final bool selected;
  final bool isCurrent;
  final VoidCallback onTap;

  const _MonthCell({
    required this.label,
    required this.selected,
    required this.isCurrent,
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
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? cs.primary.withValues(alpha: 0.15)
              : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? cs.primary
                : (isCurrent
                    ? cs.primary.withValues(alpha: 0.5)
                    : cs.outlineVariant.withValues(alpha: 0.5)),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? cs.primary : cs.onSurface,
          ),
        ),
      ),
    );
  }
}

// ── Summary Card ─────────────────────────────────────────────────────────────

/// Segmented IN / OUT / NET strip (reference) — one card split into three equal
/// columns by hairline dividers. Values come straight from the presenter.
class _SummaryStrip extends StatelessWidget {
  final LedgerPresenter presenter;

  const _SummaryStrip({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final net = presenter.filteredMonthNet;
    // NET is blue when non-negative; red when the month is in deficit (spec §3).
    final netColor = net < 0 ? cs.error : context.appColors.fast;
    final netPrefix = net > 0 ? '+' : (net < 0 ? '−' : '');

    return Container(
      width: double.infinity,
      color: theme.scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: cs.outlineVariant),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        child: IntrinsicHeight(
          child: Row(
            children: [
              _SummarySegment(
                label: 'IN',
                value: formatPeso(presenter.filteredMonthInflow),
                color: cs.tertiary,
              ),
              _SummaryDivider(color: cs.outlineVariant),
              _SummarySegment(
                label: 'OUT',
                value: formatPeso(presenter.filteredMonthOutflow),
                color: cs.error,
              ),
              _SummaryDivider(color: cs.outlineVariant),
              _SummarySegment(
                label: 'NET',
                value: '$netPrefix${formatPeso(net.abs())}',
                color: netColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryDivider extends StatelessWidget {
  final Color color;
  const _SummaryDivider({required this.color});

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, color: color, margin: const EdgeInsets.symmetric(horizontal: 4));
}

class _SummarySegment extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummarySegment({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: context.appColors.textTertiary,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTextStyles.mono(
              textStyle: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
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
  // Reference "no background" rows: no per-row card fill — rows sit directly on
  // the screen background, separated only by the list tile's own padding. Swipe
  // -to-delete + undo is preserved by TransactionListTile's onDelete.
  return TransactionListTile(
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
