import 'package:flutter/material.dart';
import '../../../utils/app_radii.dart';
import '../design/web_breakpoints.dart';

/// Hosts a body (typically a reused mobile edit sheet) inside a centered,
/// width-constrained, scrollable desktop dialog with a titled header + close
/// button. One wrapper for every "sheet-as-dialog" on web (Plan 050 polish).
Future<T?> showWebDialog<T>({
  required BuildContext context,
  required Widget child,
  String? title,
  double maxWidth = 560,
  bool scrollable = true,
}) {
  return showDialog<T>(
    context: context,
    builder: (context) => WebDialog(
        title: title, maxWidth: maxWidth, scrollable: scrollable, child: child),
  );
}

class WebDialog extends StatelessWidget {
  final Widget child;
  final String? title;
  final double maxWidth;

  /// When true (default) the body is wrapped in a scroll view — right for
  /// min-size sheets. Set false for sheets that fill height and manage their
  /// own scroll internally (they'd overflow inside a scroll view).
  final bool scrollable;

  const WebDialog({
    super.key,
    required this.child,
    this.title,
    this.maxWidth = 560,
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final media = MediaQuery.sizeOf(context);

    return Dialog(
      backgroundColor: cs.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.xl),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: media.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    WebInsets.xl, WebInsets.lg, WebInsets.sm, WebInsets.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(title!,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ),
            Flexible(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    WebInsets.xl,
                    title == null ? WebInsets.xl : 0,
                    WebInsets.xl,
                    WebInsets.xl),
                child: scrollable ? SingleChildScrollView(child: child) : child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
