import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/app_radii.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/shared/account_badge_widget.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';
import 'package:intl/intl.dart';
import '../../design/account_category_label.dart';
import '../../web_keys.dart';
import '../../widgets/web_widgets.dart';
import 'web_account_form_dialog_v2.dart';
import 'web_account_form_rules.dart';
import 'web_categories_table_v2.dart';

// Local keys (not yet in WebKeys).
const kSetupRowMenuKey = ValueKey('web.setup.row.menu');
const kSetupRowArchiveKey = ValueKey('web.setup.row.archive');
const kSetupEmptyAddAccountKey = ValueKey('web.setup.empty.addAccount');
const kSetupStatLiquidKey = ValueKey('web.setup.stat.liquid');
const kSetupStatSavingsKey = ValueKey('web.setup.stat.savings');
const kSetupStatCreditOwedKey = ValueKey('web.setup.stat.creditOwed');
const kSetupStatCreditAvailableKey = ValueKey('web.setup.stat.creditAvailable');
const kSetupRowNeedsFixKey = ValueKey('web.setup.row.needsFix');
const kSetupRowMeterKey = ValueKey('web.setup.row.meter');

/// Gap between the header's blocks — the canvas grid gap (20 px).
const double _gap = 20;

/// Minimum width of the accounts table before it scrolls sideways.
const double _tableMinWidth = 820;

/// Web "Setup & Accounts", v2 (Plan 063 Phase 8) — the canvas layout in
/// `docs/design-reference/web-v2/Setup.dc.html`: one page header with an
/// Accounts · Categories switch and Add account, a four-cell stat strip, and
/// the grouped accounts table with the single "Credit / target" column; the
/// Categories tab is the category table with its add row.
///
/// Reads [TreasuryDashboardPresenter] for accounts and [LedgerPresenter] for
/// categories, and calls the same presenter methods the pre-v2 page called
/// (`updateAccount` for the inline type, `deleteAccount`, `archiveGoal`, the
/// category CRUD). The shell owns the content width and page padding.
class WebSetupPageV2 extends StatefulWidget {
  final TreasuryDashboardPresenter presenter;
  final LedgerPresenter ledgerPresenter;

  /// Slot after the header actions — the shell's Nudgy button.
  final Widget? trailing;

  const WebSetupPageV2({
    super.key,
    required this.presenter,
    required this.ledgerPresenter,
    this.trailing,
  });

  @override
  State<WebSetupPageV2> createState() => _WebSetupPageV2State();
}

class _WebSetupPageV2State extends State<WebSetupPageV2> {
  /// 0 = Accounts, 1 = Categories.
  int _tab = 0;

  void _addAccount() => WebAccountFormDialogV2.show(context, widget.presenter);

  @override
  Widget build(BuildContext context) {
    final p = widget.presenter;
    return ListenableBuilder(
      listenable: Listenable.merge([p, widget.ledgerPresenter]),
      builder: (context, _) {
        final Widget body;
        if (p.isLoading) {
          body = const Padding(
            padding: EdgeInsets.symmetric(vertical: 96),
            child: Center(child: CircularProgressIndicator()),
          );
        } else if (_tab == 1) {
          body = WebCategoriesTableV2(ledger: widget.ledgerPresenter);
        } else if (!p.hasAccounts) {
          body = _EmptyState(onAdd: _addAccount);
        } else {
          body = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatStrip(presenter: p),
              const SizedBox(height: _gap),
              _AccountsTableCard(presenter: p),
            ],
          );
        }

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WebPageHeaderV2(
                title: 'Setup & Accounts',
                subtitle: p.isLoading ? 'Loading accounts…' : _subtitle(p),
                actions: [
                  WebTabs(
                    tabs: [
                      WebTab('Accounts',
                          count: p.activeAccountCount,
                          key: WebKeys.setupTabAccounts),
                      WebTab('Categories',
                          count: webListedCategories(widget.ledgerPresenter)
                              .length,
                          key: WebKeys.setupTabCategories),
                    ],
                    index: _tab,
                    onChanged: (i) => setState(() => _tab = i),
                  ),
                  FilledButton.icon(
                    key: WebKeys.setupAddAccount,
                    onPressed: _addAccount,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add account'),
                  ),
                  if (widget.trailing != null) widget.trailing!,
                ],
              ),
              body,
            ],
          ),
        );
      },
    );
  }

  /// "23 accounts · 7 liquid · 8 goals · 6 credit lines · 1 investment".
  static String _subtitle(TreasuryDashboardPresenter p) {
    final parts = <String>[
      _n(p.activeAccountCount, 'account', 'accounts'),
      '${p.liquidAccounts.length} liquid',
      _n(p.goalAccounts.length, 'goal', 'goals'),
      _n(p.creditAccounts.length, 'credit line', 'credit lines'),
    ];
    final investments = _topLevelOf(p, const {AccountCategory.investment});
    if (investments.isNotEmpty) {
      parts.add(_n(investments.length, 'investment', 'investments'));
    }
    if (p.custodianAccounts.isNotEmpty) {
      parts.add(_n(p.custodianAccounts.length, 'custodian', 'custodian'));
    }
    return parts.join(' · ');
  }
}

