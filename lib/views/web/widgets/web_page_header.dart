import 'package:flutter/material.dart';

import '../design/web_breakpoints.dart';

/// The page-level header the mobile redesign settled on: a large, tight,
/// left-aligned title that names the screen, with its controls (month picker,
/// primary action) pinned to the right of the same line.
///
/// Distinct from [WebSectionHeader], which titles a group of cards *inside* a
/// page and stays at `headlineSmall`. The mobile screens deliberately give the
/// page title more weight than anything under it — `w800`, negative tracking,
/// nothing competing on its line — and the pre-redesign web pages lost that by
/// reusing the section header at the top and hanging a sentence-long subtitle
/// off it. Keep [subtitle] to a short scope line or omit it.
class WebPageHeader extends StatelessWidget {
  final String title;

  /// Optional one-line scope note (e.g. "3 bills due, 1 to receive").
  final String? subtitle;

  /// Controls for the page — month picker, primary action.
  final Widget? trailing;

  const WebPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: WebInsets.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: WebInsets.xs),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: WebInsets.lg),
            trailing!,
          ],
        ],
      ),
    );
  }
}
