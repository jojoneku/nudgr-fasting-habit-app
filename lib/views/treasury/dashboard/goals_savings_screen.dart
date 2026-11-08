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
import 'package:intermittent_fasting/utils/account_archive_copy.dart';
import 'package:intermittent_fasting/utils/goal_copy.dart';
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

  /// The funding note's "Open the Savings rows in Budget". The Treasury tab
  /// shell switches to the Budget tab; null (the screen pushed from the
  /// Dashboard) hides the link and keeps the note.
  final VoidCallback? onOpenBudget;

  const GoalsSavingsScreen({
    super.key,
    required this.presenter,
    this.showAppBar = true,
    this.onOpenBudget,
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
      title: accountArchiveTitle(account),
      body: accountArchiveMessage(account),
      confirmLabel: 'Archive',
    );
    if (!ok) return;
    await presenter.archiveGoal(account.id);
    if (!context.mounted) return;
    AppToast.success(context, accountArchivedToast(account));
  }

  /// Start again for one goal, or — with no [account], from the funding
  /// note — a picker over every restartable goal (completed first), as on web.
  Future<void> _promptRestart(
      BuildContext context, FinancialAccount? account) async {
    await AppBottomSheet.show(
      context: context,
      title: account == null
          ? 'Start a goal again'
          : 'Start ${account.name} again',
      body: _RestartGoalSheet(presenter: presenter, account: account),
    );
  }

  /// The active-goal card's Start again, or null when
  /// [TreasuryDashboardPresenter.canStartAgain] says no: a savings account
  /// with a target, or a reached goal not yet marked spent (it shows
  /// "Mark spent" instead and restarts from Completed afterwards).
  VoidCallback? _startAgainFor(
          BuildContext context, FinancialAccount account) =>
      TreasuryDashboardPresenter.canStartAgain(account)
          ? () => _promptRestart(context, account)
          : null;

  /// The funding note's "Start again…", or null when no goal can restart.
  VoidCallback? _noteStartAgain(BuildContext context) =>
      presenter.restartableGoalAccounts.isEmpty
          ? null
          : () => _promptRestart(context, null);

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
        final plainSavings = presenter.plainSavingsAccounts;
        final hasRows = presenter.hasGoalsOrSavings;

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
            foregroundColor: theme.colorScheme.onPrimary,
            icon: const Icon(Icons.add),
            label: const Text('Add Goal',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              _TotalSavedHero(
                total: presenter.totalSavingsAndGoals,
                activeFunded: presenter.goalsActiveFunded,
                activeCount: presenter.goalsActiveCount,
                notStarted: presenter.goalsNotStartedCount,
                setAsides: presenter.goalSetAsidesThisMonth,
                setAsidesFunded: presenter.goalSetAsidesFundedThisMonth,
              ),
              const SizedBox(height: 20),
              if (!hasRows)
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
                            onStartAgain:
                                _startAgainFor(context, activeGoals[i]),
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
              if (hasRows) ...[
                const SizedBox(height: 4),
                _FundingNote(
                  onOpenBudget: onOpenBudget,
                  onStartAgain: _noteStartAgain(context),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

String _goalsWord(int n) => n == 1 ? 'goal' : 'goals';

class _TotalSavedHero extends StatelessWidget {
  final double total;
  final int activeFunded;
  final int activeCount;
  final int notStarted;
  final double setAsides;
  final double setAsidesFunded;

  const _TotalSavedHero({
    required this.total,
    required this.activeFunded,
    required this.activeCount,
    required this.notStarted,
    required this.setAsides,
    required this.setAsidesFunded,
  });

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
          const SizedBox(height: 14),
          Divider(height: 1, color: green.withValues(alpha: 0.22)),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _HeroStat(
                    key: const ValueKey('goals.hero.active'),
                    label: 'Active',
                    value: '$activeFunded funded',
                    caption: 'of $activeCount ${_goalsWord(activeCount)}',
                    valueColor: green,
                  ),
                ),
                VerticalDivider(
                    width: 17, color: green.withValues(alpha: 0.22)),
                Expanded(
                  child: _HeroStat(
                    key: const ValueKey('goals.hero.notStarted'),
                    label: 'Not started',
                    value: '$notStarted',
                    caption: 'nothing set aside yet',
                    valueColor: cs.onSurface,
                  ),
                ),
                VerticalDivider(
                    width: 17, color: green.withValues(alpha: 0.22)),
                Expanded(
                  child: _HeroStat(
                    key: const ValueKey('goals.hero.setAsides'),
                    label: 'Set-asides this month',
                    value: formatPeso(setAsides),
                    caption: '${formatPeso(setAsidesFunded)} funded so far',
                    valueColor: cs.primary,
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

/// One cell of the hero's strip: a small label, the figure, a caption. The
/// figure scales down rather than wrap, so peso amounts fit at 360 dp.
class _HeroStat extends StatelessWidget {
  final String label;
  final String value;
  final String caption;
  final Color valueColor;

  const _HeroStat({
    super.key,
    required this.label,
    required this.value,
    required this.caption,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: cs.onSurfaceVariant, height: 1.2),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: theme.textTheme.titleSmall?.copyWith(
              color: valueColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          caption,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant, fontSize: 11, height: 1.25),
        ),
      ],
    );
  }
}

/// "How goals are funded": the web Goals page's note, same words. Goals are
/// funded through budget set-asides, never a raw transfer, so this screen has
/// no Fund button; the note says where the money comes from instead.
class _FundingNote extends StatelessWidget {
  final VoidCallback? onOpenBudget;
  final VoidCallback? onStartAgain;

  const _FundingNote({required this.onOpenBudget, required this.onStartAgain});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final blue = cs.primary;
    final link = onOpenBudget;
    final restart = onStartAgain;
    return AppSection(
      title: 'How goals are funded',
      child: AppCard(
        key: const ValueKey('goals.fundingNote'),
        variant: AppCardVariant.elevated,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: blue.withValues(alpha: 0.22)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: blue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      kGoalsFundingNote,
                      style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.5,
                        color: cs.onSurface.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (link != null || restart != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (link != null)
                    OutlinedButton(
                      key: const ValueKey('goals.fundingNote.openBudget'),
                      onPressed: link,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(44, 44),
                      ),
                      child: const Text('Open the Savings rows in Budget'),
                    ),
                  if (restart != null)
                    TextButton(
                      key: const ValueKey('goals.fundingNote.startAgain'),
                      onPressed: restart,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 44),
                      ),
                      child: const Text('Start again…'),
                    ),
                ],
              ),
            ],
          ],
        ),
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

