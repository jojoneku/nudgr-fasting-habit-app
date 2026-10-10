import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/account_badge.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';
import '../../design/account_category_label.dart';
import '../../web_keys.dart';
import '../../widgets/web_widgets.dart';
import 'web_account_inventory_dialog.dart';

/// Budget rows at or above this share of their allocation read "Watch".
// TODO(Plan 063 Phase 6): read kBudgetWatchThreshold from budget_presenter.dart
// so the dashboard and the Budget page agree (today: 0.85 here vs 0.75 there).
const double _kBudgetWatchThreshold = 0.85;

/// Named slices in "Where your money goes"; the rest fold into "Other (n)".
const int _kMaxDonutSlices = 6;

/// Gap between cards — the canvas grid gap (20 px), between `WebInsets.lg`
/// and `.xl`.
const double _gap = 20;

/// Under this content width the hero row and the two card columns stack.
const double _twoColMin = 900;

/// Web Dashboard, v2 (Plan 063 Phase 3) — the canvas layout in
/// `docs/design-reference/web-v2/Main.dc.html`: one page header, a hero row
/// (net worth + month-end outlook statement), then two card columns. Every
/// figure comes from [TreasuryDashboardPresenter]; this file lays them out.
///
/// The shell owns the right rail (Nudgy, Coming up), the content width and
/// the page padding — none of that is rendered here.
class WebDashboardPageV2 extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  /// Owns the credit-card payment path ([BillsReceivablesPresenter.quickPayCard])
  /// behind each card's "Pay now", so paying also reconciles the statement bill.
  final BillsReceivablesPresenter billsPresenter;

  /// Empty state's "Add your first account" → Setup & Accounts.
  final VoidCallback? onOpenSetup;

  /// "Add transaction" falls back to this when [onAddTransaction] is null,
  /// matching the canvas (the button links to the Ledger).
  final VoidCallback? onOpenLedger;

  /// Credit card's "All cards ›".
  final VoidCallback? onOpenBills;

  /// Budget health's "Open budget ›".
  final VoidCallback? onOpenBudget;

  /// Savings goals' "Goals ›".
  final VoidCallback? onOpenGoals;

  /// Header primary action. Null → [onOpenLedger]; both null → disabled.
  final VoidCallback? onAddTransaction;

  /// Slot after the header actions — the integrator passes the shell's
  /// `NudgyHeaderButton` here when the fixed rail is not on screen.
  final Widget? trailing;

  const WebDashboardPageV2({
    super.key,
    required this.presenter,
    required this.billsPresenter,
    this.onOpenSetup,
    this.onOpenLedger,
    this.onOpenBills,
    this.onOpenBudget,
    this.onOpenGoals,
    this.onAddTransaction,
    this.trailing,
  });

  /// Days left in [monthKey] after [now]'s date — 0 when [now] is outside
  /// that month. Pure date arithmetic for the header subtitle; the presenter
  /// has no calendar notion of "days left".
  static int daysLeft(String monthKey, DateTime now) {
    final first = DateTime.parse('$monthKey-01');
    if (first.year != now.year || first.month != now.month) return 0;
    final last = DateTime(first.year, first.month + 1, 0).day;
    return math.max(0, last - now.day);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) {
        if (presenter.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!presenter.hasAccounts) {
          return _EmptyState(onOpenSetup: onOpenSetup);
        }
        final left = daysLeft(presenter.currentMonth, DateTime.now());
        final addTransaction = onAddTransaction ?? onOpenLedger;
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WebPageHeaderV2(
                title: 'Dashboard',
                subtitle:
                    '${monthLabel(presenter.currentMonth)} · $left ${left == 1 ? 'day' : 'days'} left',
                actions: [
                  FilledButton.icon(
                    key: WebKeys.dashboardAddTransaction,
                    onPressed: addTransaction,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add transaction'),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
              _HeroRow(presenter: presenter),
              const SizedBox(height: _gap),
              _Columns(
                presenter: presenter,
                billsPresenter: billsPresenter,
                onOpenBills: onOpenBills,
                onOpenBudget: onOpenBudget,
                onOpenGoals: onOpenGoals,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ===========================================================================
// Hero row — net worth (2/3) + month-end outlook (1/3)
// ===========================================================================

class _HeroRow extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  const _HeroRow({required this.presenter});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hero = _NetWorthHero(presenter: presenter);
        final outlook = _OutlookCard(presenter: presenter);
        if (constraints.maxWidth < _twoColMin) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [hero, const SizedBox(height: _gap), outlook],
          );
        }
        // Stretch both to one height so the hero's sparkline can sit on its
        // bottom edge while the six-row statement decides the row height.
        // Nothing inside this row may use a LayoutBuilder (IntrinsicHeight).
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 2, child: hero),
              const SizedBox(width: _gap),
              Expanded(flex: 1, child: outlook),
            ],
          ),
        );
      },
    );
  }
}

