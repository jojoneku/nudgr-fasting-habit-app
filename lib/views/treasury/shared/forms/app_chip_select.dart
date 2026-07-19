import 'package:flutter/material.dart';

/// One option in an [AppChipSelect].
class AppChipOption<T> {
  final T value;
  final String label;
  const AppChipOption(this.value, this.label);
}

/// Single-select chip row for finite choices (e.g. installment months, account
/// type, bill type). Wrap in [AppFormField] for the label. Reuses [ChoiceChip]
/// so it inherits the app's chip theme.
class AppChipSelect<T> extends StatelessWidget {
  final List<AppChipOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  const AppChipSelect({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          ChoiceChip(
            label: Text(o.label),
            selected: o.value == selected,
            onSelected: (_) => onChanged(o.value),
          ),
      ],
    );
  }
}
