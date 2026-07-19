import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/grocery/cart_item.dart';
import 'package:intermittent_fasting/models/grocery/item_unit.dart';
import 'package:intermittent_fasting/presenters/grocery_cart_presenter.dart';
import 'package:intermittent_fasting/utils/app_spacing.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/grocery/add_cart_item_sheet.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

final _tripDateFmt = DateFormat('MMM d · h:mm a');

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

  void _showHistorySheet(BuildContext context) {
    AppBottomSheet.show(
      context: context,
      title: 'Trip history',
      body: _TripHistorySheet(presenter: presenter),
    );
  }

  void _showCheckoutSheet(BuildContext context) {
    AppBottomSheet.show(
      context: context,
      title: 'Finish trip',
      body: _CheckoutSheet(presenter: presenter),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await AppConfirmDialog.confirm(
      context: context,
      title: 'Clear cart?',
      body: 'Removes all items from this trip without saving it. Your '
          'remembered prices are kept.',
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
                  onShowHistory: () => _showHistorySheet(context),
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
                  onFinish: () => _showCheckoutSheet(context),
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
  final VoidCallback onShowHistory;

  const _CartSummaryHeader({
    required this.presenter,
    required this.onEditBudget,
    required this.onShowHistory,
  });

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
          Row(
            children: [
              Expanded(
                child: Text(
                  'RUNNING TOTAL',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              if (presenter.hasTripHistory)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Trip history',
                  onPressed: onShowHistory,
                  icon: const Icon(Icons.history),
                ),
            ],
          ),
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
    final cs = Theme.of(context).colorScheme;
    final parts = <Widget>[
      _chip(context, '${formatPeso(presenter.confirmedTotal)} confirmed',
          cs.onSurfaceVariant),
    ];
    if (presenter.hasEstimates) {
      parts.add(_chip(context, '~${formatPeso(presenter.estimatedTotal)} est',
          context.appColors.fast));
    }
    if (presenter.unpricedCount > 0) {
      parts
          .add(_chip(context, '${presenter.unpricedCount} unpriced', cs.error));
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

    final over = presenter.isOverBudget;
    final remaining = presenter.budgetRemaining ?? 0;
    return InkWell(
      onTap: onEditBudget,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  over
                      ? Icons.warning_amber_rounded
                      : Icons.account_balance_wallet,
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
            const SizedBox(height: 8),
            // Reference budget bar: how much of the trip budget is used.
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: presenter.budget! > 0
                    ? (presenter.grandTotal / presenter.budget!).clamp(0.0, 1.0)
                    : 0.0,
                minHeight: 7,
                backgroundColor: cs.surfaceContainerHighest,
                color: over ? cs.error : context.appColors.fast,
              ),
            ),
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
    final suffix = item.unit.priceSuffix;

    final String subtitle;
    final Color subtitleColor;
    switch (item.priceState) {
      case PriceState.confirmed:
        subtitle = '${formatPeso(item.unitPrice!)} $suffix';
        subtitleColor = cs.onSurfaceVariant;
        break;
      case PriceState.remembered:
        subtitle = '~${formatPeso(item.unitPrice!)} $suffix · tap to confirm';
        subtitleColor = context.appColors.fast;
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
      // Remove via the data model (awaited) rather than onDismissed, so the
      // row leaves the tree on the rebuild — avoids the "dismissed Dismissible
      // still in the tree" assertion when the persist write spans a frame.
      confirmDismiss: (_) async {
        final index = presenter.items.indexWhere((i) => i.id == item.id);
        final removed = item;
        await presenter.removeItem(item.id);
        if (context.mounted) {
          AppToast.action(
            context,
            message: '${removed.name} removed',
            actionLabel: 'Undo',
            onAction: () =>
                presenter.restoreItem(removed, index < 0 ? 0 : index),
          );
        }
        return true;
      },
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
                unit: item.unit,
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
                        ? context.appColors.fast
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

/// −/+ stepper for the cart tiles. Steps by the unit's natural increment.
class _QuantityStepper extends StatelessWidget {
  final double quantity;
  final ItemUnit unit;
  final ValueChanged<double> onChanged;

  const _QuantityStepper({
    required this.quantity,
    required this.unit,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final step = unit.step;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          // Disabled at one step — removal is intentional (swipe), not an
          // accidental extra tap on the minus button.
          onPressed: quantity > step ? () => onChanged(quantity - step) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Container(
          constraints: const BoxConstraints(minWidth: 52),
          alignment: Alignment.center,
          child: Text(
            unit.quantityLabel(quantity),
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: cs.onSurface),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged(quantity + step),
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
  final VoidCallback onFinish;
  final VoidCallback onClear;

  const _BottomBar({
    required this.presenter,
    required this.onAdd,
    required this.onFinish,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final empty = presenter.isEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!empty) ...[
            AppPrimaryButton(
              label: 'Finish trip',
              leading: Icons.check_circle_outline,
              onPressed: onFinish,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Row(
            children: [
              Expanded(
                child: AppPrimaryButton(
                  label: 'Add item',
                  leading: Icons.add,
                  variant:
                      empty ? AppButtonVariant.filled : AppButtonVariant.tonal,
                  onPressed: onAdd,
                ),
              ),
              if (!empty) ...[
                const SizedBox(width: AppSpacing.sm),
                IconButton.outlined(
                  tooltip: 'Clear cart',
                  onPressed: onClear,
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Set price / budget sheets ──────────────────────────────────────────────────

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
          label: 'Price ${widget.item.unit.priceSuffix}',
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
    final text = _controller.text.trim();
    // Blank intentionally clears the budget (per the field hint). A non-blank
    // but unparseable value must NOT silently wipe an existing budget — keep it
    // and let the user correct the input.
    if (text.isNotEmpty) {
      final amount = double.tryParse(text.replaceAll(',', ''));
      if (amount == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Enter a valid amount, or leave blank to remove.'),
          ),
        );
        return;
      }
      await widget.presenter.setBudget(amount);
    } else {
      await widget.presenter.setBudget(null);
    }
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

// ── Checkout sheet ───────────────────────────────────────────────────────────

class _CheckoutSheet extends StatefulWidget {
  final GroceryCartPresenter presenter;

  const _CheckoutSheet({required this.presenter});

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  bool _logToLedger = false;
  String? _accountId;
  String? _categoryId;

  @override
  void initState() {
    super.initState();
    final accounts = widget.presenter.ledgerAccounts;
    if (accounts.isNotEmpty) _accountId = accounts.first.id;
  }

  bool get _canLog =>
      widget.presenter.canPostToLedger &&
      widget.presenter.ledgerAccounts.isNotEmpty;

  Future<void> _finish() async {
    final post = _logToLedger && _canLog && _accountId != null;
    await widget.presenter.checkout(
      postToLedger: post,
      accountId: _accountId,
      categoryId: _categoryId,
    );
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(post ? 'Trip saved & logged to ledger' : 'Trip saved'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.presenter;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accounts = p.ledgerAccounts;
    final categories = p.ledgerCategories;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(formatPeso(p.grandTotal),
            style: theme.textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: AppSpacing.xs),
        _BreakdownLine(presenter: p),
        if (p.unpricedCount > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${p.unpricedCount} item(s) have no price and aren\'t counted in '
            'the total.',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
          ),
        ],
        if (_canLog) ...[
          const SizedBox(height: AppSpacing.md),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Log to ledger as an expense'),
            value: _logToLedger,
            onChanged: (v) => setState(() => _logToLedger = v),
          ),
          if (_logToLedger) ...[
            DropdownButtonFormField<String>(
              initialValue: _accountId,
              decoration: const InputDecoration(labelText: 'Account'),
              items: [
                for (final a in accounts)
                  DropdownMenuItem(value: a.id, child: Text(a.name)),
              ],
              onChanged: (v) => setState(() => _accountId = v),
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: _categoryId,
              decoration:
                  const InputDecoration(labelText: 'Category (optional)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('None')),
                for (final c in categories)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => _categoryId = v),
            ),
          ],
        ],
        const SizedBox(height: AppSpacing.lg),
        AppPrimaryButton(
          label: _logToLedger && _canLog ? 'Finish & log' : 'Finish trip',
          leading: Icons.check_circle_outline,
          onPressed: _finish,
        ),
      ],
    );
  }
}

// ── Trip history ───────────────────────────────────────────────────────────────

class _TripHistorySheet extends StatelessWidget {
  final GroceryCartPresenter presenter;

  const _TripHistorySheet({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final trips = presenter.tripHistory;

    if (trips.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text('No saved trips yet.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant)),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.6,
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: trips.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final trip = trips[i];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(formatPeso(trip.total),
                style: theme.textTheme.titleMedium),
            subtitle: Text(
              '${_tripDateFmt.format(trip.savedAt)} · ${trip.itemCount} item(s)'
              '${trip.postedToLedger ? ' · logged' : ''}',
              style: theme.textTheme.bodySmall,
            ),
            trailing: TextButton(
              onPressed: () async {
                await presenter.repeatTrip(trip.id);
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Items added to your cart'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: const Text('Repeat'),
            ),
            onLongPress: () async {
              final ok = await AppConfirmDialog.confirm(
                context: context,
                title: 'Delete trip?',
                body: 'Removes this trip from history.',
                confirmLabel: 'Delete',
                isDestructive: true,
              );
              if (ok) await presenter.deleteTrip(trip.id);
            },
          );
        },
      ),
    );
  }
}
