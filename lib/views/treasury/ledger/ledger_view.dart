import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/utils/app_text_styles.dart';
import 'package:intermittent_fasting/models/ai_coach_context.dart';
import 'package:intermittent_fasting/models/finance/finance_parse_result.dart';
import 'package:intermittent_fasting/presenters/ai_coach_presenter.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/capture_inbox_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/views/treasury/capture/capture_inbox_view.dart';
import 'package:intermittent_fasting/views/widgets/ai_chat_sheet.dart';
import 'package:intermittent_fasting/views/widgets/finance/entry_review_card.dart';
import 'package:intermittent_fasting/presenters/nutrition_presenter.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/ledger/add_transaction_sheet.dart';
import 'package:intermittent_fasting/views/treasury/ledger/manage_categories_sheet.dart';
import 'package:intermittent_fasting/views/treasury/ledger/spending_calendar.dart';
import 'package:intermittent_fasting/views/treasury/ledger/transaction_list_tile.dart';
import 'package:intermittent_fasting/views/treasury/shared/month_stepper_pill.dart';
import 'package:intermittent_fasting/views/treasury/shared/month_year_picker.dart';
import 'package:intermittent_fasting/views/treasury/shared/photo_log_sheet.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class LedgerView extends StatefulWidget {
  final LedgerPresenter presenter;

  /// When present, the quick-log photo button also offers meal logging.
  final NutritionPresenter? nutrition;

  /// When present, the input bar's sparkle opens Nudgy over the Ledger.
  final AiCoachPresenter? aiCoach;

  /// Capture Inbox (Plan 070). When present and active, the controls row
  /// shows an `Inbox · n` pill that opens the review list.
  final CaptureInboxPresenter? captureInbox;

  const LedgerView({
    super.key,
    required this.presenter,
    this.nutrition,
    this.aiCoach,
    this.captureInbox,
  });

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
      // Quick-log always dates "today", so logging while reading an older month
      // jumps the list to the current one. Say so — moving the user's reading
      // position without a word reads as the list glitching.
      final snappedFrom = presenter.lastCommitSnappedFromMonth;
      AppToast.show(
        context,
        snappedFrom == null
            ? summary
            : '$summary — dated today, so the list moved from '
                '${monthLabel(snappedFrom)} to '
                '${monthLabel(presenter.selectedMonth)}.',
        duration: Duration(seconds: snappedFrom == null ? 2 : 4),
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

  void _showEditTransactionSheet(
    TransactionRecord txn, {
    bool split = false,
    bool reimbursable = false,
  }) {
    AppBottomSheet.show(
      context: context,
      title: 'Edit Transaction',
      body: AddTransactionSheet(
        presenter: presenter,
        existing: txn,
        initialSplit: split,
        initialReimbursable: reimbursable,
      ),
    );
  }

  /// Row action "Duplicate": a new entry prefilled from [txn], dated today.
  void _showDuplicateTransactionSheet(TransactionRecord txn) {
    AppBottomSheet.show(
      context: context,
      title: 'Log Transaction',
      body: AddTransactionSheet(presenter: presenter, duplicateOf: txn),
    );
  }

  late final _rowHandlers = _LedgerRowHandlers(
    onEdit: _showEditTransactionSheet,
    onDuplicate: _showDuplicateTransactionSheet,
    onSplit: (t) => _showEditTransactionSheet(t, split: true),
    onReimbursable: (t) => _showEditTransactionSheet(t, reimbursable: true),
  );

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
      trailing: _ResetFiltersButton(presenter: presenter),
      body: _FilterSortSheet(presenter: presenter),
      primaryAction: _ShowResultsButton(presenter: presenter),
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
                _LedgerHeader(presenter: presenter),
                _LedgerControlsRow(
                  presenter: presenter,
                  captureInbox: widget.captureInbox,
                  onOpenFilters: _showFilterSortSheet,
                ),
                _ActiveFilterChipsRow(presenter: presenter),
                // In / Out / Net moved to the Dashboard's cashflow strip — no
                // need to duplicate the month totals on the Ledger.
                Expanded(
                  child: _TransactionList(
                    presenter: presenter,
                    handlers: _rowHandlers,
                  ),
                ),
                _ChatHardErrorChip(presenter: presenter),
                _LedgerChatDrawer(presenter: presenter),
                _LedgerChatInputBar(
                  presenter: presenter,
                  nutrition: widget.nutrition,
                  aiCoach: widget.aiCoach,
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
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                border: Border(
                  top: BorderSide(color: cs.outlineVariant, width: 1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Transcript(turns: state.turns),
                  const SizedBox(height: 6),
                  if (state.entries.isNotEmpty)
                    EntryReviewCard(ledger: presenter, state: state)
                  else if (state.lastStep is StepClarify)
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
    // Show last 2 turns only — anything older isn't load-bearing for the
    // user's decision, and above a keyboard the drawer is competing with the
    // entry rows for what height there is. Each turn is capped at two lines
    // for the same reason: a long paste shouldn't push the Log button off
    // screen.
    final visible = turns.length > 2 ? turns.sublist(turns.length - 2) : turns;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final t in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: t.isUser ? 'You: ' : 'AI: ',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                  TextSpan(
                    text: t.text,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
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
  final NutritionPresenter? nutrition;
  final AiCoachPresenter? aiCoach;
  final void Function({ParsedTransaction? prefill}) onOpenForm;
  final VoidCallback onOpenCategories;

  const _LedgerChatInputBar({
    required this.presenter,
    required this.onOpenForm,
    required this.onOpenCategories,
    this.nutrition,
    this.aiCoach,
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

  /// Open Nudgy as a sheet over the Ledger, the same way the Hub's quick-log
  /// bar does. Nudgy is not tied to today, so this stays enabled on past days.
  void _openAdvisor() {
    final coach = widget.aiCoach;
    if (coach == null) return;
    _focus.unfocus();
    AiChatSheet.show(
      context,
      presenter: coach,
      entryPoint: AiCoachEntryPoint.financeAdvisor,
    );
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
          IconButton(
            icon: Icon(Icons.photo_camera_outlined, color: cs.onSurfaceVariant),
            // Receipt scanning stamps today, like the typed quick-log, so it's
            // gated to the current day too.
            onPressed: canSend
                ? () => showPhotoLogSheet(
                      context,
                      ledger: widget.presenter,
                      nutrition: widget.nutrition,
                    )
                : null,
            // Say WHY it's greyed out. A disabled button with an unchanged
            // tooltip reads as broken rather than deliberately unavailable.
            tooltip: canSend
                ? 'Scan a receipt'
                : 'Receipts are dated today — use the form to log on this day',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
          // Reference-style input pill: a sparkle glyph hinting at AI parsing +
          // the free-text field, inside a single rounded container. With Nudgy
          // wired in, the sparkle is the button that opens it — no extra slot
          // in a row that already holds four 44px targets.
          Expanded(
            child: Container(
              height: 52,
              padding: EdgeInsets.only(
                  left: widget.aiCoach == null ? 14 : 4, right: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  if (widget.aiCoach == null) ...[
                    Icon(Icons.auto_awesome, size: 16, color: blue),
                    const SizedBox(width: 8),
                  ] else
                    IconButton(
                      icon: Icon(Icons.auto_awesome, size: 20, color: blue),
                      onPressed: busy ? null : _openAdvisor,
                      tooltip: 'Ask Nudgy',
                      constraints:
                          const BoxConstraints(minWidth: 44, minHeight: 44),
                    ),
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

/// Page title row — `Ledger` on its own line, left-aligned (reference header)
/// with a search icon on the right. The icon opens the search (Plan 071
/// Phase 10a): the field takes the title's place and a "This month / All
/// months" scope row appears under it, so a closed search costs no height.
class _LedgerHeader extends StatefulWidget {
  final LedgerPresenter presenter;
  const _LedgerHeader({required this.presenter});

  @override
  State<_LedgerHeader> createState() => _LedgerHeaderState();
}

class _LedgerHeaderState extends State<_LedgerHeader> {
  late final _ctrl = TextEditingController(text: widget.presenter.searchQuery);
  final _focus = FocusNode();

  /// Open while the user is searching. Starts open when the presenter still
  /// holds a search from an earlier visit.
  late bool _open = widget.presenter.isSearching;

  @override
  void didUpdateWidget(covariant _LedgerHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The search can be cleared from outside the field (the empty list's
    // Clear search button). Follow it, without fighting a trailing space the
    // user is still typing.
    final query = widget.presenter.searchQuery;
    if (_ctrl.text.trim() != query) _ctrl.text = query;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _openSearch() {
    HapticFeedback.selectionClick();
    setState(() => _open = true);
    // The field exists from the next frame on.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _closeSearch() {
    _ctrl.clear();
    widget.presenter.clearSearch();
    _focus.unfocus();
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.scaffoldBackgroundColor,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: _open
            ? _LedgerSearchBar(
                presenter: widget.presenter,
                controller: _ctrl,
                focusNode: _focus,
                onClose: _closeSearch,
              )
            : _LedgerTitleRow(onOpenSearch: _openSearch),
      ),
    );
  }
}

class _LedgerTitleRow extends StatelessWidget {
  final VoidCallback onOpenSearch;
  const _LedgerTitleRow({required this.onOpenSearch});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPop = Navigator.canPop(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(canPop ? 4 : 20, 2, 8, 0),
      child: Row(
        children: [
          if (canPop)
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back',
              onPressed: () => Navigator.maybePop(context),
            ),
          Expanded(
            child: Text(
              'Ledger',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontSize: 23,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('ledgerSearchOpen'),
            icon: Icon(
              Icons.search_rounded,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            tooltip: 'Search transactions',
            onPressed: onOpenSearch,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
        ],
      ),
    );
  }
}

/// The open search: the field with a close button, then the scope row.
class _LedgerSearchBar extends StatelessWidget {
  final LedgerPresenter presenter;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onClose;

  const _LedgerSearchBar({
    required this.presenter,
    required this.controller,
    required this.focusNode,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.only(left: 12, right: 12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded,
                          size: 18, color: cs.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('ledgerSearchField'),
                          controller: controller,
                          focusNode: focusNode,
                          onChanged: presenter.setSearch,
                          textInputAction: TextInputAction.search,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: cs.onSurface),
                          decoration: const InputDecoration(
                            hintText: 'Search description, note, amount…',
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('ledgerSearchClose'),
                icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                tooltip: 'Close search',
                onPressed: onClose,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                _SearchScopeSegment(
                  key: const ValueKey('ledgerSearchScopeMonth'),
                  label: 'This month',
                  selected: !presenter.searchAllMonths,
                  onTap: () => presenter.setSearchAllMonths(false),
                ),
                const SizedBox(width: 8),
                _SearchScopeSegment(
                  key: const ValueKey('ledgerSearchScopeAll'),
                  label: 'All months',
                  selected: presenter.searchAllMonths,
                  onTap: () => presenter.setSearchAllMonths(true),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    presenter.searchSummary,
                    key: const ValueKey('ledgerSearchSummary'),
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One half of the search scope switch. The pill reads small; the tap area
/// is the full 44 px row height.
class _SearchScopeSegment extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SearchScopeSegment({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Search $label',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: kControlPillHeight,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? cs.primary.withValues(alpha: 0.15)
                    : cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: selected ? cs.primary : cs.outlineVariant),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Controls row: the `Filter & sort` pill (+ quick-clear ✕) on the left and the
/// month/year pill on the right, **in line** on one row (spec §2).
class _LedgerControlsRow extends StatelessWidget {
  final LedgerPresenter presenter;
  final CaptureInboxPresenter? captureInbox;
  final VoidCallback onOpenFilters;

  const _LedgerControlsRow({
    required this.presenter,
    required this.onOpenFilters,
    this.captureInbox,
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
          if (captureInbox != null) ...[
            const SizedBox(width: 8),
            _InboxPill(presenter: captureInbox!),
          ],
          const SizedBox(width: 8),
          MonthStepperPill(
            month: presenter.selectedMonth,
            onTap: () async {
              final picked = await showMonthYearPicker(
                context,
                monthKey: presenter.selectedMonth,
              );
              if (picked != null && picked != presenter.selectedMonth) {
                presenter.setMonth(picked);
              }
            },
            onMonthChanged: presenter.setMonth,
          ),
        ],
      ),
    );
  }
}

/// `Inbox · n` — the Capture Inbox entry (Plan 070). Hidden while capture is
/// off and nothing is pending, so a user who never turned it on never sees it.
class _InboxPill extends StatelessWidget {
  final CaptureInboxPresenter presenter;
  const _InboxPill({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) {
        if (!presenter.hasPresence) return const SizedBox.shrink();
        final count = presenter.pendingCount;
        final active = count > 0;
        final accent = cs.primary;
        return Semantics(
          button: true,
          label: 'Capture inbox, $count waiting',
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CaptureInboxView(presenter: presenter),
              ));
            },
            child: Container(
              height: kControlPillHeight,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: active
                    ? accent.withValues(alpha: 0.15)
                    : cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: active ? accent : cs.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.move_to_inbox_outlined,
                      size: 15, color: active ? accent : cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    'Inbox',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: active ? accent : cs.onSurfaceVariant,
                    ),
                  ),
                  if (active) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: cs.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
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

/// One removable chip per active filter, scrolling sideways under the
/// controls row, so a filter can be dropped without opening the sheet.
/// Collapses to nothing when no filter is on.
class _ActiveFilterChipsRow extends StatelessWidget {
  final LedgerPresenter presenter;
  const _ActiveFilterChipsRow({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final chips = presenter.activeFilterChips;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: chips.isEmpty
          ? const SizedBox(width: double.infinity)
          : SizedBox(
              height: 44,
              child: ListView.separated(
                key: const ValueKey('ledgerFilterChips'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: chips.length,
                separatorBuilder: (context, i) => const SizedBox(width: 8),
                itemBuilder: (context, i) => _RemovableFilterChip(
                  chip: chips[i],
                  onRemove: () => presenter.removeFilterChip(chips[i]),
                ),
              ),
            ),
    );
  }
}

class _RemovableFilterChip extends StatelessWidget {
  final LedgerFilterChip chip;
  final VoidCallback onRemove;
  const _RemovableFilterChip({required this.chip, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Remove filter ${chip.label}',
      excludeSemantics: true,
      child: Material(
        color: cs.primary.withValues(alpha: 0.12),
        shape: StadiumBorder(side: BorderSide(color: cs.primary)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () {
            HapticFeedback.selectionClick();
            onRemove();
          },
          // The whole chip removes it: a 44 px row height keeps the target
          // big enough, where a lone ✕ glyph would not be.
          child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  chip.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.close_rounded, size: 16, color: cs.primary),
              ],
            ),
          ),
        ),
      ),
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
  final picked = await showMonthYearPicker(
    context,
    monthKey: presenter.selectedMonth,
  );
  if (picked != null && picked != presenter.selectedMonth) {
    presenter.setMonth(picked);
  }
}

/// The Filter & sort sheet. Short on purpose: the order as one segmented
/// control, then one row each for Month, Day, Accounts and Categories that
/// shows its current value. Accounts and Categories open their own pickers
/// instead of laying every option out here. Everything applies live; the
/// footer button shows how many records the list will show.
class _FilterSortSheet extends StatelessWidget {
  final LedgerPresenter presenter;
  const _FilterSortSheet({required this.presenter});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _FilterHeading('Sort by'),
            AppSegmentedControl<LedgerSortOption>(
              key: const ValueKey('ledgerSortControl'),
              segments: [
                for (final o in LedgerSortOption.values)
                  (value: o, label: o.label, icon: null),
              ],
              selected: presenter.sortOption,
              onChanged: presenter.setSortOption,
              // Four labels share a phone-width row: trim the side padding so
              // "Smallest" keeps to one line at larger text sizes.
              style: SegmentedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
            ),
            const SizedBox(height: 24),
            const _FilterHeading('Show'),
            _FilterCard(
              children: [
                _FilterRow(
                  key: const ValueKey('ledgerFilterMonth'),
                  icon: Icons.calendar_month_outlined,
                  label: 'Month',
                  value: presenter.monthFilterLabel,
                  onTap: () => _pickLedgerMonth(context, presenter),
                ),
                _FilterRow(
                  key: const ValueKey('ledgerFilterDay'),
                  icon: Icons.today_outlined,
                  label: 'Day',
                  value: presenter.dayFilterLabel,
                  active: presenter.hasDayFilter,
                  onTap: () => _pickLedgerDay(context, presenter),
                  onClear: () => presenter.setSelectedDate(null),
                ),
                _FilterRow(
                  key: const ValueKey('ledgerFilterAccounts'),
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Accounts',
                  value: presenter.accountFilterSummary,
                  active: presenter.hasAccountFilter,
                  onTap: () => _showAccountFilterPicker(context, presenter),
                  onClear: presenter.clearAccountFilters,
                ),
                _FilterRow(
                  key: const ValueKey('ledgerFilterCategories'),
                  icon: Icons.category_outlined,
                  label: 'Categories',
                  value: presenter.categoryFilterSummary,
                  active: presenter.hasCategoryFilter,
                  onTap: () => _showCategoryFilterPicker(context, presenter),
                  onClear: presenter.clearCategoryFilters,
                ),
              ],
            ),
            if (presenter.showsOwedFilter) ...[
              const SizedBox(height: 12),
              _FilterCard(
                children: [_OwedFilterRow(presenter: presenter)],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Reset" in the sheet header: clears every filter and the order. Disabled
/// when there is nothing to reset.
class _ResetFiltersButton extends StatelessWidget {
  final LedgerPresenter presenter;
  const _ResetFiltersButton({required this.presenter});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) => TextButton(
        key: const ValueKey('ledgerFilterReset'),
        onPressed:
            presenter.canResetFilters ? presenter.resetFiltersAndSort : null,
        style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
        child: const Text('Reset'),
      ),
    );
  }
}

/// The sheet's footer button: 'Show 23 transactions', live as filters change.
class _ShowResultsButton extends StatelessWidget {
  final LedgerPresenter presenter;
  const _ShowResultsButton({required this.presenter});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) => AppPrimaryButton(
        key: const ValueKey('ledgerFilterShowResults'),
        label: presenter.showResultsLabel,
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
}

/// A rounded group of rows on the sheet (card on a sheet → container high),
/// with a hairline between rows.
class _FilterCard extends StatelessWidget {
  final List<Widget> children;
  const _FilterCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: 52,
                  color: cs.outlineVariant,
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// One row of the sheet: icon, label, the current value on the right, and a
/// chevron — or a clear (✕) button once this filter is on.
class _FilterRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  /// This filter is on: the value is drawn in the accent and ✕ replaces the
  /// chevron.
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _FilterRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.active = false,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final clear = onClear;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 4),
          child: Row(
            children: [
              Icon(icon, size: 20, color: cs.onSurfaceVariant),
              const SizedBox(width: 16),
              Text(label, style: theme.textTheme.bodyLarge),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: active ? cs.primary : cs.onSurfaceVariant,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (active && clear != null)
                IconButton(
                  tooltip: 'Clear $label',
                  onPressed: clear,
                  icon: Icon(Icons.close_rounded,
                      size: 18, color: cs.onSurfaceVariant),
                )
              else
                SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(Icons.chevron_right_rounded,
                      color: cs.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Only money owed to you" as a switch, with what is still owed under it.
class _OwedFilterRow extends StatelessWidget {
  final LedgerPresenter presenter;
  const _OwedFilterRow({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      onTap: () => presenter.setOwedFilter(!presenter.owedOnly),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          child: Row(
            children: [
              Icon(Icons.handshake_outlined,
                  size: 20, color: cs.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Only money owed to you',
                        style: theme.textTheme.bodyLarge),
                    Text(
                      presenter.owedFilterDetail,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Switch(
                key: const ValueKey('ledgerFilterOwed'),
                value: presenter.owedOnly,
                onChanged: presenter.setOwedFilter,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the account picker over the Filter & sort sheet.
void _showAccountFilterPicker(BuildContext context, LedgerPresenter presenter) {
  AppBottomSheet.show(
    context: context,
    title: 'Accounts',
    trailing: _ClearPickerButton(
      presenter: presenter,
      enabled: () => presenter.hasAccountFilter,
      onClear: presenter.clearAccountFilters,
    ),
    body: _AccountFilterPicker(presenter: presenter),
    primaryAction: _PickerDoneButton(),
  );
}

/// Opens the category picker over the Filter & sort sheet.
void _showCategoryFilterPicker(
    BuildContext context, LedgerPresenter presenter) {
  AppBottomSheet.show(
    context: context,
    title: 'Categories',
    trailing: _ClearPickerButton(
      presenter: presenter,
      enabled: () => presenter.hasCategoryFilter,
      onClear: presenter.clearCategoryFilters,
    ),
    body: _CategoryFilterPicker(presenter: presenter),
    primaryAction: _PickerDoneButton(),
  );
}

/// "Clear" in a picker's header; disabled when nothing is picked.
class _ClearPickerButton extends StatelessWidget {
  final LedgerPresenter presenter;
  final bool Function() enabled;
  final VoidCallback onClear;

  const _ClearPickerButton({
    required this.presenter,
    required this.enabled,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) => TextButton(
        onPressed: enabled() ? onClear : null,
        style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
        child: const Text('Clear'),
      ),
    );
  }
}

class _PickerDoneButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) => AppPrimaryButton(
        label: 'Done',
        onPressed: () => Navigator.of(context).pop(),
      );
}

/// Accounts grouped by kind, each with a checkbox. No pick means all
/// accounts.
class _AccountFilterPicker extends StatelessWidget {
  final LedgerPresenter presenter;
  const _AccountFilterPicker({required this.presenter});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) => _FilterGroupList(
        groups: presenter.accountFilterGroups,
        emptyText: 'No accounts yet',
        onToggle: presenter.toggleAccountFilter,
      ),
    );
  }
}

/// Categories with "Used this month" first, plus a search box when the list
/// is long. No pick means all categories.
class _CategoryFilterPicker extends StatefulWidget {
  final LedgerPresenter presenter;
  const _CategoryFilterPicker({required this.presenter});

  @override
  State<_CategoryFilterPicker> createState() => _CategoryFilterPickerState();
}

class _CategoryFilterPickerState extends State<_CategoryFilterPicker> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final presenter = widget.presenter;
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (presenter.categoryFilterNeedsSearch) ...[
            AppTextField(
              key: const ValueKey('ledgerCategorySearch'),
              controller: _search,
              hint: 'Search categories',
              prefixIcon: Icons.search_rounded,
              textInputAction: TextInputAction.search,
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 12),
          ],
          Flexible(
            child: _FilterGroupList(
              groups: presenter.categoryFilterGroups(_query),
              emptyText: 'No categories match',
              onToggle: presenter.toggleCategoryFilter,
            ),
          ),
        ],
      ),
    );
  }
}

/// The sections of a picker, each as a heading and a card of checkbox rows.
class _FilterGroupList extends StatelessWidget {
  final List<LedgerFilterGroup> groups;
  final String emptyText;
  final ValueChanged<String> onToggle;

  const _FilterGroupList({
    required this.groups,
    required this.emptyText,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: _FilterEmptyHint(emptyText),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var g = 0; g < groups.length; g++) ...[
            if (g > 0) const SizedBox(height: 20),
            _FilterHeading(groups[g].title),
            _FilterCard(
              children: [
                for (final o in groups[g].options)
                  _FilterOptionRow(
                    key: ValueKey('ledgerFilterOption.${o.id}'),
                    option: o,
                    onTap: () => onToggle(o.id),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One account or category in a picker: color swatch, name, this month's
/// record count, and a checkbox. The whole row is the tap target.
class _FilterOptionRow extends StatelessWidget {
  final LedgerFilterOption option;
  final VoidCallback onTap;

  const _FilterOptionRow(
      {super.key, required this.option, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final swatch = resolveSliceColor(
      option.colorHex,
      option.paletteIndex,
      brightness: theme.brightness,
    );
    return Semantics(
      checked: option.selected,
      button: true,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 4),
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: swatch,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge,
                      ),
                      if (option.detail.isNotEmpty)
                        Text(
                          option.detail,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                IgnorePointer(
                  child: Checkbox(value: option.selected, onChanged: (_) {}),
                ),
              ],
            ),
          ),
        ),
      ),
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
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.appColors.textMuted,
            ),
      ),
    );
  }
}

// ── Summary Card ─────────────────────────────────────────────────────────────

// ── Transaction List ─────────────────────────────────────────────────────────

/// What a ledger row can open: the edit sheet (plain, or with Split or "I'll
/// get this back" switched on) and a prefilled copy.
class _LedgerRowHandlers {
  final void Function(TransactionRecord txn) onEdit;
  final void Function(TransactionRecord txn) onDuplicate;
  final void Function(TransactionRecord txn) onSplit;
  final void Function(TransactionRecord txn) onReimbursable;

  const _LedgerRowHandlers({
    required this.onEdit,
    required this.onDuplicate,
    required this.onSplit,
    required this.onReimbursable,
  });
}

/// The row's account swatch: the account's own colour, else its palette slot.
/// Null when the record has no account.
Color? _accountColorOf(
    BuildContext context, LedgerPresenter presenter, String accountId) {
  final account = presenter.accountById(accountId);
  if (account == null) return null;
  return resolveSliceColor(
    account.colorHex,
    presenter.accountIndexOf(accountId),
    brightness: Theme.of(context).brightness,
  );
}

/// Builds one transaction row — account/category resolved, swipe-to-delete with
/// undo, long-press row actions. Shared by the day-grouped list and the flat
/// (amount-sorted) list.
Widget _buildTxnTile(
  BuildContext context,
  LedgerPresenter presenter,
  TransactionRecord txn,
  _LedgerRowHandlers handlers,
) {
  // Each row carries its own lighter-grey card fill (see TransactionListTile),
  // so a day's transactions read as a stack of items rather than text on the
  // page. Swipe-to-delete + undo is preserved by TransactionListTile's onDelete.
  return TransactionListTile(
    key: ValueKey(txn.id),
    txn: txn,
    account: presenter.accountById(txn.accountId),
    accountColor: _accountColorOf(context, presenter, txn.accountId),
    category: presenter.categoryById(txn.categoryId),
    actions: presenter.rowActionsFor(txn),
    dateLabel: presenter.searchRowDateLabel(txn),
    onTap: () => handlers.onEdit(txn),
    onDuplicate: () => handlers.onDuplicate(txn),
    onSplit: () => handlers.onSplit(txn),
    onReimbursable: () => handlers.onReimbursable(txn),
    onDelete: () async {
      HapticFeedback.mediumImpact();
      final deleted = txn;
      // Transfer-aware: deleting one leg of a transfer must take its partner
      // with it, or the source stays debited while the destination stays
      // credited. The removed set comes back so Undo restores every leg.
      final removed = await presenter.deleteTransactionOrGroup(deleted.id);
      if (removed.isEmpty || !context.mounted) return;
      AppToast.action(
        context,
        message: deleted.transferGroupId != null
            ? 'Deleted transfer "${deleted.description}"'
            : 'Deleted "${deleted.description}"',
        actionLabel: 'Undo',
        onAction: () => presenter.restoreTransactions(removed),
      );
    },
  );
}

class _TransactionList extends StatelessWidget {
  final LedgerPresenter presenter;
  final _LedgerRowHandlers handlers;

  const _TransactionList({
    required this.presenter,
    required this.handlers,
  });

  @override
  Widget build(BuildContext context) {
    final empty = _LedgerEmptyState(presenter: presenter);
    // Amount sort → a flat list ordered by amount (day grouping doesn't apply).
    if (presenter.sortField == LedgerSortField.amount) {
      final txns = presenter.sortedTransactions;
      if (txns.isEmpty) return empty;
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
        itemCount: txns.length,
        itemBuilder: (context, i) =>
            _buildTxnTile(context, presenter, txns[i], handlers),
      );
    }

    // Date sort → day-grouped; the presenter already ordered the day keys.
    final grouped = presenter.groupedTransactions;
    if (grouped.isEmpty) return empty;
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
          handlers: handlers,
        );
      },
    );
  }
}

/// The empty list. When a search or the filters hide every row it says so and
/// offers to clear them; otherwise the month really is empty. There is no +
/// button on the Ledger, so it gives no "tap +" hint.
class _LedgerEmptyState extends StatelessWidget {
  final LedgerPresenter presenter;
  const _LedgerEmptyState({required this.presenter});

  static IconData _iconFor(LedgerEmptyReason reason) => switch (reason) {
        LedgerEmptyReason.search => Icons.search_off_rounded,
        LedgerEmptyReason.filters => Icons.filter_alt_off_outlined,
        LedgerEmptyReason.emptyMonth => Icons.receipt_long_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: _iconFor(presenter.emptyListReason),
      title: presenter.emptyListTitle,
      body: presenter.emptyListBody,
      // No label, no button: AppEmptyState needs both.
      actionLabel: presenter.emptyListActionLabel,
      onAction: presenter.clearEmptyListCause,
    );
  }
}

// ── Date Group ───────────────────────────────────────────────────────────────

class _DateGroup extends StatelessWidget {
  final DateTime date;
  final List<TransactionRecord> transactions;
  final LedgerPresenter presenter;
  final _LedgerRowHandlers handlers;

  const _DateGroup({
    required this.date,
    required this.transactions,
    required this.presenter,
    required this.handlers,
  });

  @override
  Widget build(BuildContext context) {
    final dailyNet = presenter.dailyNetOf(transactions);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: AppSection(
        title: presenter.dateGroupLabel(date),
        trailing: dailyNet != 0 ? _DailyNetBadge(dailyNet: dailyNet) : null,
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Column(
          children: [
            ...transactions
                .map((txn) => _buildTxnTile(context, presenter, txn, handlers)),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
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
    // Sign the value explicitly (U+2212 minus) — a negative day used to read as
    // a plain figure distinguished only by color.
    final prefix = dailyNet > 0 ? '+' : (dailyNet < 0 ? '−' : '');

    return Text(
      '$prefix${formatPeso(dailyNet.abs())}',
      style: AppTextStyles.numeric(fontSize: 11, weight: FontWeight.w600)
          .copyWith(color: netColor),
    );
  }
}
