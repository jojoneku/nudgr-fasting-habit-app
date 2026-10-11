import 'dart:math';

import 'package:flutter/material.dart';

import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/category_icon_catalog.dart';
import '../../widgets/web_widgets.dart';
import 'web_budget_shared.dart';

/// The v2 "New category" dialog (Forms canvas, "Budget and History"): name,
/// Expense/Income type, a colour swatch row, an icon row with Auto and the
/// full picker behind "More…", and the exclude-from-totals switch.
///
/// Opens from the Budget draft row's "＋ New category…" (type fixed to
/// expense, since only expense categories can carry a budget) and, in a later
/// phase, from Setup › Categories with the type selectable. Returns the new
/// [FinanceCategory] — not yet saved; the caller hands it to its presenter.
Future<FinanceCategory?> showWebNewCategoryDialog(
  BuildContext context, {
  required List<FinanceCategory> existing,
  CategoryType initialType = CategoryType.expense,
  bool allowTypeChange = true,
}) {
  return showWebDialog<FinanceCategory>(
    context,
    builder: (_) => _WebNewCategoryDialog(
      existing: existing,
      initialType: initialType,
      allowTypeChange: allowTypeChange,
    ),
  );
}

/// The icons offered inline before "More…" opens the full catalog — one per
/// everyday spending shape, so most categories never need the picker.
const List<String> _kQuickIconKeys = [
  'food',
  'grocery',
  'car',
  'home',
  'bolt',
  'shopping',
  'gift',
  'health',
  'pet',
  'education',
];

class _WebNewCategoryDialog extends StatefulWidget {
  final List<FinanceCategory> existing;
  final CategoryType initialType;
  final bool allowTypeChange;

  const _WebNewCategoryDialog({
    required this.existing,
    required this.initialType,
    required this.allowTypeChange,
  });

  @override
  State<_WebNewCategoryDialog> createState() => _WebNewCategoryDialogState();
}

class _WebNewCategoryDialogState extends State<_WebNewCategoryDialog> {
  final _nameCtrl = TextEditingController();
  late CategoryType _type = widget.initialType;
  late String _colorHex = _defaultColor(_type);
  // Starts on "Auto" (the name-derived glyph) — the historical default, so a
  // category created without touching the icon row looks as it always did.
  String _iconKey = kAutoCategoryIconKey;
  bool _exclude = false;
  bool _nameMissing = false;

  bool get _isExpense => _type == CategoryType.expense;

  String _defaultColor(CategoryType type) {
    final count = widget.existing.where((c) => c.type == type).length;
    return categoryColorAt(count, isExpense: type == CategoryType.expense);
  }

  List<String> get _palette => _isExpense ? kExpensePalette : kIncomePalette;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _setType(CategoryType t) {
    if (t == _type) return;
    final wasDefault = _colorHex == _defaultColor(_type);
    setState(() {
      _type = t;
      // Follow the type's palette unless the user already chose a colour.
      if (wasDefault) _colorHex = _defaultColor(t);
    });
  }

  Future<void> _pickMoreIcons() async {
    final picked = await showWebCategoryIconPicker(context, current: _iconKey);
    if (picked != null && mounted) setState(() => _iconKey = picked);
  }

