import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/views/treasury/shared/account_badge_widget.dart';

/// Shared building blocks for the reference sheet frames
/// (`Nutrition Focus Treasury.dc.html`, Frames 9–20): an uppercase field label
/// above a bordered "field box". Keeps every creation/edit sheet visually
/// consistent with the redesign without changing any form logic.

/// Uppercase label shown directly above a sheet field.
class SheetFieldLabel extends StatelessWidget {
  final String text;
  final EdgeInsetsGeometry padding;

  const SheetFieldLabel(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.only(bottom: 7),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: context.appColors.textMuted,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// A form field with its label rendered on its own line **above** the field box
/// (per the Nudgr reference), instead of Flutter's floating inline `labelText`.
/// Wrap any field (`TextFormField`, `DropdownButtonFormField`, picker box) whose
/// decoration would otherwise carry a `label:`. Works inside a `Column` or an
/// `Expanded`/`Row` cell alike.
class SheetLabeledField extends StatelessWidget {
  final String label;
  final Widget child;

  const SheetLabeledField({
    super.key,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetFieldLabel(label),
        child,
      ],
    );
  }
}

/// [InputDecoration] matching the reference field box: filled, bordered,
/// rounded, no floating label (pair with [SheetFieldLabel]). Set [emphasize]
/// for the blue-bordered primary amount field.
InputDecoration sheetFieldDecoration(
  BuildContext context, {
  String? hint,
  String? helperText,
  String? counterText,
  Widget? prefix,
  String? prefixText,
  String? suffixText,
  Widget? suffixIcon,
  bool emphasize = false,
}) {
  final cs = Theme.of(context).colorScheme;
  final blue = context.appColors.fast;
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c, width: w),
      );
  final idle = emphasize ? blue : cs.outlineVariant.withValues(alpha: 0.6);
  return InputDecoration(
    hintText: hint,
    helperText: helperText,
    counterText: counterText,
    prefix: prefix,
    prefixText: prefixText,
    suffixText: suffixText,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: cs.surfaceContainerHigh,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    enabledBorder: border(idle, emphasize ? 1.5 : 1),
    border: border(idle, emphasize ? 1.5 : 1),
    focusedBorder: border(blue, 1.5),
  );
}

/// A tappable read-only "field box" for custom pickers (date, account) that
/// aren't form fields — label above via [SheetFieldLabel], value + trailing
/// caret/icon inside the reference box.
class SheetPickerBox extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final IconData trailingIcon;
  final bool emphasize;

  const SheetPickerBox({
    super.key,
    required this.child,
    this.onTap,
    this.trailingIcon = Icons.keyboard_arrow_down_rounded,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final blue = context.appColors.fast;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: emphasize ? blue : cs.outlineVariant.withValues(alpha: 0.6),
            width: emphasize ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(child: child),
            Icon(trailingIcon, size: 18, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

// ── Reference sheet kit ──────────────────────────────────────────────────────
// Shared chrome + controls for the redesigned Treasury creation/edit sheets
// (`Nutrition Focus Treasury.dc.html`). Purely presentational; no form logic.

/// The centered grab handle at the top of a bottom sheet.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: cs.outlineVariant,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

/// The bold sheet title (reference "New entry" / "New Installment").
class SheetTitle extends StatelessWidget {
  final String text;
  const SheetTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(
        color: cs.onSurface,
        fontSize: 17,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

/// One segment of a [SheetSegmentedToggle].
class SheetSegment<T> {
  final String label;
  final T value;

  /// Fill color when this segment is selected (e.g. bills-orange vs move-green).
  final Color accent;
  const SheetSegment(
      {required this.label, required this.value, required this.accent});
}

/// A reference-style segmented toggle: a pill container whose selected segment
/// is filled with its [SheetSegment.accent]. Pass a null [onChanged] to render
/// it disabled (e.g. edit mode locked to a kind).
class SheetSegmentedToggle<T> extends StatelessWidget {
  final List<SheetSegment<T>> segments;
  final T value;
  final ValueChanged<T>? onChanged;

  const SheetSegmentedToggle({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final disabled = onChanged == null;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final seg in segments)
            Expanded(
              child: Semantics(
                button: true,
                selected: seg.value == value,
                label: seg.label,
                child: GestureDetector(
                  onTap: disabled || seg.value == value
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          onChanged!(seg.value);
                        },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color:
                          seg.value == value ? seg.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      seg.label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: seg.value == value
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: seg.value == value
                            ? Colors.white
                            : cs.onSurfaceVariant
                                .withValues(alpha: disabled ? 0.5 : 1),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A field box showing an account as a mini [AccountBadge] + name + caret
/// (reference "PAY FROM" / "ACCOUNT" row). Tapping opens [showAccountPicker].
class SheetAccountField extends StatelessWidget {
  final FinancialAccount? account;
  final String placeholder;
  final VoidCallback onTap;

  const SheetAccountField({
    super.key,
    required this.account,
    required this.onTap,
    this.placeholder = 'Select account',
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = account;
    return SheetPickerBox(
      onTap: onTap,
      child: a == null
          ? Text(placeholder,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14))
          : Row(
              children: [
                AccountBadge.of(a, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    a.name,
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

/// Result of [showAccountPicker]. A null future means "dismissed / no change";
/// an [AccountChoice] with a null [id] means the "none" option was chosen.
class AccountChoice {
  final String? id;
  const AccountChoice(this.id);
}

/// A bottom-sheet account list reused by every account field. When [allowNone]
/// is set, a leading [noneLabel] row returns `AccountChoice(null)`.
Future<AccountChoice?> showAccountPicker(
  BuildContext context, {
  required List<FinancialAccount> accounts,
  String? selectedId,
  bool allowNone = false,
  String noneLabel = 'None',
}) {
  final cs = Theme.of(context).colorScheme;
  return showModalBottomSheet<AccountChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetHandle(),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: SheetTitle('Account'),
              ),
              if (allowNone)
                _AccountPickerRow(
                  leading: Icon(Icons.block_rounded,
                      size: 20, color: theme.colorScheme.onSurfaceVariant),
                  label: noneLabel,
                  selected: selectedId == null,
                  onTap: () => Navigator.of(ctx).pop(const AccountChoice(null)),
                ),
              for (final a in accounts)
                _AccountPickerRow(
                  leading: AccountBadge.of(a, size: 28),
                  label: a.name,
                  selected: a.id == selectedId,
                  onTap: () => Navigator.of(ctx).pop(AccountChoice(a.id)),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _AccountPickerRow extends StatelessWidget {
  final Widget leading;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AccountPickerRow({
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
