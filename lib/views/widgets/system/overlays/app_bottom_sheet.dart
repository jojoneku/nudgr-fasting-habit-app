import 'package:flutter/material.dart';
import '../../../../utils/app_motion.dart';
import '../../../../utils/app_radii.dart';
import '../../../../utils/app_spacing.dart';
import '../../../../utils/app_text_styles.dart';

/// Standard bottom sheet — drag handle, header, scrollable body, action row.
/// Replaces all ad-hoc showModalBottomSheet calls.
class AppBottomSheet {
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    Widget? trailing,
    required Widget body,
    Widget? primaryAction,
    Widget? secondaryAction,
    bool isScrollControlled = true,
    bool isDismissible = true,
    bool useDraggableScrollableSheet = false,
    double? initialChildSize,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      isDismissible: isDismissible,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
      ),
      transitionAnimationController: AnimationController(
        vsync: Navigator.of(context),
        duration: AppMotion.modal,
      ),
      builder: (ctx) {
        final hasActions = primaryAction != null || secondaryAction != null;
        final content = _AppBottomSheetContent(
          title: title,
          trailing: trailing,
          isDismissible: isDismissible,
          body: body,
          primaryAction: primaryAction,
          secondaryAction: secondaryAction,
          hasActions: hasActions,
        );

        if (useDraggableScrollableSheet) {
          return DraggableScrollableSheet(
            initialChildSize: initialChildSize ?? 0.5,
            minChildSize: 0.3,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, controller) => SingleChildScrollView(
              controller: controller,
              child: content,
            ),
          );
        }
        return content;
      },
    );
  }
}

class _AppBottomSheetContent extends StatelessWidget {
  const _AppBottomSheetContent({
    required this.title,
    this.trailing,
    required this.isDismissible,
    required this.body,
    this.primaryAction,
    this.secondaryAction,
    required this.hasActions,
  });

  final String title;
  final Widget? trailing;
  final bool isDismissible;
  final Widget body;
  final Widget? primaryAction;
  final Widget? secondaryAction;
  final bool hasActions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppSpacing.sm),
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: AppRadii.smBorder,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Text(title, style: AppTextStyles.titleLarge),
                ),
                if (trailing != null) trailing!,
                if (isDismissible)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Body
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: body,
            ),
          ),
          // Actions
          if (hasActions) ...[
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Column(
                children: [
                  if (primaryAction != null) primaryAction!,
                  if (primaryAction != null && secondaryAction != null)
                    const SizedBox(height: AppSpacing.sm),
                  if (secondaryAction != null) secondaryAction!,
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}
