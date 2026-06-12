import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/app_radii.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../../widgets/web_widgets.dart';
import 'web_account_form_dialog.dart';

/// Web Treasury "Setup & Accounts" page (6th nav item). A desktop view to
/// browse and manage every financial account, grouped by role, using the
/// shared web design-system kit (`WebCard`, `WebBadge`, `WebProgressBar`).
///
/// Add/edit use the native web [WebAccountFormDialog] — a centered, scrollable
/// dialog matching the other web modals. That form owns its own save/delete
/// logic and pops itself when done, so the [ListenableBuilder] here repaints
/// with the fresh account list automatically.
///
/// CRUD lives entirely in [TreasuryDashboardPresenter]; this page only reads
/// account lists and calls [TreasuryDashboardPresenter.deleteAccount].
class WebSetupPage extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  const WebSetupPage({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) => _SetupBody(presenter: presenter),
    );
  }
}

/// Opens the native web account form (add when [existing] is null, edit
/// otherwise) in a centered dialog. The form pops itself on save/delete; no
/// result handling is needed because the presenter notifies.
void _showAccountSheet(
  BuildContext context,
  TreasuryDashboardPresenter presenter, [
  FinancialAccount? existing,
]) {
  WebAccountFormDialog.show(context, presenter, existing: existing);
}

class _SetupBody extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  const _SetupBody({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (presenter.isLoading) {
      content = const Padding(
        padding: EdgeInsets.symmetric(vertical: 96),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (!presenter.hasAccounts) {
      content = _EmptyState(
        onAdd: () => _showAccountSheet(context, presenter),
      );
    } else {
      content = _AccountGroups(presenter: presenter);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(WebInsets.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WebSectionHeader(
            title: 'Setup & Accounts',
            subtitle: 'Manage your accounts, balances & credit',
            trailing: FilledButton.icon(
              onPressed: () => _showAccountSheet(context, presenter),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Account'),
            ),
          ),
          content,
        ],
      ),
    );
  }
}

// ─── Account groups ─────────────────────────────────────────────────────────

class _AccountGroups extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  const _AccountGroups({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final savingsAndGoals = [
      ...presenter.savingsAccounts,
      ...presenter.goalAccounts,
    ];

    final sections = <Widget>[
      if (presenter.liquidAccounts.isNotEmpty)
        _AccountSection(
          title: 'Liquid',
          description:
              'Bank, eWallet & cash · ${formatPeso(presenter.totalLiquidCash)} yours',
          presenter: presenter,
          accounts: presenter.liquidAccounts,
        ),
      if (savingsAndGoals.isNotEmpty)
        _AccountSection(
          title: 'Savings & Goals',
          description: 'Ring-fenced pockets and goal targets',
          presenter: presenter,
          accounts: savingsAndGoals,
        ),
      if (presenter.creditAccounts.isNotEmpty)
        _AccountSection(
          title: 'Credit',
          description:
              'Cards, lines & BNPL · ${formatPeso(presenter.totalCreditOwed)} owed',
          presenter: presenter,
          accounts: presenter.creditAccounts,
        ),
      if (presenter.custodianAccounts.isNotEmpty)
        _AccountSection(
          title: 'Custodian / Held',
          description:
              'Money held for others · ${formatPeso(presenter.totalHeldForOthers)}',
          presenter: presenter,
          accounts: presenter.custodianAccounts,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < sections.length; i++) ...[
          if (i > 0) const SizedBox(height: WebInsets.xl),
          sections[i],
        ],
      ],
    );
  }
}

/// One grouped card listing [accounts], each as an [_AccountRow]. Sub-accounts
/// of any listed account are rendered indented directly under their parent.
class _AccountSection extends StatelessWidget {
  final String title;
  final String description;
  final TreasuryDashboardPresenter presenter;
  final List<FinancialAccount> accounts;

  const _AccountSection({
    required this.title,
    required this.description,
    required this.presenter,
    required this.accounts,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final rows = <Widget>[];
    for (final account in accounts) {
      rows.add(_AccountRow(presenter: presenter, account: account));
      for (final sub in presenter.subAccountsOf(account.id)) {
        rows.add(
            _AccountRow(presenter: presenter, account: sub, indented: true));
      }
    }

    return WebCard(
      title: title,
      description: description,
      padding: const EdgeInsets.symmetric(
        horizontal: WebInsets.xl,
        vertical: WebInsets.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: cs.outlineVariant.withValues(alpha: 0.3),
              ),
            rows[i],
          ],
        ],
      ),
    );
  }
}

// ─── Account row ─────────────────────────────────────────────────────────────