String _n(int n, String one, String many) => '$n ${n == 1 ? one : many}';

/// Whole-peso figure for the meter labels ("₱67,315 of ₱75,000").
String _wholePeso(double v) =>
    '₱${NumberFormat('#,##0', 'en_PH').format(v.round())}';

/// Negative figures carry a typographic minus before the peso sign.
String _signed(double v) => v < 0 ? '−${formatPeso(v.abs())}' : formatPeso(v);

String _ordinal(int d) {
  if (d >= 11 && d <= 13) return '${d}th';
  return switch (d % 10) {
    1 => '${d}st',
    2 => '${d}nd',
    3 => '${d}rd',
    _ => '${d}th',
  };
}

/// Active top-level accounts of the given categories — the groups the
/// presenter has no dedicated getter for (investments; savings, goals and
/// time deposits as one group).
List<FinancialAccount> _topLevelOf(
        TreasuryDashboardPresenter p, Set<AccountCategory> categories) =>
    p.accounts
        .where((a) =>
            a.isActive &&
            a.parentAccountId == null &&
            categories.contains(a.category))
        .toList();

// ===========================================================================
// Stat strip
// ===========================================================================

class _StatStrip extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  const _StatStrip({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final p = presenter;
    final liquid = p.liquidAccounts;
    final overdrawn = liquid.where((a) => a.balance < 0).toList();
    final goals = p.goalAccounts;
    final funded = goals.where((a) => a.balance > 0).length;
    final credit = p.creditAccounts;
    final owing = credit.where((a) => a.totalDebt > 0).length;
    final limit = credit.fold(0.0, (s, a) => s + (a.creditLimit ?? 0));

    final liquidCaption = overdrawn.isEmpty
        ? _n(liquid.length, 'account', 'accounts')
        : '${_n(liquid.length, 'account', 'accounts')} · ${overdrawn.first.name} is overdrawn';

    return WebStatStrip(
      key: WebKeys.setupStatStrip,
      items: [
        WebStat(
          key: kSetupStatLiquidKey,
          label: 'Liquid cash',
          value: _signed(p.totalLiquidCash),
          caption: liquidCaption,
          tone:
              p.totalLiquidCash < 0 ? WebStatTone.warning : WebStatTone.neutral,
        ),
        WebStat(
          key: kSetupStatSavingsKey,
          label: 'Savings & goals',
          value: formatPeso(p.totalSavingsAndGoals),
          caption: goals.isEmpty
              ? _n(p.savingsAccounts.length, 'savings account',
                  'savings accounts')
              : '${_n(goals.length, 'goal', 'goals')}, $funded funded',
        ),
        WebStat(
          key: kSetupStatCreditOwedKey,
          label: 'Credit owed',
          value: formatPeso(p.totalCreditOwed),
          caption: credit.isEmpty
              ? 'No credit lines'
              : '$owing of ${_n(credit.length, 'line', 'lines')} carry a balance',
          tone:
              p.totalCreditOwed > 0 ? WebStatTone.warning : WebStatTone.neutral,
        ),
        WebStat(
          key: kSetupStatCreditAvailableKey,
          label: 'Credit available',
          value: formatPeso(p.totalCreditAvailable),
          caption: credit.isEmpty
              ? 'Add a card or line to track a limit'
              : 'of ${_wholePeso(limit)} across ${_n(credit.length, 'line', 'lines')}',
          tone: WebStatTone.info,
        ),
      ],
    );
  }
}

