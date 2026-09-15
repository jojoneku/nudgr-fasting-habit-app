import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/grocery/item_unit.dart';
import 'package:intermittent_fasting/models/grocery/remembered_price.dart';
import 'package:intermittent_fasting/presenters/grocery_cart_presenter.dart';
import 'package:intermittent_fasting/utils/amount_input_formatter.dart';
import 'package:intermittent_fasting/utils/app_radii.dart';
import 'package:intermittent_fasting/utils/app_spacing.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// Add-item form for the grocery cart.
///
/// As the name is typed, past items the user has priced before are offered as
/// suggestions with their last price — so "bear" surfaces both
/// "Bear Brand 1L · ₱92.00" and "Bear Brand powdered 240g · ₱128.00" and the
/// shopper can cross-check against the shelf before picking one.
///
/// Leaving the price blank lets the cart auto-fill it from price memory (if the
/// item was bought before) or flag it as unpriced. Entering a price confirms it
/// and teaches the memory.
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
  final _nameFocus = FocusNode();
  final _priceFocus = FocusNode();

  ItemUnit _unit = ItemUnit.piece;
  RememberedPrice? _remembered;
  List<RememberedPrice> _matches = const [];

  /// Suppressed right after a suggestion is tapped — otherwise the list would
  /// stay open over the item the user just chose.
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(_onNameFocusChanged);
    _priceFocus.addListener(_onPriceFocusChanged);
    // Pre-seed with the user's most-bought items so the list is useful before
    // the first keystroke.
    _matches = widget.presenter.suggestions('');
  }

  @override
  void dispose() {
    _nameFocus.removeListener(_onNameFocusChanged);
    _priceFocus.removeListener(_onPriceFocusChanged);
    _nameController.dispose();
    _priceController.dispose();
    _qtyController.dispose();
    _nameFocus.dispose();
    _priceFocus.dispose();
    super.dispose();
  }

  void _onNameFocusChanged() {
    if (_nameFocus.hasFocus) setState(() => _showSuggestions = true);
  }

  /// Moving on to the price means the name is settled — collapse the list so
  /// the rest of the form isn't pushed off-screen behind the keyboard.
  void _onPriceFocusChanged() {
    if (_priceFocus.hasFocus && _showSuggestions) {
      setState(() => _showSuggestions = false);
    }
  }

  void _onNameChanged(String value) {
    final match = widget.presenter.lookup(name: value);
    // Always rebuild so the submit button re-evaluates as the name is typed —
    // even for a brand-new item with no price-memory match.
    setState(() {
      _showSuggestions = true;
      _matches = widget.presenter.suggestions(value);
      if (match?.key != _remembered?.key) {
        _remembered = match;
        // Pre-select the unit we last used for this item.
        if (match != null) _unit = match.unit;
      }
    });
  }

  /// Fills the form from a tapped suggestion. The price is deliberately left
  /// blank: the cart then re-prices it from memory and marks it an *estimate*
  /// (`~`) rather than a price confirmed at the shelf. "Use this price" on the
  /// hint row is the one-tap way to confirm it instead.
  void _applySuggestion(RememberedPrice match) {
    setState(() {
      _nameController.text = match.displayName;
      _nameController.selection =
          TextSelection.collapsed(offset: match.displayName.length);
      _remembered = match;
      _unit = match.unit;
      _showSuggestions = false;
      _matches = widget.presenter.suggestions(match.displayName);
    });
    _priceFocus.requestFocus();
  }

  void _useRememberedPrice(RememberedPrice match) {
    setState(() {
      _priceController.text = match.lastPrice.toStringAsFixed(2);
    });
  }

  double get _quantity {
    final parsed = double.tryParse(_qtyController.text.trim());
    return (parsed == null || parsed <= 0) ? 1 : parsed;
  }

  void _stepQuantity(double delta) {
    final next = _quantity + delta;
    if (next <= 0) return;
    // Trim float noise from repeated 0.25 / 0.1 steps (1.7500000000000002).
    final rounded = (next * 100).roundToDouble() / 100;
    setState(() {
      _qtyController.text = rounded == rounded.truncateToDouble()
          ? rounded.toInt().toString()
          : rounded.toString();
    });
  }

  bool get _canSubmit => _nameController.text.trim().isNotEmpty;

  /// Adds the current item. When [keepOpen] the sheet stays up, the fields
  /// reset, and focus returns to the name — so a full grocery trip can be
  /// logged item-after-item without reopening the sheet each time.
  Future<void> _submit({bool keepOpen = false}) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final price = double.tryParse(_priceController.text.trim());
    await widget.presenter.addItem(
      name: name,
      quantity: _quantity,
      unitPrice: price,
      unit: _unit,
    );
    if (!mounted) return;
    if (keepOpen) {
      setState(() {
        _nameController.clear();
        _priceController.clear();
        _qtyController.text = '1';
        _remembered = null;
        _showSuggestions = true;
        _matches = widget.presenter.suggestions('');
        // Keep the unit — successive items in a trip often share it.
      });
      _nameFocus.requestFocus();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hint = _remembered;
    final typed = _nameController.text.trim();
    final suggestionsVisible = _showSuggestions && _matches.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  controller: _nameController,
                  focusNode: _nameFocus,
                  label: 'Item name',
                  hint: 'e.g. Bear Brand 320g',
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  onChanged: _onNameChanged,
                  suffixIcon: typed.isEmpty ? null : Icons.close,
                  onSuffixIconTap: () {
                    _nameController.clear();
                    _onNameChanged('');
                    _nameFocus.requestFocus();
                  },
                ),
                if (suggestionsVisible) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _SuggestionList(
                    matches: _matches,
                    query: typed,
                    onTap: _applySuggestion,
                  ),
                ],
                if (hint != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _RememberedHint(
                    match: hint,
                    onUsePrice: () => _useRememberedPrice(hint),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                const _FieldLabel(label: 'Unit'),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _QuantityField(
                        controller: _qtyController,
                        unit: _unit,
                        onStep: _stepQuantity,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: AppTextField(
                        controller: _priceController,
                        focusNode: _priceFocus,
                        label: 'Price (optional)',
                        hint: 'per ${_unit.label}',
                        prefix: const Text('₱ '),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: amountInputFormatters,
                        textInputAction: TextInputAction.done,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _submit(keepOpen: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  widget.presenter.addPreviewLabel(
                    quantity: _quantity,
                    unitPrice: double.tryParse(_priceController.text.trim()),
                    unit: _unit,
                    remembered: hint,
                  ),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: AppPrimaryButton(
                label: 'Add & next',
                leading: Icons.playlist_add,
                onPressed: _canSubmit ? () => _submit(keepOpen: true) : null,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: AppSecondaryButton(
                label: 'Add & close',
                leading: Icons.add_shopping_cart,
                onPressed: _canSubmit ? _submit : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Suggestions ──────────────────────────────────────────────────────────────

/// Past items matching what's typed, each with its last paid price so the
/// shopper can cross-check against the shelf tag before picking one.
class _SuggestionList extends StatelessWidget {
  final List<RememberedPrice> matches;
  final String query;
  final ValueChanged<RememberedPrice> onTap;

  const _SuggestionList({
    required this.matches,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(maxHeight: 216),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: AppRadii.mdBorder,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: matches.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          thickness: 1,
          color: cs.outlineVariant.withValues(alpha: 0.35),
        ),
        itemBuilder: (context, i) => _SuggestionTile(
          match: matches[i],
          query: query,
          isFirst: i == 0,
          isLast: i == matches.length - 1,
          onTap: () => onTap(matches[i]),
        ),
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final RememberedPrice match;
  final String query;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;

  const _SuggestionTile({
    required this.match,
    required this.query,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
  });

  /// Bolds the typed run inside the item name so the list is scannable while
  /// typing. Falls back to the plain name when the match was fuzzy and the
  /// query doesn't appear literally.
  TextSpan _highlighted(TextStyle? base, TextStyle? strong) {
    final name = match.displayName;
    final q = query.trim();
    final at = q.isEmpty ? -1 : name.toLowerCase().indexOf(q.toLowerCase());
    if (at < 0) return TextSpan(text: name, style: base);
    return TextSpan(style: base, children: [
      TextSpan(text: name.substring(0, at)),
      TextSpan(text: name.substring(at, at + q.length), style: strong),
      TextSpan(text: name.substring(at + q.length)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final blue = context.appColors.fast;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(isFirst ? AppRadii.md : 0),
        bottom: Radius.circular(isLast ? AppRadii.md : 0),
      ),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(Icons.history, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    _highlighted(
                      theme.textTheme.bodyMedium,
                      theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'bought ${match.timesSeen}×',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '${formatPeso(match.lastPrice)} ${match.unit.priceSuffix}',
              style: theme.textTheme.titleSmall?.copyWith(
                color: blue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Exact-match callout under the name field — the price that will auto-fill if
/// the price box is left blank, plus a one-tap way to confirm it instead.
class _RememberedHint extends StatelessWidget {
  final RememberedPrice match;
  final VoidCallback onUsePrice;

  const _RememberedHint({required this.match, required this.onUsePrice});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blue = context.appColors.fast;
    return Row(
      children: [
        Icon(Icons.history, size: 16, color: blue),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Last paid ${formatPeso(match.lastPrice)} ${match.unit.priceSuffix}'
            ' — leave price blank to use this estimate',
            style: theme.textTheme.bodySmall?.copyWith(color: blue),
          ),
        ),
        TextButton(
          onPressed: onUsePrice,
          child: const Text('Use it'),
        ),
      ],
    );
  }
}

// ── Quantity ─────────────────────────────────────────────────────────────────

/// Quantity box with −/+ buttons that step by the selected unit's natural
/// increment (1 pc, 0.25 kg, 50 g), matching the cart tiles' stepper.
class _QuantityField extends StatelessWidget {
  final TextEditingController controller;
  final ItemUnit unit;
  final ValueChanged<double> onStep;
  final ValueChanged<String> onChanged;

  const _QuantityField({
    required this.controller,
    required this.unit,
    required this.onStep,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final step = unit.step;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _FieldLabel(label: 'Quantity · ${unit.label}'),
        const SizedBox(height: 7),
        Row(
          children: [
            _StepButton(
              icon: Icons.remove,
              tooltip: 'Less',
              onPressed: () => onStep(-step),
            ),
            Expanded(
              child: AppTextField(
                controller: controller,
                textAlign: TextAlign.center,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                onChanged: onChanged,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            _StepButton(
              icon: Icons.add,
              tooltip: 'More',
              onPressed: () => onStep(step),
            ),
          ],
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 20),
        style: IconButton.styleFrom(
          foregroundColor: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Field caption matching [AppTextField]'s own label treatment, for the rows
/// that compose a field out of more than a single text box.
class _FieldLabel extends StatelessWidget {
  final String label;

  const _FieldLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    );
  }
}