class _AccountRow extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  final FinancialAccount account;
  final bool indented;

  const _AccountRow({
    required this.presenter,
    required this.account,
    this.indented = false,
  });

  Color _accountColor(BuildContext context) {
    final hex = account.colorHex.replaceFirst('#', '');
    try {
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Theme.of(context).colorScheme.primary;
    }
  }

  IconData get _icon => switch (account.category) {
        AccountCategory.bank => Icons.account_balance_outlined,
        AccountCategory.ewallet => Icons.account_balance_wallet_outlined,
        AccountCategory.cash => Icons.payments_outlined,
        AccountCategory.savings => Icons.savings_outlined,
        AccountCategory.goal => Icons.flag_outlined,
        AccountCategory.timeDeposit => Icons.lock_clock_outlined,
        AccountCategory.creditCard => Icons.credit_card_outlined,
        AccountCategory.creditLine => Icons.account_balance_outlined,
        AccountCategory.bnpl => Icons.schedule_outlined,
        AccountCategory.investment => Icons.trending_up_outlined,
        AccountCategory.custodian => Icons.group_outlined,
      };

  String get _typeLabel => switch (account.category) {
        AccountCategory.bank => 'Bank',
        AccountCategory.ewallet => 'eWallet',
        AccountCategory.cash => 'Cash',
        AccountCategory.savings => 'Savings',
        AccountCategory.goal => 'Goal',
        AccountCategory.timeDeposit => 'Time Deposit',
        AccountCategory.creditCard => 'Credit Card',
        AccountCategory.creditLine => 'Credit Line',
        AccountCategory.bnpl => 'BNPL',
        AccountCategory.investment => 'Investment',
        AccountCategory.custodian => 'External',
      };

  Future<void> _confirmDelete(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final cs = Theme.of(context).colorScheme;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account?'),
        content: Text(
          'This will permanently remove "${account.name}". '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: cs.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await presenter.deleteAccount(account.id);
    } on StateError catch (e) {
      final message = switch (e.message) {
        'has_sub_accounts' =>
          'Remove all sub-accounts first before deleting this account.',
        'has_transactions' =>
          'This account has transactions or bills linked to it. '
              'Delete or reassign them first.',
        _ => 'Could not delete account: ${e.message}',
      };
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = _accountColor(context);

    final isGoal = account.category == AccountCategory.goal;
    final goalTarget = account.goalTarget;
    final availableCredit = account.availableCredit;

    return Padding(
      padding: EdgeInsets.only(
        left: indented ? WebInsets.xl : 0,
        top: WebInsets.sm,
        bottom: WebInsets.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icon chip
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Icon(_icon, size: 20, color: color),
          ),
          const SizedBox(width: WebInsets.md),
          // Name + type sub-label (+ goal progress when applicable)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        account.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (account.isLiability) ...[
                      const SizedBox(width: WebInsets.sm),
                      const WebBadge('Credit', tone: WebBadgeTone.info),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _typeLabel,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                if (isGoal && goalTarget != null && goalTarget > 0) ...[
                  const SizedBox(height: WebInsets.sm),
                  WebProgressBar(
                    value: account.balance / goalTarget,
                    color: color,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: WebInsets.lg),
          // Balance figure (+ goal target / available credit sub-line)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatPeso(account.balance),
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: account.isLiability ? cs.error : cs.onSurface,
                ),
              ),
              if (isGoal && goalTarget != null) ...[
                const SizedBox(height: 2),
                Text(
                  'of ${formatPeso(goalTarget)}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ] else if (availableCredit != null) ...[
                const SizedBox(height: 2),
                Text(
                  '${formatPeso(availableCredit)} available',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
          const SizedBox(width: WebInsets.sm),
          // Edit / delete actions (≥44px touch targets)
          IconButton(
            tooltip: 'Edit account',
            onPressed: () => _showAccountSheet(context, presenter, account),
            icon: const Icon(Icons.edit_outlined, size: 18),
            color: cs.onSurfaceVariant,
          ),
          IconButton(
            tooltip: 'Delete account',
            onPressed: () => _confirmDelete(context),
            icon: const Icon(Icons.delete_outline, size: 18),
            color: cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

// ─── Empty state ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return WebCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: WebInsets.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance_wallet_outlined,
                size: 44, color: cs.onSurfaceVariant),
            const SizedBox(height: WebInsets.md),
            Text('No accounts yet',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: WebInsets.xs),
            Text(
              'Add your banks, wallets, savings, and cards to start '
              'tracking your treasury.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: WebInsets.xl),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Account'),
            ),
          ],
        ),
      ),
    );
  }
}