// ===========================================================================
// Accounts table
// ===========================================================================

/// Column widths; the Account column flexes.
class _Cols {
  static const double type = 150;
  static const double balance = 140;
  static const double credit = 240;

  /// Three Material icon buttons (48 px tap targets each).
  static const double actions = 3 * 48;
}

typedef _TableRow = ({FinancialAccount account, bool indented, int index});

class _Group {
  final String title;
  final List<_TableRow> rows;
  const _Group({required this.title, required this.rows});
}

class _AccountsTableCard extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  const _AccountsTableCard({required this.presenter});

  /// The canvas groups: Liquid (with pockets indented under their parent) ·
  /// Savings & goals · Credit · Investment · Held for others. Empty groups
  /// are left out.
  List<_Group> _groups() {
    final p = presenter;
    var index = 0;
    List<_TableRow> expand(List<FinancialAccount> accounts) {
      final out = <_TableRow>[];
      for (final a in accounts) {
        out.add((account: a, indented: false, index: index++));
        for (final sub in p.subAccountsOf(a.id)) {
          if (!sub.isActive) continue;
          out.add((account: sub, indented: true, index: index++));
        }
      }
      return out;
    }

    final groups = <_Group>[];
    void add(String title, List<FinancialAccount> accounts) {
      if (accounts.isEmpty) return;
      groups.add(_Group(title: title, rows: expand(accounts)));
    }

    double sum(List<FinancialAccount> list) =>
        list.fold(0.0, (s, a) => s + a.balance);

    final liquid = p.liquidAccounts;
    add('Liquid · ${liquid.length} · ${_signed(p.totalLiquidCashGross)}',
        liquid);

    final pockets = _topLevelOf(p, const {
      AccountCategory.savings,
      AccountCategory.goal,
      AccountCategory.timeDeposit,
    });
    if (pockets.isNotEmpty) {
      final allGoals = pockets.every((a) => a.category == AccountCategory.goal);
      final target = pockets.fold(0.0, (s, a) => s + (a.goalTarget ?? 0));
      final saved = formatPeso(sum(pockets));
      add(
        '${allGoals ? 'Goals' : 'Savings & goals'} · ${pockets.length} · '
        '${target > 0 ? '$saved of ${_wholePeso(target)}' : saved}',
        pockets,
      );
    }

    final credit = p.creditAccounts;
    add(
      'Credit · ${credit.length} · owe ${formatPeso(p.totalCreditOwed)} · '
      '${_wholePeso(p.totalCreditAvailable)} available',
      credit,
    );

    final investments = _topLevelOf(p, const {AccountCategory.investment});
    add(
      'Investment · ${investments.length} · ${formatPeso(sum(investments))}',
      investments,
    );

    final held = p.custodianAccounts;
    add(
      'Held for others · ${held.length} · ${formatPeso(p.totalHeldForOthers)}',
      held,
    );
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final groups = _groups();

    final children = <Widget>[const _TableHeader()];
    for (final g in groups) {
      children.add(_GroupHeader(title: g.title));
      for (var i = 0; i < g.rows.length; i++) {
        final r = g.rows[i];
        children.add(_AccountRow(
          key: ValueKey('web.setup.row.${r.account.id}'),
          presenter: presenter,
          account: r.account,
          indented: r.indented,
          index: r.index,
        ));
        if (i < g.rows.length - 1) {
          children.add(Divider(height: 1, color: cs.outlineVariant));
        }
      }
    }

    return WebCard(
      key: WebKeys.setupAccountsTable,
      title: 'Accounts',
      description: "Each account's type and balance · credit cards and lines "
          'use a limit · goals show their target',
      padding: const EdgeInsets.fromLTRB(
          WebInsets.xl, WebInsets.lg, WebInsets.xl, WebInsets.sm),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Below the rail breakpoint the content can fall under the fixed
          // columns; give the table a floor and scroll sideways.
          final tableWidth = max(_tableMinWidth, constraints.maxWidth);
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  final String text;
  final TextAlign align;
  const _Eyebrow(this.text, {this.align = TextAlign.left});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      textAlign: align,
      maxLines: 1,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
          WebInsets.sm, WebInsets.xs, 0, WebInsets.sm),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: const Row(
        children: [
          Expanded(child: _Eyebrow('ACCOUNT')),
          SizedBox(width: _Cols.type, child: _Eyebrow('TYPE')),
          SizedBox(
              width: _Cols.balance,
              child: _Eyebrow('BALANCE', align: TextAlign.right)),
          SizedBox(width: WebInsets.lg),
          SizedBox(width: _Cols.credit, child: _Eyebrow('CREDIT / TARGET')),
          SizedBox(width: _Cols.actions),
        ],
      ),
    );
  }
}

