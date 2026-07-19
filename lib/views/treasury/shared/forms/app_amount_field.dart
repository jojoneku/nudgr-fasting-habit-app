import 'package:flutter/material.dart';
import 'package:intermittent_fasting/utils/amount_input_formatter.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// Large ₱-prefixed numeric input for the Treasury form kit. Wrap in an
/// [AppFormField] for the label. Reuses [AppTextField] + [amountInputFormatters]
/// so parsing/formatting matches every other amount entry in the app.
class AppAmountField extends StatelessWidget {
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final bool enabled;
  final TextInputAction? textInputAction;

  const AppAmountField({
    super.key,
    required this.controller,
    this.validator,
    this.onChanged,
    this.autofocus = false,
    this.enabled = true,
    this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppTextField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      prefix: Text(
        '₱ ',
        style: theme.textTheme.titleMedium
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: amountInputFormatters,
      textInputAction: textInputAction,
      textStyle:
          theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      onChanged: onChanged,
      validator: validator,
    );
  }
}
