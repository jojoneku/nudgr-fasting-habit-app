import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/grocery/item_unit.dart';
import 'package:intermittent_fasting/models/grocery/remembered_price.dart';
import 'package:intermittent_fasting/presenters/grocery_cart_presenter.dart';
import 'package:intermittent_fasting/utils/app_spacing.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// Add-item form for the grocery cart. Leaving the price blank lets the cart
/// auto-fill it from price memory (if the item was bought before) or flag it as
/// unpriced. Entering a price confirms it and teaches the memory.
class AddCartItemSheet extends StatefulWidget {
  final GroceryCartPresenter presenter;

  const AddCartItemSheet({super.key, required this.presenter});

  @override
  State<AddCartItemSheet> createState() => _AddCartItemSheetState();
}

class _AddCartItemSheetState extends State<AddCartItemSheet> {
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');
  ItemUnit _unit = ItemUnit.piece;
  RememberedPrice? _remembered;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _qtyController.dispose();
    super.dispose();
  }

  void _onNameChanged(String value) {
    final match = widget.presenter.lookup(name: value);
    if (match?.key != _remembered?.key) {
      setState(() {
        _remembered = match;
        // Pre-select the unit we last used for this item.
        if (match != null) _unit = match.unit;
      });
    }
  }

  bool get _canSubmit => _nameController.text.trim().isNotEmpty;

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final qty = double.tryParse(_qtyController.text.trim());
    final price = double.tryParse(_priceController.text.trim());
    await widget.presenter.addItem(
      name: name,
      quantity: (qty == null || qty <= 0) ? 1 : qty,
      unitPrice: price,
      unit: _unit,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hint = _remembered;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          controller: _nameController,
          label: 'Item name',
          hint: 'e.g. Bear Brand 320g',
          autofocus: true,
          textInputAction: TextInputAction.next,
          onChanged: _onNameChanged,
        ),
        if (hint != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Icon(Icons.history, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Last paid ${formatPeso(hint.lastPrice)} ${hint.unit.priceSuffix}'
                  ' — leave price blank to use this estimate',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.primary),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Text('Unit', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            for (final u in ItemUnit.values)
              ChoiceChip(
                label: Text(u.label),
                selected: _unit == u,
                onSelected: (_) => setState(() => _unit = u),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: AppTextField(
                controller: _qtyController,
                label: 'Quantity',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: AppTextField(
                controller: _priceController,
                label: 'Price (optional)',
                hint: 'per ${_unit.label}',
                prefix: const Text('₱ '),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        AppPrimaryButton(
          label: 'Add to cart',
          leading: Icons.add_shopping_cart,
          onPressed: _canSubmit ? _submit : null,
        ),
      ],
    );
  }
}
