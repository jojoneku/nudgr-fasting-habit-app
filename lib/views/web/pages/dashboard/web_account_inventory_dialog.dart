import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/account_badge.dart';
import 'package:intermittent_fasting/utils/app_radii.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../../design/account_category_label.dart';
import '../../design/web_breakpoints.dart';
import '../../widgets/web_number.dart';

/// "All accounts" — every account the treasury knows about, grouped by where
/// the dashboard surfaces it.
///
/// The Accounts section shows only top-level liquid and credit accounts, so
/// savings pockets, goals, investments, sub-accounts, custodian money and
/// archived accounts are absent from it *by design*. Without this list there
/// was no way to tell a deliberately-filtered account from a genuinely missing
/// one — the distinction that matters after any sync doubt.
///
/// Read-only. Grouping and counts come from
/// [TreasuryDashboardPresenter.accountInventory]; this widget only lays them
/// out.
class WebAccountInventoryDialog extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  const WebAccountInventoryDialog({super.key, required this.presenter});

  static Future<void> show(
    BuildContext context, {
    required TreasuryDashboardPresenter presenter,
  }) =>
      showDialog<void>(
        context: context,
        builder: (_) => WebAccountInventoryDialog(presenter: presenter),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Rebuild with the presenter so a sync landing while the dialog is open
    // corrects the list in place rather than showing a stale snapshot — the
    // very situation that prompted this screen.
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) {
        final groups = presenter.accountInventory;
        final total = presenter.accountInventoryCount;
        final shown = presenter.accountInventoryShownCount;

        return Dialog(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(total: total, shown: shown),
                Divider(height: 1, color: cs.outlineVariant),
                Flexible(
                  child: groups.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(WebInsets.xxl),
                          child: Text(
                            'No accounts yet.',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: WebInsets.xl,
                            vertical: WebInsets.lg,
                          ),
                          itemCount: groups.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: WebInsets.xl),
                          itemBuilder: (context, i) => _Group(group: groups[i]),
                        ),
                ),
                Divider(height: 1, color: cs.outlineVariant),
                Padding(
                  padding: const EdgeInsets.all(WebInsets.md),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final int total;
  final int shown;
  const _Header({required this.total, required this.shown});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          WebInsets.xl, WebInsets.xl, WebInsets.md, WebInsets.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('All accounts',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: WebInsets.xs),
                Text(
                  '$total total · $shown shown as tiles on the dashboard',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final AccountInventoryGroup group;
  const _Group({required this.group});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // Credit balances are money owed, so labelling the bucket sum "total" would
    // read as money held. Say which it is.
    final owed = group.title.startsWith('Credit');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${group.title} · ${group.accounts.length}',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            const SizedBox(width: WebInsets.sm),
            WebNumber(
              '${owed ? 'owed ' : ''}${formatPeso(group.total)}',
              size: WebNumberSize.caption,
              color: cs.onSurfaceVariant,
            ),
          ],
        ),
        const SizedBox(height: WebInsets.xs),
        Row(
          children: [
            Icon(
              group.onDashboard
                  ? Icons.check_circle_outline_rounded
                  : Icons.visibility_off_outlined,
              size: 14,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: WebInsets.xs),
            Expanded(
              child: Text(
                group.surfacedIn,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: WebInsets.md),
        for (final a in group.accounts) _Row(account: a),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final FinancialAccount account;
  const _Row({required this.account});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: WebInsets.sm),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Icon(accountIconFor(account),
                size: 15, color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: WebInsets.md),
          Expanded(
            child: Text(
              account.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: WebInsets.sm),
          Text(
            // A credit row shows its balance, i.e. money OWED — while the
            // dashboard tile for the same card shows its *available* credit.
            // Two different figures for one account, so say which this one is.
            account.isLiability
                ? '${account.category.label} · owed'
                : account.category.label,
            style:
                theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: WebInsets.lg),
          WebNumber(
            formatPeso(account.balance),
            size: WebNumberSize.caption,
            color: cs.onSurface,
          ),
        ],
      ),
    );
  }
}
