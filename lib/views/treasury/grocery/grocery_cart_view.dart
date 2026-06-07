import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/grocery/cart_item.dart';
import 'package:intermittent_fasting/presenters/grocery_cart_presenter.dart';
import 'package:intermittent_fasting/utils/app_spacing.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/grocery/add_cart_item_sheet.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// Live grocery running-total screen (Plan 038). Add items + quantities while
/// shopping; the header shows an honest total breakdown so a budget shopper
/// always knows where they stand.
class GroceryCartView extends StatelessWidget {
  final GroceryCartPresenter presenter;

  const GroceryCartView({super.key, required this.presenter});

  void _showAddSheet(BuildContext context) {
    AppBottomSheet.show(
      context: context,
      title: 'Add item',
      body: AddCartItemSheet(presenter: presenter),
    );
  }

  void _showSetPriceSheet(BuildContext context, CartItem item) {
    AppBottomSheet.show(
      context: context,
      title: 'Set price · ${item.name}',
      body: _SetPriceSheet(presenter: presenter, item: item),
    );
  }

  void _showSetBudgetSheet(BuildContext context) {
    AppBottomSheet.show(
      context: context,
      title: 'Trip budget',
      body: _SetBudgetSheet(presenter: presenter),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await AppConfirmDialog.confirm(
      context: context,
      title: 'Clear cart?',
      body: 'Removes all items from this trip. Your remembered prices are '
          'kept for next time.',
      confirmLabel: 'Clear',
      isDestructive: true,
    );
    if (ok) await presenter.clearCart();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                _CartSummaryHeader(
                  presenter: presenter,
                  onEditBudget: () => _showSetBudgetSheet(context),
                ),
                Expanded(
                  child: presenter.isEmpty
                      ? const _EmptyCart()
                      : _CartList(
                          presenter: presenter,
                          onSetPrice: (item) =>
                              _showSetPriceSheet(context, item),
                        ),
                ),
                _BottomBar(
                  presenter: presenter,
                  onAdd: () => _showAddSheet(context),
                  onClear: () => _confirmClear(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Summary header ───────────────────────────────────────────────────────────

class _CartSummaryHeader extends StatelessWidget {
  final GroceryCartPresenter presenter;
  final VoidCallback onEditBudget;

  const _CartSummaryHeader(
      {required this.presenter, required this.onEditBudget});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final overBudget = presenter.isOverBudget;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              overBudget ? cs.error : cs.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RUNNING TOTAL',
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            formatPeso(presenter.grandTotal),
            style: theme.textTheme.displaySmall?.copyWith(
              color: overBudget ? cs.error : cs.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _BreakdownLine(presenter: presenter),
          const SizedBox(height: AppSpacing.sm),
          _BudgetRow(presenter: presenter, onEditBudget: onEditBudget),
        ],
      ),
    );
  }
}

class _BreakdownLine extends StatelessWidget {
  final GroceryCartPresenter presenter;
  const _BreakdownLine({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final parts = <Widget>[];

    parts.add(_chip(
      context,
      '${formatPeso(presenter.confirmedTotal)} confirmed',
      cs.onSurfaceVariant,
    ));
    if (presenter.hasEstimates) {
      parts.add(_chip(
        context,
        '~${formatPeso(presenter.estimatedTotal)} est',
        cs.secondary,
      ));
    }
    if (presenter.unpricedCount > 0) {
      parts.add(_chip(
        context,
        '${presenter.unpricedCount} unpriced',
        cs.error,
      ));
    }

    return Wrap(
        spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, children: parts);
  }

  Widget _chip(BuildContext context, String text, Color color) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
    );
  }
}

class _BudgetRow extends StatelessWidget {
  final GroceryCartPresenter presenter;
  final VoidCallback onEditBudget;

  const _BudgetRow({required this.presenter, required this.onEditBudget});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (!presenter.hasBudget) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onEditBudget,
          icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
          label: const Text('Set a budget'),
        ),
      );
    }

    final remaining = presenter.budgetRemaining ?? 0;
    final over = remaining < 0;
    return InkWell(
      onTap: onEditBudget,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(
              over ? Icons.warning_amber_rounded : Icons.account_balance_wallet,
              size: 18,
              color: over ? cs.error : cs.primary,
            ),
            const SizedBox(width: 6),
            Text(
              over
                  ? 'Over by ${formatPeso(remaining.abs())}'
                  : '${formatPeso(remaining)} left of ${formatPeso(presenter.budget!)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: over ? cs.error : cs.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Icon(Icons.edit_outlined, size: 16, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

// ── Item list ────────────────────────────────────────────────────────────────

class _CartList extends StatelessWidget {
  final GroceryCartPresenter presenter;
  final ValueChanged<CartItem> onSetPrice;

  const _CartList({required this.presenter, required this.onSetPrice});

  @override
  Widget build(BuildContext context) {
    final items = presenter.items;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        return _CartItemTile(
          item: item,
          presenter: presenter,
          onSetPrice: () => onSetPrice(item),
        );
      },
    );
  }
}

