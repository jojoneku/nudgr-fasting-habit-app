import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';

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

/// [InputDecoration] matching the reference field box: filled, bordered,
/// rounded, no floating label (pair with [SheetFieldLabel]). Set [emphasize]
/// for the blue-bordered primary amount field.
InputDecoration sheetFieldDecoration(
  BuildContext context, {
  String? hint,
  String? label,
  Widget? prefix,
  String? prefixText,
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
    // Persistent floating label for controls (dropdowns nested in builders)
    // where a separate [SheetFieldLabel] above isn't structurally convenient.
    labelText: label,
    prefix: prefix,
    prefixText: prefixText,
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
