import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

/// Keys for the credit cards card, for tests.
abstract final class CreditCardsCardKeys {
  static const card = ValueKey('bills-credit-cards');
  static const empty = ValueKey('bills-credit-cards-empty');
  static ValueKey<String> pay(String accountId) =>
      ValueKey('bills-credit-cards-pay-$accountId');
}

/// The credit cards card under the Bills tab list (Plan 071 Phase 6): what
/// is owed and still available across the credit lines, and one row per card
/// that owes something, with Pay.
///
/// A card payment is always a transfer, so [onPay] opens the card-payment
/// Settle sheet. [onPay] is null while a batch selection is running. Renders
/// nothing when there are no credit lines.
class CreditCardsCard extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final ValueChanged<FinancialAccount>? onPay;

  const CreditCardsCard({
    super.key,
    required this.presenter,
    required this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    if (presenter.creditAccounts.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final owing = presenter.creditAccountsWithBalance;
    final pay = onPay;
    return Container(
      key: CreditCardsCardKeys.card,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Credit cards',
            style: theme.textTheme.titleSmall?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            presenter.creditLinesDescription,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          if (owing.isEmpty)
            Padding(
              key: CreditCardsCardKeys.empty,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Nothing owed on any card right now.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          for (final card in owing)
            _CardRow(
              name: card.name,
              subtitle: presenter.creditLineSubtitle(card),
              owed: formatPeso(card.currentPayable),
              payKey: CreditCardsCardKeys.pay(card.id),
              onPay: pay == null ? null : () => pay(card),
            ),
        ],
      ),
    );
  }
}

class _CardRow extends StatelessWidget {
  final String name;
  final String subtitle;
  final String owed;
  final Key payKey;
  final VoidCallback? onPay;

  const _CardRow({
    required this.name,
    required this.subtitle,
    required this.owed,
    required this.payKey,
    required this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                owed,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: cs.error,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              FilledButton.tonal(
                key: payKey,
                onPressed: onPay,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(64, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text(
                  'Pay',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