class _CartItemTile extends StatelessWidget {
  final CartItem item;
  final GroceryCartPresenter presenter;
  final VoidCallback onSetPrice;

  const _CartItemTile({
    required this.item,
    required this.presenter,
    required this.onSetPrice,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final String subtitle;
    final Color subtitleColor;
    switch (item.priceState) {
      case PriceState.confirmed:
        subtitle = '${formatPeso(item.unitPrice!)} each';
        subtitleColor = cs.onSurfaceVariant;
        break;
      case PriceState.remembered:
        subtitle = '~${formatPeso(item.unitPrice!)} each · tap to confirm';
        subtitleColor = cs.secondary;
        break;
      case PriceState.unknown:
        subtitle = 'No price · tap to add';
        subtitleColor = cs.error;
        break;
    }

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.md),
        color: cs.errorContainer,
        child: Icon(Icons.delete_outline, color: cs.onErrorContainer),
      ),
      onDismissed: (_) => presenter.removeItem(item.id),
      child: InkWell(
        onTap: onSetPrice,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: subtitleColor),
                    ),
                  ],
                ),
              ),
              _QuantityStepper(
                quantity: item.quantity,
                onChanged: (q) => presenter.updateQuantity(item.id, q),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 84,
                child: Text(
                  item.isPriced ? formatPeso(item.lineTotal) : '—',
                  textAlign: TextAlign.right,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: item.priceState == PriceState.remembered
                        ? cs.secondary
                        : cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// −/+ stepper shared by the cart tiles.
class _QuantityStepper extends StatelessWidget {
  final double quantity;
  final ValueChanged<double> onChanged;

  const _QuantityStepper({required this.quantity, required this.onChanged});

  String get _label => quantity == quantity.truncateToDouble()
      ? quantity.toInt().toString()
      : quantity.toString();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged(quantity - 1),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Container(
          constraints: const BoxConstraints(minWidth: 24),
          alignment: Alignment.center,
          child: Text(_label, style: Theme.of(context).textTheme.titleMedium),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged(quantity + 1),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shopping_cart_outlined,
                size: 56, color: cs.onSurfaceVariant),
            const SizedBox(height: AppSpacing.md),
            Text('Your cart is empty', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Add items as you shop to track your running total.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bottom action bar ──────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final GroceryCartPresenter presenter;
  final VoidCallback onAdd;
  final VoidCallback onClear;

  const _BottomBar({
    required this.presenter,
    required this.onAdd,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: AppPrimaryButton(
              label: 'Add item',
              leading: Icons.add,
              onPressed: onAdd,
            ),
          ),
          if (!presenter.isEmpty) ...[
            const SizedBox(width: AppSpacing.sm),
            IconButton.outlined(
              tooltip: 'Clear cart',
              onPressed: onClear,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Mini forms ───────────────────────────────────────────────────────────────

class _SetPriceSheet extends StatefulWidget {
  final GroceryCartPresenter presenter;
  final CartItem item;

  const _SetPriceSheet({required this.presenter, required this.item});

  @override
  State<_SetPriceSheet> createState() => _SetPriceSheetState();
}

class _SetPriceSheetState extends State<_SetPriceSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.item.unitPrice?.toStringAsFixed(2) ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final price = double.tryParse(_controller.text.trim());
    if (price == null) return;
    await widget.presenter.setPrice(widget.item.id, price);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppTextField(
          controller: _controller,
          label: 'Unit price',
          prefix: const Text('₱ '),
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppPrimaryButton(label: 'Save price', onPressed: _save),
      ],
    );
  }
}

class _SetBudgetSheet extends StatefulWidget {
  final GroceryCartPresenter presenter;

  const _SetBudgetSheet({required this.presenter});

  @override
  State<_SetBudgetSheet> createState() => _SetBudgetSheetState();
}

class _SetBudgetSheetState extends State<_SetBudgetSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.presenter.budget?.toStringAsFixed(2) ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_controller.text.trim());
    await widget.presenter.setBudget(amount);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppTextField(
          controller: _controller,
          label: 'Budget for this trip',
          hint: 'Leave blank to remove',
          prefix: const Text('₱ '),
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppPrimaryButton(label: 'Save budget', onPressed: _save),
      ],
    );
  }
}
