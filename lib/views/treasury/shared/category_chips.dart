import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/utils/app_radii.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/category_icon_catalog.dart';
import 'package:intermittent_fasting/views/treasury/shared/category_badge_widget.dart';
import 'package:intermittent_fasting/views/treasury/shared/sheet_fields.dart';

/// A wrap of category pills, each tinted with the category's OWN color and icon
/// so the picker reads like the categories the user created — not a row of dark
/// theme chips. Selecting fills the pill more strongly and thickens its border.
/// Shared by the ledger / bill / budgeted-expense / receivable sheets.
class CategoryChoiceChips extends StatelessWidget {
  final List<FinanceCategory> categories;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  /// Caps the pill area to roughly this height (≈3 rows). Invisible for a small
  /// number of categories — the box just takes its natural height — and only
  /// kicks in as a bounded internal scroll once the pills exceed it, so a long
  /// category list never pushes the rest of the form (and Save) off-screen.
  final double maxHeight;

  const CategoryChoiceChips({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelected,
    this.maxHeight = 148,
  });

  @override
  Widget build(BuildContext context) {
    final wrap = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < categories.length; i++)
          _CategoryPill(
            category: categories[i],
            index: i,
            selected: categories[i].id == selectedId,
            onTap: () => onSelected(categories[i].id),
          ),
      ],
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        // A clipped final row is the scroll affordance; short lists don't scroll.
        child: wrap,
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  final FinanceCategory category;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryPill({
    required this.category,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // The category's own color (white-default fallback + light-mode deepening
    // handled by resolveSliceColor), so each pill carries its identity.
    final color = resolveSliceColor(
      category.colorHex,
      index,
      brightness: Theme.of(context).brightness,
    );
    final spec =
        resolveCategoryBadge(category.icon, category.name, category.type);

    return Semantics(
      button: true,
      selected: selected,
      label: category.name,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.smBorder,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              // Blend the tint over the sheet surface so it reads as a colored
              // fill, not a near-black translucent one on the dark sheet.
              color: Color.alphaBlend(
                color.withValues(alpha: selected ? 0.38 : 0.20),
                cs.surface,
              ),
              borderRadius: AppRadii.smBorder,
              border: Border.all(
                color: selected ? color : color.withValues(alpha: 0.6),
                width: selected ? 1.6 : 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (spec.icon != null)
                  Icon(spec.icon, size: 16, color: color)
                else
                  Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                const SizedBox(width: 7),
                Text(
                  category.name,
                  // Always the category color so the pill reads as colored
                  // (never grey/black); weight rises when selected.
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Result of [showCategoryPicker]. A null future means "dismissed / no change";
/// a [CategoryChoice] with a null [id] means the "None" option was chosen.
class CategoryChoice {
  final String? id;
  const CategoryChoice(this.id);
}

/// A bottom sheet of colored category pills (+ an optional "None" row). Reused
/// by [CategoryPickerField] so a category is chosen the same way everywhere.
Future<CategoryChoice?> showCategoryPicker(
  BuildContext context, {
  required List<FinanceCategory> categories,
  String? selectedId,
  bool allowNone = true,
  String noneLabel = 'None',
}) {
  final cs = Theme.of(context).colorScheme;
  return showModalBottomSheet<CategoryChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetHandle(),
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: SheetTitle('Category'),
              ),
              if (allowNone)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: () =>
                        Navigator.of(ctx).pop(const CategoryChoice(null)),
                    borderRadius: AppRadii.smBorder,
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: AppRadii.smBorder,
                        border: Border.all(
                          color: selectedId == null
                              ? cs.primary
                              : cs.outlineVariant.withValues(alpha: 0.6),
                          width: selectedId == null ? 1.6 : 1.2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.block_rounded,
                              size: 16, color: cs.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Text(noneLabel,
                              style: TextStyle(
                                  color: cs.onSurface,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
              CategoryChoiceChips(
                categories: categories,
                selectedId: selectedId,
                // Pop with the chosen id (tapping a pill = commit).
                onSelected: (id) => Navigator.of(ctx).pop(CategoryChoice(id)),
                maxHeight: 320,
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// A compact category "field box" (color dot + name, or a placeholder) that
/// opens [showCategoryPicker]. Mirrors the account field so Category and Account
/// read as the same kind of form control (per the reference layout).
class CategoryPickerField extends StatelessWidget {
  final List<FinanceCategory> categories;
  final String? selectedId;

  /// Fires with the chosen category id, or null when "None" is picked.
  final ValueChanged<String?> onChanged;
  final String placeholder;

  const CategoryPickerField({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onChanged,
    this.placeholder = 'Select category',
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final idx = categories.indexWhere((c) => c.id == selectedId);
    final selected = idx < 0 ? null : categories[idx];

    return SheetPickerBox(
      onTap: () async {
        final choice = await showCategoryPicker(
          context,
          categories: categories,
          selectedId: selectedId,
        );
        if (choice != null) onChanged(choice.id);
      },
      child: selected == null
          ? Text(
              placeholder,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            )
          : Row(
              children: [
                CategoryBadge(
                  iconKey: selected.icon,
                  name: selected.name,
                  type: selected.type,
                  color: resolveSliceColor(selected.colorHex, idx,
                      brightness: Theme.of(context).brightness),
                  size: 24,
                  iconSize: 14,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    selected.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
    );
  }
}