/// A group row inside the table ("Liquid · 7 · ₱30,542.27").
class _GroupHeader extends StatelessWidget {
  final String title;
  const _GroupHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      width: double.infinity,
      color: cs.surfaceContainerHigh.withValues(alpha: 0.5),
      padding: const EdgeInsets.symmetric(
          horizontal: WebInsets.sm, vertical: WebInsets.sm),
      child: Text(
        title.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: webNumericStyle(
          theme.textTheme.labelSmall?.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.66,
          ),
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

// ===========================================================================
// Account row
// ===========================================================================

class _AccountRow extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  final FinancialAccount account;
  final bool indented;
  final int index;

  const _AccountRow({
    super.key,
    required this.presenter,
    required this.account,
    required this.indented,
    required this.index,
  });

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showWebConfirm(
      context,
      title: 'Delete ${account.name}?',
      message: webAccountDeleteMessage(account),
    );
    if (!confirmed || !context.mounted) return;
    try {
      await presenter.deleteAccount(account.id);
    } on StateError catch (e) {
      if (!context.mounted) return;
      AppToast.error(context, webAccountDeleteError(e));
    }
  }

  Future<void> _archive(BuildContext context) async {
    final confirmed = await showWebConfirm(
      context,
      title: 'Archive ${account.name}?',
      message: 'The goal is hidden from every list and picker until it is '
          'reactivated from "All accounts" on the Dashboard. Its '
          'transactions stay in the ledger.',
      confirmLabel: 'Archive',
      destructive: false,
    );
    if (!confirmed || !context.mounted) return;
    await presenter.archiveGoal(account.id);
    if (!context.mounted) return;
    AppToast.show(context, 'Archived ${account.name}.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final appColors = context.appColors;
    final a = account;
    final isCredit = a.isLiability;
    final isGoal = a.category == AccountCategory.goal;
    final overdrawn = !isCredit && a.balance < 0;

    // ── Account: tile + name + subline ──
    String? subline;
    Color sublineColor = appColors.textMuted;
    if (overdrawn) {
      subline = 'Overdrawn · the last transfer out was larger than the balance';
      sublineColor = appColors.bills;
    } else if (isCredit && a.statementDay != null) {
      final due = a.paymentDueDay != null
          ? ' · due ${_ordinal(a.paymentDueDay!)}'
          : a.dueDaysAfterStatement != null
              ? ' · due ${a.dueDaysAfterStatement} days after'
              : '';
      subline = 'Statement ${_ordinal(a.statementDay!)}$due';
    }

    final accountCell = Padding(
      padding:
          EdgeInsets.only(left: WebInsets.sm + (indented ? WebInsets.xl : 0)),
      child: Row(
        children: [
          if (indented)
            Padding(
              padding: const EdgeInsets.only(right: WebInsets.sm),
              child: Icon(Icons.subdirectory_arrow_right_rounded,
                  size: 16, color: appColors.textMuted),
            ),
          AccountBadge.of(a, size: 30),
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
        ],
      ),
    );

    // ── Type: inline switcher for assets; static label for credit ──
    final typeCell = isCredit
        ? Text(
            a.category.label,
            style: theme.textTheme.bodySmall
                ?.copyWith(fontSize: 12.5, color: cs.onSurfaceVariant),
          )
        : _TypeDropdown(presenter: presenter, account: a);

    // ── Balance ──
    final String balanceText;
    final Color balanceColor;
    if (isCredit) {
      balanceText =
          a.balance > 0 ? '−${formatPeso(a.balance)}' : _signed(a.balance);
      balanceColor = a.balance > 0 ? cs.error : appColors.textMuted;
    } else {
      balanceText = _signed(a.balance);
      balanceColor = overdrawn
          ? appColors.bills
          : a.balance == 0
              ? appColors.textMuted
              : cs.onSurface;
    }
    final balanceCell = Text(
      balanceText,
      textAlign: TextAlign.right,
      maxLines: 1,
      style: webNumericStyle(
        theme.textTheme.bodyMedium?.copyWith(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
        ),
        color: balanceColor,
      ),
    );

    // ── Credit / target: a meter for credit and goals, a pill for an
    // overdrawn liquid row, nothing otherwise (never "—") ──
    final Widget creditCell;
    final tileColor = isCredit
        ? ((a.utilization ?? 0) >= 0.5 ? appColors.bills : cs.primary)
        : cs.tertiary;
    if (isCredit && a.creditLimit != null) {
      creditCell = _MeterCell(
        fraction: a.utilization ?? 0,
        color: tileColor,
        label: '${_wholePeso(a.availableCredit ?? 0)} of '
            '${_wholePeso(a.creditLimit!)}',
      );
    } else if (isGoal && a.hasGoalTarget) {
      creditCell = _MeterCell(
        fraction: a.goalProgress,
        color: tileColor,
        label: '${formatPercent(a.goalProgress)} of '
            '${_wholePeso(a.goalTarget!)}',
      );
    } else if (overdrawn) {
      creditCell = const Align(
        alignment: Alignment.centerLeft,
        child: WebBadge('Needs a fix',
            key: kSetupRowNeedsFixKey, tone: WebBadgeTone.warning),
      );
    } else {
      creditCell = const SizedBox.shrink();
    }

    // ── Actions ──
    final actions = Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Liquid parents (bank / e-wallet / cash) hold pockets; sub-accounts
        // and other roles do not nest further, so the control is absent there.
        if (!indented && a.isLiquid)
          IconButton(
            key: WebKeys.setupRowAddPocket,
            tooltip: 'Add savings pocket / goal',
            onPressed: () => WebAccountFormDialogV2.show(context, presenter,
                parentAccountId: a.id),
            icon: const Icon(Icons.add_rounded, size: 18),
            style: _rowButtonStyle(cs),
          ),
        IconButton(
          key: WebKeys.setupRowEdit,
          tooltip: 'Edit account',
          onPressed: () =>
              WebAccountFormDialogV2.show(context, presenter, existing: a),
          icon: const Icon(Icons.edit_outlined, size: 16),
          style: _rowButtonStyle(cs),
        ),
        WebRowMenu(
          key: kSetupRowMenuKey,
          items: [
            WebMenuItem('Edit',
                icon: Icons.edit_outlined,
                onTap: () => WebAccountFormDialogV2.show(context, presenter,
                    existing: a)),
            // Archiving is a goal-lifecycle action on the presenter
            // (archiveGoal); other roles have no archive path, so the entry
            // only appears on goal rows.
            if (isGoal)
              WebMenuItem('Archive',
                  key: kSetupRowArchiveKey,
                  icon: Icons.inventory_2_outlined,
                  onTap: () => _archive(context)),
            WebMenuItem('Delete',
                key: WebKeys.setupRowDelete,
                icon: Icons.delete_outline,
                destructive: true,
                onTap: () => _delete(context)),
          ],
        ),
      ],
    );

