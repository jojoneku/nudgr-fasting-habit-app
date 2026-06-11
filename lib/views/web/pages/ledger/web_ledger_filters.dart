import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../../widgets/web_widgets.dart';

/// Filter row above the detailed-records table: month stepper, account and
/// category dropdowns, and a prominent "Add transaction" action (Plan 050-B).
class LedgerFilterBar extends StatelessWidget {
  final LedgerPresenter presenter;
  final VoidCallback onAdd;
  const LedgerFilterBar({
    super.key,
    required this.presenter,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return WebCard(
      padding: const EdgeInsets.symmetric(
        horizontal: WebInsets.lg,
        vertical: WebInsets.md,
      ),
      child: Wrap(
        spacing: WebInsets.lg,
        runSpacing: WebInsets.md,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _MonthStepper(presenter: presenter),
          _AccountDropdown(presenter: presenter),
          _CategoryDropdown(presenter: presenter),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add transaction'),
          ),
        ],
      ),
    );
  }
}

class _MonthStepper extends StatelessWidget {
  final LedgerPresenter presenter;
  const _MonthStepper({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Previous month',
          onPressed: () =>
              presenter.setMonth(previousMonth(presenter.selectedMonth)),
        ),
        SizedBox(
          width: 150,
          child: Text(
            monthLabel(presenter.selectedMonth),
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Next month',
          onPressed: () =>
              presenter.setMonth(nextMonth(presenter.selectedMonth)),
        ),
      ],
    );
  }
}

class _AccountDropdown extends StatelessWidget {
  final LedgerPresenter presenter;
  const _AccountDropdown({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final accounts = presenter.accounts
        .where((a) => a.isActive && !a.isSubAccount)
        .toList(growable: false);
    return _FilterDropdown<String?>(
      icon: Icons.account_balance_wallet_outlined,
      hint: 'All accounts',
      value: presenter.selectedAccountId,
      onChanged: presenter.setAccount,
      items: [
        const DropdownMenuItem(value: null, child: Text('All accounts')),
        for (final FinancialAccount a in accounts)
          DropdownMenuItem(value: a.id, child: Text(a.name)),
      ],
    );
  }
}

class _CategoryDropdown extends StatelessWidget {
  final LedgerPresenter presenter;
  const _CategoryDropdown({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final categories = presenter.categories;
    return _FilterDropdown<String?>(
      icon: Icons.label_outline,
      hint: 'All categories',
      value: presenter.selectedCategoryId,
      onChanged: presenter.setCategoryFilter,
      items: [
        const DropdownMenuItem(value: null, child: Text('All categories')),
        for (final FinanceCategory c in categories)
          DropdownMenuItem(value: c.id, child: Text(c.name)),
      ],
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  final IconData icon;
  final String hint;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  const _FilterDropdown({
    required this.icon,
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: WebInsets.md),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: WebInsets.sm),
          DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              hint: Text(hint),
              isDense: true,
              borderRadius: BorderRadius.circular(8),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
