import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/utils/account_badge.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// The canonical account badge — a rounded tile showing either a chosen icon, a
/// name monogram, or the category default (see [resolveAccountBadge]). Used
/// everywhere an account is represented so all surfaces stay consistent.
class AccountBadge extends StatelessWidget {
  final AccountCategory category;
  final String name;

  /// The stored [FinancialAccount.icon] value (catalog key / monogram / default).
  final String iconKey;
  final String colorHex;
  final double size;

  const AccountBadge({
    super.key,
    required this.category,
    required this.name,
    required this.iconKey,
    required this.colorHex,
    this.size = 36,
  });

  /// Convenience: build from an existing account.
  factory AccountBadge.of(FinancialAccount account, {double size = 36}) =>
      AccountBadge(
        category: account.category,
        name: account.name,
        iconKey: account.icon,
        colorHex: account.colorHex,
        size: size,
      );

  Color _accent(BuildContext context) {
    try {
      return Color(int.parse('FF${colorHex.replaceFirst('#', '')}', radix: 16));
    } catch (_) {
      return Theme.of(context).colorScheme.tertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent(context);
    final spec =
        resolveAccountBadge(iconKey: iconKey, category: category, name: name);
    final f = size / 36; // scale factor (design sizes are tuned at 36px)

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: spec.solid ? accent : accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.30),
      ),
      child: spec.isMonogram
          ? Text(
              spec.monogram!,
              style: TextStyle(
                color: accountBadgeForeground(accent),
                fontWeight: FontWeight.w800,
                height: 1.0,
                letterSpacing: 0.2,
                fontSize: switch (spec.monogram!.length) {
                      >= 5 => 9,
                      4 => 10.5,
                      3 => 12,
                      _ => 14,
                    } *
                    f,
              ),
            )
          : Icon(
              spec.icon,
              size: 18 * f,
              color: spec.solid ? accountBadgeForeground(accent) : accent,
            ),
    );
  }
}

/// Opens the icon/monogram picker and returns the chosen [FinancialAccount.icon]
/// value: a catalog key, [kMonogramBadgeKey], or `''` for the category default.
/// Returns null if dismissed. [current] is the current stored value.
Future<String?> showAccountBadgePicker(
  BuildContext context, {
  required String current,
  required AccountCategory category,
  required String name,
  required String colorHex,
}) {
  return AppBottomSheet.show<String>(
    context: context,
    title: 'Choose an icon',
    body: SingleChildScrollView(
      child: _BadgePickerBody(
        current: current,
        category: category,
        name: name,
        colorHex: colorHex,
      ),
    ),
  );
}

class _BadgePickerBody extends StatelessWidget {
  final String current;
  final AccountCategory category;
  final String name;
  final String colorHex;

  const _BadgePickerBody({
    required this.current,
    required this.category,
    required this.name,
    required this.colorHex,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    void choose(String value) {
      HapticFeedback.selectionClick();
      Navigator.of(context).pop(value);
    }

    // "Default" is represented by any non-catalog / non-monogram value; we store
    // the category name so it round-trips as the category default.
    final isDefault = !kAccountIconCatalog.containsKey(current) &&
        current != kMonogramBadgeKey;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Special options: Default (category/monogram) + explicit Monogram.
        Row(
          children: [
            Expanded(
              child: _SpecialOption(
                label: accountUsesMonogramByDefault(category)
                    ? 'Default (monogram)'
                    : 'Default (category)',
                selected: isDefault,
                onTap: () => choose(category.name),
                preview: AccountBadge(
                  category: category,
                  name: name,
                  iconKey: category.name,
                  colorHex: colorHex,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SpecialOption(
                label: 'Monogram',
                selected: current == kMonogramBadgeKey,
                onTap: () => choose(kMonogramBadgeKey),
                preview: AccountBadge(
                  category: category,
                  name: name,
                  iconKey: kMonogramBadgeKey,
                  colorHex: colorHex,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        for (final group in kAccountIconGroups) ...[
          Text(
            group.label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: context.appColors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final key in group.keys)
                _IconOption(
                  icon: kAccountIconCatalog[key]!,
                  colorHex: colorHex,
                  selected: current == key,
                  onTap: () => choose(key),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _SpecialOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget preview;

  const _SpecialOption({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.preview,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
          color: selected ? cs.primary.withValues(alpha: 0.06) : null,
        ),
        child: Row(
          children: [
            preview,
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, size: 18, color: cs.primary),
          ],
        ),
      ),
    );
  }
}

class _IconOption extends StatelessWidget {
  final IconData icon;
  final String colorHex;
  final bool selected;
  final VoidCallback onTap;

  const _IconOption({
    required this.icon,
    required this.colorHex,
    required this.selected,
    required this.onTap,
  });

  Color _accent(BuildContext context) {
    try {
      return Color(int.parse('FF${colorHex.replaceFirst('#', '')}', radix: 16));
    } catch (_) {
      return Theme.of(context).colorScheme.tertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = _accent(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? accent : accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(13),
          border: selected ? Border.all(color: cs.primary, width: 2) : null,
        ),
        child: Icon(
          icon,
          size: 24,
          color: selected ? accountBadgeForeground(accent) : accent,
        ),
      ),
    );
  }
}