    return Container(
      constraints: const BoxConstraints(minHeight: kWebHitTarget + 4),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: accountCell),
          SizedBox(width: _Cols.type, child: typeCell),
          SizedBox(width: _Cols.balance, child: balanceCell),
          const SizedBox(width: WebInsets.lg),
          SizedBox(width: _Cols.credit, child: creditCell),
          SizedBox(width: _Cols.actions, child: actions),
        ],
      ),
    );
  }
}

ButtonStyle _rowButtonStyle(ColorScheme cs) => IconButton.styleFrom(
      foregroundColor: cs.onSurfaceVariant,
      hoverColor: cs.surfaceContainerHigh,
      minimumSize: const Size(kWebHitTarget, kWebHitTarget),
      maximumSize: const Size(kWebHitTarget, kWebHitTarget),
      padding: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.smBorder),
    );

/// The "Credit / target" cell: a thin bar and a muted figure beside it.
class _MeterCell extends StatelessWidget {
  final double fraction;
  final Color color;
  final String label;

  const _MeterCell({
    required this.fraction,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      key: kSetupRowMeterKey,
      children: [
        Expanded(
          child: WebProgressBar(value: fraction, color: color),
        ),
        const SizedBox(width: WebInsets.sm),
        Text(
          label,
          maxLines: 1,
          style: webNumericStyle(
            theme.textTheme.bodySmall?.copyWith(fontSize: 12),
            color: context.appColors.textMuted,
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// Inline "change type" dropdown
// ===========================================================================

/// Compact inline dropdown that re-assigns an account's [AccountCategory].
/// Selecting a new type persists through [TreasuryDashboardPresenter.updateAccount];
/// the grouping re-derives on the presenter's notify, so the row moves to
/// its new group. Rendered for non-liability accounts only.
class _TypeDropdown extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  final FinancialAccount account;

  const _TypeDropdown({required this.presenter, required this.account});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final base = account.parentAccountId == null
        ? kWebTopLevelSwitchable
        : kWebSubSwitchable;
    // Keep the current type selectable so the dropdown's value-in-items
    // invariant holds even for an unlisted current type.
    final options =
        base.contains(account.category) ? base : [account.category, ...base];

    return Container(
      height: 30,
      padding: const EdgeInsets.only(left: WebInsets.sm, right: WebInsets.xs),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border.all(color: cs.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<AccountCategory>(
          key: WebKeys.setupRowType,
          value: account.category,
          isDense: true,
          isExpanded: true,
          borderRadius: AppRadii.smBorder,
          icon: Icon(Icons.unfold_more, size: 14, color: cs.onSurfaceVariant),
          style: theme.textTheme.bodySmall
              ?.copyWith(fontSize: 12.5, color: cs.onSurfaceVariant),
          dropdownColor: cs.surfaceContainerHigh,
          items: [
            for (final c in options)
              DropdownMenuItem(value: c, child: Text(c.label)),
          ],
          onChanged: (c) => _changeType(context, c),
        ),
      ),
    );
  }

  Future<void> _changeType(BuildContext context, AccountCategory? c) async {
    if (c == null || c == account.category) return;
    await presenter.updateAccount(account.copyWith(category: c));
    if (!context.mounted) return;
    // A Goal with no target shows no progress and stays off the dashboard
    // goals until a target is set — point at the edit form for that.
    if (c == AccountCategory.goal && (account.goalTarget ?? 0) <= 0) {
      AppToast.show(context, 'Set a goal target in Edit to track progress.');
    }
  }
}

// ===========================================================================
// Empty state
// ===========================================================================

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
              'Add your banks, wallets, savings and cards to start tracking '
              'your treasury.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: WebInsets.xl),
            FilledButton.icon(
              key: kSetupEmptyAddAccountKey,
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add account'),
            ),
          ],
        ),
      ),
    );
  }
}