  void _create() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _nameMissing = true);
      return;
    }
    Navigator.of(context).pop(FinanceCategory(
      id: '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}',
      name: name,
      type: _type,
      icon: _iconKey,
      colorHex: _colorHex,
      excludeFromTotals: _exclude,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return WebDialog(
      title: _isExpense ? 'New expense category' : 'New income category',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: WebField(
                  label: 'Name',
                  error: _nameMissing ? 'Give the category a name.' : null,
                  child: WebInput(
                    key: WebBudgetKeys.newCategoryName,
                    controller: _nameCtrl,
                    autofocus: true,
                    hint: 'Pet care',
                    error: _nameMissing,
                    textInputAction: TextInputAction.done,
                    // Rebuild so the auto-glyph preview tracks the typed
                    // name live, the way the mobile add-form does.
                    onChanged: (_) => setState(() => _nameMissing = false),
                    onSubmitted: (_) => _create(),
                  ),
                ),
              ),
              if (widget.allowTypeChange) ...[
                const SizedBox(width: WebInsets.md),
                Expanded(
                  flex: 2,
                  child: WebField(
                    label: 'Type',
                    child: SizedBox(
                      height: kWebInputHeight,
                      child: WebSegmented<CategoryType>(
                        key: WebBudgetKeys.newCategoryType,
                        value: _type,
                        onChanged: _setType,
                        segments: const [
                          WebSegment(CategoryType.expense, 'Expense',
                              tone: WebSegmentTone.warning),
                          WebSegment(CategoryType.income, 'Income',
                              tone: WebSegmentTone.success),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: WebInsets.lg),
          WebField(
            label: 'Color',
            child: Wrap(
              key: WebBudgetKeys.newCategoryColor,
              spacing: WebInsets.sm,
              runSpacing: WebInsets.sm,
              children: [
                for (final hex in _palette)
                  _Swatch(
                    color:
                        resolveSliceColor(hex, 0, brightness: theme.brightness),
                    selected: hex == _colorHex,
                    onTap: () => setState(() => _colorHex = hex),
                  ),
              ],
            ),
          ),
          const SizedBox(height: WebInsets.lg),
          WebField(
            label: 'Icon',
            helper: 'Auto picks one from the name.',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WebCategoryIconPreview(
                  iconKey: _iconKey,
                  name: _nameCtrl.text,
                  type: _type,
                  size: kWebInputHeight,
                  onTap: _pickMoreIcons,
                ),
                const SizedBox(width: WebInsets.md),
                Expanded(
                  child: Wrap(
                    key: WebBudgetKeys.newCategoryIcon,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _IconTile(
                        icon: Icons.auto_awesome_rounded,
                        label: 'Auto',
                        selected: !kCategoryIconCatalog.containsKey(_iconKey),
                        onTap: () =>
                            setState(() => _iconKey = kAutoCategoryIconKey),
                      ),
                      for (final key in _kQuickIconKeys)
                        if (kCategoryIconCatalog.containsKey(key))
                          _IconTile(
                            icon: kCategoryIconCatalog[key]!,
                            selected: key == _iconKey,
                            onTap: () => setState(() => _iconKey = key),
                          ),
                      _IconTile(
                        key: WebBudgetKeys.newCategoryIconMore,
                        icon: Icons.more_horiz_rounded,
                        label: 'More…',
                        selected: false,
                        onTap: _pickMoreIcons,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: WebInsets.lg),
          WebSwitchRow(
            key: WebBudgetKeys.newCategoryExclude,
            title: 'Exclude from spending totals',
            subtitle: 'For transfers, fees, reimbursements',
            value: _exclude,
            onChanged: (v) => setState(() => _exclude = v),
          ),
        ],
      ),
      secondary: TextButton(
        key: WebBudgetKeys.newCategoryCancel,
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      primary: FilledButton(
        key: WebBudgetKeys.newCategoryCreate,
        onPressed: _create,
        style: FilledButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
        ),
        child: const Text('Create'),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        // 44 px hit area around a 26 px swatch.
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: selected ? 28 : 24,
              height: selected ? 28 : 24,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? cs.onSurface : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  final IconData icon;
  final String? label;
  final bool selected;
  final VoidCallback onTap;

  const _IconTile({
    super.key,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final muted = context.appColors.textMuted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        padding: EdgeInsets.symmetric(
          horizontal: label == null ? WebInsets.sm : WebInsets.md,
        ),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: selected ? cs.primary : cs.onSurface),
            if (label != null) ...[
              const SizedBox(width: 6),
              Text(
                label!,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected ? cs.primary : muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
