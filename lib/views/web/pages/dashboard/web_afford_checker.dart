import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../../widgets/web_widgets.dart';

/// Sentinel value for the "Any account" dropdown entry (null account scope).
const String _kAnyAccountId = '__any__';

/// "Can I afford it?" tool — an amount field + account dropdown that asks the
/// presenter for a verdict and renders a tier-coloured copy line. UI state
/// only; the affordability math lives in [TreasuryDashboardPresenter.canAfford].
class WebAffordChecker extends StatefulWidget {
  final TreasuryDashboardPresenter presenter;
  const WebAffordChecker({super.key, required this.presenter});

  @override
  State<WebAffordChecker> createState() => _WebAffordCheckerState();
}

class _WebAffordCheckerState extends State<WebAffordChecker> {
  final TextEditingController _controller = TextEditingController();
  String _accountId = _kAnyAccountId;
  AffordVerdict? _verdict;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _recompute() {
    final amount = double.tryParse(_controller.text.trim());
    setState(() {
      if (amount == null || amount <= 0) {
        _verdict = null;
      } else {
        _verdict = widget.presenter.canAfford(
          amount,
          accountId: _accountId == _kAnyAccountId ? null : _accountId,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accounts = widget.presenter.liquidAccounts;

    return WebCard(
      title: 'Can I afford it?',
      description: 'Check a one-off spend against your spare cash this month.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _controller,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  onChanged: (_) => _recompute(),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: '₱ ',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: WebInsets.lg),
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  initialValue: _accountId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'From account',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: _kAnyAccountId,
                      child: Text('Any account'),
                    ),
                    for (final FinancialAccount a in accounts)
                      DropdownMenuItem(
                        value: a.id,
                        child: Text(a.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    _accountId = value;
                    _recompute();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: WebInsets.lg),
          if (_verdict == null)
            Text(
              'Enter an amount to see if it fits.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            )
          else
            _VerdictLine(verdict: _verdict!),
        ],
      ),
    );
  }
}

class _VerdictLine extends StatelessWidget {
  final AffordVerdict verdict;
  const _VerdictLine({required this.verdict});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final (Color color, String text) = switch (verdict.tier) {
      AffordTier.yes => (
          cs.tertiary,
          '✅ YES — fits comfortably. About ${formatPeso(verdict.spareAfter)} '
              'spare left this month after bills & savings.'
        ),
      AffordTier.tight => (
          cs.secondary,
          '⚠️ Tight — possible, but only ${formatPeso(verdict.spareAfter)} '
              'spare after bills & savings.'
        ),
      AffordTier.no => (
          cs.error,
          verdict.accountShortfall != null
              ? '❌ Not this month — that account is short by '
                  '${formatPeso(verdict.accountShortfall!)}.'
              : '❌ Not this month'
        ),
    };

    return Container(
      padding: const EdgeInsets.all(WebInsets.lg),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodyLarge
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
