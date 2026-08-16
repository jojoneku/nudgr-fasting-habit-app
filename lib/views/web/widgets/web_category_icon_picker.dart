import 'package:flutter/material.dart';

import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/utils/category_icon_catalog.dart';
import '../design/web_breakpoints.dart';

/// Desktop counterpart of the mobile category-icon picker. Same catalog, same
/// "Auto" sentinel, so an icon chosen on either platform reads identically in
/// the other — the web forms previously hard-coded [kAutoCategoryIconKey] with
/// no way to pick anything else.
///
/// Returns the chosen catalog key, [kAutoCategoryIconKey] for the name-derived
/// glyph, or null if dismissed.
Future<String?> showWebCategoryIconPicker(
  BuildContext context, {
  required String current,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _WebCategoryIconPickerDialog(current: current),
  );
}

class _WebCategoryIconPickerDialog extends StatelessWidget {
  final String current;

  const _WebCategoryIconPickerDialog({required this.current});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // Anything outside the catalog is the auto sentinel or legacy free-text —
    // both render via the name heuristic, so both highlight "Auto".
    final autoSelected = !kCategoryIconCatalog.containsKey(current);

    return AlertDialog(
      title: const Text('Choose an icon'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _IconChoice(
                icon: Icons.auto_awesome_rounded,
                label: 'Auto',
                selected: autoSelected,
                onTap: () => Navigator.of(context).pop(kAutoCategoryIconKey),
              ),
              for (final group in kCategoryIconGroups) ...[
                const SizedBox(height: WebInsets.lg),
                Text(
                  group.label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: WebInsets.sm),
                Wrap(
                  spacing: WebInsets.sm,
                  runSpacing: WebInsets.sm,
                  children: [
                    for (final key in group.keys)
                      _IconChoice(
                        icon: kCategoryIconCatalog[key]!,
                        selected: key == current,
                        onTap: () => Navigator.of(context).pop(key),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _IconChoice extends StatelessWidget {
  final IconData icon;
  final String? label;
  final bool selected;
  final VoidCallback onTap;

  const _IconChoice({
    required this.icon,
    required this.selected,
    required this.onTap,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        // 44px minimum touch target, same as every other control.
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        padding: EdgeInsets.symmetric(
          horizontal: label == null ? WebInsets.md : WebInsets.lg,
          vertical: WebInsets.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 22, color: selected ? cs.primary : cs.onSurface),
            if (label != null) ...[
              const SizedBox(width: WebInsets.sm),
              Text(
                label!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: selected ? cs.primary : cs.onSurface,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The badge shown next to a category name field — tapping it opens the picker.
/// Mirrors the mobile preview: a real catalog icon when one is picked, else the
/// name-derived glyph or monogram, so the preview matches what the ledger feed
/// will render.
class WebCategoryIconPreview extends StatelessWidget {
  final String iconKey;
  final String? name;
  final CategoryType type;
  final VoidCallback onTap;

  /// Box edge. Defaults to the 48px form-field size; the Setup table passes a
  /// compact 32 so the row height doesn't grow.
  final double size;

  const WebCategoryIconPreview({
    super.key,
    required this.iconKey,
    required this.name,
    required this.type,
    required this.onTap,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final badge = resolveCategoryBadge(iconKey, name, type);
    final radius = size >= 40 ? 10.0 : 8.0;

    return Tooltip(
      message: 'Choose category icon',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: badge.icon != null
              ? Icon(badge.icon, size: size * 0.46, color: cs.onSurface)
              : Text(
                  badge.monogram!,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
        ),
      ),
    );
  }
}
