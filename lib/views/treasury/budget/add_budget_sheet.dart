import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/budget_group_def.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/utils/amount_input_formatter.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/shared/sheet_fields.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class AddBudgetSheet extends StatefulWidget {
  final BudgetPresenter presenter;
  final String? preselectedCategoryId;

  const AddBudgetSheet(
      {super.key, required this.presenter, this.preselectedCategoryId});

  @override
  State<AddBudgetSheet> createState() => _AddBudgetSheetState();
}

class _AddBudgetSheetState extends State<AddBudgetSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();

  String? _selectedCategoryId;
  String _groupId = BudgetGroupDef.idNonNegotiables;
  BudgetType _budgetType = BudgetType.variable;
  bool _isSubmitting = false;

  static const _newCategorySentinel = '__new_category__';

  @override
  void initState() {
    super.initState();
    _selectedCategoryId = widget.preselectedCategoryId;
    if (_selectedCategoryId != null) {
      final existing = widget.presenter.budgetFor(_selectedCategoryId!);
      if (existing != null) {
        _amountController.text = existing.allocatedAmount.toStringAsFixed(2);
        _groupId = existing.group;
        _budgetType = existing.budgetType;
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  bool get _isSavings => _groupId == BudgetGroupDef.idSavings;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null) {
      AppToast.error(context, 'Select a category');
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final amount = double.parse(_amountController.text.replaceAll(',', ''));
      await widget.presenter.setBudget(
        _selectedCategoryId!,
        amount,
        group: _groupId,
        budgetType: _budgetType,
      );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  bool get _isEdit =>
      _selectedCategoryId != null &&
      widget.presenter.budgetFor(_selectedCategoryId!) != null;

  Future<FinanceCategory?> _showCreateCategoryDialog(
      BuildContext context) async {
    final nameCtrl = TextEditingController();
    final existing = widget.presenter.expenseCategories;
    final colorHex = categoryColorAt(existing.length, isExpense: true);
    final cat = await showDialog<FinanceCategory>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Expense Category'),
        content: LabeledField(
          label: 'Category name',
          child: TextField(
            controller: nameCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(
                ctx,
                FinanceCategory(
                  id: '${DateTime.now().microsecondsSinceEpoch}_'
                      '${Random().nextInt(9999)}',
                  name: name,
                  type: CategoryType.expense,
                  icon: 'tag',
                  colorHex: colorHex,
                ),
              );
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    return cat;
  }

  Future<void> _createCategory() async {
    final newCat = await _showCreateCategoryDialog(context);
    if (newCat != null) {
      await widget.presenter.addCategory(newCat);
      if (mounted) setState(() => _selectedCategoryId = newCat.id);
    }
  }

  /// The label shown in the target picker box for the current selection.
  String get _selectedTargetName {
    final id = _selectedCategoryId;
    if (id == null) return '';
    if (_isSavings) {
      final a =
          widget.presenter.savingsTargets.where((x) => x.id == id).firstOrNull;
      return a != null ? _savingsAccountLabel(a) : '';
    }
    final c =
        widget.presenter.expenseCategories.where((x) => x.id == id).firstOrNull;
    return c?.name ?? '';
  }

  Future<void> _pickTarget() async {
    if (_isSavings) {
      final targets = widget.presenter.savingsTargets;
      final picked = await _showTargetPicker(
        title: 'Savings / Goal account',
        rows: [for (final a in targets) (_savingsAccountLabel(a), a.id)],
      );
      if (picked != null) setState(() => _selectedCategoryId = picked);
    } else {
      final cats = widget.presenter.expenseCategories;
      final picked = await _showTargetPicker(
        title: 'Category',
        rows: [for (final c in cats) (c.name, c.id)],
        newLabel: 'New category…',
      );
      if (picked == _newCategorySentinel) {
        await _createCategory();
      } else if (picked != null) {
        setState(() => _selectedCategoryId = picked);
      }
    }
  }

  /// A bottom-sheet single-select list matching the reference picker. Returns
  /// the chosen id, [_newCategorySentinel] for the optional "new" row, or null.
  Future<String?> _showTargetPicker({
    required String title,
    required List<(String, String)> rows,
    String? newLabel,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(title,
                      style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                ),
                if (newLabel != null)
                  _TargetPickerRow(
                    leading:
                        Icon(Icons.add_rounded, size: 20, color: cs.primary),
                    label: newLabel,
                    selected: false,
                    onTap: () => Navigator.of(ctx).pop(_newCategorySentinel),
                  ),
                for (final (label, id) in rows)
                  _TargetPickerRow(
                    leading: Icon(Icons.sell_outlined,
                        size: 18, color: cs.onSurfaceVariant),
                    label: label,
                    selected: id == _selectedCategoryId,
                    onTap: () => Navigator.of(ctx).pop(id),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final expenseCategories = widget.presenter.expenseCategories;
    final savingsTargets = widget.presenter.savingsTargets;
    final isPreselected = widget.preselectedCategoryId != null;
    final targetName = _selectedTargetName;
    final accent = Theme.of(context).colorScheme.primary;

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Category / account target
            if (isPreselected) ...[
              SheetFieldLabel(_isSavings ? 'Account' : 'Category'),
              SheetPickerBox(
                trailingIcon: Icons.lock_outline_rounded,
                child: Text(
                  targetName.isEmpty ? '—' : targetName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ] else if (_isSavings && savingsTargets.isEmpty) ...[
              _NoSavingsHint(),
            ] else if (!_isSavings && expenseCategories.isEmpty) ...[
              _NoCategoriesHint(onAdd: _createCategory),
            ] else ...[
              SheetFieldLabel(
                  _isSavings ? 'Savings / Goal account' : 'Category'),
              SheetPickerBox(
                onTap: _pickTarget,
                child: Text(
                  targetName.isEmpty
                      ? (_isSavings ? 'Select account' : 'Select category')
                      : targetName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: targetName.isEmpty
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : Theme.of(context).colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),

            // Budget amount (emphasized field)
            SheetFieldLabel('Budget amount'),
            TextFormField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: amountInputFormatters,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
              decoration: sheetFieldDecoration(
                context,
                hint: '0.00',
                prefixText: '₱ ',
                emphasize: true,
              ),
              validator: (v) {
                final p = double.tryParse(v ?? '');
                if (p == null || p <= 0) return 'Must be > 0';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Budget group
            SheetFieldLabel('Budget group'),
            SheetSegmentedToggle<String>(
              value: _groupId,
              onChanged: (gId) {
                // Switching between expense ↔ savings invalidates the picked
                // id since categories and accounts share the same `categoryId`
                // slot but draw from different lists.
                final newIsSavings = gId == BudgetGroupDef.idSavings;
                final crossing = newIsSavings != _isSavings;
                setState(() {
                  _groupId = gId;
                  if (crossing) _selectedCategoryId = null;
                });
              },
              segments: [
                for (final g in widget.presenter.groups)
                  SheetSegment(label: g.name, value: g.id, accent: accent),
              ],
            ),
            const SizedBox(height: 20),

            // Save button
            AppPrimaryButton(
              label: _isEdit ? 'Save Budget' : 'Set Budget',
              onPressed: _isSubmitting ? null : _submit,
              isLoading: _isSubmitting,
            ),

            // Remove budget button (edit only)
            if (_isEdit) ...[
              const SizedBox(height: 8),
              AppDestructiveButton(
                label: 'Remove Budget',
                onPressed: _isSubmitting
                    ? null
                    : () async {
                        await widget.presenter
                            .removeBudget(_selectedCategoryId!);
                        if (context.mounted) Navigator.pop(context);
                      },
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

String _savingsAccountLabel(FinancialAccount a) {
  if (a.category == AccountCategory.goal && a.goalTarget != null) {
    return '${a.name}  ·  goal ${formatPesoCompact(a.goalTarget!)}';
  }
  return a.name;
}

class _TargetPickerRow extends StatelessWidget {
  final Widget leading;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TargetPickerRow({
    required this.leading,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
            ),
            if (selected)
              Icon(Icons.check_rounded, size: 20, color: cs.primary),
          ],
        ),
      ),
    );
  }
}

class _NoSavingsHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppCard(
      variant: AppCardVariant.outlined,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: cs.onSurfaceVariant, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'No savings or goal accounts yet — add one in the Dashboard first.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoCategoriesHint extends StatelessWidget {
  final VoidCallback onAdd;

  const _NoCategoriesHint({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppCard(
      variant: AppCardVariant.outlined,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: cs.onSurfaceVariant, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'No expense categories yet.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: onAdd,
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
