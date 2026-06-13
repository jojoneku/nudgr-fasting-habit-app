import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/app_radii.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../../design/account_category_label.dart';
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
  final LedgerPresenter ledgerPresenter;

  const WebSetupPage({
    super.key,
    required this.presenter,
    required this.ledgerPresenter,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) =>
          _SetupBody(presenter: presenter, ledgerPresenter: ledgerPresenter),
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
  final LedgerPresenter ledgerPresenter;

  const _SetupBody({required this.presenter, required this.ledgerPresenter});

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
            subtitle: 'Manage your accounts, categories, balances & credit',
            trailing: FilledButton.icon(
              onPressed: () => _showAccountSheet(context, presenter),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Account'),
            ),
          ),
          content,
          const SizedBox(height: WebInsets.xl),
          _CategoriesCard(ledger: ledgerPresenter),
        ],
      ),
    );
  }
}

// ─── Categories ───────────────────────────────────────────────────────────────

/// Manage transaction categories (the labels used to tag ledger entries and
/// drive the budget). Mirrors the mobile ManageCategoriesSheet: add by name
/// under the selected type — icon defaults to `tag` and the colour is
/// auto-assigned from the palette — and delete (blocked while transactions
/// still reference the category). CRUD lives entirely on [LedgerPresenter].
class _CategoriesCard extends StatefulWidget {
  final LedgerPresenter ledger;

  const _CategoriesCard({required this.ledger});

  @override
  State<_CategoriesCard> createState() => _CategoriesCardState();
}

class _CategoriesCardState extends State<_CategoriesCard> {
  final _nameController = TextEditingController();
  CategoryType _type = CategoryType.expense;
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _nextColor() {
    final index = widget.ledger.categories.where((c) => c.type == _type).length;
    return categoryColorAt(index, isExpense: _type == CategoryType.expense);
  }

