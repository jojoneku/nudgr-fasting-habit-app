import 'package:flutter/material.dart';
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
  double _quantity = 1;
  RememberedPrice? _remembered;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _onNameChanged(String value) {
    final match = widget.presenter.lookup(name: value);
    if (match?.key != _remembered?.key) {
      setState(() => _remembered = match);
    }
  }

  bool get _canSubmit => _nameController.text.trim().isNotEmpty;

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final price = double.tryParse(_priceController.text.trim());
    await widget.presenter.addItem(
      name: name,
      quantity: _quantity,
      unitPrice: price,
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
                  'Last paid ${formatPeso(hint.lastPrice)} — leave price blank '
                  'to use this estimate',
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
        Row(
          children: [
            Text('Quantity', style: Theme.of(context).textTheme.bodyLarge),
            const Spacer(),
            _QuantityStepper(
              quantity: _quantity,
              onChanged: (q) => setState(() => _quantity = q),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          controller: _priceController,
          label: 'Unit price (optional)',
          hint: hint != null
              ? 'Blank → ${formatPeso(hint.lastPrice)} estimate'
              : 'Blank → added as unpriced',
          prefix: const Text('₱ '),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
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

/// Reusable −/+ stepper for quantities. Touch targets are full IconButton size
/// (≥48px) to satisfy the 44px minimum.
class _QuantityStepper extends StatelessWidget {
  final double quantity;
  final ValueChanged<double> onChanged;

  const _QuantityStepper({required this.quantity, required this.onChanged});

  String get _label => quantity == quantity.truncateToDouble()
      ? quantity.toInt().toString()
      : quantity.toString();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          onPressed: quantity > 1 ? () => onChanged(quantity - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        Container(
          constraints: const BoxConstraints(minWidth: 44),
          alignment: Alignment.center,
          child: Text(
            _label,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: cs.onSurface),
          ),
        ),
        IconButton.filledTonal(
          onPressed: () => onChanged(quantity + 1),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}
