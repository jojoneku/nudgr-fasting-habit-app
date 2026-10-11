import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/account_badge.dart';
import 'package:intermittent_fasting/utils/amount_input_formatter.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';
import 'package:intl/intl.dart';
import '../../design/account_category_label.dart';
import '../../web_keys.dart';
import '../../widgets/web_widgets.dart';
import '../setup/web_account_form_dialog.dart';

/// Gap between cards — the canvas grid gap.
const double _gap = 20;

/// Narrowest a goal card goes before the grid drops a column: three columns
/// across the 1120 px content column at 1440, two at 760. Four columns fit
/// the maths but not the names ("Buy Something Nice Fund" truncated).
const double _minCardWidth = 340;

final _completedFmt = DateFormat('MMM d, yyyy');

/// Web Goals page (Plan 063 Phase 9) — the canvas layout in
/// `docs/design-reference/web-v2/Goals.dc.html`: a page header with Add goal,
/// a TOTAL SAVED hero with a three-cell strip, a grid of goal cards, the
/// Savings & investments table and the funding-model note.
///
/// Every figure and every mutation comes from [TreasuryDashboardPresenter],
/// through exactly the members the mobile `GoalsSavingsScreen` uses:
/// `activeGoalAccounts`, `completedGoalAccounts`, `savingsAccounts`,
/// `totalSavingsAndGoals`, `addAccount`, `restartGoalAccount`,
/// `markGoalRedeemed`, `archiveGoal`. Goals are funded through budget
/// set-asides, never a raw transfer, so there is no Fund button: a goal with
/// nothing in it offers "Set a monthly amount", which [onSetMonthlyAmount]
/// routes to the Budget page's Savings rows.
class WebGoalsPage extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  /// Funding note's "Open the Savings rows in Budget".
  final VoidCallback? onOpenBudget;

  /// Savings table's "Manage in Setup ›".
  final VoidCallback? onOpenSetup;

  /// A not-started goal's "Set a monthly amount" — the integrator opens the
  /// Budget set-aside dialog for that goal account.
  final ValueChanged<FinancialAccount>? onSetMonthlyAmount;

  /// Slot after the header actions — the shell's Nudgy button when the fixed
  /// rail is not on screen.
  final Widget? trailing;

  const WebGoalsPage({
    super.key,
    required this.presenter,
    this.onOpenBudget,
    this.onOpenSetup,
    this.onSetMonthlyAmount,
    this.trailing,
  });

  // ── Dialogs ──────────────────────────────────────────────────────────────

  Future<void> _addGoal(BuildContext context) async {
    final added = await showWebDialog<FinancialAccount>(
      context,
      builder: (_) => _AddGoalDialog(presenter: presenter),
    );
    if (added == null || !context.mounted) return;
    AppToast.success(context, 'Added ${added.name}');
  }

  void _edit(BuildContext context, FinancialAccount account) {
    WebAccountFormDialog.show(context, presenter, existing: account);
  }

  Future<void> _startAgain(
      BuildContext context, FinancialAccount? account) async {
    final restarted = await showWebDialog<FinancialAccount>(
      context,
      builder: (_) =>
          _RestartGoalDialog(presenter: presenter, account: account),
    );
    if (restarted == null || !context.mounted) return;
    AppToast.success(context, '${restarted.name} is tracking a new target');
  }

  Future<void> _markSpent(
      BuildContext context, FinancialAccount account) async {
    final ok = await showWebConfirm(
      context,
      title: 'Spent ${account.name}?',
      message: 'Marks this goal complete and files it under Completed. The '
          'money and its transactions stay in your ledger either way — this '
          'only records that you spent it on what you were saving for.',
      confirmLabel: 'Yes, spent it',
      destructive: false,
    );
    if (!ok) return;
    await presenter.markGoalRedeemed(account.id);
    if (!context.mounted) return;
    AppToast.success(context, 'Filed ${account.name} under Completed');
  }

  Future<void> _archive(BuildContext context, FinancialAccount account) async {
    final ok = await showWebConfirm(
      context,
      title: 'Archive ${account.name}?',
      message: 'Files it away and takes it out of your account pickers. '
          'Nothing is deleted — the transactions stay in your ledger, and you '
          'can bring it back from the accounts list any time.',
      confirmLabel: 'Archive',
      destructive: false,
    );
    if (!ok) return;
    await presenter.archiveGoal(account.id);
    if (!context.mounted) return;
    AppToast.success(context, 'Archived ${account.name}');
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) {
        if (presenter.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        final figures = _GoalsFigures.of(presenter);
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WebPageHeaderV2(
                title: 'Goals',
                subtitle: figures.subtitle,
                actions: [
                  _SuccessButton(
                    key: WebKeys.goalsAddGoal,
                    label: 'Add goal',
                    onPressed: () => _addGoal(context),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
              if (figures.isEmpty)
                _EmptyState(onAddGoal: () => _addGoal(context))
              else ...[
                _TotalSavedHero(figures: figures),
                const SizedBox(height: _gap),
                if (figures.hasCards) ...[
                  _GoalGrid(
                    figures: figures,
                    onEdit: (a) => _edit(context, a),
                    onSetMonthlyAmount: onSetMonthlyAmount,
                    onMarkSpent: (a) => _markSpent(context, a),
                    onStartAgain: (a) => _startAgain(context, a),
                    onArchive: (a) => _archive(context, a),
                  ),
                  const SizedBox(height: _gap),
                ],
                _SavingsTable(
                  presenter: presenter,
                  figures: figures,
                  onOpenSetup: onOpenSetup,
                ),
                const SizedBox(height: _gap),
                _FundingNote(
                  onOpenBudget: onOpenBudget,
                  onStartAgain: figures.restartable.isEmpty
                      ? null
                      : () => _startAgain(context, null),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ===========================================================================
// Figures — read once per build from the presenter
// ===========================================================================

/// The page's numbers, read from the presenter once per build so the widget
/// tree below carries no filtering of its own. Everything here is a view of
/// presenter-owned lists; no goal rule lives in this file.
class _GoalsFigures {
  final List<FinancialAccount> active;
  final List<FinancialAccount> completed;
  final List<FinancialAccount> plainSavings;
  final List<FinancialAccount> investments;
  final double totalSaved;
  final double thisMonth;
  final double setAsideAllocated;
  final double setAsideFunded;

  const _GoalsFigures({
    required this.active,
    required this.completed,
    required this.plainSavings,
    required this.investments,
    required this.totalSaved,
    required this.thisMonth,
    required this.setAsideAllocated,
    required this.setAsideFunded,
  });

  factory _GoalsFigures.of(TreasuryDashboardPresenter p) {
    final setAsides = p.setAsidesThisMonth;
    return _GoalsFigures(
      active: p.activeGoalAccounts,
      completed: p.completedGoalAccounts,
      plainSavings:
          p.savingsAccounts.where((a) => (a.goalTarget ?? 0) <= 0).toList(),
      investments: p.accounts
          .where((a) => a.isActive && a.category == AccountCategory.investment)
          .toList(),
      totalSaved: p.totalSavingsAndGoals,
      thisMonth: p.monthSavingsContributions,
      setAsideAllocated: setAsides.fold(0.0, (s, e) => s + e.allocated),
      setAsideFunded: setAsides.fold(0.0, (s, e) => s + e.funded),
    );
  }

  bool get isEmpty =>
      active.isEmpty &&
      completed.isEmpty &&
      plainSavings.isEmpty &&
      investments.isEmpty;

  bool get hasCards => active.isNotEmpty || completed.isNotEmpty;

  /// Goals with money in them, against the ones still at ₱0.
  List<FinancialAccount> get started =>
      active.where((a) => !isNotStarted(a)).toList();
  List<FinancialAccount> get notStarted => active.where(isNotStarted).toList();

  /// Goals the Start again dialog can offer: completed first, then live goal
  /// accounts (a savings account with a target is not restartable).
  List<FinancialAccount> get restartable => [
        ...completed,
        ...active.where((a) => a.category == AccountCategory.goal),
      ];

  double get savedTowardTargets =>
      active.fold(0.0, (s, a) => s + math.max(0.0, a.balance));
  double get totalTarget => active.fold(0.0, (s, a) => s + (a.goalTarget ?? 0));
  double? get shareOfTargets =>
      totalTarget > 0 ? savedTowardTargets / totalTarget : null;

  String get subtitle {
    if (active.isEmpty) return 'Funded through budget set-asides';
    final n = active.length;
    return '$n ${n == 1 ? 'goal' : 'goals'} · '
        '${formatPeso(savedTowardTargets)} saved of ${formatPeso(totalTarget)}'
        ' · funded through budget set-asides';
  }

  static bool isNotStarted(FinancialAccount a) =>
      a.balance <= 0 && a.goalStage != GoalStage.funded;
}

// ===========================================================================
// Hero
// ===========================================================================

class _TotalSavedHero extends StatelessWidget {
  final _GoalsFigures figures;
  const _TotalSavedHero({required this.figures});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final green = context.appColors.success;
    final share = figures.shareOfTargets;
    final caption = [
      '${formatPesoSigned(figures.thisMonth)} this month',
      if (share != null) '${formatPercent(share)} of all targets',
    ].join(' · ');

    return WebHeroCard(
      key: WebKeys.goalsHero,
      accent: green,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.savings_rounded, size: 18, color: green),
              const SizedBox(width: WebInsets.sm),
              Text(
                'TOTAL SAVED',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: green,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: WebInsets.sm),
          Text(
            formatPeso(figures.totalSaved),
            style: webNumericStyle(
              theme.textTheme.displaySmall?.copyWith(
                fontSize: 44,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
                height: 1.05,
              ),
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: WebInsets.xs),
          Text(
            caption,
            style: webNumericStyle(
              theme.textTheme.bodySmall?.copyWith(fontSize: 13),
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: WebInsets.lg),
          WebStatStrip(
            onCard: true,
            items: [
              WebStat(
                label: 'Active',
                value: '${figures.started.length} funded',
                caption: 'of ${figures.active.length} '
                    '${figures.active.length == 1 ? 'goal' : 'goals'}',
                tone: WebStatTone.success,
              ),
              WebStat(
                label: 'Not started',
                value: '${figures.notStarted.length}',
                caption: 'nothing set aside yet',
              ),
              WebStat(
                label: 'Set-asides this month',
                value: formatPeso(figures.setAsideAllocated),
                caption: '${formatPeso(figures.setAsideFunded)} funded so far',
                tone: WebStatTone.info,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Goal card grid
// ===========================================================================

class _GoalGrid extends StatelessWidget {
  final _GoalsFigures figures;
  final ValueChanged<FinancialAccount> onEdit;
  final ValueChanged<FinancialAccount>? onSetMonthlyAmount;
  final ValueChanged<FinancialAccount> onMarkSpent;
  final ValueChanged<FinancialAccount> onStartAgain;
  final ValueChanged<FinancialAccount> onArchive;

  const _GoalGrid({
    required this.figures,
    required this.onEdit,
    required this.onSetMonthlyAmount,
    required this.onMarkSpent,
    required this.onStartAgain,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final cards = [...figures.active, ...figures.completed];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns =
            math.max(1, ((width + _gap) / (_minCardWidth + _gap)).floor());
        final cardWidth = (width - _gap * (columns - 1)) / columns;
        return KeyedSubtree(
          key: WebKeys.goalsGrid,
          child: Wrap(
            spacing: _gap,
            runSpacing: _gap,
            children: [
              for (var i = 0; i < cards.length; i++)
                SizedBox(
                  width: cardWidth,
                  child: WebGoalCard(
                    account: cards[i],
                    index: i,
                    onEdit: () => onEdit(cards[i]),
                    onSetMonthlyAmount: onSetMonthlyAmount == null
                        ? null
                        : () => onSetMonthlyAmount!(cards[i]),
                    onMarkSpent: () => onMarkSpent(cards[i]),
                    onStartAgain: () => onStartAgain(cards[i]),
                    onArchive: () => onArchive(cards[i]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// One goal in the grid: icon tile, name, the percentage (or a status pill),
/// the bar, "₱saved of ₱target", and the ⋯ menu. A goal with nothing in it
/// gets a dashed border and "Set a monthly amount"; a completed one shows
/// what it delivered instead of a bar at 0%.
class WebGoalCard extends StatelessWidget {
  final FinancialAccount account;
  final int index;
  final VoidCallback onEdit;
  final VoidCallback? onSetMonthlyAmount;
  final VoidCallback onMarkSpent;
  final VoidCallback onStartAgain;
  final VoidCallback onArchive;

  const WebGoalCard({
    super.key,
    required this.account,
    required this.index,
    required this.onEdit,
    required this.onSetMonthlyAmount,
    required this.onMarkSpent,
    required this.onStartAgain,
    required this.onArchive,
  });

  bool get _completed => account.goalStage == GoalStage.redeemed;
  bool get _reached => account.goalStage == GoalStage.funded;
  bool get _notStarted => !_completed && _GoalsFigures.isNotStarted(account);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final green = context.appColors.success;
    final a = account;
    final target = a.goalTarget ?? 0;
    // `goalProgress` pins a reached goal at 100%, so spending it doesn't make
    // the bar collapse as though it was never saved for.
    final progress = a.hasGoalTarget
        ? a.goalProgress
        : (target > 0 ? (a.balance / target).clamp(0.0, 1.0) : 0.0);
    final tileColor = _notStarted
        ? cs.surfaceContainerHigh
        : resolveSliceColor(a.colorHex, index, brightness: theme.brightness);
    final iconColor =
        _notStarted ? cs.onSurfaceVariant : accountBadgeForeground(tileColor);
    final barColor = _reached || _completed ? green : tileColor;

    final Widget status;
    if (_completed) {
      status = const WebBadge('Completed',
          tone: WebBadgeTone.success, icon: Icons.check_rounded);
    } else if (_reached) {
      status = const WebBadge('Reached', tone: WebBadgeTone.success);
    } else if (_notStarted) {
      status = const WebBadge('Not started');
    } else {
      status = Text(
        '${(progress * 100).round()}%',
        style: webNumericStyle(
          theme.textTheme.titleLarge
              ?.copyWith(fontSize: 20, fontWeight: FontWeight.w800),
          color: cs.onSurface,
        ),
      );
    }

    final menu = WebRowMenu(
      key: WebKeys.goalsCardMenu,
      tooltip: '${a.name} actions',
      items: [
        WebMenuItem('Edit',
            key: WebKeys.goalsCardEdit,
            icon: Icons.edit_outlined,
            onTap: onEdit),
        if (_reached)
          WebMenuItem('Mark as spent',
              key: WebKeys.goalsCardMarkSpent,
              icon: Icons.check_circle_outline,
              onTap: onMarkSpent),
        if (a.category == AccountCategory.goal)
          WebMenuItem('Start again',
              key: WebKeys.goalsCardStartAgain,
              icon: Icons.restart_alt_rounded,
              onTap: onStartAgain),
        if (_completed)
          WebMenuItem('Archive',
              key: WebKeys.goalsCardArchive,
              icon: Icons.inventory_2_outlined,
              onTap: onArchive),
      ],
    );

    final muted = theme.textTheme.bodySmall
        ?.copyWith(fontSize: 12.5, color: cs.onSurfaceVariant);

    final Widget footer;
    if (_completed) {
      final funded = a.goalRedeemedAmount ?? target;
      final on = a.goalRedeemedAt;
      footer = Text(
        'Funded ${formatPeso(funded)}'
        '${on == null ? '' : ' · spent ${_completedFmt.format(on)}'}',
        style: webNumericStyle(muted),
      );
    } else {
      // A Wrap, not a Row: on a narrow card the action drops under the
      // figures instead of squeezing them.
      footer = Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: WebInsets.sm,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: formatPeso(a.balance),
                  style: TextStyle(
                      color: cs.onSurface, fontWeight: FontWeight.w700),
                ),
                TextSpan(text: ' of ${formatPeso(target)}'),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: webNumericStyle(muted),
          ),
          if (_notStarted && onSetMonthlyAmount != null)
            TextButton(
              key: WebKeys.goalsCardSetMonthly,
              onPressed: onSetMonthlyAmount,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, kWebHitTarget),
                padding: const EdgeInsets.symmetric(horizontal: WebInsets.sm),
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              child: const Text('Set a monthly amount'),
            ),
        ],
      );
    }

    final body = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top-aligned so a name that wraps to two lines grows downward
          // while the tile, the pill and the menu stay on the first line;
          // a one-line name centres against the 36 px tile.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WebRowTile(
                color: tileColor,
                size: 36,
                child: Icon(accountIconFor(a), size: 18, color: iconColor),
              ),
              const SizedBox(width: WebInsets.sm),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 36),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      a.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        height: 1.25,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Capped so a long pill never pushes the menu off the card;
              // it scales down instead of overflowing.
              SizedBox(
                height: 36,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 112),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: status,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: WebInsets.xs),
              SizedBox(height: 36, child: Center(child: menu)),
            ],
          ),
          const SizedBox(height: WebInsets.md),
          Padding(
            padding: const EdgeInsets.only(right: WebInsets.sm),
            child: WebProgressBar(
              value: _completed ? 1 : progress.toDouble(),
              color: barColor,
              height: 8,
            ),
          ),
          const SizedBox(height: WebInsets.md),
          Padding(
            padding: const EdgeInsets.only(right: WebInsets.sm),
            child: footer,
          ),
        ],
      ),
    );

    final radius = BorderRadius.circular(16);
    if (_notStarted) {
      return CustomPaint(
        foregroundPainter: _DashedBorderPainter(color: cs.outline, radius: 16),
        child: Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: radius,
          ),
          child: body,
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: radius,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: body,
    );
  }
}

/// The canvas's `border-style: dashed` for a goal that has not started.
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  const _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rect = (Offset.zero & size).deflate(0.5);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    const dash = 6.0;
    const space = 4.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
            metric.extractPath(d, math.min(d + dash, metric.length)), paint);
        d += dash + space;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

// ===========================================================================
// Savings & investments
// ===========================================================================

class _SavingsTable extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  final _GoalsFigures figures;
  final VoidCallback? onOpenSetup;

  const _SavingsTable({
    required this.presenter,
    required this.figures,
    required this.onOpenSetup,
  });

  /// Where the money physically sits: the parent account for a pocket, else
  /// the account's own type.
  String _storedIn(FinancialAccount a) {
    final parentId = a.parentAccountId;
    if (parentId != null) {
      final parent =
          presenter.accounts.where((p) => p.id == parentId).firstOrNull;
      if (parent != null) return parent.name;
    }
    return a.category.label;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final rows = [...figures.plainSavings, ...figures.investments];
    return WebCard(
      key: WebKeys.goalsSavingsTable,
      title: 'Savings & investments',
      description: 'Balances that are not tied to a target',
      trailing: TextButton(
        key: WebKeys.goalsManageSetup,
        onPressed: onOpenSetup,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, kWebHitTarget),
          textStyle:
              const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
        child: const Text('Manage in Setup ›'),
      ),
      padding: const EdgeInsets.fromLTRB(
          WebInsets.xl, WebInsets.xl, WebInsets.xl, WebInsets.sm),
      child: WebDataTable<FinancialAccount>(
        rows: rows,
        emptyLabel: 'No savings or investment accounts yet',
        columns: [
          WebColumn(
            label: 'Account',
            flex: 3,
            cell: (context, a) {
              final tile = resolveSliceColor(a.colorHex, rows.indexOf(a),
                  brightness: theme.brightness);
              return Row(
                children: [
                  WebRowTile(
                    color: tile,
                    size: 30,
                    child: Icon(accountIconFor(a),
                        size: 16, color: accountBadgeForeground(tile)),
                  ),
                  const SizedBox(width: WebInsets.md),
                  Flexible(
                    child: Text(
                      a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              );
            },
          ),
          WebColumn(
            label: 'Stored in',
            flex: 2,
            cell: (context, a) => Text(
              _storedIn(a),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          WebColumn(
            label: 'Balance',
            numeric: true,
            flex: 2,
            cell: (context, a) => Text(
              formatPeso(a.balance),
              style: webNumericStyle(theme.textTheme.bodyMedium)
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Funding note
// ===========================================================================

class _FundingNote extends StatelessWidget {
  final VoidCallback? onOpenBudget;
  final VoidCallback? onStartAgain;
  const _FundingNote({required this.onOpenBudget, required this.onStartAgain});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final blue = cs.primary;
    return WebCard(
      key: WebKeys.goalsFundingNote,
      title: 'How goals are funded',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
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
                    'Each goal is a Savings row in your budget. Money reaches '
                    'it through a set-aside (Bills → Mark paid → Set aside '
                    'into), not through a raw transfer, so the month-end '
                    'outlook stays right. "Start again" clears a completed '
                    'goal\'s spent stamp and starts it toward a new target; '
                    'the account and its history stay put.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12.5,
                      height: 1.5,
                      color: cs.onSurface.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: WebInsets.sm,
            runSpacing: WebInsets.sm,
            children: [
              OutlinedButton(
                key: WebKeys.goalsOpenBudget,
                onPressed: onOpenBudget,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, kWebHitTarget),
                ),
                child: const Text('Open the Savings rows in Budget'),
              ),
              TextButton(
                key: WebKeys.goalsNoteStartAgain,
                onPressed: onStartAgain,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, kWebHitTarget),
                ),
                child: const Text('Start again…'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Empty state
// ===========================================================================

class _EmptyState extends StatelessWidget {
  final VoidCallback onAddGoal;
  const _EmptyState({required this.onAddGoal});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return WebCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: WebInsets.xxl),
        child: Column(
          children: [
            Icon(Icons.flag_outlined,
                size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
            const SizedBox(height: WebInsets.lg),
            Text('No goals yet',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: WebInsets.sm),
            Text(
              'A goal is a fund with a target. Add one, then give it a '
              'monthly set-aside in Budget.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: WebInsets.xl),
            _SuccessButton(
              key: WebKeys.goalsEmptyAddGoal,
              label: 'Add goal',
              onPressed: onAddGoal,
            ),
          ],
        ),
      ),
    );
  }
}

/// The canvas's `.btn.move` — the success-toned filled button used for
/// Add goal (the one action here that moves money toward something).
class _SuccessButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const _SuccessButton({super.key, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final green = context.appColors.success;
    final onGreen =
        ThemeData.estimateBrightnessForColor(green) == Brightness.light
            ? Colors.black87
            : Colors.white;
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: green,
        foregroundColor: onGreen,
      ),
      icon: const Icon(Icons.add_rounded, size: 18),
      label: Text(label),
    );
  }
}

// ===========================================================================
// Add goal dialog
// ===========================================================================

double? _parseAmount(String text) =>
    double.tryParse(text.replaceAll(',', '').trim());

/// Builds the same [FinancialAccount] the mobile `AccountSetupView` builds for
/// a goal (same id generation, default color, icon marker) and calls the same
/// [TreasuryDashboardPresenter.addAccount]. Pops with the new account.
///
/// The canvas also sketches a target date and monthly set-aside chips; the
/// mobile flow creates neither (the account has no target date, and the
/// Savings budget row is added on the Budget page), so they are not here.
class _AddGoalDialog extends StatefulWidget {
  final TreasuryDashboardPresenter presenter;
  const _AddGoalDialog({required this.presenter});

  @override
  State<_AddGoalDialog> createState() => _AddGoalDialogState();
}

class _AddGoalDialogState extends State<_AddGoalDialog> {
  final _name = TextEditingController();
  final _target = TextEditingController();
  final _balance = TextEditingController();
  String? _parentId;
  bool _submitted = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _balance.dispose();
    super.dispose();
  }

  String? get _nameError =>
      _submitted && _name.text.trim().isEmpty ? 'Give the goal a name' : null;

  String? get _targetError =>
      _submitted && (_parseAmount(_target.text) ?? 0) <= 0
          ? 'Enter a target above ₱0'
          : null;

  Future<void> _submit() async {
    setState(() => _submitted = true);
    if (_nameError != null || _targetError != null) return;
    setState(() => _saving = true);
    final id =
        '${DateTime.now().microsecondsSinceEpoch}_${math.Random().nextInt(9999)}';
    final account = FinancialAccount(
      id: id,
      name: _name.text.trim(),
      category: AccountCategory.goal,
      parentAccountId: _parentId,
      balance: _parseAmount(_balance.text) ?? 0,
      colorHex: '#7C3AED',
      icon: AccountCategory.goal.name,
      goalTarget: _parseAmount(_target.text),
    );
    try {
      await widget.presenter.addAccount(account);
      if (mounted) Navigator.of(context).pop(account);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Could not save goal: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final liquid = widget.presenter.liquidAccounts;
    return WebDialog(
      key: WebKeys.goalsAddGoalDialog,
      title: 'Add goal',
      onSubmit: _saving ? null : _submit,
      subtitle: 'A fund with a target. It is funded through budget set-asides.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          WebField(
            label: 'Name',
            error: _nameError,
            child: WebInput(
              key: WebKeys.goalsAddGoalName,
              controller: _name,
              hint: 'Travel Fund',
              autofocus: true,
              error: _nameError != null,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: WebInsets.lg),
          WebField(
            label: 'Target',
            error: _targetError,
            child: WebInput.amount(
              key: WebKeys.goalsAddGoalTarget,
              controller: _target,
              inputFormatters: amountInputFormatters,
              error: _targetError != null,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (liquid.isNotEmpty) ...[
            const SizedBox(height: WebInsets.lg),
            WebField(
              label: 'Stored in',
              optional: true,
              helper: 'The account that physically holds the money. Its '
                  'balance already counts this goal.',
              child: DropdownButtonFormField<String?>(
                key: WebKeys.goalsAddGoalStoredIn,
                initialValue: _parentId,
                decoration: WebInput.decoration(context),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Its own account')),
                  for (final a in liquid)
                    DropdownMenuItem<String?>(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) => setState(() => _parentId = v),
              ),
            ),
          ],
          const SizedBox(height: WebInsets.lg),
          WebMoreOptions(
            children: [
              WebField(
                label: 'Starting balance',
                optional: true,
                helper: 'Only if money is already set aside for it.',
                child: WebInput.amount(
                  controller: _balance,
                  inputFormatters: amountInputFormatters,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ],
      ),
      secondary: TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      primary: _SuccessButton(
        key: WebKeys.goalsAddGoalSubmit,
        label: 'Add goal',
        onPressed: _saving ? null : _submit,
      ),
    );
  }
}

// ===========================================================================
// Start again dialog
// ===========================================================================

/// The mobile `_RestartGoalSheet` as a [WebDialog]: the same copy, a New
/// target field, and the same [TreasuryDashboardPresenter.restartGoalAccount].
/// With no [account] (the funding note's "Start again…") it first asks which
/// goal, completed goals listed first. Pops with the restarted account.
class _RestartGoalDialog extends StatefulWidget {
  final TreasuryDashboardPresenter presenter;
  final FinancialAccount? account;
  const _RestartGoalDialog({required this.presenter, this.account});

  @override
  State<_RestartGoalDialog> createState() => _RestartGoalDialogState();
}

class _RestartGoalDialogState extends State<_RestartGoalDialog> {
  late final TextEditingController _controller;
  late List<FinancialAccount> _candidates;
  String? _selectedId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _candidates = _GoalsFigures.of(widget.presenter).restartable;
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

  double? get _target => _parseAmount(_controller.text);
  bool get _canSave => _selected != null && (_target ?? 0) > 0 && !_saving;

  Future<void> _save() async {
    final account = _selected;
    final target = _target;
    if (account == null || target == null || target <= 0) return;
    setState(() => _saving = true);
    try {
      await widget.presenter.restartGoalAccount(account.id, newTarget: target);
      if (mounted) Navigator.of(context).pop(account);
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
    final cs = theme.colorScheme;
    final fixed = widget.account;
    return WebDialog(
      key: WebKeys.goalsStartAgainDialog,
      onSubmit: _canSave ? _save : null,
      title: fixed != null ? 'Start ${fixed.name} again' : 'Start a goal again',
      primaryExpands: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Clears the completed stamp and starts tracking toward a new '
            'target. The account and everything in its history stay put.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: WebInsets.lg),
          if (fixed == null) ...[
            WebField(
              label: 'Goal',
              child: DropdownButtonFormField<String>(
                key: WebKeys.goalsStartAgainGoal,
                initialValue: _selectedId,
                decoration: WebInput.decoration(context),
                items: [
                  for (final a in _candidates)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) => setState(() {
                  _selectedId = v;
                  _controller.text = _targetText(_selected);
                }),
              ),
            ),
            const SizedBox(height: WebInsets.lg),
          ],
          WebField(
            label: 'New target',
            child: WebInput.amount(
              key: WebKeys.goalsStartAgainTarget,
              controller: _controller,
              autofocus: true,
              inputFormatters: amountInputFormatters,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
      secondary: TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      primary: FilledButton.icon(
        key: WebKeys.goalsStartAgainSubmit,
        onPressed: _canSave ? _save : null,
        icon: const Icon(Icons.restart_alt_rounded, size: 18),
        label: const Text('Start again'),
      ),
    );
  }
}
