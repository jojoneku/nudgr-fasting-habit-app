import 'package:flutter/material.dart';

import '../../../models/finance/finance_parse_result.dart';
import '../../../presenters/ledger_presenter.dart';
import '../../../utils/app_spacing.dart';
import '../../../utils/app_text_styles.dart';

/// The transient AI dialog shown above a ledger chat input: a thinking spinner,
/// a resolved summary with confirm actions, a clarifying question with quick
/// replies, or a hard-error chip. Collapses to nothing when the chat is idle.
///
/// Shared by the Finance hub card's quick-log chat and the hub's unified
/// quick-log bar so both surfaces drive [LedgerPresenter]'s chat pipeline with
/// identical confirm/clarify UI.
class LedgerChatPanel extends StatelessWidget {
  const LedgerChatPanel({super.key, required this.ledger});

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
      body = _ResolvedBody(ledger: ledger, step: step);
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
  const _ResolvedBody({required this.ledger, required this.step});

  final LedgerPresenter ledger;
  final StepResolved step;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // For a batch the summary is already one line per transaction, so this
        // reads as a list rather than needing a separate layout.
        Text(step.summaryText,
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
              // Naming the count matters here: the button commits every
              // transaction the step carries, not just the first.
              child: Text(step.isBatch
                  ? 'Log all ${step.transactions.length}'
                  : 'Log it'),
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
