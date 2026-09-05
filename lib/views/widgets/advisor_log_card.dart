import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/finance/finance_parse_result.dart';
import '../../models/finance/transaction_record.dart';
import '../../presenters/ledger_presenter.dart';
import '../../presenters/finance_tool_executor.dart';
import 'finance/entry_review_card.dart';
import 'finance/finance_proposal_card.dart';

/// Polished in-chat confirm/clarify card for logging an expense from the
/// financial advisor conversation. Driven by [LedgerPresenter.chatState] — the
/// same confirm-before-commit pipeline the hub quick-log bar uses, rendered as
/// a richer card (amount + account + category chips, explicit actions).
///
/// Collapses to nothing when the ledger chat is idle.
class AdvisorLogCard extends StatelessWidget {
  const AdvisorLogCard({super.key, required this.ledger, this.proposals});

  final LedgerPresenter ledger;

  /// Where a change Nudgy proposed waits for an answer. Null when this build
  /// has no tool executor, in which case the card behaves exactly as before.
  final FinanceProposalHost? proposals;

  static final _money = NumberFormat('#,##0.##', 'en_US');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final state = ledger.chatState;
    final hardError = ledger.chatHardError;
    final step = state.lastStep;

    final pending = proposals?.pending;

    Widget? body;
    if (hardError != null) {
      body = _Error(
          message: hardError.userMessage, onDismiss: ledger.clearChatHardError);
    } else if (pending != null) {
      // A pending proposal outranks the logging states: the tool loop is
      // blocked on this answer, and nothing else in the chat can progress
      // until the user gives one.
      // Keyed by proposal, so the next one in a run gets its own State rather
      // than inheriting the previous card's "busy" and recurrence choice.
      body = FinanceProposalCard(
        key: ValueKey(pending.call.id),
        host: proposals!,
        action: pending,
      );
    } else if (state.phase == ChatPhase.classifying) {
      body = _Thinking(cs: cs);
    } else if (state.entries.isNotEmpty) {
      // Plan 058: rows from the one-call extractor, reviewed and completed in
      // place. The StepResolved branch below still serves the regex fallback.
      body = EntryReviewCard(ledger: ledger, state: state);
    } else if (step is StepResolved) {
      body = _Resolved(ledger: ledger, step: step, money: _money);
    } else if (step is StepClarify) {
      body = _Clarify(ledger: ledger, step: step);
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      alignment: Alignment.bottomCenter,
      child: body == null
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant, width: 0.5),
              ),
              child: body,
            ),
    );
  }
}

class _Thinking extends StatelessWidget {
  const _Thinking({required this.cs});
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Text('Preparing your entry…',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
        ],
      );
}

class _Resolved extends StatelessWidget {
  const _Resolved(
      {required this.ledger, required this.step, required this.money});

  final LedgerPresenter ledger;
  final StepResolved step;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txns = step.transactions;
    final deferred = step.deferred.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // One message can describe several transactions. Rendering only the
        // first while "Log it" commits all of them would misreport what the
        // button does, so every entry gets a row.
        if (step.isBatch) ...[
          Text(
            '${txns.length} entries',
            style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6),
          ),
          const SizedBox(height: 8),
        ],
        for (var i = 0; i < txns.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, color: cs.outlineVariant),
            ),
          _ResolvedEntry(ledger: ledger, txn: txns[i], money: money),
        ],
        if (deferred > 0) ...[
          const SizedBox(height: 10),
          Text(
            deferred == 1
                ? '1 more needs a detail — I\'ll ask next.'
                : '$deferred more need a detail — I\'ll ask next.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: ledger.cancelChat,
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed: ledger.confirmResolved,
              icon: const Icon(Icons.check, size: 18),
              label: Text(step.isBatch ? 'Log all ${txns.length}' : 'Log it'),
            ),
          ],
        ),
      ],
    );
  }
}

/// One transaction inside a confirm card: description + amount, then the
/// account / destination / category chips.
class _ResolvedEntry extends StatelessWidget {
  const _ResolvedEntry(
      {required this.ledger, required this.txn, required this.money});

  final LedgerPresenter ledger;
  final ParsedTransaction txn;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final type = txn.type ?? TransactionType.outflow;

    final amountColor = switch (type) {
      TransactionType.inflow => cs.tertiary,
      TransactionType.outflow => cs.error,
      TransactionType.transfer => cs.primary,
    };
    final sign = type == TransactionType.inflow ? '+' : '';
    final amountText =
        txn.amount == null ? '—' : '$sign₱${money.format(txn.amount)}';

    final accountName = _nameOrNull(ledger.accounts, txn.accountId);
    final categoryName = _nameOrNull(ledger.categories, txn.categoryId);
    final toAccountName = _nameOrNull(ledger.accounts, txn.transferToAccountId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                txn.description.isEmpty ? 'New entry' : txn.description,
                style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              amountText,
              style: TextStyle(
                  color: amountColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (accountName != null)
              _Chip(
                  icon: Icons.account_balance_wallet_outlined,
                  label: accountName),
            if (toAccountName != null)
              _Chip(icon: Icons.arrow_forward, label: toAccountName),
            if (categoryName != null)
              _Chip(icon: Icons.label_outline, label: categoryName),
          ],
        ),
      ],
    );
  }

  static String? _nameOrNull(List<dynamic> items, String? id) {
    if (id == null) return null;
    for (final it in items) {
      if ((it as dynamic).id == id) return (it).name as String;
    }
    return null;
  }
}

class _Clarify extends StatelessWidget {
  const _Clarify({required this.ledger, required this.step});

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
            style: TextStyle(color: cs.onSurface, fontSize: 14)),
        if (replies.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
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

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: cs.onSurface, fontSize: 12.5)),
        ],
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.onDismiss});
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
          child: Text(message, style: TextStyle(color: cs.error, fontSize: 13)),
        ),
        IconButton(
          icon: Icon(Icons.close, color: cs.onSurfaceVariant, size: 18),
          onPressed: onDismiss,
          tooltip: 'Dismiss',
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          padding: EdgeInsets.zero,
        ),
      ],
    );
  }
}
