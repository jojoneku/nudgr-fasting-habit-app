import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/views/treasury/shared/account_badge_widget.dart';
import 'package:intermittent_fasting/views/treasury/shared/account_setup_view.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/amount_input_formatter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/goal_progress_card.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// Dedicated Goals & Savings screen (`Nutrition Focus Treasury.dc.html`,
/// Frame 12): a TOTAL SAVED hero, the active goals (progress cards) and plain
/// savings accounts, with an add-goal FAB. Reachable both as its own Treasury
/// tab and from the Dashboard's goals section. All figures come from
/// [TreasuryDashboardPresenter]; it owns its own add/edit sheets.
final _completedFmt = DateFormat('MMM d, yyyy');

class GoalsSavingsScreen extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  /// False when an enclosing shell already titles the page — the desktop web
  /// sidebar names the destination in its topbar, so a second "Goals & Savings"
  /// bar directly under it is pure duplication.
  final bool showAppBar;

  const GoalsSavingsScreen({
    super.key,
    required this.presenter,
    this.showAppBar = true,
  });

  void _showAddSheet(BuildContext context) {
    AppBottomSheet.show(
      context: context,
      title: 'Add Goal or Savings',
      body: AccountSetupView(
        presenter: presenter,
        initialCategory: AccountCategory.savings,
      ),
    );
  }

  void _showEditSheet(BuildContext context, FinancialAccount account) {
    AppBottomSheet.show(
      context: context,
      title: 'Edit Account',
      body: AccountSetupView(presenter: presenter, existing: account),
    );
  }

  Future<void> _confirmMarkSpent(
      BuildContext context, FinancialAccount account) async {
    final ok = await AppConfirmDialog.confirm(
      context: context,
      title: 'Spent ${account.name}?',
      body: 'Marks this goal complete and files it under Completed. The money '
          'and its transactions stay in your ledger either way — this only '
          'records that you spent it on what you were saving for.',
      confirmLabel: 'Yes, spent it',
    );
    if (ok) await presenter.markGoalRedeemed(account.id);
  }

  Future<void> _confirmArchive(
      BuildContext context, FinancialAccount account) async {
    final ok = await AppConfirmDialog.confirm(
      context: context,
      title: 'Archive ${account.name}?',
      body: 'Files it away and takes it out of your account pickers. Nothing '
          'is deleted — the transactions stay in your ledger, and you can '
          'bring it back from the accounts list any time.',
      confirmLabel: 'Archive',
    );
    if (ok) await presenter.archiveGoal(account.id);
  }

  Future<void> _promptRestart(
      BuildContext context, FinancialAccount account) async {
    await AppBottomSheet.show(
      context: context,
      title: 'Start ${account.name} again',
      body: _RestartGoalSheet(presenter: presenter, account: account),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) {
        // Goals (with a target) and savings holding a target render as progress
        // cards; plain savings (no target) render as simple balance rows.
        // Both lists are presenter-owned so this build() stays free of
        // stage filtering.
        final activeGoals = presenter.activeGoalAccounts;
        final completedGoals = presenter.completedGoalAccounts;
        final plainSavings = presenter.savingsAccounts
            .where((a) => (a.goalTarget ?? 0) <= 0)
            .toList();

        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: showAppBar
              ? AppBar(
                  backgroundColor: theme.scaffoldBackgroundColor,
                  title: const Text('Goals & Savings'),
                )
              : null,
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showAddSheet(context),
            backgroundColor: context.appColors.success,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add),
            label: const Text('Add Goal',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              _TotalSavedHero(total: presenter.totalSavingsAndGoals),
              const SizedBox(height: 20),
              if (activeGoals.isEmpty &&
                  completedGoals.isEmpty &&
                  plainSavings.isEmpty)
                const AppCard(
                  variant: AppCardVariant.elevated,
                  child: AppEmptyState(
                    icon: Icons.savings_outlined,
                    title: 'No goals or savings yet',
                    body: 'Add a savings account or goal to track progress',
                  ),
                ),
              if (activeGoals.isNotEmpty)
                AppSection(
                  title: 'Active goals',
                  child: AppCard(
                    variant: AppCardVariant.elevated,
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < activeGoals.length; i++) ...[
                          GoalProgressCard(
                            account: activeGoals[i],
                            onTap: () {
                              HapticFeedback.selectionClick();
                              _showEditSheet(context, activeGoals[i]);
                            },
                            onMarkSpent: activeGoals[i].goalStage ==
                                    GoalStage.funded
                                ? () =>
                                    _confirmMarkSpent(context, activeGoals[i])
                                : null,
                          ),
                          if (i < activeGoals.length - 1)
                            Divider(
                              height: 1,
                              indent: 16,
                              endIndent: 16,
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.4),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              if (completedGoals.isNotEmpty) ...[
                const SizedBox(height: 4),
                AppSection(
                  title: 'Completed',
                  child: AppCard(
                    variant: AppCardVariant.elevated,
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < completedGoals.length; i++) ...[
                          _CompletedGoalRow(
                            account: completedGoals[i],
                            onRestart: () =>
                                _promptRestart(context, completedGoals[i]),
                            onArchive: () =>
                                _confirmArchive(context, completedGoals[i]),
                          ),
                          if (i < completedGoals.length - 1)
                            Divider(
                              height: 1,
                              indent: 16,
                              endIndent: 16,
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.4),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
              if (plainSavings.isNotEmpty) ...[
                const SizedBox(height: 4),
                AppSection(
                  title: 'Savings accounts',
                  child: Column(
                    children: [
                      for (final a in plainSavings)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: _SavingsRow(
                            account: a,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              _showEditSheet(context, a);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _TotalSavedHero extends StatelessWidget {
  final double total;
  const _TotalSavedHero({required this.total});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final green = context.appColors.success;

    Color blend(double a) =>
        Color.alphaBlend(green.withValues(alpha: a), cs.surface);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [blend(0.22), blend(0.10), cs.surface],
          stops: const [0.0, 0.55, 1.0],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: green.withValues(alpha: 0.28)),
      ),
      padding: const EdgeInsets.all(17),
      child: Row(
        children: [
          Icon(Icons.savings_rounded, size: 30, color: green),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TOTAL SAVED',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: green,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                formatPeso(total),
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SavingsRow extends StatelessWidget {
  final FinancialAccount account;
  final VoidCallback onTap;

  const _SavingsRow({required this.account, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AppCard(
      variant: AppCardVariant.elevated,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          AccountBadge.of(account, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              account.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          AppNumberDisplay(
            value: formatPeso(account.balance),
            size: AppNumberSize.body,
            color: cs.onSurface,
          ),
        ],
      ),
    );
  }
}

/// A goal the user reached and spent. Shows what it delivered rather than a
/// progress bar: after the purchase the balance is back to ₱0, and 0% would
/// report a success as a failure.
class _CompletedGoalRow extends StatelessWidget {
  final FinancialAccount account;
  final VoidCallback onRestart;
  final VoidCallback onArchive;

  const _CompletedGoalRow({
    required this.account,
    required this.onRestart,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final green = context.appColors.success;
    final funded = account.goalRedeemedAmount ?? account.goalTarget ?? 0;
    final on = account.goalRedeemedAt;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.check_circle, size: 22, color: green),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  account.name,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  'Funded ${formatPeso(funded)}'
                  '${on == null ? '' : ' · spent ${_completedFmt.format(on)}'}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onRestart,
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Start again'),
          ),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              tooltip: 'Archive',
              onPressed: onArchive,
              icon: const Icon(Icons.inventory_2_outlined, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

/// Restarts a completed goal against a fresh target, keeping the account and
/// its transaction history. Asks for the new target rather than reusing the old
/// one: a goal worth repeating usually costs something different the next time.
class _RestartGoalSheet extends StatefulWidget {
  final TreasuryDashboardPresenter presenter;
  final FinancialAccount account;

  const _RestartGoalSheet({required this.presenter, required this.account});

  @override
  State<_RestartGoalSheet> createState() => _RestartGoalSheetState();
}

class _RestartGoalSheetState extends State<_RestartGoalSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: (widget.account.goalTarget ?? 0) > 0
          ? widget.account.goalTarget!.toStringAsFixed(2)
          : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double? get _target => double.tryParse(_controller.text.trim());
  bool get _canSave => (_target ?? 0) > 0;

  Future<void> _save() async {
    final target = _target;
    if (target == null || target <= 0) return;
    await widget.presenter
        .restartGoalAccount(widget.account.id, newTarget: target);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Clears the completed stamp and starts tracking toward a new target. '
          'The account and everything in its history stay put.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _controller,
          label: 'New target',
          prefix: const Text('₱ '),
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: amountInputFormatters,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _canSave ? _save() : null,
        ),
        const SizedBox(height: 24),
        AppPrimaryButton(
          label: 'Start again',
          leading: Icons.restart_alt,
          onPressed: _canSave ? _save : null,
        ),
      ],
    );
  }
}
