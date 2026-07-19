import 'package:flutter/material.dart';

/// A tappable "select" row for the Treasury form kit: shows [value] (or
/// [placeholder] when empty) with a trailing caret. Tapping calls [onTap] — the
/// form owns the picker (typically an `AppActionSheet`) and options, so this
/// widget stays presentational. Wrap in [AppFormField] for the label.
class AppSelectField extends StatelessWidget {
  final String value;
  final String placeholder;
  final VoidCallback? onTap;
  final IconData? leadingIcon;

  const AppSelectField({
    super.key,
    required this.value,
    this.placeholder = 'Select',
    this.onTap,
    this.leadingIcon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final empty = value.trim().isEmpty;
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              if (leadingIcon != null) ...[
                Icon(leadingIcon, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  empty ? placeholder : value,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: empty ? cs.onSurfaceVariant : cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.keyboard_arrow_down_rounded,
                  color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
