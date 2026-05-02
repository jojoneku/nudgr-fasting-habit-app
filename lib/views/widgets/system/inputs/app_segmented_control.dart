import 'package:flutter/material.dart';

/// M3 SegmentedButton wrapper with a simpler API.
class AppSegmentedControl<T> extends StatelessWidget {
  const AppSegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.showSelectedIcon = false,
  });

  final List<({T value, String label, IconData? icon})> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool showSelectedIcon;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<T>(
      segments: segments
          .map((s) => ButtonSegment<T>(
                value: s.value,
                label: Text(s.label),
                icon: s.icon != null ? Icon(s.icon) : null,
              ))
          .toList(),
      selected: {selected},
      onSelectionChanged: (set) {
        if (set.isNotEmpty) onChanged(set.first);
      },
      showSelectedIcon: showSelectedIcon,
    );
  }
}
