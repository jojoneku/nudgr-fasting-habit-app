import 'package:flutter/material.dart';
import 'package:intermittent_fasting/utils/amount_input_formatter.dart';

/// Large ₱-prefixed numeric input for the Treasury form kit. Wrap in an
/// [AppFormField] for the label. Built on [TextFormField] (not the plain
/// TextField-based `AppTextField`) so its [validator] participates in an
/// enclosing [Form]; outside a Form it works as a plain input and callers
/// validate manually. Reuses [amountInputFormatters] so parsing/formatting
/// matches every other amount entry.
class AppAmountField extends StatelessWidget {
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final bool enabled;
  final TextInputAction? textInputAction;
  final String? hint;

  const AppAmountField({
    super.key,
    required this.controller,
    this.validator,
    this.onChanged,
    this.autofocus = false,
    this.enabled = true,
    this.textInputAction,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextFormField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: amountInputFormatters,
      textInputAction: textInputAction,
      onChanged: onChanged,
      validator: validator,
      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      decoration: InputDecoration(
        prefixText: '₱ ',
        hintText: hint,
      ),
    );
  }
}