  Future<void> _add() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      final id =
          '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';
      await widget.ledger.addCategory(FinanceCategory(
        id: id,
        name: name,
        type: _type,
        icon: 'tag',
        colorHex: _nextColor(),
      ));
      _nameController.clear();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _confirmDelete(FinanceCategory category) async {
    final messenger = ScaffoldMessenger.of(context);
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text(
          '"${category.name}" will be removed. You can only delete categories '
          'with no transactions linked to them.',
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
      await widget.ledger.deleteCategory(category.id);
    } on StateError catch (e) {
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            e.message == 'has_transactions'
                ? 'This category has transactions linked to it. '
                    'Delete or reassign those entries first.'
                : 'Could not delete category: ${e.message}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.ledger,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final expense = widget.ledger.categories
            .where((c) => c.type == CategoryType.expense)
            .toList();
        final income = widget.ledger.categories
            .where((c) => c.type == CategoryType.income)
            .toList();

        return WebCard(
          title: 'Categories',
          description: 'Labels for tagging transactions & budgeting',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _CategoryTypeToggle(
                    value: _type,
                    onChanged: (t) => setState(() => _type = t),
                  ),
                  const SizedBox(width: WebInsets.md),
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: TextField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        onSubmitted: (_) => _add(),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: _type == CategoryType.expense
                              ? 'Add an expense category…'
                              : 'Add an income category…',
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 0, horizontal: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: WebInsets.sm),
                  SizedBox(
                    height: 40,
                    child: FilledButton.icon(
                      onPressed: _submitting ? null : _add,
                      icon: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadii.sm)),
                      ),
                    ),
                  ),
                ],
              ),
              if (expense.isEmpty && income.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: WebInsets.xl),
                  child: Text(
                    'No categories yet — add expense and income labels above.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                )
              else ...[
                if (expense.isNotEmpty) ...[
                  const SizedBox(height: WebInsets.xl),
                  _CategoryGroup(
                    label: 'Expense',
                    accent: cs.error,
                    categories: expense,
                    onDelete: _confirmDelete,
                  ),
                ],
                if (income.isNotEmpty) ...[
                  const SizedBox(height: WebInsets.lg),
                  _CategoryGroup(
                    label: 'Income',
                    accent: cs.tertiary,
                    categories: income,
                    onDelete: _confirmDelete,
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Compact two-option (Expense / Income) segmented toggle that drives which
/// type the add field creates.
class _CategoryTypeToggle extends StatelessWidget {
  final CategoryType value;
  final ValueChanged<CategoryType> onChanged;

  const _CategoryTypeToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 40,
      padding: const EdgeInsets.all(WebInsets.xs),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _seg(context, CategoryType.expense, 'Expense'),
          _seg(context, CategoryType.income, 'Income'),
        ],
      ),
    );
  }

  Widget _seg(BuildContext context, CategoryType t, String label) {
    final cs = Theme.of(context).colorScheme;
    final sel = t == value;
    return GestureDetector(
      onTap: () => onChanged(t),
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: double.infinity,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: WebInsets.md),
        decoration: BoxDecoration(
          color: sel ? cs.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.sm - 2),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: sel ? cs.onPrimary : cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

/// A labelled group ("Expense"/"Income") rendering its categories as removable
/// pills that wrap across the card width.
class _CategoryGroup extends StatelessWidget {
  final String label;
  final Color accent;
  final List<FinanceCategory> categories;
  final ValueChanged<FinanceCategory> onDelete;

  const _CategoryGroup({
    required this.label,
    required this.accent,
    required this.categories,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(width: WebInsets.sm),
            Text(
              '${categories.length}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: WebInsets.md),
        Wrap(
          spacing: WebInsets.sm,
          runSpacing: WebInsets.sm,
          children: [
            for (final c in categories)
              _CategoryPill(category: c, onDelete: () => onDelete(c)),
          ],
        ),
      ],
    );
  }
}

class _CategoryPill extends StatelessWidget {
  final FinanceCategory category;
  final VoidCallback onDelete;

  const _CategoryPill({required this.category, required this.onDelete});

  Color _dotColor(BuildContext context) {
    final hex = category.colorHex.replaceFirst('#', '');
    try {
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Theme.of(context).colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.only(
          left: WebInsets.md, right: WebInsets.xs, top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: _dotColor(context),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: WebInsets.sm),
          Text(
            category.name,
            style: theme.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: WebInsets.xs),
          InkWell(
            onTap: onDelete,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close_rounded,
                  size: 14, color: cs.onSurfaceVariant),
            ),
          ),
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

// ─── Inline "change type" dropdown ────────────────────────────────────────────

/// Asset-side categories offered for quick switching on a top-level account.
/// Credit (liability) types are intentionally excluded — converting to/from a
/// liability flips the balance's meaning and needs a credit limit, so that
/// stays in the full edit form.
const List<AccountCategory> _kTopLevelSwitchable = [
  AccountCategory.bank,
  AccountCategory.ewallet,
  AccountCategory.cash,
  AccountCategory.savings,
  AccountCategory.goal,
  AccountCategory.investment,
  AccountCategory.custodian,
];

/// Sub-account categories (ring-fenced pockets) offered for quick switching.
const List<AccountCategory> _kSubSwitchable = [
  AccountCategory.savings,
  AccountCategory.goal,
  AccountCategory.timeDeposit,
];

/// Compact inline dropdown that re-assigns an account's [AccountCategory].
/// Selecting a new type persists immediately via [updateAccount]; the section
/// grouping re-derives on the presenter's notify, so the row jumps to its new
/// section. Only rendered for non-liability accounts (see [_kTopLevelSwitchable]).
class _TypeDropdown extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  final FinancialAccount account;

  const _TypeDropdown({required this.presenter, required this.account});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final base = account.parentAccountId == null
        ? _kTopLevelSwitchable
        : _kSubSwitchable;
    // Guarantee the current category is selectable so DropdownButton's
    // value-in-items invariant holds even for an unlisted current type.
    final options =
        base.contains(account.category) ? base : [account.category, ...base];

    return DropdownButtonHideUnderline(
      child: DropdownButton<AccountCategory>(
        value: account.category,
        isDense: true,
        borderRadius: AppRadii.smBorder,
        icon: Icon(Icons.unfold_more, size: 14, color: cs.onSurfaceVariant),
        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        dropdownColor: cs.surfaceContainerHigh,
        items: [
          for (final c in options)
            DropdownMenuItem(value: c, child: Text(c.label)),
        ],
        onChanged: (c) => _changeType(context, c),
      ),
    );
  }

  Future<void> _changeType(BuildContext context, AccountCategory? c) async {
    if (c == null || c == account.category) return;
    final messenger = ScaffoldMessenger.of(context);
    await presenter.updateAccount(account.copyWith(category: c));
    // A Goal with no target won't show progress or surface in dashboard goals
    // until a target is set — nudge the user toward the edit form for that.
    if (c == AccountCategory.goal && (account.goalTarget ?? 0) <= 0) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Set a goal target in Edit to track progress.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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

  String get _typeLabel => account.category.label;

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
                // Liability rows keep a static label — converting to/from
                // credit stays in the edit form. Asset rows get an inline
                // type switcher.
                account.isLiability
                    ? Text(
                        _typeLabel,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      )
                    : _TypeDropdown(presenter: presenter, account: account),
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
