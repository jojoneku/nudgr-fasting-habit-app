import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/grocery/cart_item.dart';
import 'package:intermittent_fasting/models/grocery/item_unit.dart';
import 'package:intermittent_fasting/presenters/grocery_cart_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/grocery/add_cart_item_sheet.dart';

import '../../widgets/web_widgets.dart';

/// Opens the shared mobile [AddCartItemSheet] as a desktop dialog. The sheet
/// already pops itself on submit, so this resolves when the user is done.
Future<void> showAddCartItemDialog(
  BuildContext context,
  GroceryCartPresenter presenter,
) {
  return showWebDialog<void>(
    context: context,
    title: 'Add item',
    maxWidth: 460,
    child: AddCartItemSheet(presenter: presenter),
  );
}

/// Row-edit dialog: set/confirm the unit price, change quantity & unit, or
/// remove the line. Web equivalent of tapping a mobile cart tile.
Future<void> showEditCartItemDialog(
  BuildContext context,
  GroceryCartPresenter presenter,
  CartItem item,
) {
  return showWebDialog<void>(
    context: context,
    title: 'Edit · ${item.name}',
    maxWidth: 460,
    child: _EditCartItemForm(presenter: presenter, item: item),
  );
}

class _EditCartItemForm extends StatefulWidget {
  final GroceryCartPresenter presenter;
  final CartItem item;
  const _EditCartItemForm({required this.presenter, required this.item});

  @override
  State<_EditCartItemForm> createState() => _EditCartItemFormState();
}

class _EditCartItemFormState extends State<_EditCartItemForm> {
  late final TextEditingController _price;
  late final TextEditingController _qty;
  late ItemUnit _unit;

  @override
  void initState() {
    super.initState();
    _price = TextEditingController(
      text: widget.item.unitPrice?.toStringAsFixed(2) ?? '',
    );
    _qty = TextEditingController(text: _formatQty(widget.item.quantity));
    _unit = widget.item.unit;
  }

  String _formatQty(double q) =>
      q == q.truncateToDouble() ? q.toInt().toString() : q.toString();

  @override
  void dispose() {
    _price.dispose();
    _qty.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final id = widget.item.id;
    final qty = double.tryParse(_qty.text.trim());
    final price = double.tryParse(_price.text.trim());
    if (qty != null && qty > 0 && qty != widget.item.quantity) {
      await widget.presenter.updateQuantity(id, qty);
    }
    if (price != null && price >= 0) {
      await widget.presenter.setPrice(id, price);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _remove() async {
    await widget.presenter.removeItem(widget.item.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Unit', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: WebInsets.sm),
        Wrap(
          spacing: WebInsets.sm,
          children: [
            for (final u in ItemUnit.values)
              ChoiceChip(
                label: Text(u.label),
                selected: _unit == u,
                onSelected: (_) => setState(() => _unit = u),
              ),
          ],
        ),
        const SizedBox(height: WebInsets.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _qty,
                decoration: const InputDecoration(
                  labelText: 'Quantity',
                  border: OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const SizedBox(width: WebInsets.md),
            Expanded(
              child: TextField(
                controller: _price,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Price ${_unit.priceSuffix}',
                  prefixText: '₱ ',
                  border: const OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onSubmitted: (_) => _save(),
              ),
            ),
          ],
        ),
        const SizedBox(height: WebInsets.xl),
        Row(
          children: [
            TextButton.icon(
              onPressed: _remove,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Remove'),
              style: TextButton.styleFrom(foregroundColor: cs.error),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Trip-budget editor dialog.
Future<void> showSetBudgetDialog(
  BuildContext context,
  GroceryCartPresenter presenter,
) {
  return showWebDialog<void>(
    context: context,
    title: 'Trip budget',
    maxWidth: 460,
    child: _SetBudgetForm(presenter: presenter),
  );
}

class _SetBudgetForm extends StatefulWidget {
  final GroceryCartPresenter presenter;
  const _SetBudgetForm({required this.presenter});

  @override
  State<_SetBudgetForm> createState() => _SetBudgetFormState();
}

class _SetBudgetFormState extends State<_SetBudgetForm> {
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Budget for this trip',
            hintText: 'Leave blank to remove',
            prefixText: '₱ ',
            border: OutlineInputBorder(),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: WebInsets.xl),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(onPressed: _save, child: const Text('Save')),
        ),
      ],
    );
  }
}

/// Checkout dialog — confirms the total, optionally posts to the Ledger as an
/// outflow, then clears the cart. Returns true when a trip was finished.
Future<bool> showCheckoutDialog(
  BuildContext context,
  GroceryCartPresenter presenter,
) async {
  final done = await showWebDialog<bool>(
    context: context,
    title: 'Finish trip',
    maxWidth: 460,
    child: _CheckoutForm(presenter: presenter),
  );
  return done ?? false;
}

class _CheckoutForm extends StatefulWidget {
  final GroceryCartPresenter presenter;
  const _CheckoutForm({required this.presenter});

  @override
  State<_CheckoutForm> createState() => _CheckoutFormState();
}

class _CheckoutFormState extends State<_CheckoutForm> {
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
    if (mounted) Navigator.of(context).pop(true);
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(formatPeso(p.grandTotal),
            style: theme.textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: WebInsets.xs),
        Text(
          '${formatPeso(p.confirmedTotal)} confirmed'
          '${p.hasEstimates ? ' · ~${formatPeso(p.estimatedTotal)} estimated' : ''}',
          style:
              theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        if (p.unpricedCount > 0) ...[
          const SizedBox(height: WebInsets.sm),
          Text(
            "${p.unpricedCount} item(s) have no price and aren't counted in "
            'the total.',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
          ),
        ],
        if (_canLog) ...[
          const SizedBox(height: WebInsets.md),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Log to ledger as an expense'),
            value: _logToLedger,
            onChanged: (v) => setState(() => _logToLedger = v),
          ),
          if (_logToLedger) ...[
            DropdownButtonFormField<String>(
              initialValue: _accountId,
              decoration: const InputDecoration(
                labelText: 'Account',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final a in accounts)
                  DropdownMenuItem(value: a.id, child: Text(a.name)),
              ],
              onChanged: (v) => setState(() => _accountId = v),
            ),
            const SizedBox(height: WebInsets.md),
            DropdownButtonFormField<String>(
              initialValue: _categoryId,
              decoration: const InputDecoration(
                labelText: 'Category (optional)',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('None')),
                for (final c in categories)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => _categoryId = v),
            ),
          ],
        ],
        const SizedBox(height: WebInsets.xl),
        FilledButton.icon(
          onPressed: _finish,
          icon: const Icon(Icons.check_circle_outline),
          label: Text(_logToLedger && _canLog ? 'Finish & log' : 'Finish trip'),
        ),
      ],
    );
  }
}
