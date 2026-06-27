import 'package:flutter/material.dart';
import '../../../models/finance/finance_parse_result.dart';
import '../../../presenters/ledger_presenter.dart';
import '../../../presenters/treasury_dashboard_presenter.dart';
import '../../treasury/ledger/add_transaction_sheet.dart';
import '../system/system.dart';
import '../../../app_colors.dart';
import '../../../utils/app_spacing.dart';
import '../../../utils/app_text_styles.dart';
import '../../../utils/finance_format.dart';
import 'hub_card_header.dart';

class TreasuryHubCard extends StatelessWidget {
  const TreasuryHubCard({
    super.key,
    required this.treasury,
    required this.onNavigate,
    this.ledger,
  });

  final TreasuryDashboardPresenter treasury;
  final VoidCallback onNavigate;

  /// When provided, a compact chat bar is shown so an expense can be logged
  /// straight from the hub without opening the full Treasury module. The chat
  /// pipeline (parse → clarify → confirm) is the same one the Ledger uses; this
  /// is just a second, condensed entry point onto it.
  final LedgerPresenter? ledger;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: treasury,
      builder: (context, _) {
        final isActive = treasury.hasBillImminent;
        // The header + snapshot navigate into the module; the chat bar below
        // must NOT, so we wrap only the top region in the tap target instead
        // of putting onTap on the whole AppCard.
        return AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppPressable(
                onTap: onNavigate,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HubCardHeader(
                      icon: isActive
                          ? Icons.account_balance
                          : Icons.account_balance_outlined,
                      title: 'Finance',
                      accentColor: context.appColors.gold,
                      isActive: isActive,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _Snapshot(treasury: treasury, isActive: isActive),
                  ],
                ),
              ),
              if (ledger != null) ...[
                const SizedBox(height: AppSpacing.md),
                _QuickLogChat(ledger: ledger!),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Snapshot extends StatelessWidget {
  const _Snapshot({required this.treasury, required this.isActive});
  final TreasuryDashboardPresenter treasury;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _StatCol(
                  label: 'EXPENSE',
                  // monthTotalOutflow already excludes reimbursables/loans (money
                  // you'll get back isn't spending) and internal transfers.
                  value: formatPesoCompact(treasury.monthTotalOutflow),
                  color: theme.colorScheme.error,
                  align: CrossAxisAlignment.start,
                ),
              ),
              _Divider(theme: theme),
              Expanded(
                child: _StatCol(
                  label: 'INCOME',
                  value: formatPesoCompact(treasury.monthTotalInflow),
                  color: theme.colorScheme.tertiary,
                  align: CrossAxisAlignment.center,
                ),
              ),
              _Divider(theme: theme),
              Expanded(
                child: _StatCol(
                  label: 'ENDING',
                  value: formatPesoCompact(treasury.endingCash),
                  color: treasury.endingCash >= 0
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.error,
                  align: CrossAxisAlignment.end,
                ),
              ),
            ],
          ),
        ),
        if (isActive) ...[
          const SizedBox(height: AppSpacing.sm),
          _BillWarning(treasury: treasury),
        ],
      ],
    );
  }
}

class _StatCol extends StatelessWidget {
  const _StatCol({
    required this.label,
    required this.value,
    required this.color,
    required this.align,
  });
  final String label;
  final String value;
  final Color color;
  final CrossAxisAlignment align;

  TextAlign get _textAlign => switch (align) {
        CrossAxisAlignment.end => TextAlign.end,
        CrossAxisAlignment.center => TextAlign.center,
        _ => TextAlign.start,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.6,
          ),
          textAlign: _textAlign,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.numeric(fontSize: 16, weight: FontWeight.w700)
              .copyWith(color: color),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: _textAlign,
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return VerticalDivider(
      width: AppSpacing.sm,
      thickness: 0.5,
      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
    );
  }
}

class _BillWarning extends StatelessWidget {
  const _BillWarning({required this.treasury});
  final TreasuryDashboardPresenter treasury;

