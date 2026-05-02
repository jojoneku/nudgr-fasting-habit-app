import 'package:flutter/material.dart';
import '../../../../utils/app_text_styles.dart';

/// M3 dialog wrapper with title, body widget, and action row.
class AppDialog {
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required Widget body,
    List<Widget> actions = const [],
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: AppTextStyles.titleLarge),
        content: body,
        actions: actions,
      ),
    );
  }
}
