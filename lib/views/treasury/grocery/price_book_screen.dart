import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/grocery/item_unit.dart';
import 'package:intermittent_fasting/models/grocery/remembered_price.dart';
import 'package:intermittent_fasting/presenters/grocery_cart_presenter.dart';
import 'package:intermittent_fasting/utils/amount_input_formatter.dart';
import 'package:intermittent_fasting/utils/app_spacing.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

final _lastSeenFmt = DateFormat('MMM d, yyyy');

/// The price book — every price the user has built up, in one browsable place.
///
/// Until now prices could only be *taught* as a side effect of shopping: add an
/// item, type a price, and the cart remembers it. That makes the memory
/// invisible and un-editable. This screen is the direct surface: see the whole
/// list, search it, correct a price that changed, add one straight off a
/// receipt without pretending to shop, or drop an item you no longer buy.
class PriceBookScreen extends StatefulWidget {
  final GroceryCartPresenter presenter;

  const PriceBookScreen({super.key, required this.presenter});

  @override
  State<PriceBookScreen> createState() => _PriceBookScreenState();
}

class _PriceBookScreenState extends State<PriceBookScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showEditor({RememberedPrice? existing}) async {
    await AppBottomSheet.show(
      context: context,
      title: existing == null ? 'Add a price' : 'Edit price',
      body: PriceBookEntrySheet(
        presenter: widget.presenter,
        existing: existing,
      ),
    );
  }

  Future<void> _confirmDelete(RememberedPrice entry) async {
    final ok = await AppConfirmDialog.confirm(
      context: context,
      title: 'Forget ${entry.displayName}?',
      body: 'Removes it from your price book. Items already in the cart keep '
          'the price they were added with.',
      confirmLabel: 'Forget',
      isDestructive: true,
    );
    if (ok) await widget.presenter.deletePriceBookEntry(entry.key);
  }

  Future<void> _addToCart(RememberedPrice entry) async {
    // No price passed — the cart re-prices it from this very entry and flags it
    // as an estimate, which is what an un-checked shelf price is.
    await widget.presenter.addItem(
      name: entry.displayName,
      unit: entry.unit,
      barcode: entry.barcode,
    );
    if (!mounted) return;
    AppToast.show(context, '${entry.displayName} added to cart');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.presenter,
      builder: (context, _) {
        // Search reuses the cart's typeahead ranking, so "bear" or a typo finds
        // the same rows here that it would in the add-item sheet.
        final entries = _query.trim().isEmpty
            ? widget.presenter.priceMemory
            : widget.presenter.suggestions(_query, limit: 100);

        return AppPageScaffold(
          title: 'Price book',
          padding: EdgeInsets.zero,
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showEditor(),
            icon: const Icon(Icons.add),
            label: const Text('Add price'),
          ),
          body: Column(
            children: [
              _PriceBookHeader(presenter: widget.presenter),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
                child: AppTextField(
                  controller: _searchController,
                  hint: 'Search your prices',
                  prefixIcon: Icons.search,
                  suffixIcon: _query.isEmpty ? null : Icons.close,
                  onSuffixIconTap: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: entries.isEmpty
                    ? _EmptyPriceBook(
                        isSearching: _query.trim().isNotEmpty,
                        onAdd: () => _showEditor(),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                            AppSpacing.md, 0, AppSpacing.md, 96),
                        itemCount: entries.length,
                        itemBuilder: (context, i) => _PriceRow(
                          entry: entries[i],
                          onEdit: () => _showEditor(existing: entries[i]),
                          onDelete: () => _confirmDelete(entries[i]),
                          onAddToCart: () => _addToCart(entries[i]),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PriceBookHeader extends StatelessWidget {
  final GroceryCartPresenter presenter;

  const _PriceBookHeader({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
      child: Text(
        presenter.priceBookSummary,
        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  final RememberedPrice entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAddToCart;

  const _PriceRow({
    required this.entry,
    required this.onEdit,
    required this.onDelete,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Dismissible(
      key: ValueKey(entry.key),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        return false; // the confirm dialog owns the removal
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.lg),
        color: cs.errorContainer,
        child: Icon(Icons.delete_outline, color: cs.onErrorContainer),
      ),
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.displayName,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'bought ${entry.timesSeen}× · last seen '
                      '${_lastSeenFmt.format(entry.lastSeen)}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatPeso(entry.lastPrice),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: context.appColors.fast,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    entry.unit.priceSuffix,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              SizedBox(
                width: 44,
                height: 44,
                child: IconButton(
                  tooltip: 'Add to cart',
                  onPressed: onAddToCart,
                  icon: const Icon(Icons.add_shopping_cart, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyPriceBook extends StatelessWidget {
  final bool isSearching;
  final VoidCallback onAdd;

  const _EmptyPriceBook({required this.isSearching, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    if (isSearching) {
      return const AppEmptyState(
        icon: Icons.search_off,
        title: 'No match',
        body: 'Nothing in your price book matches that.',
      );
    }
    return AppEmptyState(
      icon: Icons.receipt_long_outlined,
      title: 'No prices yet',
      body: 'Add prices here straight off a receipt, or let them build up '
          'as you confirm prices while shopping.',
      actionLabel: 'Add a price',
      onAction: onAdd,
    );
  }
}

// ── Add / edit sheet ─────────────────────────────────────────────────────────

/// Create or correct a single price-book entry. Nothing here touches the cart —
/// this is the price memory itself.
class PriceBookEntrySheet extends StatefulWidget {
  final GroceryCartPresenter presenter;

  /// Null for a new entry; otherwise the row being corrected.
  final RememberedPrice? existing;

  const PriceBookEntrySheet({
    super.key,
    required this.presenter,
    this.existing,
  });

  @override
  State<PriceBookEntrySheet> createState() => _PriceBookEntrySheetState();
}

class _PriceBookEntrySheetState extends State<PriceBookEntrySheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late ItemUnit _unit;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.displayName ?? '');
    _priceController = TextEditingController(
        text: e == null ? '' : e.lastPrice.toStringAsFixed(2));
    _unit = e?.unit ?? ItemUnit.piece;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _nameController.text.trim().isNotEmpty &&
      (double.tryParse(_priceController.text.trim()) ?? -1) >= 0;

  Future<void> _save() async {
    final price = double.tryParse(_priceController.text.trim());
    if (price == null) return;
    await widget.presenter.savePriceBookEntry(
      name: _nameController.text,
      price: price,
      unit: _unit,
      barcode: widget.existing?.barcode,
      replacingKey: widget.existing?.key,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: _nameController,
          label: 'Item name',
          hint: 'e.g. Bear Brand 320g',
          autofocus: widget.existing == null,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Unit', style: Theme.of(context).textTheme.labelLarge),
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
        AppTextField(
          controller: _priceController,
          label: 'Price ${_unit.priceSuffix}',
          prefix: const Text('₱ '),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: amountInputFormatters,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _canSave ? _save() : null,
        ),
        const SizedBox(height: AppSpacing.lg),
        AppPrimaryButton(
          label: widget.existing == null ? 'Save price' : 'Update price',
          leading: Icons.check,
          onPressed: _canSave ? _save : null,
        ),
      ],
    );
  }
}