  @override
  Widget build(BuildContext context) {
    final bill = treasury.imminentBill;
    if (bill == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final today = DateTime.now().day;
    final label = bill.dueDay == today ? 'Due today' : 'Due tomorrow';

    return Row(
      children: [
        Icon(Icons.warning_amber_rounded,
            size: 14, color: theme.colorScheme.error),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            '$label · ${bill.name}',
            style: AppTextStyles.bodySmall
                .copyWith(color: theme.colorScheme.error),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── Quick-log chat ────────────────────────────────────────────────────────────
//
// A condensed view onto [LedgerPresenter]'s chat pipeline, embedded in the hub
// card. Sending runs the same parse → clarify → confirm loop as the Ledger;
// because it's the same presenter instance, an unfinished conversation started
// here is picked up seamlessly if the user then opens the full module.

class _QuickLogChat extends StatefulWidget {
  const _QuickLogChat({required this.ledger});

  final LedgerPresenter ledger;

  @override
  State<_QuickLogChat> createState() => _QuickLogChatState();
}

class _QuickLogChatState extends State<_QuickLogChat> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _sending = false;
  String? _lastToastSummary;

  LedgerPresenter get ledger => widget.ledger;

  @override
  void initState() {
    super.initState();
    ledger.addListener(_onLedgerChange);
  }

  @override
  void dispose() {
    ledger.removeListener(_onLedgerChange);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Mirrors the side effects the Ledger view runs on presenter changes:
  /// surface the post-commit toast, and when the AI can't auto-resolve (or AI
  /// is unavailable) open the prefilled form sheet. Both are guarded on route
  /// currency so they don't double up with the Ledger view when the full module
  /// is open on top of the hub.
  void _onLedgerChange() {
    if (!mounted) return;
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    if (!isCurrent) return;

    final summary = ledger.lastCommittedSummary;
    if (summary != null && summary != _lastToastSummary) {
      _lastToastSummary = summary;
      AppToast.success(context, summary);
      ledger.clearLastCommittedSummary();
    }

    final prefill = ledger.pendingFormPrefill;
    if (prefill != null) {
      ledger.consumeFormPrefill();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openFormSheet(prefill);
      });
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      _ctrl.clear();
      await ledger.sendChatInput(text);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _openFormSheet(ParsedTransaction prefill) {
    AppBottomSheet.show(
      context: context,
      title: 'Log Transaction',
      body: AddTransactionSheet(
        presenter: ledger,
        prefill: prefill,
        initialDate: ledger.selectedDate,
      ),
    );
  }

  String _hint(LedgerPresenter p) {
    if (!p.isSelectedDateToday) return 'Open Finance to log on that day';
    if (p.chatState.phase == ChatPhase.clarifying) return 'Reply…';
    return 'Log an expense…';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final state = ledger.chatState;
        // Quick logging stamps "today", so it's gated to the current day; the
        // full form (reachable via the card header) handles back-dated entries.
        final canSend = ledger.isSelectedDateToday;
        final classifying = state.phase == ChatPhase.classifying;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ResponseArea(ledger: ledger),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    enabled: canSend && !classifying,
                    style: AppTextStyles.bodyMedium,
                    decoration: InputDecoration(
                      hintText: _hint(ledger),
                      hintStyle: AppTextStyles.bodyMedium.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      filled: true,
                      fillColor: cs.surfaceContainerHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
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
                    icon: _sending || classifying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    onPressed: canSend && !classifying ? _send : null,
                    tooltip: 'Send',
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// The transient AI dialog shown above the input: thinking spinner, a resolved
/// summary with confirm actions, a clarifying question with quick replies, or a
/// hard-error chip. Collapses to nothing when the chat is idle.
class _ResponseArea extends StatelessWidget {
  const _ResponseArea({required this.ledger});

  final LedgerPresenter ledger;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final state = ledger.chatState;
    final hardError = ledger.chatHardError;
    final step = state.lastStep;

    Widget? body;
    if (hardError != null) {
      body = _ErrorBody(
          message: hardError.userMessage,
          onDismiss: () {
            ledger.clearChatHardError();
          });
    } else if (state.phase == ChatPhase.classifying) {
      body = Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text('Thinking…',
              style:
                  AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant)),
        ],
      );
    } else if (step is StepResolved) {
      body = _ResolvedBody(ledger: ledger, summary: step.summaryText);
    } else if (step is StepClarify) {
      body = _ClarifyBody(ledger: ledger, step: step);
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: body == null
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: body,
            ),
    );
  }
}

class _ResolvedBody extends StatelessWidget {
  const _ResolvedBody({required this.ledger, required this.summary});

  final LedgerPresenter ledger;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(summary,
            style: AppTextStyles.bodySmall.copyWith(color: cs.onSurface)),
        const SizedBox(height: AppSpacing.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: ledger.cancelChat,
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: ledger.confirmResolved,
              child: const Text('Log it'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ClarifyBody extends StatelessWidget {
  const _ClarifyBody({required this.ledger, required this.step});

  final LedgerPresenter ledger;
  final StepClarify step;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final replies = step.quickReplies ?? const <QuickReply>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(step.question,
            style: AppTextStyles.bodySmall.copyWith(color: cs.onSurface)),
        if (replies.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final r in replies)
                ActionChip(
                  label: Text(r.label),
                  onPressed: () => ledger.sendChatInput(r.replyText),
                ),
            ],
          ),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: ledger.cancelChat,
            child: const Text('Cancel'),
          ),
        ),
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.error_outline, size: 16, color: cs.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message,
              style: AppTextStyles.bodySmall.copyWith(color: cs.error)),
        ),
        IconButton(
          icon: Icon(Icons.close, color: cs.onSurfaceVariant, size: 18),
          onPressed: onDismiss,
          tooltip: 'Dismiss',
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}
