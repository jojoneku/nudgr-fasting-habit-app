import 'package:flutter/material.dart';
import 'app_list_tile.dart';

enum AppSelectableMode { checkbox, radio, none }

/// Selection tile — checkbox or radio leading slot.
class AppSelectableTile extends StatelessWidget {
  const AppSelectableTile({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.selected,
    required this.onTap,
    this.mode = AppSelectableMode.checkbox,
    this.leading,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final bool selected;
  final VoidCallback onTap;
  final AppSelectableMode mode;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    Widget? selectionWidget;
    switch (mode) {
      case AppSelectableMode.checkbox:
        selectionWidget = IgnorePointer(
          child: Checkbox(value: selected, onChanged: (_) {}),
        );
      case AppSelectableMode.radio:
        selectionWidget = IgnorePointer(
          child: Radio<bool>(value: true, groupValue: selected, onChanged: (_) {}),
        );
      case AppSelectableMode.none:
        selectionWidget = leading;
    }

    return AppListTile(
      leading: mode == AppSelectableMode.none ? leading : selectionWidget,
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      selected: selected,
      onTap: onTap,
    );
  }
}
