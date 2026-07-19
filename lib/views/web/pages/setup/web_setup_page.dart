import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/views/treasury/shared/account_badge_widget.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/app_radii.dart';
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

/// Opens the account form pre-bound to [parent] so the user can create a nested
/// sub-account (savings pocket / goal / time deposit). The form switches to the
/// sub-account category list when a parentAccountId is set.
void _showAddSubAccount(
  BuildContext context,
  TreasuryDashboardPresenter presenter,
  FinancialAccount parent,
) {
  WebAccountFormDialog.show(context, presenter, parentAccountId: parent.id);
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
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SetupKpiRow(presenter: presenter),
          const SizedBox(height: WebInsets.xl),
          _AccountsTableCard(presenter: presenter),
        ],
      );
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
  String _draftColor = kCategoryPalette.first;
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
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
        colorHex: _draftColor,
      ));
      _nameController.clear();
      // Advance the draft swatch so consecutive adds get distinct colors.
      setState(() => _draftColor = cycleCategoryColor(_draftColor));
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
        // Expense categories first, then income — matches the dropdown order
        // and keeps like rows together while staying one table.
        final categories = [
          ...widget.ledger.categories
              .where((c) => c.type == CategoryType.expense),
          ...widget.ledger.categories
              .where((c) => c.type == CategoryType.income),
        ];

        final rows = <Widget>[
          const _CategoryTableHeader(),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
        ];
        for (final c in categories) {
          rows.add(_CategoryTableRow(
            key: ValueKey(c.id),
            ledger: widget.ledger,
            category: c,
            onDelete: () => _confirmDelete(c),
          ));
          rows.add(Divider(
              height: 1, color: cs.outlineVariant.withValues(alpha: 0.25)));
        }
        rows.add(_buildAddRow(context));

        return WebCard(
          title: 'Categories',
          description: 'Labels for tagging transactions & budgeting',
          padding: const EdgeInsets.symmetric(
            horizontal: WebInsets.xl,
            vertical: WebInsets.lg,
          ),
          // Scroll horizontally on narrow viewports rather than overflowing the
          // fixed TYPE/COLOR/actions columns (matches the accounts table).
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tableWidth = max(480.0, constraints.maxWidth);
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: rows,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// The "add a category…" row pinned to the bottom of the table — name field,
  /// type dropdown, draft color swatch, and a check button. Mirrors the
  /// reference add-row.
  Widget _buildAddRow(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      padding: const EdgeInsets.symmetric(vertical: WebInsets.xs),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                _ColorDot(hex: _draftColor),
                const SizedBox(width: WebInsets.sm),
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    onSubmitted: (_) => _add(),
                    style: theme.textTheme.bodyMedium,
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: 'Add a category…',
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: _CatCols.type,
            child: _CategoryTypeDropdown(
              value: _type,
              onChanged: (t) => setState(() => _type = t),
            ),
          ),
          SizedBox(
            width: _CatCols.color,
            child: Center(
              child: _ColorSwatch(
                hex: _draftColor,
                onTap: () => setState(
                    () => _draftColor = cycleCategoryColor(_draftColor)),
              ),
            ),
          ),
          // New categories count toward totals by default — the exclude toggle
          // lives on the saved rows. Reserve the column to stay aligned.
          const SizedBox(width: _CatCols.exclude),
          SizedBox(
            width: _CatCols.actions,
            child: Center(
              child: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      tooltip: 'Add category',
                      onPressed: _add,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      color: cs.primary,
                      visualDensity: VisualDensity.compact,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Palette the Setup categories table cycles through for color swatches
/// (mirrors the reference SPALETTE).
const List<String> kCategoryPalette = [
  '#3b82f6',
  '#8b5cf6',
  '#22c55e',
  '#f59e0b',
  '#14b8a6',
  '#ec4899',
  '#f43f5e',
  '#0ea5e9',
  '#64748b',
  '#9ea8ba',
];

/// Next color in [kCategoryPalette] after [hex] (wraps); falls back to the
/// first entry when [hex] isn't in the palette.
String cycleCategoryColor(String hex) {
  final i = kCategoryPalette.indexOf(hex);
  return kCategoryPalette[(i + 1) % kCategoryPalette.length];
}

Color _hexColor(String hex, Color fallback) {
  final h = hex.replaceFirst('#', '');
  try {
    return Color(int.parse('FF$h', radix: 16));
  } catch (_) {
    return fallback;
  }
}

/// Column widths for the categories table (Category flexes; the rest fixed).
class _CatCols {
  static const double type = 130;
  static const double color = 70;
  static const double exclude = 90;
  static const double actions = 56;
}

/// Uppercase column header row for the categories table.
class _CategoryTableHeader extends StatelessWidget {
  const _CategoryTableHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    Widget h(String label, {TextAlign align = TextAlign.left}) => Text(
          label,
          textAlign: align,
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: WebInsets.sm),
      child: Row(
        children: [
          Expanded(child: h('CATEGORY')),
          SizedBox(width: _CatCols.type, child: h('TYPE')),
          SizedBox(
              width: _CatCols.color,
              child: h('COLOR', align: TextAlign.center)),
          SizedBox(
              width: _CatCols.exclude,
              child: h('EXCLUDE', align: TextAlign.center)),
          const SizedBox(width: _CatCols.actions),
        ],
      ),
    );
  }
}

/// One editable category row: color dot + inline-rename name field · type
/// dropdown · color swatch (cycles palette) · delete. Persists each edit
/// through [LedgerPresenter.updateCategory]/[deleteCategory].
class _CategoryTableRow extends StatefulWidget {
  final LedgerPresenter ledger;
  final FinanceCategory category;
  final VoidCallback onDelete;

  const _CategoryTableRow({
    super.key,
    required this.ledger,
    required this.category,
    required this.onDelete,
  });

  @override
  State<_CategoryTableRow> createState() => _CategoryTableRowState();
}

class _CategoryTableRowState extends State<_CategoryTableRow> {
  late final TextEditingController _ctl;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(text: widget.category.name);
    _focus = FocusNode()..addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _CategoryTableRow old) {
    super.didUpdateWidget(old);
    // Reflect external renames (e.g. sync) when this row isn't being edited.
    if (!_focus.hasFocus && widget.category.name != _ctl.text) {
      _ctl.text = widget.category.name;
    }
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    final name = _ctl.text.trim();
    if (name.isEmpty) {
      _ctl.text = widget.category.name; // revert empties
      return;
    }
    if (name == widget.category.name) return;
    widget.ledger.updateCategory(widget.category.copyWith(name: name));
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cat = widget.category;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WebInsets.xs),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                _ColorDot(hex: cat.colorHex),
                const SizedBox(width: WebInsets.sm),
                Expanded(
                  child: TextField(
                    controller: _ctl,
                    focusNode: _focus,
                    textCapitalization: TextCapitalization.words,
                    onSubmitted: (_) {
                      _commit();
                      _focus.unfocus();
                    },
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: _CatCols.type,
            child: _CategoryTypeDropdown(
              value: cat.type,
              onChanged: (t) =>
                  widget.ledger.updateCategory(cat.copyWith(type: t)),
            ),
          ),
          SizedBox(
            width: _CatCols.color,
            child: Center(
              child: _ColorSwatch(
                hex: cat.colorHex,
                onTap: () => widget.ledger.updateCategory(
                    cat.copyWith(colorHex: cycleCategoryColor(cat.colorHex))),
              ),
            ),
          ),
          SizedBox(
            width: _CatCols.exclude,
            child: Center(
              child: Tooltip(
                message: 'Exclude from income/expense totals',
                child: Switch.adaptive(
                  value: cat.excludeFromTotals,
                  onChanged: (v) => widget.ledger
                      .updateCategory(cat.copyWith(excludeFromTotals: v)),
                ),
              ),
            ),
          ),
          SizedBox(
            width: _CatCols.actions,
            child: Center(
              child: IconButton(
                tooltip: 'Delete category',
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                color: cs.onSurfaceVariant,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline Expense/Income dropdown used in both the category rows and add-row.
class _CategoryTypeDropdown extends StatelessWidget {
  final CategoryType value;
  final ValueChanged<CategoryType> onChanged;

  const _CategoryTypeDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return DropdownButtonHideUnderline(
      child: DropdownButton<CategoryType>(
        value: value,
        isDense: true,
        isExpanded: true,
        borderRadius: AppRadii.smBorder,
        icon: Icon(Icons.unfold_more, size: 14, color: cs.onSurfaceVariant),
        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        dropdownColor: cs.surfaceContainerHigh,
        items: const [
          DropdownMenuItem(value: CategoryType.expense, child: Text('Expense')),
          DropdownMenuItem(value: CategoryType.income, child: Text('Income')),
        ],
        onChanged: (t) {
          if (t != null && t != value) onChanged(t);
        },
      ),
    );
  }
}

/// Small color dot shown before a category name.
class _ColorDot extends StatelessWidget {
  final String hex;

  const _ColorDot({required this.hex});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: _hexColor(hex, Theme.of(context).colorScheme.primary),
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Clickable color swatch — cycles the category palette on tap.
class _ColorSwatch extends StatelessWidget {
  final String hex;
  final VoidCallback onTap;

  const _ColorSwatch({required this.hex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Click to change color',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: _hexColor(hex, cs.primary),
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
          ),
        ),
      ),
    );
  }
}

// ─── KPI row ─────────────────────────────────────────────────────────────────

/// Four summary tiles at the top of Setup (mirrors `setup.jsx`): account count,
/// liquid cash, savings & goals set aside, and credit available.
class _SetupKpiRow extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  const _SetupKpiRow({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final p = presenter;
    final tiles = <Widget>[
      WebStatTile(
        label: 'Accounts',
        value: '${p.activeAccountCount}',
        sub: '${p.liquidAccounts.length} liquid',
        icon: Icons.account_balance_outlined,
      ),
      WebStatTile(
        label: 'Liquid Cash',
        value: formatPeso(p.totalLiquidCash),
        sub: 'Spendable',
        icon: Icons.account_balance_wallet_outlined,
      ),
      WebStatTile(
        label: 'Savings & Goals',
        value: formatPeso(p.totalSavingsAndGoals),
        sub: 'Set aside',
        icon: Icons.savings_outlined,
      ),
      WebStatTile(
        label: 'Credit Available',
        value: formatPeso(p.totalCreditAvailable),
        sub: 'Across cards',
        icon: Icons.credit_card_outlined,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 1040
            ? 4
            : constraints.maxWidth >= 560
                ? 2
                : 1;
        final rows = <Widget>[];
        for (var i = 0; i < tiles.length; i += cols) {
          final cells = <Widget>[];
          for (var c = 0; c < cols; c++) {
            if (c > 0) cells.add(const SizedBox(width: WebInsets.lg));
            final idx = i + c;
            cells.add(Expanded(
              child: idx < tiles.length ? tiles[idx] : const SizedBox.shrink(),
            ));
          }
          if (rows.isNotEmpty) rows.add(const SizedBox(height: WebInsets.lg));
          rows.add(IntrinsicHeight(
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: cells),
          ));
        }
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
      },
    );
  }
}

// ─── Accounts table ───────────────────────────────────────────────────────────

/// Column widths for the spreadsheet-style accounts table. The Account column
/// flexes; the rest are fixed and right-aligned (matching `setup.jsx`).
class _Cols {
  static const double type = 150;
  static const double balance = 130;
  static const double limit = 120;
  static const double available = 130;
  static const double actions = 92;
}

/// One role group within the accounts table — a labelled sub-header followed by
/// its account rows (sub-accounts indented under their parent).
typedef _AccountGroup = ({
  String title,
  List<({FinancialAccount account, bool indented})> rows,
});

/// Single card holding every account in one inline spreadsheet-style table —
/// adopts the Claude Design layout while keeping the rich edit dialog, inline
/// type switching, goal progress and credit availability from the prior view.
/// Rows are organised into labelled role groups (Liquid → Savings & Goals →
/// Credit → Custodian); sub-accounts render indented under their parent.
class _AccountsTableCard extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  const _AccountsTableCard({required this.presenter});

  List<_AccountGroup> _groups() {
    List<({FinancialAccount account, bool indented})> expand(
        List<FinancialAccount> accts) {
      final out = <({FinancialAccount account, bool indented})>[];
      for (final a in accts) {
        out.add((account: a, indented: false));
        for (final sub in presenter.subAccountsOf(a.id)) {
          out.add((account: sub, indented: true));
        }
      }
      return out;
    }

    final groups = <_AccountGroup>[];
    void add(String title, List<FinancialAccount> accts) {
      if (accts.isEmpty) return;
      groups.add((title: title, rows: expand(accts)));
    }

    add('Liquid', presenter.liquidAccounts);
    add('Savings & Goals',
        [...presenter.savingsAccounts, ...presenter.goalAccounts]);
    add('Credit', presenter.creditAccounts);
    add('Custodian / Held', presenter.custodianAccounts);
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final groups = _groups();

    final children = <Widget>[
      const _AccountTableHeader(),
      Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
    ];
    for (final group in groups) {
      children.add(_AccountGroupHeader(title: group.title));
      for (final row in group.rows) {
        children.add(_AccountTableRow(
          presenter: presenter,
          account: row.account,
          indented: row.indented,
        ));
        children.add(Divider(
            height: 1, color: cs.outlineVariant.withValues(alpha: 0.25)));
      }
    }

    return WebCard(
      title: 'Accounts',
      description: "Each account's type & balance · credit cards use a limit",
      padding: const EdgeInsets.symmetric(
        horizontal: WebInsets.xl,
        vertical: WebInsets.lg,
      ),
      // The fixed columns total ~622px plus a flexible ACCOUNT column. Below the
      // rail breakpoint the content area can fall under that, so give the table
      // a bounded min width and scroll horizontally when the viewport is narrow
      // — matching the budget table and avoiding a RenderFlex overflow.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tableWidth = max(820.0, constraints.maxWidth);
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

/// A role sub-header inside the accounts table (e.g. "Liquid", "Credit").
class _AccountGroupHeader extends StatelessWidget {
  final String title;

  const _AccountGroupHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      width: double.infinity,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      padding: const EdgeInsets.symmetric(
          horizontal: WebInsets.sm, vertical: WebInsets.sm),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

/// Uppercase column header row for the accounts table.
class _AccountTableHeader extends StatelessWidget {
  const _AccountTableHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    Widget h(String label, {TextAlign align = TextAlign.left}) => Text(
          label,
          textAlign: align,
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: WebInsets.sm),
      child: Row(
        children: [
          Expanded(child: h('ACCOUNT')),
          SizedBox(width: _Cols.type, child: h('TYPE')),
          SizedBox(
              width: _Cols.balance,
              child: h('BALANCE', align: TextAlign.right)),
          SizedBox(
              width: _Cols.limit,
              child: h('CREDIT LIMIT', align: TextAlign.right)),
          SizedBox(
              width: _Cols.available,
              child: h('AVAILABLE', align: TextAlign.right)),
          const SizedBox(width: _Cols.actions),
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

class _AccountTableRow extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  final FinancialAccount account;
  final bool indented;

  const _AccountTableRow({
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
    final isCredit = account.isLiability;
    final availableCredit = account.availableCredit;

    // ACCOUNT — colored icon chip + name (+ Credit badge), indented for subs.
    final accountCell = Padding(
      padding: EdgeInsets.only(left: indented ? WebInsets.lg : 0),
      child: Row(
        children: [
          AccountBadge.of(account, size: 32),
          const SizedBox(width: WebInsets.md),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  account.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                // Goal progress under the name (kept from the prior view).
                // Width-capped so it stays within the name column and never
                // crowds the Type cell to its right.
                if (isGoal && goalTarget != null && goalTarget > 0) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 180,
                      child: WebProgressBar(
                          value: account.balance / goalTarget, color: color),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isCredit) ...[
            const SizedBox(width: WebInsets.sm),
            const WebBadge('Credit', tone: WebBadgeTone.info),
          ],
        ],
      ),
    );

    // TYPE — inline switcher for assets; static label for liabilities.
    final typeCell = isCredit
        ? Text(_typeLabel,
            style:
                theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant))
        : _TypeDropdown(presenter: presenter, account: account);

    // BALANCE — red for liabilities; "of target" sub-line for goals.
    final balanceCell = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          formatPeso(account.balance),
          textAlign: TextAlign.right,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: isCredit ? cs.error : cs.onSurface,
          ),
        ),
        if (isGoal && goalTarget != null) ...[
          const SizedBox(height: 2),
          Text('of ${formatPeso(goalTarget)}',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ],
    );

    Widget rightText(String value, {Color? color}) => Text(
          value,
          textAlign: TextAlign.right,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: color ?? cs.onSurfaceVariant,
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WebInsets.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: accountCell),
          SizedBox(width: _Cols.type, child: typeCell),
          SizedBox(width: _Cols.balance, child: balanceCell),
          SizedBox(
            width: _Cols.limit,
            child: rightText(isCredit && account.creditLimit != null
                ? formatPeso(account.creditLimit!)
                : '—'),
          ),
          SizedBox(
            width: _Cols.available,
            child: rightText(
                availableCredit != null ? formatPeso(availableCredit) : '—',
                color: availableCredit != null ? cs.primary : null),
          ),
          SizedBox(
            width: _Cols.actions,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Liquid parents (bank/e-wallet/cash) can hold nested pockets
                // (savings, goals, time deposits). Sub-accounts and non-liquid
                // roles don't nest further, so the affordance is hidden there.
                if (!indented && account.isLiquid)
                  IconButton(
                    tooltip: 'Add savings pocket / goal',
                    onPressed: () =>
                        _showAddSubAccount(context, presenter, account),
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    color: cs.onSurfaceVariant,
                    visualDensity: VisualDensity.compact,
                  ),
                IconButton(
                  tooltip: 'Edit account',
                  onPressed: () =>
                      _showAccountSheet(context, presenter, account),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  color: cs.onSurfaceVariant,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: 'Delete account',
                  onPressed: () => _confirmDelete(context),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: cs.onSurfaceVariant,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
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