/// The net-worth hero: eyebrow + trend pill, 52/800 figure, "±₱X this month",
/// a three-cell position strip, and the sparkline bleeding to the card's
/// bottom edge. Same figures as `WebNetWorthHero` + the old position row.
class _NetWorthHero extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  const _NetWorthHero({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final appColors = context.appColors;
    final blue = appColors.fast;
    final p = presenter;

    final trend = p.netWorthTrend();
    final spark = AppSparkline(
      values: [for (final t in trend) t.value],
      color: blue,
      height: 56,
      strokeWidth: 2.5,
      endDotRadius: 3.5,
    );
    final delta = p.netWorthMonthDelta;
    final pct = p.netWorthMonthDeltaPct;
    final flow = p.monthNetCashFlow;

    return WebHeroCard(
      key: WebKeys.dashboardNetWorthHero,
      accent: blue,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  WebInsets.xl, WebInsets.xl, WebInsets.xl, WebInsets.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _Eyebrow('NET WORTH', color: blue),
                      const Spacer(),
                      if (pct != null) _TrendPill(pct: pct),
                    ],
                  ),
                  const SizedBox(height: WebInsets.sm),
                  WebNumber(
                    formatPeso(p.netWorth),
                    size: WebNumberSize.hero,
                    weight: FontWeight.w800,
                  ),
                  const SizedBox(height: WebInsets.xs),
                  _ThisMonthLine(delta: delta),
                  const SizedBox(height: WebInsets.lg),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _HeroCell(
                          label: 'NET CASH FLOW',
                          value:
                              '${flow >= 0 ? '↑ ' : '↓ '}${formatPeso(flow.abs())}',
                          caption: 'Income less spending',
                          valueColor: flow >= 0 ? appColors.success : cs.error,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _HeroCell(
                          label: 'LIQUID CASH',
                          value: formatPeso(p.totalLiquidCash),
                          caption: 'Spendable across accounts',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _HeroCell(
                          label: 'TOTAL ASSETS',
                          value: formatPeso(p.totalAssets),
                          caption: 'Cash, savings & goals',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Pushes the sparkline to the bottom edge when the outlook card
            // makes the row taller than the hero's own content.
            const Spacer(),
            if (spark.hasTrend) spark,
          ],
        ),
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  final String text;
  final Color? color;
  const _Eyebrow(this.text, {this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(
        color: color ?? context.appColors.textTertiary,
        fontSize: 10.5,
        letterSpacing: 0.9,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// One of the three wells inside the hero (net cash flow, liquid, assets).
class _HeroCell extends StatelessWidget {
  final String label;
  final String value;
  final String caption;
  final Color? valueColor;
  const _HeroCell({
    required this.label,
    required this.value,
    required this.caption,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        // A translucent well over the gradient: darker than the hero in dark
        // mode, lighter in light mode — the surface tint does both.
        color: cs.surface.withValues(alpha: isDark ? 0.38 : 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Eyebrow(label, color: context.appColors.fast),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: webNumericStyle(
              theme.textTheme.titleMedium?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
              color: valueColor ?? cs.onSurface,
            ),
          ),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: context.appColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Signed month-over-month percentage pill — success when up, error when down.
class _TrendPill extends StatelessWidget {
  final double pct;
  const _TrendPill({required this.pct});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final up = pct >= 0;
    final color = up ? context.appColors.success : theme.colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            '${up ? '+' : ''}${(pct * 100).toStringAsFixed(1)}%',
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// "±₱X this month", coloured by direction; "Tracking this month" when there
/// is no prior month-end to compare against.
class _ThisMonthLine extends StatelessWidget {
  final double? delta;
  const _ThisMonthLine({required this.delta});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = context.appColors.textMuted;
    final d = delta;
    if (d == null) {
      return Text(
        'Tracking this month',
        style: theme.textTheme.bodySmall?.copyWith(color: muted),
      );
    }
    final up = d >= 0;
    final color = up ? context.appColors.success : theme.colorScheme.error;
    return Row(
      children: [
        Text(
          '${up ? '+' : '−'}${formatPeso(d.abs())}',
          style: webNumericStyle(theme.textTheme.bodyMedium, color: color)
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 5),
        Text(
          'this month',
          style: theme.textTheme.bodyMedium?.copyWith(color: muted),
        ),
      ],
    );
  }
}

// ===========================================================================
// Month-end outlook — the projection chain as one vertical statement
// ===========================================================================

/// The same six presenter figures the old tile row showed, as a statement:
///   Liquid now + To receive − Upcoming bills − Set-asides due − Budget left
///     = Projected month-end.
/// Signs are on the amounts, colours carry the meaning; labels stay plain.
class _OutlookCard extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  const _OutlookCard({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final appColors = context.appColors;
    final p = presenter;
    final projected = p.forecastedNetBalance;
    final projectedTone = projected >= 0 ? appColors.success : cs.error;

    return WebCard(
      key: WebKeys.dashboardOutlook,
      title: 'Month-end outlook',
      description: "How this month's cash gets to the finish line",
      padding: const EdgeInsets.fromLTRB(
          WebInsets.xl, WebInsets.lg + 2, WebInsets.xl, WebInsets.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _OutlookRow(
            label: 'Liquid now',
            caption: 'Cash across accounts',
            amount: _signedNegative(p.totalLiquidCash),
          ),
          _OutlookRow(
            label: 'To receive',
            caption: 'Money owed to you',
            amount: '+${formatPeso(p.pendingReceivables)}',
            color: appColors.success,
          ),
          _OutlookRow(
            label: 'Upcoming bills',
            caption: 'Unpaid this month',
            amount: '−${formatPeso(p.monthUnpaidBills)}',
            color: appColors.bills,
          ),
          _OutlookRow(
            label: 'Set-asides due',
            caption: 'Still to fund',
            amount: '−${formatPeso(p.budgetedExpensesRemaining)}',
            color: appColors.bills,
          ),
          _OutlookRow(
            label: 'Budget left',
            caption: 'Still budgeted to spend',
            amount: '−${formatPeso(p.budgetRemainingNetOfObligations)}',
            color: appColors.bills,
            divider: false,
          ),
          const SizedBox(height: WebInsets.sm),
          Container(
            padding: const EdgeInsets.all(WebInsets.md),
            decoration: BoxDecoration(
              color: projectedTone.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: projectedTone.withValues(alpha: 0.25)),
            ),
            child: _OutlookLine(
              label: 'Projected month-end',
              caption: 'After bills, budget & savings',
              amount: _signedNegative(projected),
              color: projectedTone,
              emphasis: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// `₱X` for a non-negative amount, `−₱X` for a negative one — the figure a
/// row shows for a balance that may have gone below zero.
String _signedNegative(double amount) =>
    amount < 0 ? '−${formatPeso(amount.abs())}' : formatPeso(amount);

class _OutlookRow extends StatelessWidget {
  final String label;
  final String caption;
  final String amount;
  final Color? color;
  final bool divider;
  const _OutlookRow({
    required this.label,
    required this.caption,
    required this.amount,
    this.color,
    this.divider = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: divider
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: cs.outlineVariant)),
            )
          : null,
      child: _OutlookLine(
        label: label,
        caption: caption,
        amount: amount,
        color: color,
      ),
    );
  }
}

class _OutlookLine extends StatelessWidget {
  final String label;
  final String caption;
  final String amount;
  final Color? color;
  final bool emphasis;
  const _OutlookLine({
    required this.label,
    required this.caption,
    required this.amount,
    this.color,
    this.emphasis = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final labelColor = color ?? cs.onSurfaceVariant;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 13.5,
                  color: labelColor,
                  fontWeight: emphasis ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: emphasis
                      ? labelColor.withValues(alpha: 0.8)
                      : context.appColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: WebInsets.md),
        Text(
          amount,
          textAlign: TextAlign.right,
          style: webNumericStyle(
            theme.textTheme.bodyMedium?.copyWith(
              fontSize: emphasis ? 20 : 13.5,
              fontWeight: FontWeight.w700,
            ),
            color: color ?? cs.onSurface,
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// Two card columns
// ===========================================================================

class _Columns extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  final BillsReceivablesPresenter billsPresenter;
  final VoidCallback? onOpenBills;
  final VoidCallback? onOpenBudget;
  final VoidCallback? onOpenGoals;
  const _Columns({
    required this.presenter,
    required this.billsPresenter,
    required this.onOpenBills,
    required this.onOpenBudget,
    required this.onOpenGoals,
  });

  @override
  Widget build(BuildContext context) {
    final left = <Widget>[
      _AccountsCard(presenter: presenter),
      _CashFlowCard(presenter: presenter),
      _BudgetHealthCard(presenter: presenter, onOpenBudget: onOpenBudget),
    ];
    final right = <Widget>[
      _TrendsCard(presenter: presenter),
      _WhereMoneyGoesCard(presenter: presenter),
      if (presenter.creditAccounts.isNotEmpty)
        _CreditCard(
          presenter: presenter,
          billsPresenter: billsPresenter,
          onOpenBills: onOpenBills,
        ),
      _SavingsGoalsCard(presenter: presenter, onOpenGoals: onOpenGoals),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _twoColMin) {
          return _stack([...left, ...right]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _stack(left)),
            const SizedBox(width: _gap),
            Expanded(child: _stack(right)),
          ],
        );
      },
    );
  }

  Widget _stack(List<Widget> cards) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: _gap),
            cards[i],
          ],
        ],
      );
}

/// "All N ›" / "Open budget ›" — a text link in a card header, sized to the
/// 44 px hit target.
class _HeaderLink extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const _HeaderLink({super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(kWebHitTarget, kWebHitTarget),
        padding: const EdgeInsets.symmetric(horizontal: WebInsets.sm),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      child: Text('$label ›'),
    );
  }
}

// ===========================================================================
// Accounts — liquid + credit, as a table
// ===========================================================================

class _AccountsCard extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  const _AccountsCard({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = presenter;
    final held = p.heldAmountByAccountId;
    final liquid = p.liquidAccounts;
    final credit = p.creditAccounts;
    final accounts = [...liquid, ...credit];

    return WebCard(
      title: 'Accounts',
      description: credit.isEmpty
          ? '${formatPeso(p.totalLiquidCash)} liquid'
          : '${formatPeso(p.totalLiquidCash)} liquid · ${formatPeso(p.totalCreditAvailable)} credit available across ${credit.length} ${credit.length == 1 ? 'line' : 'lines'}',
      trailing: _HeaderLink(
        key: WebKeys.dashboardAllAccounts,
        label: 'All ${p.accountInventoryCount}',
        onPressed: () => WebAccountInventoryDialog.show(context, presenter: p),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: cs.outlineVariant)),
            ),
            child: const Row(
              children: [
                Expanded(child: _Eyebrow('ACCOUNT')),
                SizedBox(width: _AccountRow.typeWidth, child: _Eyebrow('TYPE')),
                SizedBox(
                  width: _AccountRow.amountWidth,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _Eyebrow('SPENDABLE'),
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < accounts.length; i++)
            _AccountRow(
              account: accounts[i],
              index: i,
              held: held[accounts[i].id] ?? 0,
              dueInfo:
                  accounts[i].isLiability ? p.creditDueInfo(accounts[i]) : null,
              divider: i < accounts.length - 1,
            ),
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  static const double typeWidth = 96;
  static const double amountWidth = 124;

  final FinancialAccount account;
  final int index;
  final double held;
  final ({String label, bool imminent})? dueInfo;
  final bool divider;
  const _AccountRow({
    required this.account,
    required this.index,
    required this.held,
    required this.dueInfo,
    required this.divider,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final appColors = context.appColors;
    final a = account;
    final isCredit = a.isLiability;
    // Credit shows what's still available to spend; liquid shows spendable
    // cash (balance minus any amount ring-fenced by linked custodians).
    final spendable =
        isCredit ? (a.availableCredit ?? a.balance) : a.balance - held;
    final overdrawn = !isCredit && spendable < 0;

    final String? subline;
    Color sublineColor = appColors.textMuted;
    if (isCredit) {
      final due = dueInfo;
      subline = due == null
          ? 'Owe ${formatPeso(a.totalDebt)}'
          : 'Owe ${formatPeso(a.totalDebt)} · ${due.label}';
      if (due?.imminent ?? false) sublineColor = cs.error;
    } else if (overdrawn) {
      subline = 'Overdrawn · check the last transfer';
      sublineColor = appColors.bills;
    } else if (held > 0) {
      subline = '${formatPeso(held)} held';
    } else {
      subline = null;
    }

    final tileColor =
        resolveSliceColor(a.colorHex, index, brightness: theme.brightness);

    return Container(
      constraints: const BoxConstraints(minHeight: kWebHitTarget),
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: divider
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: cs.outlineVariant)),
            )
          : null,
      child: Row(
        children: [
          WebRowTile(
            color: tileColor,
            size: 34,
            child: Icon(accountIconFor(a),
                color: accountBadgeForeground(tileColor)),
          ),
          const SizedBox(width: WebInsets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  a.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subline != null)
                  Text(
                    subline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11.5,
                      color: sublineColor,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: typeWidth,
            child: Text(
              isCredit ? 'Credit' : a.category.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13.5,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          SizedBox(
            width: amountWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _signedNegative(spendable),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: webNumericStyle(
                    theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                    color: isCredit
                        ? cs.primary
                        : overdrawn
                            ? appColors.bills
                            : cs.onSurface,
                  ),
                ),
                if (isCredit)
                  Text(
                    'available',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: appColors.textMuted,
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

// ===========================================================================
// Cash flow
// ===========================================================================

class _CashFlowCard extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  const _CashFlowCard({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final appColors = context.appColors;
    final p = presenter;
    final income = p.monthTotalInflow;
    final expenses = p.monthTotalOutflow;
    final net = p.monthNetCashFlow;
    final rate = p.savingsRate;
    // Each bar is sized against the larger flow, so the dominant one fills the
    // track and the other reads in proportion (same as the mobile strip).
    final peak = math.max(income, expenses);
    final spentPctLabel =
        income > 0 ? '${(expenses / income * 100).round()}%' : '—';

    return WebCard(
      key: WebKeys.dashboardCashFlow,
      title: 'Cash flow',
      description: 'Income vs spending · ${monthLabel(p.currentMonth)}',
      trailing: WebBadge(
        rate == null
            ? 'Savings rate —'
            : 'Savings rate ${(rate * 100).toStringAsFixed(1)}%',
        tone: rate == null ? WebBadgeTone.neutral : WebBadgeTone.success,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FlowRow(
            label: 'Income',
            color: appColors.move,
            fraction: peak > 0 ? income / peak : 0,
            amount: formatPeso(income),
          ),
          const SizedBox(height: WebInsets.md),
          _FlowRow(
            label: 'Expenses',
            color: appColors.bills,
            fraction: peak > 0 ? expenses / peak : 0,
            amount: formatPeso(expenses),
          ),
          const SizedBox(height: WebInsets.md),
          Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: cs.outlineVariant)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Net flow',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12.5,
                            color: cs.onSurfaceVariant,
                          )),
                      Text('Spent $spentPctLabel of income',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: appColors.textMuted,
                          )),
                    ],
                  ),
                ),
                Text(
                  formatPesoSigned(net),
                  style: webNumericStyle(
                    theme.textTheme.titleMedium?.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                    color: net >= 0 ? cs.onSurface : cs.error,
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

/// Label · tinted track · amount — one flow bar of the Cash flow card.
class _FlowRow extends StatelessWidget {
  final String label;
  final Color color;
  final double fraction;
  final String amount;
  const _FlowRow({
    required this.label,
    required this.color,
    required this.fraction,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontSize: 12, color: cs.onSurfaceVariant)),
        ),
        Expanded(
          child: WebProgressBar(
            value: fraction.clamp(0.0, 1.0),
            color: color,
            height: 10,
          ),
        ),
        SizedBox(
          width: 104,
          child: Text(
            amount,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: webNumericStyle(theme.textTheme.labelLarge, color: color)
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// Budget health
// ===========================================================================

class _BudgetHealthCard extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  final VoidCallback? onOpenBudget;
  const _BudgetHealthCard(
      {required this.presenter, required this.onOpenBudget});

  WebBadge _status(double ratio) {
    if (ratio >= 1.0) return const WebBadge('Over', tone: WebBadgeTone.danger);
    if (ratio >= _kBudgetWatchThreshold) {
      return const WebBadge('Watch', tone: WebBadgeTone.warning);
    }
    return const WebBadge('On track', tone: WebBadgeTone.success);
  }

  Color _groupColor(
      ColorScheme cs, AppThemeExtension colors, int index, double ratio) {
    if (ratio >= 1.0) return cs.error;
    if (ratio >= _kBudgetWatchThreshold) return colors.bills;
    return [cs.primary, colors.weight, colors.treasury, cs.tertiary][index % 4];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final p = presenter;
    final allocated = p.budgetAllocatedByGroup;
    final spent = p.budgetSpentByGroup;
    final totalAlloc = p.totalBudgetAllocated;
    final totalSpent = p.totalBudgetSpent;
    final totalLeft = p.totalBudgetRemaining;
    final active = p.budgetGroups
        .where((g) => (allocated[g.id] ?? 0) > 0 || (spent[g.id] ?? 0) > 0)
        .toList();
    final usedPct =
        totalAlloc > 0 ? '${(totalSpent / totalAlloc * 100).round()}%' : '0%';
    final link = _HeaderLink(
      key: WebKeys.dashboardOpenBudget,
      label: 'Open budget',
      onPressed: onOpenBudget,
    );

    if (active.isEmpty) {
      return WebCard(
        key: WebKeys.dashboardBudgetHealth,
        title: 'Budget health',
        description: monthLabel(p.currentMonth),
        trailing: link,
        child: const _CardEmpty(
          icon: Icons.pie_chart_outline_rounded,
          text: 'No budget set for this month yet',
        ),
      );
    }

    return WebCard(
      key: WebKeys.dashboardBudgetHealth,
      title: 'Budget health',
      description:
          '${monthLabel(p.currentMonth)} · $usedPct of ${formatPeso(totalAlloc)} used',
      trailing: link,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < active.length; i++) ...[
            if (i > 0) const SizedBox(height: WebInsets.lg),
            Builder(builder: (context) {
              final g = active[i];
              final alloc = allocated[g.id] ?? 0;
              final spnt = spent[g.id] ?? 0;
              final ratio = alloc > 0 ? spnt / alloc : 0.0;
              final left = (alloc - spnt).clamp(0.0, double.infinity);
              final pct = alloc > 0 ? (spnt / alloc * 100).round() : 0;
              final dot = _groupColor(cs, context.appColors, i, ratio);
              return WebBudgetRow(
                dotColor: dot,
                name: g.name,
                spent: formatPeso(spnt),
                target: formatPeso(alloc),
                progress: ratio.clamp(0.0, 1.0),
                status: _status(ratio),
                sub: '${formatPeso(left)} left · $pct%',
                barColor: dot,
              );
            }),
          ],
          const SizedBox(height: WebInsets.lg),
          Divider(height: 1, color: cs.outlineVariant),
          const SizedBox(height: WebInsets.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Eyebrow('TOTAL'),
              const SizedBox(width: WebInsets.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${formatPeso(totalSpent)} / ${formatPeso(totalAlloc)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: webNumericStyle(theme.textTheme.bodyMedium)
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${formatPeso(totalLeft)} left',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: webNumericStyle(
                        theme.textTheme.bodySmall,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Trends — one card, three charts, one visible at a time
// ===========================================================================

enum _Trend { netWorth, incomeExpenses, dailySpending }

class _TrendsCard extends StatefulWidget {
  final TreasuryDashboardPresenter presenter;
  const _TrendsCard({required this.presenter});

  @override
  State<_TrendsCard> createState() => _TrendsCardState();
}

class _TrendsCardState extends State<_TrendsCard> {
  _Trend _trend = _Trend.netWorth;

  @override
  Widget build(BuildContext context) {
    final p = widget.presenter;
    final daysTotal =
        p.last7DaysSpending.fold<double>(0, (s, d) => s + d.amount);
    final description = switch (_trend) {
      _Trend.netWorth => 'Last 6 months · your overall position',
      _Trend.incomeExpenses => 'Last 6 months · monthly comparison',
      _Trend.dailySpending => daysTotal > 0
          ? 'Last 7 days · ${formatPeso(daysTotal)} total'
          : 'Last 7 days',
    };

    return WebCard(
      title: 'Trends',
      description: description,
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: WebSegmented<_Trend>(
          key: WebKeys.dashboardTrendsSwitch,
          value: _trend,
          onChanged: (t) => setState(() => _trend = t),
          segments: const [
            WebSegment(_Trend.netWorth, 'Net worth'),
            WebSegment(_Trend.incomeExpenses, 'Income vs expenses'),
            WebSegment(_Trend.dailySpending, 'Daily spending'),
          ],
        ),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: switch (_trend) {
          _Trend.netWorth =>
            _NetWorthTrend(key: WebKeys.dashboardTrendNetWorth, presenter: p),
          _Trend.incomeExpenses => _IncomeExpensesTrend(
              key: WebKeys.dashboardTrendIncomeExpenses, presenter: p),
          _Trend.dailySpending => _DailySpendingTrend(
              key: WebKeys.dashboardTrendDailySpending, presenter: p),
        },
      ),
    );
  }
}

class _NetWorthTrend extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  const _NetWorthTrend({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    final trend = presenter.netWorthTrend();
    if (trend.length < 2) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WebBadge(
            formatPeso(presenter.netWorth),
            tone: WebBadgeTone.info,
            icon: Icons.trending_up_rounded,
          ),
          const _CardEmpty(
            icon: Icons.show_chart_rounded,
            text: 'Your net-worth trend will appear as months accrue.',
          ),
        ],
      );
    }
    final diff = trend.last.value - trend.first.value;
    final up = diff >= 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WebBadge(
          '${up ? '↑ ' : '↓ '}${formatPesoCompact(diff.abs())} (${trend.length} mo)',
          tone: up ? WebBadgeTone.success : WebBadgeTone.danger,
          icon: up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
        ),
        const SizedBox(height: WebInsets.sm),
        WebLineChart(
          values: trend.map((t) => t.value).toList(),
          bottomLabels: trend.map((t) => t.label).toList(),
          area: true,
          leftLabelFormat: formatPesoCompact,
          height: 180,
        ),
      ],
    );
  }
}

class _IncomeExpensesTrend extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  const _IncomeExpensesTrend({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ie = presenter.incomeExpenseTrend();
    if (ie.length < 2) {
      return const _CardEmpty(
        icon: Icons.bar_chart_rounded,
        text: 'Your income vs expenses trend will appear as months accrue.',
      );
    }
    return WebBarPairChart(
      groups:
          ie.map((m) => (label: m.label, a: m.income, b: m.expense)).toList(),
      aColor: cs.tertiary,
      bColor: cs.primary,
      leftLabelFormat: formatPesoCompact,
      height: 208,
    );
  }
}

class _DailySpendingTrend extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  const _DailySpendingTrend({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    final days = presenter.last7DaysSpending;
    final total = days.fold<double>(0, (s, d) => s + d.amount);
    if (total <= 0) {
      return const _CardEmpty(
        icon: Icons.show_chart_rounded,
        text: 'No spending recorded in the last 7 days',
      );
    }
    return WebLineChart(
      values: days.map((d) => d.amount).toList(),
      bottomLabels: [for (final d in days) '${d.date.month}/${d.date.day}'],
      area: false,
      leftLabelFormat: formatPesoCompact,
      minY: 0,
      height: 208,
    );
  }
}

// ===========================================================================
// Where your money goes
// ===========================================================================

class _WhereMoneyGoesCard extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  const _WhereMoneyGoesCard({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spend = presenter.categorySpendThisMonth;
    final description = 'Top spending · ${monthLabel(presenter.currentMonth)}';
    if (spend.isEmpty) {
      return WebCard(
        key: WebKeys.dashboardSpendingDonut,
        title: 'Where your money goes',
        description: description,
        child: const _CardEmpty(
          icon: Icons.donut_large_rounded,
          text: 'No expenses recorded this month',
        ),
      );
    }

    final total = spend.fold<double>(0, (s, e) => s + e.$2);
    final overflow = spend.length > _kMaxDonutSlices;
    final named = overflow ? spend.sublist(0, _kMaxDonutSlices) : spend;
    final tail = overflow ? spend.sublist(_kMaxDonutSlices) : null;
    final slices = <WebChartSlice>[
      for (var i = 0; i < named.length; i++)
        WebChartSlice(
          label: named[i].$1.name,
          value: named[i].$2,
          color: resolveSliceColor(named[i].$1.colorHex, i,
              brightness: theme.brightness),
        ),
      if (tail != null)
        WebChartSlice(
          label: 'Other (${tail.length})',
          value: tail.fold<double>(0, (s, e) => s + e.$2),
          color: theme.colorScheme.outline,
        ),
    ];

    return WebCard(
      key: WebKeys.dashboardSpendingDonut,
      title: 'Where your money goes',
      description: description,
      child: WebDonutChart(
        slices: slices,
        centerLabel: 'Spent',
        centerValue: formatPesoCompact(total),
        size: 150,
      ),
    );
  }
}

// ===========================================================================
// Credit
// ===========================================================================

class _CreditCard extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  final BillsReceivablesPresenter billsPresenter;
  final VoidCallback? onOpenBills;
  const _CreditCard({
    required this.presenter,
    required this.billsPresenter,
    required this.onOpenBills,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accounts = presenter.creditAccounts;
    return WebCard(
      title: 'Credit',
      description:
          'Owe ${formatPeso(presenter.totalCreditOwed)} · ${formatPeso(presenter.totalCreditAvailable)} available',
      trailing: _HeaderLink(
        key: WebKeys.dashboardAllCards,
        label: 'All cards',
        onPressed: onOpenBills,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < accounts.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(height: WebInsets.md),
              Divider(height: 1, color: cs.outlineVariant),
              const SizedBox(height: WebInsets.md),
            ],
            _CreditRow(
              billsPresenter: billsPresenter,
              account: accounts[i],
              index: i,
              dueInfo: presenter.creditDueInfo(accounts[i]),
              cycleNote: presenter.creditCycleNote(accounts[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _CreditRow extends StatelessWidget {
  final BillsReceivablesPresenter billsPresenter;
  final FinancialAccount account;
  final int index;

  /// "Due Nov 4 · min ₱850" / "No payment due", rendered as-is.
  final ({String label, bool imminent})? dueInfo;

  /// "Statement closes Oct 20 · due Nov 4", or a no-billing-cycle warning.
  final ({String label, bool warning})? cycleNote;

  const _CreditRow({
    required this.billsPresenter,
    required this.account,
    required this.index,
    required this.dueInfo,
    required this.cycleNote,
  });

  Future<void> _payNow(BuildContext context) async {
    // Same funding rule as the mobile quick-pay sheet: any non-liability
    // account may pay, not just the liquid ones.
    final funders =
        billsPresenter.accounts.where((a) => a.isActive && !a.isLiability);
    if (funders.isEmpty) {
      AppToast.error(context, 'No account to pay from.');
      return;
    }
    // TODO(Plan 063 Phase 5): route through showWebSettleDialog(cardPayment).
    final paid = await showWebQuickPayDialog(
      context,
      card: account,
      presenter: billsPresenter,
    );
    if (paid != null && context.mounted) {
      AppToast.success(context, 'Paid ${formatPeso(paid)} to ${account.name}.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final appColors = context.appColors;
    final a = account;
    final utilization = a.utilization;
    final due = dueInfo;
    final note = cycleNote;
    final tileColor =
        resolveSliceColor(a.colorHex, index, brightness: theme.brightness);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(fontSize: 12, color: cs.onSurfaceVariant);
    final availableLine =
        '${formatPeso(a.availableCredit ?? 0)} of ${formatPeso(a.creditLimit ?? 0)} available';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WebRowTile(
          color: tileColor,
          size: 40,
          child:
              Icon(accountIconFor(a), color: accountBadgeForeground(tileColor)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: WebInsets.sm),
                  Text(
                    'Owe ${formatPeso(a.totalDebt)}',
                    style: webNumericStyle(theme.textTheme.bodyMedium,
                            color: cs.error)
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              if (utilization != null) ...[
                const SizedBox(height: WebInsets.sm),
                WebProgressBar(
                  value: utilization.clamp(0.0, 1.0),
                  color: utilization >= 0.9 ? cs.error : cs.primary,
                ),
                const SizedBox(height: 6),
                Text(
                  note == null || note.warning
                      ? availableLine
                      : '$availableLine · ${note.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: muted,
                ),
              ] else if (note != null && !note.warning) ...[
                const SizedBox(height: WebInsets.xs),
                Text(note.label, style: muted),
              ],
              if (due != null) ...[
                const SizedBox(height: WebInsets.xs),
                Row(
                  children: [
                    Icon(Icons.event_outlined,
                        size: 14,
                        color: due.imminent ? cs.error : cs.onSurfaceVariant),
                    const SizedBox(width: WebInsets.xs),
                    Expanded(
                      child: Text(
                        due.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted?.copyWith(
                          color: due.imminent ? cs.error : cs.onSurfaceVariant,
                          fontWeight:
                              due.imminent ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (note != null && note.warning) ...[
                const SizedBox(height: WebInsets.xs),
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 14, color: appColors.bills),
                    const SizedBox(width: WebInsets.xs),
                    Expanded(
                      child: Text(
                        note.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted?.copyWith(color: appColors.bills),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 14),
        // Disabled when nothing is owed — an overpaid or cleared card has
        // currentPayable == 0, so there is nothing to pay.
        OutlinedButton(
          key: WebKeys.dashboardPayCard,
          onPressed: a.currentPayable > 0 ? () => _payNow(context) : null,
          child: const Text('Pay now'),
        ),
      ],
    );
  }
}

// ===========================================================================
// Savings goals
// ===========================================================================

class _SavingsGoalsCard extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  final VoidCallback? onOpenGoals;
  const _SavingsGoalsCard({required this.presenter, required this.onOpenGoals});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // Targeted goals first (progress bar), then plain savings (balance only).
    final all = [...presenter.goalAccounts, ...presenter.savingsAccounts];
    final goals = all.where((a) => (a.goalTarget ?? 0) > 0).toList();
    final plain = all.where((a) => (a.goalTarget ?? 0) <= 0).toList();
    final link = _HeaderLink(
      key: WebKeys.dashboardOpenGoals,
      label: 'Goals',
      onPressed: onOpenGoals,
    );

    if (goals.isEmpty && plain.isEmpty) {
      return WebCard(
        key: WebKeys.dashboardSavingsGoals,
        title: 'Savings goals',
        description: 'Progress toward your targets',
        trailing: link,
        child: const _CardEmpty(
          icon: Icons.flag_outlined,
          text: 'No savings or goal accounts yet',
        ),
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < goals.length; i++) {
      final a = goals[i];
      final target = a.goalTarget ?? 0;
      // `goalProgress` pins a funded goal at 100%, so spending it doesn't make
      // the bar collapse to 0% as though it was never saved for.
      final progress = a.hasGoalTarget
          ? a.goalProgress
          : (target > 0 ? (a.balance / target).clamp(0.0, 1.0) : 0.0);
      final pct = (progress * 100).round();
      final color =
          resolveSliceColor(a.colorHex, i, brightness: theme.brightness);
      if (i > 0) rows.add(const SizedBox(height: WebInsets.md));
      rows.add(Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(a.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: WebInsets.sm),
              Text(
                '${formatPeso(a.balance)} of ${formatPeso(target)} · $pct%',
                style: webNumericStyle(
                  theme.textTheme.bodySmall?.copyWith(fontSize: 12.5),
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          WebProgressBar(value: progress.toDouble(), color: color),
        ],
      ));
    }

    // Savings with no target: a balance line, no bar — nothing to be a
    // percentage of.
    for (var i = 0; i < plain.length; i++) {
      final a = plain[i];
      final first = rows.isEmpty;
      rows.add(Container(
        margin: EdgeInsets.only(top: first ? 0 : WebInsets.md),
        padding: EdgeInsets.only(top: first ? 0 : 10),
        decoration: first
            ? null
            : BoxDecoration(
                border: Border(top: BorderSide(color: cs.outlineVariant)),
              ),
        child: Row(
          children: [
            Expanded(
              child: Text(a.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontSize: 13, color: cs.onSurfaceVariant)),
            ),
            Text(formatPeso(a.balance),
                style: webNumericStyle(theme.textTheme.bodyMedium)
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      ));
    }

    return WebCard(
      key: WebKeys.dashboardSavingsGoals,
      title: 'Savings goals',
      description: goals.isEmpty
          ? 'Your savings accounts'
          : 'Progress toward your targets',
      trailing: link,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }
}

// ===========================================================================
// Shared page-private helpers
// ===========================================================================

class _CardEmpty extends StatelessWidget {
  final IconData icon;
  final String text;
  const _CardEmpty({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SizedBox(
      height: 140,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 28, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: WebInsets.sm),
            Text(text,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  /// Null only where the page is mounted without a shell to navigate (tests);
  /// the copy then points at the sidebar instead of offering a button.
  final VoidCallback? onOpenSetup;
  const _EmptyState({this.onOpenSetup});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(WebInsets.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance_wallet_outlined,
                size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
            const SizedBox(height: WebInsets.lg),
            Text('No accounts yet',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: WebInsets.sm),
            Text(
              onOpenSetup != null
                  ? 'Add an account to start tracking your financial position.'
                  : 'Add an account under Setup & Accounts to start tracking '
                      'your financial position.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            if (onOpenSetup != null) ...[
              const SizedBox(height: WebInsets.xl),
              FilledButton.icon(
                key: WebKeys.dashboardAddFirstAccount,
                onPressed: onOpenSetup,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add your first account'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
