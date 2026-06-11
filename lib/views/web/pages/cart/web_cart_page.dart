import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/grocery/cart_item.dart';
import 'package:intermittent_fasting/models/grocery/item_unit.dart';
import 'package:intermittent_fasting/presenters/grocery_cart_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

import '../../widgets/web_widgets.dart';
import 'cart_dialogs.dart';

/// Desktop Treasury Grocery Cart (Plan 050-F).
///
/// A KPI strip (confirmed / estimated / unpriced / budget remaining), a budget
/// meter, and a sheet-style [WebDataTable] of cart lines. Row click opens the
/// edit dialog; the header carries add-item and checkout-to-Ledger actions.
class WebCartPage extends StatelessWidget {
  final GroceryCartPresenter presenter;
  const WebCartPage({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.all(WebInsets.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WebSectionHeader(
              title: 'Grocery Cart',
              subtitle: 'Running total before you reach the till.',
              trailing: _HeaderActions(presenter: presenter),
            ),
            _StatStrip(presenter: presenter),
            const SizedBox(height: WebInsets.xl),
            _BudgetCard(presenter: presenter),
            const SizedBox(height: WebInsets.xl),
            _ItemsCard(presenter: presenter),
          ],
        ),
      ),
    );
  }
}

class _HeaderActions extends StatelessWidget {
  final GroceryCartPresenter presenter;
  const _HeaderActions({required this.presenter});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          onPressed: () => showAddCartItemDialog(context, presenter),
          icon: const Icon(Icons.add),
          label: const Text('Add item'),
        ),
        const SizedBox(width: WebInsets.md),
        FilledButton.icon(
          onPressed:
              presenter.canCheckoutToLedger ? () => _checkout(context) : null,
          icon: const Icon(Icons.point_of_sale_outlined),
          label: const Text('Checkout → Ledger'),
        ),
      ],
    );
  }

  Future<void> _checkout(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final done = await showCheckoutDialog(context, presenter);
    if (done) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Trip saved'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
}

// ── KPI strip ────────────────────────────────────────────────────────────────

class _StatStrip extends StatelessWidget {
  final GroceryCartPresenter presenter;
  const _StatStrip({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tiles = <Widget>[
      WebStatTile(
        label: 'Confirmed total',
        value: formatPeso(presenter.confirmedTotal),
        icon: Icons.check_circle_outline,
        sub: '${presenter.itemCount} item(s) in cart',
      ),
      WebStatTile(
        label: 'Estimated total',
        value: '~${formatPeso(presenter.estimatedTotal)}',
        icon: Icons.history,
        valueColor: presenter.hasEstimates ? cs.secondary : null,
        sub: 'From price memory',
      ),
      WebStatTile(
        label: 'Unpriced items',
        value: '${presenter.unpricedCount}',
        icon: Icons.help_outline,
        valueColor: presenter.unpricedCount > 0 ? cs.error : null,
        sub: 'Not counted in the total',
      ),
      WebStatTile(
        label: 'Budget remaining',
        value: presenter.budgetRemainingLabel,
        icon: Icons.account_balance_wallet_outlined,
        valueColor: presenter.isOverBudget ? cs.error : null,
        sub: presenter.budgetSubLabel,
      ),
    ];

    return WebStatGrid(tiles: tiles);
  }
}

// ── Budget meter ───────────────────────────────────────────────────────────

class _BudgetCard extends StatelessWidget {
  final GroceryCartPresenter presenter;
  const _BudgetCard({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final over = presenter.isOverBudget;

    return WebCard(
      title: 'Budget',
      description: 'Track the running total against this trip\'s cap.',
      trailing: TextButton.icon(
        onPressed: () => showSetBudgetDialog(context, presenter),
        icon: const Icon(Icons.edit_outlined, size: 18),
        label: Text(presenter.hasBudget ? 'Edit' : 'Set budget'),
      ),
      child: presenter.hasBudget
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${formatPeso(presenter.grandTotal)} of ${formatPeso(presenter.budget!)}',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (over)
                      const WebBadge('Over budget',
                          tone: WebBadgeTone.danger,
                          icon: Icons.warning_amber_rounded),
                  ],
                ),
                const SizedBox(height: WebInsets.md),
                ClipRRect(
                  borderRadius: AppRadii.smBorder,
                  child: LinearProgressIndicator(
                    value: presenter.budgetUsedFraction,
                    minHeight: 10,
                    backgroundColor: cs.surfaceContainerHighest,
                    color: over ? cs.error : cs.primary,
                  ),
                ),
                const SizedBox(height: WebInsets.sm),
                Text(
                  presenter.budgetDetailLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: over ? cs.error : cs.onSurfaceVariant,
                    fontWeight: over ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            )
          : Text(
              'No budget set for this trip.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
    );
  }
}

// ── Items table ──────────────────────────────────────────────────────────────

class _ItemsCard extends StatelessWidget {
  final GroceryCartPresenter presenter;
  const _ItemsCard({required this.presenter});

  @override
  Widget build(BuildContext context) {
    return WebCard(
      title: 'Items',
      description:
          'Click a row to set its price, adjust quantity, or remove it.',
      trailing: OutlinedButton.icon(
        onPressed: () => showAddCartItemDialog(context, presenter),
        icon: const Icon(Icons.add),
        label: const Text('Add item'),
      ),
      padding: const EdgeInsets.all(WebInsets.lg),
      child: WebDataTable<CartItem>(
        rows: presenter.items,
        emptyLabel: 'Your cart is empty — add items as you shop.',
        onRowTap: (item) => showEditCartItemDialog(context, presenter, item),
        columns: [
          WebColumn<CartItem>(
            label: 'Item',
            flex: 3,
            cell: (context, row) =>
                Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          WebColumn<CartItem>(
            label: 'Qty',
            numeric: true,
            cell: (context, row) => Text(row.unit.quantityLabel(row.quantity)),
          ),
          WebColumn<CartItem>(
            label: 'Unit',
            cell: (context, row) => Text(row.unit.label),
          ),
          WebColumn<CartItem>(
            label: 'Unit price',
            numeric: true,
            flex: 2,
            cell: (context, row) => _UnitPriceCell(item: row),
          ),
          WebColumn<CartItem>(
            label: 'Line total',
            numeric: true,
            flex: 2,
            cell: (context, row) => _LineTotalCell(item: row),
          ),
        ],
      ),
    );
  }
}

class _UnitPriceCell extends StatelessWidget {
  final CartItem item;
  const _UnitPriceCell({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    switch (item.priceState) {
      case PriceState.confirmed:
        return Text('${formatPeso(item.unitPrice!)} ${item.unit.priceSuffix}');
      case PriceState.remembered:
        return Text(
          '~${formatPeso(item.unitPrice!)} ${item.unit.priceSuffix}',
          style: theme.textTheme.bodyMedium?.copyWith(color: cs.secondary),
        );
      case PriceState.unknown:
        return const WebBadge('No price', tone: WebBadgeTone.danger);
    }
  }
}

class _LineTotalCell extends StatelessWidget {
  final CartItem item;
  const _LineTotalCell({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color =
        item.priceState == PriceState.remembered ? cs.secondary : cs.onSurface;
    return Text(
      item.isPriced ? formatPeso(item.lineTotal) : '—',
      style: theme.textTheme.bodyMedium
          ?.copyWith(color: color, fontWeight: FontWeight.w600),
    );
  }
}