/// Restarts a goal against a fresh target, keeping the account and its
/// transaction history. Asks for the new target rather than reusing the old
/// one: a goal worth repeating usually costs something different the next time.
///
/// With an [account] it restarts that goal (an active goal's card or a
/// completed row). With none (the funding note's "Start again…") it first asks
/// which goal, from [TreasuryDashboardPresenter.restartableGoalAccounts] —
/// completed goals first, as on web.
class _RestartGoalSheet extends StatefulWidget {
  final TreasuryDashboardPresenter presenter;
  final FinancialAccount? account;

  const _RestartGoalSheet({required this.presenter, this.account});

  @override
  State<_RestartGoalSheet> createState() => _RestartGoalSheetState();
}

class _RestartGoalSheetState extends State<_RestartGoalSheet> {
  late final TextEditingController _controller;
  late final List<FinancialAccount> _candidates;
  String? _selectedId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _candidates = widget.presenter.restartableGoalAccounts;
    _selectedId = widget.account?.id ?? _candidates.firstOrNull?.id;
    _controller = TextEditingController(text: _targetText(_selected));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  FinancialAccount? get _selected =>
      widget.account ??
      _candidates.where((a) => a.id == _selectedId).firstOrNull;

  static String _targetText(FinancialAccount? a) =>
      (a?.goalTarget ?? 0) > 0 ? a!.goalTarget!.toStringAsFixed(2) : '';

  double? get _target =>
      double.tryParse(_controller.text.replaceAll(',', '').trim());
  bool get _canSave => _selected != null && (_target ?? 0) > 0 && !_saving;

  void _select(String? id) => setState(() {
        _selectedId = id;
        _controller.text = _targetText(_selected);
      });

  Future<void> _save() async {
    final account = _selected;
    final target = _target;
    if (account == null || target == null || target <= 0) return;
    setState(() => _saving = true);
    try {
      await widget.presenter.restartGoalAccount(account.id, newTarget: target);
      if (!mounted) return;
      AppToast.success(context, '${account.name} is tracking a new target');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Could not restart goal: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pickGoal = widget.account == null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          kGoalRestartNote,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        if (pickGoal) ...[
          DropdownButtonFormField<String>(
            key: const ValueKey('goals.startAgain.goal'),
            initialValue: _selectedId,
            decoration: const InputDecoration(labelText: 'Goal'),
            items: [
              for (final a in _candidates)
                DropdownMenuItem(value: a.id, child: Text(a.name)),
            ],
            onChanged: _select,
          ),
          const SizedBox(height: 16),
        ],
        AppTextField(
          controller: _controller,
          label: 'New target',
          prefix: const Text('₱ '),
          autofocus: !pickGoal,
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
          isLoading: _saving,
        ),
      ],
    );
  }
}
